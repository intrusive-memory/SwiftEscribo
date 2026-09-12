import EscriboCore
import Testing

#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

@testable import SwiftEscribo

/// ``EditorCoordinator``'s block queries, and the reason they cannot simply read the last
/// scan's blocks (REQUIREMENTS-1.1.0 § 4.3).
///
/// ## The defect this file exists to prevent
///
/// `ScanResult.blocks` covers only the **rescanned window**, and its first and last block
/// may be truncated at that window's edge. A query that answered from it unconditionally
/// would be wrong for every document larger than one rescan window — and would pass in
/// every small fixture, because a small fixture's window *is* the whole document. So the
/// central test here is ``queryIsCorrectAfterAnIncrementalEditInALargeDocument``, which is
/// deliberately built on a document of eighty paragraphs rather than the three-line
/// documents the rest of the suite uses.
/// ## Why this suite is `@MainActor`
///
/// The convention `CoordinatorFixtures` documents, for the reason it gives: the thing under
/// test is main-thread-owned by contract, `NSTextStorage` is an AppKit/UIKit object, and an
/// unannotated suite would run across the cooperative pool and exercise the coordinator in
/// a way no Representable ever will — testing a concurrency story the package explicitly
/// does not have. Every suite here builds a real editor through `CoordinatorFixtures`, so
/// every one of them needs it.
@MainActor
@Suite("Coordinator block queries")
struct EditorCoordinatorBlockQueryTests {

  // MARK: - A document whose offsets are arithmetic

  /// One paragraph of the large fixture: two hard-wrapped lines, 38 UTF-16 units.
  ///
  /// `"alpha bravo charlie"` is 19 units and `"delta echo foxtrot"` is 18, plus the
  /// terminator between them.
  static let paragraph = "alpha bravo charlie\ndelta echo foxtrot"

  /// How far apart consecutive paragraphs start: the paragraph plus its blank separator.
  static let paragraphStride = 40

  /// Eighty identical two-line paragraphs separated by blank lines.
  ///
  /// Identical on purpose. Every offset in it is arithmetic — paragraph `i` starts at
  /// `paragraphStride * i`, covers lines `3i` and `3i + 1`, and its block range is
  /// `paragraphStride * i ..< paragraphStride * i + 39` — so an expectation can be written down rather than
  /// read off the scanner. A fixture whose paragraphs differed in length would force every
  /// expectation to be computed by the same code it is meant to check.
  static let largeDocument = Array(repeating: paragraph, count: 80).joined(separator: "\n\n")

  /// The block range paragraph `index` must come back with.
  static func expectedRange(ofParagraph index: Int) -> Range<Int> {
    (paragraphStride * index)..<(paragraphStride * index + 39)
  }

  /// The line range paragraph `index` must come back with.
  static func expectedLines(ofParagraph index: Int) -> Range<Int> {
    (3 * index)..<(3 * index + 2)
  }

  // MARK: - The fixture holds

  @Test("The large fixture's arithmetic is what the scanner actually produces")
  func largeFixtureArithmeticHolds() {
    // Asserted before anything depends on it: if the offsets below are wrong, every other
    // test in this file fails for a reason that has nothing to do with the queries.
    let editor = CoordinatorFixtures.makeEditor(Self.largeDocument)
    #expect(editor.storage.length == Self.paragraphStride * 80 - 2, "eighty paragraphs, no trailing blank")

    let blocks = editor.coordinator.lastBlocks
    #expect(blocks.count == 80 * 2 - 1, "eighty paragraphs and seventy-nine blank separators")
    #expect(blocks.first?.kind == .paragraph)
    #expect(blocks.first?.lines == Self.expectedLines(ofParagraph: 0))
    #expect(blocks.first?.range == Self.expectedRange(ofParagraph: 0))
    #expect(blocks.dropFirst().first?.kind == .blank, "a blank line between paragraphs")
  }

  // MARK: - What an offset resolves to, including at and past the edges

  @Test("A known offset resolves to the block that contains it")
  func knownOffsetResolvesToItsBlock() {
    let editor = CoordinatorFixtures.makeEditor(Self.largeDocument)

    // Five units into paragraph 40's first line.
    let offset = Self.paragraphStride * 40 + 5
    let block = editor.coordinator.block(atUTF16Offset: offset)
    #expect(block?.kind == .paragraph)
    #expect(block?.lines == Self.expectedLines(ofParagraph: 40))
    #expect(block?.range == Self.expectedRange(ofParagraph: 40))

    // The second line of the same paragraph resolves to the **same** block, which is the
    // whole point of a block query: a hard wrap is not a boundary a writer sees.
    let secondLine = editor.coordinator.block(atUTF16Offset: Self.paragraphStride * 40 + 25)
    #expect(secondLine?.range == block?.range, "both wrapped lines are one block")

    // The blank separator after it is its own block, so the query is not simply returning
    // the nearest paragraph.
    let blank = editor.coordinator.block(atUTF16Offset: Self.paragraphStride * 40 + 39)
    #expect(blank?.kind == .blank)
  }

  @Test("A genuinely out-of-range offset resolves to nothing, and costs no scan")
  func outOfRangeOffsetsResolveToNothing() {
    // "Out of range" means negative, or past the last code unit. Those are the two a caller
    // can actually get wrong, and both are reachable from a hover just off the edge of a
    // text view — which is what Sortie 5 will be doing on every pointer move.
    //
    //   "one\n\ntwo" — line 0 is 0..<4, the blank line is 4..<5, line 2 is 5..<8
    let editor = CoordinatorFixtures.makeEditor("one\n\ntwo")
    #expect(editor.storage.length == 8)
    #expect(editor.coordinator.documentBlocks.map(\.kind) == [.paragraph, .blank, .paragraph])

    let before = editor.coordinator.restyleCount
    #expect(editor.coordinator.block(atUTF16Offset: -1) == nil, "a negative offset is nowhere")
    #expect(editor.coordinator.block(atUTF16Offset: 9) == nil, "one past the end is nowhere")
    #expect(editor.coordinator.block(atUTF16Offset: 9_999) == nil)
    #expect(
      editor.coordinator.restyleCount == before,
      """
      an out-of-range offset must not trigger a scan: the document-wide cache already \
      proves there is no block there, and a hover off the edge of the view would otherwise \
      full-scan on every pointer move
      """)
  }

  @Test("An offset at the document's length is the caret at the end, not out of range")
  func offsetAtTheDocumentLengthResolvesToTheLastBlock() {
    // The boundary, which is easy to get wrong in either direction and which no other test
    // covers. Offset 8 in an eight-unit document is where a writer leaves the caret after
    // typing the last character; it belongs to the last block, not to nothing.
    let editor = CoordinatorFixtures.makeEditor("one\n\ntwo")
    let last = editor.coordinator.block(atUTF16Offset: 8)
    #expect(last?.kind == .paragraph)
    #expect(last?.range == 5..<8, "the final paragraph, not the blank line before it")

    // And the blank line in the middle is reachable by its own offset, so the tiling is
    // real rather than an artefact of clamping.
    #expect(editor.coordinator.block(atUTF16Offset: 4)?.kind == .blank)
  }

  @Test("An empty document resolves to its blank block, because blocks tile completely")
  func anEmptyDocumentResolvesToItsBlankBlock() {
    // Sortie 1 made blank runs blocks specifically so that this query is a **total**
    // function with no "not found" branch. An empty document scans to one blank block
    // covering `0..<0`, and offset 0 — a perfectly valid caret position — resolves to it.
    //
    // An earlier version of this file asserted `nil` here, conflating "the document is
    // empty" with "the offset is out of range". They are different claims: the second is
    // covered by `outOfRangeOffsetsResolveToNothing` above. Answering `nil` for an empty
    // document would put a hole in a total function for the one document in which nothing
    // can go wrong, and Sortie 5's eligibility check would be the first thing to trip on it.
    let editor = CoordinatorFixtures.makeEditor("")
    #expect(editor.storage.length == 0)

    let block = editor.coordinator.block(atUTF16Offset: 0)
    #expect(block?.kind == .blank, "an empty document is one blank line, and blank lines are blocks")
    #expect(block?.range == 0..<0)
    #expect(block?.lines == 0..<1, "one line, empty")
    #expect(block?.contentRanges.isEmpty == true, "…and nothing to speak")

    // Out of range is still out of range, even here.
    #expect(editor.coordinator.block(atUTF16Offset: 1) == nil)
    #expect(editor.coordinator.block(atUTF16Offset: -1) == nil)
  }

  @Test("A coordinator that has never scanned scans once and then answers")
  func unscannedCoordinatorsScanRatherThanGuess() {
    // The miss path, and the same trade `elementKind(atUTF16Offset:)` makes: rather than
    // guess, or answer from an index that describes no document, the query scans.
    let storage = NSTextStorage(string: "prose")
    let fresh = EditorCoordinator(
      attachingTo: storage, language: .markdown, styler: EscriboStyler(theme: .markdownLight))
    #expect(fresh.restyleCount == 0, "nothing has been scanned yet")
    #expect(fresh.blocksSpanDocument == false, "…so the cache spans nothing")

    #expect(fresh.block(atUTF16Offset: 0)?.kind == .paragraph, "the query scans and answers")
    #expect(fresh.restyleCount == 1, "…having paid for exactly one scan to do it")
    #expect(fresh.blocksSpanDocument, "and the cache now spans the document")

    // A second query is free, including one that finds nothing.
    #expect(fresh.block(atUTF16Offset: 2)?.kind == .paragraph)
    #expect(fresh.block(atUTF16Offset: 99) == nil)
    #expect(fresh.restyleCount == 1, "no further scan for either")
  }

  // MARK: - The test this file exists for

  @Test("A query is correct after an incremental edit in a document larger than one window")
  func queryIsCorrectAfterAnIncrementalEditInALargeDocument() {
    let editor = CoordinatorFixtures.makeEditor(Self.largeDocument)

    // Type one character into paragraph 0, which is an incremental rescan of a handful of
    // lines out of two hundred and thirty-nine.
    editor.storage.replaceCharacters(in: NSRange(location: 5, length: 0), with: "X")

    // The premise: the rescan really was a window, not the document. Without this the test
    // could pass on a coordinator that full-scanned every keystroke, which is the
    // implementation it is supposed to rule out.
    #expect(
      editor.coordinator.lastBlockCoverage.upperBound < editor.storage.length,
      """
      the edit must have been incremental; covered \
      \(editor.coordinator.lastBlockCoverage) of \(editor.storage.length)
      """)
    #expect(editor.coordinator.lastBlocks.count < 80, "the window is not the whole document")

    // Now ask about paragraph 40, nowhere near the edit. Every offset past the edit has
    // shifted by one, because a character was inserted before them.
    let shifted = 1
    let block = editor.coordinator.block(atUTF16Offset: Self.paragraphStride * 40 + 5 + shifted)
    #expect(block?.kind == .paragraph)
    #expect(
      block?.lines == Self.expectedLines(ofParagraph: 40),
      "a block far from the edit must still resolve, which means falling back to a full scan")
    let expected = Self.expectedRange(ofParagraph: 40)
    #expect(block?.range == ((expected.lowerBound + shifted)..<(expected.upperBound + shifted)))
  }

  @Test("A block truncated by the rescan window is never returned as if it were whole")
  func truncatedBlocksAreNotReturned() {
    // The subtler half of the same defect. After an incremental edit the *edited*
    // paragraph's block may itself be cut at the window's edge, so a query for an offset
    // **inside** the window is not automatically safe either. It must come back as the
    // whole paragraph, not as however much of it the window happened to contain.
    let editor = CoordinatorFixtures.makeEditor(Self.largeDocument)
    editor.storage.replaceCharacters(in: NSRange(location: Self.paragraphStride * 40 + 5, length: 0), with: "X")

    let block = editor.coordinator.block(atUTF16Offset: Self.paragraphStride * 40 + 5)
    #expect(block?.kind == .paragraph)
    #expect(
      block?.lines == Self.expectedLines(ofParagraph: 40),
      "the edited paragraph must resolve to both its lines, not to the window's fragment")
    #expect(block?.range.count == 39 + 1, "the whole paragraph, plus the character just typed")
  }

  @Test("Every block of a fully scanned document is trusted without a second scan")
  func fullyScannedDocumentsNeedNoRefetch() {
    // The cheap path, asserted so that a regression turning every query into a full scan
    // shows up as a behaviour change rather than only as a slow editor.
    let editor = CoordinatorFixtures.makeEditor(Self.largeDocument)
    let before = editor.coordinator.restyleCount

    for index in stride(from: 0, to: 80, by: 7) {
      let block = editor.coordinator.block(atUTF16Offset: Self.paragraphStride * index + 3)
      #expect(block?.lines == Self.expectedLines(ofParagraph: index))
    }
    #expect(
      editor.coordinator.restyleCount == before,
      "a full scan already covers the document, so no query may trigger another")
  }

  // MARK: - The splice

  @Test("An incremental edit splices into the document-wide cache instead of invalidating it")
  func incrementalEditSplicesRatherThanInvalidates() {
    // The saving the splice exists for: after an ordinary edit the cache still describes
    // the whole document, so a viewport query costs nothing. Without the splice this flag
    // would be false and every `blocks(in:)` would scan.
    let editor = CoordinatorFixtures.makeEditor(Self.largeDocument)
    #expect(editor.coordinator.blocksSpanDocument, "a full scan covers the document")

    let before = editor.coordinator.restyleCount
    editor.storage.replaceCharacters(in: NSRange(location: 5, length: 0), with: "X")
    #expect(editor.coordinator.blocksSpanDocument, "the edit spliced; the cache still spans")
    #expect(editor.coordinator.documentBlocks.count == 80 * 2 - 1, "no block was lost or added")

    // And the query is now free — no second scan.
    let block = editor.coordinator.block(atUTF16Offset: Self.paragraphStride * 60 + 5 + 1)
    #expect(block?.lines == Self.expectedLines(ofParagraph: 60))
    #expect(
      editor.coordinator.restyleCount == before + 1,
      "one scan for the edit itself, and none for the query")
  }

  @Test("The splice shifts blocks past the window when an edit changes the line count")
  func spliceShiftsLinesWhenTheLineCountChanges() {
    // **The test that a splice ignoring the line delta cannot pass.** Every other test here
    // edits within a line, so every cached block past the window keeps its line numbers and
    // a splice that never shifted anything would look correct. Inserting a newline moves
    // every line after it by one.
    let editor = CoordinatorFixtures.makeEditor(Self.largeDocument)
    let lineCountBefore = editor.coordinator.lastLineRecords.count
    #expect(lineCountBefore == 80 * 3 - 1, "two lines and a separator per paragraph, bar the last")

    // Split paragraph 0's first line in two. Offsets past it move by one; lines move by one.
    editor.storage.replaceCharacters(in: NSRange(location: 5, length: 0), with: "\n")

    // Paragraph 40 is now one line and one code unit later than it was.
    let block = editor.coordinator.block(atUTF16Offset: Self.paragraphStride * 40 + 5 + 1)
    let expectedLines = Self.expectedLines(ofParagraph: 40)
    let expectedRange = Self.expectedRange(ofParagraph: 40)
    #expect(
      block?.lines == ((expectedLines.lowerBound + 1)..<(expectedLines.upperBound + 1)),
      """
      a splice that ignored the line delta returns \(expectedLines) here;       got \(String(describing: block?.lines))
      """)
    #expect(block?.range == ((expectedRange.lowerBound + 1)..<(expectedRange.upperBound + 1)))
    #expect(block?.kind == .paragraph)
  }

  @Test("The splice shifts blocks back when an edit removes a line")
  func spliceShiftsLinesBackWhenALineIsRemoved() {
    // The inverse, because a splice can get the sign wrong and still pass the insertion
    // case. Delete paragraph 0's internal newline, joining its two lines into one.
    let editor = CoordinatorFixtures.makeEditor(Self.largeDocument)
    editor.storage.replaceCharacters(in: NSRange(location: 19, length: 1), with: "")

    let block = editor.coordinator.block(atUTF16Offset: Self.paragraphStride * 40 + 5 - 1)
    let expectedLines = Self.expectedLines(ofParagraph: 40)
    let expectedRange = Self.expectedRange(ofParagraph: 40)
    #expect(block?.lines == ((expectedLines.lowerBound - 1)..<(expectedLines.upperBound - 1)))
    #expect(block?.range == ((expectedRange.lowerBound - 1)..<(expectedRange.upperBound - 1)))
  }

  @Test("A spliced answer agrees with a freshly scanned one, which is the real criterion")
  func splicedAnswersAgreeWithAFreshScan() {
    // The property that makes the splice trustworthy rather than merely plausible: after a
    // line-count-changing edit, every block the cache reports must be the block a scanner
    // that had never seen the earlier document would report. Checked across the whole
    // document rather than at one offset, because a splice can be right at the edges and
    // wrong in the middle.
    let editor = CoordinatorFixtures.makeEditor(Self.largeDocument)
    editor.storage.replaceCharacters(in: NSRange(location: 5, length: 0), with: "\n")
    let spliced = editor.coordinator.documentBlocks

    let fresh = CoordinatorFixtures.makeEditor(editor.storage.string)
    #expect(fresh.coordinator.blocksSpanDocument)
    #expect(
      spliced.map(\.lines) == fresh.coordinator.documentBlocks.map(\.lines),
      "spliced line ranges must equal a fresh scan's")
    #expect(
      spliced.map(\.range) == fresh.coordinator.documentBlocks.map(\.range),
      "spliced offset ranges must equal a fresh scan's")
    #expect(spliced.map(\.kind) == fresh.coordinator.documentBlocks.map(\.kind))
    #expect(
      spliced.map(\.contentLines) == fresh.coordinator.documentBlocks.map(\.contentLines),
      "and so must contentLines, which `shifted(byLines:byOffset:)` moves too")
  }

  // MARK: - Geometry, through the seam rather than through a text view

  @Test("A point resolves through the view-supplied probe, and a lane point by its y")
  func pointQueriesGoThroughTheGeometrySeam() {
    // No text view here. The seam is a closure, so a test can supply the platform's
    // contracted behaviour — closest-position — and assert the coordinator's half of it.
    let editor = CoordinatorFixtures.makeEditor(Self.largeDocument)

    // A stand-in for a 20-point line height: y picks the line, x is ignored entirely,
    // which is exactly what a real closest-position call does for a point left of the text.
    editor.coordinator.utf16Offset = { point in
      let line = Int(point.y / 20)
      guard line >= 0, line < 80 * 3 - 1 else { return nil }
      return Self.paragraphStride * (line / 3) + (line % 3 == 1 ? 20 : 0)
    }

    // Paragraph 40's first line is document line 120.
    let inText = editor.coordinator.block(at: CGPoint(x: 200, y: 120 * 20))
    #expect(inText?.lines == Self.expectedLines(ofParagraph: 40))

    // The same y, but far to the left — in the well's lane, outside the text container.
    // It must resolve to the same block, and it does so without any lane-width rule here.
    let inLane = editor.coordinator.block(at: CGPoint(x: -24, y: 120 * 20))
    #expect(
      inLane?.lines == inText?.lines,
      "a point in the lane resolves by its y alone, through closest-position")
  }

  @Test("A viewport rect resolves to the blocks on screen, derived from two corner probes")
  func rectQueriesDeriveTheirRangeFromCornerProbes() {
    let editor = CoordinatorFixtures.makeEditor(Self.largeDocument)
    editor.coordinator.utf16Offset = { point in
      let line = Int(point.y / 20)
      guard line >= 0, line < 80 * 3 - 1 else { return nil }
      return Self.paragraphStride * (line / 3) + (line % 3 == 1 ? 20 : 0)
    }

    // A viewport over document lines 120 to 125 — paragraphs 40 and 41.
    let onScreen = editor.coordinator.blocks(in: CGRect(x: 0, y: 120 * 20, width: 600, height: 5 * 20))
    #expect(!onScreen.isEmpty)
    #expect(onScreen.first?.lines.lowerBound == Self.expectedLines(ofParagraph: 40).lowerBound)
    #expect(
      onScreen.allSatisfy { $0.lines.lowerBound >= 120 && $0.lines.upperBound <= 127 },
      "nothing off screen may come back; got \(onScreen.map(\.lines))")
    #expect(
      onScreen.contains { $0.kind == .blank },
      "the separator between the two paragraphs is on screen too")
  }

  @Test("A coordinator with no geometry installed says nothing rather than guessing")
  func geometryQueriesAreEmptyWithoutASeam() {
    let editor = CoordinatorFixtures.makeEditor(Self.largeDocument)
    #expect(editor.coordinator.utf16Offset == nil, "nothing was installed")
    #expect(editor.coordinator.block(at: .zero) == nil)
    #expect(editor.coordinator.blocks(in: CGRect(x: 0, y: 0, width: 100, height: 100)).isEmpty)
  }

  // MARK: - The handle, which is how a host avoids casting to the text view

  @Test("The handle forwards every query and is inert before it is attached")
  func handleForwardsQueriesAndIsInertWhenEmpty() {
    let handle = EscriboEditorHandle()
    #expect(handle.coordinator == nil, "an unattached handle holds nothing")
    #expect(handle.block(atUTF16Offset: 0) == nil, "…and answers without trapping")
    #expect(handle.block(at: .zero) == nil)
    #expect(handle.blocks(in: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)

    let editor = CoordinatorFixtures.makeEditor(Self.largeDocument)
    handle.attach(to: editor.coordinator)
    #expect(handle.coordinator === editor.coordinator)
    #expect(
      handle.block(atUTF16Offset: Self.paragraphStride * 40 + 5)?.lines
        == Self.expectedLines(ofParagraph: 40),
      "an attached handle answers exactly what the coordinator answers")
  }

  // MARK: - The internals stay internal

  @Test("The block search agrees with the record search about boundaries")
  func blockSearchMatchesTheRecordSearchIdiom() {
    // `block(containing:in:)` is deliberately the same shape as `record(containing:in:)`,
    // including the inclusive upper bound — an offset at the very end of a block is the
    // caret where a writer leaves it after typing. Asserted directly on the static helper
    // so the boundary is pinned independently of the caching around it.
    let editor = CoordinatorFixtures.makeEditor("one two\n\nthree")
    let blocks = editor.coordinator.lastBlocks
    #expect(blocks.map(\.kind) == [.paragraph, .blank, .paragraph])

    let first = blocks[0]
    #expect(EditorCoordinator.block(containing: first.range.lowerBound, in: blocks)?.range == first.range)
    #expect(
      EditorCoordinator.block(containing: first.range.upperBound, in: blocks) != nil,
      "an offset at a block's end resolves, as it does for records")
    #expect(EditorCoordinator.block(containing: -1, in: blocks) == nil)
    #expect(EditorCoordinator.block(containing: 0, in: []) == nil, "an empty array says nothing")
  }
}
