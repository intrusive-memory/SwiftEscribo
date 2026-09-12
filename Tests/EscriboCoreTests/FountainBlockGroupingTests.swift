import Testing

@testable import EscriboCore

/// Fountain **block** grouping: which runs of line records become one ``EscriboBlock``
/// (REQUIREMENTS-1.1.0 § 4.2).
///
/// ## Why every expectation here is written out by hand
///
/// For the reason `MarkdownBlockStructureTests` gives and `MarkdownBlockGroupingTests`
/// repeats: the `incrementalScan == fullScan` gate compares two runs of the same code, so
/// a grouping rule that is wrong is wrong identically on both sides and the gate stays
/// green. Every kind and every line range below is a value a human wrote down.
///
/// ## The rule this file is really about
///
/// `ScriptPreview.blocks(from:)` in the Escribir app decided where a speech ended with
/// `isContiguousWithPrevious: !sawBlankSinceLastBlock && !blocks.isEmpty`, dropping
/// `.note`, `.boneyard`, `.section`, and `.synopsis` as **neutral**. That rule now lives
/// in ``EscriboBlockGrouper/fountainBlocks(from:)`` so that the preview, the well, and
/// read-aloud cannot disagree about where a speech ends (D-8). Its one observable
/// consequence — **a note between a cue and its dialogue does not end the speech; a blank
/// line does** — is asserted three times below, from three directions, because it is the
/// assertion that would silently regress if someone "simplified" the neutral set away.
///
/// Every element sequence used as a fixture here is one already asserted by
/// `FountainGrammarTests` or `FountainRegionTests`, so a failure in this file is a
/// grouping failure and never a classification surprise.
@Suite("Fountain grammar — block grouping")
struct FountainBlockGroupingTests {

  // MARK: - Helpers

  /// Full-scans `text` and asserts every `ScanResult` invariant on the way out.
  static func fullScan(
    _ text: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> ScanResult {
    var scanner = IncrementalScanner(grammar: FountainGrammar())
    let result = scanner.fullScan(text)
    ScanInvariants.check(
      result, text: text, editedRange: nil, "fountain block grouping of \(text.debugDescription)",
      sourceLocation: sourceLocation)
    return result
  }

  /// Each block as `(kind, lines)`, which is the pair every row of the table states.
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

  // MARK: - The § 4.2 table, as a table

  static let groupingTable: [GroupingCase] = [
    // Speech: a cue plus the contiguous parentheticals and dialogue lines after it.
    GroupingCase(
      "a cue, a parenthetical, and a line of dialogue are ONE speech block",
      "BOB\n(beat)\nHello there.\n",
      [Shape(.speech, 0, 3), Shape(.blank, 3, 4)]),
    GroupingCase(
      "a cue and its dialogue with no parenthetical are one speech block",
      "R2D2\nHello.",
      [Shape(.speech, 0, 2)]),
    GroupingCase(
      "a blank line between a cue and its dialogue ENDS the speech",
      "BOB\nHello.\n\nStill speaking.",
      [Shape(.speech, 0, 2), Shape(.blank, 2, 3), Shape(.action, 3, 4)]),
    GroupingCase(
      "a second cue ends the first speech — a cue is never part of the speech above it",
      "BOB\nHello.\n\nJANE\nHi.",
      [Shape(.speech, 0, 2), Shape(.blank, 2, 3), Shape(.speech, 3, 5)]),

    // The D-8 neutrality rule.
    GroupingCase(
      "a note between dialogue lines does NOT end the speech",
      "BOB\nHello there.\n[[a note]]\nStill speaking.",
      [Shape(.speech, 0, 4)]),
    GroupingCase(
      "a boneyard between dialogue lines does NOT end the speech",
      "BOB\nHello there.\n/* struck */\nStill speaking.",
      [Shape(.speech, 0, 4)]),
    GroupingCase(
      "a note spanning two lines still does not end the speech",
      "BOB\nHello.\n[[a note\nstill the note]]\nStill speaking.",
      [Shape(.speech, 0, 5)]),

    // Action, and neutrality outside a speech.
    GroupingCase(
      "consecutive action lines group",
      "INT. HOUSE - DAY\nBob waits.\nJane enters.",
      [Shape(.sceneHeading, 0, 1), Shape(.action, 1, 3)]),
    GroupingCase(
      "a note bridges two action lines into one block",
      "INT. HOUSE - DAY\nBob waits.\n[[a note]]\nJane enters.",
      [Shape(.sceneHeading, 0, 1), Shape(.action, 1, 4)]),
    GroupingCase(
      "a note that bridges nothing is its own block, and does not swallow the action",
      "INT. HOUSE - DAY\nBob waits.\n[[a note]]\n\nCUT TO:",
      [
        Shape(.sceneHeading, 0, 1), Shape(.action, 1, 2), Shape(.note, 2, 3),
        Shape(.blank, 3, 4), Shape(.transition, 4, 5),
      ]),

    // Scene headings are one line, always.
    GroupingCase(
      "a scene heading is one line and does not group with the next one",
      "INT. HOUSE - DAY\n\n.SNIPER SCOPE POV",
      [Shape(.sceneHeading, 0, 1), Shape(.blank, 1, 2), Shape(.sceneHeading, 2, 3)]),

    // The title page, and Fountain's leading YAML region (deviation 12b).
    GroupingCase(
      "each title-page key is its own block",
      "Title: The One\nAuthor: Nobody\n\nINT. HOUSE - DAY",
      [
        Shape(.titlePage, 0, 1), Shape(.titlePage, 1, 2), Shape(.blank, 2, 3),
        Shape(.sceneHeading, 3, 4),
      ]),
    GroupingCase(
      "a leading YAML region in a Fountain document is one frontmatter block",
      "---\ntype: episode\n---\n\nCUT TO:\n\nINT. HOUSE - DAY\n",
      [
        Shape(.frontmatter, 0, 3), Shape(.blank, 3, 4), Shape(.transition, 4, 5),
        Shape(.blank, 5, 6), Shape(.sceneHeading, 6, 7), Shape(.blank, 7, 8),
      ]),
  ]

  @Test("The § 4.2 grouping table holds", arguments: groupingTable)
  func groupingTableHolds(testCase: GroupingCase) {
    #expect(Self.shape(testCase.text) == testCase.expected, "\(testCase.rule)")
  }

  // MARK: - Speech, in detail

  @Test("A cue plus a parenthetical plus dialogue is a single block of kind speech")
  func cueParentheticalAndDialogueAreOneSpeechBlock() {
    // The exit criterion, stated on its own so it can fail on its own. Two dialogue lines
    // rather than one, because a rule that grouped only the cue and the line under it
    // would pass with one.
    let result = Self.fullScan("BOB\n(beat)\nHello there.\nStill speaking.")

    #expect(
      result.lineRecords.map(\.element) == [.character, .parenthetical, .dialogue, .dialogue],
      "the fixture must really be a cue, a parenthetical, and two dialogue lines")
    #expect(result.blocks.count == 1, "cue + parenthetical + two dialogue lines is ONE block")
    #expect(result.blocks.first?.kind == .speech)
    #expect(result.blocks.first?.lines == 0..<4)
    #expect(
      result.blocks.first?.contentRanges.count == 4,
      "every line of the speech contributes its content — the cue name, the parenthetical, both lines")
  }

  @Test("A note inside a speech keeps the block whole but stays out of its content")
  func noteInsideASpeechIsNeutralAndUnspoken() {
    // The D-8 rule and its consequence for read-aloud, in one test. The note is inside
    // `lines` and inside `range`, because blocks tile; it is absent from `contentRanges`,
    // because `[[a note]]` must never be spoken aloud.
    let source = "BOB\nHello there.\n[[a note]]\nStill speaking."
    let result = Self.fullScan(source)

    #expect(result.lineRecords.map(\.element) == [.character, .dialogue, .note, .dialogue])
    #expect(result.blocks.count == 1, "a note does not end the speech")

    let speech = result.blocks.first
    #expect(speech?.kind == .speech)
    #expect(speech?.lines == 0..<4, "the note's line is inside the block, as tiling requires")
    #expect(speech?.range == 0..<source.utf16.count)
    #expect(
      speech?.contentRanges.count == 3,
      "three spoken lines, not four — the note's content is omitted")

    // Named rather than counted, so the assertion says *which* content survived.
    let spoken = (speech?.contentRanges ?? []).map { range in
      String(decoding: Array(source.utf16)[range], as: UTF16.self)
    }
    #expect(spoken == ["BOB", "Hello there.", "Still speaking."])
  }

  @Test("A blank line ends a speech where a note does not — the same document, twice")
  func blankSeparatesWhereNoteDoesNot() {
    // The two halves of the contiguity rule against each other. Asserting them as a pair
    // is the point: either one alone passes under a rule that treats every non-dialogue
    // line the same way, and only the contrast fails such a rule.
    let withNote = Self.fullScan("BOB\nHello there.\n[[a note]]\nStill speaking.")
    let withBlank = Self.fullScan("BOB\nHello there.\n\nStill speaking.")

    #expect(withNote.blocks.count == 1, "a note is neutral")
    #expect(withNote.blocks.map(\.kind) == [.speech])

    #expect(withBlank.blocks.count == 3, "a blank line separates")
    #expect(withBlank.blocks.map(\.kind) == [.speech, .blank, .action])
    #expect(withBlank.blocks.first?.lines == 0..<2, "the speech ends at the blank line")
  }

  @Test("A lyric under a cue is part of that character's speech; a lyric alone is not")
  func lyricsUnderACueAreSpeech() {
    // The judgment call, asserted so that it is a decision rather than an accident. The
    // grammar keeps the dialogue block open across a lyric, and the app's contiguity flag
    // did not treat a lyric as a separator, so a sung line under a cue belongs to that
    // speech in both.
    let sung = Self.fullScan("BOB\n~Willy Wonka, Willy Wonka")
    #expect(sung.lineRecords.map(\.element) == [.character, .lyrics])
    #expect(sung.blocks.map(\.kind) == [.speech], "a lyric under a cue is speech")
    #expect(sung.blocks.first?.lines == 0..<2)
    #expect(
      sung.blocks.first?.contentRanges.count == 2,
      "a lyric is sung, not annotated, so its content is kept")

    // With no cue above it, the same line is a lyrics block.
    let alone = Self.fullScan("INT. HOUSE - DAY\n\n~Willy Wonka, Willy Wonka")
    #expect(alone.blocks.map(\.kind) == [.sceneHeading, .blank, .lyrics])
  }

  // MARK: - A whole screenplay page

  /// Every § 4.2 element in one document, with the element sequence already asserted by
  /// `FountainGrammarTests.everyBlockElementOnOnePage`.
  ///
  /// The CRLF and the astral-plane character are in the fixture for the reason that test
  /// gives — both are where a hand-written scanner drops a code unit — and they exercise
  /// the block `range` arithmetic as well as the span tiling.
  static let screenplayPage = """
    # Act One

    = Bob finally tells the truth.

    INT. HOUSE - DAY\r
    Bob steps back. A \u{1F600} on the wall.

    ~Willy Wonka, Willy Wonka

    >THE END<

    CUT TO:

    ===

    .SNIPER SCOPE POV
    """

  @Test("Every § 4.2 element on one page groups to one block each")
  func everyElementOnOnePage() {
    let result = Self.fullScan(Self.screenplayPage)

    // The classification, restated from `FountainGrammarTests` so that a grammar change
    // fails here as a fixture error rather than as a mysterious grouping error.
    #expect(
      result.lineRecords.map(\.element) == [
        .section, .blank,
        .synopsis, .blank,
        .sceneHeading, .action, .blank,
        .lyrics, .blank,
        .centered, .blank,
        .transition, .blank,
        .pageBreak, .blank,
        .sceneHeading,
      ])

    #expect(
      Self.shape(Self.screenplayPage) == [
        Shape(.section, 0, 1), Shape(.blank, 1, 2),
        Shape(.synopsis, 2, 3), Shape(.blank, 3, 4),
        Shape(.sceneHeading, 4, 5), Shape(.action, 5, 6), Shape(.blank, 6, 7),
        Shape(.lyrics, 7, 8), Shape(.blank, 8, 9),
        Shape(.centered, 9, 10), Shape(.blank, 10, 11),
        Shape(.transition, 11, 12), Shape(.blank, 12, 13),
        Shape(.pageBreak, 13, 14), Shape(.blank, 14, 15),
        Shape(.sceneHeading, 15, 16),
      ])
  }

  // MARK: - The tiling invariant

  @Test("Fountain blocks tile a scan's lines in order, with no gaps and no overlaps")
  func blocksTileTheScan() {
    // The Fountain counterpart of `MarkdownBlockGroupingTests.blocksTileTheScan`. One
    // document carrying a title page, a leading YAML region, every block element, a
    // speech with a note inside it, and a page break, so the invariant is checked across
    // the joins between them rather than inside any one rule.
    let document = """
      ---
      type: episode
      ---

      Title: The One
      Author: Nobody

      # Act One

      = Bob finally tells the truth.

      INT. HOUSE - DAY
      Bob steps back.
      [[a note]]
      Jane enters.

      BOB
      (beat)
      Hello there.
      /* struck */
      Still speaking.

      ~Willy Wonka

      >THE END<

      CUT TO:

      ===

      .SNIPER SCOPE POV
      """
    let result = Self.fullScan(document)
    let blocks = result.blocks

    #expect(!blocks.isEmpty, "a Fountain document must produce blocks")
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
      for content in block.contentRanges {
        #expect(block.range.lowerBound <= content.lowerBound)
        #expect(content.upperBound <= block.range.upperBound)
        #expect(!content.isEmpty, "an empty content range must not be carried")
      }
    }

    // The document's one speech, found by kind rather than by index, so the assertion
    // survives an edit to the fixture above it.
    let speeches = blocks.filter { $0.kind == .speech }
    #expect(speeches.count == 1)
    #expect(
      speeches.first?.lines.count == 5,
      "cue, parenthetical, dialogue, boneyard, dialogue — the boneyard is inside the speech")
    #expect(
      speeches.first?.contentRanges.count == 4,
      "four spoken lines: the boneyard's content is omitted")
  }

  @Test("A Fountain block's line indices are document indices, not window offsets")
  func incrementalBlocksCarryDocumentLineIndices() {
    var scanner = IncrementalScanner(grammar: FountainGrammar())
    let before = "INT. HOUSE - DAY\n\nBOB\nHello there.\n\nCUT TO:"
    _ = scanner.fullScan(before)

    // "Hello there." occupies 22..<34: "INT. HOUSE - DAY\n" is 0..<17, the blank line
    // 17..<18, "BOB\n" 18..<22.
    let after = "INT. HOUSE - DAY\n\nBOB\nGoodbye now.\n\nCUT TO:"
    let result = scanner.incrementalScan(TextEdit(range: 22..<34, replacementLength: 12), in: after)

    #expect(!result.blocks.isEmpty)
    #expect(result.blocks.first?.lines.lowerBound == result.lineRecords.first?.index)
    #expect(result.blocks.last?.lines.upperBound == (result.lineRecords.last?.index).map { $0 + 1 })
    #expect(
      result.blocks.first.map { result.lines.contains($0.lines.lowerBound) } == true,
      "a block cannot begin outside the lines the result claims to cover")
  }
}
