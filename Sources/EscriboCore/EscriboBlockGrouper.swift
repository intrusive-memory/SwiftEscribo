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
    case .fountain: fountainBlocks(from: records)
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

  // MARK: - Fountain (§ 4.2)

  /// Groups a run of Fountain line records.
  ///
  /// | Element seen | Block |
  /// |---|---|
  /// | `.blank` | the whole run of blanks, one ``BlockKind/blank`` |
  /// | `.frontmatterDelimiter` | through the closing delimiter, one ``BlockKind/frontmatter`` |
  /// | `.sceneHeading` | **one line**, always — two adjacent slug lines are two blocks |
  /// | `.pageBreak` | one line |
  /// | `.character` | the cue plus its speech body — see ``speech(_:from:)`` |
  /// | `.action` | the run |
  /// | `.transition`, `.centered` | the run |
  /// | `.lyrics` | the run — **unless** it sits under a cue, where it is speech body |
  /// | `.titlePageKey` | the key plus its `.titlePageValue` continuations |
  /// | `.note`, `.boneyard`, `.section`, `.synopsis` | the run, at one depth — but only when the run stands alone; see below |
  ///
  /// ## The contiguity rule, ported from the app (D-8)
  ///
  /// `ScriptPreview.blocks(from:)` decided where a speech ended with
  /// `isContiguousWithPrevious: !sawBlankSinceLastBlock && !blocks.isEmpty`, where a
  /// `.blank` record set the flag, a `.pageBreak` emitted a non-contiguous block and set
  /// it, and `.note`, `.boneyard`, `.section`, and `.synopsis` were **dropped but
  /// neutral** — they neither joined nor separated. Moving the rule here is the whole
  /// point of § 4.2: the preview, the well, and read-aloud cannot disagree about where a
  /// speech ends if only one of them decides.
  ///
  /// The consequence that matters, and the one the tests name: **a note or a boneyard
  /// between a cue and its dialogue does not end the speech. A blank line does.** The
  /// grammar already agrees — see ``ElementKind/note``, which says a note is commentary
  /// layered over a screenplay rather than an element of one.
  ///
  /// "Neutral" is implemented as ``neutralBridge(_:from:resumingAt:)`` rather than as
  /// greedy absorption, and the difference is observable: a neutral run joins what is on
  /// both sides of it **only when the block actually resumes after it**. So
  /// `action / note / action` is one action block, while `action / note / blank` is an
  /// action block and then a note block. Greedy absorption would swallow the trailing note
  /// into the action, which is neither what the app did nor what a writer sees.
  ///
  /// A neutral line cannot *start* a block either, which is why the neutral arm is
  /// reached only when the line is not inside a run — there, it is its own block, which is
  /// the case § 4.2 describes and by far the common one.
  ///
  /// The content of an absorbed neutral line is **omitted from
  /// ``EscriboBlock/contentRanges``**: the line is inside the block's `lines` and `range`
  /// because the tiling invariant requires it, but read-aloud must not speak
  /// `[[a note]]`. That is the one place where a block's content is narrower than its
  /// lines, and it is the reason `contentRanges` is an array.
  static func fountainBlocks(from records: [LineRecord]) -> [EscriboBlock] {
    var blocks: [EscriboBlock] = []
    var cursor = 0

    while cursor < records.count {
      let element = records[cursor].element

      switch element {
      case .blank:
        cursor = append(&blocks, .blank, over: run(records, from: cursor, of: .blank), records)

      case .frontmatterDelimiter:
        // Fountain hosts a leading YAML region too (see `FountainGrammar` deviation 12b:
        // a file may write `---` metadata *and* a title page), so this is not a
        // Markdown-only arm.
        cursor = append(
          &blocks, .frontmatter,
          over: region(records, from: cursor, closedBy: .frontmatterDelimiter), records)

      case .sceneHeading:
        // One line, per § 4.2, and deliberately not a run: two slug lines in a row are two
        // scenes, and a writer who wants one scene does not write two slugs.
        cursor = append(&blocks, .sceneHeading, over: cursor..<(cursor + 1), records)

      case .pageBreak:
        // Non-contiguous in the app's rule, which here means simply: its own block, and it
        // cannot be bridged into anything.
        cursor = append(&blocks, .pageBreak, over: cursor..<(cursor + 1), records)

      case .character:
        cursor = append(
          &blocks, .speech, over: speech(records, from: cursor), records,
          omittingContentOf: neutralElements)

      case .action:
        cursor = append(
          &blocks, .action, over: bridgedRun(records, from: cursor, of: .action), records,
          omittingContentOf: neutralElements)

      case .transition:
        cursor = append(
          &blocks, .transition, over: bridgedRun(records, from: cursor, of: .transition), records,
          omittingContentOf: neutralElements)

      case .centered:
        cursor = append(
          &blocks, .centered, over: bridgedRun(records, from: cursor, of: .centered), records,
          omittingContentOf: neutralElements)

      case .lyrics:
        // A lyric run that is *not* under a cue. A lyric under one is speech — see
        // `isSpeechBody`.
        cursor = append(
          &blocks, .lyrics, over: bridgedRun(records, from: cursor, of: .lyrics), records,
          omittingContentOf: neutralElements)

      case .titlePageKey:
        cursor = append(&blocks, .titlePage, over: titlePageEntry(records, from: cursor), records)

      case .titlePageValue:
        // A continuation with no key above it — reachable at a window edge, or from a
        // title page whose first line is indented. Its own block rather than dropped.
        cursor = append(
          &blocks, .titlePage, over: run(records, from: cursor, of: .titlePageValue), records)

      case .note, .boneyard, .section, .synopsis:
        // A neutral run that bridges nothing, so it stands on its own. Grouped by depth as
        // well as by element, which matters only for `.section`: `# Act One` followed by
        // `## Scene One` is two blocks, because they are two levels of structure.
        cursor = append(
          &blocks, degradedKind(for: element),
          over: sameDepthRun(records, from: cursor, of: element), records)

      default:
        // Not part of the Fountain block vocabulary — a window edge, or an element a later
        // grammar change introduces. A run of one element becomes one block, which keeps
        // the tiling invariant true no matter what arrives.
        cursor = append(
          &blocks, degradedKind(for: element), over: run(records, from: cursor, of: element),
          records)
      }
    }

    return blocks
  }

  /// The elements that are **dropped but neutral**: they neither join nor separate a
  /// block, and their content is omitted from the block that absorbs them.
  ///
  /// Exactly the four the app's rule dropped. They are annotations layered over a
  /// screenplay rather than elements of one, which is why a note between two lines of
  /// speech leaves the speech contiguous.
  static let neutralElements: Set<ElementKind> = [.note, .boneyard, .section, .synopsis]

  /// One speech: a `.character` cue at `cue`, plus the contiguous speech-body lines that
  /// follow it, bridged across neutral annotation runs.
  ///
  /// It ends at a blank line, at the next cue, and at every other element — which is the
  /// app's `sawBlankSinceLastBlock` rule restated positively. A second cue ends the first
  /// speech because a cue is never part of the speech above it, however tightly the two
  /// are written.
  private static func speech(_ records: [LineRecord], from cue: Int) -> Range<Int> {
    var end = cue + 1
    while end < records.count {
      if isSpeechBody(records[end]) {
        end += 1
        continue
      }
      if let resumed = neutralBridge(records, from: end, resumingAt: isSpeechBody) {
        end = resumed
        continue
      }
      break
    }
    return cue..<end
  }

  /// Whether `record` is a line of a speech's body.
  ///
  /// Parentheticals and dialogue, plainly. ``ElementKind/lyrics`` too, and that is a
  /// judgment call worth naming: the grammar keeps a dialogue block **open** across a
  /// lyric line (see `ElementKind.note`, which grants lyrics the same rule), and the app's
  /// contiguity flag did not treat a lyric as a separator either — so a sung line under a
  /// cue is part of that character's speech in both, and splitting it out here would
  /// reintroduce exactly the disagreement § 4.2 exists to end. A lyric run with no cue
  /// above it is still a ``BlockKind/lyrics`` block.
  ///
  /// Unlike a neutral line, a lyric's content is **kept**: it is sung, not annotated.
  private static func isSpeechBody(_ record: LineRecord) -> Bool {
    record.element == .parenthetical || record.element == .dialogue
      || record.element == .lyrics
  }

  /// One title-page entry: a `.titlePageKey` line plus the `.titlePageValue` continuations
  /// indented under it.
  private static func titlePageEntry(_ records: [LineRecord], from key: Int) -> Range<Int> {
    var end = key + 1
    while end < records.count, records[end].element == .titlePageValue { end += 1 }
    return key..<end
  }

  // MARK: - Run finders

  /// The maximal run of `element` beginning at `start`, continuing **across** any neutral
  /// annotation run that is itself followed by another `element` line. Never empty.
  ///
  /// The "followed by" clause is the whole rule. Without it the run would greedily swallow
  /// a trailing note, and `Bob waits. / # Act Two / INT. OFFICE` would become one action
  /// block containing a section heading and reaching to the slug line.
  private static func bridgedRun(
    _ records: [LineRecord], from start: Int, of element: ElementKind
  ) -> Range<Int> {
    var end = start + 1
    while end < records.count {
      if records[end].element == element {
        end += 1
        continue
      }
      if let resumed = neutralBridge(records, from: end, resumingAt: { $0.element == element }) {
        end = resumed
        continue
      }
      break
    }
    return start..<end
  }

  /// If a run of neutral annotation lines begins at `start` and the line **after** that
  /// run satisfies `resumes`, the index of that resuming line; otherwise `nil`.
  ///
  /// Returning the resuming index rather than a `Bool` is what makes the caller's loop
  /// terminate: it advances past the whole neutral run in one step, and `resumed > start`
  /// always, so no caller can spin.
  private static func neutralBridge(
    _ records: [LineRecord], from start: Int, resumingAt resumes: (LineRecord) -> Bool
  ) -> Int? {
    var end = start
    while end < records.count, neutralElements.contains(records[end].element) { end += 1 }
    guard end > start, end < records.count, resumes(records[end]) else { return nil }
    return end
  }

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
  ///
  /// - Parameter omitted: Elements whose lines are inside the block but whose *content* is
  ///   not. Empty for every Markdown block; the Fountain neutral annotations for the
  ///   blocks that bridge across one. Such a line stays inside `lines` and `range`, because
  ///   the tiling invariant requires it, and is absent from **both**
  ///   ``EscriboBlock/contentRanges`` and ``EscriboBlock/contentLines`` — read-aloud must
  ///   not speak a `[[note]]` buried in a speech, and a per-line consumer needs to know
  ///   which line that was.
  @discardableResult
  private static func append(
    _ blocks: inout [EscriboBlock], _ kind: BlockKind, over lines: Range<Int>,
    _ records: [LineRecord], omittingContentOf omitted: Set<ElementKind> = []
  ) -> Int {
    guard let first = records[safe: lines.lowerBound], let last = records[safe: lines.upperBound - 1]
    else { return max(lines.upperBound, lines.lowerBound + 1) }

    // One filtered pass, two projections of it. `EscriboBlock.contentRanges` and
    // `contentLines` must have equal count and must agree element for element; deriving
    // both from this single array is what makes that true *by construction* rather than
    // by two filters that happen to be written the same way today.
    let spoken = records[lines].filter { record in
      !omitted.contains(record.element) && !record.contentRange.isEmpty
    }

    blocks.append(
      EscriboBlock(
        kind: kind,
        // Document line indices, taken from the records rather than from the loop's
        // cursor: on an incremental scan the window does not begin at line zero.
        lines: first.index..<(last.index + 1),
        range: first.range.lowerBound..<last.range.upperBound,
        contentRanges: spoken.map(\.contentRange),
        contentLines: spoken.map(\.index)
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
