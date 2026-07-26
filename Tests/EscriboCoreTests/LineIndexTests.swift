import Testing

@testable import EscriboCore

/// A document plus the exact line geometry it must produce.
///
/// Named so a failing parameterized case identifies itself — "Mixed terminators" in the
/// failure message is worth more than "argument 4".
struct TerminatorFixture: Sendable, CustomTestStringConvertible {
  let name: String
  let text: String
  /// Full line ranges, terminator included.
  let ranges: [Range<Int>]
  /// Terminator length per line: `2` for `\r\n`, `1` for `\n` or lone `\r`, `0` for none.
  let terminatorLengths: [Int]

  var testDescription: String { name }
}

/// The seven terminator conventions REQUIREMENTS.md § Line termination names, each as
/// its own case, plus the degenerate shapes that surround them.
///
/// Every one of these is a real document someone will open. CRLF arrives from Windows
/// and from Highland exports; lone `\r` arrives from classic-Mac-era files and from
/// text pasted out of some spreadsheets; mixed terminators arrive the first time two
/// people edit the same file on different machines. Getting any of them wrong shifts
/// every offset after the first occurrence, which is not a rendering glitch — it is
/// every subsequent span landing on the wrong characters.
let terminatorFixtures: [TerminatorFixture] = [
  TerminatorFixture(
    name: "LF only",
    text: "alpha\nbravo\ncharlie",
    ranges: [0..<6, 6..<12, 12..<19],
    terminatorLengths: [1, 1, 0]
  ),
  TerminatorFixture(
    name: "CRLF only",
    text: "alpha\r\nbravo\r\ncharlie",
    // The whole reason this fixture exists: each terminator is TWO code units, so every
    // line start after the first is one further along than an LF-only reading would say.
    ranges: [0..<7, 7..<14, 14..<21],
    terminatorLengths: [2, 2, 0]
  ),
  TerminatorFixture(
    name: "Lone CR only",
    text: "alpha\rbravo\rcharlie",
    ranges: [0..<6, 6..<12, 12..<19],
    terminatorLengths: [1, 1, 0]
  ),
  TerminatorFixture(
    name: "Mixed terminators",
    text: "a\nb\r\nc\rd",
    // All three conventions in one document, which REQUIREMENTS.md explicitly permits.
    // A scanner that picks a convention per document instead of per line fails here.
    ranges: [0..<2, 2..<5, 5..<7, 7..<8],
    terminatorLengths: [1, 2, 1, 0]
  ),
  TerminatorFixture(
    name: "Trailing terminator",
    text: "alpha\nbravo\n",
    // Three lines, not two. The trailing terminator produces a final EMPTY line because
    // that is where the text view lets the caret go, and disagreeing with the text view
    // about line count is unrecoverable.
    ranges: [0..<6, 6..<12, 12..<12],
    terminatorLengths: [1, 1, 0]
  ),
  TerminatorFixture(
    name: "Trailing CRLF terminator",
    text: "alpha\r\n",
    ranges: [0..<7, 7..<7],
    terminatorLengths: [2, 0]
  ),
  TerminatorFixture(
    name: "No trailing terminator",
    text: "alpha\nbravo",
    ranges: [0..<6, 6..<11],
    terminatorLengths: [1, 0]
  ),
  TerminatorFixture(
    name: "Empty document",
    text: "",
    // One empty line, never zero. Zero lines would mean the caret has nowhere to sit.
    ranges: [0..<0],
    terminatorLengths: [0]
  ),
  TerminatorFixture(
    name: "Single line, no terminator",
    text: "a",
    ranges: [0..<1],
    terminatorLengths: [0]
  ),
  TerminatorFixture(
    name: "Terminator only",
    text: "\n",
    ranges: [0..<1, 1..<1],
    terminatorLengths: [1, 0]
  ),
  TerminatorFixture(
    name: "Consecutive blank lines",
    text: "\n\r\n\r",
    ranges: [0..<1, 1..<3, 3..<4, 4..<4],
    terminatorLengths: [1, 2, 1, 0]
  ),
  TerminatorFixture(
    name: "Astral-plane characters",
    // The emoji is TWO code units. Offsets here are code units, never characters, so a
    // Character-counting index would put the terminator at 2 rather than 3.
    text: "a\u{1F600}\nb",
    ranges: [0..<4, 4..<5],
    terminatorLengths: [1, 0]
  ),
]

@Suite("Line index — terminators and line geometry")
struct LineIndexTests {

  // MARK: - Helpers

  /// Asserts the invariant everything else in this package rests on: the line ranges
  /// partition the document exactly, so concatenating them reproduces the source code
  /// unit for code unit.
  ///
  /// This is the strongest available check here. It catches an off-by-one in terminator
  /// length, a dropped final line, a duplicated line start, and an overlapping range —
  /// all at once, on every fixture, without enumerating what could go wrong.
  private func expectReconstructsSource(_ text: String, _ index: LineIndex) {
    let units = Array(text.utf16)
    var reassembled: [UInt16] = []
    for lineNumber in 0..<index.lineCount {
      reassembled.append(contentsOf: units[index.line(at: lineNumber).range])
    }
    #expect(reassembled == units)
    #expect(String(decoding: reassembled, as: UTF16.self) == text)
  }

  // MARK: - Line geometry

  @Test(
    "Line ranges are exactly as specified, under every terminator convention",
    arguments: terminatorFixtures)
  func lineRanges(fixture: TerminatorFixture) {
    let index = LineIndex(fixture.text)
    #expect(index.lineCount == fixture.ranges.count)
    #expect(index.utf16Count == fixture.text.utf16.count)
    #expect(index.lines.map(\.range) == fixture.ranges)
    #expect(index.lines.map(\.terminatorLength) == fixture.terminatorLengths)
    #expect(index.lines.map(\.index) == Array(0..<fixture.ranges.count))
  }

  @Test(
    "Summing every line range reconstructs the source byte for byte",
    arguments: terminatorFixtures)
  func rangesTileTheDocument(fixture: TerminatorFixture) {
    expectReconstructsSource(fixture.text, LineIndex(fixture.text))
  }

  @Test(
    "Every line's range includes its terminator, and its content range excludes it",
    arguments: terminatorFixtures)
  func rangesIncludeTerminators(fixture: TerminatorFixture) {
    // `LineRecord.range` includes the terminator and `contentRange` excludes it —
    // REQUIREMENTS.md states this explicitly because leaving it ambiguous guarantees an
    // off-by-one at every call site. Asserting it structurally (the terminator code
    // units really are the last ones in `range`, and no terminator code unit survives
    // into `contentRange`) beats asserting a length, which a scanner could satisfy by
    // accident.
    let units = Array(fixture.text.utf16)
    let index = LineIndex(fixture.text)

    for line in index.lines {
      #expect(line.contentRange.lowerBound == line.range.lowerBound)
      #expect(line.contentRange.upperBound == line.range.upperBound - line.terminatorLength)
      #expect(line.range.count == line.contentRange.count + line.terminatorLength)

      // Nothing terminator-ish hides inside the content.
      for unit in units[line.contentRange] {
        #expect(unit != 0x0A)
        #expect(unit != 0x0D)
      }

      // And what `range` holds past the content really is a terminator, of exactly the
      // shape the length claims.
      let terminator = Array(units[line.contentRange.upperBound..<line.range.upperBound])
      switch line.terminatorLength {
      case 0: #expect(terminator.isEmpty)
      case 1: #expect(terminator == [0x0A] || terminator == [0x0D])
      case 2: #expect(terminator == [0x0D, 0x0A])
      default: Issue.record("terminator length \(line.terminatorLength) is not 0, 1, or 2")
      }
    }
  }

  @Test("A CRLF pair is one terminator of two code units, never two terminators")
  func crlfIsOneTerminator() {
    // Stated as its own case because the failure is silent: reading `\r\n` as two
    // terminators produces a phantom empty line between every pair of real lines, and
    // every line index after the first is then wrong by a growing amount.
    let index = LineIndex("a\r\nb\r\nc")
    #expect(index.lineCount == 3)
    #expect(index.line(at: 0).terminatorLength == 2)
    #expect(index.line(at: 1).terminatorLength == 2)
    #expect(index.line(at: 0).contentRange == 0..<1)
    #expect(index.line(at: 1).contentRange == 3..<4)
  }

  @Test("A CR at a scan-chunk boundary still pairs with the LF after it")
  func crlfAcrossAChunkBoundary() {
    // The index reads the document in 4 096-code-unit chunks. A `\r` as the last unit of
    // a chunk is the one place the pair can be decided by two different reads, and
    // getting it wrong turns one CRLF into a lone CR plus a leading LF — the exact
    // corruption this package exists to avoid. 4 095 filler units put the `\r` at index
    // 4 095, the final position of the first chunk.
    let text = String(repeating: "a", count: 4095) + "\r\nb"
    let index = LineIndex(text)
    #expect(index.lineCount == 2)
    #expect(index.line(at: 0).range == 0..<4097)
    #expect(index.line(at: 0).terminatorLength == 2)
    #expect(index.line(at: 1).range == 4097..<4098)
    expectReconstructsSource(text, index)
  }

  @Test("Unicode's other line breaks are not terminators")
  func onlyThreeTerminatorsExist() {
    // U+0085, U+2028, and U+2029 are line breaks to Unicode but not to AppKit's or
    // UIKit's paragraph model, and REQUIREMENTS.md names three terminators and only
    // three. Treating one of these as a terminator would make the index disagree with
    // the text view about line count, which is unrecoverable.
    let index = LineIndex("a\u{0085}b\u{2028}c\u{2029}d")
    #expect(index.lineCount == 1)
  }

  // MARK: - Lookup

  @Test("An offset on a line boundary belongs to the line starting there")
  func lineIndexContainingOffset() {
    // "a\n" is two lines: 0..<2 and 2..<2. Offset 2 is both the end of the first and the
    // start of the second, and incremental adjustment picks its rescan region with this
    // function — so which one it answers is load-bearing, not a tie-break.
    let index = LineIndex("ab\ncd\n")
    #expect(index.lineIndex(containing: 0) == 0)
    #expect(index.lineIndex(containing: 2) == 0)
    #expect(index.lineIndex(containing: 3) == 1)
    #expect(index.lineIndex(containing: 5) == 1)
    #expect(index.lineIndex(containing: 6) == 2)
    // Out-of-range offsets clamp rather than trap: an edit arriving from a text view
    // that has already mutated is a real, survivable race.
    #expect(index.lineIndex(containing: -5) == 0)
    #expect(index.lineIndex(containing: 999) == 2)
  }

  // MARK: - Provisional records

  @Test("A 1 MB single line is exactly one line record covering every code unit")
  func megabyteSingleLine() {
    // REQUIREMENTS.md § Degenerate input: no algorithm may be worse than linear in line
    // length, and a minified megabyte-long line is how a scanner that benchmarks well
    // hangs in the field. This assertion is deliberately STRUCTURAL — one record, every
    // code unit covered. The wall-clock linearity check lives in
    // `EscriboPerformanceTests` (Sortie 28), because a timing assertion in the
    // PR-gating target is a flake waiting for a loaded CI runner.
    let length = 1_048_576
    let text = String(repeating: "a", count: length)
    let index = LineIndex(text)

    #expect(index.lineCount == 1)
    let records = index.provisionalRecords
    #expect(records.count == 1)
    #expect(records[0].range == 0..<length)
    #expect(records[0].contentRange == 0..<length)
    #expect(records[0].index == 0)
    #expect(index.utf16Count == length)
  }

  @Test("Provisional records carry the ranges and the blank/paragraph shape, nothing more")
  func provisionalRecords() {
    // The index knows where lines are; it knows no grammar. "Empty apart from its
    // terminator" is the one classification that is a property of the line's shape
    // rather than of Markdown or Fountain, and both grammars agree on it — everything
    // else waits for Sortie 4.
    let index = LineIndex("alpha\n\nbravo")
    let records = index.provisionalRecords
    #expect(records.map(\.index) == [0, 1, 2])
    #expect(records.map(\.range) == [0..<6, 6..<7, 7..<12])
    #expect(records.map(\.contentRange) == [0..<5, 6..<6, 7..<12])
    #expect(records.map(\.element) == [.paragraph, .blank, .paragraph])
    #expect(records.allSatisfy { $0.depth == 0 })
    #expect(records.allSatisfy { $0.startState == .documentStart })
  }
}
