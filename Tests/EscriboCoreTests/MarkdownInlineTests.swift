import Testing

@testable import EscriboCore

/// CommonMark **inline** structure: emphasis, strong, code spans, links, images, and hard
/// breaks — asserted as the flat, tiling span layouts they flatten into.
///
/// ## Why every span below is written out by hand
///
/// `ScanGateTests`'s `incrementalScan == fullScan` property **cannot** catch a bug in this
/// grammar. Both sides of its comparison run the same code, so a scanner that flattens
/// emphasis wrongly is wrong identically on both sides and the gate stays green. The
/// supervisor proved this twice on this mission — a grammar state-omission break left the
/// gate at 224/224 while four hand-written tests caught it, and a too-short forward
/// extension did the same.
///
/// So nothing here infers a span layout from a green gate. Every range, every
/// ``SpanKind``, every ``StyleSet``, and every ``SpanRole`` below is a value a human
/// computed from the UTF-16 code units of the fixture and wrote down. Do not replace one
/// with a comparison against another scan, and do not weaken one to "contains a strong
/// span somewhere" — a scanner that puts a delimiter boundary one code unit wrong passes
/// that and flickers a `*` on every keystroke.
///
/// Every scan in this suite goes through ``fullScan(_:)``, which routes it through
/// `ScanInvariants` — Sortie 6's always-on harness — on the way out.
@Suite("Markdown grammar — CommonMark inline structure")
struct MarkdownInlineTests {

  // MARK: - Helpers

  /// Full-scans `text` **and asserts every `ScanResult` invariant on the way out**.
  ///
  /// The harness lives here rather than at each call site so that adding a test to this
  /// suite cannot omit it — which is how the "invariant helper passes on all inline tests"
  /// criterion is met structurally rather than by remembering.
  static func fullScan(
    _ text: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> ScanResult {
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    let result = scanner.fullScan(text)
    ScanInvariants.check(
      result, text: text, editedRange: nil, "markdown inline scan of \(text.debugDescription)",
      sourceLocation: sourceLocation)
    return result
  }

  /// One expected span, written the way a reader thinks about it.
  struct Expected: Equatable, CustomStringConvertible {
    let range: Range<Int>
    let kind: SpanKind
    let style: StyleSet
    let role: SpanRole

    init(_ range: Range<Int>, _ kind: SpanKind, _ style: StyleSet = [], _ role: SpanRole = .content)
    {
      self.range = range
      self.kind = kind
      self.style = style
      self.role = role
    }

    init(_ span: EscriboSpan) {
      self.range = span.range
      self.kind = span.kind
      self.style = span.style
      self.role = span.role
    }

    var description: String {
      "\(range.lowerBound)..<\(range.upperBound) \(kind.rawValue)/\(role.rawValue)"
        + "/\(style.rawValue)"
    }
  }

  /// Asserts the whole span layout of `text`, span by span, in order.
  ///
  /// Whole-layout rather than spot checks on purpose: a spot check cannot see a span that
  /// should not be there, and an extra zero-width-looking span is exactly what a
  /// mis-encoded delimiter produces.
  static func expectLayout(
    _ text: String,
    _ expected: [Expected],
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let result = fullScan(text, sourceLocation: sourceLocation)
    ScanInvariants.expectSameElements(
      result.spans.map(Expected.init), expected, "spans", text.debugDescription,
      sourceLocation: sourceLocation)
  }

  /// Whether a boundary at `offset` falls between a high and a low surrogate. Hand-written
  /// here rather than borrowed from the scanner, because an invariant checked with the
  /// code that produced the value is not checked.
  static func splitsPair(_ offset: Int, _ units: [UInt16]) -> Bool {
    guard offset > 0, offset < units.count else { return false }
    return (0xD800...0xDBFF).contains(units[offset - 1])
      && (0xDC00...0xDFFF).contains(units[offset])
  }

  // MARK: - The union, which is the whole design

  @Test(
    "`**bold `code` bold**` flattens to consecutive spans, the code one `[.strong, .inlineCode]`")
  func strongWrappingACodeSpanUnionsBothStyles() {
    // The sortie's headline criterion, and the one assertion that says "flattened, never a
    // tree" in executable form. `**bold `code` bold**`, code unit by code unit:
    //
    //   0 1   2 3 4 5   6   7   8 9 10 11  12  13  14 15 16 17  18 19
    //   * *   b o l d  ' '  `   c o  d  e   `  ' '  b  o  l  d   *  *
    //
    // The strong run covers 0..<20 — markers included, because a marker carries the same
    // style as the content it wraps — and the code span ORs `.inlineCode` over 7..<13.
    // The overlap is a UNION, not a winner: 7..<13 carries both.
    Self.expectLayout(
      "**bold `code` bold**",
      [
        Expected(0..<2, .text, [.strong], .marker),
        Expected(2..<7, .text, [.strong]),
        Expected(7..<8, .text, [.strong, .inlineCode], .marker),
        Expected(8..<12, .text, [.strong, .inlineCode]),
        Expected(12..<13, .text, [.strong, .inlineCode], .marker),
        Expected(13..<18, .text, [.strong]),
        Expected(18..<20, .text, [.strong], .marker),
      ])

    // Stated a second way, so that a future edit weakening the layout above still trips:
    // the code span's three spans are consecutive, they carry BOTH flags, and no span in
    // the line carries `.inlineCode` without `.strong`.
    let result = Self.fullScan("**bold `code` bold**")
    let coded = result.spans.filter { $0.style.contains(.inlineCode) }
    #expect(coded.count == 3)
    #expect(coded.allSatisfy { $0.style == [.strong, .inlineCode] })
    #expect(coded.first?.range.lowerBound == 7)
    #expect(coded.last?.range.upperBound == 13)
  }

  @Test("`***x***` leaves the outer asterisks emphasis-only and the inner pair both")
  func tripleAsterisksNestWithoutATree() {
    // The clearest possible statement that this is paint and not a tree. An opener spends
    // from its RIGHT end and a closer from its LEFT, so the strong pair is the inner one
    // and the emphasis pair wraps it — and the outer asterisks therefore carry a style the
    // inner ones do not.
    Self.expectLayout(
      "***x***",
      [
        Expected(0..<1, .text, [.emphasis], .marker),
        Expected(1..<3, .text, [.emphasis, .strong], .marker),
        Expected(3..<4, .text, [.emphasis, .strong]),
        Expected(4..<6, .text, [.emphasis, .strong], .marker),
        Expected(6..<7, .text, [.emphasis], .marker),
      ])
  }

  @Test("A marker carries the same kind and style as the content it wraps")
  func markersDifferFromContentOnlyInRole() {
    // The rule the whole styler rests on, asserted on an inline construct rather than on a
    // block one. If a delimiter ever disagrees with its content about kind or style,
    // "the asterisks show, dimmed, while the word renders bold" stops being a property of
    // the data and becomes a special case in the styler.
    let result = Self.fullScan("*em*")
    #expect(result.spans.count == 3, "open marker, content, close marker — and nothing else")
    let open = result.spans[0]
    let content = result.spans[1]
    let close = result.spans[2]

    #expect(open.range == 0..<1)
    #expect(content.range == 1..<3)
    #expect(close.range == 3..<4)
    #expect(open.kind == content.kind)
    #expect(close.kind == content.kind)
    #expect(open.style == content.style)
    #expect(close.style == content.style)
    #expect(content.style == [.emphasis])
    #expect(open.role == .marker)
    #expect(close.role == .marker)
    #expect(content.role == .content)
  }

  // MARK: - Flanking

  @Test("`snake_case_name` is not emphasized, and `a*b*c` is")
  func flankingRulesDistinguishUnderscoreFromAsterisk() {
    // The single most complained-about Markdown misrender there is, and the reason the
    // `_`-specific clauses of the flanking rules exist. One span, no emphasis anywhere.
    Self.expectLayout("snake_case_name", [Expected(0..<15, .text)])

    // `*` has no intraword restriction, so the same shape with asterisks DOES emphasize.
    // Both halves are needed: a scanner that simply refused intraword delimiters would
    // pass the first and fail this.
    Self.expectLayout(
      "a*b*c",
      [
        Expected(0..<1, .text),
        Expected(1..<2, .text, [.emphasis], .marker),
        Expected(2..<3, .text, [.emphasis]),
        Expected(3..<4, .text, [.emphasis], .marker),
        Expected(4..<5, .text),
      ])

    // `_` between spaces is emphasis, which is what stops the rule above from being
    // "underscores never work".
    Self.expectLayout(
      "a _b_ c",
      [
        Expected(0..<2, .text),
        Expected(2..<3, .text, [.emphasis], .marker),
        Expected(3..<4, .text, [.emphasis]),
        Expected(4..<5, .text, [.emphasis], .marker),
        Expected(5..<7, .text),
      ])
  }

  @Test("An unpaired delimiter is literal text, not a marker")
  func unpairedDelimitersDegradeToText() {
    // "Malformed constructs degrade to text" for the inline scanner: no marker span, no
    // style, no gap — one `.text` span across the whole line.
    Self.expectLayout("2 * 3 * 4", [Expected(0..<9, .text)])
    Self.expectLayout("**", [Expected(0..<2, .text)])
    Self.expectLayout("a ` b", [Expected(0..<5, .text)])
  }

  @Test("A backslash escape is a marker and its target is inert")
  func backslashEscapesSuppressEmphasis() {
    // `\*not emphasis\*` — the backslashes are markers, the asterisks are ordinary text,
    // and nothing on the line carries a style.
    Self.expectLayout(
      "\\*not emphasis\\*",
      [
        Expected(0..<1, .text, [], .marker),
        Expected(1..<14, .text),
        Expected(14..<15, .text, [], .marker),
        Expected(15..<16, .text),
      ])
  }

  // MARK: - Code spans

  @Test("A backtick run is closed only by a run of exactly its own length")
  func codeSpanBacktickRunsOfArbitraryLength() {
    // Two backticks open a span that a single backtick cannot close, which is how a code
    // span comes to contain a backtick at all.
    //
    //   0 1  2   3   4   5   6   7 8
    //   ` `  a  ' '  `  ' '  b   ` `
    Self.expectLayout(
      "``a ` b``",
      [
        Expected(0..<2, .text, [.inlineCode], .marker),
        Expected(2..<7, .text, [.inlineCode]),
        Expected(7..<9, .text, [.inlineCode], .marker),
      ])

    // Emphasis delimiters inside a code span are text: the walk steps over the span
    // wholesale, so the collector never sees them.
    Self.expectLayout(
      "`*x*`",
      [
        Expected(0..<1, .text, [.inlineCode], .marker),
        Expected(1..<4, .text, [.inlineCode]),
        Expected(4..<5, .text, [.inlineCode], .marker),
      ])
  }

  @Test("A code span keeps the enclosing block's kind rather than taking one of its own")
  func codeSpanInheritsTheBlockKind() {
    // The deliberate asymmetry with links, and it comes straight from the theme's
    // composition order: `.inlineCode` is a STYLE flag that swaps the font family, while
    // `kind` supplies color and size scale. A `.codeSpan` kind would override a heading's
    // size scale and render inline code inside a heading at body size.
    //
    //   0 1  2   3  4  5  6   7  8 9 10 11
    //   # #  ' ' `  a  b  `  ' ' c  d  e  f      -> "## `ab` cdef"
    Self.expectLayout(
      "## `ab` cdef",
      [
        Expected(0..<3, .heading, [], .marker),
        Expected(3..<4, .heading, [.inlineCode], .marker),
        Expected(4..<6, .heading, [.inlineCode]),
        Expected(6..<7, .heading, [.inlineCode], .marker),
        Expected(7..<12, .heading),
      ])
  }

  // MARK: - Links and images

  @Test("`[text](url)` splits into link spans and `.linkURL` spans")
  func inlineLinkSpanLayout() {
    //   0   1 2 3 4   5   6   7 8 9  10
    //   [   t e x t   ]   (   u r l   )
    //
    // `]` closes the link text and `(` opens the destination, so the two delimiters are
    // separate spans rather than one `](`: they belong to different kinds, and a marker
    // must carry the kind of what it wraps.
    Self.expectLayout(
      "[text](url)",
      [
        Expected(0..<1, .link, [], .marker),
        Expected(1..<5, .link),
        Expected(5..<6, .link, [], .marker),
        Expected(6..<7, .linkURL, [], .marker),
        Expected(7..<10, .linkURL),
        Expected(10..<11, .linkURL, [], .marker),
      ])
  }

  @Test("`![alt](img.png \"Title\")` yields image, `.linkURL`, and `.linkTitle` spans")
  func imageWithTitleSpanLayout() {
    //   0   1   2 3 4   5   6   7 8 9 10 11 12 13  14   15  16..20  21  22
    //   !   [   a l t   ]   (   i m g  .  p  n  g  ' '   "  Title    "   )
    Self.expectLayout(
      "![alt](img.png \"Title\")",
      [
        Expected(0..<2, .image, [], .marker),
        Expected(2..<5, .image),
        Expected(5..<6, .image, [], .marker),
        Expected(6..<7, .linkURL, [], .marker),
        Expected(7..<14, .linkURL),
        Expected(14..<15, .linkURL, [], .marker),
        Expected(15..<16, .linkTitle, [], .marker),
        Expected(16..<21, .linkTitle),
        Expected(21..<22, .linkTitle, [], .marker),
        Expected(22..<23, .linkURL, [], .marker),
      ])
  }

  @Test("A bracket with no inline destination is literal text")
  func bracketsWithoutADestinationAreText() {
    // Reference links need the document's link reference definitions, which this scanner
    // does not carry. `[a][b]` and `[a]` therefore scan as text rather than as a link with
    // a destination the scanner invented. Asserted so that adding reference links later is
    // a change somebody notices.
    Self.expectLayout("[a][b]", [Expected(0..<6, .text)])
    Self.expectLayout("see [docs] here", [Expected(0..<15, .text)])
  }

  @Test("Emphasis inside link text stays inside it")
  func emphasisIsBoundedByBrackets() {
    //   0   1   2   3   4   5   6   7 8 9  10
    //   [   *   a   *   ]   (   u   )  ... -> "[*a*](u)"
    Self.expectLayout(
      "[*a*](u)",
      [
        Expected(0..<1, .link, [], .marker),
        Expected(1..<2, .link, [.emphasis], .marker),
        Expected(2..<3, .link, [.emphasis]),
        Expected(3..<4, .link, [.emphasis], .marker),
        Expected(4..<5, .link, [], .marker),
        Expected(5..<6, .linkURL, [], .marker),
        Expected(6..<7, .linkURL),
        Expected(7..<8, .linkURL, [], .marker),
      ])

    // And the converse: a `*` opened inside link text may not close outside it. The
    // delimiters inside the brackets are retired when the link closes, so the trailing `*`
    // has nothing to pair with and is text.
    Self.expectLayout(
      "[*a](u)*",
      [
        Expected(0..<1, .link, [], .marker),
        Expected(1..<3, .link),
        Expected(3..<4, .link, [], .marker),
        Expected(4..<5, .linkURL, [], .marker),
        Expected(5..<6, .linkURL),
        Expected(6..<7, .linkURL, [], .marker),
        Expected(7..<8, .text),
      ])
  }

  // MARK: - Hard breaks

  @Test("Two trailing spaces and a trailing backslash are both hard breaks")
  func hardBreakSpanLayout() {
    // The trailing whitespace is a span rather than filler, which is what keeps the tiling
    // total over characters a reader cannot see.
    let spaces = Self.fullScan("line one  \nline two")
    ScanInvariants.expectSameElements(
      spaces.spans.prefix(3).map(Expected.init),
      [
        Expected(0..<8, .text),
        Expected(8..<10, .hardBreak, [], .marker),
        Expected(10..<11, .text),  // the terminator, engine-supplied filler
      ],
      "spans", "two trailing spaces")

    let backslash = Self.fullScan("line\\\nnext")
    ScanInvariants.expectSameElements(
      backslash.spans.prefix(3).map(Expected.init),
      [
        Expected(0..<4, .text),
        Expected(4..<5, .hardBreak, [], .marker),
        Expected(5..<6, .text),
      ],
      "spans", "trailing backslash")

    // One trailing space is not a break, and an escaped backslash is not one either.
    Self.expectLayout("one ", [Expected(0..<4, .text)])
    Self.expectLayout(
      "one\\\\",
      [
        Expected(0..<3, .text),
        Expected(3..<4, .text, [], .marker),
        Expected(4..<5, .text),
      ])

    // A heading has no hard break: the trailing spaces belong to the heading's own
    // trimming, not to an inline construct.
    let heading = Self.fullScan("# Title  ")
    #expect(heading.spans.allSatisfy { $0.kind != .hardBreak })
  }

  // MARK: - Inline structure inside every block that has content

  @Test("Emphasis and links work inside list items and blockquotes, inheriting the kind")
  func inlineStructureInsideContainers() {
    //   0   1   2 3   4   5   6   7   8   9  10  11  12  13
    //   -  ' '  a ' '  *   b   *  ' '  [   c   ]   (   d   )
    Self.expectLayout(
      "- a *b* [c](d)",
      [
        Expected(0..<2, .listItem, [], .marker),
        Expected(2..<4, .listItem),
        Expected(4..<5, .listItem, [.emphasis], .marker),
        Expected(5..<6, .listItem, [.emphasis]),
        Expected(6..<7, .listItem, [.emphasis], .marker),
        Expected(7..<8, .listItem),
        Expected(8..<9, .link, [], .marker),
        Expected(9..<10, .link),
        Expected(10..<11, .link, [], .marker),
        Expected(11..<12, .linkURL, [], .marker),
        Expected(12..<13, .linkURL),
        Expected(13..<14, .linkURL, [], .marker),
      ])

    //   0   1   2 3 4   5   6   7   8
    //   >  ' '  a b c   ' '  *   d   *  -> "> abc *d*"
    Self.expectLayout(
      "> abc *d*",
      [
        Expected(0..<2, .blockquote, [], .marker),
        Expected(2..<6, .blockquote),
        Expected(6..<7, .blockquote, [.emphasis], .marker),
        Expected(7..<8, .blockquote, [.emphasis]),
        Expected(8..<9, .blockquote, [.emphasis], .marker),
      ])

    //   0   1   2 3 4 5 6   7   8   9 10 11 12
    //   #  ' '  A ' ' * * b  o   l   d  *  *   -> "# A **bold**"
    Self.expectLayout(
      "# A **bold**",
      [
        Expected(0..<2, .heading, [], .marker),
        Expected(2..<4, .heading),
        Expected(4..<6, .heading, [.strong], .marker),
        Expected(6..<10, .heading, [.strong]),
        Expected(10..<12, .heading, [.strong], .marker),
      ])
  }

  @Test("Inline syntax inside a code block is not inline syntax")
  func codeBlocksAreNotInlineScanned() {
    // The one place the block grammar has to say no. Both fenced and indented code, and
    // the closing fence with them.
    let fenced = Self.fullScan("```\n**not bold** `nor code`\n```")
    #expect(fenced.lineRecords[1].element == .codeBlock)
    #expect(fenced.spans.allSatisfy { $0.style.isEmpty }, "no style may leak into a code block")
    #expect(fenced.spans.allSatisfy { $0.kind == .codeBlock || $0.kind == .text })

    let indented = Self.fullScan("    **not bold**")
    #expect(indented.lineRecords[0].element == .codeBlock)
    ScanInvariants.expectSameElements(
      indented.spans.map(Expected.init), [Expected(0..<16, .codeBlock)], "spans", "indented code")

    // And a thematic break, which is `***` and would otherwise be an emphasis run.
    let rule = Self.fullScan("***")
    ScanInvariants.expectSameElements(
      rule.spans.map(Expected.init), [Expected(0..<3, .thematicBreak, [], .marker)], "spans",
      "thematic break")
  }

  // MARK: - Surrogate pairs

  @Test("No span boundary in an emoji-dense document splits a surrogate pair")
  func emojiBoundariesFallBetweenSurrogatePairs() {
    // The criterion, and the shape that makes it capable of failing: every emoji is
    // ADJACENT to a delimiter, so a boundary that landed one code unit late or early would
    // land inside the pair rather than beside it. A fixture with emoji in the middle of
    // words could not distinguish the two.
    let text = """
      **😀bold😀** and `😀` and [😀](😀.png) and 𐐷*𐐷*𐐷
      - 😀 *𐐷* item
      > 😀`𐐷`😀
      # 😀 **𐐷**
      """
    let result = Self.fullScan(text)
    let units = Array(text.utf16)

    for span in result.spans {
      #expect(
        !Self.splitsPair(span.range.lowerBound, units),
        "span boundary at \(span.range.lowerBound) splits a surrogate pair")
      #expect(
        !Self.splitsPair(span.range.upperBound, units),
        "span boundary at \(span.range.upperBound) splits a surrogate pair")
    }

    // The fixture must actually exercise adjacency, or the loop above proves nothing. Count
    // the boundaries that sit immediately AFTER a low surrogate or immediately BEFORE a
    // high one — those are the boundaries a one-off error would push into a pair.
    var adjacent = 0
    for span in result.spans {
      for boundary in [span.range.lowerBound, span.range.upperBound]
      where boundary > 0 && boundary < units.count {
        if (0xDC00...0xDFFF).contains(units[boundary - 1])
          || (0xD800...0xDBFF).contains(units[boundary])
        {
          adjacent += 1
        }
      }
    }
    #expect(adjacent >= 20, "fixture exercised only \(adjacent) pair-adjacent boundaries")

    // Every code unit is still covered exactly once — the tiling is what makes stale
    // attributes impossible, and an astral-plane document is where a hand-written scanner
    // drops one.
    #expect(result.spans.reduce(0) { $0 + $1.range.count } == units.count)
  }

  @Test("`*😀*` puts its boundaries at 1 and 3, never at 2")
  func emphasisAroundASurrogatePairHasHandWrittenBoundaries() {
    // The property test above says "no boundary splits a pair"; this says where the
    // boundaries ARE. A scanner that measured characters instead of code units would put
    // the closing marker at 2..<3 and this goes red, where the property test would not.
    //
    //   0   1        2       3
    //   *   D83D    DE00     *
    Self.expectLayout(
      "*\u{1F600}*",
      [
        Expected(0..<1, .text, [.emphasis], .marker),
        Expected(1..<3, .text, [.emphasis]),
        Expected(3..<4, .text, [.emphasis], .marker),
      ])
  }

  // MARK: - Stale attributes

  @Test("Deleting one `*` from `**bold**` dirties the whole former bold run")
  func deletingOneAsteriskDirtiesTheWholeBoldRun() {
    // The requirement, stated as the defect it prevents: if the dirty range were narrower
    // than the run that used to be bold, the editor would reapply attributes to part of it
    // and leave the rest bold on screen. That is a thing the user sees.
    //
    //   "intro\n"       0..<6
    //   "**bold**\n"    6..<15   — the bold run is 6..<14
    //   "tail\n"        15..<20
    let text = "intro\n**bold**\ntail\n"
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    let before = scanner.fullScan(text)
    ScanInvariants.check(before, text: text, editedRange: nil, "bold base")

    // The premise: it really was bold, over exactly 6..<14.
    let boldBefore = before.spans.filter { $0.style.contains(.strong) }
    #expect(boldBefore.first?.range.lowerBound == 6)
    #expect(boldBefore.last?.range.upperBound == 14)

    // Delete the first `*`.
    let edited = ScanInvariants.splice(text, 6..<7, "")
    #expect(edited == "intro\n*bold**\ntail\n")
    let result = scanner.incrementalScan(TextEdit(range: 6..<7, replacementLength: 0), in: edited)
    ScanInvariants.check(result, text: edited, editedRange: 6..<6, "one asterisk deleted")

    // The criterion. The former bold run occupied 6..<14 of the old text; its surviving
    // text plus its terminator occupy 6..<14 of the new text, and the dirty range covers
    // all of it.
    #expect(result.dirtyRange.lowerBound <= 6, "dirty range starts after the former bold run")
    #expect(result.dirtyRange.upperBound >= 14, "dirty range ends before the former bold run")

    // And the substance behind it: nothing repainted over that region is strong any more.
    // The criterion above is satisfied for free by `dirtyRange` being line-aligned, so on
    // its own it certifies very little; this is the assertion that would actually catch a
    // scanner leaving `.strong` behind.
    let repainted = result.spans.filter { $0.range.overlaps(6..<14) }
    #expect(!repainted.isEmpty)
    #expect(
      repainted.allSatisfy { !$0.style.contains(.strong) },
      "a `.strong` span survived the deletion of its opening delimiter")

    // What is left is single-asterisk emphasis over 6..<12, which is CommonMark's reading
    // of `*bold**` and is written out rather than read off the scanner.
    let line = result.spans.filter { $0.range.lowerBound >= 6 && $0.range.upperBound <= 14 }
    ScanInvariants.expectSameElements(
      line.map(Expected.init),
      [
        Expected(6..<7, .text, [.emphasis], .marker),
        Expected(7..<11, .text, [.emphasis]),
        Expected(11..<12, .text, [.emphasis], .marker),
        Expected(12..<13, .text),
        Expected(13..<14, .text),
      ],
      "spans", "after deleting one asterisk")

    // And the incremental scanner still agrees with a full scan of the same text, which is
    // what makes "dirtied correctly" rather than merely "dirtied widely".
    var fresh = IncrementalScanner(grammar: MarkdownGrammar())
    let full = fresh.fullScan(edited)
    ScanInvariants.check(full, text: edited, editedRange: nil, "one asterisk deleted, full")
    ScanInvariants.expectSameElements(
      scanner.startStates, fresh.startStates, "startStates", "one asterisk deleted")
    ScanInvariants.expectSameElements(
      result.spans.map(Expected.init),
      full.spans.filter { result.dirtyRange.contains($0.range.lowerBound) }.map(Expected.init),
      "spans", "one asterisk deleted")
  }

  @Test("Typing a `*` one character at a time never leaves a stale style behind")
  func typingEmphasisTracksAFullScanThroughout() {
    // Fixed script, no randomness. Every step compares the whole repainted region against
    // a full scan of the same text, so a step that repainted too little is caught by the
    // comparison rather than assumed away.
    let script: [(Range<Int>, String)] = [
      (0..<0, "word\n"),
      (0..<0, "*"),  // "*word\n"      — unpaired, no style
      (5..<5, "*"),  // "*word*\n"     — emphasis
      (0..<0, "*"),  // "**word*\n"    — emphasis, one asterisk spare
      (7..<7, "*"),  // "**word**\n"   — strong
      (0..<1, ""),  // "*word**\n"    — back to emphasis
      (0..<1, ""),  // "word**\n"     — nothing
    ]

    var text = ""
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    ScanInvariants.check(scanner.fullScan(text), text: text, editedRange: nil, "inline base")

    for (range, replacement) in script {
      let next = ScanInvariants.splice(text, range, replacement)
      let result = scanner.incrementalScan(
        TextEdit(range: range, replacementLength: replacement.utf16.count), in: next)
      ScanInvariants.check(
        result, text: next,
        editedRange: range.lowerBound..<(range.lowerBound + replacement.utf16.count),
        "inline sequence at \(next.debugDescription)")

      var fresh = IncrementalScanner(grammar: MarkdownGrammar())
      let full = fresh.fullScan(next)
      ScanInvariants.check(
        full, text: next, editedRange: nil, "inline sequence full at \(next.debugDescription)")
      ScanInvariants.expectSameElements(
        result.spans.map(Expected.init),
        full.spans.filter { result.dirtyRange.contains($0.range.lowerBound) }.map(Expected.init),
        "spans", "inline sequence at \(next.debugDescription)")
      ScanInvariants.expectSameElements(
        scanner.startStates, fresh.startStates, "startStates",
        "inline sequence at \(next.debugDescription)")
      text = next
    }

    // The end state: the asterisks are gone from the front and nothing is styled.
    #expect(text == "word**\n")
    let final = Self.fullScan(text)
    #expect(final.spans.allSatisfy { $0.style.isEmpty })
  }

  // MARK: - Vocabulary

  @Test(
    "The inline SpanKind raw values are stable",
    arguments: [
      (SpanKind.link, "link"),
      (SpanKind.linkURL, "linkURL"),
      (SpanKind.linkTitle, "linkTitle"),
      (SpanKind.image, "image"),
      (SpanKind.hardBreak, "hardBreak"),
    ])
  func inlineSpanKindRawValues(kind: SpanKind, expected: String) {
    // Raw values are API: a theme persisted against one spelling must keep resolving.
    #expect(kind.rawValue == expected)
  }

  // MARK: - Degenerate input

  @Test(
    "Degenerate inline documents scan without failing and still tile",
    arguments: [
      "*", "**", "***", "****", "*****", "_", "___", "`", "``", "[", "]", "[]", "()",
      "[](", "[]()", "![", "![]()", "\\", "\\\\", "*`*`*", "[*](*)", "a**b*c**d*e",
      "*a**b*c*d**e*", "  ", "\t\t*x*", "***a*b*c***",
    ])
  func degenerateInlineDocuments(text: String) {
    let result = Self.fullScan(text)
    #expect(result.spans.reduce(0) { $0 + $1.range.count } == text.utf16.count)
  }

  @Test("A line of pathological delimiters scans in linear time")
  func pathologicalDelimiterLinesTerminate() {
    // Without CommonMark's `openers_bottom`, a line of closers that never match searches
    // the whole delimiter stack once per closer — quadratic, and a one-megabyte line then
    // does not scan at all (REQUIREMENTS.md § Degenerate input). This is not a wall-clock
    // assertion, which would be machine dependent; it is a "does it come back" assertion at
    // a size where the quadratic version does not.
    for unit in ["a* ", "a_ ", "*a ", "[a](b) ", "`a "] {
      let text = String(repeating: unit, count: 4000)
      let result = Self.fullScan(text)
      #expect(result.spans.reduce(0) { $0 + $1.range.count } == text.utf16.count)
    }
  }
}
