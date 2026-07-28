import EscriboCore
import Foundation

/// What a Return keystroke should actually do at the caret.
///
/// Two cases, and the first one is the default. REQUIREMENTS.md § Fountain Tab and Return
/// states the rule that governs both grammars: "When context is ambiguous, an affordance
/// does the boring thing. An affordance that guesses is worse than no affordance, because
/// the user cannot predict it and the correction costs more keystrokes than it saved."
/// Every path through ``MarkdownListContinuation`` that is not certain produces
/// ``literalNewline``, which means "let the text view insert a newline exactly as it would
/// have without this package."
enum ListContinuation: Equatable, Sendable {

  /// Do nothing special — the text view's own `insertNewline`/`insertText` runs unchanged.
  case literalNewline

  /// Replace `range` with `replacement`, in **document UTF-16 code-unit coordinates**.
  ///
  /// Deliberately expressed as one replacement rather than as "insert this, then delete
  /// that". REQUIREMENTS.md § Undo makes that shape mandatory rather than tidy: a single
  /// replacement is a single trip through the text view's input path and therefore a single
  /// undo action, and "no amount of `NSUndoManager` grouping reliably merges" two.
  case rewrite(range: Range<Int>, replacement: String)
}

/// The parsed shape of a Markdown list item's leading marker.
///
/// Produced by ``MarkdownListContinuation/marker(in:)`` and consumed by
/// ``MarkdownListContinuation/outcome(line:lineStart:caret:element:)``. Public to the test
/// target so the marker grammar can be asserted directly, without a text view anywhere in
/// the assertion — see the header of ``MarkdownListContinuation`` for why that matters.
struct ListItemMarker: Equatable, Sendable {

  /// How many UTF-16 code units of the line the marker occupies: indent, bullet or number,
  /// the whitespace after it, and a GFM task checkbox with its trailing whitespace if one
  /// is present.
  let prefixLength: Int

  /// The marker the **next** line should begin with — indent preserved verbatim, an ordered
  /// number incremented, a task checkbox reset to unchecked.
  let continuation: String

  /// Whether the line is empty apart from its marker.
  ///
  /// REQUIREMENTS.md § Editing behavior: "Return on an item that is empty apart from its
  /// marker | Delete the marker, leaving an empty line — do not insert another."
  let isEmptyItem: Bool
}

/// REQUIREMENTS.md § Editing behavior, "Continuation, not conversion", as a pure function.
///
/// ## Why this is a free enum and not four branches inside the text view
///
/// The same reason ``SelectionClamp`` is. Sortie 12 shipped a selection-clamping rule inline
/// and its integration tests passed **with the implementation deleted**, because
/// `NSTextView.selectedRange`'s setter clamps on its own; the tests were measuring AppKit.
/// The remedy, and the standing pattern in this package, is that a rule with a right answer
/// gets extracted to a function whose inputs and outputs are values, so that a test of it
/// cannot be satisfied by a framework standing in.
///
/// That risk is acute here. `NSTextView` and `UITextView` both do a great deal of undo and
/// input handling on their own, so an integration test that presses Return and reads the
/// document back can pass for reasons that have nothing to do with this file. Everything
/// below takes a `String` and an ``ElementKind`` and returns a value. Delete a rule and the
/// table in `MarkdownListContinuationTests` goes red immediately, with the failing row
/// naming itself.
///
/// ## Continuation, not conversion
///
/// REQUIREMENTS.md § "Input shortcuts" is the wrong frame: because markers are never hidden
/// (Architecture §2), typing `# ` needs no shortcut — the characters already are the syntax
/// and they are already correct. There is therefore **no conversion path in this file**, and
/// no keystroke other than Return reaches it.
///
/// ## What decides whether a line is a list item
///
/// The scanner does — that is what the `element` parameter is, and it is the gate. It is
/// what makes the affordance correct inside constructs this file knows nothing about:
///
/// - A `- item` line inside YAML frontmatter is **YAML**, not a Markdown list, and the
///   scanner classifies it ``ElementKind/frontmatter`` (DL-108: frontmatter exists in
///   `LineState` specifically so continuation can know not to fire inside it).
/// - A `- item` line inside a fenced code block is ``ElementKind/codeBlock``.
/// - A `- item` line inside a `fountain` fence is Fountain.
/// - A `--- ` under a paragraph is a setext ``ElementKind/heading`` underline, and deleting
///   it because it "looks like a marker-only item" would silently demote a heading.
///
/// None of those needed a rule here. Re-deriving "is this a list?" lexically would have
/// duplicated the grammar in a second place and got a different answer the first time
/// either changed.
///
/// ## DL-118 — two gaps in the scanner's *tight* list handling, and why they are absorbed
/// here rather than worked around
///
/// `MarkdownGrammar` (as of Sortie 20; the Markdown breadth sorties are still in flight)
/// misclassifies two shapes, both of them in **tight** lists — lists with no blank line
/// between items, which is the ordinary way people write them:
///
/// | Document | The scanner says | CommonMark says |
/// |---|---|---|
/// | `1. one`⏎`2. two` | line 2 is ``ElementKind/paragraph`` | an ordered list item |
/// | `- item`⏎`- ` | line 2 is ``ElementKind/heading`` | a blank list item |
///
/// Both come from `paragraphOpen` leaking across a list item: a list item may not interrupt
/// a paragraph unless it is non-blank and, if ordered, starts at 1 — a rule about paragraphs
/// *outside* a list, applied here to the paragraph inside the item above. The second case
/// then reaches the setext-underline rule, which claims a run of hyphens under an open
/// paragraph.
///
/// This matters enormously, because those two shapes are exactly the ones the affordance
/// exists for: "Return at end of `3. item`" and "Return on an item empty apart from its
/// marker" **are** the second-and-later items of a tight list. Gating strictly on
/// ``ElementKind/orderedListItem`` would have shipped a continuation that works for the first
/// item of a list and no other, and tests written to match would have certified that as
/// correct.
///
/// So the gate admits ``ElementKind/paragraph`` and ``ElementKind/heading`` **only when the
/// line immediately above also carries a list marker.** That one extra fact separates every
/// real case:
///
/// - `1. one`⏎`2. two`⏎`3. item` — the line above `3. item` is `2. two`, which carries a
///   marker, so the list continues. No recursion: each line only ever looks at the one above
///   it, and a tight list satisfies that at every step.
/// - `The years`⏎`1985. Something happened.` — the line above carries no marker, so this is
///   prose that begins with a year and Return inserts a newline.
/// - `prose`⏎`-` — the line above carries no marker, so the `-` stays the setext underline
///   the scanner said it was.
/// - `- item`⏎`- ` — the line above carries a marker, so the blank item loses its marker as
///   the requirement states.
///
/// When the scanner learns tight lists, every one of those lines starts arriving as a list
/// item and the fallback stops being reached. Nothing here has to be undone for that to
/// happen, which is the property that made this the right place to absorb the gap.
///
/// ## What is not here
///
/// Following ordered items are left exactly as the writer typed them. REQUIREMENTS.md
/// § Editing behavior defers rewriting their numbers outright: "It is a document-wide
/// rewrite triggered by a single keystroke, which fights coalesced undo and the line-local
/// edit model for a cosmetic gain — `1. 1. 1.` renders as 1, 2, 3 in every CommonMark
/// implementation anyway."
enum MarkdownListContinuation {

  // MARK: - The rule

  /// What Return should do, given the caret's line and how the scanner classified it.
  ///
  /// - Parameters:
  ///   - line: The caret's line **without its terminator**.
  ///   - previousLine: The line above it, without its terminator, or `nil` at the top of the
  ///     document. Read only by the DL-118 fallback.
  ///   - lineStart: The line's first UTF-16 offset in the document.
  ///   - caret: The caret's UTF-16 offset in the document.
  ///   - element: The scanner's classification of this line.
  /// - Returns: ``ListContinuation/literalNewline`` unless every condition for continuing a
  ///   list is met.
  static func outcome(
    line: String, previousLine: String? = nil, lineStart: Int, caret: Int, element: ElementKind
  ) -> ListContinuation {
    guard isListContext(element: element, previousLine: previousLine) else {
      return .literalNewline
    }

    // REQUIREMENTS.md states every continuation trigger as "Return **at end of** …".
    // A Return in the middle of an item splits it, and what the writer wants from the two
    // halves is not knowable — so it is ambiguous, and ambiguous means the boring thing.
    guard caret == lineStart + line.utf16.count, caret >= lineStart else {
      return .literalNewline
    }

    guard let marker = marker(in: line) else { return .literalNewline }

    // Rule: an item empty apart from its marker loses the marker and keeps the line.
    // The whole line goes, indent included — "leaving an empty line", and a line carrying
    // two columns of indent is not an empty line.
    if marker.isEmptyItem {
      return .rewrite(range: lineStart..<caret, replacement: "")
    }

    return .rewrite(range: caret..<caret, replacement: "\n" + marker.continuation)
  }

  /// Whether the caret's line is somewhere a Markdown list marker means a Markdown list.
  ///
  /// An **allow**-set rather than a veto set, so an ``ElementKind`` this version has never
  /// heard of declines rather than fires. A kind added in a later minor release must not turn
  /// an affordance on inside a construct nobody checked it against — REQUIREMENTS.md
  /// § Semver commitments makes adding kinds routine, and "the new construct silently
  /// acquired list continuation" is not a routine consequence.
  ///
  /// The `paragraph`/`heading` branch is DL-118, documented in full on the enum. It exists
  /// because the scanner misclassifies the second and later items of a *tight* list, which is
  /// the majority of lists in real documents.
  static func isListContext(element: ElementKind, previousLine: String?) -> Bool {
    if element == .unorderedListItem || element == .orderedListItem { return true }
    guard element == .paragraph || element == .heading else { return false }
    guard let previousLine, marker(in: previousLine) != nil else { return false }
    return true
  }

  // MARK: - The marker grammar

  /// Parses the leading marker of `line`, or returns `nil` if it has none.
  ///
  /// Hand-written scanning over UTF-16 code units, no regular expressions — the same rule
  /// the scanners live under (REQUIREMENTS.md requirement 4), applied here because this is
  /// grammar even though it lives beside the editor.
  ///
  /// Every marker character in both grammars is ASCII, so a code-unit walk cannot split a
  /// grapheme cluster: the loop stops at the first non-ASCII unit it meets, which is always
  /// content.
  static func marker(in line: String) -> ListItemMarker? {
    let units = Array(line.utf16)
    var cursor = 0

    // Indent, verbatim. "Return at end of an indented nested item | Continue at the same
    // indent" — and *the same indent* means the characters the writer typed, tabs included,
    // not a normalised count of columns.
    while cursor < units.count, isSpaceOrTab(units[cursor]) { cursor += 1 }
    let indentEnd = cursor
    guard cursor < units.count else { return nil }

    let nextBullet: String
    if isBullet(units[cursor]) {
      // `-`, `*`, `+` — carried through unchanged, because the writer chose it.
      nextBullet = String(UnicodeScalar(units[cursor])!)
      cursor += 1
    } else if let ordered = orderedBullet(units, from: cursor) {
      nextBullet = ordered.successor
      cursor = ordered.end
    } else {
      return nil
    }

    // At least one space or tab must follow, or the marker must end the line. `-item` is a
    // paragraph beginning with a hyphen, and `1.5` is not a list.
    let gapStart = cursor
    while cursor < units.count, isSpaceOrTab(units[cursor]) { cursor += 1 }
    guard cursor > gapStart || cursor == units.count else { return nil }
    let gap = cursor > gapStart ? string(units, gapStart..<cursor) : " "

    // A GFM task checkbox, if the item opens with one. Always continued **unchecked**:
    // REQUIREMENTS.md § Editing behavior, "Return at end of `- [ ] item` | Insert
    // `\n- [ ] ` (always unchecked)". Carrying a tick forward would assert the next item is
    // already done, which is never what pressing Return means.
    var checkbox = ""
    if let box = taskCheckbox(units, from: cursor) {
      checkbox = "[ ]" + box.gap
      cursor = box.end
    }

    let prefixLength = cursor
    var isEmptyItem = true
    var scan = cursor
    while scan < units.count {
      if !isSpaceOrTab(units[scan]) {
        isEmptyItem = false
        break
      }
      scan += 1
    }

    return ListItemMarker(
      prefixLength: prefixLength,
      continuation: string(units, 0..<indentEnd) + nextBullet + gap + checkbox,
      isEmptyItem: isEmptyItem)
  }

  // MARK: - Pieces

  /// An ordered-list bullet at `start`, and the bullet the next item should carry.
  ///
  /// The number is incremented and the delimiter — `.` or `)` — is preserved, because a
  /// document that uses `1)` throughout should keep using it. A run of digits that does not
  /// fit in an `Int`, or one that would overflow on increment, yields `nil` and therefore a
  /// literal newline: a pathological input degrades to the boring thing rather than to a
  /// trap inside a keystroke handler.
  private static func orderedBullet(_ units: [UInt16], from start: Int)
    -> (successor: String, end: Int)?
  {
    var cursor = start
    while cursor < units.count, isDigit(units[cursor]) { cursor += 1 }
    guard cursor > start else { return nil }
    guard cursor < units.count, isOrderedDelimiter(units[cursor]) else { return nil }

    guard let number = Int(string(units, start..<cursor)), number < Int.max else { return nil }
    let delimiter = String(UnicodeScalar(units[cursor])!)
    return ("\(number + 1)" + delimiter, cursor + 1)
  }

  /// A `[ ]`, `[x]`, or `[X]` checkbox at `start`, plus the whitespace after it.
  ///
  /// The same shape `MarkdownGrammar` recognises, restated here rather than reached for,
  /// because `EscriboCore` exposes the *classification* of a line and not the offsets inside
  /// its marker. It must be followed by whitespace or end the line, so `- [x]y` is an
  /// ordinary item whose text happens to begin with a bracket.
  private static func taskCheckbox(_ units: [UInt16], from start: Int)
    -> (gap: String, end: Int)?
  {
    guard start + 2 < units.count else { return nil }
    guard units[start] == leftBracket, units[start + 2] == rightBracket else { return nil }

    let mark = units[start + 1]
    guard mark == lowercaseX || mark == uppercaseX || isSpaceOrTab(mark) else { return nil }

    var end = start + 3
    guard end == units.count || isSpaceOrTab(units[end]) else { return nil }
    let gapStart = end
    while end < units.count, isSpaceOrTab(units[end]) { end += 1 }
    return (end > gapStart ? string(units, gapStart..<end) : " ", end)
  }

  private static func string(_ units: [UInt16], _ range: Range<Int>) -> String {
    range.isEmpty ? "" : String(decoding: units[range], as: UTF16.self)
  }

  // MARK: - Code units

  private static let tab: UInt16 = 0x09
  private static let space: UInt16 = 0x20
  private static let hyphen: UInt16 = 0x2D
  private static let asterisk: UInt16 = 0x2A
  private static let plus: UInt16 = 0x2B
  private static let period: UInt16 = 0x2E
  private static let rightParenthesis: UInt16 = 0x29
  private static let leftBracket: UInt16 = 0x5B
  private static let rightBracket: UInt16 = 0x5D
  private static let zero: UInt16 = 0x30
  private static let nine: UInt16 = 0x39
  private static let uppercaseX: UInt16 = 0x58
  private static let lowercaseX: UInt16 = 0x78

  private static func isSpaceOrTab(_ unit: UInt16) -> Bool { unit == space || unit == tab }
  private static func isDigit(_ unit: UInt16) -> Bool { unit >= zero && unit <= nine }
  private static func isBullet(_ unit: UInt16) -> Bool {
    unit == hyphen || unit == asterisk || unit == plus
  }
  private static func isOrderedDelimiter(_ unit: UInt16) -> Bool {
    unit == period || unit == rightParenthesis
  }
}
