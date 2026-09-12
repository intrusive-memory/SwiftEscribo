import Testing

@testable import EscriboCore

/// Cross-line inline spans inside **containers**: blockquotes and list items
/// (REQUIREMENTS-1.1.0 § 3, § 4.1).
///
/// ## Why this is a separate file from `MarkdownCrossLineSpanTests`
///
/// Sortie 3a joined **paragraph** blocks, which was tractable because a paragraph line
/// carries no marker spans at all — `scanParagraph` emits the inline pass's output and
/// nothing else, so a line's spans could be replaced wholesale. A blockquote line carries
/// its `> `, and a list-item line its `- ` and possibly a task checkbox, fused with the
/// inline spans into one exact tiling. Joining those blocks means replacing the inline half
/// and leaving the marker half **byte-identical**, which is the failure mode this file is
/// really about: a styled `> `, or a content span that has swallowed an indent, is what
/// going wrong looks like.
///
/// So every test here asserts the markers as well as the content, and
/// ``markersAreUntouchedByJoining`` asserts them against a non-joining variant of the same
/// document so that "unchanged" is measured rather than assumed.
///
/// ## These tests were written before the implementation
///
/// Deliberately, and on instruction. Twice in this mission a predicate introduced for
/// performance turned out to carry a correctness obligation that only a test for the
/// *inverse* edit could catch — `deletingTheCloserUnstylesTheFirstLine` in 3a being the
/// case that broke a two-syntax-line threshold. The removal tests below
/// (``deletingACloserInsideABlockquoteRepaintsTheOpeningLine``,
/// ``deletingACloserInsideAListItemRepaintsTheOpeningLine``, and
/// ``deepeningTheLastLineOfABlockquoteUnstylesTheFirst``) exist before the code they
/// constrain, not after it.
@Suite("Markdown inline — blockquote and list-item joining")
struct MarkdownContainerSpanTests {

  // MARK: - Helpers

  static func fullScan(
    _ text: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> ScanResult {
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    let result = scanner.fullScan(text)
    ScanInvariants.check(
      result, text: text, editedRange: nil, "container spans of \(text.debugDescription)",
      sourceLocation: sourceLocation)
    return result
  }

  static func ranges(_ result: ScanResult, styled style: StyleSet) -> [Range<Int>] {
    result.spans.filter { $0.style.contains(style) }.map(\.range)
  }

  /// The **block markers** — marker-role spans carrying no emphasis.
  ///
  /// The style filter is what separates a block marker from an inline one: the inline pass
  /// emits marker-role spans of its own for the `**` delimiters, and they carry the style
  /// they delimit. A `> ` or a `- ` never does.
  static func blockMarkers(_ result: ScanResult) -> [Range<Int>] {
    result.spans.filter { $0.role == .marker && $0.style.isEmpty }.map(\.range)
  }

  // MARK: - Emphasis across a hard wrap in a blockquote

  @Test("Emphasis pairs across a hard wrap inside a blockquote, and the `> ` survives")
  func strongPairsAcrossAWrapInsideABlockquote() {
    // "> **bold\n> text**"
    //   line 0: "> **bold" + \n — marker 0..<2,  content  2..<8,  range 0..<9
    //   line 1: "> text**"      — marker 9..<11, content 11..<17, range 9..<17
    // Joined content: "**bold text**" — the `**` at 0 opens, the `**` at 11 closes.
    let result = Self.fullScan("> **bold\n> text**")

    #expect(result.lineRecords.map(\.element) == [.blockquote, .blockquote])
    #expect(result.lineRecords.map(\.depth) == [0, 0], "same depth, so one block")
    #expect(result.blocks.map(\.kind) == [.blockquote])
    #expect(result.blocks.map(\.lines) == [0..<2])

    #expect(
      Self.ranges(result, styled: .strong) == [2..<4, 4..<8, 11..<15, 15..<17],
      "one strong run over both lines' content, and nothing outside it")

    // The markers: `> ` on each line, unstyled, and exactly two of them.
    #expect(
      Self.blockMarkers(result) == [0..<2, 9..<11],
      "the `> ` prefixes must survive the join unstyled")
    let quoteMarkers = result.spans.filter { $0.range == 0..<2 || $0.range == 9..<11 }
    #expect(quoteMarkers.allSatisfy { $0.kind == .blockquote && $0.role == .marker })
    #expect(quoteMarkers.allSatisfy { $0.style.isEmpty }, "a styled `> ` is the failure mode")

    // Content spans keep the blockquote kind, so a theme still colours them as quoted.
    let strong = result.spans.filter { $0.style.contains(.strong) }
    #expect(strong.allSatisfy { $0.kind == .blockquote })
    #expect(strong.map(\.role) == [.marker, .content, .content, .marker])
  }

  // MARK: - Emphasis across a hard wrap in a list item

  @Test("Emphasis pairs across a list item's continuation line, and the `- ` survives")
  func strongPairsAcrossAListItemContinuation() {
    // "- **bold\n  text**"
    //   line 0: "- **bold" + \n — marker 0..<2, content 2..<8,  range 0..<9
    //   line 1: "  text**"      — a `.paragraph` continuation, content 9..<17 (indent
    //                             included, because that is what `LineRecord` says its
    //                             content is), range 9..<17
    // Joined content: "**bold   text**" — one space joining the pieces, two from the indent.
    let result = Self.fullScan("- **bold\n  text**")

    #expect(result.lineRecords.map(\.element) == [.unorderedListItem, .paragraph])
    #expect(result.blocks.map(\.kind) == [.listItem])
    #expect(result.blocks.map(\.lines) == [0..<2], "the item is one block, marker plus its tail")

    #expect(
      Self.ranges(result, styled: .strong) == [2..<4, 4..<8, 9..<15, 15..<17],
      "one strong run over the marker line's content and the continuation's")

    // The `- ` marker, unstyled and alone: a continuation line has no marker of its own.
    #expect(Self.blockMarkers(result) == [0..<2])
    let bullet = result.spans.filter { $0.range == 0..<2 }
    #expect(bullet.allSatisfy { $0.kind == .listItem && $0.role == .marker })
    #expect(bullet.allSatisfy { $0.style.isEmpty })

    // Each line's spans keep the kind that line would have had on its own: `.listItem` on
    // the marker line, `.text` on the continuation. Block scoping changes which delimiters
    // pair, never what kind a line's content is.
    let strong = result.spans.filter { $0.style.contains(.strong) }
    #expect(
      strong.map(\.kind) == [.listItem, .listItem, .text, .text],
      "the joined pass must not relabel a continuation line as a list item")
  }

  // MARK: - The removal cases

  @Test("Deleting a closer inside a blockquote repaints the opening line")
  func deletingACloserInsideABlockquoteRepaintsTheOpeningLine() {
    // FOUR lines, so `backwardWidening` of 1 is provably insufficient: without the
    // block-aware widening the window reaches line 2 and line 0 keeps a `.strong` it is no
    // longer entitled to. This is the blockquote analogue of 3a's
    // `deletingTheCloserUnstylesTheFirstLine`.
    //
    //   line 0: "> **bold" + \n — content  2..<8,  range  0..<9
    //   line 1: "> middle" + \n — content 11..<17, range  9..<18
    //   line 2: "> more"   + \n — content 20..<24, range 18..<25
    //   line 3: "> text**"      — content 27..<33, range 25..<33
    let before = "> **bold\n> middle\n> more\n> text**"
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    let base = scanner.fullScan(before)
    #expect(base.blocks.map(\.lines) == [0..<4], "all four lines are one blockquote block")
    #expect(!Self.ranges(base, styled: .strong).isEmpty, "it really was strong")

    let after = "> **bold\n> middle\n> more\n> text"
    #expect(ScanInvariants.splice(before, 31..<33, "") == after)
    let result = scanner.incrementalScan(TextEdit(range: 31..<33, replacementLength: 0), in: after)
    ScanInvariants.check(result, text: after, editedRange: 31..<31, "blockquote closer deleted")

    #expect(result.dirtyRange.lowerBound == 0, "line 0 must be repainted")
    let repainted = result.spans.filter { $0.range.overlaps(0..<9) }
    #expect(!repainted.isEmpty)
    #expect(
      repainted.allSatisfy { !$0.style.contains(.strong) },
      "a `.strong` span survived on line 0 after its closer was deleted")

    // And the markers are still markers — a repaint that lost the `> ` would be a
    // different defect with the same cause.
    #expect(Self.blockMarkers(result).contains(0..<2))
  }

  @Test("Deleting a closer inside a list item repaints the opening line")
  func deletingACloserInsideAListItemRepaintsTheOpeningLine() {
    //   line 0: "- **bold" + \n — content  2..<8,  range  0..<9
    //   line 1: "  middle" + \n — content  9..<17, range  9..<18
    //   line 2: "  more"   + \n — content 18..<24, range 18..<25
    //   line 3: "  text**"      — content 25..<33, range 25..<33
    let before = "- **bold\n  middle\n  more\n  text**"
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    let base = scanner.fullScan(before)
    #expect(base.blocks.map(\.lines) == [0..<4], "the item and its three continuations")
    #expect(!Self.ranges(base, styled: .strong).isEmpty, "it really was strong")

    let after = "- **bold\n  middle\n  more\n  text"
    #expect(ScanInvariants.splice(before, 31..<33, "") == after)
    let result = scanner.incrementalScan(TextEdit(range: 31..<33, replacementLength: 0), in: after)
    ScanInvariants.check(result, text: after, editedRange: 31..<31, "list closer deleted")

    #expect(result.dirtyRange.lowerBound == 0, "line 0 must be repainted")
    let repainted = result.spans.filter { $0.range.overlaps(0..<9) }
    #expect(!repainted.isEmpty)
    #expect(
      repainted.allSatisfy { !$0.style.contains(.strong) },
      "a `.strong` span survived on line 0 after its closer was deleted")
    #expect(Self.blockMarkers(result).contains(0..<2), "the `- ` survived the repaint")
  }

  @Test("Deepening the last line of a blockquote un-styles the first")
  func deepeningTheLastLineOfABlockquoteUnstylesTheFirst() {
    // The case that has no paragraph analogue, and the reason the removal-first policy
    // earns its keep in this sortie: the edit does not remove a delimiter at all. It adds
    // one `>`, which changes that line's *depth*, which splits one four-line blockquote
    // block into a three-line one and a one-line one — so the pair that spanned the whole
    // block no longer has a closer inside it, and line 0 must stop being bold.
    //
    // The edit is on line 3 and the repaint is needed on line 0, three lines away.
    let before = "> **bold\n> middle\n> more\n> text**"
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    let base = scanner.fullScan(before)
    #expect(!Self.ranges(base, styled: .strong).isEmpty)

    let after = "> **bold\n> middle\n> more\n>> text**"
    #expect(ScanInvariants.splice(before, 25..<25, ">") == after)
    let result = scanner.incrementalScan(TextEdit(range: 25..<25, replacementLength: 1), in: after)
    ScanInvariants.check(result, text: after, editedRange: 25..<26, "line 3 deepened")

    #expect(
      result.lineRecords.map(\.depth) == [0, 0, 0, 1],
      "the last line is now one level deeper")
    #expect(
      result.blocks.map(\.lines) == [0..<3, 3..<4],
      "a depth change splits the block — grouping's rule from Sortie 1, unchanged")
    #expect(result.dirtyRange.lowerBound == 0, "line 0 must be repainted")
    #expect(
      Self.ranges(result, styled: .strong).isEmpty,
      "the opener at depth 0 has no closer at depth 0 any more")
  }

  // MARK: - Bounded by the container

  @Test("An unmatched opener does not style past the end of its blockquote")
  func unmatchedOpenerStaysInsideItsBlockquote() {
    // Two blockquote blocks with a blank line between them. The first opens a `**` and
    // never closes it; the second closes one it never opened. Each block also carries an
    // emphasis pair that closes inside it, which is what proves the joined pass actually
    // ran rather than the test passing because nothing was joined.
    //
    //   line 0: "> **unclosed"   — range  0..<13
    //   line 1: "> still *here*" — range 13..<28
    //   line 2: ""               — range 28..<29
    //   line 3: "> closed *now*" — range 29..<44
    //   line 4: "> here**"       — range 44..<52
    let result = Self.fullScan("> **unclosed\n> still *here*\n\n> closed *now*\n> here**")

    #expect(result.blocks.map(\.kind) == [.blockquote, .blank, .blockquote])
    #expect(result.blocks.map(\.lines) == [0..<2, 2..<3, 3..<5])
    #expect(
      Self.ranges(result, styled: .strong).isEmpty,
      "a `**` must not pair across a blank line between two blockquotes")

    let emphasis = Self.ranges(result, styled: .emphasis)
    #expect(emphasis.contains { $0.upperBound <= 28 }, "the first quote's emphasis paired")
    #expect(emphasis.contains { $0.lowerBound >= 29 }, "the second quote's emphasis paired")
    #expect(
      result.spans.allSatisfy { $0.style.isEmpty || !$0.range.contains(28) },
      "no styled span may cover the blank line at 28")
  }

  @Test("An unmatched opener does not style past the end of its list item into the next")
  func unmatchedOpenerStaysInsideItsListItem() {
    // Two list items with **no blank line between them**, so they are one non-blank run and
    // two blocks. That is the case that distinguishes per-item joining from per-run
    // joining: if the pass joined the run instead of the item, the `**` on line 0 would
    // find the `**` on line 3 and bold both items.
    //
    //   line 0: "- **unclosed"   — range  0..<13
    //   line 1: "  still *here*" — range 13..<28
    //   line 2: "- closed *now*" — range 28..<43
    //   line 3: "  here**"       — range 43..<51
    let result = Self.fullScan("- **unclosed\n  still *here*\n- closed *now*\n  here**")

    #expect(
      result.lineRecords.map(\.element) == [
        .unorderedListItem, .paragraph, .unorderedListItem, .paragraph,
      ])
    #expect(
      result.blocks.map(\.lines) == [0..<2, 2..<4],
      "each item is its own block — Sortie 1's rule, and what bounds the join")
    #expect(
      Self.ranges(result, styled: .strong).isEmpty,
      "a `**` in one list item must not pair with a `**` in the next")

    let emphasis = Self.ranges(result, styled: .emphasis)
    #expect(emphasis.contains { $0.upperBound <= 28 }, "the first item's emphasis paired")
    #expect(emphasis.contains { $0.lowerBound >= 28 }, "the second item's emphasis paired")
  }

  @Test("A blockquote depth change splits the join, so a `>` cannot pair with a `>>`")
  func depthChangeSplitsTheJoin() {
    // Both depth groups are two lines and both carry a pair that closes inside the group,
    // so both are genuinely joined; the `**` at the start of the depth-0 group and the `**`
    // at the end of the depth-1 group are the delimiters that must not meet.
    //
    //   line 0: "> **bold *x"   — range  0..<12   depth 0
    //   line 1: "> y* more"     — range 12..<22   depth 0
    //   line 2: ">> text *p"    — range 22..<33   depth 1
    //   line 3: ">> q* here**"  — range 33..<45   depth 1
    let result = Self.fullScan("> **bold *x\n> y* more\n>> text *p\n>> q* here**")

    #expect(result.lineRecords.map(\.element) == [.blockquote, .blockquote, .blockquote, .blockquote])
    #expect(result.lineRecords.map(\.depth) == [0, 0, 1, 1])
    #expect(
      result.blocks.map(\.lines) == [0..<2, 2..<4],
      "consecutive blockquote lines group only at the same depth")

    #expect(
      Self.ranges(result, styled: .strong).isEmpty,
      "the `**` at depth 0 must not pair with the `**` at depth 1")

    let emphasis = Self.ranges(result, styled: .emphasis)
    #expect(emphasis.contains { $0.upperBound <= 22 }, "the depth-0 group's emphasis paired")
    #expect(emphasis.contains { $0.lowerBound >= 22 }, "the depth-1 group's emphasis paired")
  }

  // MARK: - Markers are untouched, measured rather than assumed

  @Test("Joining leaves a container's markers byte-identical")
  func markersAreUntouchedByJoining() {
    // The same documents twice: once where the pair closes and the joined pass rewrites
    // every content span, once where it does not. The marker spans must be identical in
    // both, which is the only way to say "untouched" without trusting the implementation
    // that produced them.
    let quoteJoined = Self.fullScan("> **bold\n> text**")
    let quotePlain = Self.fullScan("> **bold\n> text")
    #expect(!Self.ranges(quoteJoined, styled: .strong).isEmpty, "the first really joins")
    #expect(Self.ranges(quotePlain, styled: .strong).isEmpty, "the second really does not")
    #expect(Self.blockMarkers(quoteJoined) == [0..<2, 9..<11])
    #expect(
      Self.blockMarkers(quotePlain) == [0..<2, 9..<11],
      "the `> ` prefixes are the same spans whether the content paired or not")

    let itemJoined = Self.fullScan("- **bold\n  text**")
    let itemPlain = Self.fullScan("- **bold\n  text")
    #expect(!Self.ranges(itemJoined, styled: .strong).isEmpty)
    #expect(Self.ranges(itemPlain, styled: .strong).isEmpty)
    #expect(Self.blockMarkers(itemJoined) == [0..<2])
    #expect(Self.blockMarkers(itemPlain) == [0..<2])

    // A task-list checkbox is a second marker on the same line, and it must survive too.
    //   "- [x] **bold" — `- ` is 0..<2, `[x] ` is 2..<6, content is 6..<12
    let checkbox = Self.fullScan("- [x] **bold\n  text**")
    #expect(!Self.ranges(checkbox, styled: .strong).isEmpty, "the pair still joins")
    #expect(
      Self.blockMarkers(checkbox) == [0..<2, 2..<6],
      "the bullet and the checkbox both survive as unstyled markers")
    #expect(
      checkbox.spans.contains { $0.range == 2..<6 && $0.kind == .taskListChecked },
      "and the checkbox keeps its own kind rather than the block's")
  }

  @Test("A container whose content has no delimiters is byte-identical to 0.3.0")
  func containersWithoutDelimitersAreUnchanged() {
    // The bound on this sortie's regression surface, the same one 3a claimed for
    // paragraphs: a document whose containers carry no inline syntax is not joined at all,
    // so its spans cannot have moved.
    let quote = Self.fullScan("> one\n> two\n> three")
    #expect(quote.blocks.map(\.lines) == [0..<3])
    #expect(quote.spans.allSatisfy { $0.style.isEmpty })
    #expect(Self.blockMarkers(quote) == [0..<2, 6..<8, 12..<14])

    let item = Self.fullScan("- one\n  two\n  three")
    #expect(item.blocks.map(\.lines) == [0..<3])
    #expect(item.spans.allSatisfy { $0.style.isEmpty })
    #expect(Self.blockMarkers(item) == [0..<2])
  }
}
