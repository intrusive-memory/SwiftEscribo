// Deliberately NOT `@testable`. This file is the only one in the target that sees
// `EscriboCore` the way a consumer does, which is what makes it able to assert
// anything about the *public* surface at all. Adding `@testable` here would silently
// delete every assertion in it.
import EscriboCore
import Testing

/// Accepts any `Sendable` type. Passing a metatype is a compile-time proof that the
/// type is publicly visible and publicly `Sendable`, and needs no instance — which
/// matters for a type that cannot be constructed from here.
private func requireSendableType<T: Sendable>(_ type: T.Type) -> String {
  String(describing: type)
}

/// Accepts any `Equatable` type. Passing a metatype proves the *conformance* is public,
/// not merely that the type is.
private func requireEquatableType<T: Equatable>(_ type: T.Type) -> String {
  String(describing: type)
}

/// A text source declared **outside** `EscriboCore`, which is the whole point of it.
///
/// `SwiftEscribo` conforms `NSTextStorage` to ``UTF16TextSource`` in Sortie 9, across a
/// module boundary. That is impossible unless the protocol and both of its requirements
/// are `public`, and this type is the compile-time proof that they are — it is written
/// against exactly what ships, with no `@testable` to paper over an `internal`.
private struct ExternalTextSource: UTF16TextSource {
  let units: [UInt16]

  var utf16Count: Int { units.count }

  func copyUTF16CodeUnits(in range: Range<Int>, into buffer: UnsafeMutableBufferPointer<UInt16>) {
    var out = 0
    for offset in range {
      buffer[out] = units[offset]
      out += 1
    }
  }
}

/// `LineState` is public but opaque, and opacity is only real if something checks it
/// from outside. This suite is that check: it imports `EscriboCore` without
/// `@testable`, so every line here compiles against exactly what ships.
///
/// The negative half — that no public member is reachable — cannot be asserted by
/// running code, because the failure mode is code that *compiles*. It is asserted
/// instead by the commented lines below: each is a construction or an access that must
/// fail to compile from this file. Uncomment one and the build breaks; if one ever
/// stops breaking the build, the opacity guarantee has been lost and Sortie 30's API
/// audit has a real regression to find.
@Suite("Public surface (no @testable import)")
struct PublicSurfaceTests {

  // MARK: - LineState is comparable but nothing else

  @Test("LineState is publicly visible, publicly Equatable, and publicly Sendable")
  func lineStateIsPubliclyComparable() {
    // Sortie 4's convergence engine compares `startState == previousValue`, and a
    // consumer holding two `LineRecord` values has to be able to make the same
    // comparison. That is the entire public contract of the type, and these two calls
    // are its compile-time proof — no instance required, because from out here no
    // instance can be made.
    #expect(requireEquatableType(LineState.self) == "LineState")
    #expect(requireSendableType(LineState.self) == "LineState")
  }

  @Test("LineState exposes no public initializer, properties, or cases")
  func lineStateIsOpaque() {
    // Every line in this comment block must fail to compile if pasted into this file.
    // They are the specification of the opacity, stated where a reader of the public
    // API will look for it:
    //
    //   _ = LineState()                    // no public initializer
    //   _ = LineState.documentStart        // no public static member
    //   _ = someState.isInFence            // no public property, now or ever
    //
    // Exposing any of them would freeze the scanner's internals at 1.0 and make every
    // convergence improvement a breaking change. What runs here is only the positive
    // half; the negative half is enforced by the compiler on the lines above.
    #expect(requireEquatableType(LineState.self) == "LineState")
  }

  // MARK: - What a consumer can construct

  @Test("A consumer can construct the types it is expected to produce")
  func consumerConstructibleTypes() {
    // `EscriboSpan` and `TextEdit` are inputs a consumer legitimately makes: a host app
    // describes an edit it performed, and tests and tools build spans. Both have public
    // initializers, and this is where that stays true.
    let span = EscriboSpan(range: 0..<5, kind: .heading, style: [.strong], role: .marker)
    #expect(span.range == 0..<5)
    #expect(span.kind == .heading)
    #expect(span.style == [.strong])
    #expect(span.role == .marker)

    let edit = TextEdit(range: 6..<11, replacementLength: 5)
    #expect(edit.range == 6..<11)
    #expect(edit.replacementLength == 5)
    #expect(edit.changeInLength == 0)
  }

  @Test("A consumer cannot fabricate scanner output")
  func scannerOutputIsNotConsumerConstructible() {
    // `LineRecord` and `ScanResult` are scanner *output*. Their initializers are
    // internal, which falls out of `LineState`'s opacity rather than being a separate
    // decision: a caller could not supply a `startState` even if the memberwise
    // initializer were public. These must fail to compile from this file:
    //
    //   _ = LineRecord(index: 0, range: 0..<1, contentRange: 0..<0,
    //                  element: .blank, startState: ???, depth: 0)
    //   _ = ScanResult(dirtyRange: 0..<0, spans: [], lines: 0..<1, lineRecords: [])
    //
    // The types themselves stay public and readable, because a consumer receives them.
    #expect(requireSendableType(LineRecord.self) == "LineRecord")
    #expect(requireSendableType(ScanResult.self) == "ScanResult")
    #expect(requireEquatableType(LineRecord.self) == "LineRecord")
    #expect(requireEquatableType(ScanResult.self) == "ScanResult")
  }

  // MARK: - The rest of the 1.0 vocabulary

  @Test("The 1.0 vocabulary types are public and publicly constructible")
  func vocabularyIsPublic() {
    // REQUIREMENTS.md § What is public in 1.0 lists these by name. A consumer with a
    // newer core and an older theme has to be able to name an unrecognized kind
    // without the compiler's help, which is why the raw-value initializers are public.
    #expect(SpanKind(rawValue: "text") == .text)
    #expect(ElementKind(rawValue: "blank") == .blank)
    #expect(Language(rawValue: "fountain") == .fountain)
    #expect(StyleSet(rawValue: 1) == .strong)
    #expect(SpanRole(rawValue: "marker") == .marker)
  }

  // MARK: - The one thing SwiftEscribo must be able to conform

  @Test("A type outside EscriboCore can conform to UTF16TextSource and be read through")
  func textSourceIsPubliclyConformable() {
    // `LineIndex` itself stays `internal` — REQUIREMENTS.md § What is public in 1.0 does
    // not list it and nothing outside the core needs to name it. The *source* protocol
    // is the exception, and this test is its justification: without it Sortie 9 cannot
    // hand the scanner an `NSTextStorage`, and the scanner would be back to bridging
    // 120 KB to a Swift `String` on every keystroke.
    let source = ExternalTextSource(units: Array("a\r\nb".utf16))
    #expect(source.utf16Count == 4)

    var destination = [UInt16](repeating: 0, count: 4)
    destination.withUnsafeMutableBufferPointer {
      source.copyUTF16CodeUnits(in: 1..<3, into: $0)
    }
    #expect(destination[0] == 0x0D)
    #expect(destination[1] == 0x0A)

    // `String` satisfies the same protocol, from inside the module.
    #expect("a\r\nb".utf16Count == 4)
  }

  // MARK: - Every member of the record types a consumer receives

  /// Sortie 30. The suite above proves the *types* cross the module boundary; this proves
  /// every **member** of them does, which is a different claim and the one the audit is
  /// actually about. A property demoted to `internal` by mistake is invisible to a
  /// `@testable` suite and to every other test in this target — this method is where it
  /// stops compiling.
  ///
  /// Read rather than merely named: each value is asserted against a number computed by
  /// hand from the source below, so a member that survived the audit but started returning
  /// something else is caught here too.
  @Test("Every public member of LineRecord, ScanResult, and EscriboSpan is readable from outside")
  func recordMembersAreReadable() {
    var scanner = EscriboScanner(language: .markdown)
    //          0123456789
    // line 0:  "# Title"   + \n   → offsets  0..<8
    // line 1:  "a | b"     + \n   → offsets  8..<14
    // line 2:  "|:-|-:|"   + \n   → offsets 14..<22
    // line 3:  ""                 → offset  22..<22
    let text = "# Title\na | b\n|:-|-:|\n"
    let result = scanner.fullScan(text)

    // ScanResult: all four members.
    #expect(result.dirtyRange == 0..<22)
    #expect(result.lines == 0..<4)
    #expect(result.lineRecords.count == 4)
    #expect(!result.spans.isEmpty)

    // LineRecord: index, range, contentRange, element, depth, startState, tableAlignments.
    let heading = result.lineRecords[0]
    #expect(heading.index == 0)
    #expect(heading.range == 0..<8)
    #expect(heading.contentRange == 2..<7, "content excludes the `# ` marker and the newline")
    #expect(heading.element == .heading)
    #expect(heading.depth == 1)
    #expect(heading.tableAlignments.isEmpty)

    // `startState` is readable — it is a public stored property — and comparing two of them
    // is the only thing a consumer can do with one. Asserted across *two independent scans*
    // rather than against itself, so the comparison is a real one: scanning the same text
    // twice must yield equal states line for line, and a state that hashed an address or a
    // scan sequence number would fail here while passing `x == x`.
    var again = EscriboScanner(language: .markdown)
    let second = again.fullScan(text)
    #expect(second.lineRecords.map(\.startState) == result.lineRecords.map(\.startState))
    #expect(heading.startState == second.lineRecords[0].startState)
    // …and the delimiter row does *not* begin in the same state as the heading, so equality
    // is discriminating rather than degenerate.
    #expect(heading.startState != result.lineRecords[2].startState)

    // `tableAlignments` is the reason ``TableAlignment`` is public at all: it is a stored
    // property of a public struct, so its type is forced public with it. Reaching a value
    // of that type from out here is the proof the forcing is real rather than assumed.
    let delimiter = result.lineRecords[2]
    #expect(delimiter.element == .tableDelimiterRow)
    #expect(delimiter.tableAlignments == [.left, .right])
    #expect(delimiter.tableAlignments[0].rawValue == 1)
    #expect(TableAlignment(rawValue: 3) == .center)
    #expect(TableAlignment.unspecified != TableAlignment.left)

    // EscriboSpan: the memberwise initializer's defaults are public API too — a consumer
    // that has to spell `style:` and `role:` at every call site has a different API than
    // the one that shipped.
    let defaulted = EscriboSpan(range: 0..<1, kind: .text)
    #expect(defaulted.style == [])
    #expect(defaulted.role == .content)
  }
}

/// The canonical writer, exercised the way a consumer sees it — which is the only way it
/// *can* be exercised for the 1.0 audit.
///
/// REQUIREMENTS.md § What is public in 1.0 names "the writer" alongside the scanner entry
/// points, and until Sortie 30 every one of its ~90 tests lived behind `@testable import`.
/// Those tests would have stayed green with `FountainWriter` demoted to `internal`, so the
/// package had no assertion at all that its second shipping entry point was reachable.
///
/// ## Why this is not the writer's test suite
///
/// `FountainWriterTests` and `FountainWriterTitlePageTests` own the writer's behaviour and
/// are far more thorough. This is a *reachability* test with teeth: the assertions are byte
/// comparisons chosen so that neither an identity writer (`return source`) nor an empty one
/// (`return ""`) can satisfy them, because a reachability test that only checked
/// `write(...)` compiled would be exactly the vacuous criterion this mission keeps finding.
@Suite("Public writer entry point (no @testable import)")
struct PublicWriterTests {

  @Test("A consumer can scan a document and write it back out through the public API")
  func writerIsPubliclyReachable() {
    // Every line here is deliberately non-canonical, so a writer that returned its input
    // unchanged fails on the first assertion:
    //   `#   ACT ONE` → `# ACT ONE`   (section marker, one space)
    //   `=====`       → `===`         (page break, exactly three)
    //   `BOB   ^`     → `BOB ^`       (dual-dialogue caret, one space)
    let source = "INT. HOUSE - DAY\n\n#   ACT ONE\n\n=====\n\nBOB   ^\nHello.\n"

    var scanner = EscriboScanner(language: .fountain)
    let result = scanner.fullScan(source)
    let written = FountainWriter().write(result.lineRecords, from: source)

    #expect(written == "INT. HOUSE - DAY\n\n# ACT ONE\n\n===\n\nBOB ^\nHello.\n")
    #expect(written != source, "an identity writer would pass every reachability check")
    #expect(!written.isEmpty)

    // Writing is idempotent: the canonical form of a canonical document is itself. A
    // writer that normalized on a schedule rather than to a fixed point would pass the
    // assertion above and fail this one.
    var second = EscriboScanner(language: .fountain)
    let reWritten = FountainWriter().write(second.fullScan(written).lineRecords, from: written)
    #expect(reWritten == written)

    // A subrange is a legal argument and writes that subrange — the documented contract,
    // and the one thing about the signature a consumer cannot discover by trying it on a
    // whole document.
    let firstLineOnly = FountainWriter().write(Array(result.lineRecords.prefix(1)), from: source)
    #expect(firstLineOnly == "INT. HOUSE - DAY\n")

    // A `UTF16TextSource` that is not a `String` reaches the same generic parameter, which
    // is what `SwiftEscribo` does with an `NSTextStorage` on every save.
    let external = ExternalWriterSource(units: Array(source.utf16))
    #expect(FountainWriter().write(result.lineRecords, from: external) == written)
  }

  @Test("The writer is total on a record set it was not given the matching grammar for")
  func writerIsTotalOnForeignRecords() {
    // REQUIREMENTS.md § Unknown kinds fall back, never fail. Markdown records handed to
    // the Fountain writer come back verbatim rather than throwing or trapping, and a
    // consumer must be able to rely on that from outside the module.
    let source = "# Heading\n\n- item\n"
    var scanner = EscriboScanner(language: .markdown)
    let result = scanner.fullScan(source)
    #expect(FountainWriter().write(result.lineRecords, from: source) == source)

    // …and on nothing at all.
    #expect(FountainWriter().write([], from: source).isEmpty)
  }
}

/// A non-`String`, non-`NSTextStorage` conformer, declared out here so the writer's generic
/// parameter is exercised across the module boundary rather than only by `String`.
private struct ExternalWriterSource: UTF16TextSource {
  let units: [UInt16]

  var utf16Count: Int { units.count }

  func copyUTF16CodeUnits(in range: Range<Int>, into buffer: UnsafeMutableBufferPointer<UInt16>) {
    var out = 0
    for offset in range {
      buffer[out] = units[offset]
      out += 1
    }
  }
}

/// The public scanner entry point, exercised the way a consumer sees it.
///
/// Also **not** `@testable`, and that is the whole assertion: `EscriboScanner` has to be
/// usable from out here with no grammar type in sight, while `LineGrammar`,
/// `IncrementalScanner`, `LineIndex`, and `LineState`'s initializer stay unreachable.
/// REQUIREMENTS.md § What is public in 1.0 lists "the scanner entry points"; this suite
/// is the proof that the listed thing exists and that the price of it was not the
/// opacity of `LineState`.
@Suite("Public scanner entry point (no @testable import)")
struct PublicScannerTests {

  @Test("A consumer can full-scan and incrementally scan a Markdown document")
  func markdownScanningIsPubliclyReachable() {
    // Nothing internal is named anywhere in this method. That is the point of it: a
    // caller names a `Language`, and `EscriboCore` owns the grammar behind it.
    var scanner = EscriboScanner(language: .markdown)
    #expect(scanner.language == .markdown)

    let text = "# Title\nprose\n```swift\nlet x = 1\n```\n"
    let full = scanner.fullScan(text)
    // The always-on harness reaches here too. `ScanInvariants` is written against the
    // public surface for exactly this reason: the facade's output has to satisfy the same
    // contract as the engine's, and asserting that must not cost this file its
    // `@testable`-free status.
    ScanInvariants.check(full, text: text, editedRange: nil, "facade full scan")
    #expect(full.dirtyRange == 0..<text.utf16.count)
    #expect(full.spans.reduce(0) { $0 + $1.range.count } == text.utf16.count)
    #expect(full.lineRecords.first?.element == .heading)
    #expect(full.lineRecords.first?.depth == 1)
    #expect(full.spans.first?.kind == .heading)
    #expect(full.spans.first?.role == .marker)
    #expect(full.spans.contains { $0.kind == .codeInfoString })

    // And the incremental half, in old-text coordinates.
    let edited = "## Title\nprose\n```swift\nlet x = 1\n```\n"
    let result = scanner.incrementalScan(TextEdit(range: 0..<1, replacementLength: 2), in: edited)
    ScanInvariants.check(result, text: edited, editedRange: 0..<2, "facade incremental scan")
    #expect(result.dirtyRange.lowerBound == 0)
    #expect(result.lineRecords.first?.depth == 2)
    #expect(result.spans.first?.range == 0..<3)

    // Consecutive spans on the dirty range are contiguous — the tiling guarantee holds
    // through the facade, which is the only place a consumer ever sees it.
    var cursor = result.dirtyRange.lowerBound
    for span in result.spans {
      #expect(span.range.lowerBound == cursor)
      cursor = span.range.upperBound
    }
    #expect(cursor == result.dirtyRange.upperBound)
  }

  @Test("`Language.fountain` reaches the Fountain grammar through the public facade")
  func fountainScansThroughTheFacade() {
    // Sortie 13 gave `.fountain` a grammar, and this is the only place in the suite that
    // proves the *public* entry point dispatches to it: `FountainGrammar` is internal, so
    // a test that names the type cannot tell whether `EscriboScanner(language: .fountain)`
    // ever reaches it. Naming the resulting `ElementKind`s can.
    //
    // `BOB` is a character cue and `Hello.` is dialogue, which also proves the facade
    // reaches a grammar that declares a **lookahead**: `BOB` is ALL-CAPS either way, and
    // only the line under it makes it a cue.
    var scanner = EscriboScanner(language: .fountain)
    let text = "INT. HOUSE - DAY\n\nBOB\nHello.\n"
    let result = scanner.fullScan(text)
    ScanInvariants.check(result, text: text, editedRange: nil, "fountain full scan")

    #expect(result.dirtyRange == 0..<text.utf16.count)
    #expect(result.spans.reduce(0) { $0 + $1.range.count } == text.utf16.count)
    #expect(
      result.lineRecords.map(\.element) == [.sceneHeading, .blank, .character, .dialogue, .blank])
    #expect(result.spans.first?.kind == .sceneHeading)
    #expect(result.spans.first?.range == 0..<16)

    // Editing it is total too.
    let edited = "INT. HOUSE - NIGHT\n\nBOB\nHello.\n"
    let after = scanner.incrementalScan(TextEdit(range: 13..<16, replacementLength: 5), in: edited)
    ScanInvariants.check(after, text: edited, editedRange: 13..<18, "fountain edit")
    #expect(after.dirtyRange.upperBound <= edited.utf16.count)
    #expect(after.lineRecords.first?.element == .sceneHeading)
  }

  @Test("A language this version has never heard of scans as text rather than trapping")
  func unknownLanguageDegrades() {
    // `Language` is a struct with static members precisely so a consumer can name one
    // the linked core does not implement. Dispatch has to stay total for that to be a
    // feature rather than a crash.
    var scanner = EscriboScanner(language: Language(rawValue: "org.example.notALanguage"))
    let text = "# not a heading here\n"
    let result = scanner.fullScan(text)
    ScanInvariants.check(result, text: text, editedRange: nil, "unknown language")
    #expect(result.spans.allSatisfy { $0.kind == .text })
    #expect(result.lineRecords.first?.element == .paragraph)
  }

  @Test("An out-of-range edit through the facade is clamped, not trapped")
  func facadeIsTotalOnBadInput() {
    var scanner = EscriboScanner(language: .markdown)
    ScanInvariants.check(scanner.fullScan("hello"), text: "hello", editedRange: nil, "clamp base")
    let result = scanner.incrementalScan(
      TextEdit(range: 900..<9000, replacementLength: 3), in: "hello world")
    // No `editedRange`: the edit was deliberately nonsense and has no meaningful extent
    // in the new text, which is the one case the harness's containment check must skip.
    ScanInvariants.check(result, text: "hello world", editedRange: nil, "clamped facade edit")
    #expect(result.dirtyRange.upperBound <= "hello world".utf16.count)
    #expect(result.lineRecords.count == 1)
  }

  @Test("Scanning through the facade requires naming nothing internal")
  func scannerInternalsAreUnreachable() {
    // The negative half of the contract cannot be asserted by running code — the failure
    // mode is code that *compiles*. It is asserted by these lines, each of which must
    // fail to compile if pasted into this file:
    //
    //   struct MyGrammar: LineGrammar { }          // no public grammar protocol
    //   _ = IncrementalScanner(grammar: ...)       // no public generic scanner
    //   _ = LineIndex("text")                      // no public line index
    //   _ = LineState()                            // no public LineState initializer
    //   _ = MarkdownGrammar()                      // grammars are not public either
    //
    // Every one of them is reachable from a `@testable` file in this same target, which
    // is what makes the difference observable rather than theoretical: if any of the
    // five ever compiles from *here*, `LineState` has stopped being opaque and the
    // scanner's internals are frozen at 1.0.
    //
    // What runs is the positive half — the facade is a public, non-generic type that
    // needs none of them. It is deliberately **not** `Sendable`: it carries mutable scan
    // state and REQUIREMENTS.md § Concurrency and failure makes the scanner synchronous
    // and single-threaded, so one lives beside the text storage it reads and never
    // crosses an isolation boundary.
    #expect(String(describing: EscriboScanner.self) == "EscriboScanner")
    var scanner = EscriboScanner(language: .markdown)
    let result = scanner.fullScan("")
    ScanInvariants.check(result, text: "", editedRange: nil, "empty document through the facade")
    #expect(result.lineRecords.count == 1)
  }
}
