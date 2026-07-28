import Testing

@testable import EscriboCore

/// An ASCII document used as the base text for exhaustive edit sweeps.
///
/// ASCII on purpose: the sweep splices arbitrary code-unit ranges, and splicing through
/// the middle of a surrogate pair would produce a string the test itself corrupted
/// rather than one the index mishandled. Astral-plane handling is asserted structurally
/// in `LineIndexTests` instead, where nothing gets spliced.
struct EditCorpusDocument: Sendable, CustomTestStringConvertible {
  let name: String
  let text: String

  var testDescription: String { name }
}

let editCorpus: [EditCorpusDocument] = [
  EditCorpusDocument(name: "empty", text: ""),
  EditCorpusDocument(name: "single line", text: "alpha"),
  EditCorpusDocument(name: "LF document", text: "one\ntwo\nthree"),
  EditCorpusDocument(name: "CRLF document", text: "one\r\ntwo\r\nthree"),
  EditCorpusDocument(name: "lone CR document", text: "one\rtwo\rthree"),
  EditCorpusDocument(name: "mixed terminators", text: "a\nb\r\nc\rd"),
  EditCorpusDocument(name: "trailing terminator", text: "one\ntwo\n"),
  EditCorpusDocument(name: "trailing CRLF", text: "one\r\n"),
  EditCorpusDocument(name: "blank lines", text: "\n\r\n\r\n"),
]

/// Replacement strings the sweep splices in. Every terminator convention appears, plus
/// the two adversarial ones: a bare `\r` (which may pair with a following `\n` that was
/// already there) and a `\n\r` (which may pair *backwards* with a `\r` already there).
let editReplacements: [String] = ["", "x", "\n", "\r", "\r\n", "\n\r", "ab\ncd", "z\r\ny"]

@Suite("Line index — incremental adjustment")
struct LineIndexIncrementalTests {

  // MARK: - Helpers

  /// Splices `replacement` over `range` (UTF-16 code units) of `text`.
  private static func splice(_ text: String, _ range: Range<Int>, _ replacement: String) -> String {
    var units = Array(text.utf16)
    units.replaceSubrange(range, with: Array(replacement.utf16))
    return String(decoding: units, as: UTF16.self)
  }

  /// Applies `edit` incrementally and asserts the result is indistinguishable from
  /// indexing the new text from scratch.
  ///
  /// `LineIndex` is `Equatable` over its whole storage, so this compares every line
  /// start and every terminator length in one assertion. It is the analogue of Sortie
  /// 6's `incrementalScan == fullScan` gate, one layer down: if incremental adjustment
  /// can diverge from a full index, no scanner built on it can be correct either.
  @discardableResult
  private static func expectIncrementalMatchesFull(
    from old: String,
    replacing range: Range<Int>,
    with replacement: String
  ) -> LineIndex {
    let new = splice(old, range, replacement)
    var incremental = LineIndex(old)
    incremental.apply(
      TextEdit(range: range, replacementLength: replacement.utf16.count),
      to: new
    )
    let full = LineIndex(new)
    #expect(incremental == full, "old=\(old.debugDescription) new=\(new.debugDescription)")
    return incremental
  }

  // MARK: - The sweep

  @Test(
    "Incremental adjustment equals a full re-index for every edit in the corpus",
    arguments: editCorpus)
  func incrementalEqualsFull(document: EditCorpusDocument) {
    // Every start offset, four deletion lengths, eight replacement strings. On this
    // corpus that is a few thousand edits per document, which is cheap and which covers
    // the cases nobody thinks to write by hand: deleting exactly the LF out of a CRLF,
    // inserting a `\r` immediately before an existing `\n`, replacing a whole document
    // with a terminator, and editing at offset 0 and at EOF.
    let length = document.text.utf16.count
    for start in 0...length {
      for deleted in 0...min(3, length - start) {
        for replacement in editReplacements {
          Self.expectIncrementalMatchesFull(
            from: document.text,
            replacing: start..<(start + deleted),
            with: replacement
          )
        }
      }
    }
  }

  @Test("A whole-document replacement re-indexes correctly", arguments: editCorpus)
  func wholeDocumentReplacement(document: EditCorpusDocument) {
    for replacement in editReplacements {
      Self.expectIncrementalMatchesFull(
        from: document.text,
        replacing: 0..<document.text.utf16.count,
        with: replacement
      )
    }
  }

  // MARK: - The CRLF cases, named

  @Test("An edit landing between the CR and the LF splits the pair into two terminators")
  func editInsideACRLFPair() {
    // Offset 2 of "a\r\nb" is *inside* line 0's terminator. The obvious correct answer —
    // and the one the index gives — is that after the edit there is no `\r\n` left to
    // split: the `\r` becomes a lone-CR terminator, the inserted text becomes a new
    // line ended by the orphaned `\n`, and the document grows from two lines to three.
    // Nothing is normalized and no pair is broken across a line boundary, because no
    // pair survives the edit.
    let index = Self.expectIncrementalMatchesFull(from: "a\r\nb", replacing: 2..<2, with: "X")

    #expect(index.lineCount == 3)
    #expect(index.line(at: 0).range == 0..<2)
    #expect(index.line(at: 0).terminatorLength == 1)  // lone CR
    #expect(index.line(at: 1).range == 2..<4)  // "X\n"
    #expect(index.line(at: 1).terminatorLength == 1)
    #expect(index.line(at: 2).range == 4..<5)  // "b"
    #expect(index.line(at: 2).terminatorLength == 0)
  }

  @Test("Typing an LF after a trailing CR forms one CRLF, not a split pair")
  func typingLineFeedAfterCarriageReturn() {
    // This is the case that forces backward widening. The edit is at offset 2 of "a\r",
    // which is the start of the final empty line — so rescanning only the lines the edit
    // touches would leave the `\r` frozen as line 0's terminator and hand the new `\n`
    // to line 1, splitting a `\r\n` pair across a line boundary. Widening the rescan
    // back one line is what makes the two code units get looked at together.
    let index = Self.expectIncrementalMatchesFull(from: "a\r", replacing: 2..<2, with: "\n")

    #expect(index.lineCount == 2)
    #expect(index.line(at: 0).range == 0..<3)
    #expect(index.line(at: 0).terminatorLength == 2)
    #expect(index.line(at: 1).range == 3..<3)
  }

  @Test("Deleting the LF out of a CRLF leaves a lone CR terminator")
  func deletingTheLineFeedOfACRLF() {
    let index = Self.expectIncrementalMatchesFull(from: "a\r\nb", replacing: 2..<3, with: "")
    #expect(index.lineCount == 2)
    #expect(index.line(at: 0).range == 0..<2)
    #expect(index.line(at: 0).terminatorLength == 1)
    #expect(index.line(at: 1).range == 2..<3)
  }

  @Test("Deleting between a lone CR and a lone LF fuses them into one CRLF")
  func deletingBetweenACarriageReturnAndALineFeed() {
    // "a\rX\nb" is three lines. Deleting the `X` puts the `\r` and the `\n` adjacent,
    // which must collapse them into a single two-code-unit terminator and drop the
    // document to two lines. A rescan region that stopped at the edit would leave the
    // `\n` in a separate line.
    let index = Self.expectIncrementalMatchesFull(from: "a\rX\nb", replacing: 2..<3, with: "")
    #expect(index.lineCount == 2)
    #expect(index.line(at: 0).range == 0..<3)
    #expect(index.line(at: 0).terminatorLength == 2)
    #expect(index.line(at: 1).range == 3..<4)
  }

  // MARK: - Shifting versus recomputing

  @Test("Lines before the edit are untouched and lines after it shift by changeInLength")
  func linesShiftRatherThanRescan() {
    // The whole point of incremental adjustment: an edit on line 2 of a long document
    // must not re-read lines 3 through 400. They keep their terminators and move by
    // exactly `TextEdit.changeInLength` — the accessor, not a locally recomputed delta,
    // because two ways of computing the same number is one way too many.
    let old = (0..<400).map { "line \($0)" }.joined(separator: "\r\n")
    let edit = TextEdit(range: 3..<3, replacementLength: 5)
    let new = Self.splice(old, 3..<3, "XXXXX")

    var incremental = LineIndex(old)
    let before = incremental.line(at: 0).range
    incremental.apply(edit, to: new)

    let full = LineIndex(new)
    #expect(incremental == full)
    #expect(incremental.lineCount == 400)
    // Line 0 grew by the insertion; every later line moved by exactly +5 and kept its
    // two-code-unit CRLF terminator.
    #expect(incremental.line(at: 0).range == before.lowerBound..<(before.upperBound + 5))
    for lineNumber in 1..<400 {
      #expect(incremental.line(at: lineNumber).range == full.line(at: lineNumber).range)
      #expect(incremental.line(at: lineNumber).terminatorLength == (lineNumber == 399 ? 0 : 2))
    }
  }

  @Test("Deleting the entire document leaves one empty line, never zero")
  func deletingEverything() {
    let index = Self.expectIncrementalMatchesFull(from: "a\r\nb\n", replacing: 0..<5, with: "")
    #expect(index.lineCount == 1)
    #expect(index.line(at: 0).range == 0..<0)
    #expect(index.utf16Count == 0)
  }

  @Test("A multi-line paste and a multi-line deletion both re-index correctly")
  func multiLineBlockEdits() {
    // Paste: three lines land in the middle of line 1.
    let pasted = Self.expectIncrementalMatchesFull(
      from: "one\ntwo\nthree", replacing: 5..<5, with: "A\r\nB\rC")
    #expect(pasted.lineCount == 5)

    // Delete: a range spanning two terminators collapses three lines into one.
    let deleted = Self.expectIncrementalMatchesFull(
      from: "one\ntwo\nthree", replacing: 2..<10, with: "")
    #expect(deleted.lineCount == 1)
  }

  @Test("A sequence of edits applied one at a time tracks a full re-index throughout")
  func editSequence() {
    // Single edits are the easy case; drift shows up when the index is carried across
    // many of them without ever being rebuilt, which is exactly how a live editor uses
    // it. Fixed script, no randomness — a seeded generator belongs to Sortie 6, and an
    // unseeded one belongs nowhere.
    let script: [(Range<Int>, String)] = [
      (0..<0, "INT. HOUSE - DAY\r\n"),
      (18..<18, "\r\n"),
      (20..<20, "BOB\n"),
      (24..<24, "Hello.\r"),
      (16..<18, ""),  // delete the CRLF, fusing lines
      (0..<1, "\r"),  // turn the first character into a CR
      (0..<0, "\n"),  // and put an LF in front of it — must NOT fuse backwards
    ]

    var text = ""
    var incremental = LineIndex(text)
    for (range, replacement) in script {
      let next = Self.splice(text, range, replacement)
      incremental.apply(
        TextEdit(range: range, replacementLength: replacement.utf16.count), to: next)
      text = next
      #expect(incremental == LineIndex(text), "diverged at \(text.debugDescription)")
    }
  }
}
