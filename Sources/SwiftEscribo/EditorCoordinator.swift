import EscriboCore
import Foundation

/// The editor's engine room: it owns the scanner, owns the styler, translates text-system
/// edits into ``TextEdit`` values, and writes the resulting attributes back.
///
/// Both Representables — `NSTextView` on macOS, `UITextView` on iOS — drive **this same
/// type**, not two parallel ones. REQUIREMENTS.md Architecture §10 makes that structural
/// rather than aspirational: "The coordinator, styler, and geometry layer are
/// platform-neutral… A coordinator shaped around AppKit does not retrofit to UIKit
/// cheaply."
///
/// ## How this file stays platform-neutral
///
/// It imports Foundation and `EscriboCore`, and nothing else. Every type that appears in
/// its API is from one of those two. The three things a real editor needs that *are*
/// platform-specific are each handled without naming a UI framework:
///
/// | Need | AppKit | UIKit | How it enters here |
/// |---|---|---|---|
/// | The document | `NSTextStorage` (AppKit) | `NSTextStorage` (UIKit) | ``EditorTextStorage``, whose members are all `NSMutableAttributedString`'s and therefore Foundation's |
/// | "Is an IME composition in flight?" | `hasMarkedText()` | `markedTextRange != nil` | ``hasMarkedText``, a closure the view supplies |
/// | The edit notification | `NSTextStorageDelegate` | `NSTextStorageDelegate` | ``didProcessCharacterEdit(editedRange:changeInLength:)``, called by the bridge |
///
/// The middle row is the one that decides whether the seam retrofits. AppKit spells the
/// question as a **method** on `NSTextInputClient`; UIKit spells it as a **property** on
/// `UITextInput`. No protocol requirement can be satisfied by both directly, so a
/// coordinator that declared one would have forced an adapter type on whichever platform
/// lost the coin toss — and, in practice, would have been written with `hasMarkedText()`
/// in it because macOS is built first. A closure is satisfied by a one-line binding on
/// either platform and by a literal in a test.
///
/// ## Threading
///
/// Synchronous, single-threaded, and **not** `Sendable` — deliberately, and for the same
/// reason ``EscriboScanner`` and ``EscriboStyler`` are not (REQUIREMENTS.md § Concurrency
/// and failure). Own one per document on the main thread, beside the text storage it
/// reads. It is not `@MainActor`-isolated because `NSTextStorageDelegate` is not, and
/// bridging the two would mean a `MainActor.assumeIsolated` — a *trap* — on the hot path
/// of a text-view callback, which is precisely the failure mode this package refuses
/// everywhere else.
///
/// ## Lifecycle
///
/// ```swift
/// let coordinator = EditorCoordinator(textStorage: storage, language: .markdown, theme: theme)
/// coordinator.hasMarkedText = { [weak view] in view?.hasMarkedText() ?? false }  // macOS
/// coordinator.attach(to: storage)     // installs the delegate
/// coordinator.restyleEverything()     // first full scan
/// ```
///
/// After that the coordinator is driven entirely by the text system.
final class EditorCoordinator: NSObject {

  // MARK: - Owned state

  /// The document, read as UTF-16 by the scanner and written as attributes by the styler.
  ///
  /// One reference for both directions. The scanner never sees a Swift `String` of the
  /// document — REQUIREMENTS.md § Edits and text access: bridging 120 KB per keystroke
  /// "would exceed the whole budget before scanning began."
  let textStorage: any EditorTextStorage

  /// The scanner, one per document.
  ///
  /// `private(set)` and replaced wholesale by ``setLanguage(_:)`` rather than mutated:
  /// DL-28 — `EscriboScanner.language` is a `let`, because every line's cached state is
  /// meaningless under a different grammar.
  private(set) var scanner: EscriboScanner

  /// The style cache, one per document and shared across every span of every scan.
  ///
  /// A `final class` on purpose (Sortie 7): it *is* the cache, and a per-lookup copy
  /// would defeat it. Hosts change appearance, theme, mode, and font metrics by assigning
  /// `styler.environment`, which runs the one invalidation path and nothing else.
  let styler: EscriboStyler

  // MARK: - The platform seam

  /// Whether the text view currently has an active marked-text (IME) composition.
  ///
  /// **Restyling is skipped entirely while this answers `true`** — REQUIREMENTS.md
  /// Architecture §8: "Skip restyling while `hasMarkedText` is true, or CJK input
  /// breaks." Reapplying attributes underneath a composition tears down the marked-text
  /// underline and, on some input methods, cancels the composition outright.
  ///
  /// Bound by the Representable, and spelled as a closure because the two platforms spell
  /// the question incompatibly:
  ///
  /// ```swift
  /// coordinator.hasMarkedText = { [weak view] in view?.hasMarkedText() ?? false }   // macOS
  /// coordinator.hasMarkedText = { [weak view] in view?.markedTextRange != nil }     // iOS
  /// ```
  ///
  /// Defaults to "no composition", so an unattached coordinator — or a test — behaves as
  /// if the user were typing Latin text.
  var hasMarkedText: () -> Bool = { false }

  // MARK: - Instrumentation

  /// The most recent edit, as translated into old-text coordinates.
  ///
  /// Recorded even when the restyle is skipped for marked text, because the translation
  /// is what is under test and it happens either way.
  private(set) var lastEdit: TextEdit?

  /// The range whose attributes were most recently reapplied — the last scan's
  /// `dirtyRange`, clamped to the document.
  private(set) var lastAppliedRange: Range<Int>?

  /// How many times attributes have been applied.
  private(set) var restyleCount = 0

  /// How many edits have been skipped because a composition was in flight.
  private(set) var markedTextSkipCount = 0

  /// The line records the most recent scan produced, in order.
  ///
  /// ## Why records are retained when spans are not
  ///
  /// REQUIREMENTS.md § Spans is explicit that spans "are produced for a requested range on
  /// demand and are **not** retained for the whole document" — they exist to become
  /// character attributes and are worthless the moment they have. Line records are the other
  /// output of the same pass and answer a different question, "what *is* this line," which
  /// an editing affordance has to ask between scans rather than during one.
  ///
  /// Sortie 25's list continuation is the first caller. It has to know whether the caret's
  /// line is a list item — and, just as importantly, whether it is a YAML frontmatter entry
  /// or the inside of a code fence that merely looks like one (DL-108). Re-deriving that
  /// lexically would put a second, disagreeing copy of the grammar beside the editor; asking
  /// the scanner for it is free, because the scan already happened.
  ///
  /// Bounded by the last scan, which is a handful of lines per keystroke and the whole
  /// document exactly once per full scan. That last case is a real cost — on the order of a
  /// few hundred kilobytes for a 120 KB screenplay — paid on attach, language switch, and
  /// external reset, and never on the typing path.
  private(set) var lastLineRecords: [LineRecord] = []

  // MARK: - Private state

  /// Set while ``apply(_:)`` is writing, so the attribute edits it causes cannot re-enter
  /// ``didProcessCharacterEdit(editedRange:changeInLength:)`` and rescan the document
  /// from inside its own restyle.
  ///
  /// Belt and braces: the bridge already filters to `.editedCharacters`, and an attribute
  /// pass reports `.editedAttributes`. This makes the guarantee local to the coordinator
  /// so it does not depend on a filter in another file staying correct.
  private var isApplying = false

  /// Set when an edit was dropped on the floor for marked text.
  ///
  /// The scanner's line index now describes a document that no longer exists, and no
  /// sequence of incremental edits can recover it, because the edits it missed were never
  /// recorded. The next edit that arrives with no composition in flight therefore
  /// **full-scans** instead. This is why the Representables need no "composition ended"
  /// callback: the recovery is driven by the next real edit, which is the first moment
  /// the document is stable enough to scan anyway.
  private var needsFullRescan = false

  // MARK: - Creation

  /// Creates a coordinator over `textStorage`.
  ///
  /// - Parameters:
  ///   - textStorage: The document. Not retained by the text system on the coordinator's
  ///     behalf — the caller owns the lifetime.
  ///   - language: The grammar to scan with. Change it later with ``setLanguage(_:)``.
  ///   - styler: The style cache. Pass the same one for the lifetime of the document.
  ///
  /// Does **not** scan. Call ``restyleEverything()`` once the storage has its initial
  /// contents; scanning an empty storage that is about to be filled is wasted work, and
  /// the scanner's "assume empty until told otherwise" contract makes it harmless to
  /// defer.
  init(textStorage: any EditorTextStorage, language: Language, styler: EscriboStyler) {
    self.textStorage = textStorage
    self.scanner = EscriboScanner(language: language)
    self.styler = styler
    super.init()
  }

  /// Creates a coordinator with a styler built over `theme`.
  convenience init(
    textStorage: any EditorTextStorage, language: Language, theme: EscriboTheme
  ) {
    self.init(
      textStorage: textStorage, language: language, styler: EscriboStyler(theme: theme))
  }

  // MARK: - Language

  /// The grammar the document is currently scanned with.
  var language: Language { scanner.language }

  /// Switches grammars and restyles the whole document.
  ///
  /// DL-28: a new ``EscriboScanner`` and a full scan, never a mutation of the existing
  /// one. `EscriboScanner.language` is a `let` precisely so this cannot be got wrong —
  /// every line's `startState` is a claim about a grammar, and reusing them across a
  /// switch would misclassify exactly the multi-line constructs the state exists for.
  ///
  /// A no-op when the language is unchanged, so a host may push its configuration on
  /// every layout pass without throwing away the document's styling.
  func setLanguage(_ language: Language) {
    guard language != scanner.language else { return }
    scanner = EscriboScanner(language: language)
    restyleEverything()
  }

  // MARK: - Scanning

  /// Scans the whole document and reapplies every attribute.
  ///
  /// The entry point for the three events that invalidate everything: the first attach,
  /// a language switch, and an external replacement of the text (Sortie 12). Also the
  /// recovery path after a composition, which is why it clears ``needsFullRescan``.
  func restyleEverything() {
    needsFullRescan = false
    apply(textStorage.fullScan(using: &scanner))
  }

  /// Handles one **character** edit reported by the text system.
  ///
  /// Called by the `NSTextStorageDelegate` bridge, which has already filtered out
  /// attribute-only edits. Kept platform-neutral by taking the two values the callback
  /// carries rather than the callback's own types: `NSRange` and `Int` are Foundation,
  /// `NSTextStorage.EditActions` is not.
  ///
  /// - Parameters:
  ///   - editedRange: The edited range in **new**-text coordinates, exactly as the text
  ///     system reports it.
  ///   - changeInLength: How much the document grew or shrank.
  func didProcessCharacterEdit(editedRange: NSRange, changeInLength: Int) {
    guard !isApplying else { return }

    let edit = Self.textEdit(editedRange: editedRange, changeInLength: changeInLength)
    lastEdit = edit

    // Architecture §8. Nothing below this line runs during a composition — not the scan,
    // and above all not the styler.
    guard !hasMarkedText() else {
      markedTextSkipCount += 1
      needsFullRescan = true
      return
    }

    guard !needsFullRescan else {
      restyleEverything()
      return
    }

    apply(textStorage.incrementalScan(edit, using: &scanner))
  }

  /// Translates a text-system edit notification into a ``TextEdit``.
  ///
  /// `textStorage(_:didProcessEditing:range:changeInLength:)` reports `editedRange` in
  /// **new**-text coordinates; ``TextEdit`` is in **old**-text coordinates. The location
  /// needs no adjustment — an edit does not move its own start — but the length does:
  ///
  /// ```
  /// oldLength = editedRange.length - changeInLength
  /// ```
  ///
  /// That subtraction is the one that gets forgotten, which is why this is a static
  /// function with no dependencies rather than four lines inlined into the callback.
  ///
  /// Total: a nonsensical notification (negative location, a `changeInLength` larger than
  /// the range) is clamped to a well-formed edit rather than trapping. `EscriboScanner`
  /// clamps stale edits itself, so a clamped edit degrades to a larger rescan and never
  /// to a crash inside a delegate callback.
  static func textEdit(editedRange: NSRange, changeInLength: Int) -> TextEdit {
    let location = max(0, editedRange.location)
    let newLength = max(0, editedRange.length)
    let oldLength = max(0, newLength - changeInLength)
    return TextEdit(
      range: location..<(location + oldLength), replacementLength: newLength)
  }

  // MARK: - Attribute application

  /// Writes `result` to the text storage: span attributes, then paragraph geometry.
  ///
  /// ## Never replace the attributed string wholesale
  ///
  /// REQUIREMENTS.md Architecture §8 forbids the whole-string assignment outright: it
  /// "destroys selection, undo stack, and marked text." The permitted shape is
  /// `beginEditing()` / `setAttributes(_:range:)` / `endEditing()` over the rescanned
  /// range only, and ``EditorTextStorage`` is narrow enough that this function could not
  /// express the forbidden call even if it wanted to.
  ///
  /// ## DL-44 — why the paragraph pass comes second, and additively
  ///
  /// `setAttributes(_:range:)` **replaces** the whole dictionary for a range. Sortie 8
  /// produces geometry separately from span attributes: `paragraphStyleRuns(for:)`
  /// returns `(range, NSParagraphStyle)` pairs and `attributes(for:on:)` carries no
  /// paragraph style at all. Setting the paragraph styles first and then setting span
  /// attributes over them would drop every one of them — silently, with the document
  /// rendering exactly as if the geometry layer were switched off, and with no test
  /// failing unless one asserts the *composed* result.
  ///
  /// So the order is: span attributes with `setAttributes`, then paragraph styles with
  /// `addAttribute(.paragraphStyle:)`, which merges. The runs cover each line's **full
  /// `LineRecord.range`, terminator included** — a paragraph style that stopped short of
  /// its terminator would leave the newline carrying the previous paragraph's geometry,
  /// and `NSParagraphStyle` is applied per paragraph by the layout system, so the
  /// terminator is the character that decides.
  ///
  /// ## Spell checking survives this
  ///
  /// Deliberately. Misspelling underlines are *temporary* attributes on the layout
  /// manager, not text-storage attributes, so `setAttributes` never sees them
  /// (REQUIREMENTS.md § Text-system hygiene).
  private func apply(_ result: ScanResult) {
    let limit = textStorage.length
    restyleCount += 1
    lastAppliedRange = Self.clamped(result.dirtyRange, to: limit) ?? (0..<0)
    lastLineRecords = result.lineRecords

    isApplying = true
    textStorage.beginEditing()
    defer {
      textStorage.endEditing()
      isApplying = false
    }

    // Pass 1 — character attributes, one `setAttributes` per span.
    //
    // The line record a span sits on is found by walking both sorted sequences with a
    // single cursor: spans exactly tile `dirtyRange` and line records exactly tile the
    // same lines, so this is linear rather than a search per span. Point size comes from
    // the *line* (Sortie 7), which is the whole reason the record is needed here at all.
    if !result.lineRecords.isEmpty {
      var cursor = result.lineRecords.startIndex
      let lastRecord = result.lineRecords.index(before: result.lineRecords.endIndex)
      for span in result.spans {
        while cursor < lastRecord,
          result.lineRecords[cursor].range.upperBound <= span.range.lowerBound
        {
          cursor += 1
        }
        guard let range = Self.clamped(span.range, to: limit) else { continue }
        textStorage.setAttributes(
          styler.attributes(for: span, on: result.lineRecords[cursor]),
          range: Self.nsRange(range))
      }
    }

    // Pass 2 — paragraph geometry, additively, over each line's full range. DL-44.
    for run in styler.paragraphStyleRuns(for: result.lineRecords) {
      guard let range = Self.clamped(run.range, to: limit) else { continue }
      textStorage.addAttribute(
        .paragraphStyle, value: run.style, range: Self.nsRange(range))
    }
  }

  // MARK: - Asking the scanner about a line

  /// How the scanner classified the line containing `offset`, or `nil` if it cannot say.
  ///
  /// The seam an editing affordance uses to ask "what is this line?" without re-deriving the
  /// grammar beside the editor. A `- item` inside YAML frontmatter is YAML; inside a fenced
  /// code block it is code; inside a `fountain` fence it is Fountain. All three answers come
  /// out of this one call, and none of them needed a rule at the call site (DL-108).
  ///
  /// ## The miss path is a full scan, and that is the right cost
  ///
  /// ``lastLineRecords`` holds the last scan's window, so the common case — the writer typed
  /// on this line and then pressed Return — is a hit with no work at all. A miss means the
  /// caret is somewhere the last scan did not cover, which happens when the writer clicks
  /// elsewhere and presses Return without typing first. Rather than guess, or answer from a
  /// stale index, that path full-scans and asks again.
  ///
  /// A full scan is the cold-scan budget (REQUIREMENTS.md § Performance budget: 50 ms
  /// ceiling, 10 ms target for 120 KB) paid on a single Return keystroke, not on the typing
  /// path, and not per character. The alternative — a document-wide record cache the
  /// coordinator maintains across every edit — buys a rare keystroke some milliseconds in
  /// exchange for an invalidation rule on the hot path, which is the wrong trade and the
  /// usual source of "the affordance fired on stale state" bugs.
  ///
  /// - Returns: `nil` when the document has never been scanned, or when `offset` lies
  ///   outside it. A caller that gets `nil` must do the boring thing.
  func elementKind(atUTF16Offset offset: Int) -> ElementKind? {
    if let record = Self.record(containing: offset, in: lastLineRecords) {
      return record.element
    }
    restyleEverything()
    return Self.record(containing: offset, in: lastLineRecords)?.element
  }

  /// The record whose line contains `offset`, by binary search.
  ///
  /// Records tile the lines they cover in order and their ranges include terminators, so a
  /// search for the **last** record starting at or before `offset` lands on the right line
  /// for every offset inside the covered window.
  ///
  /// Two boundary cases decide the comparisons, and both are real:
  ///
  /// - `offset` may equal a record's `upperBound`. The final line of a document that ends
  ///   without a terminator has an offset one past its last character where the caret
  ///   legitimately sits, and an empty final line after a trailing terminator has an *empty*
  ///   range. `<=` admits both; `<` would answer `nil` for a caret at the end of the
  ///   document, which is where a writer presses Return most often.
  /// - `records` may be an incremental window rather than the whole document. An offset
  ///   before the window finds nothing; one after it lands on the last record and fails the
  ///   `upperBound` check. Both answer `nil`, which is the honest answer — this window
  ///   cannot classify that line.
  static func record(containing offset: Int, in records: [LineRecord]) -> LineRecord? {
    var low = records.startIndex
    var high = records.endIndex - 1
    var found = -1
    while low <= high {
      let middle = low + (high - low) / 2
      if records[middle].range.lowerBound <= offset {
        found = middle
        low = middle + 1
      } else {
        high = middle - 1
      }
    }
    guard found >= 0 else { return nil }
    let record = records[found]
    return offset <= record.range.upperBound ? record : nil
  }

  // MARK: - Range arithmetic

  /// `range` confined to `0..<limit`, or `nil` if nothing of it survives.
  ///
  /// The scanner's invariants already guarantee ranges inside the document, and the
  /// invariant harness enforces them. This exists anyway because the cost of being wrong
  /// is an `NSRangeException` raised inside a text-view delegate — an uncatchable crash
  /// in the host app, from a scanner bug that a clamp would have rendered as slightly
  /// wrong styling.
  private static func clamped(_ range: Range<Int>, to limit: Int) -> Range<Int>? {
    let lower = min(max(0, range.lowerBound), limit)
    let upper = min(max(lower, range.upperBound), limit)
    return lower < upper ? lower..<upper : nil
  }

  /// A `Range<Int>` of UTF-16 offsets as the text system's `NSRange`.
  ///
  /// Free, by Architecture §4: token ranges are UTF-16 code-unit offsets precisely so
  /// this conversion is arithmetic and not a `String.Index` walk.
  private static func nsRange(_ range: Range<Int>) -> NSRange {
    NSRange(location: range.lowerBound, length: range.count)
  }
}
