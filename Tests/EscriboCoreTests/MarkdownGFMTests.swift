import Testing

@testable import EscriboCore

/// GFM extensions — tables, task-list checkboxes, strikethrough, autolinks — and YAML
/// frontmatter as a distinct leading region.
///
/// ## Why every expectation here is written out by hand
///
/// `ScanGateTests`'s `incrementalScan == fullScan` property **cannot** catch a bug in this
/// grammar, and frontmatter is the worst case for it: both sides of the gate's comparison
/// run the same grammar, so a frontmatter rule that opens a region on the wrong line is
/// wrong identically on both sides and the gate stays green. The supervisor has now proved
/// that three separate ways on this codebase — a Fountain grammar with its lookahead set to
/// zero, recognizing no character cues at all, left the gate green at 288/288 while 62
/// hand-written tests went red.
///
/// So nothing here infers a classification from a green gate. Every element, every span
/// range, every ``SpanKind``, and every ``TableAlignment`` below is a value a human computed
/// from the UTF-16 code units of the fixture and wrote down.
///
/// ## The boundary this suite exists to pin
///
/// `---` already had a meaning before this sortie: Sortie 18 ships it as a thematic break,
/// and under an open paragraph as a setext heading underline. Frontmatter is therefore a
/// **position-dependent reinterpretation of a token that already means something**, and the
/// whole risk is in the boundary. Two tests state the two sides of it against fixtures whose
/// only difference is where the `---` sits, and the second of them carries a negative
/// assertion — no frontmatter span anywhere in the document — because "line 5 is a thematic
/// break" on its own is a claim Sortie 18 already satisfied and would stay green with every
/// line of this sortie deleted.
@Suite("Markdown grammar — GFM extensions and YAML frontmatter")
struct MarkdownGFMTests {

  // MARK: - Helpers

  /// Full-scans `text` **and asserts every `ScanResult` invariant on the way out**.
  ///
  /// The harness lives here rather than at each call site so that adding a test to this
  /// suite cannot omit it.
  static func fullScan(
    _ text: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> ScanResult {
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    let result = scanner.fullScan(text)
    ScanInvariants.check(
      result, text: text, editedRange: nil, "markdown GFM scan of \(text.debugDescription)",
      sourceLocation: sourceLocation)
    return result
  }

  /// Every line's element, in order.
  static func elements(_ text: String, sourceLocation: SourceLocation = #_sourceLocation)
    -> [ElementKind]
  {
    fullScan(text, sourceLocation: sourceLocation).lineRecords.map(\.element)
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
  /// Whole-layout rather than spot checks: a spot check cannot see a span that should not
  /// be there, and an extra span is exactly what a mis-encoded delimiter produces.
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

  /// Asserts that an incremental scan of one edit agrees with a full scan of the result —
  /// **the whole painted document**, plus every line's start state.
  ///
  /// The painted-document comparison is the one that can see a rescan window that was too
  /// small; comparing the returned `ScanResult` alone asks only "is what you repainted
  /// correct?" and never "did you repaint everything that changed?".
  static func expectConvergence(
    _ before: String,
    replacing range: Range<Int>,
    with replacement: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    let full = scanner.fullScan(before)
    ScanInvariants.check(
      full, text: before, editedRange: nil, "full scan of \(before.debugDescription)",
      sourceLocation: sourceLocation)
    var painted = ScanInvariants.PaintedDocument(full)

    let after = ScanInvariants.splice(before, range, replacement)
    let replacementLength = replacement.utf16.count
    let result = scanner.incrementalScan(
      TextEdit(range: range, replacementLength: replacementLength), in: after)
    let note = "\(before.debugDescription) → \(after.debugDescription)"
    ScanInvariants.check(
      result, text: after,
      editedRange: range.lowerBound..<(range.lowerBound + replacementLength), note,
      sourceLocation: sourceLocation)
    painted.apply(result, newLineCount: ScanInvariants.lineCount(of: after))

    var oracle = IncrementalScanner(grammar: MarkdownGrammar())
    let fullAfter = oracle.fullScan(after)
    ScanInvariants.expectSameElements(
      painted.lines, ScanInvariants.paintedLines(of: fullAfter), "painted lines", note,
      sourceLocation: sourceLocation)
    ScanInvariants.expectSameElements(
      scanner.startStates, oracle.startStates, "start states", note,
      sourceLocation: sourceLocation)
  }

  // MARK: - Frontmatter: the criterion, and the boundary

  @Test("A document opening with `---` is frontmatter with key and value spans, not a break")
  func frontmatterAtTheTopOfTheDocumentIsNotAThematicBreak() {
    // `---\ntype: docs\n---\nbody\n`, code unit by code unit:
    //
    //   line 0   0..<4    `-` `-` `-` `\n`
    //   line 1   4..<15   t  y  p  e  :  ' ' d  o  c  s  `\n`
    //                     4  5  6  7  8   9  10 11 12 13  14
    //   line 2  15..<19   `-` `-` `-` `\n`
    //   line 3  19..<24   b  o  d  y  `\n`
    //   line 4  24..<24   the final empty line a trailing terminator produces
    let text = "---\ntype: docs\n---\nbody\n"

    Self.expectLayout(
      text,
      [
        // The opening fence. `.frontmatterDelimiter`, NOT `.thematicBreak` — that is the
        // criterion, and it is the whole difference this sortie makes to line 1.
        Expected(0..<3, .frontmatterDelimiter, [], .marker),
        Expected(3..<4, .text),
        // The entry: key, then the `:` and its trailing space as a marker carrying the
        // key's own kind, then the value.
        Expected(4..<8, .frontmatterKey),
        Expected(8..<10, .frontmatterKey, [], .marker),
        Expected(10..<14, .frontmatterValue),
        Expected(14..<15, .text),
        // The closing fence.
        Expected(15..<18, .frontmatterDelimiter, [], .marker),
        Expected(18..<19, .text),
        // Out the other side: ordinary Markdown resumes.
        Expected(19..<23, .text),
        Expected(23..<24, .text),
      ])

    #expect(
      Self.elements(text) == [
        .frontmatterDelimiter, .frontmatter, .frontmatterDelimiter, .paragraph, .blank,
      ])

    // Stated negatively as well, because the positive form above would still pass if the
    // grammar emitted a thematic break *and* a frontmatter span on the same line.
    let result = Self.fullScan(text)
    #expect(
      !result.spans.contains { $0.kind == .thematicBreak },
      "a document's leading `---` must not be a thematic break")
    #expect(
      !result.lineRecords.contains { $0.element == .thematicBreak },
      "a document's leading `---` must not be a thematic break")
    #expect(result.lineRecords[1].contentRange == 10..<14, "the entry's content is its value")
  }

  @Test("`---` on line 5 is a thematic break, and opens no frontmatter anywhere")
  func aDelimiterBelowTheFirstLineIsAThematicBreak() {
    // `---` on **line 5**, one-based — index 4 — with a blank line above it so that Sortie
    // 18's setext rule does not claim it first. The body below is byte-for-byte the
    // frontmatter fixture above, so the *only* difference between the two documents is
    // where the `---` sits.
    //
    //   line 0  `intro`
    //   line 1  ``
    //   line 2  `more`
    //   line 3  ``
    //   line 4  `---`      <- line 5, one-based
    //   line 5  `type: docs`
    //   line 6  `---`
    //   line 7  `body`
    let text = "intro\n\nmore\n\n---\ntype: docs\n---\nbody"
    let result = Self.fullScan(text)

    #expect(result.lineRecords[4].element == .thematicBreak, "`---` on line 5 is a break")

    // **This is the assertion with teeth.** "Line 5 is a thematic break" was already true
    // before this sortie existed — Sortie 18 shipped it — so that expectation alone would
    // stay green with every line of frontmatter code deleted. What can only be true because
    // the position rule is right is that *no* frontmatter is anywhere in this document:
    // not on the `---`, and not on the `type: docs` line directly beneath it, which is the
    // line an over-broad rule would key off.
    #expect(
      !result.spans.contains {
        $0.kind == .frontmatterDelimiter || $0.kind == .frontmatterKey
          || $0.kind == .frontmatterValue
      },
      "no frontmatter span may appear in a document whose `---` is not on line 1")
    #expect(
      !result.lineRecords.contains {
        $0.element == .frontmatter || $0.element == .frontmatterDelimiter
      },
      "no frontmatter record may appear in a document whose `---` is not on line 1")

    // And the line below it scans as ordinary Markdown, which is what "not a thematic break
    // followed by garbage" means read the other way round.
    #expect(result.lineRecords[5].element == .paragraph)
    #expect(
      Self.elements(text) == [
        .paragraph, .blank, .paragraph, .blank, .thematicBreak, .paragraph, .heading,
        .paragraph,
      ],
      """
      line 6's `---` is a setext underline for the paragraph above it — Sortie 18's rule, \
      unchanged
      """)
  }

  @Test("Exactly three hyphens open a region; four on line one are still a thematic break")
  func onlyExactlyThreeHyphensOpenARegion() {
    // The other half of the boundary. Widening the opener to "three or more" would swallow
    // the top of any document that opens with a rule, and every tool that reads this region
    // spells the fence with exactly three.
    #expect(Self.elements("----\ntype: docs\n")[0] == .thematicBreak)
    #expect(Self.elements("---\ntype: docs\n")[0] == .frontmatterDelimiter)
    // Trailing whitespace is allowed; anything else is not.
    #expect(Self.elements("---  \ntype: docs\n")[0] == .frontmatterDelimiter)
    #expect(Self.elements("--- x\ntype: docs\n")[0] == .paragraph)
    // A fence sits flush left. An indented one is not a fence.
    #expect(Self.elements(" ---\ntype: docs\n")[0] == .thematicBreak)
  }

  @Test("Inside a region, Markdown syntax is not syntax")
  func frontmatterSuppressesMarkdown() {
    // The point of the region being a region: a `#` inside it is a YAML comment and a `- `
    // is a sequence entry. If either were scanned as Markdown the document would come back
    // as "a thematic break followed by garbage", which is the phrase the requirement uses.
    let text = "---\n# a comment\n- name: bob\ntags:\n---\n# A Heading\n"
    #expect(
      Self.elements(text) == [
        .frontmatterDelimiter, .frontmatter, .frontmatter, .frontmatter, .frontmatterDelimiter,
        .heading, .blank,
      ])

    let result = Self.fullScan(text)
    // `- name: bob` finds its key past the sequence dash.
    // `---\n` ends at 4, `# a comment\n` at 16, `- name: bob\n` at 28, `tags:\n` at 34.
    // On line 2 the sequence dash and its space are 16 and 17, so `name` is 18..<22 and
    // `bob` is 24..<27. On line 3 `tags` is 28..<32 and the colon ends the line.
    let keys = result.spans.filter { $0.kind == .frontmatterKey && $0.role == .content }
    #expect(
      keys.map(\.range) == [18..<22, 28..<32],
      "the keys are `name` and `tags`, not `- name` and not the comment")
    // `tags:` has a key and no value, and emits no value span rather than an empty one.
    #expect(result.spans.filter { $0.kind == .frontmatterValue }.map(\.range) == [24..<27])
  }

  @Test("A colon inside a value does not split the key")
  func onlyAColonFollowedByWhitespaceSeparates() {
    // `url: https://example.com` — without YAML's "the colon must be followed by
    // whitespace" rule the key comes back as `url: https` and the value as `//example.com`,
    // which is the sort of wrong that looks right until somebody reads the spans.
    let text = "---\nurl: https://example.com\n---\n"
    let result = Self.fullScan(text)
    #expect(
      result.spans.filter { $0.kind == .frontmatterKey && $0.role == .content }.map(\.range)
        == [4..<7])
    #expect(result.spans.filter { $0.kind == .frontmatterValue }.map(\.range) == [9..<28])
  }

  @Test("Unterminated frontmatter scans to end of document and degrades to `.text`")
  func unterminatedFrontmatterDegradesToText() {
    // The scan path has no error path, so this must not fail — and it must reach the last
    // code unit of the document. What "degrades to `.text`" means for a zero-lookahead
    // grammar is stated on `scanInsideFrontmatter`: a line inside the region that is not
    // `key:`-shaped comes back as a single `.text` span, so a region that was never YAML is
    // `.text` from its second line to the end of the document.
    let text = "---\njust prose\nmore prose"
    let result = Self.fullScan(text)

    #expect(result.lineRecords.count == 3)
    #expect(
      result.lineRecords.map(\.element) == [.frontmatterDelimiter, .frontmatter, .frontmatter])
    #expect(result.dirtyRange == 0..<25, "the scan reaches the last code unit of the document")
    #expect(result.lineRecords.last?.range.upperBound == 25)

    // Every span past the opening fence is `.text`. No key, no value, nothing invented.
    let past = result.spans.filter { $0.range.lowerBound >= 4 }
    #expect(past.allSatisfy { $0.kind == .text }, "unterminated frontmatter is text")
    #expect(past.map(\.range) == [4..<14, 14..<15, 15..<25])

    // A one-line document that is nothing but the opener is the degenerate case of the
    // same thing, and must also come back rather than trapping.
    let alone = Self.fullScan("---")
    #expect(alone.lineRecords.map(\.element) == [.frontmatterDelimiter])
  }

  @Test("Convergence holds across a frontmatter region, in both directions")
  func frontmatterConverges() {
    let document = "---\ntype: docs\ntitle: T\n---\n# Heading\nbody\n"

    // An edit *inside* the region. The region stays open, and every line after it must come
    // back identical to a full scan.
    Self.expectConvergence(document, replacing: 10..<14, with: "guide")

    // An edit that **destroys the opener** at offset zero. Every line of the document
    // changes meaning: the entries become paragraphs and the closing `---` becomes a setext
    // underline. This is the case the position rule could get wrong incrementally, and the
    // reason it cannot is that line 0 begins at offset 0, so an edit that renumbers it must
    // touch it.
    Self.expectConvergence(document, replacing: 0..<1, with: "")

    // And the inverse: typing the opener into a document that had none.
    Self.expectConvergence("type: docs\n---\nbody\n", replacing: 0..<0, with: "---\n")
  }

  // MARK: - Task-list checkboxes

  @Test("`- [ ]` and `- [x]` produce distinguishable checkbox spans")
  func taskListCheckboxesAreDistinguishable() {
    // `- [ ] todo\n- [x] done\n`, code unit by code unit:
    //
    //   line 0   0..<11   `-` ' ' `[` ' ' `]` ' ' t o d o `\n`
    //                      0   1   2   3   4   5  6 7 8 9  10
    //   line 1  11..<22   `-` ' ' `[` `x` `]` ' ' d o n e `\n`
    //                     11  12  13  14  15  16 17 18 19 20 21
    Self.expectLayout(
      "- [ ] todo\n- [x] done\n",
      [
        Expected(0..<2, .listItem, [], .marker),
        Expected(2..<6, .taskListUnchecked, [], .marker),
        Expected(6..<10, .listItem),
        Expected(10..<11, .text),
        Expected(11..<13, .listItem, [], .marker),
        Expected(13..<17, .taskListChecked, [], .marker),
        Expected(17..<21, .listItem),
        Expected(21..<22, .text),
      ])

    // The criterion, stated as the comparison it actually is: the two spans differ, and they
    // differ in `kind` — not in role, not in style, both of which are identical.
    let result = Self.fullScan("- [ ] todo\n- [x] done\n")
    let boxes = result.spans.filter {
      $0.kind == .taskListChecked || $0.kind == .taskListUnchecked
    }
    #expect(boxes.count == 2)
    #expect(boxes[0].kind != boxes[1].kind, "an unchecked box and a checked box are not the same")
    #expect(boxes[0].kind == .taskListUnchecked)
    #expect(boxes[1].kind == .taskListChecked)
    #expect(boxes.allSatisfy { $0.role == .marker && $0.style == [] })

    // `[X]` is checked too, and the record's content range starts past the box.
    let upper = Self.fullScan("- [X] done\n")
    #expect(upper.spans.contains { $0.kind == .taskListChecked })
    #expect(upper.lineRecords[0].contentRange == 6..<10)
  }

  @Test("A bracket that is not a checkbox is ordinary list content")
  func nearMissesAreNotCheckboxes() {
    // Each of these is one code unit away from a checkbox and none of them is one. Without
    // the "followed by whitespace or end of line" rule, the third would be.
    for text in ["- [] a\n", "- [y] a\n", "- [x]a\n", "- [xx] a\n"] {
      let result = Self.fullScan(text)
      #expect(
        !result.spans.contains {
          $0.kind == .taskListChecked || $0.kind == .taskListUnchecked
        },
        "\(text.debugDescription) is not a task list item")
    }
    // An empty item that is nothing but a checkbox is one, though.
    #expect(Self.fullScan("- [ ]\n").spans.contains { $0.kind == .taskListUnchecked })
  }

  @Test("A checkbox does not move the item's content column")
  func checkboxesDoNotChangeListNesting() {
    // GFM measures a list item's content from just past its marker, so a continuation line
    // under `- [ ] a` needs the same indent as one under `- a`. If the checkbox were folded
    // into the content column, the nested item below would come back at depth 0.
    #expect(
      Self.fullScan("- [ ] a\n  - [x] b\n").lineRecords.map(\.depth) == [0, 1, 0],
      "the nested item is depth 1")
  }

  // MARK: - Tables

  @Test("A table alignment row `|:---|---:|` produces alignment-bearing line records")
  func tableDelimiterRowCarriesAlignments() {
    // `| a | b |\n|:---|---:|\n| 1 | 2 |\n`
    //
    // The header row is a paragraph — GFM recognizes a header only by the delimiter row
    // beneath it, which is lookahead this grammar does not have — and the delimiter row is
    // recognized from its own text plus the open paragraph arriving from above.
    let text = "| a | b |\n|:---|---:|\n| 1 | 2 |\n"
    let result = Self.fullScan(text)

    #expect(
      result.lineRecords.map(\.element) == [
        .paragraph, .tableDelimiterRow, .tableRow, .blank,
      ])

    // The criterion. Left from `:---`, right from `---:`, in column order.
    #expect(result.lineRecords[1].tableAlignments == [.left, .right])

    // And nothing else carries alignments, which is what makes the field mean "this row
    // declared them" rather than "this row is in a table".
    #expect(result.lineRecords[0].tableAlignments.isEmpty)
    #expect(result.lineRecords[2].tableAlignments.isEmpty)
    #expect(result.lineRecords[3].tableAlignments.isEmpty)
  }

  @Test(
    "Every alignment spelling is read off its colons",
    arguments: [
      ("|---|", [TableAlignment.unspecified]),
      ("|:---|", [TableAlignment.left]),
      ("|---:|", [TableAlignment.right]),
      ("|:---:|", [TableAlignment.center]),
      ("|:-|-:|:-:|-|", [TableAlignment.left, .right, .center, .unspecified]),
      // Outer pipes are optional in GFM, and a row with no pipe at all is not a delimiter
      // row — it is a setext underline, which is why `---` never reaches this code.
      ("---|---", [TableAlignment.unspecified, .unspecified]),
      (" :--- | ---: ", [TableAlignment.left, .right]),
    ]
  )
  func alignmentSpellings(row: String, expected: [TableAlignment]) {
    let result = Self.fullScan("header\n\(row)\n")
    #expect(result.lineRecords[1].element == .tableDelimiterRow, "\(row) is a delimiter row")
    #expect(result.lineRecords[1].tableAlignments == expected)
  }

  @Test("A delimiter row needs a paragraph above it and at least one pipe in it")
  func delimiterRowsAreNotThematicBreaks() {
    // Under a blank line there is no header, so there is no table — and a `---` with no pipe
    // is a setext underline under a paragraph and a thematic break otherwise. These are the
    // three ways this method could have stolen a line that already had a meaning.
    #expect(Self.elements("\n|:---|---:|\n")[1] == .paragraph, "no header, no table")
    #expect(Self.elements("header\n---\n")[1] == .heading, "no pipe: still a setext underline")
    #expect(Self.elements("\n---\n")[1] == .thematicBreak, "no pipe, no paragraph: still a break")
    #expect(Self.elements("header\n| a b |\n")[1] == .paragraph, "cells must be dashes")
    #expect(Self.elements("header\n|::--|\n")[1] == .paragraph, "two leading colons is not a cell")
  }

  @Test("A table's body ends at a blank line or at a line with no pipe")
  func tablesEndWhereTheyEnd() {
    // The trailing terminator produces a final empty line, which is why every expectation
    // here ends in `.blank`.
    #expect(
      Self.elements("h\n|-|\n| a |\n\n| b |\n") == [
        .paragraph, .tableDelimiterRow, .tableRow, .blank, .paragraph, .blank,
      ],
      "a blank line closes the table; the row after it is a paragraph again")
    #expect(
      Self.elements("h\n|-|\n| a |\n# Heading\n") == [
        .paragraph, .tableDelimiterRow, .tableRow, .heading, .blank,
      ],
      "a line with no pipe closes the table and is scanned as whatever it is")
  }

  @Test("A table row's cells are separated by markers and inline-scanned")
  func tableRowCellLayout() {
    // `h\n|-|\n| **a** |\n` — the row is at 6..<17:
    //
    //    6   7  8  9 10 11 12 13 14 15  16
    //   `|` ' ' `*` `*` a `*` `*` ' ' `|` `\n`
    //    6   7   8   9 10  11  12  13  14  15
    Self.expectLayout(
      "h\n|-|\n| **a** |\n",
      [
        Expected(0..<1, .text),
        Expected(1..<2, .text),
        Expected(2..<5, .tableDelimiter, [], .marker),
        Expected(5..<6, .text),
        Expected(6..<7, .tableCell, [], .marker),
        Expected(7..<8, .tableCell),
        Expected(8..<10, .tableCell, [.strong], .marker),
        Expected(10..<11, .tableCell, [.strong]),
        Expected(11..<13, .tableCell, [.strong], .marker),
        Expected(13..<14, .tableCell),
        Expected(14..<15, .tableCell, [], .marker),
        Expected(15..<16, .text),
      ])
  }

  @Test("An escaped pipe does not end a cell")
  func escapedPipesStayInsideCells() {
    // `\|` is the one escape GFM gives tables and the only way to put a pipe in a cell.
    // The row is `| a \| b |` at 6..<16:
    //
    //   `|` ' '  a  ' ' `\` `|` ' '  b  ' ' `|` `\n`
    //    6   7   8   9  10  11  12  13  14  15  16
    //
    // Two cell separators — 6 and 15 — and the pipe at 11 is **content**, inside the span
    // 11..<15. The backslash at 10 is a marker because a backslash escape is one
    // everywhere in this package, which is a different thing from a cell separator and is
    // why this is asserted as a whole layout rather than by counting markers.
    Self.expectLayout(
      "h\n|-|\n| a \\| b |\n",
      [
        Expected(0..<1, .text),
        Expected(1..<2, .text),
        Expected(2..<5, .tableDelimiter, [], .marker),
        Expected(5..<6, .text),
        Expected(6..<7, .tableCell, [], .marker),
        Expected(7..<10, .tableCell),
        Expected(10..<11, .tableCell, [], .marker),
        Expected(11..<15, .tableCell),
        Expected(15..<16, .tableCell, [], .marker),
        Expected(16..<17, .text),
      ])
  }

  @Test("Convergence holds across a table")
  func tablesConverge() {
    let document = "h\n|:-|-:|\n| a | b |\n| c | d |\ntail\n"
    // Break the delimiter row, which closes the table and reclassifies every row below it.
    Self.expectConvergence(document, replacing: 2..<3, with: "x")
    // Put it back the other way: turn a paragraph into a delimiter row.
    Self.expectConvergence("h\nx:-|-:|\n| a | b |\ntail\n", replacing: 2..<3, with: "|")
  }

  // MARK: - Strikethrough

  @Test("`~~struck~~` carries `.strikethrough` over content and markers alike")
  func strikethroughFlattensLikeEmphasis() {
    //   `~` `~`  s  t  r  u  c  k  `~` `~`
    //    0   1   2  3  4  5  6  7   8   9
    Self.expectLayout(
      "~~struck~~",
      [
        Expected(0..<2, .text, [.strikethrough], .marker),
        Expected(2..<8, .text, [.strikethrough]),
        Expected(8..<10, .text, [.strikethrough], .marker),
      ])
  }

  @Test("A single `~x~` is strikethrough; mismatched run lengths are literal")
  func tildeRunLengthsMustMatch() {
    #expect(
      Self.fullScan("~x~").spans.allSatisfy { $0.style == [.strikethrough] },
      "GFM's cmark accepts a single tilde pair")
    // Mismatched lengths do not pair, so nothing on the line carries the flag.
    for text in ["~~x~", "~x~~", "~~~x~~~"] {
      #expect(
        !Self.fullScan(text).spans.contains { $0.style.contains(.strikethrough) },
        "\(text.debugDescription) is literal tildes")
    }
  }

  @Test("Strikethrough unions with emphasis rather than nesting under it")
  func strikethroughUnionsWithStrong() {
    // `**~~x~~**`:
    //
    //   `*` `*` `~` `~`  x  `~` `~` `*` `*`
    //    0   1   2   3   4   5   6   7   8
    //
    // The strong run covers 0..<9 and the struck run 2..<7, and the overlap is a UNION —
    // which is the whole model, and comes out of `|=` rather than out of a tree.
    Self.expectLayout(
      "**~~x~~**",
      [
        Expected(0..<2, .text, [.strong], .marker),
        Expected(2..<4, .text, [.strong, .strikethrough], .marker),
        Expected(4..<5, .text, [.strong, .strikethrough]),
        Expected(5..<7, .text, [.strong, .strikethrough], .marker),
        Expected(7..<9, .text, [.strong], .marker),
      ])
  }

  @Test("A tilde inside a code span is not a delimiter, and a `~~~` fence is not inline")
  func tildesInsideOtherConstructsAreNotStrikethrough() {
    #expect(
      !Self.fullScan("`~~x~~`").spans.contains { $0.style.contains(.strikethrough) },
      "a code span's contents are code")
    #expect(
      Self.elements("~~~\ncode\n~~~\n") == [.codeFence, .codeBlock, .codeFence, .blank],
      "a tilde fence is still a fence")
  }

  // MARK: - Autolinks

  @Test("`<https://example.com>` is a link destination with its brackets as markers")
  func bracketedURIAutolink() {
    //   `<`  h  t  t  p  s  `:` `/` `/` e ... m  `>`
    //    0   1  2  3  4  5   6   7   8  9 ... 19  20
    Self.expectLayout(
      "<https://example.com>",
      [
        Expected(0..<1, .linkURL, [], .marker),
        Expected(1..<20, .linkURL),
        Expected(20..<21, .linkURL, [], .marker),
      ])
  }

  @Test("`<user@example.com>` is an email autolink")
  func bracketedEmailAutolink() {
    //   `<` u  s  e  r  `@` e ... m `>`
    //    0  1  2  3  4   5  6 ... 16 17
    Self.expectLayout(
      "<user@example.com>",
      [
        Expected(0..<1, .linkURL, [], .marker),
        Expected(1..<17, .linkURL),
        Expected(17..<18, .linkURL, [], .marker),
      ])
  }

  @Test("A `<` that opens nothing is ordinary text")
  func nonAutolinksAreText() {
    // Each of these fails a different clause. Without them, `a < b` would paint half a
    // paragraph as a URL.
    for text in [
      "<not a link>",  // whitespace inside
      "<a:b>",  // a one-character scheme; CommonMark's minimum is two
      "<a>",  // no scheme, no `@`
      "<@example.com>",  // empty local part
      "<user@>",  // empty domain
      "<user@localhost>",  // no dot in the domain
      "a < b > c",  // no closing bracket before the space
      "<>",  // empty
    ] {
      #expect(
        !Self.fullScan(text).spans.contains { $0.kind == .linkURL },
        "\(text.debugDescription) is not an autolink")
    }
  }

  @Test("Autolinks and emphasis coexist on one line")
  func autolinksInsideEmphasis() {
    // `*<ab:c>*` — a two-character scheme, because CommonMark's minimum is two and `<a:b>`
    // is therefore not an autolink at all:
    //
    //   `*` `<`  a  b  `:`  c  `>` `*`
    //    0   1   2  3   4   5   6   7
    //
    // The emphasis paints its flag over the whole run — markers included — and the autolink
    // overrides only `kind`, which is exactly the trade `SpanKind.link` documents.
    Self.expectLayout(
      "*<ab:c>*",
      [
        Expected(0..<1, .text, [.emphasis], .marker),
        Expected(1..<2, .linkURL, [.emphasis], .marker),
        Expected(2..<6, .linkURL, [.emphasis]),
        Expected(6..<7, .linkURL, [.emphasis], .marker),
        Expected(7..<8, .text, [.emphasis], .marker),
      ])
  }

  // MARK: - Vocabulary

  @Test(
    "The raw values this sortie added are stable",
    arguments: [
      (SpanKind.frontmatterDelimiter, "frontmatterDelimiter"),
      (SpanKind.frontmatterKey, "frontmatterKey"),
      (SpanKind.frontmatterValue, "frontmatterValue"),
      (SpanKind.tableCell, "tableCell"),
      (SpanKind.tableDelimiter, "tableDelimiter"),
      (SpanKind.taskListChecked, "taskListChecked"),
      (SpanKind.taskListUnchecked, "taskListUnchecked"),
    ]
  )
  func spanKindRawValues(kind: SpanKind, expected: String) {
    #expect(kind.rawValue == expected)
  }

  @Test(
    "The element raw values this sortie added are stable",
    arguments: [
      (ElementKind.frontmatterDelimiter, "frontmatterDelimiter"),
      (ElementKind.frontmatter, "frontmatter"),
      (ElementKind.tableDelimiterRow, "tableDelimiterRow"),
      (ElementKind.tableRow, "tableRow"),
    ]
  )
  func elementKindRawValues(element: ElementKind, expected: String) {
    #expect(element.rawValue == expected)
  }

  @Test("`TableAlignment` raw values are stable, and `unspecified` is not `left`")
  func alignmentRawValues() {
    #expect(TableAlignment.unspecified.rawValue == 0)
    #expect(TableAlignment.left.rawValue == 1)
    #expect(TableAlignment.right.rawValue == 2)
    #expect(TableAlignment.center.rawValue == 3)
    // `---` and `:---` render the same and mean different things to a writer round-tripping
    // the document, which is why they are two values and not one.
    #expect(TableAlignment.unspecified != TableAlignment.left)
    #expect(TableAlignment(rawValue: 200) != TableAlignment.center, "unknown values are legal")
  }
}
