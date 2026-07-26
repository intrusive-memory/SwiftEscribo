import EscriboCore
import Testing

#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

@testable import SwiftEscribo

/// Scaffolding for the coordinator suites.
///
/// Every fixture here drives a **real `NSTextStorage` and a real `EscriboScanner`**. No
/// mock storage, and no hand-built `ScanResult`:
///
/// - DL-12 keeps `LineRecord`'s and `ScanResult`'s initializers internal to `EscriboCore`
///   by design, and a fabricated result could not carry a `LineState` anyway.
/// - A mock text storage would not exercise the thing most likely to be wrong — the
///   `NSTextStorageDelegate` callback's *own* coordinates, which are the whole subject of
///   the translation under test. A mock that reported the range the test already knew
///   would pass whether or not the translation was right.
///
/// ## Why every coordinator suite is `@MainActor`
///
/// Because that is where the thing under test lives. `EditorCoordinator` is synchronous,
/// single-threaded, and main-thread-owned by contract (REQUIREMENTS.md § Concurrency and
/// failure), and `NSTextStorage` is an AppKit/UIKit object. Left unannotated, swift-testing
/// would run these suites across the cooperative pool and exercise the coordinator in a way
/// no Representable ever will — testing a concurrency story the package explicitly does not
/// have. Pinning to the main actor tests it as it is used.
@MainActor
enum CoordinatorFixtures {

  // MARK: - Documents

  /// A Markdown document with a heading, so both output paths — span attributes and
  /// paragraph geometry — have something to disagree about.
  static let document = """
    # Title
    Plain paragraph with no syntax at all.
    Second paragraph, for edits that must not disturb the first.
    """

  /// The UTF-16 offset at which `needle` starts in `text`.
  static func offset(of needle: String, in text: String = document) throws -> Int {
    let found = try #require(text.range(of: needle), "fixture does not contain \(needle)")
    let start = try #require(found.lowerBound.samePosition(in: text.utf16))
    return text.utf16.distance(from: text.utf16.startIndex, to: start)
  }

  // MARK: - Theme

  /// A theme with real span styling **and** real geometry, on two different elements.
  ///
  /// Both halves are needed and neither is decorative: DL-44 is invisible unless a line
  /// has attributes from the span pass *and* a non-default paragraph style, and unless the
  /// two elements' paragraph styles differ from each other.
  static let probeTheme = EscriboTheme(
    name: "coordinator probe",
    baseFontSize: 12,
    base: TokenStyle(foreground: .black, family: .monospaced),
    kindStyles: [
      .heading: TokenStyle(foreground: EscriboColor(red: 0.8, green: 0.1, blue: 0.1)),
      .codeBlock: TokenStyle(foreground: EscriboColor(red: 0, green: 0.4, blue: 0)),
    ],
    elementSizeScales: [.heading: [1: 2.0]],
    elementParagraphMetrics: [
      .heading: [1: ParagraphMetrics(leftIndentChars: 5, spaceBeforeLines: 2)],
      .paragraph: [0: ParagraphMetrics(leftIndentChars: 1, firstLineIndentChars: 2)],
    ],
    markerOpacity: 0.4
  )

  // MARK: - Editors

  /// A text storage with a coordinator attached and the document fully styled.
  static func makeEditor(
    _ text: String = document,
    language: Language = .markdown,
    theme: EscriboTheme = probeTheme
  ) -> (storage: NSTextStorage, coordinator: EditorCoordinator, styler: EscriboStyler) {
    let storage = NSTextStorage(string: text)
    let styler = EscriboStyler(theme: theme)
    let coordinator = EditorCoordinator(
      attachingTo: storage, language: language, styler: styler)
    coordinator.restyleEverything()
    return (storage, coordinator, styler)
  }

  /// The code units `storage` reports through ``UTF16TextSource``.
  static func codeUnits(of storage: NSTextStorage, in range: Range<Int>) -> [UInt16] {
    var out = [UInt16](repeating: 0, count: range.count)
    out.withUnsafeMutableBufferPointer { buffer in
      storage.copyUTF16CodeUnits(in: range, into: buffer)
    }
    return out
  }

  /// Every attribute dictionary in `storage`, one per character, reduced to something
  /// comparable.
  static func attributeSnapshot(_ storage: NSTextStorage) -> [NSDictionary] {
    (0..<storage.length).map {
      StylingFixtures.comparable(storage.attributes(at: $0, effectiveRange: nil))
    }
  }

  /// Asserts that two storages carry character-for-character identical attributes.
  ///
  /// Per character rather than whole-snapshot, so a failure names the offset. "The two
  /// arrays differ" is not a diagnosis when the arrays are hundreds of attribute
  /// dictionaries long.
  static func expectSameAttributes(
    _ actual: NSTextStorage,
    _ expected: NSTextStorage,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    #expect(actual.length == expected.length, sourceLocation: sourceLocation)
    let a = attributeSnapshot(actual)
    let b = attributeSnapshot(expected)
    for index in 0..<min(a.count, b.count) where a[index] != b[index] {
      Issue.record(
        "attributes differ at \(index): \(a[index]) vs \(b[index])",
        sourceLocation: sourceLocation)
      return
    }
  }
}

// MARK: - Edit translation

/// `textStorage(_:didProcessEditing:range:changeInLength:)` reports **new**-text
/// coordinates; ``TextEdit`` is **old**-text coordinates. REQUIREMENTS.md § Edits and text
/// access: mixing the two "silently corrupts offsets" rather than failing, so every case
/// below is asserted against a real `NSTextStorage` mutation rather than against the
/// translation function alone.
@Suite("Coordinator edit translation")
@MainActor
struct EditorCoordinatorEditTranslationTests {

  @Test("A single-character insertion mid-paragraph is an empty range in old coordinates")
  func singleCharacterInsertion() throws {
    let editor = CoordinatorFixtures.makeEditor()
    let at = try CoordinatorFixtures.offset(of: "paragraph with")

    editor.storage.replaceCharacters(in: NSRange(location: at, length: 0), with: "X")

    let edit = try #require(editor.coordinator.lastEdit)
    // The discriminator. In *new* coordinates the edited range is `at..<at+1`, because
    // the inserted character is there now. In old coordinates it is empty, because
    // nothing was replaced.
    #expect(edit.range == at..<at)
    #expect(edit.range.isEmpty)
    #expect(edit.range.upperBound == at)
    #expect(edit.replacementLength == 1)
    // DL-9: the delta is `TextEdit`'s own computed property, never recomputed.
    #expect(edit.changeInLength == 1)
  }

  @Test("Replacing a five-unit selection with one character keeps the five-unit old range")
  func multiCharacterReplacement() throws {
    let editor = CoordinatorFixtures.makeEditor()
    let at = try CoordinatorFixtures.offset(of: "Plain")

    // Select five, type one.
    editor.storage.replaceCharacters(in: NSRange(location: at, length: 5), with: "X")

    let edit = try #require(editor.coordinator.lastEdit)
    #expect(edit.range == at..<(at + 5))
    #expect(edit.range.count == 5)
    #expect(edit.replacementLength == 1)
    #expect(edit.changeInLength == -4)
  }

  @Test("A deletion is a non-empty old range with a zero-length replacement")
  func deletion() throws {
    let editor = CoordinatorFixtures.makeEditor()
    let at = try CoordinatorFixtures.offset(of: " with no syntax")

    editor.storage.replaceCharacters(in: NSRange(location: at, length: 15), with: "")

    let edit = try #require(editor.coordinator.lastEdit)
    #expect(edit.range == at..<(at + 15))
    #expect(edit.replacementLength == 0)
    #expect(edit.changeInLength == -15)
  }

  @Test("The translation matches TextEdit's own worked example, case for case")
  func translationTable() {
    // `"Hello world"` (11 units), from `TextEdit`'s documentation.
    let cases: [(NSRange, Int, TextEdit)] = [
      // Select `world`, type `there`: new range is 6..<11, delta 0.
      (NSRange(location: 6, length: 5), 0, TextEdit(range: 6..<11, replacementLength: 5)),
      // Delete `" world"`: new range is empty at 5, delta -6.
      (NSRange(location: 5, length: 0), -6, TextEdit(range: 5..<11, replacementLength: 0)),
      // Insert `"!"` at the end: new range is 11..<12, delta +1.
      (NSRange(location: 11, length: 1), 1, TextEdit(range: 11..<11, replacementLength: 1)),
      // Type `x` over the whole document: new range is 0..<1, delta -10.
      (NSRange(location: 0, length: 1), -10, TextEdit(range: 0..<11, replacementLength: 1)),
    ]
    for (range, delta, expected) in cases {
      #expect(
        EditorCoordinator.textEdit(editedRange: range, changeInLength: delta) == expected,
        "translation of \(range) by \(delta)")
    }
  }

  @Test("A nonsensical notification clamps rather than trapping")
  func degenerateNotificationsClamp() {
    // A delta larger than the edited range would make the old length negative.
    let overshoot = EditorCoordinator.textEdit(
      editedRange: NSRange(location: 4, length: 1), changeInLength: 9)
    #expect(overshoot.range == 4..<4)
    #expect(overshoot.replacementLength == 1)

    // `NSNotFound` is what the text system reports for "no pending change".
    let none = EditorCoordinator.textEdit(
      editedRange: NSRange(location: 0, length: 0), changeInLength: 0)
    #expect(none.range == 0..<0)
    #expect(none.replacementLength == 0)
  }
}

// MARK: - Marked text

/// REQUIREMENTS.md Architecture §8: "Skip restyling while `hasMarkedText` is true, or CJK
/// input breaks."
@Suite("Coordinator marked-text handling")
@MainActor
struct EditorCoordinatorMarkedTextTests {

  @Test("With marked text active, a storage edit makes zero calls into the styler")
  func markedTextMakesZeroStylerCalls() throws {
    let editor = CoordinatorFixtures.makeEditor()
    let restylesBefore = editor.coordinator.restyleCount

    // Empty the styler completely, so "was it called" is observable three ways: the hit
    // and miss counters, and whether anything at all landed in any of its caches. The
    // last one covers the paragraph-geometry path, which the counters do not.
    editor.styler.invalidate()
    editor.styler.resetStatistics()
    #expect(editor.styler.isCacheEmpty)

    editor.coordinator.hasMarkedText = { true }
    let at = try CoordinatorFixtures.offset(of: "Plain")
    editor.storage.replaceCharacters(in: NSRange(location: at, length: 0), with: "\u{3042}")

    #expect(editor.styler.cacheHits == 0)
    #expect(editor.styler.cacheMisses == 0)
    #expect(editor.styler.isCacheEmpty)
    #expect(editor.coordinator.restyleCount == restylesBefore)
    #expect(editor.coordinator.markedTextSkipCount == 1)

    // Non-vacuity: the same edit with no composition in flight does reach the styler.
    editor.coordinator.hasMarkedText = { false }
    editor.storage.replaceCharacters(in: NSRange(location: at, length: 0), with: "Z")
    #expect(editor.styler.cacheHits + editor.styler.cacheMisses > 0)
    #expect(editor.coordinator.restyleCount > restylesBefore)
  }

  @Test("The edit is still translated while a composition is in flight")
  func markedTextStillTranslates() throws {
    let editor = CoordinatorFixtures.makeEditor()
    editor.coordinator.hasMarkedText = { true }
    let at = try CoordinatorFixtures.offset(of: "Second")

    editor.storage.replaceCharacters(in: NSRange(location: at, length: 6), with: "\u{3042}")

    let edit = try #require(editor.coordinator.lastEdit)
    #expect(edit.range == at..<(at + 6))
    #expect(edit.replacementLength == 1)
  }

  @Test("Edits dropped during a composition are recovered by a full rescan afterwards")
  func compositionIsRecoveredByFullRescan() throws {
    let editor = CoordinatorFixtures.makeEditor()
    let at = try CoordinatorFixtures.offset(of: "Plain")

    // ASCII composition text, deliberately. A real IME composes CJK, and the two suites
    // above use it — but this test compares *whole attribute dictionaries* against a
    // reference editor, and the text system's own `fixAttributesInRange:` substitutes a
    // fallback face for characters the theme's font cannot render. Whether that
    // substitution has run yet depends on how deeply the restyle was nested inside
    // `processEditing`, which differs between "restyled from a delegate callback" and
    // "restyled directly" — so a CJK fixture would make this assert the text system's
    // font-fixing schedule rather than the coordinator's recovery.
    editor.coordinator.hasMarkedText = { true }
    editor.storage.replaceCharacters(in: NSRange(location: at, length: 0), with: "n")
    editor.storage.replaceCharacters(in: NSRange(location: at, length: 1), with: "ni")
    #expect(editor.coordinator.markedTextSkipCount == 2)

    // Composition committed; the next real edit is the first moment the document is
    // stable enough to scan, and the scanner's line index is stale by two edits.
    editor.coordinator.hasMarkedText = { false }
    editor.storage.replaceCharacters(in: NSRange(location: at + 2, length: 0), with: "!")

    // The recovery is a *full* scan: the applied range is the whole document.
    #expect(editor.coordinator.lastAppliedRange == 0..<editor.storage.length)

    // And the result is character for character what a fresh editor over the same text
    // produces — which it could not be if the stale line index had survived.
    let reference = CoordinatorFixtures.makeEditor(editor.storage.string)
    CoordinatorFixtures.expectSameAttributes(editor.storage, reference.storage)
  }
}

// MARK: - Attribute application

/// REQUIREMENTS.md Architecture §8: `beginEditing()` / `setAttributes(_:range:)` /
/// `endEditing()` over the rescanned range only, and never a wholesale replacement of the
/// attributed string.
@Suite("Coordinator attribute application")
@MainActor
struct EditorCoordinatorApplicationTests {

  /// The composed-result test DL-44 demands.
  ///
  /// `setAttributes(_:range:)` **replaces** the attribute dictionary for a range. Sortie 8
  /// produces paragraph styles separately from span attributes, so a coordinator that set
  /// geometry first and span attributes second would drop every paragraph style — the
  /// document would render exactly as if the geometry layer were switched off, and no
  /// other test in this package would fail. This is the one that would.
  @Test("A styled line carries both its span attributes and its paragraph style")
  func spanAttributesAndParagraphStyleSurviveTogether() throws {
    let editor = CoordinatorFixtures.makeEditor()

    let headingContent = try CoordinatorFixtures.offset(of: "Title")
    let bodyContent = try CoordinatorFixtures.offset(of: "Plain")

    let headingAttributes = editor.storage.attributes(at: headingContent, effectiveRange: nil)
    let bodyAttributes = editor.storage.attributes(at: bodyContent, effectiveRange: nil)

    // The span pass survived: font and foreground are present, and the heading's are the
    // heading's — not the body's.
    let headingFont = try #require(headingAttributes[.font] as? PlatformFont)
    let bodyFont = try #require(bodyAttributes[.font] as? PlatformFont)
    #expect(headingAttributes[.foregroundColor] != nil)
    #expect(bodyAttributes[.foregroundColor] != nil)
    // The probe theme scales `.heading` at depth 1 by 2.0 over a 12 pt base.
    #expect(headingFont.pointSize > bodyFont.pointSize)

    // The paragraph pass survived, on the same characters, with the right geometry.
    let headingParagraph = try #require(
      headingAttributes[.paragraphStyle] as? NSParagraphStyle)
    let bodyParagraph = try #require(bodyAttributes[.paragraphStyle] as? NSParagraphStyle)
    #expect(headingParagraph.isEqual(editor.styler.paragraphStyle(element: .heading, depth: 1)))
    #expect(bodyParagraph.isEqual(editor.styler.paragraphStyle(element: .paragraph, depth: 0)))

    // Non-vacuous three ways: neither is the text system's default, and they differ from
    // each other, so "both lines got some paragraph style" cannot pass by accident.
    #expect(!headingParagraph.isEqual(NSParagraphStyle.default))
    #expect(!bodyParagraph.isEqual(NSParagraphStyle.default))
    #expect(!headingParagraph.isEqual(bodyParagraph))
  }

  @Test("A line's paragraph style covers its terminator, not just its content")
  func paragraphStyleCoversTheTerminator() throws {
    let editor = CoordinatorFixtures.makeEditor()

    // The newline that ends `# Title`. `LineRecord.range` includes it, and paragraph
    // attributes are applied per paragraph by the layout system — a style that stopped
    // short of the terminator would leave the newline carrying the previous paragraph's
    // geometry, which is a real layout bug and an invisible one in any test that only
    // probes content.
    let terminator = try CoordinatorFixtures.offset(of: "\n")
    let attributes = editor.storage.attributes(at: terminator, effectiveRange: nil)
    let paragraph = try #require(attributes[.paragraphStyle] as? NSParagraphStyle)

    #expect(paragraph.isEqual(editor.styler.paragraphStyle(element: .heading, depth: 1)))
    #expect(!paragraph.isEqual(editor.styler.paragraphStyle(element: .paragraph, depth: 0)))
    // And the span pass reached it too — the terminator is inside the tiled dirty range.
    #expect(attributes[.font] != nil)
  }

  @Test("Marker spans are dimmed but keep the line's size and geometry")
  func markersAreDimmedNotResized() throws {
    let editor = CoordinatorFixtures.makeEditor()
    let markerAttributes = editor.storage.attributes(at: 0, effectiveRange: nil)
    let contentAttributes = editor.storage.attributes(
      at: try CoordinatorFixtures.offset(of: "Title"), effectiveRange: nil)

    let markerFont = try #require(markerAttributes[.font] as? PlatformFont)
    let contentFont = try #require(contentAttributes[.font] as? PlatformFont)
    // Architecture §3: alpha only. Resizing a marker makes text jitter while typing.
    #expect(markerFont.pointSize == contentFont.pointSize)

    let markerParagraph = try #require(markerAttributes[.paragraphStyle] as? NSParagraphStyle)
    #expect(markerParagraph.isEqual(editor.styler.paragraphStyle(element: .heading, depth: 1)))
  }

  @Test("An incremental restyle touches only the rescanned range")
  func incrementalRestyleTouchesOnlyTheDirtyRange() throws {
    let editor = CoordinatorFixtures.makeEditor()

    // A sentinel the coordinator has no reason to write and no way to reproduce. If the
    // restyle reached this character, `setAttributes` replaced the whole dictionary and
    // the sentinel is gone.
    let sentinelKey = NSAttributedString.Key("com.intrusive-memory.escribo.test.sentinel")
    editor.storage.addAttribute(sentinelKey, value: "kept", range: NSRange(location: 0, length: 1))

    let at = try CoordinatorFixtures.offset(of: "Second")
    editor.storage.replaceCharacters(in: NSRange(location: at, length: 0), with: "X")

    let applied = try #require(editor.coordinator.lastAppliedRange)
    #expect(!applied.contains(0))
    #expect(applied.count < editor.storage.length)
    #expect(
      editor.storage.attributes(at: 0, effectiveRange: nil)[sentinelKey] as? String == "kept")
  }

  @Test("Applying attributes does not re-enter the scan path")
  func attributeApplicationDoesNotReenter() throws {
    let editor = CoordinatorFixtures.makeEditor()
    let before = editor.coordinator.restyleCount

    let at = try CoordinatorFixtures.offset(of: "Plain")
    editor.storage.replaceCharacters(in: NSRange(location: at, length: 0), with: "X")

    // Exactly one restyle. The attribute pass reports `.editedAttributes`, which the
    // bridge filters, and the coordinator's own guard covers the case where it does not.
    #expect(editor.coordinator.restyleCount == before + 1)
  }

  @Test("Styling after an incremental edit equals styling after a full scan")
  func incrementalStylingEqualsFullStyling() throws {
    let editor = CoordinatorFixtures.makeEditor()

    // A sequence that moves both outputs: a word inside a paragraph, then a `#` that
    // reclassifies a whole line from paragraph to heading.
    let word = try CoordinatorFixtures.offset(of: "no syntax")
    editor.storage.replaceCharacters(in: NSRange(location: word, length: 0), with: "very ")
    let secondLine = try CoordinatorFixtures.offset(of: "Second")
    editor.storage.replaceCharacters(in: NSRange(location: secondLine, length: 0), with: "## ")

    let reference = CoordinatorFixtures.makeEditor(editor.storage.string)
    CoordinatorFixtures.expectSameAttributes(editor.storage, reference.storage)
  }
}

// MARK: - Ownership

@Suite("Coordinator ownership")
@MainActor
struct EditorCoordinatorOwnershipTests {

  @Test("Attaching installs the coordinator as the storage's delegate")
  func attachInstallsDelegate() {
    let editor = CoordinatorFixtures.makeEditor()
    #expect(editor.storage.delegate === editor.coordinator)
  }

  /// DL-28: `EscriboScanner.language` is a `let`, and every line's cached state is a claim
  /// about a grammar. A language switch is a new scanner and a full scan, never a mutation.
  @Test("Switching language builds a new scanner and restyles everything")
  func languageSwitchIsAFullRescan() throws {
    let editor = CoordinatorFixtures.makeEditor()
    #expect(editor.coordinator.language == .markdown)
    let before = editor.coordinator.restyleCount

    editor.coordinator.setLanguage(.fountain)
    #expect(editor.coordinator.language == .fountain)
    #expect(editor.coordinator.restyleCount == before + 1)
    #expect(editor.coordinator.lastAppliedRange == 0..<editor.storage.length)

    // Fountain has no grammar until Sortie 13 and degrades to plain text, so `# Title`
    // stops being a heading and becomes an ordinary paragraph. Its geometry changing to
    // the paragraph element's is the observable proof that the scanner was replaced
    // rather than reused — a reused scanner would have kept the line's heading state.
    let firstLine = editor.storage.attributes(at: 0, effectiveRange: nil)
    let paragraph = try #require(firstLine[.paragraphStyle] as? NSParagraphStyle)
    #expect(paragraph.isEqual(editor.styler.paragraphStyle(element: .paragraph, depth: 0)))
    #expect(!paragraph.isEqual(editor.styler.paragraphStyle(element: .heading, depth: 1)))
  }

  @Test("Setting the same language is a no-op")
  func sameLanguageIsANoOp() {
    let editor = CoordinatorFixtures.makeEditor()
    let before = editor.coordinator.restyleCount
    editor.coordinator.setLanguage(.markdown)
    #expect(editor.coordinator.restyleCount == before)
  }

  @Test("Edits after a language switch scan under the new grammar")
  func editsAfterLanguageSwitchAreIncremental() throws {
    let editor = CoordinatorFixtures.makeEditor()
    editor.coordinator.setLanguage(.fountain)

    let at = try CoordinatorFixtures.offset(of: "Plain")
    editor.storage.replaceCharacters(in: NSRange(location: at, length: 0), with: "X")

    let reference = CoordinatorFixtures.makeEditor(editor.storage.string, language: .fountain)
    CoordinatorFixtures.expectSameAttributes(editor.storage, reference.storage)
  }
}

// MARK: - The UTF-16 seam

/// REQUIREMENTS.md § Edits and text access: "The scanner **must not require the document
/// as a Swift `String` per edit.**"
@Suite("NSTextStorage as a UTF-16 text source")
@MainActor
struct TextStorageTextSourceTests {

  @Test("Length is reported in UTF-16 code units, matching the text system's own count")
  func lengthIsUTF16() {
    for text in ["", "plain", "caf\u{00E9}", "a\u{1F600}b", "line\r\nline"] {
      let storage = NSTextStorage(string: text)
      #expect(storage.utf16Count == storage.length)
      #expect(storage.utf16Count == text.utf16.count)
    }
  }

  @Test("Bulk reads return exactly the document's code units, astral planes included")
  func bulkReadsMatchTheDocument() {
    // An emoji is two code units and a CRLF is two code units; both are the classic ways
    // an offset drifts between the scanner and the text system.
    let text = "# Caf\u{00E9} \u{1F600}\r\nsecond \u{1F1FA}\u{1F1F8} line"
    let storage = NSTextStorage(string: text)
    let expected = Array(text.utf16)

    #expect(CoordinatorFixtures.codeUnits(of: storage, in: 0..<storage.length) == expected)

    // Every sub-run, so a read that ignored `range.lowerBound` could not pass.
    for lower in 0..<storage.length {
      for upper in lower...storage.length {
        #expect(
          CoordinatorFixtures.codeUnits(of: storage, in: lower..<upper)
            == Array(expected[lower..<upper]),
          "read of \(lower)..<\(upper)")
      }
    }
  }

  @Test("An empty read writes nothing and does not require a buffer")
  func emptyReadsAreSafe() {
    let storage = NSTextStorage(string: "text")
    var scratch = [UInt16](repeating: 0xFFFF, count: 4)
    scratch.withUnsafeMutableBufferPointer { buffer in
      storage.copyUTF16CodeUnits(in: 2..<2, into: UnsafeMutableBufferPointer(rebasing: buffer[0..<0]))
    }
    #expect(scratch == [0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF])
  }

  @Test("The storage reads correctly after a mutation, with no stale snapshot")
  func readsFollowMutations() {
    let storage = NSTextStorage(string: "hello")
    storage.replaceCharacters(in: NSRange(location: 5, length: 0), with: " world")
    #expect(storage.utf16Count == 11)
    #expect(
      CoordinatorFixtures.codeUnits(of: storage, in: 0..<11) == Array("hello world".utf16))
  }
}
