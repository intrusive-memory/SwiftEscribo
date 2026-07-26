import Testing

@testable import EscriboCore

/// A document the scanner sweeps edits over.
///
/// ASCII on purpose, for the same reason `LineIndexIncrementalTests` gives: the sweep
/// splices arbitrary UTF-16 ranges, and splicing through a surrogate pair would produce
/// a string the *test* corrupted rather than one the scanner mishandled. Astral-plane
/// handling is asserted structurally instead, in `spanBoundariesNeverSplitASurrogatePair`.
struct ScanCorpusDocument: Sendable, CustomTestStringConvertible {
  let name: String
  let text: String

  var testDescription: String { name }
}

let scanCorpus: [ScanCorpusDocument] = [
  ScanCorpusDocument(name: "empty", text: ""),
  ScanCorpusDocument(name: "single line", text: "alpha"),
  ScanCorpusDocument(name: "plain lines", text: "one\ntwo\nthree"),
  ScanCorpusDocument(name: "mixed terminators", text: "AAA\nbbb\r\nCCC\rddd"),
  ScanCorpusDocument(name: "open and closed fence", text: "a\n~~~swift\ncode\n~~~\nb"),
  ScanCorpusDocument(name: "unterminated fence", text: "a\n~~~\ncode\nmore"),
  ScanCorpusDocument(name: "cue shapes", text: "BOB\nHello.\n\nJANE\n\nACTION"),
  ScanCorpusDocument(name: "trailing terminator", text: "one\ntwo\n"),
]

/// Splices spanning every terminator convention plus the two adversarial ones — a bare
/// `\r` that may pair forward, and a `\n\r` that may pair backward.
let scanReplacements: [String] = ["", "x", "\n", "\r\n", "~~~", "BOB\n", "\n\r"]

@Suite("Incremental scanner — convergence engine")
struct IncrementalScannerTests {

  // MARK: - Forwarders onto the shared harness
  //
  // The invariant block was written out longhand here by Sortie 4, when no shared harness
  // existed to agree on. Sortie 6 built one — `ScanInvariants` — and these two names now
  // forward to it so that there is exactly ONE executable statement of the contract in
  // the target. Two copies of an invariant list is one copy that will be edited and one
  // that will not.

  /// Every offset a line may start or end at. See ``ScanInvariants/lineBoundaries(of:)``.
  static func lineBoundaries(of text: String) -> Set<Int> {
    ScanInvariants.lineBoundaries(of: text)
  }

  /// Splices `replacement` over `range` (UTF-16 code units) of `text`.
  static func splice(_ text: String, _ range: Range<Int>, _ replacement: String) -> String {
    ScanInvariants.splice(text, range, replacement)
  }

  /// Asserts every ``ScanResult`` invariant against `text`.
  static func expectInvariants(
    _ result: ScanResult,
    text: String,
    editedRange: Range<Int>?,
    _ context: @autoclosure () -> String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    ScanInvariants.check(
      result, text: text, editedRange: editedRange, context(), sourceLocation: sourceLocation)
  }

  /// Runs one edit through an incremental scanner and a full scan of the same new text,
  /// asserts every invariant on both, and asserts they agree everywhere they overlap.
  @discardableResult
  static func expectIncrementalMatchesFull<G: LineGrammar>(
    _ grammar: G,
    from old: String,
    replacing range: Range<Int>,
    with replacement: String
  ) -> ScanResult {
    let new = splice(old, range, replacement)
    let edit = TextEdit(range: range, replacementLength: replacement.utf16.count)
    let editedRange = range.lowerBound..<(range.lowerBound + replacement.utf16.count)
    let note =
      "grammar=\(G.self) old=\(old.debugDescription) new=\(new.debugDescription) edit=\(range)"

    var incremental = IncrementalScanner(grammar: grammar)
    let baseline = incremental.fullScan(old)
    let result = incremental.incrementalScan(edit, in: new)

    var fresh = IncrementalScanner(grammar: grammar)
    let full = fresh.fullScan(new)

    expectInvariants(result, text: new, editedRange: editedRange, note)
    expectInvariants(full, text: new, editedRange: nil, note)

    // The gate, one layer above `LineIndex`'s: an incremental scan must be
    // indistinguishable from a full scan wherever it claims to have scanned. Reported
    // through `expectSameElements` so a mismatch names the first divergent index instead
    // of printing two span arrays at each other.
    ScanInvariants.expectSameElements(
      incremental.startStates, fresh.startStates, "startStates", note)
    ScanInvariants.expectSameElements(
      result.lineRecords, full.lineRecords.filter { result.lines.contains($0.index) },
      "lineRecords", note)
    ScanInvariants.expectSameElements(
      result.spans,
      full.spans.filter {
        $0.range.lowerBound >= result.dirtyRange.lowerBound
          && $0.range.upperBound <= result.dirtyRange.upperBound
      },
      "spans", note)

    // And the other half of the gate: not "is what you repainted right" but "did you
    // repaint everything that changed". A window-slice comparison cannot fail when the
    // window is too SMALL, because the lines wrongly left alone are outside it. See
    // `ScanInvariants.PaintedDocument`.
    var painted = ScanInvariants.PaintedDocument(baseline)
    painted.apply(result, newLineCount: ScanInvariants.lineCount(of: new))
    ScanInvariants.expectSameElements(
      painted.lines, ScanInvariants.paintedLines(of: full), "painted document", note)

    return result
  }

  // MARK: - Full scan

  @Test("A full scan tiles the whole document and emits one record per line", arguments: scanCorpus)
  func fullScanTilesTheDocument(document: ScanCorpusDocument) {
    let length = document.text.utf16.count
    for grammar in [AnyTestGrammar.plain, .fence, .cue(1), .hostile] {
      let result = grammar.fullScan(document.text)
      Self.expectInvariants(result, text: document.text, editedRange: 0..<length, "full \(grammar)")
      #expect(result.dirtyRange == 0..<length)
      #expect(result.lines.lowerBound == 0)
      #expect(result.spans.reduce(0) { $0 + $1.range.count } == length, "total tiling \(grammar)")
      #expect(result.lineRecords.count == result.lines.count)
      // Strictly increasing, gapless indices starting at zero.
      #expect(result.lineRecords.map(\.index) == Array(result.lines))
    }
  }

  @Test("An empty document is one line, one record, and no spans")
  func emptyDocument() {
    var scanner = IncrementalScanner(grammar: PlainTextGrammar())
    let result = scanner.fullScan("")
    Self.expectInvariants(result, text: "", editedRange: nil, "empty document")
    #expect(result.dirtyRange == 0..<0)
    #expect(result.spans.isEmpty)
    #expect(result.lines == 0..<1)
    #expect(result.lineRecords.count == 1)
    #expect(result.lineRecords[0].range == 0..<0)
  }

  // MARK: - The sweep
  //
  // Thousands of distinct edits per grammar, which is what the exit criteria's "≥ 20"
  // is a floor for. Every one of them asserts line alignment at both ends, containment
  // of the edited range, exact span tiling, and gapless line records.

  @Test(
    "Every edit in the corpus yields a line-aligned dirty range that contains it",
    arguments: scanCorpus)
  func dirtyRangeInvariantsAcrossTheCorpus(document: ScanCorpusDocument) {
    let length = document.text.utf16.count
    for start in 0...length {
      for deleted in 0...min(2, length - start) {
        for replacement in scanReplacements {
          let range = start..<(start + deleted)
          Self.expectIncrementalMatchesFull(
            PlainTextGrammar(), from: document.text, replacing: range, with: replacement)
          Self.expectIncrementalMatchesFull(
            FenceGrammar(), from: document.text, replacing: range, with: replacement)
          Self.expectIncrementalMatchesFull(
            CueGrammar(lookahead: 1), from: document.text, replacing: range, with: replacement)
        }
      }
    }
  }

  @Test("A whole-document replacement rescans from scratch and stays total", arguments: scanCorpus)
  func wholeDocumentReplacement(document: ScanCorpusDocument) {
    for replacement in scanReplacements {
      Self.expectIncrementalMatchesFull(
        FenceGrammar(), from: document.text, replacing: 0..<document.text.utf16.count,
        with: replacement)
    }
  }

  @Test("A sequence of edits tracks a full scan throughout")
  func editSequence() {
    // Drift shows up when a scanner is carried across many edits without being rebuilt,
    // which is exactly how a live editor uses one. Fixed script, no randomness — a
    // seeded generator is Sortie 6's, and an unseeded one is nobody's.
    let script: [(Range<Int>, String)] = [
      (0..<0, "BOB\n"),
      (4..<4, "Hello.\n"),
      (11..<11, "~~~\n"),
      (15..<15, "let x = 1\n"),
      (25..<25, "~~~\n"),
      (4..<11, ""),  // delete the dialogue line, retroactively un-cueing BOB
      (0..<0, "~~~\n"),  // open a fence at the top: everything below re-scans
      (0..<4, ""),  // and close it again by deletion
    ]

    var text = ""
    var incremental = IncrementalScanner(grammar: FenceGrammar())
    Self.expectInvariants(incremental.fullScan(text), text: text, editedRange: nil, "sequence base")

    for (range, replacement) in script {
      let next = Self.splice(text, range, replacement)
      let result = incremental.incrementalScan(
        TextEdit(range: range, replacementLength: replacement.utf16.count), in: next)
      Self.expectInvariants(
        result, text: next,
        editedRange: range.lowerBound..<(range.lowerBound + replacement.utf16.count),
        "sequence at \(next.debugDescription)")

      var fresh = IncrementalScanner(grammar: FenceGrammar())
      Self.expectInvariants(
        fresh.fullScan(next), text: next, editedRange: nil,
        "sequence full scan at \(next.debugDescription)")
      ScanInvariants.expectSameElements(
        incremental.startStates, fresh.startStates, "startStates",
        "sequence at \(next.debugDescription)")
      text = next
    }
  }

  // MARK: - Backward widening

  @Test("Rescanning starts at least one line before the first edited line")
  func backwardWideningReachesThePrecedingLine() {
    // The rule that nothing about the edit points at: the edit is on line 3, and line 2
    // is rescanned because a grammar can classify a line by what follows it. This is
    // NOT `LineIndex`'s CRLF rule, which is a code-unit argument about terminators.
    let text = "aaa\nbbb\nCCC\nddd\neee"
    var scanner = IncrementalScanner(grammar: CueGrammar(lookahead: 1))
    Self.expectInvariants(scanner.fullScan(text), text: text, editedRange: nil, "widening base")
    let edited = "aaa\nbbb\nCCC\n\neee"
    let result = scanner.incrementalScan(TextEdit(range: 12..<15, replacementLength: 0), in: edited)
    Self.expectInvariants(result, text: edited, editedRange: 12..<12, "widening")

    #expect(result.lines.lowerBound == 2, "did not widen back to the line above the edit")
    // And the point of widening: `CCC` was a cue while `ddd` followed it, and stops
    // being one the moment the following line goes blank. An engine that started at the
    // edited line would leave it painted as a cue.
    #expect(result.lineRecords.first?.element == .paragraph)
    #expect(result.lineRecords.first?.index == 2)
  }

  @Test("A grammar declaring two lines of backward extent gets two lines of backward extent")
  func backwardWideningFollowsTheDeclaredExtent() {
    let text = "aaa\nbbb\nCCC\nddd\neee\nfff"
    for lookahead in 0...2 {
      var scanner = IncrementalScanner(grammar: CueGrammar(lookahead: lookahead))
      Self.expectInvariants(
        scanner.fullScan(text), text: text, editedRange: nil, "extent base \(lookahead)")
      let edited = Self.splice(text, 12..<12, "X")
      let result = scanner.incrementalScan(
        TextEdit(range: 12..<12, replacementLength: 1), in: edited)
      Self.expectInvariants(result, text: edited, editedRange: 12..<13, "extent \(lookahead)")
      // Edit lands on line 3; the extent is `max(1, lookahead)`.
      #expect(result.lines.lowerBound == 3 - max(1, lookahead), "lookahead \(lookahead)")
    }
  }

  // MARK: - Forward convergence and the declared lookahead

  @Test("The rescan stops `lookahead` lines past convergence, not at it")
  func forwardConvergenceHonoursTheDeclaredLookahead() {
    // `CueGrammar`'s state is uniform, so the state-equality condition is satisfied at
    // EVERY boundary — including the one before the edited line. What decides where the
    // rescan stops is therefore entirely the other two conditions: the edit being behind
    // us (which fixes convergence at line 4, one past the edited line 3) and the
    // declared lookahead (which extends the window that many lines further).
    //
    // The expected window is exact and arithmetic, which is what makes it able to fail:
    //   start = 3 - max(1, lookahead),  stop = 4 + lookahead.
    let text = "AAA\nbbb\nCCC\nddd\nEEE\nfff"
    let expected: [Int: Range<Int>] = [0: 2..<4, 1: 2..<5, 2: 1..<6]

    for lookahead in 0...2 {
      var scanner = IncrementalScanner(grammar: CueGrammar(lookahead: lookahead))
      Self.expectInvariants(
        scanner.fullScan(text), text: text, editedRange: nil, "convergence base \(lookahead)")
      let edited = Self.splice(text, 13..<13, "X")
      let result = scanner.incrementalScan(
        TextEdit(range: 13..<13, replacementLength: 1), in: edited)
      Self.expectInvariants(result, text: edited, editedRange: 13..<14, "convergence \(lookahead)")
      #expect(
        result.lines == expected[lookahead], "lookahead \(lookahead) rescanned \(result.lines)")
    }
  }

  @Test("A cue's classification changes when the line after it changes, both ways")
  func lookaheadClassificationIsRecomputed() {
    // The defect class the lookahead contract exists to prevent: correct on a full
    // parse, wrong while typing. Both directions are asserted, because an engine that
    // only ever widens on insertion passes the first half.
    let before = "BOB\n\nrest"
    var scanner = IncrementalScanner(grammar: CueGrammar(lookahead: 1))
    Self.expectInvariants(scanner.fullScan(before), text: before, editedRange: nil, "cue base")
    #expect(scanner.startStates.count == 3)

    // Typing on the blank line retroactively makes `BOB` a cue.
    let typed = Self.splice(before, 4..<4, "Hi")
    let result = scanner.incrementalScan(TextEdit(range: 4..<4, replacementLength: 2), in: typed)
    Self.expectInvariants(result, text: typed, editedRange: 4..<6, "cue typed")
    #expect(result.lines.contains(0))
    #expect(result.lineRecords.first(where: { $0.index == 0 })?.element == .testCue)

    // Deleting it again retroactively un-makes it.
    let undone = Self.splice(typed, 4..<6, "")
    let back = scanner.incrementalScan(TextEdit(range: 4..<6, replacementLength: 0), in: undone)
    Self.expectInvariants(back, text: undone, editedRange: 4..<4, "cue undone")
    #expect(back.lineRecords.first(where: { $0.index == 0 })?.element == .paragraph)
  }

  @Test("Convergence stops early when the state matches and the document is long")
  func convergenceStopsWellShortOfTheDocument() {
    // The other half of the contract: the window must be SMALL when it can be. A
    // one-character edit in the middle of a 500-line document must not rescan the
    // document — that is the difference between O(edited lines) and O(document), and it
    // is the whole reason the engine exists.
    let text = (0..<500).map { "line \($0)" }.joined(separator: "\n")
    var scanner = IncrementalScanner(grammar: FenceGrammar())
    Self.expectInvariants(scanner.fullScan(text), text: text, editedRange: nil, "long base")
    let offset = text.utf16.count / 2
    let edited = Self.splice(text, offset..<offset, "z")
    let result = scanner.incrementalScan(
      TextEdit(range: offset..<offset, replacementLength: 1), in: edited)
    Self.expectInvariants(result, text: edited, editedRange: offset..<(offset + 1), "long edit")

    #expect(
      result.lines.count <= 3, "rescanned \(result.lines.count) lines for a one-character edit")
    #expect(result.lines.upperBound < 500)
  }

  // MARK: - State, and the constructs that carry it

  @Test("Opening a fence on line 1 dirties the rest of the document")
  func openingAFenceDirtiesEverythingBelow() {
    // `dirtyRange` may be much larger than the edit (ScanResult invariant 3). The state
    // change propagates and nothing downstream ever converges, so the window runs to EOF.
    let body = (0..<200).map { "line \($0)" }.joined(separator: "\n")
    let text = "intro\n" + body
    var scanner = IncrementalScanner(grammar: FenceGrammar())
    Self.expectInvariants(scanner.fullScan(text), text: text, editedRange: nil, "fence base")

    let edited = Self.splice(text, 6..<6, "~~~\n")
    let result = scanner.incrementalScan(TextEdit(range: 6..<6, replacementLength: 4), in: edited)
    Self.expectInvariants(result, text: edited, editedRange: 6..<10, "fence opened")

    #expect(result.dirtyRange.upperBound == edited.utf16.count, "did not reach end of document")
    #expect(result.lines.upperBound == 202)
    #expect(result.lineRecords.last?.element == .codeBlock)
  }

  @Test("An unterminated fence scans to the end of the document and returns normally")
  func unterminatedFenceIsNotAnError() {
    let text = "~~~\n" + (0..<50).map { "line \($0)" }.joined(separator: "\n")
    var scanner = IncrementalScanner(grammar: FenceGrammar())
    let result = scanner.fullScan(text)
    Self.expectInvariants(result, text: text, editedRange: nil, "unterminated fence")

    #expect(result.dirtyRange == 0..<text.utf16.count)
    #expect(result.lineRecords.count == 51)
    #expect(result.lineRecords.dropFirst().allSatisfy { $0.element == .codeBlock })
    #expect(result.spans.reduce(0) { $0 + $1.range.count } == text.utf16.count)
  }

  @Test("Closing a fence reclassifies every line that was inside it")
  func closingAFenceReclassifiesTheBlock() {
    let text = "~~~\na\nb\nc\nd"
    var scanner = IncrementalScanner(grammar: FenceGrammar())
    Self.expectInvariants(scanner.fullScan(text), text: text, editedRange: nil, "closing base")
    // Delete the opening fence: every line below stops being code.
    let edited = Self.splice(text, 0..<4, "")
    let result = scanner.incrementalScan(TextEdit(range: 0..<4, replacementLength: 0), in: edited)
    Self.expectInvariants(result, text: edited, editedRange: 0..<0, "fence closed by deletion")

    #expect(result.lines == 0..<4)
    #expect(result.lineRecords.allSatisfy { $0.element == .paragraph })
    #expect(result.lineRecords.allSatisfy { $0.startState == LineState.documentStart })
  }

  // MARK: - Totality against bad grammars

  @Test(
    "A grammar emitting overlapping, unordered, and out-of-bounds spans still tiles",
    arguments: scanCorpus)
  func hostileGrammarStillTiles(document: ScanCorpusDocument) {
    var scanner = IncrementalScanner(grammar: HostileGrammar())
    let result = scanner.fullScan(document.text)
    Self.expectInvariants(result, text: document.text, editedRange: nil, "hostile")
    #expect(result.spans.reduce(0) { $0 + $1.range.count } == document.text.utf16.count)
  }

  @Test("A span boundary never splits a surrogate pair")
  func spanBoundariesNeverSplitASurrogatePair() {
    // `SurrogateSplittingGrammar` puts a boundary one code unit into every line. On a
    // line beginning with an astral-plane character that is half a character, and the
    // engine has to move it — a boundary through a surrogate pair hands
    // `setAttributes(_:range:)` a range the text system rounds outward, so the
    // attributes applied would not be the attributes computed.
    let text = "\u{1F600}abc\n\u{1F600}\nplain"
    var scanner = IncrementalScanner(grammar: SurrogateSplittingGrammar())
    let result = scanner.fullScan(text)
    Self.expectInvariants(result, text: text, editedRange: nil, "surrogate")

    let units = Array(text.utf16)
    for span in result.spans {
      let lower = span.range.lowerBound
      guard lower > 0, lower < units.count else { continue }
      let before = units[lower - 1]
      let at = units[lower]
      let splits = (0xD800...0xDBFF).contains(Int(before)) && (0xDC00...0xDFFF).contains(Int(at))
      #expect(!splits, "span boundary at \(lower) splits a surrogate pair")
    }
    // The first line's marker span swallowed the whole emoji rather than half of it.
    #expect(result.spans.first?.range == 0..<2)
  }

  @Test("A malformed edit is clamped rather than trapped")
  func outOfRangeEditsAreClamped() {
    // No `precondition` on the scan path: a caller that hands over a stale or nonsense
    // edit gets a well-formed result for the text it actually passed, not a crash inside
    // a text-view delegate callback.
    var scanner = IncrementalScanner(grammar: FenceGrammar())
    Self.expectInvariants(scanner.fullScan("hello"), text: "hello", editedRange: nil, "clamp base")
    let result = scanner.incrementalScan(
      TextEdit(range: 900..<9000, replacementLength: 3), in: "hello world")
    Self.expectInvariants(result, text: "hello world", editedRange: nil, "clamped")
    #expect(result.lineRecords.count == 1)
  }
}

/// A boxed grammar so one test can loop over several of them.
///
/// A tiny enum rather than an existential: `LineGrammar` has no associated types, but
/// keeping the grammars concrete keeps the engine's generic specialization — and its
/// error messages — honest.
enum AnyTestGrammar: CustomStringConvertible {
  case plain
  case fence
  case cue(Int)
  case hostile

  var description: String {
    switch self {
    case .plain: "plain"
    case .fence: "fence"
    case .cue(let lookahead): "cue(\(lookahead))"
    case .hostile: "hostile"
    }
  }

  /// Full-scans `text` **and runs the invariant harness on the way out**, so that no
  /// caller of this convenience can produce an unchecked `ScanResult`.
  func fullScan(
    _ text: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> ScanResult {
    let result: ScanResult
    switch self {
    case .plain:
      var scanner = IncrementalScanner(grammar: PlainTextGrammar())
      result = scanner.fullScan(text)
    case .fence:
      var scanner = IncrementalScanner(grammar: FenceGrammar())
      result = scanner.fullScan(text)
    case .cue(let lookahead):
      var scanner = IncrementalScanner(grammar: CueGrammar(lookahead: lookahead))
      result = scanner.fullScan(text)
    case .hostile:
      var scanner = IncrementalScanner(grammar: HostileGrammar())
      result = scanner.fullScan(text)
    }
    ScanInvariants.check(
      result, text: text, editedRange: nil, "\(self) full scan of \(text.debugDescription)",
      sourceLocation: sourceLocation)
    return result
  }
}
