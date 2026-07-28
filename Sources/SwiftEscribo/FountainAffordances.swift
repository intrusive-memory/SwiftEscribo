import EscriboCore
import Foundation

/// What a Tab or a Return keystroke should actually do at the caret in a Fountain document.
///
/// Three cases, and the first one is the default. REQUIREMENTS.md § Fountain Tab and Return
/// states the governing rule: "When context is ambiguous, an affordance does the boring
/// thing. An affordance that guesses is worse than no affordance, because the user cannot
/// predict it and the correction costs more keystrokes than it saved." Every path through
/// ``FountainAffordances`` that is not certain produces ``literal``.
///
/// ``consume`` is the one case ``ListContinuation`` has no equivalent of, and it exists for
/// exactly one row of the table — see ``FountainAffordances/tabOutcome(line:lineStart:caret:element:previousElement:)``.
enum FountainAffordanceOutcome: Equatable, Sendable {

  /// Do nothing special — the text view's own `insertTab`/`insertNewline` runs unchanged and
  /// puts a literal tab or a literal newline in the document. The last row of the table.
  case literal

  /// Swallow the keystroke and change nothing.
  ///
  /// **Not** the same as ``literal``, and not a way of saying "declined". It is the answer
  /// for a context where the rule's *post-condition already holds*: Tab on an empty line that
  /// is already preceded by a blank line has nothing to insert, because the blank line a
  /// character cue needs is already there. Inserting a literal tab would put whitespace in a
  /// document that asked for structure, and inserting another newline would walk the writer
  /// down the page one blank line per keypress.
  ///
  /// A caller must not turn this into an empty ``rewrite``: an empty replacement over an
  /// empty range still travels the input path and still registers an undo action, so Cmd-Z
  /// would appear to do nothing.
  case consume

  /// Replace `range` with `replacement`, in **document UTF-16 code-unit coordinates**.
  ///
  /// One replacement, for the reason ``ListContinuation/rewrite(range:replacement:)`` gives:
  /// REQUIREMENTS.md § Undo makes a single trip through the text view's input path the
  /// definition of a single undo action, and "no amount of `NSUndoManager` grouping reliably
  /// merges" two.
  case rewrite(range: Range<Int>, replacement: String)
}

/// REQUIREMENTS.md § Fountain Tab and Return, as pure functions.
///
/// ## Scaffolding, not markup
///
/// The requirement's own framing decides almost everything in this file: "Fountain structure
/// is positional — blank lines and capitalization — so these affordances insert **scaffolding
/// rather than markup**." So none of these rules types a `@`, a `.`, or a `>` on the writer's
/// behalf. Fountain's forcing markers exist for the cases the positional rules cannot reach,
/// and a Tab key that emitted one would be answering a question the writer did not ask —
/// `@` on a line the natural rule would have claimed anyway is decoration, and it is
/// decoration the writer then has to delete.
///
/// What the affordance inserts instead is the *position*: the blank line above a cue, and the
/// unblanked line below one. The one exception is the parenthetical, whose parentheses print
/// and are therefore content rather than markup — REQUIREMENTS.md names it in the table as
/// "wrap the line in `()`".
///
/// ## Why this is a free enum and not four branches inside the text view
///
/// The same reason ``MarkdownListContinuation`` is, and the reason is sharper here.
/// `NSTextView.insertTab(_:)` already inserts a tab and `insertNewline(_:)` already inserts a
/// newline, so an integration test that presses a key and reads the document back can agree
/// with the requirement while this file is *empty* — the frameworks supply the "boring thing"
/// for free. Sortie 12 shipped a rule inline and its tests passed with the implementation
/// deleted, for precisely that shape of reason.
///
/// Everything below therefore takes values and returns values, and
/// `FountainAffordanceTests` asserts the table against them. Delete a branch and a named row
/// goes red.
///
/// ## The Return column is the boring thing in every row, and that is a finding
///
/// Read the Return column of the table against what a plain newline already does:
///
/// | Context | Return must | A plain newline does |
/// |---|---|---|
/// | On a character cue | Next line as dialogue, **no blank line between** | Exactly that |
/// | On a dialogue line | Continue dialogue | Exactly that — the block stays open |
/// | On a parenthetical | Next line as dialogue | Exactly that |
///
/// A cue opens a dialogue block and the block is closed only by a blank line or by a
/// non-dialogue element (`FountainGrammar`'s end-state rule), so inserting one newline and
/// nothing else *is* "next line as dialogue with no blank line between" in all three rows.
/// The requirement is a prohibition — do not helpfully insert a blank line, do not continue
/// Markdown's list markers here — rather than an instruction.
///
/// ``returnOutcome(element:)`` is written out anyway, and is asserted row by row, for two
/// reasons: it is where the reasoning above is recorded against the rows it applies to, and
/// it is the thing that goes red if a later change decides Return should be clever. It is
/// stated honestly in the tests that an end-to-end Return assertion could not have failed
/// even with this file absent.
enum FountainAffordances {

  // MARK: - Tab

  /// What Tab should do at the caret, given the caret's line and how the scanner classified
  /// it and the line above it.
  ///
  /// The rows of REQUIREMENTS.md § Fountain Tab and Return's Tab column, in order:
  ///
  /// | Context | Tab | Here |
  /// |---|---|---|
  /// | Empty line, previous block is dialogue or blank | Begin a character cue | ``FountainAffordanceOutcome/rewrite(range:replacement:)`` of `"\n"`, or ``FountainAffordanceOutcome/consume`` |
  /// | On a character cue | Move to the next line as dialogue | `"\n"` at the caret |
  /// | On a dialogue line | Wrap the line in `()` as a parenthetical | The line's content, parenthesised |
  /// | On a parenthetical | Move to the next line as dialogue | `"\n"` at the caret |
  /// | Anywhere ambiguous | Insert a literal tab | ``FountainAffordanceOutcome/literal`` |
  ///
  /// ## Row 1 has two shapes, and only one of them inserts anything
  ///
  /// "Begin a character cue" is a post-condition, not an insertion: after Tab, the caret must
  /// sit on a line that Fountain will read as a character cue the moment a name is typed on
  /// it. A natural cue needs a **blank line above it** (`FountainGrammar.naturalCharacter`
  /// declines when `followsNonBlankLine`), so:
  ///
  /// - Above a dialogue block's last line, that blank line does not exist yet, and one
  ///   newline creates it. `BOB`⏎`Hello.`⏎ with the caret on the empty third line becomes
  ///   `BOB`⏎`Hello.`⏎⏎ with the caret on the fourth, where `JIM` is a cue and not a second
  ///   line of Bob's speech — which is what it would have been without the keystroke.
  /// - Above a blank line, it already exists. There is nothing to insert, so the keystroke is
  ///   consumed and the document is untouched. That makes Tab **idempotent** here: pressing
  ///   it three times leaves the writer cue-ready once, not three blank lines further down.
  ///
  /// An empty line under *action* or a scene heading is in neither shape. The table names
  /// "dialogue or blank" and nothing else, so that context is ambiguous and takes the literal
  /// tab — the row that matters most.
  ///
  /// ## Row 2 pushes whatever was below the cue down, deliberately
  ///
  /// A *natural* cue is only a cue when a non-blank line follows it, so at the end of one
  /// there is always something below to push. Tab inserts one newline there anyway, because
  /// the alternative — moving the caret without editing when the line below is already
  /// dialogue — is a second rule the table does not state, and one whose behaviour changes
  /// depending on what the writer happened to have typed underneath.
  ///
  /// - Parameters:
  ///   - line: The caret's line **without its terminator**.
  ///   - lineStart: That line's first UTF-16 offset in the document.
  ///   - caret: The caret's UTF-16 offset in the document.
  ///   - element: The scanner's classification of the caret's line.
  ///   - previousElement: The scanner's classification of the line above, or `nil` at the top
  ///     of the document. Read only by row 1.
  static func tabOutcome(
    line: String,
    lineStart: Int,
    caret: Int,
    element: ElementKind,
    previousElement: ElementKind?
  ) -> FountainAffordanceOutcome {
    // Every row of the table is stated as a whole-line context, and REQUIREMENTS.md states
    // the sibling Markdown triggers as "Return **at end of** …". A Tab struck in the middle
    // of a line is a request to split it or to indent inside it, and which of those the
    // writer meant is not knowable — so it is ambiguous, and ambiguous means the boring
    // thing.
    guard caret >= lineStart, caret == lineStart + line.utf16.count else { return .literal }

    switch element {
    case .blank:
      // Row 1. A whitespace-only line is `blank` to the scanner but is not an *empty* line,
      // which is what the row says; the writer has already put characters there, and this
      // will not silently build structure around them.
      guard line.isEmpty else { return .literal }
      guard let previousElement else { return .consume }
      if previousElement == .blank { return .consume }
      guard isDialogueBlock(previousElement) else { return .literal }
      return .rewrite(range: caret..<caret, replacement: "\n")

    case .character, .parenthetical:
      // Rows 2 and 4 — "move to the next line as dialogue". One newline, never two: a blank
      // line between a cue and its speech closes the dialogue block and turns the speech into
      // action, which is the exact failure the Return column names.
      return .rewrite(range: caret..<caret, replacement: "\n")

    case .dialogue:
      // Row 3 — wrap the line in `()`.
      return parenthesise(line: line, lineStart: lineStart)

    default:
      return .literal
    }
  }

  /// Row 3: the line's content, in parentheses, as one replacement.
  ///
  /// Only the content is replaced — the leading indent and any trailing whitespace stay
  /// exactly where the writer left them, outside the parentheses. `FountainGrammar`'s
  /// parenthetical rule trims both before it looks for the brackets, so `  (beat)  ` is a
  /// parenthetical, and rewriting the whole line instead would have thrown away indentation
  /// the writer typed for a formatting effect that survives into the printed page.
  ///
  /// A line with no content cannot reach here — the scanner calls a whitespace-only line
  /// `blank`, not `dialogue` — but the guard is kept because the alternative is emitting
  /// `()` around nothing, which is a parenthetical with no word in it.
  private static func parenthesise(line: String, lineStart: Int) -> FountainAffordanceOutcome {
    let units = Array(line.utf16)
    var start = 0
    while start < units.count, isSpaceOrTab(units[start]) { start += 1 }
    var end = units.count
    while end > start, isSpaceOrTab(units[end - 1]) { end -= 1 }
    guard end > start else { return .literal }

    let content = String(decoding: units[start..<end], as: UTF16.self)
    return .rewrite(
      range: (lineStart + start)..<(lineStart + end), replacement: "(" + content + ")")
  }

  /// Whether `element` is a line of an open dialogue block.
  ///
  /// The three elements a cue's block is made of, and the same three `FountainGrammar` keeps
  /// `inDialogueBlock` open across. An **allow**-set rather than a veto set, for the reason
  /// ``MarkdownListContinuation/isListContext(element:previousLine:)`` gives: an
  /// ``ElementKind`` a later minor release adds must decline here rather than silently
  /// acquiring an affordance nobody checked it against.
  ///
  /// `lyrics`, `note`, and `boneyard` also continue an open block in the scanner and are
  /// deliberately **not** here. They continue a block; they are not a block of speech, and
  /// "the previous block is dialogue" is a claim about what the writer just wrote, not about
  /// what the scanner's state machine tolerates.
  static func isDialogueBlock(_ element: ElementKind) -> Bool {
    element == .dialogue || element == .parenthetical || element == .character
  }

  // MARK: - Return

  /// What Return should do at the caret in a Fountain document: a newline, in every row.
  ///
  /// See the enum's header for why this is not an oversight. A cue opens a dialogue block, a
  /// parenthetical and a line of speech continue it, and a single newline leaves the caret on
  /// the very next line with the block still open — which is what all three rows of the Return
  /// column ask for, stated as a prohibition on inserting a blank line rather than as an
  /// instruction to insert anything.
  ///
  /// Written as a switch over the rows it governs, rather than as `return .literal`, so that
  /// the rows are enumerable by the test that asserts them and so that a later change which
  /// makes one of them clever has to say so here.
  static func returnOutcome(element: ElementKind) -> FountainAffordanceOutcome {
    switch element {
    case .character:
      // "Next line as dialogue, no blank line between." One newline does it; two would close
      // the block the cue just opened.
      return .literal
    case .dialogue:
      // "Continue dialogue." The block is already open and a newline does not close it.
      return .literal
    case .parenthetical:
      // "Next line as dialogue." As above — a parenthetical continues a block, so the line
      // below a newline is inside the same one.
      return .literal
    default:
      // Every other context, including the empty line whose Return column the table leaves
      // as "—".
      return .literal
    }
  }

  // MARK: - Code units

  private static let tab: UInt16 = 0x09
  private static let space: UInt16 = 0x20

  private static func isSpaceOrTab(_ unit: UInt16) -> Bool { unit == space || unit == tab }
}
