import EscriboCore
import Foundation
import Testing

@testable import SwiftEscribo

/// One row of the Tab table: a line, how the scanner classified it and the line above it, and
/// what pressing Tab at its end must do.
///
/// A named type rather than a tuple so a failing row identifies itself by name in the test
/// output — the pattern `SelectionClampCase` established in Sortie 12 and
/// `ContinuationCase` carried into Sortie 25.
struct FountainTabRule: Sendable, CustomStringConvertible {

  /// What this row is here to pin down.
  let name: String

  /// The caret's line, without its terminator.
  let line: String

  /// The scanner's classification of that line.
  let element: ElementKind

  /// The scanner's classification of the line above, or `nil` at the top of the document.
  let previousElement: ElementKind?

  /// What Tab must do, with the line at offset zero and the caret at its end.
  let expected: FountainAffordanceOutcome

  var description: String {
    let above = previousElement.map { "under \($0.rawValue)" } ?? "at the top of the document"
    return "\(name) — \(escaped) as \(element.rawValue), \(above)"
  }

  private var escaped: String {
    "\"" + line.replacingOccurrences(of: "\t", with: "\\t") + "\""
  }
}

/// REQUIREMENTS.md § Fountain Tab and Return, asserted where it can actually fail.
///
/// ## Why this suite exists alongside `FountainInputPathTests`
///
/// `NSTextView.insertTab(_:)` already inserts a tab and `insertNewline(_:)` already inserts a
/// newline. So an end-to-end test that presses a key and reads the document back agrees with
/// the last row of the table — "anywhere ambiguous, insert a literal tab" — **with this file
/// deleted**, and agrees with the entire Return column too. Sortie 12's selection-clamping
/// tests passed with their implementation removed for exactly that reason: the framework was
/// doing the work.
///
/// Nothing below touches a text view. Every assertion is a pure function's output against a
/// literal, so no framework can stand in for a rule, and deleting a branch of
/// ``FountainAffordances`` turns a named row red. `FountainInputPathTests` is the second leg —
/// it proves the rule is reached by the Tab key, that the document ends up in the state the
/// table describes, and that the whole rewrite is one undo action — and neither suite
/// substitutes for the other.
@Suite("Fountain Tab and Return — the rules, as functions")
struct FountainAffordanceTests {

  /// The five rows of REQUIREMENTS.md § Fountain Tab and Return's Tab column, plus the
  /// neighbouring contexts that would otherwise let a rule fire where the table does not say
  /// it should.
  static let cases: [FountainTabRule] = [
    // Row 1 — "Empty line, previous block is dialogue or blank | Begin a character cue."
    // Under dialogue, the blank line a cue needs does not exist yet, so one newline creates
    // it.
    FountainTabRule(
      name: "an empty line under speech gains the blank line a cue needs",
      line: "", element: .blank, previousElement: .dialogue,
      expected: .rewrite(range: 0..<0, replacement: "\n")),
    FountainTabRule(
      name: "an empty line under a parenthetical is under the same dialogue block",
      line: "", element: .blank, previousElement: .parenthetical,
      expected: .rewrite(range: 0..<0, replacement: "\n")),
    FountainTabRule(
      name: "an empty line under a cue is under a dialogue block too",
      line: "", element: .blank, previousElement: .character,
      expected: .rewrite(range: 0..<0, replacement: "\n")),

    // Row 1, second shape — under a blank line the post-condition already holds, so there is
    // nothing to insert and the keystroke is swallowed. This is what makes Tab idempotent
    // rather than a way to walk down the page one blank line per press.
    FountainTabRule(
      name: "an empty line under a blank line is already cue-ready, so nothing is inserted",
      line: "", element: .blank, previousElement: .blank,
      expected: .consume),
    FountainTabRule(
      name: "the top of an empty document is a block boundary, so it is cue-ready too",
      line: "", element: .blank, previousElement: nil,
      expected: .consume),

    // Row 2 — "On a character cue | Move to the next line as dialogue." One newline, never
    // two: a blank line would close the block the cue opened.
    FountainTabRule(
      name: "a cue moves to the next line as dialogue",
      line: "BOB", element: .character, previousElement: .blank,
      expected: .rewrite(range: 3..<3, replacement: "\n")),
    FountainTabRule(
      name: "a forced cue moves to the next line the same way",
      line: "@McAvoy", element: .character, previousElement: .blank,
      expected: .rewrite(range: 7..<7, replacement: "\n")),
    FountainTabRule(
      name: "a cue with an extension and a dual-dialogue caret is still just a cue",
      line: "BOB (V.O.) ^", element: .character, previousElement: .blank,
      expected: .rewrite(range: 12..<12, replacement: "\n")),

    // Row 3 — "On a dialogue line | Wrap the line in `()` as a parenthetical."
    FountainTabRule(
      name: "a dialogue line is wrapped in parentheses",
      line: "Hello.", element: .dialogue, previousElement: .character,
      expected: .rewrite(range: 0..<6, replacement: "(Hello.)")),
    FountainTabRule(
      name: "the indent of an indented dialogue line stays outside the parentheses",
      line: "\t Hello.", element: .dialogue, previousElement: .character,
      expected: .rewrite(range: 2..<8, replacement: "(Hello.)")),
    FountainTabRule(
      name: "trailing whitespace stays outside them too, so the line still ends in `)`",
      line: "Hello.  ", element: .dialogue, previousElement: .character,
      expected: .rewrite(range: 0..<6, replacement: "(Hello.)")),
    FountainTabRule(
      name: "the wrap is textual, so a line that merely contains parentheses is not special",
      line: "Hello (there).", element: .dialogue, previousElement: .dialogue,
      expected: .rewrite(range: 0..<14, replacement: "(Hello (there).)")),

    // Row 4 — "On a parenthetical | Move to the next line as dialogue."
    FountainTabRule(
      name: "a parenthetical moves to the next line as dialogue",
      line: "(beat)", element: .parenthetical, previousElement: .character,
      expected: .rewrite(range: 6..<6, replacement: "\n")),
    FountainTabRule(
      name: "an indented parenthetical does the same, and keeps its indent",
      line: "    (beat)", element: .parenthetical, previousElement: .dialogue,
      expected: .rewrite(range: 10..<10, replacement: "\n")),

    // Row 5 — "Anywhere ambiguous | Insert a literal tab." The row that matters most.
    //
    // An empty line under action or a scene heading is **not** in row 1: the table names
    // "dialogue or blank" and nothing else, so this package does not decide that a writer
    // who tabbed under a paragraph of action wanted a character cue.
    FountainTabRule(
      name: "an empty line under action is not in the table, so it takes the literal tab",
      line: "", element: .blank, previousElement: .action,
      expected: .literal),
    FountainTabRule(
      name: "an empty line under a scene heading takes the literal tab",
      line: "", element: .blank, previousElement: .sceneHeading,
      expected: .literal),
    FountainTabRule(
      name: "an empty line under a transition takes the literal tab",
      line: "", element: .blank, previousElement: .transition,
      expected: .literal),
    FountainTabRule(
      name: "a whitespace-only line is blank to the scanner but is not an *empty* line",
      line: "  ", element: .blank, previousElement: .dialogue,
      expected: .literal),
    FountainTabRule(
      name: "action is not dialogue, so tabbing on it inserts a tab",
      line: "Bob walks in.", element: .action, previousElement: .blank,
      expected: .literal),
    FountainTabRule(
      name: "a scene heading gets no scaffolding",
      line: "INT. HOUSE - DAY", element: .sceneHeading, previousElement: .blank,
      expected: .literal),
    FountainTabRule(
      name: "a transition gets none either",
      line: "CUT TO:", element: .transition, previousElement: .blank,
      expected: .literal),
    FountainTabRule(
      name: "lyrics continue a dialogue block in the scanner but are not a line of speech",
      line: "~Willy Wonka", element: .lyrics, previousElement: .dialogue,
      expected: .literal),
    FountainTabRule(
      name: "a whole-line note is commentary, not speech",
      line: "[[check this]]", element: .note, previousElement: .dialogue,
      expected: .literal),
    FountainTabRule(
      name: "a title-page value is not dialogue however it is punctuated",
      line: "    Bob", element: .titlePageValue, previousElement: .titlePageKey,
      expected: .literal),
    FountainTabRule(
      name: "a section heading is structure, not speech",
      line: "# Act One", element: .section, previousElement: .blank,
      expected: .literal),
    FountainTabRule(
      name: "an element this version has never heard of declines rather than guessing",
      line: "something", element: ElementKind(rawValue: "inventedByALaterRelease"),
      previousElement: .dialogue,
      expected: .literal),
  ]

  @Test("Tab at the end of the line does exactly what the table says", arguments: cases)
  func tabMatchesTheTable(testCase: FountainTabRule) {
    let outcome = FountainAffordances.tabOutcome(
      line: testCase.line,
      lineStart: 0,
      caret: testCase.line.utf16.count,
      element: testCase.element,
      previousElement: testCase.previousElement)
    #expect(outcome == testCase.expected)
  }

  /// The same table, with the line placed somewhere other than offset zero.
  ///
  /// Every range the rule emits is a **document** offset, and a rule that quietly returned
  /// line-relative offsets would pass every row above and corrupt every document below the
  /// first line. Row 3 makes this more than theoretical: its range is not empty and does not
  /// start at the caret, so a missed `lineStart` there would parenthesise somebody else's
  /// line.
  @Test("Every emitted range is in document coordinates, not line coordinates", arguments: cases)
  func rangesAreDocumentOffsets(testCase: FountainTabRule) {
    let lineStart = 137
    let outcome = FountainAffordances.tabOutcome(
      line: testCase.line,
      lineStart: lineStart,
      caret: lineStart + testCase.line.utf16.count,
      element: testCase.element,
      previousElement: testCase.previousElement)

    switch (outcome, testCase.expected) {
    case (.literal, .literal), (.consume, .consume):
      break
    case (.rewrite(let range, let replacement), .rewrite(let base, let baseReplacement)):
      #expect(range == (base.lowerBound + lineStart)..<(base.upperBound + lineStart))
      #expect(replacement == baseReplacement)
    default:
      Issue.record("outcome changed shape when the line moved: \(outcome)")
    }
  }

  // MARK: - Where the caret is

  /// Every row of the table is a whole-line context, and REQUIREMENTS.md states the sibling
  /// Markdown triggers as "Return **at end of** …". A Tab struck inside a line is a request
  /// to split it or to indent within it, and which of those was meant is not knowable.
  @Test(
    "A Tab anywhere but the end of the line is ambiguous and inserts a literal tab",
    arguments: [0, 1, 2, 3, 4, 5])
  func midLineTabIsALiteralTab(caret: Int) {
    for element in [ElementKind.dialogue, .character, .parenthetical] {
      #expect(
        FountainAffordances.tabOutcome(
          line: "(beat)", lineStart: 0, caret: caret, element: element,
          previousElement: .character) == .literal)
    }
  }

  @Test("A caret past the end of the line is nonsense and is declined, not clamped")
  func caretPastTheEndIsDeclined() {
    #expect(
      FountainAffordances.tabOutcome(
        line: "Hello.", lineStart: 0, caret: 99, element: .dialogue,
        previousElement: .character) == .literal)
  }

  @Test("A caret before the line's start is declined too")
  func caretBeforeTheLineIsDeclined() {
    #expect(
      FountainAffordances.tabOutcome(
        line: "Hello.", lineStart: 10, caret: 4, element: .dialogue,
        previousElement: .character) == .literal)
  }

  // MARK: - The dialogue-block allow-set

  /// Row 1 reads "previous block is dialogue **or blank**", and this is the "dialogue" half.
  ///
  /// An allow-set rather than a veto set, for the reason
  /// ``MarkdownListContinuation/isListContext(element:previousLine:)`` gives: an
  /// ``ElementKind`` added in a later minor release must decline rather than silently acquire
  /// an affordance nobody checked it against. `lyrics`, `note`, and `boneyard` keep the
  /// scanner's dialogue block open but are not lines of speech, and they are deliberately
  /// outside the set.
  @Test(
    "Only a cue, a parenthetical, and a line of speech count as a dialogue block",
    arguments: [
      (ElementKind.character, true),
      (ElementKind.parenthetical, true),
      (ElementKind.dialogue, true),
      (ElementKind.lyrics, false),
      (ElementKind.note, false),
      (ElementKind.boneyard, false),
      (ElementKind.blank, false),
      (ElementKind.action, false),
      (ElementKind.sceneHeading, false),
      (ElementKind.transition, false),
      (ElementKind.centered, false),
      (ElementKind.section, false),
      (ElementKind.synopsis, false),
      (ElementKind.titlePageKey, false),
      (ElementKind.titlePageValue, false),
      (ElementKind.paragraph, false),
      (ElementKind(rawValue: "inventedByALaterRelease"), false),
    ])
  func dialogueBlockAllowSet(element: ElementKind, isDialogue: Bool) {
    #expect(FountainAffordances.isDialogueBlock(element) == isDialogue)

    // And the allow-set really is what decides row 1, not merely what the predicate says.
    let outcome = FountainAffordances.tabOutcome(
      line: "", lineStart: 0, caret: 0, element: .blank, previousElement: element)
    if isDialogue {
      #expect(outcome == .rewrite(range: 0..<0, replacement: "\n"))
    } else if element == .blank {
      #expect(outcome == .consume)
    } else {
      #expect(outcome == .literal)
    }
  }

  // MARK: - The Return column

  /// The Return column of the table, row by row.
  ///
  /// **Stated honestly**: every row is a literal newline, so this assertion is green with
  /// ``FountainAffordances/returnOutcome(element:)`` replaced by `return .literal` and green
  /// end-to-end with the function absent entirely — `NSTextView` and `UITextView` insert the
  /// newline themselves. It is here because it is what goes red if a later change decides
  /// Return should be clever: the failure mode this pins down is an implementation that
  /// "helpfully" inserts a blank line after a cue, which would close the dialogue block the
  /// cue opened and turn the writer's next line into action.
  @Test(
    "Return is a literal newline in every context, which is what the table asks for",
    arguments: [
      // "On a character cue | Next line as dialogue, no blank line between."
      ElementKind.character,
      // "On a dialogue line | Continue dialogue."
      ElementKind.dialogue,
      // "On a parenthetical | Next line as dialogue."
      ElementKind.parenthetical,
      // The table's Return column for row 1 is "—", and everything else is ambiguous.
      ElementKind.blank,
      ElementKind.action,
      ElementKind.sceneHeading,
      ElementKind.transition,
      ElementKind.lyrics,
      ElementKind.titlePageKey,
    ])
  func returnIsAlwaysALiteralNewline(element: ElementKind) {
    #expect(FountainAffordances.returnOutcome(element: element) == .literal)
  }
}
