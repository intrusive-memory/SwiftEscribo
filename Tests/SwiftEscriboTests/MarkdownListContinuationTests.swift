import EscriboCore
import Foundation
import Testing

@testable import SwiftEscribo

/// One row of the continuation table: a line, how the scanner classified it, and what
/// pressing Return at its end must do.
///
/// A named type rather than a tuple so a failing row identifies itself by name in the test
/// output, the pattern `SelectionClampCase` established in Sortie 12.
struct ContinuationCase: Sendable, CustomStringConvertible {

  /// What this row is here to pin down.
  let name: String

  /// The caret's line, without its terminator.
  let line: String

  /// The scanner's classification of that line — the gate, and the only thing that decides
  /// whether the line is a list at all.
  let element: ElementKind

  /// What Return must do, with the line at offset zero and the caret at its end.
  let expected: ListContinuation

  var description: String { "\(name) — \(debugLine)" }

  private var debugLine: String {
    "\"" + line.replacingOccurrences(of: "\t", with: "\\t") + "\" as \(element.rawValue)"
  }
}

/// REQUIREMENTS.md § Editing behavior, "Continuation, not conversion", asserted where it
/// can actually fail.
///
/// ## Why this suite is the one with teeth
///
/// `NSTextView` and `UITextView` do an enormous amount on their own — undo grouping, typing
/// coalescing, selection fixup, newline insertion. An integration test that presses Return
/// and reads the document back can therefore pass for reasons that have nothing to do with
/// this package, which is exactly what happened to Sortie 12's selection-clamping tests:
/// they stayed green with the implementation deleted, because AppKit was doing the work.
///
/// Nothing below touches a text view. Every assertion is a pure function's output against a
/// literal, so no framework can stand in for the rule, and deleting any branch of
/// ``MarkdownListContinuation`` turns rows here red. The integration suite in
/// `EditorInputPathTests` is the *second* leg — it proves the rule is wired to the Return
/// key and registers as one undo action — and it is not a substitute for this one.
@Suite("Markdown list continuation — the rule, as a function")
struct MarkdownListContinuationTests {

  /// The five rows of REQUIREMENTS.md § Editing behavior's continuation table, plus the
  /// inputs that would otherwise turn a marker parser into a guessing machine.
  static let cases: [ContinuationCase] = [
    // Row 1 — Return at end of `- item` inserts `\n- `.
    ContinuationCase(
      name: "an unordered item continues with the same bullet",
      line: "- item", element: .unorderedListItem,
      expected: .rewrite(range: 6..<6, replacement: "\n- ")),
    ContinuationCase(
      name: "an asterisk bullet is carried through, not normalised to a hyphen",
      line: "* item", element: .unorderedListItem,
      expected: .rewrite(range: 6..<6, replacement: "\n* ")),
    ContinuationCase(
      name: "a plus bullet is carried through too",
      line: "+ item", element: .unorderedListItem,
      expected: .rewrite(range: 6..<6, replacement: "\n+ ")),

    // Row 2 — Return at end of `3. item` inserts `\n4. `.
    ContinuationCase(
      name: "an ordered item's number is incremented",
      line: "3. item", element: .orderedListItem,
      expected: .rewrite(range: 7..<7, replacement: "\n4. ")),
    ContinuationCase(
      name: "the increment carries across a digit boundary",
      line: "9. item", element: .orderedListItem,
      expected: .rewrite(range: 7..<7, replacement: "\n10. ")),
    ContinuationCase(
      name: "a parenthesis delimiter is preserved",
      line: "1) item", element: .orderedListItem,
      expected: .rewrite(range: 7..<7, replacement: "\n2) ")),

    // Row 3 — Return at end of `- [ ] item` inserts `\n- [ ] `, always unchecked.
    ContinuationCase(
      name: "a task item continues unchecked",
      line: "- [ ] item", element: .unorderedListItem,
      expected: .rewrite(range: 10..<10, replacement: "\n- [ ] ")),
    ContinuationCase(
      name: "a CHECKED task item still continues UNCHECKED",
      line: "- [x] item", element: .unorderedListItem,
      expected: .rewrite(range: 10..<10, replacement: "\n- [ ] ")),
    ContinuationCase(
      name: "an uppercase tick is a tick and is still not carried forward",
      line: "- [X] item", element: .unorderedListItem,
      expected: .rewrite(range: 10..<10, replacement: "\n- [ ] ")),
    ContinuationCase(
      name: "an ordered task item continues unchecked with the next number",
      line: "2. [x] item", element: .orderedListItem,
      expected: .rewrite(range: 11..<11, replacement: "\n3. [ ] ")),

    // Row 4 — Return on an item empty apart from its marker deletes the marker.
    ContinuationCase(
      name: "a marker-only item loses its marker and inserts nothing",
      line: "- ", element: .unorderedListItem,
      expected: .rewrite(range: 0..<2, replacement: "")),
    ContinuationCase(
      name: "a bare bullet with no trailing space is still marker-only",
      line: "-", element: .unorderedListItem,
      expected: .rewrite(range: 0..<1, replacement: "")),
    ContinuationCase(
      name: "a marker-only ordered item loses its marker too",
      line: "1. ", element: .orderedListItem,
      expected: .rewrite(range: 0..<3, replacement: "")),
    ContinuationCase(
      name: "a marker-only task item loses the whole marker, checkbox included",
      line: "- [ ] ", element: .unorderedListItem,
      expected: .rewrite(range: 0..<6, replacement: "")),
    ContinuationCase(
      name: "a marker-only item with trailing whitespace still clears the whole line",
      line: "-   ", element: .unorderedListItem,
      expected: .rewrite(range: 0..<4, replacement: "")),
    ContinuationCase(
      name: "an indented marker-only item leaves a line with no indent left on it",
      line: "  - ", element: .unorderedListItem,
      expected: .rewrite(range: 0..<4, replacement: "")),

    // Row 5 — Return at end of an indented nested item continues at the same indent.
    ContinuationCase(
      name: "two spaces of indent are reproduced exactly",
      line: "  - nested", element: .unorderedListItem,
      expected: .rewrite(range: 10..<10, replacement: "\n  - ")),
    ContinuationCase(
      name: "a tab indent is reproduced as a tab, not expanded to spaces",
      line: "\t- tabbed", element: .unorderedListItem,
      expected: .rewrite(range: 9..<9, replacement: "\n\t- ")),
    ContinuationCase(
      name: "four spaces and an ordered marker keep both the indent and the increment",
      line: "    2. deep", element: .orderedListItem,
      expected: .rewrite(range: 11..<11, replacement: "\n    3. ")),
    ContinuationCase(
      name: "a wide gap after the bullet is reproduced verbatim",
      line: "-   spaced", element: .unorderedListItem,
      expected: .rewrite(range: 10..<10, replacement: "\n-   ")),

    // The gate. None of these lines is a list, and the scanner is what says so — DL-108.
    ContinuationCase(
      name: "a YAML sequence entry inside frontmatter is YAML, not a Markdown list",
      line: "- alpha", element: .frontmatter,
      expected: .literalNewline),
    ContinuationCase(
      name: "a bullet inside a fenced code block is code",
      line: "- not a list", element: .codeBlock,
      expected: .literalNewline),
    ContinuationCase(
      name: "a bullet in a paragraph the scanner declined to open a list for is prose",
      line: "- looks like one", element: .paragraph,
      expected: .literalNewline),
    ContinuationCase(
      name: "a Fountain action line that begins with a hyphen is not a list",
      line: "- he says", element: .action,
      expected: .literalNewline),
    ContinuationCase(
      name: "a blank line has no marker to continue",
      line: "", element: .blank,
      expected: .literalNewline),

    // Inputs a marker parser has to decline rather than guess at.
    ContinuationCase(
      name: "no space after the bullet is not a list marker",
      line: "-item", element: .unorderedListItem,
      expected: .literalNewline),
    ContinuationCase(
      name: "a decimal number is not an ordered marker",
      line: "1.5 kilometres", element: .orderedListItem,
      expected: .literalNewline),
    ContinuationCase(
      name: "a number with no delimiter is not an ordered marker",
      line: "12 items", element: .orderedListItem,
      expected: .literalNewline),
    ContinuationCase(
      name: "a number too large to increment degrades to a literal newline, never a trap",
      line: "99999999999999999999. x", element: .orderedListItem,
      expected: .literalNewline),
    ContinuationCase(
      name: "a bracket run that is not a checkbox is content, so the marker is just the bullet",
      line: "- [x]y", element: .unorderedListItem,
      expected: .rewrite(range: 6..<6, replacement: "\n- ")),
    ContinuationCase(
      name: "a checkbox with a letter that is not x is content",
      line: "- [z] thing", element: .unorderedListItem,
      expected: .rewrite(range: 11..<11, replacement: "\n- ")),
  ]

  @Test("Return at the end of the line does exactly what the table says", arguments: cases)
  func continuationMatchesTheTable(testCase: ContinuationCase) {
    let outcome = MarkdownListContinuation.outcome(
      line: testCase.line,
      lineStart: 0,
      caret: testCase.line.utf16.count,
      element: testCase.element)
    #expect(outcome == testCase.expected)
  }

  /// The same table, with the line placed somewhere other than offset zero.
  ///
  /// Every range the rule emits is a **document** offset, and a rule that quietly returned
  /// line-relative offsets would pass every row above and corrupt every document below the
  /// first line. Cheap to check, and impossible to notice from the table alone.
  @Test("Every emitted range is in document coordinates, not line coordinates", arguments: cases)
  func rangesAreDocumentOffsets(testCase: ContinuationCase) {
    let lineStart = 137
    let caret = lineStart + testCase.line.utf16.count
    let outcome = MarkdownListContinuation.outcome(
      line: testCase.line, lineStart: lineStart, caret: caret, element: testCase.element)

    switch (outcome, testCase.expected) {
    case (.literalNewline, .literalNewline):
      break
    case (.rewrite(let range, let replacement), .rewrite(let base, let baseReplacement)):
      #expect(range == (base.lowerBound + lineStart)..<(base.upperBound + lineStart))
      #expect(replacement == baseReplacement)
    default:
      Issue.record("outcome changed shape when the line moved: \(outcome)")
    }
  }

  /// REQUIREMENTS.md states every trigger as "Return **at end of** …", and § Fountain Tab
  /// and Return gives the governing rule for everything else: "When context is ambiguous, an
  /// affordance does the boring thing."
  @Test(
    "A Return anywhere but the end of the line is ambiguous, so it inserts a plain newline",
    arguments: [0, 1, 2, 3, 4, 5])
  func midLineReturnIsALiteralNewline(caret: Int) {
    let line = "- item"
    let outcome = MarkdownListContinuation.outcome(
      line: line, lineStart: 0, caret: caret, element: .unorderedListItem)
    #expect(outcome == .literalNewline)
  }

  @Test("A caret past the end of the line is nonsense and is declined, not clamped")
  func caretPastTheEndIsDeclined() {
    #expect(
      MarkdownListContinuation.outcome(
        line: "- item", lineStart: 0, caret: 99, element: .unorderedListItem)
        == .literalNewline)
  }

  // MARK: - DL-118, the tight-list fallback

  /// The gap and the fallback, asserted as a table so each shape names itself.
  ///
  /// `MarkdownGrammar` misclassifies the second and later items of a **tight** list — no
  /// blank line between items, which is how most lists are written. `1. one`⏎`2. two` makes
  /// line 2 a ``ElementKind/paragraph``; `- item`⏎`- ` makes line 2 a setext
  /// ``ElementKind/heading``. Both are the shapes REQUIREMENTS.md's continuation table is
  /// *about*, so gating strictly on the list kinds would have shipped an affordance that
  /// works for the first item of a list and no other.
  ///
  /// The fallback admits those two kinds only when the line above also carries a marker.
  /// Every row below is a case where that one extra fact is the difference between continuing
  /// a list and corrupting prose or a heading.
  @Test(
    "The tight-list fallback fires on lists and declines on prose and setext headings",
    arguments: [
      ("2. two", "1. one", ElementKind.paragraph, true),
      ("3. item", "2. two", ElementKind.paragraph, true),
      ("- ", "- item", ElementKind.heading, true),
      ("-", "- item", ElementKind.heading, true),
      ("  - ", "  - inner", ElementKind.heading, true),
      // Prose that happens to begin with a year, under prose. Not a list.
      ("1985. Something happened.", "The years", ElementKind.paragraph, false),
      // A real setext underline under a real paragraph. Deleting it would demote a heading.
      ("-", "prose", ElementKind.heading, false),
      ("---", "prose", ElementKind.heading, false),
      // The top of the document has no line above it to appeal to.
      ("2. two", nil, ElementKind.paragraph, false),
      ("- ", nil, ElementKind.heading, false),
      // The fallback never reaches a kind outside the allow-set, whatever is above it.
      ("- entry", "- entry", ElementKind.frontmatter, false),
      ("- entry", "- entry", ElementKind.codeBlock, false),
      ("- entry", "- entry", ElementKind.blockquote, false),
      ("- entry", "- entry", ElementKind.tableRow, false),
      ("- entry", "- entry", ElementKind.thematicBreak, false),
      ("- entry", "- entry", ElementKind.action, false),
      // A list kind needs no fallback and no line above it.
      ("- item", nil, ElementKind.unorderedListItem, true),
      ("1. item", nil, ElementKind.orderedListItem, true),
    ])
  func tightListFallback(
    line: String, previousLine: String?, element: ElementKind, isList: Bool
  ) {
    #expect(
      MarkdownListContinuation.isListContext(element: element, previousLine: previousLine)
        == isList)

    // And the gate really is what decides the outcome, not merely what the predicate says.
    let outcome = MarkdownListContinuation.outcome(
      line: line, previousLine: previousLine, lineStart: 0, caret: line.utf16.count,
      element: element)
    #expect(
      (outcome != .literalNewline) == (isList && MarkdownListContinuation.marker(in: line) != nil))
  }

  @Test("A `3. item` under a `2. two` continues with `4. `, which is the whole point")
  func tightOrderedListContinues() {
    #expect(
      MarkdownListContinuation.outcome(
        line: "3. item", previousLine: "2. two", lineStart: 0, caret: 7, element: .paragraph)
        == .rewrite(range: 7..<7, replacement: "\n4. "))
  }

  @Test("A `- ` under a `- item` loses its marker, which is the other whole point")
  func tightMarkerOnlyItemIsCleared() {
    #expect(
      MarkdownListContinuation.outcome(
        line: "- ", previousLine: "- item", lineStart: 0, caret: 2, element: .heading)
        == .rewrite(range: 0..<2, replacement: ""))
  }

  // MARK: - The marker grammar itself

  @Test(
    "The marker's measured length is where the item's text begins",
    arguments: [
      ("- item", 2),
      ("*  item", 3),
      ("  - nested", 4),
      ("\t- tabbed", 3),
      ("10. item", 4),
      ("1)  item", 4),
      ("- [ ] task", 6),
      ("- [X]\ttask", 6),
      ("-   spaced", 4),
    ])
  func markerPrefixLength(line: String, expected: Int) throws {
    let marker = try #require(MarkdownListContinuation.marker(in: line))
    #expect(marker.prefixLength == expected)
    #expect(marker.isEmptyItem == false)
  }

  @Test(
    "Lines with no list marker at all produce no marker",
    arguments: [
      "", "   ", "plain text", "-item", "1.5", "12 items", "#heading", "> quote", "[x] no bullet",
    ])
  func linesWithoutMarkers(line: String) {
    #expect(MarkdownListContinuation.marker(in: line) == nil)
  }

  /// The rule is stated as an insertion of `"\n" + marker`, so the marker it inserts and the
  /// marker the *next* Return would parse off that line have to be the same string. If they
  /// are not, the second item in a list continues differently from the first — a bug that
  /// example tests miss because they only ever press Return once.
  @Test(
    "Continuing a continuation is stable: the inserted marker parses back to itself",
    arguments: [
      "- item", "* item", "+ item", "3. item", "9. item", "1) item", "- [ ] item",
      "- [x] item", "  - nested", "\t- tabbed", "    2. deep", "-   spaced",
    ])
  func insertedMarkerIsItselfAContinuableItem(line: String) throws {
    let firstMarkerCharacter = line.drop(while: { $0 == " " || $0 == "\t" }).first
    let element: ElementKind =
      firstMarkerCharacter?.isNumber == true ? .orderedListItem : .unorderedListItem

    guard
      case .rewrite(_, let replacement) = MarkdownListContinuation.outcome(
        line: line, lineStart: 0, caret: line.utf16.count, element: element)
    else {
      Issue.record("expected a rewrite for \(line)")
      return
    }

    // The inserted line, with the marker and nothing else, is by definition marker-only.
    let inserted = String(replacement.dropFirst())
    let marker = try #require(MarkdownListContinuation.marker(in: inserted))
    #expect(marker.isEmptyItem == true)
    #expect(marker.prefixLength == inserted.utf16.count)
  }
}
