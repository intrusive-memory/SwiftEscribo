import Testing

@testable import EscriboCore

/// The **cross-line inline span** pass: emphasis, code spans, and links that open on one
/// line of a paragraph and close on another (REQUIREMENTS-1.1.0 § 3, § 7 test 2).
///
/// ## What changed, and what a failure here means
///
/// Through 0.3.0 the inline pass ran once per line, so `**bold` on one line and `text**` on
/// the next produced four literal asterisks on screen. From 0.4.0 a **paragraph** block's
/// inline pass runs over the block's joined content, so the pair pairs. Every expectation
/// below is written out by hand in document coordinates; none is read off the scanner.
///
/// The failure mode this file guards is the one a user would file a bug about: an unmatched
/// opener styling past the end of its block. ``unmatchedOpenerDoesNotStylePastTheBlank`` is
/// that test, and it is the one to look at first if this file goes red.
///
/// ## Joined offsets, and why the arithmetic below is so tidy
///
/// Pieces are joined with **one space**, and every fixture here uses `\n` terminators of
/// **one** code unit, so a piece's joined offset and its document offset coincide. That is
/// a property of these fixtures rather than of the implementation — a CRLF document would
/// make the two differ by one per line — and it is why the expectations can be read
/// straight off the source text.
@Suite("Markdown inline — cross-line spans")
struct MarkdownCrossLineSpanTests {

  // MARK: - Helpers

  /// Full-scans `text` and asserts every `ScanResult` invariant on the way out.
  ///
  /// The invariant harness is doing real work in this file: the joined pass splits spans at
  /// piece boundaries and re-tiles each line, so an off-by-one in the splitter shows up as
  /// a tiling violation here rather than as a subtly wrong style.
  static func fullScan(
    _ text: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> ScanResult {
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    let result = scanner.fullScan(text)
    ScanInvariants.check(
      result, text: text, editedRange: nil, "cross-line spans of \(text.debugDescription)",
      sourceLocation: sourceLocation)
    return result
  }

  /// The ranges of every span carrying `style`, in document order.
  static func ranges(_ result: ScanResult, styled style: StyleSet) -> [Range<Int>] {
    result.spans.filter { $0.style.contains(style) }.map(\.range)
  }

  // MARK: - (a) Emphasis across a hard wrap

  @Test("(a) `**` opened on one line and closed on the next is one strong run, split by line")
  func strongPairsAcrossAHardWrap() {
    // "**bold\ntext**"
    //   line 0: "**bold" + \n   — content 0..<6,  range 0..<7
    //   line 1: "text**"        — content 7..<13, range 7..<13
    // Joined: "**bold text**" — the `**` at 0 opens, the `**` at 11 closes.
    let result = Self.fullScan("**bold\ntext**")

    #expect(
      result.lineRecords.map(\.element) == [.paragraph, .paragraph],
      "the fixture must be two paragraph lines — one block, not two")
    #expect(result.blocks.map(\.kind) == [.paragraph], "…and therefore exactly one block")

    // The criterion: ONE strong run, realized as one piece per line. Written as the
    // complete list of strong ranges so that a span leaking onto the terminator, or a
    // missing piece on either line, both fail.
    #expect(
      Self.ranges(result, styled: .strong) == [0..<2, 2..<6, 7..<11, 11..<13],
      "the strong run covers both lines' content and nothing else")

    // The delimiters are markers and the text between them is content, exactly as they are
    // on a single line — block scoping changes where the pass runs, not what it emits.
    let strong = result.spans.filter { $0.style.contains(.strong) }
    #expect(strong.map(\.role) == [.marker, .content, .content, .marker])
    #expect(strong.allSatisfy { $0.kind == .text }, "a paragraph's inline spans carry `.text`")

    // The one gap in the run is the line terminator, which is not content and must not be
    // styled — a styled terminator is how a trailing-newline artifact reaches the screen.
    let terminator = result.spans.first { $0.range == 6..<7 }
    #expect(terminator?.style.isEmpty == true, "the `\\n` between the pieces is unstyled")

    // cmark-gfm agrees: emphasis spans a softbreak inside a paragraph. This is a
    // CommonMark-derived expectation, not a house convention.
  }

  // MARK: - (b) A code span across a soft wrap

  @Test("(b) A code span opened on one line and closed on the next pairs")
  func codeSpanPairsAcrossASoftWrap() {
    // "a `code\nspan` b"
    //   line 0: "a `code" + \n  — content 0..<7,  range 0..<8
    //   line 1: "span` b"       — content 8..<15, range 8..<15
    // Joined: "a `code span` b" — the backtick at 2 opens, the backtick at 12 closes.
    let result = Self.fullScan("a `code\nspan` b")

    #expect(result.blocks.map(\.kind) == [.paragraph])
    #expect(
      Self.ranges(result, styled: .inlineCode) == [2..<3, 3..<7, 8..<12, 12..<13],
      "the code span covers both lines' halves, markers included")

    let code = result.spans.filter { $0.style.contains(.inlineCode) }
    #expect(code.map(\.role) == [.marker, .content, .content, .marker])
    #expect(
      code.allSatisfy { $0.kind == .text },
      "a code span keeps the enclosing block's kind — `.inlineCode` is a style flag")

    // The prose on either side of the span is untouched, which is what says the span ends
    // where it should rather than swallowing the rest of the block.
    #expect(result.spans.contains { $0.range == 0..<2 && $0.style.isEmpty })
    #expect(result.spans.contains { $0.range == 13..<15 && $0.style.isEmpty })

    // CommonMark-derived: a code span may contain a softbreak, which renders as a space.
  }

  // MARK: - (c) An unmatched opener is bounded by its block

  @Test("(c) An unmatched `**` does not style past the blank line that ends its block")
  func unmatchedOpenerDoesNotStylePastTheBlank() {
    // The regression this sortie could plausibly introduce, stated as the document that
    // would expose it. The first block opens a `**` and never closes it; the second closes
    // a `**` it never opened. If block scoping leaked across the blank line the two would
    // pair and style everything between them, the blank line included.
    //
    // Both blocks carry a delimiter on two lines, so both are genuinely joined — the
    // emphasis assertions below prove the joined pass ran, which is what stops this from
    // passing for the trivial reason that nothing was joined at all.
    //
    //   line 0: "**unclosed"   — content  0..<10, range  0..<11
    //   line 1: "still *here*" — content 11..<23, range 11..<24
    //   line 2: ""             — blank,           range 24..<25
    //   line 3: "closed *now*" — content 25..<37, range 25..<38
    //   line 4: "here**"       — content 38..<44, range 38..<44
    let text = "**unclosed\nstill *here*\n\nclosed *now*\nhere**"
    let result = Self.fullScan(text)

    #expect(
      result.lineRecords.map(\.element) == [
        .paragraph, .paragraph, .blank, .paragraph, .paragraph,
      ])
    #expect(
      result.blocks.map(\.kind) == [.paragraph, .blank, .paragraph],
      "two paragraph blocks with a blank between them — the blank is the boundary")
    #expect(result.blocks.map(\.lines) == [0..<2, 2..<3, 3..<5])

    // The whole criterion: the opener in the first block and the closer in the second never
    // meet, so nothing anywhere is strong.
    #expect(
      Self.ranges(result, styled: .strong).isEmpty,
      "an unmatched `**` must not pair across a block boundary")

    // And the joined pass really did run in both blocks, which is what makes the assertion
    // above meaningful: each block's own `*here*` and `*now*` paired inside it.
    let emphasis = Self.ranges(result, styled: .emphasis)
    #expect(!emphasis.isEmpty)
    #expect(
      emphasis.contains { $0.upperBound <= 24 }, "the first block's emphasis paired")
    #expect(
      emphasis.contains { $0.lowerBound >= 25 }, "the second block's emphasis paired")

    // Nothing styled straddles the blank line, stated as a range rather than a feeling.
    #expect(
      result.spans.allSatisfy { $0.style.isEmpty || !$0.range.contains(24) },
      "no styled span may cover the blank line at 24")
    #expect(result.spans.allSatisfy { $0.kind == .text })
  }

  @Test("An unmatched opener does not style past a non-blank element boundary either")
  func unmatchedOpenerDoesNotStylePastAHeading() {
    // A blank line is not the only thing that ends a paragraph block. A heading does too,
    // and the joined pass must respect that boundary for the same reason.
    //
    //   line 0: "**unclosed" — range  0..<11
    //   line 1: "# Heading"  — range 11..<21
    //   line 2: "more**"     — range 21..<27
    let result = Self.fullScan("**unclosed\n# Heading\nmore**")

    #expect(result.lineRecords.map(\.element) == [.paragraph, .heading, .paragraph])
    #expect(result.blocks.map(\.kind) == [.paragraph, .heading, .paragraph])
    #expect(
      Self.ranges(result, styled: .strong).isEmpty,
      "a heading between the delimiters bounds each block, so neither `**` pairs")
  }

  // MARK: - (d) An edit on the second line restyles the first

  @Test("(d) Closing a `**` on the second line restyles the first line")
  func editOnTheSecondLineRestylesTheFirst() {
    // The incremental half of the feature, and the reason the rescan window had to widen
    // backwards: convergence alone would have stopped at the edited line and left the
    // first line painted with literal asterisks.
    // FOUR lines, not two, and that is the point: `backwardWidening` is 1 for Markdown, so
    // an edit on line 3 would reach back only to line 2 under the 0.3.0 window. Line 0
    // can only be repainted because the joined pass widens to the block's first line.
    //
    //   line 0: "**bold" + \n — content  0..<6,  range  0..<7
    //   line 1: "middle" + \n — content  7..<13, range  7..<14
    //   line 2: "more"   + \n — content 14..<18, range 14..<19
    //   line 3: "text"        — content 19..<23, range 19..<23
    let before = "**bold\nmiddle\nmore\ntext"
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    let base = scanner.fullScan(before)
    ScanInvariants.check(base, text: before, editedRange: nil, "unclosed base")

    // The premise: unpaired, so nothing is strong yet.
    #expect(Self.ranges(base, styled: .strong).isEmpty, "`**bold middle more text` has no closer")
    #expect(base.blocks.map(\.lines) == [0..<4], "all four lines are one paragraph block")

    // Type the closing `**` at the very end of line 3.
    let after = "**bold\nmiddle\nmore\ntext**"
    #expect(ScanInvariants.splice(before, 23..<23, "**") == after)
    let result = scanner.incrementalScan(TextEdit(range: 23..<23, replacementLength: 2), in: after)
    ScanInvariants.check(result, text: after, editedRange: 23..<25, "closer typed")

    // The criterion: the dirty range reaches back to line 0. Under the 0.3.0 window this
    // is 14 — one line back from the edit — and lines 0 and 1 keep stale spans on screen.
    #expect(
      result.dirtyRange.lowerBound == 0,
      "an edit on line 3 must dirty line 0, because line 0's spans just changed")
    #expect(result.lines.lowerBound == 0)

    // And the substance: every line of the block is now strong, which is what the user
    // sees change. One run, one piece per line, terminators unstyled.
    #expect(
      Self.ranges(result, styled: .strong) == [0..<2, 2..<6, 7..<13, 14..<18, 19..<23, 23..<25])

    // The incremental scanner still agrees with a full scan of the same text — "dirtied
    // correctly", not merely "dirtied widely".
    var fresh = IncrementalScanner(grammar: MarkdownGrammar())
    let full = fresh.fullScan(after)
    ScanInvariants.check(full, text: after, editedRange: nil, "closer typed, full")
    ScanInvariants.expectSameElements(
      scanner.startStates, fresh.startStates, "startStates", "closer typed")
    #expect(Self.ranges(full, styled: .strong) == Self.ranges(result, styled: .strong))
  }

  @Test("Deleting a closer on the second line un-styles the first")
  func deletingTheCloserUnstylesTheFirstLine() {
    // The inverse edit, because the interesting failure is asymmetric: a scanner that
    // widens backwards when adding style but not when removing it leaves the first line
    // bold forever, which is the stale-attribute defect the whole design exists to
    // prevent.
    let before = "**bold\nmiddle\nmore\ntext**"
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    let base = scanner.fullScan(before)
    #expect(!Self.ranges(base, styled: .strong).isEmpty, "it really was strong")

    let after = "**bold\nmiddle\nmore\ntext"
    let result = scanner.incrementalScan(TextEdit(range: 23..<25, replacementLength: 0), in: after)
    ScanInvariants.check(result, text: after, editedRange: 23..<23, "closer deleted")

    #expect(result.dirtyRange.lowerBound == 0, "line 0 must be repainted")
    let repainted = result.spans.filter { $0.range.overlaps(0..<6) }
    #expect(!repainted.isEmpty)
    #expect(
      repainted.allSatisfy { !$0.style.contains(.strong) },
      "a `.strong` span survived on line 0 after its closer was deleted")
  }

  // MARK: - The perf backstop

  /// A paragraph of `lines` lines whose first line opens a `**` and whose last line closes
  /// it, with inert filler between.
  ///
  /// No blank line anywhere, so the whole thing is one paragraph block — which is what
  /// makes it a test of the backstop rather than of grouping.
  static func longParagraph(lines: Int) -> String {
    var out = ["**bold"]
    out.append(contentsOf: (0..<(lines - 2)).map { "filler \($0)" })
    out.append("text**")
    return out.joined(separator: "\n")
  }

  @Test("The joined pass applies at the line limit and stops one line past it")
  func joinedPassStopsAtTheLineLimit() {
    // The boundary asserted *at* the threshold rather than left implicit, in both
    // directions, so a change to `joinedContentLineLimit` moves both halves together and
    // an off-by-one in the comparison cannot hide.
    let atLimit = Self.longParagraph(lines: joinedContentLineLimit)
    let overLimit = Self.longParagraph(lines: joinedContentLineLimit + 1)

    let inside = Self.fullScan(atLimit)
    #expect(
      inside.lineRecords.count == joinedContentLineLimit,
      "the fixture must really be exactly the limit")
    #expect(inside.blocks.map(\.kind) == [.paragraph], "one block, no blank lines")
    #expect(
      !Self.ranges(inside, styled: .strong).isEmpty,
      "at exactly the limit the pair still pairs")

    let outside = Self.fullScan(overLimit)
    #expect(outside.lineRecords.count == joinedContentLineLimit + 1)
    #expect(outside.blocks.map(\.kind) == [.paragraph])
    #expect(
      Self.ranges(outside, styled: .strong).isEmpty,
      "one line past the limit the block line-scopes, and the stars are literal again")

    // The other half, and the stronger claim: the rescan *window* moves with the verdict.
    // At the limit an edit on the last line widens back to the block's first line, because
    // the joined pass is about to run over all of it. One line past the limit it must not
    // widen at all — the pass will be skipped, so paying for a 200-line rescan would buy
    // nothing. That is the defect that broke `ordinaryEditsStayLocal`, asserted here at the
    // exact boundary where the two behaviours meet.
    var insideScanner = IncrementalScanner(grammar: MarkdownGrammar())
    _ = insideScanner.fullScan(atLimit)
    let insideEnd = atLimit.utf16.count
    let insideEdit = insideScanner.incrementalScan(
      TextEdit(range: insideEnd..<insideEnd, replacementLength: 1), in: atLimit + "!")
    #expect(
      insideEdit.lines.lowerBound == 0,
      "at the limit, an edit on the last line widens back to the block's first line")

    var outsideScanner = IncrementalScanner(grammar: MarkdownGrammar())
    _ = outsideScanner.fullScan(overLimit)
    let outsideEnd = overLimit.utf16.count
    let outsideEdit = outsideScanner.incrementalScan(
      TextEdit(range: outsideEnd..<outsideEnd, replacementLength: 1), in: overLimit + "!")
    #expect(
      outsideEdit.lines.count <= 3,
      """
      past the limit the window must not widen; rescanned \(outsideEdit.lines.count) lines
      """)
  }

  @Test("An edit in ordinary prose does not widen the window, however long the paragraph")
  func proseWithNoDelimitersNeverWidens() {
    // The condition that keeps typing cheap, stated directly rather than left to the
    // performance suite. Joining can only change spans when two or more of a block's lines
    // carry inline syntax; prose carries none, so the window stays where 0.3.0 put it even
    // though the block is well inside the backstop.
    let text = (0..<40).map { "line \($0) of ordinary prose" }.joined(separator: "\n")
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    let base = scanner.fullScan(text)
    #expect(base.blocks.map(\.kind) == [.paragraph], "one 40-line block, no blank lines")

    // One character into the middle of the block.
    let at = text.utf16.count / 2
    let edited = ScanInvariants.splice(text, at..<at, "x")
    let result = scanner.incrementalScan(TextEdit(range: at..<at, replacementLength: 1), in: edited)
    ScanInvariants.check(result, text: edited, editedRange: at..<(at + 1), "prose edit")

    #expect(
      result.lines.count <= 3,
      "rescanned \(result.lines.count) lines for one character in delimiter-free prose")
  }

  @Test("Crossing the backstop degrades to the 0.3.0 reading rather than to a broken one")
  func backstopDegradesGracefully() {
    // The backstop is a perf guard, not a correctness boundary. Above it every line must
    // still be scanned, still tile, and still style whatever pairs *within* one line — the
    // exact behaviour 0.3.0 shipped.
    // Built without Foundation: one line in the middle carries a pair that closes on
    // itself, so it must still style, and the block's own `**` … `**` must not.
    var lines = ["**bold"]
    lines.append(contentsOf: (0..<(joinedContentLineLimit - 2)).map { "filler \($0)" })
    lines.append("a **self closing** pair")
    lines.append("text**")
    #expect(lines.count == joinedContentLineLimit + 1, "one line past the limit")

    let result = Self.fullScan(lines.joined(separator: "\n"))
    #expect(result.blocks.map(\.kind) == [.paragraph], "one block, no blank lines")

    let strong = Self.ranges(result, styled: .strong)
    #expect(
      !strong.isEmpty, "a pair that closes on its own line still pairs above the backstop")
    #expect(
      strong.allSatisfy { $0.lowerBound > 6 },
      "…and nothing on the first line is strong: its `**` never found a closer")
  }

  // MARK: - What must not have changed

  @Test("A single-line paragraph is byte-identical to the line-scoped pass")
  func singleLineParagraphsAreUnchanged() {
    // The joined pass is skipped for one-line blocks precisely so this holds, and it is
    // the claim that bounds this sortie's regression surface: an adopter whose documents
    // have no hard-wrapped emphasis sees no change at all.
    let result = Self.fullScan("a **bold** word\n\nand *more* here")

    #expect(result.blocks.map(\.kind) == [.paragraph, .blank, .paragraph])
    #expect(
      result.blocks.allSatisfy { $0.lines.count == 1 },
      "every block here is one line, so the joined pass is skipped throughout")
    #expect(Self.ranges(result, styled: .strong) == [2..<4, 4..<8, 8..<10])
    #expect(Self.ranges(result, styled: .emphasis) == [21..<22, 22..<26, 26..<27])
  }

  @Test("A hard break at the end of an interior line survives joining")
  func hardBreaksAreDecidedPerLine() {
    // A hard break is two trailing spaces — a property of where a LINE ends, and the
    // joined buffer has no line ends in it. So each piece's break is taken out before
    // joining. Without that, an interior line's break is simply lost.
    //
    // Both lines carry a delimiter deliberately: that is what makes the block joinable, so
    // this really exercises the joined path rather than falling back to line scoping.
    //
    //   line 0: "*one*  " + \n — content  0..<7, the break is 5..<7
    //   line 1: "*two*"        — content  8..<13
    let result = Self.fullScan("*one*  \n*two*")

    #expect(result.blocks.map(\.kind) == [.paragraph])
    #expect(result.blocks.first?.lines == 0..<2, "one block")
    #expect(
      result.spans.contains { $0.range == 5..<7 && $0.kind == .hardBreak && $0.role == .marker },
      "the interior line's hard break must survive the join")
    #expect(
      Self.ranges(result, styled: .emphasis) == [0..<1, 1..<4, 4..<5, 8..<9, 9..<12, 12..<13],
      "…and both lines' emphasis still pairs, so the joined pass really ran")

    // CommonMark-derived: two trailing spaces before a newline are a hard line break.
  }

  @Test("Fountain does not join, so a cue's `*` cannot pair with a `*` in the dialogue")
  func fountainStaysLineScoped() {
    // The other half of decision 4 in the Sortie 3 report, asserted rather than assumed.
    // A speech block joins a cue, its parentheticals, and its dialogue; joining their
    // content would let a delimiter in a character name pair with one three lines down.
    var scanner = IncrementalScanner(grammar: FountainGrammar())
    let result = scanner.fullScan("BOB*\nHello *there.")

    #expect(!result.blocks.isEmpty, "Fountain still groups blocks")
    #expect(
      Self.ranges(result, styled: .emphasis).isEmpty,
      "Fountain's inline pass is line-scoped and must stay that way")
  }
}
