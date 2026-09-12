import Testing

@testable import EscriboCore

/// Markdown **block** grouping: which runs of line records become one
/// ``EscriboBlock`` (REQUIREMENTS-1.1.0 § 4.1, and § 7 test 1).
///
/// ## Why every expectation here is written out by hand
///
/// For the reason `MarkdownBlockStructureTests` gives: the `incrementalScan == fullScan`
/// gate compares two runs of the same code, so a grouping rule that is wrong is wrong
/// identically on both sides and the gate stays green. Every kind and every line range
/// below is a value a human wrote down. Do not replace one with a comparison against
/// another scan.
///
/// ## The fixture that matters
///
/// § 7 test 1 names a specific document: the overview of Sonido's `REQUIREMENTS.md`,
/// whose lines 20–25 and 27–33 must each group to **exactly one** block. That is the
/// hard-wrapped-prose case the paragraph well exists to serve, and the shape that a
/// naive "one line, one block" implementation gets wrong six and seven times over. It is
/// reproduced verbatim in ``sonidoOverview``.
@Suite("Markdown grammar — block grouping")
struct MarkdownBlockGroupingTests {

  // MARK: - Helpers

  /// Full-scans `text` and asserts every `ScanResult` invariant on the way out.
  static func fullScan(
    _ text: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> ScanResult {
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    let result = scanner.fullScan(text)
    ScanInvariants.check(
      result, text: text, editedRange: nil, "markdown block grouping of \(text.debugDescription)",
      sourceLocation: sourceLocation)
    return result
  }

  /// Each block as `(kind, lines)`, which is the pair every row of the table below states.
  static func shape(
    _ text: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> [Shape] {
    fullScan(text, sourceLocation: sourceLocation).blocks.map {
      Shape($0.kind, $0.lines.lowerBound, $0.lines.upperBound)
    }
  }

  /// One expected block: its kind and its half-open line range.
  struct Shape: Sendable, Equatable, CustomStringConvertible {
    let kind: BlockKind
    let lowerBound: Int
    let upperBound: Int

    init(_ kind: BlockKind, _ lowerBound: Int, _ upperBound: Int) {
      self.kind = kind
      self.lowerBound = lowerBound
      self.upperBound = upperBound
    }

    var description: String { "\(kind.rawValue) \(lowerBound)..<\(upperBound)" }
  }

  /// One row of the grouping table.
  struct GroupingCase: Sendable, CustomStringConvertible {
    let rule: String
    let text: String
    let expected: [Shape]

    init(_ rule: String, _ text: String, _ expected: [Shape]) {
      self.rule = rule
      self.text = text
      self.expected = expected
    }

    var description: String { rule }
  }

  // MARK: - The § 4.1 table, as a table

  static let groupingTable: [GroupingCase] = [
    // paragraph: consecutive `.paragraph` lines, ended by a blank line or any other element
    GroupingCase(
      "a paragraph run ends at a blank line",
      "first\nsecond\n\nthird",
      [Shape(.paragraph, 0, 2), Shape(.blank, 2, 3), Shape(.paragraph, 3, 4)]),
    GroupingCase(
      "a paragraph run ends at any other element",
      "prose\n# Heading\nmore prose",
      [Shape(.paragraph, 0, 1), Shape(.heading, 1, 2), Shape(.paragraph, 2, 3)]),
    GroupingCase(
      "a run of blank lines is one block, so the blocks tile the document",
      "prose\n\n\n\nmore",
      [Shape(.paragraph, 0, 1), Shape(.blank, 1, 4), Shape(.paragraph, 4, 5)]),

    // heading: one ATX heading line, or a setext pair
    GroupingCase(
      "an ATX heading is one block on its own",
      "# Heading",
      [Shape(.heading, 0, 1)]),
    GroupingCase(
      "a setext pair — text plus `===` — is ONE heading block, not a paragraph and a heading",
      "Title\n=====\nprose",
      [Shape(.heading, 0, 2), Shape(.paragraph, 2, 3)]),
    GroupingCase(
      "a setext pair underlined with `---` is one heading block too",
      "Title\n---\nprose",
      [Shape(.heading, 0, 2), Shape(.paragraph, 2, 3)]),

    // list item: the marker line plus its continuations. Each item is its own block.
    GroupingCase(
      "each bullet is its own block — three items are three blocks, never one list",
      "- one\n- two\n- three",
      [Shape(.listItem, 0, 1), Shape(.listItem, 1, 2), Shape(.listItem, 2, 3)]),
    GroupingCase(
      "a list item absorbs its indented continuation line",
      "- one\n  continued\n- two",
      [Shape(.listItem, 0, 2), Shape(.listItem, 2, 3)]),
    GroupingCase(
      "a nested bullet is its own block, not part of its parent",
      "- outer\n  - inner",
      [Shape(.listItem, 0, 1), Shape(.listItem, 1, 2)]),
    GroupingCase(
      "a list item ends at a blank line",
      "- one\n\nprose",
      [Shape(.listItem, 0, 1), Shape(.blank, 1, 2), Shape(.paragraph, 2, 3)]),

    // blockquote: consecutive `.blockquote` lines at the same depth
    GroupingCase(
      "consecutive blockquote lines at the same depth are one block",
      "> a\n> b\n\n> c",
      [Shape(.blockquote, 0, 2), Shape(.blank, 2, 3), Shape(.blockquote, 3, 4)]),
    GroupingCase(
      "a change of blockquote depth starts a new block",
      "> a\n> > b",
      [Shape(.blockquote, 0, 1), Shape(.blockquote, 1, 2)]),

    // code block: the whole fence, and indented code
    GroupingCase(
      "a fenced code block is one block, opener through closer",
      "```\ncode\n```\nprose",
      [Shape(.codeBlock, 0, 3), Shape(.paragraph, 3, 4)]),
    GroupingCase(
      "an unterminated fence is one block running to the end of the document",
      "```\ncode\nmore",
      [Shape(.codeBlock, 0, 3)]),
    GroupingCase(
      "a run of indented code lines is one block",
      "    code\n    more",
      [Shape(.codeBlock, 0, 2)]),

    // table, frontmatter, thematic break
    GroupingCase(
      "a table is its header, its delimiter row, and its body — one block",
      "| a | b |\n|---|---|\n| 1 | 2 |\nprose",
      [Shape(.table, 0, 3), Shape(.paragraph, 3, 4)]),
    GroupingCase(
      "leading frontmatter is one block, delimiters included",
      "---\ntitle: x\n---\nprose",
      [Shape(.frontmatter, 0, 3), Shape(.paragraph, 3, 4)]),
    GroupingCase(
      "a thematic break is one block and does not swallow the prose around it",
      "prose\n\n***\nmore",
      [
        Shape(.paragraph, 0, 1), Shape(.blank, 1, 2), Shape(.thematicBreak, 2, 3),
        Shape(.paragraph, 3, 4),
      ]),
  ]

  @Test("The § 4.1 grouping table holds", arguments: groupingTable)
  func groupingTableHolds(testCase: GroupingCase) {
    #expect(Self.shape(testCase.text) == testCase.expected, "\(testCase.rule)")
  }

  // MARK: - § 7 test 1: the Sonido overview fixture

  /// Sonido `REQUIREMENTS.md` lines 20–33, verbatim: a six-line hard-wrapped paragraph, a
  /// blank line, and a seven-line hard-wrapped paragraph.
  ///
  /// Verbatim on purpose. The point of the fixture is that it is real prose someone
  /// actually wrote — em dashes, a bracketed link, a backticked identifier, section signs,
  /// a line opening with `*` and a line opening with `**` — and that none of those makes
  /// the scanner break the run. A synthetic `"a\nb\nc"` fixture would pass while every one
  /// of those characters was mishandled.
  static let sonidoOverview = """
    Where those come from is not Sonido's concern. A **connector** supplies both,
    behind a contract specified in
    [REQUIREMENTS_Connectors.md](REQUIREMENTS_Connectors.md), cited here as
    *Connectors §n*. This document covers the app: the playlist it consumes, how it
    plays and caches, and what the listener sees. §5 states what the app owes the
    connector boundary.

    **The first build is locked to one playlist: the `granville` playlist we
    supply.** Its URL is built into the app (Connectors §3), and the listener
    cannot enter, change, or add a playlist or source. This is a development
    provision to keep the first build simple, not the shipped product: the
    published app will not be limited to a single built-in URL (§10). There is no
    identity in v1: no accounts, no sign-in, and nothing that varies by who is
    listening.
    """

  /// Lines 27–33 of the same file — the seven-line run on its own, so that the § 7
  /// test-1 assertion can be made about a document that is nothing else.
  static let sonidoSecondRun = """
    **The first build is locked to one playlist: the `granville` playlist we
    supply.** Its URL is built into the app (Connectors §3), and the listener
    cannot enter, change, or add a playlist or source. This is a development
    provision to keep the first build simple, not the shipped product: the
    published app will not be limited to a single built-in URL (§10). There is no
    identity in v1: no accounts, no sign-in, and nothing that varies by who is
    listening.
    """

  @Test("The Sonido overview groups to one block per hard-wrapped run, blank between")
  func sonidoOverviewGroupsToOneBlockPerRun() {
    let result = Self.fullScan(Self.sonidoOverview)

    // Fourteen lines in, three blocks out. The six-line run and the seven-line run are
    // each ONE block — the § 7 test-1 criterion, stated as the whole document's shape so
    // that a rule which merged the two runs across the blank line also fails here.
    #expect(result.lineRecords.count == 14)
    #expect(
      Self.shape(Self.sonidoOverview) == [
        Shape(.paragraph, 0, 6), Shape(.blank, 6, 7), Shape(.paragraph, 7, 14),
      ])

    // The two runs, named, so a failure says which one broke.
    let runs = result.blocks.filter { $0.kind == .paragraph }
    #expect(runs.count == 2, "two paragraph blocks, not eight and not one")
    #expect(runs.first?.lines == 0..<6, "the six-line run is one block")
    #expect(runs.last?.lines == 7..<14, "the seven-line run is one block")

    // Every line of each run contributes its content, markers excluded — which is what
    // read-aloud will speak and what a naive single-range block could not express.
    #expect(runs.first?.contentRanges.count == 6)
    #expect(runs.last?.contentRanges.count == 7)
  }

  @Test("A seven-line hard-wrapped paragraph on its own is exactly one block")
  func sevenLineHardWrappedParagraphIsOneBlock() {
    // The § 7 test-1 assertion in its smallest form: the seven-line run alone, nothing
    // else in the document, `blocks.count == 1`. Separate from the fixture test above
    // because this is the assertion the well's hover lane depends on directly, and it
    // must be able to fail on its own.
    let result = Self.fullScan(Self.sonidoSecondRun)

    #expect(result.lineRecords.count == 7, "the fixture slice must really be seven lines")
    #expect(result.blocks.count == 1, "seven hard-wrapped lines are ONE paragraph block")
    #expect(result.blocks.first?.kind == .paragraph)
    #expect(result.blocks.first?.lines == 0..<7)
    #expect(
      result.blocks.first?.range == 0..<Self.sonidoSecondRun.utf16.count,
      "the block's range runs from the first line's start to the last line's end")
  }

  // MARK: - The tiling invariant

  @Test("Blocks tile a scan's lines in order, with no gaps and no overlaps")
  func blocksTileTheScan() {
    // One document carrying every construct the § 4.1 table names, so that the invariant
    // is checked across the joins between them rather than inside any one rule.
    let document = """
      ---
      title: everything
      ---

      # Heading

      Setext title
      ============

      A hard-wrapped run
      that continues here.

      - one
      - two
        continued

      > quoted
      > still quoted

      ```
      fenced code
      ```

      | a | b |
      |---|---|
      | 1 | 2 |

      ***

      Last word.
      """
    let result = Self.fullScan(document)
    let blocks = result.blocks

    #expect(!blocks.isEmpty)
    #expect(blocks.first?.lines.lowerBound == result.lines.lowerBound)
    #expect(blocks.last?.lines.upperBound == result.lines.upperBound)
    #expect(blocks.first?.range.lowerBound == result.dirtyRange.lowerBound)
    #expect(blocks.last?.range.upperBound == result.dirtyRange.upperBound)

    for (previous, next) in zip(blocks, blocks.dropFirst()) {
      #expect(
        previous.lines.upperBound == next.lines.lowerBound,
        "a gap or overlap between \(previous.kind.rawValue) and \(next.kind.rawValue)")
      #expect(
        previous.range.upperBound == next.range.lowerBound,
        "a UTF-16 gap or overlap between \(previous.kind.rawValue) and \(next.kind.rawValue)")
    }
    for block in blocks {
      #expect(!block.lines.isEmpty, "\(block.kind.rawValue) covers no lines")
      // Content is inside the block, and markers are excluded by `LineRecord` rather
      // than re-derived here.
      for content in block.contentRanges {
        #expect(block.range.lowerBound <= content.lowerBound)
        #expect(content.upperBound <= block.range.upperBound)
        #expect(!content.isEmpty, "an empty content range must not be carried")
      }
    }
  }

  @Test("A block's line indices are document indices, not offsets into the rescan window")
  func incrementalBlocksCarryDocumentLineIndices() {
    // The one property of blocks an incremental scan can break: a window that starts at
    // line five must produce blocks whose `lines` start at five. Asserted through the
    // record indices of the same result, which the gate already proves correct.
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    let before = "one\ntwo\nthree\n\nfour\nfive\nsix"
    _ = scanner.fullScan(before)

    let after = "one\ntwo\nthree\n\nfour\nFIVE\nsix"
    // `five` occupies 20..<24: "one\n" is 0..<4, "two\n" 4..<8, "three\n" 8..<14,
    // the blank line 14..<15, "four\n" 15..<20.
    let edit = TextEdit(range: 20..<24, replacementLength: 4)
    let result = scanner.incrementalScan(edit, in: after)

    #expect(!result.blocks.isEmpty)
    #expect(result.blocks.first?.lines.lowerBound == result.lineRecords.first?.index)
    #expect(result.blocks.last?.lines.upperBound == (result.lineRecords.last?.index).map { $0 + 1 })
    #expect(
      result.blocks.first.map { result.lines.contains($0.lines.lowerBound) } == true,
      "a block cannot begin outside the lines the result claims to cover")
  }

  // MARK: - A grammar with no block structure produces nothing

  @Test("A grammar with no block dialect produces no blocks rather than wrong ones")
  func grammarsWithoutABlockDialectProduceNoBlocks() {
    // `TextGrammar` recognizes nothing and its `blockDialect` is the protocol's `.none`
    // default. Empty is the honest answer for a language with no block structure, and it
    // must be *empty* rather than one block per line: a consumer that drew a well lane
    // from these would be drawing structure the scanner never found.
    var text = IncrementalScanner(grammar: TextGrammar())
    let plain = text.fullScan("a\nb\n\nc")
    #expect(!plain.lineRecords.isEmpty, "the scan itself must still be total")
    #expect(plain.blocks.isEmpty)

    // The other half of this test asserted, until § 4.2 shipped, that Fountain produced
    // no blocks — a deliberate tripwire on the seam. It now asserts the opposite, and it
    // stays here rather than moving so that the two dialects are compared in one place:
    // `.none` means empty, and a real dialect never does.
    var fountain = IncrementalScanner(grammar: FountainGrammar())
    let screenplay = fountain.fullScan("INT. HOUSE - DAY\n\nBob waits.")
    #expect(!screenplay.blocks.isEmpty, "Fountain grouping shipped; blocks must not be empty")
    #expect(
      screenplay.blocks.map(\.kind) == [.sceneHeading, .blank, .action],
      "and they must be the right blocks, not merely present")
  }
}
