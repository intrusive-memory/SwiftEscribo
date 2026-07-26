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

  // MARK: - Independent oracles
  //
  // Deliberately not built on `LineIndex`. An invariant checked with the same code that
  // produced the value under test is not checked at all, and line alignment is exactly
  // the invariant where that mistake would be invisible.

  /// Every offset a line may start or end at: `0`, one past each terminator, and the end
  /// of the document. Hand-written, no regex, and no `LineIndex`.
  static func lineBoundaries(of text: String) -> Set<Int> {
    let units = Array(text.utf16)
    var boundaries: Set<Int> = [0, units.count]
    var offset = 0
    while offset < units.count {
      if units[offset] == 0x0A {
        boundaries.insert(offset + 1)
        offset += 1
      } else if units[offset] == 0x0D {
        let pair = offset + 1 < units.count && units[offset + 1] == 0x0A
        boundaries.insert(offset + (pair ? 2 : 1))
        offset += pair ? 2 : 1
      } else {
        offset += 1
      }
    }
    return boundaries
  }

  /// Splices `replacement` over `range` (UTF-16 code units) of `text`.
  static func splice(_ text: String, _ range: Range<Int>, _ replacement: String) -> String {
    var units = Array(text.utf16)
    units.replaceSubrange(range, with: Array(replacement.utf16))
    return String(decoding: units, as: UTF16.self)
  }

  // MARK: - The invariant block
  //
  // Written out longhand, once, here. Sortie 6 owns the shared harness; until it exists,
  // direct assertions beat a helper nobody has agreed on yet.

  /// Asserts every ``ScanResult`` invariant against `text`.
  static func expectInvariants(
    _ result: ScanResult,
    text: String,
    editedRange: Range<Int>?,
    _ context: @autoclosure () -> String
  ) {
    let boundaries = lineBoundaries(of: text)
    let note = context()

    // 2. `dirtyRange` is line-aligned at BOTH ends.
    #expect(boundaries.contains(result.dirtyRange.lowerBound), "lower not line-aligned — \(note)")
    #expect(boundaries.contains(result.dirtyRange.upperBound), "upper not line-aligned — \(note)")
    #expect(result.dirtyRange.lowerBound <= result.dirtyRange.upperBound, "inverted — \(note)")
    #expect(result.dirtyRange.upperBound <= text.utf16.count, "past EOF — \(note)")

    // 2, continued. `dirtyRange` CONTAINS the edited range, in new-text coordinates.
    if let editedRange {
      #expect(result.dirtyRange.lowerBound <= editedRange.lowerBound, "starts after edit — \(note)")
      #expect(result.dirtyRange.upperBound >= editedRange.upperBound, "ends before edit — \(note)")
    }

    // 1. Spans are ordered, non-overlapping, contiguous, and exactly tile `dirtyRange`.
    if result.dirtyRange.isEmpty {
      #expect(result.spans.isEmpty, "spans over an empty dirty range — \(note)")
    } else {
      #expect(
        result.spans.first?.range.lowerBound == result.dirtyRange.lowerBound, "first span — \(note)"
      )
      #expect(
        result.spans.last?.range.upperBound == result.dirtyRange.upperBound, "last span — \(note)")
      var cursor = result.dirtyRange.lowerBound
      for span in result.spans {
        #expect(span.range.lowerBound == cursor, "gap or overlap at \(cursor) — \(note)")
        #expect(!span.range.isEmpty, "empty span at \(cursor) — \(note)")
        cursor = span.range.upperBound
      }
      #expect(cursor == result.dirtyRange.upperBound, "short tiling — \(note)")
    }

    // 4. `lineRecords` covers `lines` completely, in order, with no gaps.
    #expect(result.lineRecords.count == result.lines.count, "record count — \(note)")
    for (offset, record) in result.lineRecords.enumerated() {
      #expect(record.index == result.lines.lowerBound + offset, "index gap — \(note)")
      #expect(record.contentRange.lowerBound >= record.range.lowerBound, "content below — \(note)")
      #expect(record.contentRange.upperBound <= record.range.upperBound, "content above — \(note)")
    }
    // Records tile the dirty range too — they are the paragraph-attribute half of the
    // same output and must agree with the span half about where the region is.
    if let first = result.lineRecords.first, let last = result.lineRecords.last {
      #expect(first.range.lowerBound == result.dirtyRange.lowerBound, "record start — \(note)")
      #expect(last.range.upperBound == result.dirtyRange.upperBound, "record end — \(note)")
      var cursor = first.range.lowerBound
      for record in result.lineRecords {
        #expect(record.range.lowerBound == cursor, "record gap — \(note)")
        cursor = record.range.upperBound
      }
    }
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
    incremental.fullScan(old)
    let result = incremental.incrementalScan(edit, in: new)

    var fresh = IncrementalScanner(grammar: grammar)
    let full = fresh.fullScan(new)

    expectInvariants(result, text: new, editedRange: editedRange, note)
    expectInvariants(full, text: new, editedRange: nil, note)

    // The gate, one layer above `LineIndex`'s: an incremental scan must be
    // indistinguishable from a full scan wherever it claims to have scanned.
    #expect(incremental.startStates == fresh.startStates, "line states diverged — \(note)")
    let expectedRecords = full.lineRecords.filter { result.lines.contains($0.index) }
    #expect(result.lineRecords == expectedRecords, "records diverged — \(note)")
    let expectedSpans = full.spans.filter {
      $0.range.lowerBound >= result.dirtyRange.lowerBound
        && $0.range.upperBound <= result.dirtyRange.upperBound
    }
    #expect(result.spans == expectedSpans, "spans diverged — \(note)")

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
    incremental.fullScan(text)

    for (range, replacement) in script {
      let next = Self.splice(text, range, replacement)
      let result = incremental.incrementalScan(
        TextEdit(range: range, replacementLength: replacement.utf16.count), in: next)
      Self.expectInvariants(
        result, text: next,
        editedRange: range.lowerBound..<(range.lowerBound + replacement.utf16.count),
        "sequence at \(next.debugDescription)")

      var fresh = IncrementalScanner(grammar: FenceGrammar())
      fresh.fullScan(next)
      #expect(incremental.startStates == fresh.startStates, "diverged at \(next.debugDescription)")
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
    scanner.fullScan(text)
    let result = scanner.incrementalScan(
      TextEdit(range: 12..<15, replacementLength: 0), in: "aaa\nbbb\nCCC\n\neee")

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
      scanner.fullScan(text)
      let result = scanner.incrementalScan(
        TextEdit(range: 12..<12, replacementLength: 1), in: Self.splice(text, 12..<12, "X"))
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
      scanner.fullScan(text)
      let result = scanner.incrementalScan(
        TextEdit(range: 13..<13, replacementLength: 1), in: Self.splice(text, 13..<13, "X"))
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
    scanner.fullScan(before)
    #expect(scanner.startStates.count == 3)

    // Typing on the blank line retroactively makes `BOB` a cue.
    let typed = Self.splice(before, 4..<4, "Hi")
    let result = scanner.incrementalScan(TextEdit(range: 4..<4, replacementLength: 2), in: typed)
    #expect(result.lines.contains(0))
    #expect(result.lineRecords.first(where: { $0.index == 0 })?.element == .character)

    // Deleting it again retroactively un-makes it.
    let undone = Self.splice(typed, 4..<6, "")
    let back = scanner.incrementalScan(TextEdit(range: 4..<6, replacementLength: 0), in: undone)
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
    scanner.fullScan(text)
    let offset = text.utf16.count / 2
    let result = scanner.incrementalScan(
      TextEdit(range: offset..<offset, replacementLength: 1),
      in: Self.splice(text, offset..<offset, "z"))

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
    scanner.fullScan(text)

    let edited = Self.splice(text, 6..<6, "~~~\n")
    let result = scanner.incrementalScan(TextEdit(range: 6..<6, replacementLength: 4), in: edited)

    #expect(result.dirtyRange.upperBound == edited.utf16.count, "did not reach end of document")
    #expect(result.lines.upperBound == 202)
    #expect(result.lineRecords.last?.element == .codeBlock)
  }

  @Test("An unterminated fence scans to the end of the document and returns normally")
  func unterminatedFenceIsNotAnError() {
    let text = "~~~\n" + (0..<50).map { "line \($0)" }.joined(separator: "\n")
    var scanner = IncrementalScanner(grammar: FenceGrammar())
    let result = scanner.fullScan(text)

    #expect(result.dirtyRange == 0..<text.utf16.count)
    #expect(result.lineRecords.count == 51)
    #expect(result.lineRecords.dropFirst().allSatisfy { $0.element == .codeBlock })
    #expect(result.spans.reduce(0) { $0 + $1.range.count } == text.utf16.count)
  }

  @Test("Closing a fence reclassifies every line that was inside it")
  func closingAFenceReclassifiesTheBlock() {
    let text = "~~~\na\nb\nc\nd"
    var scanner = IncrementalScanner(grammar: FenceGrammar())
    scanner.fullScan(text)
    // Delete the opening fence: every line below stops being code.
    let edited = Self.splice(text, 0..<4, "")
    let result = scanner.incrementalScan(TextEdit(range: 0..<4, replacementLength: 0), in: edited)

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
    scanner.fullScan("hello")
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

  func fullScan(_ text: String) -> ScanResult {
    switch self {
    case .plain:
      var scanner = IncrementalScanner(grammar: PlainTextGrammar())
      return scanner.fullScan(text)
    case .fence:
      var scanner = IncrementalScanner(grammar: FenceGrammar())
      return scanner.fullScan(text)
    case .cue(let lookahead):
      var scanner = IncrementalScanner(grammar: CueGrammar(lookahead: lookahead))
      return scanner.fullScan(text)
    case .hostile:
      var scanner = IncrementalScanner(grammar: HostileGrammar())
      return scanner.fullScan(text)
    }
  }
}
