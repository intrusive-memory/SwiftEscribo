import Foundation
import Markdown
import Testing

// Deliberately **not** `@testable`. The oracle validates the shipped public surface —
// `EscriboScanner`, `ScanResult`, `LineRecord`, `ElementKind` — because that is what a
// consumer sees. A differential test that reached into internals could agree with an
// implementation detail no caller can observe.
import EscriboCore

/// A differential oracle for ``MarkdownGrammar``'s **block** structure, run against
/// `swift-markdown` (cmark-gfm) as an independent CommonMark implementation.
///
/// ## Why an oracle at all
///
/// `ScanGateTests`'s `incrementalScan == fullScan` property cannot see a grammar bug —
/// both sides run the same grammar. `MarkdownBlockStructureTests`'s hand-written
/// expectations can, but only where a human thought to write one down. This file closes
/// the third gap: an implementation nobody here wrote, disagreeing on documents nobody
/// wrote expectations for.
///
/// ## `swift-markdown` is test-only, and that is a graph property, not a declaration
///
/// `Package.swift` names `swift-markdown` on `EscriboCoreTests` and nowhere else. SwiftPM
/// prunes it from every downstream consumer *because* no shipping target references it —
/// there is no `testOnly:` to write and no diagnostic when the property stops holding
/// (swiftlang/swift-package-manager#7007). The `no_markdown_import_in_sources` SwiftLint
/// rule is what keeps `import Markdown` out of `Sources/`. See EXECUTION_PLAN.md § D-2.
///
/// ## What is compared, and what is not
///
/// **Compared:** every line's block class, over the reduced vocabulary in ``Block`` —
/// blank, paragraph, heading *with level*, code, thematic break, blockquote *with depth*,
/// ordered/unordered list item *with depth*, table, HTML block. That is `ElementKind` plus
/// `LineRecord.depth`, which is the entire block-structure output of a scan.
///
/// **Not compared:** inline structure. `EscriboSpan` tiles a line with emphasis, links,
/// and code spans; `swift-markdown` builds an inline tree. Projecting one onto the other
/// is a second oracle, not a narrower version of this one, and doing it badly would let
/// this one's failures hide inside it. One inline fact *is* asserted, in
/// ``extendedAutolinksAreOutsideThisOracleEntirely()``, because the mission expected this
/// oracle to surface DL-107 and it structurally cannot — see that test.
///
/// ## Disagreements are the product
///
/// `EscriboCore` is a syntax-highlighting scanner, not a CommonMark AST builder, and the
/// two disagree by design in several places. Every disagreement is enumerated in the
/// fixture's ``Fixture/divergences`` table with its exact `(scanner, oracle)` pair and a
/// classification. The test fails in **both** directions:
///
/// - an undocumented divergence fails — the scanner changed, or regressed;
/// - a documented divergence that no longer occurs fails — the scanner was fixed and the
///   table is now a lie.
///
/// So the table cannot be used to make the comparison weaker: widening it to cover
/// everything makes every entry stale the moment the scanner agrees, and the second
/// direction catches that. There is no way to write a table that passes for a scanner
/// that does not exist.
@Suite("Markdown differential oracle — swift-markdown")
struct MarkdownDifferentialOracleTests {

  // MARK: - The reduced block vocabulary

  /// The one vocabulary both implementations are projected into.
  ///
  /// Reduced, not lossy in the interesting direction: every distinction `EscriboCore`
  /// draws at the block level survives the projection, including heading level, list
  /// nesting depth, and blockquote nesting depth. What it drops is the split between a
  /// fence line and the code inside it, and between a table's delimiter row and its body
  /// rows — distinctions `swift-markdown` has no node for at all, so keeping them would
  /// manufacture divergences that say nothing about the scanner.
  enum Block: Equatable, Sendable, CustomStringConvertible {
    case blank
    case paragraph
    case heading(level: Int)
    case code
    case thematicBreak
    case blockquote(depth: Int)
    case unorderedListItem(depth: Int)
    case orderedListItem(depth: Int)
    case table
    case html
    /// Scanner-only: `EscriboCore` models YAML frontmatter and CommonMark does not.
    case frontmatter
    /// Neither side produced anything this projection models. Always a divergence.
    case unmapped

    var description: String {
      switch self {
      case .blank: ".blank"
      case .paragraph: ".paragraph"
      case .heading(let level): ".heading(level: \(level))"
      case .code: ".code"
      case .thematicBreak: ".thematicBreak"
      case .blockquote(let depth): ".blockquote(depth: \(depth))"
      case .unorderedListItem(let depth): ".unorderedListItem(depth: \(depth))"
      case .orderedListItem(let depth): ".orderedListItem(depth: \(depth))"
      case .table: ".table"
      case .html: ".html"
      case .frontmatter: ".frontmatter"
      case .unmapped: ".unmapped"
      }
    }
  }

  /// Why a documented divergence exists — and therefore what to do about it.
  enum Verdict: String, Sendable {
    /// `EscriboCore` is right for what it is. Asserted here so it is documented rather
    /// than rediscovered as a bug every time someone runs a CommonMark renderer.
    case deliberate
    /// `EscriboCore` is wrong. Recorded, not fixed — this sortie validates and does not
    /// repair. Removing the entry is how the fix proves itself.
    case scannerDefect
  }

  /// One line on which the two implementations disagree, with both readings pinned.
  struct Divergence: Equatable, Sendable, CustomStringConvertible {
    let line: Int
    let scanner: Block
    let oracle: Block
    var verdict: Verdict = .deliberate
    var reason: String = ""

    static func == (a: Divergence, b: Divergence) -> Bool {
      a.line == b.line && a.scanner == b.scanner && a.oracle == b.oracle
    }

    var description: String {
      "line \(line): scanner \(scanner) vs oracle \(oracle)"
    }

    /// A copy-pasteable table entry, emitted in failure messages so a legitimate scanner
    /// change is cheap to re-baseline — and an illegitimate one still has to be typed out
    /// by a human who has to write a `reason`.
    var literal: String {
      "Divergence(line: \(line), scanner: \(scanner), oracle: \(oracle), verdict: ..., reason: ...)"
    }
  }

  /// A fixture and the complete set of divergences it is allowed to exhibit.
  struct Fixture: Sendable, CustomStringConvertible, CustomTestStringConvertible {
    let name: String
    let divergences: [Divergence]

    var description: String { name }
    var testDescription: String { name }
  }

  // MARK: - Fixture loading

  static let subdirectory = "Fixtures/Markdown"

  static func load(_ name: String) -> String? {
    guard
      let url = Bundle.module.url(
        forResource: name, withExtension: "markdown", subdirectory: subdirectory),
      let data = try? Data(contentsOf: url)
    else { return nil }
    return String(decoding: data, as: UTF8.self)
  }

  /// The fixtures are `.markdown`, not `.md`, for a reason worth stating: a repo-wide
  /// policy hook requires every `.md` file to open with a YAML `type:` frontmatter block.
  /// Applying it here would put the same five lines at the top of every fixture and make
  /// line 0 of the corpus uniform — and line 0 is exactly where frontmatter, setext
  /// underlines, and thematic breaks are decided. The fixtures would then agree with each
  /// other instead of testing anything.

  // MARK: - Projecting `EscriboCore`

  /// `ElementKind` + `LineRecord.depth`, projected into ``Block``.
  static func scannerBlocks(_ text: String) -> [Block] {
    var scanner = EscriboScanner(language: .markdown)
    return scanner.fullScan(text).lineRecords.map { record in
      switch record.element {
      case .blank: return .blank
      case .paragraph: return .paragraph
      case .heading: return .heading(level: record.depth)
      case .codeFence, .codeBlock: return .code
      case .thematicBreak: return .thematicBreak
      case .blockquote: return .blockquote(depth: record.depth)
      case .unorderedListItem: return .unorderedListItem(depth: record.depth)
      case .orderedListItem: return .orderedListItem(depth: record.depth)
      case .tableDelimiterRow, .tableRow: return .table
      case .frontmatterDelimiter, .frontmatter: return .frontmatter
      default: return .unmapped
      }
    }
  }

  // MARK: - Projecting `swift-markdown`

  /// `swift-markdown`'s parse, projected into ``Block`` one line at a time.
  ///
  /// Two mapping rules are choices rather than mechanics, and both mirror a rule
  /// `EscriboCore` documents on `ElementKind`:
  ///
  /// 1. **A blockquote swallows its contents.** Any line with a `BlockQuote` ancestor is
  ///    `.blockquote` at that ancestor's nesting depth, whatever node is innermost.
  ///    `EscriboCore` does not re-scan blockquote content, so `> # Title` is one
  ///    blockquote line on both sides.
  /// 2. **Only a list item's first line is a list item.** Continuation lines are whatever
  ///    their own block says, which is `EscriboCore`'s rule verbatim.
  ///
  /// Everything else is the innermost block that covers the line.
  static func oracleBlocks(_ text: String, lineCount: Int) -> [Block] {
    // `.disableSmartOpts` because cmark's smart punctuation rewrites `--` and quotes in
    // the inline text. It does not move source positions, but this oracle has no use for
    // a transformed document and the scanner deliberately disables the same feature.
    let document = Document(parsing: text, options: [.disableSmartOpts])
    var blocks = [Block?](repeating: nil, count: lineCount)
    fill(document, quoteDepth: 0, listDepth: 0, into: &blocks)

    let raw = text.components(separatedBy: "\n")
    return blocks.enumerated().map { index, block in
      if let block { return block }
      // cmark emits no node for a blank line, so an unassigned line is blank — unless it
      // has content, in which case this projection is missing a block type and the
      // `.unmapped` says so instead of quietly agreeing.
      let line = index < raw.count ? raw[index] : ""
      let bare = line.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r"))
      return bare.isEmpty ? .blank : .unmapped
    }
  }

  private static func fill(
    _ markup: Markup, quoteDepth: Int, listDepth: Int, into blocks: inout [Block?]
  ) {
    let inQuote = quoteDepth > 0

    func lineRange(_ node: Markup) -> Range<Int>? {
      guard let range = node.range else { return nil }
      let lower = range.lowerBound.line - 1
      var upper = range.upperBound.line - 1
      // An end position in column 1 of a later line is one past the block, not part of it.
      if upper > lower, range.upperBound.column <= 1 { upper -= 1 }
      guard lower >= 0, upper >= lower, lower < blocks.count else { return nil }
      return lower..<min(upper + 1, blocks.count)
    }

    func assign(_ node: Markup, _ value: Block) {
      guard let range = lineRange(node) else { return }
      for index in range { blocks[index] = value }
    }

    func assignFirstLine(_ node: Markup, _ value: Block) {
      guard let range = lineRange(node) else { return }
      blocks[range.lowerBound] = value
    }

    switch markup {
    case let quote as BlockQuote:
      assign(quote, .blockquote(depth: quoteDepth))
      for child in quote.children {
        fill(child, quoteDepth: quoteDepth + 1, listDepth: listDepth, into: &blocks)
      }

    case let list as UnorderedList:
      for item in list.children.compactMap({ $0 as? ListItem }) {
        fillItem(item, ordered: false, quoteDepth: quoteDepth, listDepth: listDepth, into: &blocks)
      }

    case let list as OrderedList:
      for item in list.children.compactMap({ $0 as? ListItem }) {
        fillItem(item, ordered: true, quoteDepth: quoteDepth, listDepth: listDepth, into: &blocks)
      }

    case let heading as Heading:
      if !inQuote { assign(heading, .heading(level: heading.level)) }

    case is Paragraph:
      if !inQuote { assign(markup, .paragraph) }

    case is CodeBlock:
      if !inQuote { assign(markup, .code) }

    case is HTMLBlock:
      if !inQuote { assign(markup, .html) }

    case is ThematicBreak:
      if !inQuote { assign(markup, .thematicBreak) }

    case is Table:
      // The delimiter row has no node — it is the thing that makes the table a table —
      // so the whole extent is claimed here rather than walked cell by cell.
      if !inQuote { assign(markup, .table) }

    case is Document:
      for child in markup.children {
        fill(child, quoteDepth: quoteDepth, listDepth: listDepth, into: &blocks)
      }

    default:
      // A block type this projection does not model leaves its lines unassigned, which
      // surfaces as `.unmapped` rather than as silent agreement. Inline nodes are never
      // reached: no block case above descends into one.
      break
    }
  }

  private static func fillItem(
    _ item: ListItem, ordered: Bool, quoteDepth: Int, listDepth: Int, into blocks: inout [Block?]
  ) {
    // Children first, then the marker line — the item's first `Paragraph` covers the
    // marker line too, and the marker is what that line is.
    for child in item.children {
      fill(child, quoteDepth: quoteDepth, listDepth: listDepth + 1, into: &blocks)
    }
    guard quoteDepth == 0 else { return }
    guard let range = item.range else { return }
    let first = range.lowerBound.line - 1
    guard first >= 0, first < blocks.count else { return }
    blocks[first] = ordered
      ? .orderedListItem(depth: listDepth) : .unorderedListItem(depth: listDepth)
  }

  // MARK: - Comparison

  /// Every line on which the two projections disagree.
  static func compare(_ text: String) -> (
    scanner: [Block], oracle: [Block], divergences: [Divergence]
  ) {
    let scanner = scannerBlocks(text)
    let oracle = oracleBlocks(text, lineCount: scanner.count)
    var found: [Divergence] = []
    for index in scanner.indices where scanner[index] != oracle[index] {
      found.append(Divergence(line: index, scanner: scanner[index], oracle: oracle[index]))
    }
    return (scanner, oracle, found)
  }

  // MARK: - The fixture corpus and its divergence tables

  /// Nine documents, and every line of every one of them that the two implementations
  /// read differently. Line numbers are zero-based, matching `LineRecord.index`.
  static let fixtures: [Fixture] = [

    // ATX headings at every level, wrapped paragraphs, blank separators. The plainest
    // corpus there is, and it agrees on all 17 lines.
    Fixture(name: "atx_headings", divergences: []),

    // Fenced code (backtick and tilde), an info string, and an indented code block.
    // Agrees on all 20 lines, including which lines are inside a fence.
    Fixture(name: "code", divergences: []),

    // Quotes at two nesting depths, and every thematic-break spelling. Agrees on all 18
    // lines, depths included.
    Fixture(name: "quotes_and_rules", divergences: []),

    // Continuation lines, a fence inside an item, a list inside a quote, and a quote
    // inside an ordered item. Agrees on all 19 lines.
    Fixture(name: "nested_containers", divergences: []),

    Fixture(
      name: "lists",
      divergences: [
        // ── DL-122, the whole of it, reproduced by an independent parser ────────────
        // A *tight ordered* list: `1. one` ⏎ `2. two`. `paragraphOpen` leaks out of the
        // paragraph inside item one, so the CommonMark rule "a list may not interrupt a
        // paragraph" fires against it and items two and three fall through to
        // `.paragraph`. This is the ordinary way an ordered list is written.
        Divergence(
          line: 5, scanner: .paragraph, oracle: .orderedListItem(depth: 0),
          verdict: .scannerDefect,
          reason: "DL-122: paragraphOpen leaks across a list item, so a tight ordered list's second item is not a list item"),
        Divergence(
          line: 6, scanner: .paragraph, oracle: .orderedListItem(depth: 0),
          verdict: .scannerDefect,
          reason: "DL-122: same, third item"),

        // ── DL-167, new here ───────────────────────────────────────────────────────
        // The *unordered* half of DL-122 is narrower than the decision log records. A
        // tight unordered list of ordinary items (lines 0–2) agrees exactly, and so does
        // `- outer` ⏎ `- back out`; the defect needs an item with **no content**. `-`
        // alone on line 18 is an empty second item to CommonMark; `EscriboCore` reads it
        // as a setext underline for the paragraph it believes line 17 opened, which is
        // the same `paragraphOpen` leak arriving at a different scan.
        Divergence(
          line: 18, scanner: .heading(level: 2), oracle: .unorderedListItem(depth: 0),
          verdict: .scannerDefect,
          reason: "DL-167 (narrows DL-122): the unordered half needs an EMPTY item — `- a` ⏎ `- ` — not any tight list. Ordinary tight bullet lists classify correctly."),
      ]),

    Fixture(
      name: "gfm",
      divergences: [
        // Deliberate, and documented on `ElementKind.tableRow`: GFM recognizes a header
        // row only by the delimiter row *beneath* it, which is a line of lookahead this
        // grammar does not have. The header stays `.paragraph` — the same honest gap a
        // setext heading's text line has — and a consumer that wants the header reads the
        // line above a `tableDelimiterRow` record.
        Divergence(
          line: 0, scanner: .paragraph, oracle: .table, verdict: .deliberate,
          reason: "a GFM table header is defined by the row below it; MarkdownGrammar has no lookahead"),
      ]),

    Fixture(
      name: "readme",
      divergences: [
        Divergence(
          line: 26, scanner: .paragraph, oracle: .table, verdict: .deliberate,
          reason: "table header row, as in `gfm` — the same documented lookahead gap"),
      ]),

    Fixture(
      name: "frontmatter",
      divergences: [
        // Deliberate, and the single largest structural difference between the two.
        // YAML frontmatter is not CommonMark: cmark reads line 0 as a thematic break,
        // then lines 1–2 as a paragraph that line 3's `---` underlines into a level-two
        // setext heading. `EscriboCore` models the region because an editor for this org's
        // documents has to. Note what does *not* diverge: line 9's `---` is a thematic
        // break on both sides, which is the rule that only line 0 may open a region.
        Divergence(
          line: 0, scanner: .frontmatter, oracle: .thematicBreak, verdict: .deliberate,
          reason: "frontmatter opener; CommonMark has no frontmatter and reads `---` as a rule"),
        Divergence(
          line: 1, scanner: .frontmatter, oracle: .heading(level: 2), verdict: .deliberate,
          reason: "cmark folds the frontmatter body and its closer into one setext heading"),
        Divergence(
          line: 2, scanner: .frontmatter, oracle: .heading(level: 2), verdict: .deliberate,
          reason: "as line 1"),
        Divergence(
          line: 3, scanner: .frontmatter, oracle: .heading(level: 2), verdict: .deliberate,
          reason: "frontmatter closer, read by cmark as the setext underline"),
      ]),

    Fixture(
      name: "setext_and_traps",
      divergences: [
        // Deliberate, and stated in `scanSetextUnderline`'s own documentation: the
        // underline is classified as the heading and carries the level, but the *text*
        // line above it cannot be reclassified by a grammar with no backward reach, so it
        // stays `.paragraph`. The record's content range is empty rather than claiming
        // the dashes are the heading text.
        //
        // What agrees here matters as much: lines 1 and 4 are `.heading(level: 1)` and
        // `.heading(level: 2)` on both sides, line 7's `1968. It should not…` is a
        // paragraph and not an ordered list, and line 9's `-word` is a paragraph and not
        // a bullet. Those three are the traps this fixture exists for.
        Divergence(
          line: 0, scanner: .paragraph, oracle: .heading(level: 1), verdict: .deliberate,
          reason: "setext heading text line; the underline below carries the heading, the text line cannot be reclassified without backward reach"),
        Divergence(
          line: 3, scanner: .paragraph, oracle: .heading(level: 2), verdict: .deliberate,
          reason: "as line 0, level two"),
      ]),
  ]

  // MARK: - The differential test

  @Test(
    "Block structure agrees with swift-markdown, or diverges exactly as documented",
    arguments: MarkdownDifferentialOracleTests.fixtures)
  func blockStructureMatchesCommonMark(_ fixture: Fixture) throws {
    let text = try #require(
      Self.load(fixture.name), "fixture \(fixture.name).markdown is not in Bundle.module")

    let (scanner, oracle, actual) = Self.compare(text)

    // The corpus is line-for-line, so a disagreement about how many lines there are would
    // silently misalign every comparison below it.
    let rawLineCount = text.components(separatedBy: "\n").count
    #expect(
      scanner.count == rawLineCount,
      """
      \(fixture.name): the scanner produced \(scanner.count) line records for a document \
      of \(rawLineCount) LF-terminated lines
      """)
    #expect(scanner.count == oracle.count)

    let expected = fixture.divergences

    // Direction 1 — the scanner disagreed somewhere nobody wrote down.
    for divergence in actual where !expected.contains(divergence) {
      Issue.record(
        """
        \(fixture.name): UNDOCUMENTED divergence at line \(divergence.line).
          scanner: \(divergence.scanner)
          oracle:  \(divergence.oracle)
          source:  \(Self.sourceLine(text, divergence.line).debugDescription)
        If this is correct behaviour, add it to the fixture's table with a verdict and a
        reason. If it is not, it is a regression:
          \(divergence.literal)
        """)
    }

    // Direction 2 — a documented divergence stopped happening. The scanner may have been
    // fixed, in which case the table is now false and must shrink. This is the direction
    // that makes the table unable to weaken the comparison.
    for divergence in expected where !actual.contains(divergence) {
      let observed =
        divergence.line < scanner.count ? "\(scanner[divergence.line])" : "<out of range>"
      Issue.record(
        """
        \(fixture.name): STALE expectation at line \(divergence.line).
          documented: scanner \(divergence.scanner) vs oracle \(divergence.oracle)
          observed:   scanner \(observed) vs oracle \
        \(divergence.line < oracle.count ? "\(oracle[divergence.line])" : "<out of range>")
          verdict was: \(divergence.verdict.rawValue) — \(divergence.reason)
        The two now agree, or disagree differently. Delete or amend this entry.
        """)
    }
  }

  // MARK: - Anti-vacuity

  /// The oracle must actually *find* structure, or every "agreement" above is two empty
  /// projections matching.
  ///
  /// This is the check that a degenerate oracle fails. An `oracleBlocks` that returned all
  /// `.blank`, all `.unmapped`, or all `.paragraph` — the three ways to write one that
  /// costs nothing — cannot satisfy this, and neither can one that never walks into a
  /// container.
  @Test("The oracle finds every block class the corpus contains")
  func oracleIsNotDegenerate() throws {
    var seen: [String: Int] = [:]
    for fixture in Self.fixtures {
      let text = try #require(Self.load(fixture.name))
      let blocks = Self.oracleBlocks(text, lineCount: text.components(separatedBy: "\n").count)
      for block in blocks {
        seen["\(block)", default: 0] += 1
      }
    }

    // Written out by hand from the corpus, not read back off a run.
    let required = [
      ".paragraph", ".blank", ".heading(level: 1)", ".heading(level: 2)",
      ".heading(level: 6)", ".code", ".thematicBreak", ".blockquote(depth: 0)",
      ".blockquote(depth: 1)", ".unorderedListItem(depth: 0)",
      ".unorderedListItem(depth: 1)", ".unorderedListItem(depth: 2)",
      ".orderedListItem(depth: 0)", ".table",
    ]
    for kind in required {
      #expect((seen[kind] ?? 0) > 0, "the oracle never produced \(kind) anywhere in the corpus")
    }
  }

  /// The scanner must find the same variety, for the same reason in reverse: a scanner
  /// that classified everything as `.paragraph` would agree with nothing, but a *table*
  /// wide enough to document that away would still pass the differential test. This is
  /// the floor that table cannot be widened past.
  @Test("The scanner finds every block class the corpus contains")
  func scannerIsNotDegenerate() throws {
    var seen: [String: Int] = [:]
    for fixture in Self.fixtures {
      let text = try #require(Self.load(fixture.name))
      for block in Self.scannerBlocks(text) {
        seen["\(block)", default: 0] += 1
      }
    }
    let required = [
      ".paragraph", ".blank", ".heading(level: 1)", ".heading(level: 2)",
      ".heading(level: 6)", ".code", ".thematicBreak", ".blockquote(depth: 0)",
      ".blockquote(depth: 1)", ".unorderedListItem(depth: 0)",
      ".unorderedListItem(depth: 1)", ".unorderedListItem(depth: 2)",
      ".orderedListItem(depth: 0)", ".table", ".frontmatter",
    ]
    for kind in required {
      #expect((seen[kind] ?? 0) > 0, "the scanner never produced \(kind) anywhere in the corpus")
    }
  }

  /// Most of the corpus must agree outright.
  ///
  /// Without this, the divergence tables are an unbounded escape hatch: a scanner that got
  /// steadily worse could be kept green one documented entry at a time. The floor is
  /// deliberately well below the measured rate so ordinary churn does not trip it, and far
  /// above what any broken scanner reaches.
  @Test("At least 85% of corpus lines agree with swift-markdown outright")
  func agreementRateIsHigh() throws {
    var total = 0
    var agreeing = 0
    for fixture in Self.fixtures {
      let text = try #require(Self.load(fixture.name))
      let (scanner, _, divergences) = Self.compare(text)
      total += scanner.count
      agreeing += scanner.count - divergences.count
    }
    #expect(total > 100, "the corpus is too small for this rate to mean anything")
    #expect(
      agreeing * 100 >= total * 85,
      "only \(agreeing)/\(total) lines agree with swift-markdown")
  }

  // MARK: - The oracle's own blind spot (DL-107)

  /// **DL-166**: this oracle **cannot** surface DL-107, and the reason is `swift-markdown`,
  /// not the comparison.
  ///
  /// DL-107 records that GFM *extended* autolinks — a bare `https://example.com` in prose,
  /// with no angle brackets — are unimplemented in `EscriboCore`, and the mission expected
  /// this sortie to surface them as a diff because `swift-markdown` "implements GFM".
  /// It does not implement that part. `CommonMarkConverter.parseString` attaches exactly
  /// three cmark-gfm syntax extensions — `table`, `strikethrough`, `tasklist` — and
  /// **not** `autolink`, so `swift-markdown` leaves a bare URL as plain text too
  /// (verified against swift-markdown 0.8.0, `Sources/Markdown/Parser/CommonMarkConverter.swift`).
  ///
  /// Two implementations that share a gap agree across it. Asserting that here is the only
  /// honest way to record it: if a future `swift-markdown` attaches the extension, this
  /// test goes red and DL-107 becomes surfaceable — which is exactly when someone should
  /// be told.
  ///
  /// This is also the one place this file looks at inline structure, and it is scoped to
  /// a single question: does either side produce a `Link` for a bare URL?
  @Test("DL-166: swift-markdown does not linkify bare URLs either, so DL-107 is invisible here")
  func extendedAutolinksAreOutsideThisOracleEntirely() {
    let bare = "Visit https://example.com for more.\n"
    let bracketed = "Visit <https://example.com> for more.\n"

    func oracleLinkCount(_ text: String) -> Int {
      var count = 0
      func walk(_ markup: Markup) {
        if markup is Link { count += 1 }
        for child in markup.children { walk(child) }
      }
      walk(Document(parsing: text, options: [.disableSmartOpts]))
      return count
    }

    func scannerLinkCount(_ text: String) -> Int {
      var scanner = EscriboScanner(language: .markdown)
      return scanner.fullScan(text).spans.filter {
        $0.kind == .link || $0.kind == .linkURL
      }.count
    }

    // The bracketed CommonMark form: both find it. This half is what proves the two
    // counters above are wired to anything at all.
    #expect(oracleLinkCount(bracketed) == 1, "swift-markdown must find the bracketed autolink")
    #expect(scannerLinkCount(bracketed) > 0, "EscriboCore must find the bracketed autolink")

    // The GFM extended form: neither finds it. `EscriboCore`'s miss is DL-107;
    // `swift-markdown`'s miss is why this oracle cannot report DL-107.
    #expect(
      oracleLinkCount(bare) == 0,
      """
      swift-markdown 0.8.0 does not attach cmark-gfm's `autolink` extension. If this is \
      now non-zero, the dependency gained extended autolinks and DL-107 can finally be \
      tested differentially — go do that.
      """)
    #expect(
      scannerLinkCount(bare) == 0,
      "EscriboCore gained extended autolinks (DL-107). Update this test and SUPERVISOR_STATE.")
  }

  // MARK: - Helpers

  static func sourceLine(_ text: String, _ index: Int) -> String {
    let lines = text.components(separatedBy: "\n")
    return index < lines.count ? lines[index] : "<past end>"
  }
}
