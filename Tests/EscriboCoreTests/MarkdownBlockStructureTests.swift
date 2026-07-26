import Testing

@testable import EscriboCore

/// CommonMark **block** structure: indented code, lists and their nesting, blockquotes,
/// thematic breaks, and setext heading underlines.
///
/// ## Why every expectation here is written out by hand
///
/// `ScanGateTests`'s `incrementalScan == fullScan` property **cannot** catch a bug in this
/// grammar — both sides of its comparison run the same grammar, so a grammar that forgets
/// a piece of its state is wrong identically on both sides and the comparison stays green.
/// Sortie 5 demonstrated it against its own interest: breaking the in-fence flag turned six
/// direct classification tests red and left the gate green.
///
/// So nothing in this file infers a classification from a green gate. Every element, every
/// depth, and every span range below is a value a human wrote down and did not read out of
/// a scanner. Do not replace one with a comparison against another scan.
@Suite("Markdown grammar — CommonMark block structure")
struct MarkdownBlockStructureTests {

  // MARK: - Helpers

  /// Full-scans `text` **and asserts every `ScanResult` invariant on the way out**.
  static func fullScan(
    _ text: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> ScanResult {
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    let result = scanner.fullScan(text)
    ScanInvariants.check(
      result, text: text, editedRange: nil, "markdown block scan of \(text.debugDescription)",
      sourceLocation: sourceLocation)
    return result
  }

  /// Every line's element, in order.
  static func elements(_ text: String, sourceLocation: SourceLocation = #_sourceLocation)
    -> [ElementKind]
  {
    fullScan(text, sourceLocation: sourceLocation).lineRecords.map(\.element)
  }

  /// Every line's depth, in order.
  static func depths(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) -> [Int] {
    fullScan(text, sourceLocation: sourceLocation).lineRecords.map(\.depth)
  }

  /// The UTF-16 code units of `text`, which is the only coordinate space this grammar
  /// works in.
  static func units(_ text: String) -> [UInt16] { Array(text.utf16) }

  // MARK: - Visual columns: code units, and a four-column tab stop

  @Test("A tab advances to the next four-column stop, from column 0 and from column 2")
  func tabsAdvanceToTheNextFourColumnStop() {
    // The exact criterion, stated twice because the two halves fail for different
    // reasons: a tab width of ONE gets the first wrong, and a tab width of FOUR added
    // rather than snapped gets the second wrong.
    #expect(
      MarkdownGrammar.visualColumn(of: Self.units("\t"), upTo: 1) == 4,
      "a tab at column 0 must advance to column 4")
    #expect(
      MarkdownGrammar.visualColumn(of: Self.units("  \t"), upTo: 3) == 4,
      "a tab at column 2 must advance to column 4, not to column 6")

    // The rest of the stop table, which is what makes the two above a rule rather than
    // two constants that happen to hold.
    #expect(MarkdownGrammar.visualColumn(of: Self.units(" \t"), upTo: 2) == 4, "column 1")
    #expect(MarkdownGrammar.visualColumn(of: Self.units("   \t"), upTo: 4) == 4, "column 3")
    #expect(
      MarkdownGrammar.visualColumn(of: Self.units("    \t"), upTo: 5) == 8,
      "a tab already at a stop advances a full four columns")
    #expect(MarkdownGrammar.visualColumn(of: Self.units("\t\t"), upTo: 2) == 8, "two stops")

    // Clamping rather than trapping, because this is the scan path.
    #expect(MarkdownGrammar.visualColumn(of: Self.units("ab"), upTo: 99) == 2)
    #expect(MarkdownGrammar.visualColumn(of: Self.units("ab"), upTo: -5) == 0)
  }

  @Test("A tab stop decides indented code, so the four-column rule is observable")
  func tabStopsDecideIndentedCode() {
    // The same rule as above, seen through a classification rather than through the
    // arithmetic — a tab width of one makes both of these paragraphs.
    #expect(Self.elements("\tcode") == [.codeBlock], "one tab is four columns: code")
    #expect(
      Self.elements("  \tcode") == [.codeBlock],
      "two spaces then a tab is four columns: code")
    #expect(Self.elements("   code") == [.paragraph], "three columns is not enough")
    #expect(Self.elements("    code") == [.codeBlock], "four spaces is code")
  }

  @Test("An emoji counts two columns, because a column is a UTF-16 code unit")
  func columnsCountCodeUnitsNotCharacters() {
    // THE criterion this suite exists to make un-fakeable. A grammar that counted
    // `Character`s is correct on every ASCII document — which is why it survives casual
    // testing — and wrong on every document with an emoji in it. Each expectation below
    // is one a character-counting implementation FAILS: it would answer 1, 2, and 4.
    let emoji = Self.units("😀")
    #expect(emoji.count == 2, "the fixture is only meaningful if this is a surrogate pair")
    #expect(
      MarkdownGrammar.visualColumn(of: emoji, upTo: 2) == 2,
      "one emoji is two code units and therefore two columns, not one")

    #expect(
      MarkdownGrammar.visualColumn(of: Self.units("😀😀"), upTo: 4) == 4,
      "two emoji are four columns, not two")

    // And the interaction that makes it matter: a tab after an emoji snaps to the stop
    // measured in code units. Counting characters puts the emoji at column 2 and lands
    // the tab at column 4; counting code units puts it at column 4 and lands the tab at
    // column 8.
    #expect(
      MarkdownGrammar.visualColumn(of: Self.units("😀😀\t"), upTo: 5) == 8,
      "an emoji before a tab must not shift the tab's stop by counting characters")

    // A surrogate pair is never split by the measurement itself: measuring to the middle
    // of one is a caller error the function answers rather than traps on, and it answers
    // with the high surrogate's own column.
    #expect(MarkdownGrammar.visualColumn(of: emoji, upTo: 1) == 1)
  }

  @Test("Emoji in a list document shift offsets by two code units, never by one")
  func emojiShiftOffsetsByCodeUnits() {
    // The same claim, asserted end to end: every span offset below was computed by hand
    // from the UTF-16 length of the emoji, so a scanner that measured characters anywhere
    // would put the second line's marker one unit early.
    let text = "- 😀 item\n  - nested\n"
    let result = Self.fullScan(text)

    #expect(
      Self.units("- 😀 item\n").count == 10,
      "ten code units — the nine a character count would report is the bug")
    #expect(result.lineRecords.map(\.element) == [.unorderedListItem, .unorderedListItem, .blank])
    #expect(result.lineRecords.map(\.depth) == [0, 1, 0])

    #expect(result.lineRecords[0].contentRange == 2..<9, "the emoji is two units of content")
    #expect(result.lineRecords[1].range == 10..<21)
    #expect(result.lineRecords[1].contentRange == 14..<20)
    #expect(result.spans[0].range == 0..<2, "the first marker")
    #expect(result.spans[0].kind == .listItem)
    #expect(result.spans[0].role == .marker)

    // The nested marker: line 1 starts at 10, its indent is two spaces, and its bullet
    // plus the space after it runs to 14.
    let nestedMarker = result.spans.first { $0.range.lowerBound == 12 }
    #expect(nestedMarker?.range == 12..<14)
    #expect(nestedMarker?.role == .marker)
  }

  // MARK: - Lists

  @Test("A three-level nested list yields depth 0, 1, 2")
  func threeLevelNestingYieldsDepthZeroOneTwo() {
    let text = """
      - a
        - b
          - c
      """
    let result = Self.fullScan(text)
    #expect(result.lineRecords.map(\.depth) == [0, 1, 2], "the exact criterion")
    #expect(
      result.lineRecords.map(\.element)
        == [.unorderedListItem, .unorderedListItem, .unorderedListItem])

    // Content ranges, hand-computed: "- a\n" is four units and "  - b\n" is six, so the
    // three lines begin at 0, 4, and 10 and their text at 2, 8, and 16.
    #expect(result.lineRecords[0].contentRange == 2..<3)
    #expect(result.lineRecords[1].contentRange == 8..<9)
    #expect(result.lineRecords[2].contentRange == 16..<17)
  }

  @Test("Un-nesting walks the depth back down, one item at a time")
  func unNestingWalksDepthBackDown() {
    // Nesting on its own passes for a grammar that only ever increments. Coming back out
    // is what proves a real stack: `- d` is a sibling of `- b` and `- e` is a sibling of
    // `- a`, and nothing on either line says how far to pop except its own column.
    let text = """
      - a
        - b
          - c
        - d
      - e
      """
    #expect(Self.depths(text) == [0, 1, 2, 1, 0])
  }

  @Test("Ordered list items are their own element and nest with unordered ones")
  func orderedListsNest() {
    #expect(Self.elements("1. one") == [.orderedListItem])
    #expect(Self.elements("1) one") == [.orderedListItem])
    #expect(Self.elements("- one") == [.unorderedListItem])
    #expect(Self.elements("+ one") == [.unorderedListItem])
    #expect(Self.elements("* one") == [.unorderedListItem])

    // The blank line is load-bearing and not decoration: without it, `2. two` cannot
    // interrupt the open paragraph inside the bullet item, and CommonMark reads it as a
    // lazy continuation of that paragraph rather than as a new item. See
    // `listInterruptionRules`.
    let mixed = """
      1. one
         - bullet

      2. two
      """
    #expect(
      Self.elements(mixed) == [.orderedListItem, .unorderedListItem, .blank, .orderedListItem])
    #expect(Self.depths(mixed) == [0, 1, 0, 0])
  }

  @Test("A marker must be followed by whitespace, and a marker alone is still an item")
  func markerRecognitionEdges() {
    #expect(Self.elements("-word") == [.paragraph], "no space after the bullet")
    #expect(Self.elements("1.word") == [.paragraph], "no space after the number")
    #expect(Self.elements("1234567890. too many digits") == [.paragraph], "ten digits")
    #expect(Self.elements("123456789. nine digits") == [.orderedListItem])

    // An item with nothing after its marker is legal, and its content range is the empty
    // range at the end of the line.
    let empty = Self.fullScan("-")
    #expect(empty.lineRecords[0].element == .unorderedListItem)
    #expect(empty.lineRecords[0].contentRange == 1..<1)
    #expect(empty.spans.count == 1)
    #expect(empty.spans[0].range == 0..<1)
    #expect(empty.spans[0].role == .marker)
  }

  @Test("A list item's marker and content differ only in role")
  func listMarkerAndContentDifferOnlyInRole() {
    let result = Self.fullScan("- item")
    #expect(result.spans.count == 2)
    let marker = result.spans[0]
    let content = result.spans[1]
    #expect(marker.range == 0..<2, "the marker swallows the bullet AND the space")
    #expect(content.range == 2..<6)
    #expect(marker.kind == content.kind)
    #expect(marker.kind == .listItem)
    #expect(marker.style == content.style)
    #expect(marker.role == .marker)
    #expect(content.role == .content)
    #expect(result.lineRecords[0].contentRange == 2..<6)
  }

  @Test("A list can interrupt a paragraph only when the rules let it")
  func listInterruptionRules() {
    // A non-empty bullet may interrupt.
    #expect(Self.elements("text\n- item") == [.paragraph, .unorderedListItem])
    // An empty one may not: it is continuation prose. Spelled with `+` because a lone `-`
    // under a paragraph is a setext underline — a one-character one is legal CommonMark —
    // and that reading is tried first.
    #expect(Self.elements("text\n+") == [.paragraph, .paragraph])
    #expect(Self.elements("text\n*") == [.paragraph, .paragraph])
    #expect(Self.elements("text\n-") == [.paragraph, .heading], "a lone dash underlines")
    // An ordered item may interrupt only when it starts at 1 — otherwise every sentence
    // wrapping onto a line beginning "1968. " would turn the line above it into a list.
    #expect(Self.elements("text\n1. item") == [.paragraph, .orderedListItem])
    #expect(Self.elements("text\n2. item") == [.paragraph, .paragraph])
    // With a blank line between, all three are lists: the rule is about interruption.
    #expect(Self.elements("text\n\n2. item") == [.paragraph, .blank, .orderedListItem])
  }

  @Test("A continuation line inside an item carries the item's depth")
  func continuationLinesCarryItemDepth() {
    let text = """
      - a
        - b
          continued
      """
    #expect(Self.elements(text) == [.unorderedListItem, .unorderedListItem, .paragraph])
    #expect(Self.depths(text) == [0, 1, 1], "the prose belongs to the depth-1 item")

    // A lazy continuation — one that is not indented at all — stays in the item too.
    let lazy = "- a\ncontinued\n"
    #expect(Self.elements(lazy) == [.unorderedListItem, .paragraph, .blank])
    #expect(Self.depths(lazy) == [0, 0, 0])
  }

  @Test("A blank line separates blocks inside an item without closing it")
  func blankLinesDoNotCloseAnItem() {
    // The item is still open across the blank, so six columns of indent is code INSIDE
    // it — four columns past its content column of two — rather than four columns past
    // the margin.
    let inside = """
      - item

            code
      """
    #expect(Self.elements(inside) == [.unorderedListItem, .blank, .codeBlock])

    // And a line that outdents past the item closes it, which is what makes the previous
    // assertion mean something.
    let outside = """
      - item

      prose
      """
    #expect(Self.elements(outside) == [.unorderedListItem, .blank, .paragraph])
    #expect(Self.depths(outside) == [0, 0, 0])
  }

  @Test("Indentation inside an item is measured from the item's content column")
  func indentIsRelativeToTheItemsContentColumn() {
    // Four columns from the margin, but only two past the item's content column, so it is
    // prose inside the item and not code.
    #expect(Self.elements("- item\n\n    still prose") == [.unorderedListItem, .blank, .paragraph])
    // Six columns from the margin is four past it, so it is code.
    #expect(Self.elements("- item\n\n      code") == [.unorderedListItem, .blank, .codeBlock])

    // The same rule for a heading: `#` five columns in is code, not a heading, because
    // the item's content begins at column two.
    #expect(Self.elements("- item\n\n      # hash") == [.unorderedListItem, .blank, .codeBlock])
    #expect(Self.elements("- item\n\n  # heading") == [.unorderedListItem, .blank, .heading])
  }

  @Test("A marker followed by five or more columns of space is an item with code in it")
  func wideMarkerPaddingIsCode() {
    // CommonMark: only one column of the padding belongs to the marker when there are five
    // or more, so the item's content column is 2 and the text sits four past it.
    let result = Self.fullScan("-     code")
    #expect(result.lineRecords[0].element == .unorderedListItem)
    #expect(result.lineRecords[0].contentRange == 2..<10, "one space belongs to the marker")
    #expect(result.spans[0].range == 0..<2)
    #expect(result.spans[0].role == .marker)
  }

  // MARK: - Blockquotes

  @Test("A blockquote's marker run is one span and its nesting is its depth")
  func blockquoteMarkerAndDepth() {
    let single = Self.fullScan("> quoted")
    #expect(single.lineRecords[0].element == .blockquote)
    #expect(single.lineRecords[0].depth == 0, "one `>` is depth zero, as a first list item is")
    #expect(single.lineRecords[0].contentRange == 2..<8)
    #expect(single.spans.count == 2)
    #expect(single.spans[0].range == 0..<2, "the marker swallows one following space")
    #expect(single.spans[0].kind == .blockquote)
    #expect(single.spans[0].role == .marker)
    #expect(single.spans[1].range == 2..<8)
    #expect(single.spans[1].kind == .blockquote)
    #expect(single.spans[1].role == .content)

    // Nested, spelled both ways. One span for the whole run, so a dimmed gutter has no
    // holes in it.
    let spaced = Self.fullScan("> > nested")
    #expect(spaced.lineRecords[0].depth == 1)
    #expect(spaced.spans[0].range == 0..<4)
    #expect(spaced.lineRecords[0].contentRange == 4..<10)

    let tight = Self.fullScan(">> nested")
    #expect(tight.lineRecords[0].depth == 1)
    #expect(tight.spans[0].range == 0..<3)
    #expect(tight.lineRecords[0].contentRange == 3..<9)

    let three = Self.fullScan("> > > deep")
    #expect(three.lineRecords[0].depth == 2)
  }

  @Test("An empty blockquote line is a blockquote with an empty content range")
  func emptyBlockquote() {
    let result = Self.fullScan(">")
    #expect(result.lineRecords[0].element == .blockquote)
    #expect(result.lineRecords[0].depth == 0)
    #expect(result.lineRecords[0].contentRange == 1..<1)
    #expect(result.spans.count == 1)
    #expect(result.spans[0].role == .marker)
  }

  @Test("A blockquote does not leave a paragraph open behind it")
  func blockquoteClosesTheParagraph() {
    // If it did, the `---` below would become a setext underline for a paragraph that is
    // not there. This is the one place the blockquote's endState is observable, and it is
    // asserted rather than assumed.
    #expect(Self.elements("> quoted\n---") == [.blockquote, .thematicBreak])
  }

  // MARK: - Thematic breaks and setext underlines

  @Test("`---`, `***`, and `___` are thematic breaks, with or without spaces between")
  func thematicBreaks() {
    for text in ["---", "***", "___", "- - -", "* * *", "_ _ _", "-----", "   ---"] {
      #expect(Self.elements(text) == [.thematicBreak], "\(text.debugDescription)")
    }
    for text in ["--", "**", "__", "- -", "---x", "- --a"] {
      #expect(Self.elements(text) != [.thematicBreak], "\(text.debugDescription)")
    }

    // Pure delimiter: the whole run is a marker and the content range is empty.
    let result = Self.fullScan("---")
    #expect(result.spans.count == 1)
    #expect(result.spans[0].range == 0..<3)
    #expect(result.spans[0].kind == .thematicBreak)
    #expect(result.spans[0].role == .marker)
    #expect(result.lineRecords[0].contentRange == 3..<3)

    // Four columns of indent makes it code, not a break.
    #expect(Self.elements("    ---") == [.codeBlock])
  }

  @Test("`---` after a paragraph line is a setext heading, not a thematic break")
  func dashesUnderAParagraphAreASetextHeading() {
    // The exact criterion. Both readings are available and CommonMark gives the heading
    // precedence, which is decidable only from the state arriving from the line above —
    // the `---` line's own text is identical in both cases.
    let heading = Self.fullScan("Foo\n---")
    #expect(heading.lineRecords[1].element == .heading, "the criterion")
    #expect(heading.lineRecords[1].element != .thematicBreak)
    #expect(heading.lineRecords[1].depth == 2, "dashes underline a level-two heading")
    #expect(
      heading.spans.contains { $0.range == 4..<7 && $0.kind == .heading && $0.role == .marker })

    // `===` is the level-one spelling.
    let level1 = Self.fullScan("Foo\n===")
    #expect(level1.lineRecords[1].element == .heading)
    #expect(level1.lineRecords[1].depth == 1)

    // And the other half, without which the assertion above is satisfied by a grammar
    // that calls every run of dashes a heading: with a blank line above, the same text is
    // a thematic break.
    #expect(Self.elements("Foo\n\n---") == [.paragraph, .blank, .thematicBreak])
    #expect(Self.elements("---") == [.thematicBreak])

    // `***` and `___` are never setext underlines, so they stay thematic breaks under a
    // paragraph.
    #expect(Self.elements("Foo\n***") == [.paragraph, .thematicBreak])
    #expect(Self.elements("Foo\n___") == [.paragraph, .thematicBreak])
    // Spaced dashes cannot underline either — the run breaks at the first space — so
    // CommonMark reads them as a break, and so does this.
    #expect(Self.elements("Foo\n- - -") == [.paragraph, .thematicBreak])

    // A heading, a blank, and a code fence all close the paragraph, so none of them
    // leaves a setext reading available to the line after.
    #expect(Self.elements("# Foo\n---") == [.heading, .thematicBreak])
    #expect(Self.elements("    code\n---") == [.codeBlock, .thematicBreak])
  }

  // MARK: - Indented code blocks

  @Test("An indented code block keeps its indentation as content")
  func indentedCodeKeepsItsIndent() {
    let result = Self.fullScan("    let x = 1\n")
    #expect(result.lineRecords[0].element == .codeBlock)
    #expect(
      result.lineRecords[0].contentRange == 0..<13,
      "indentation is significant inside code, so it is content and the writer keeps it")
    #expect(result.spans[0].range == 0..<13)
    #expect(result.spans[0].kind == .codeBlock)
    #expect(result.spans[0].role == .content)
  }

  @Test("An indented code block cannot interrupt a paragraph")
  func indentedCodeCannotInterruptAParagraph() {
    // The rule that keeps a hanging-indented sentence from turning into code as it is
    // typed. It is decidable only from the state above, which is why `paragraphOpen` is a
    // field rather than something re-derived.
    #expect(Self.elements("prose\n    not code") == [.paragraph, .paragraph])
    #expect(Self.elements("prose\n\n    code") == [.paragraph, .blank, .codeBlock])
    #expect(Self.elements("    code") == [.codeBlock])
  }

  // MARK: - Interaction with fenced code

  @Test("A fenced block inside a list item does not close the item")
  func fenceCarriesTheBlockContextThrough() {
    // A state-omission test with teeth: if the opening fence dropped the list stack, the
    // last line — four columns from the margin, two past the item's content column —
    // would come back as an indented code block instead of prose in the item. The gate
    // test cannot see this; only this expectation can.
    let text = """
      - item

        ```
        code
        ```

          still text
      """
    #expect(
      Self.elements(text) == [
        .unorderedListItem, .blank, .codeFence, .codeBlock, .codeFence, .blank, .paragraph,
      ])
    #expect(Self.depths(text) == [0, 0, 0, 0, 0, 0, 0])

    // And the item really is still open: six columns is code, four is not.
    let deeper = """
      - item

        ```
        code
        ```

            code again
      """
    #expect(Self.elements(deeper).last == .codeBlock)
  }

  @Test("Inside a fence, no block construct is syntax")
  func fenceSuppressesBlockConstructs() {
    let text = "```\n- not a list\n> not a quote\n---\n    not code\n```\n- a list\n"
    #expect(
      Self.elements(text) == [
        .codeFence, .codeBlock, .codeBlock, .codeBlock, .codeBlock, .codeFence,
        .unorderedListItem, .blank,
      ])
  }

  // MARK: - Convergence

  @Test("Opening a list item changes the state entering every line inside it")
  func openingAListDirtiesWhatItContains() {
    // The list stack is convergence state, and this is what that buys: typing the marker
    // reclassifies the indented lines below it, because their meaning is measured against
    // the item's content column. A grammar that recomputed nesting per line would repaint
    // the marker and nothing else.
    let before = "text\n\n    x\n    y\n    z\n"
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    let base = scanner.fullScan(before)
    ScanInvariants.check(base, text: before, editedRange: nil, "list convergence base")
    #expect(
      base.lineRecords.map(\.element) == [
        .paragraph, .blank, .codeBlock, .codeBlock, .codeBlock, .blank,
      ])

    // Turn the first prose line into a list item. Everything below it is now two columns
    // past the item's content column — prose, not code.
    let after = "- t\n\n    x\n    y\n    z\n"
    let edit = TextEdit(range: 0..<4, replacementLength: 3)
    let result = scanner.incrementalScan(edit, in: after)
    ScanInvariants.check(result, text: after, editedRange: 0..<3, "list opened")

    #expect(result.lines.upperBound == 6, "the rescan did not reach the end of the document")
    #expect(
      result.lineRecords.map(\.element) == [
        .unorderedListItem, .blank, .paragraph, .paragraph, .paragraph, .blank,
      ])

    // And it agrees with a full scan of the same text, which is what makes "reclassified"
    // mean "correctly reclassified".
    var fresh = IncrementalScanner(grammar: MarkdownGrammar())
    let full = fresh.fullScan(after)
    ScanInvariants.check(full, text: after, editedRange: nil, "list opened, full scan")
    ScanInvariants.expectSameElements(
      scanner.startStates, fresh.startStates, "startStates", "list opened at line 0")
    ScanInvariants.expectSameElements(
      result.lineRecords, full.lineRecords.filter { result.lines.contains($0.index) },
      "lineRecords", "list opened at line 0")
  }

  @Test("A sequence of block-structure edits tracks a full scan throughout")
  func blockEditSequenceTracksFullScan() {
    // Fixed script, no randomness — drift only shows up when one scanner is carried
    // across many edits, which is how a live editor uses one.
    let script: [(Range<Int>, String)] = [
      (0..<0, "- a\n"),
      (4..<4, "  - b\n"),
      (10..<10, "    - c\n"),
      (18..<18, "\n> quoted\n"),
      (28..<28, "---\n"),
      (0..<2, ""),  // `- a` becomes `a` — the whole stack below it shifts
      (0..<0, "1. "),  // and comes back as an ordered item
      (4..<4, "\nFoo\n---\n"),  // a setext underline in the middle
    ]

    var text = ""
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    ScanInvariants.check(scanner.fullScan(text), text: text, editedRange: nil, "block base")

    for (range, replacement) in script {
      let next = ScanInvariants.splice(text, range, replacement)
      let result = scanner.incrementalScan(
        TextEdit(range: range, replacementLength: replacement.utf16.count), in: next)
      ScanInvariants.check(
        result, text: next,
        editedRange: range.lowerBound..<(range.lowerBound + replacement.utf16.count),
        "block sequence at \(next.debugDescription)")

      var fresh = IncrementalScanner(grammar: MarkdownGrammar())
      let full = fresh.fullScan(next)
      ScanInvariants.check(
        full, text: next, editedRange: nil, "block sequence full scan at \(next.debugDescription)")
      ScanInvariants.expectSameElements(
        scanner.startStates, fresh.startStates, "startStates",
        "block sequence at \(next.debugDescription)")
      ScanInvariants.expectSameElements(
        result.lineRecords, full.lineRecords.filter { result.lines.contains($0.index) },
        "lineRecords", "block sequence at \(next.debugDescription)")
      text = next
    }
  }

  // MARK: - The block state itself

  @Test("The list stack pops to the innermost item a column still sits inside")
  func listStackPopRule() {
    // The one rule list nesting rests on, asserted on the value rather than through a
    // document, so a failure names the arithmetic instead of a classification.
    var stack = MarkdownBlockState()
    #expect(stack.listDepth == 0)
    #expect(stack.innermostContentColumn == 0)

    stack.pushList(contentColumn: 2)
    stack.pushList(contentColumn: 4)
    stack.pushList(contentColumn: 6)
    #expect(stack.listDepth == 3)
    #expect(stack.innermostContentColumn == 6)

    stack.popLists(deeperThan: 4)
    #expect(stack.listDepth == 2, "column 4 is still inside the item whose content is at 4")

    stack.popLists(deeperThan: 2)
    #expect(stack.listDepth == 1)

    stack.popLists(deeperThan: 0)
    #expect(stack.listDepth == 0)
    #expect(stack.contentColumns == 0, "a fully popped stack is bit-identical to a fresh one")

    // Saturation rather than corruption past the tracked depth.
    var deep = MarkdownBlockState()
    for level in 1...(MarkdownBlockState.maxTrackedDepth + 4) {
      deep.pushList(contentColumn: level * 2)
    }
    #expect(deep.listDepth == MarkdownBlockState.maxTrackedDepth)

    // And a column past the byte range is clamped, never truncated to something smaller.
    var wide = MarkdownBlockState()
    wide.pushList(contentColumn: 4000)
    #expect(wide.innermostContentColumn == MarkdownBlockState.maxTrackedColumn)
  }

  // MARK: - Degenerate input

  @Test(
    "Degenerate block documents scan without failing",
    arguments: [
      "-", ">", "---", "___", "***", "1.", "1)", "- \n- \n- ", ">>>>>>>>", "\t", "    ",
      "- - - - -", "> - > -", "-\t", ">\t>", "1.\t", "\u{1F600}\t- x", "- 😀\n  - 😀\n",
    ])
  func degenerateBlockDocuments(text: String) {
    let result = Self.fullScan(text)
    #expect(result.spans.reduce(0) { $0 + $1.range.count } == text.utf16.count)
    IncrementalScannerTests.expectInvariants(
      result, text: text, editedRange: nil, "degenerate block")
  }

  @Test("A pathologically nested list scans and saturates rather than growing without bound")
  func deeplyNestedListsSaturate() {
    var lines: [String] = []
    for level in 0..<24 {
      lines.append(String(repeating: " ", count: level * 2) + "- item \(level)")
    }
    let text = lines.joined(separator: "\n")
    let result = Self.fullScan(text)
    #expect(result.lineRecords.count == 24)
    #expect(result.lineRecords.allSatisfy { $0.element == .unorderedListItem })
    #expect(
      result.lineRecords.map(\.depth).max() == MarkdownBlockState.maxTrackedDepth,
      "depth saturates at the tracked depth instead of climbing forever")
    #expect(result.lineRecords.map(\.depth) == result.lineRecords.map(\.depth).sorted())
  }
}
