/// The block-grouping rules: ``LineRecord`` values in, ``EscriboBlock`` values out.
///
/// A **pure function over line records**, with no access to the source text, no scanner
/// state, and no `LineState`. That is the whole design constraint and it is load-bearing
/// twice over:
///
/// 1. It makes grouping testable by writing records down, without a document.
/// 2. It makes grouping re-runnable on any window of records the scanner happens to
///    produce, which is what lets an incremental scan carry blocks at all.
///
/// The cost of the constraint is stated where it bites — see ``isSetextUnderline(_:)``,
/// the one rule that a record alone cannot decide with certainty.
///
/// ## The tiling invariant
///
/// For a non-empty, contiguous, ascending run of records, the blocks returned **tile it
/// exactly**: in ascending order, no gaps, no overlaps, every line in exactly one block,
/// and the first and last block's `range` bounds equal to the first and last record's.
/// Blank runs are blocks for this reason and no other — a gap would make an
/// offset-to-block lookup a search plus a fallback, and the fallback is where the bugs
/// would live.
enum EscriboBlockGrouper {

  /// Groups `records` according to `dialect`.
  ///
  /// - Parameters:
  ///   - records: A contiguous, ascending run of line records — a whole document for a
  ///     full scan, or the rescanned window for an incremental one.
  ///   - dialect: Which grouping vocabulary to apply. ``BlockDialect/none`` returns no
  ///     blocks, which is the honest answer for a language that has no block structure.
  /// - Returns: The blocks, in ascending line order.
  static func blocks(from records: [LineRecord], dialect: BlockDialect) -> [EscriboBlock] {
    switch dialect {
    case .markdown: markdownBlocks(from: records)
    case .fountain: []  // Fountain grouping lands with § 4.2; the vocabulary is already declared.
    case .none: []
    }
  }

  // MARK: - Markdown (§ 4.1)

  /// Groups a run of Markdown line records.
  ///
  /// The rules, in the order the loop tries them:
  ///
  /// | Element seen | Block |
  /// |---|---|
  /// | `.blank` | the whole run of blanks, one ``BlockKind/blank`` |
  /// | `.frontmatterDelimiter` | through the closing delimiter, one ``BlockKind/frontmatter`` |
  /// | `.codeFence` | through the closing fence **whatever is inside it**, one ``BlockKind/codeBlock`` |
  /// | `.codeBlock` | the run, one ``BlockKind/codeBlock`` (indented code) |
  /// | `.thematicBreak` | one line |
  /// | `.heading` | one line (an ATX heading; a setext underline is reached from the paragraph rule) |
  /// | `.blockquote` | the run **at the same depth** |
  /// | a list-item marker | the marker line plus its `.paragraph` continuations — **one block per item** |
  /// | `.tableDelimiterRow` | the delimiter plus its `.tableRow` body |
  /// | `.paragraph` | the run, then whatever ends it decides the kind — see below |
  ///
  /// The paragraph rule is the only one with three outcomes, because in Markdown a run of
  /// prose does not know what it is until the line after it:
  ///
  /// - ended by a setext underline: the run **and** the underline are one
  ///   ``BlockKind/heading``. The whole run, not just the last line, because that is what
  ///   CommonMark makes the heading.
  /// - ended by a table delimiter row: the run's **last** line is the table's header, so it
  ///   leaves the paragraph and joins the ``BlockKind/table``. A one-line run yields no
  ///   paragraph block at all.
  /// - ended by anything else, or by nothing: one ``BlockKind/paragraph``.
  static func markdownBlocks(from records: [LineRecord]) -> [EscriboBlock] {
    var blocks: [EscriboBlock] = []
    var cursor = 0

    while cursor < records.count {
      let element = records[cursor].element

      switch element {
      case .blank:
        cursor = append(&blocks, .blank, over: run(records, from: cursor, of: .blank), records)

      case .frontmatterDelimiter:
        cursor = append(
          &blocks, .frontmatter,
          over: region(records, from: cursor, closedBy: .frontmatterDelimiter), records)

      case .codeFence:
        // Everything between the fences belongs to the fence regardless of how it
        // classified — a fence tagged `fountain` is scanned with the Fountain grammar, so
        // the lines inside it are not `.codeBlock` and a rule that looked for `.codeBlock`
        // would end the block at the first one.
        cursor = append(
          &blocks, .codeBlock, over: region(records, from: cursor, closedBy: .codeFence), records)

      case .codeBlock:
        cursor = append(
          &blocks, .codeBlock, over: run(records, from: cursor, of: .codeBlock), records)

      case .thematicBreak:
        cursor = append(&blocks, .thematicBreak, over: cursor..<(cursor + 1), records)

      case .heading:
        cursor = append(&blocks, .heading, over: cursor..<(cursor + 1), records)

      case .blockquote:
        cursor = append(
          &blocks, .blockquote,
          over: sameDepthRun(records, from: cursor, of: .blockquote), records)

      case .unorderedListItem, .orderedListItem:
        // The marker line plus its continuations. A continuation of a list item is a
        // `.paragraph` record carrying the item's depth (see `ElementKind`), and the item
        // ends at a blank line, at the next marker, or at any other element.
        var end = cursor + 1
        while end < records.count, records[end].element == .paragraph { end += 1 }
        cursor = append(&blocks, .listItem, over: cursor..<end, records)

      case .tableDelimiterRow:
        cursor = append(&blocks, .table, over: tableBody(records, from: cursor), records)

      case .paragraph:
        cursor = appendParagraphRun(&blocks, records, from: cursor)

      default:
        // Not part of the Markdown block vocabulary. Reached only at a window edge or from
        // a Fountain construct that escaped a fence, and it degrades rather than dropping
        // lines: a run of one element becomes one block, which keeps the tiling invariant
        // true no matter what arrives.
        cursor = append(
          &blocks, degradedKind(for: element), over: run(records, from: cursor, of: element), records)
      }
    }

    return blocks
  }

  /// Emits the block for a run of `.paragraph` records starting at `start`, and returns
  /// the index to continue from.
  private static func appendParagraphRun(
    _ blocks: inout [EscriboBlock], _ records: [LineRecord], from start: Int
  ) -> Int {
    var end = start + 1
    while end < records.count, records[end].element == .paragraph { end += 1 }

    guard end < records.count else {
      return append(&blocks, .paragraph, over: start..<end, records)
    }

    if isSetextUnderline(records[end]) {
      return append(&blocks, .heading, over: start..<(end + 1), records)
    }

    if records[end].element == .tableDelimiterRow {
      // GFM recognizes a header row only by the delimiter row beneath it, which the
      // grammar cannot see from the header's own line — so the header arrives as a
      // `.paragraph` and is reunited with its table here.
      if end - 1 > start {
        _ = append(&blocks, .paragraph, over: start..<(end - 1), records)
      }
      return append(&blocks, .table, over: tableBody(records, from: end, header: end - 1), records)
    }

    return append(&blocks, .paragraph, over: start..<end, records)
  }

  // MARK: - Run finders

  /// The maximal run of `element` beginning at `start`. Never empty.
  private static func run(
    _ records: [LineRecord], from start: Int, of element: ElementKind
  ) -> Range<Int> {
    var end = start + 1
    while end < records.count, records[end].element == element { end += 1 }
    return start..<end
  }

  /// The maximal run of `element` beginning at `start` **at `start`'s depth**. Never empty.
  private static func sameDepthRun(
    _ records: [LineRecord], from start: Int, of element: ElementKind
  ) -> Range<Int> {
    let depth = records[start].depth
    var end = start + 1
    while end < records.count, records[end].element == element, records[end].depth == depth {
      end += 1
    }
    return start..<end
  }

  /// A delimited region: `start`, everything after it, and the next `delimiter` line,
  /// inclusive — or to the end of the records if the region never closes.
  ///
  /// An unterminated fence or frontmatter region running to the end of the document is
  /// exactly what the scanner does with it, so it is what grouping does with it too.
  private static func region(
    _ records: [LineRecord], from start: Int, closedBy delimiter: ElementKind
  ) -> Range<Int> {
    var end = start + 1
    while end < records.count {
      let isCloser = records[end].element == delimiter
      end += 1
      if isCloser { break }
    }
    return start..<end
  }

  /// A table: an optional header line, the delimiter row at `delimiter`, and the
  /// `.tableRow` body that follows.
  private static func tableBody(
    _ records: [LineRecord], from delimiter: Int, header: Int? = nil
  ) -> Range<Int> {
    var end = delimiter + 1
    while end < records.count, records[end].element == .tableRow { end += 1 }
    return (header ?? delimiter)..<end
  }

  // MARK: - The one uncertain rule

  /// Whether `record` is a **setext underline** rather than an ATX heading.
  ///
  /// Only ever asked of a record that directly follows a `.paragraph` run, which is what
  /// makes the answer reliable in practice: `scanSetextUnderline` is reachable only with an
  /// open paragraph above it, so under a paragraph an underline is the overwhelmingly
  /// likely reading.
  ///
  /// It is nonetheless a **heuristic**, and this is where the pure-function constraint
  /// bites. A setext underline's record is `.heading` with an empty content range and a
  /// depth of 1 (`===`) or 2 (`---`); so is the record of a bare `##` with no heading text.
  /// Telling them apart needs the line's first code unit, which a record does not carry.
  /// The two collide only for a text-free `#` or `##` written flush against a paragraph
  /// line, and the cost of being wrong is that one heading block covers one line too many —
  /// so the heuristic is preferred to widening ``LineRecord``, which is public API.
  private static func isSetextUnderline(_ record: LineRecord) -> Bool {
    record.element == .heading && record.contentRange.isEmpty
      && (record.depth == 1 || record.depth == 2)
  }

  // MARK: - Assembly

  /// Appends the block covering `lines` — **indices into `records`**, not document line
  /// indices — and returns the index to continue from.
  @discardableResult
  private static func append(
    _ blocks: inout [EscriboBlock], _ kind: BlockKind, over lines: Range<Int>,
    _ records: [LineRecord]
  ) -> Int {
    guard let first = records[safe: lines.lowerBound], let last = records[safe: lines.upperBound - 1]
    else { return max(lines.upperBound, lines.lowerBound + 1) }

    blocks.append(
      EscriboBlock(
        kind: kind,
        // Document line indices, taken from the records rather than from the loop's
        // cursor: on an incremental scan the window does not begin at line zero.
        lines: first.index..<(last.index + 1),
        range: first.range.lowerBound..<last.range.upperBound,
        contentRanges: records[lines].map(\.contentRange).filter { !$0.isEmpty }
      ))
    return lines.upperBound
  }

  /// The block kind a stray element degrades to, for the `default` arm only.
  private static func degradedKind(for element: ElementKind) -> BlockKind {
    switch element {
    case .sceneHeading: .sceneHeading
    case .action: .action
    case .character, .dialogue, .parenthetical: .speech
    case .transition: .transition
    case .centered: .centered
    case .lyrics: .lyrics
    case .note: .note
    case .boneyard: .boneyard
    case .section: .section
    case .synopsis: .synopsis
    case .pageBreak: .pageBreak
    case .titlePageKey, .titlePageValue: .titlePage
    case .tableRow: .table
    case .frontmatter: .frontmatter
    default: .paragraph
    }
  }
}

/// Which block-grouping vocabulary a grammar's line records should be grouped with.
///
/// Internal, and a property of the *grammar* rather than of the ``Language``, because the
/// grouper runs inside ``IncrementalScanner`` — which is generic over ``LineGrammar`` and
/// has never heard of `Language`.
enum BlockDialect: Sendable {
  /// CommonMark and its GFM extensions (§ 4.1).
  case markdown

  /// Fountain (§ 4.2).
  case fountain

  /// A language with no block structure worth grouping. Plain text, and the default, so
  /// that no existing grammar and no future one has to mention it.
  case none
}

extension Array {
  /// Bounds-checked subscript, so that assembling a block cannot trap on a malformed
  /// range. This is reached from the scan path, and the scan path does not trap.
  fileprivate subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
