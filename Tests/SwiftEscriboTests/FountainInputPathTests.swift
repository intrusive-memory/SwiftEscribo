import EscriboCore
import Foundation
import Testing

@testable import SwiftEscribo

#if os(macOS)
  import AppKit
#elseif os(iOS)
  import UIKit
#endif

// MARK: - Driving the real Tab key

/// Presses Tab the way the platform's keyboard does.
///
/// macOS routes Tab through `doCommandBySelector(insertTab:)`; UIKit has no such selector and
/// routes it through `UIKeyInput.insertText("\t")`. Both are the *entry points this package
/// overrides*, so a test that calls them exercises the shipped affordance rather than a
/// test-only hook. Nothing below ever calls `handleTabKey()` directly, because that would
/// prove the method works and not that the Tab key reaches it.
@MainActor
func pressTab(_ editor: EscriboTextView) {
  #if os(macOS)
    editor.textView.insertTab(nil)
  #elseif os(iOS)
    editor.textView.insertText("\t")
  #endif
}

/// One row of the Tab table, as a document: what it looked like, where the caret was, and what
/// it must look like afterwards.
///
/// A named type rather than a tuple so a failing row identifies itself in the test output.
struct FountainTabDocument: Sendable, CustomStringConvertible {

  /// Which row of REQUIREMENTS.md § Fountain Tab and Return this is, in the requirement's own
  /// words.
  let name: String

  /// The document before the keystroke.
  let before: String

  /// The caret's UTF-16 offset, with nothing selected.
  let caret: Int

  /// The document after exactly one Tab.
  let after: String

  var description: String { "\(name) — \(escaped(before)) → \(escaped(after))" }

  private func escaped(_ text: String) -> String {
    "\""
      + text.replacingOccurrences(of: "\n", with: "⏎").replacingOccurrences(
        of: "\t", with: "\\t") + "\""
  }
}

extension FountainTabDocument {

  /// Every row of the Tab column, as a document.
  ///
  /// Row 1 appears twice because the requirement's single row covers two contexts —
  /// "previous block is **dialogue**" and "previous block is **blank**" — whose behaviours
  /// differ: the first has a blank line to insert and the second already has one.
  ///
  /// Declared here rather than on the suite because the suite is `@MainActor` and
  /// `@Test(arguments:)` reads its arguments from outside that actor.
  static let all: [FountainTabDocument] = [
    FountainTabDocument(
      name: "Row 1 — empty line, previous block is dialogue: begin a character cue",
      before: "BOB\nHello.\n", caret: 11, after: "BOB\nHello.\n\n"),
    FountainTabDocument(
      name: "Row 1 — empty line, previous block is blank: already cue-ready, nothing inserted",
      before: "BOB\nHello.\n\n", caret: 12, after: "BOB\nHello.\n\n"),
    FountainTabDocument(
      name: "Row 2 — on a character cue: move to the next line as dialogue",
      before: "@BOB", caret: 4, after: "@BOB\n"),
    FountainTabDocument(
      name: "Row 3 — on a dialogue line: wrap the line in () as a parenthetical",
      before: "BOB\nHello.", caret: 10, after: "BOB\n(Hello.)"),
    FountainTabDocument(
      name: "Row 4 — on a parenthetical: move to the next line as dialogue",
      before: "BOB\n(beat)", caret: 10, after: "BOB\n(beat)\n"),
    FountainTabDocument(
      name: "Row 5 — anywhere ambiguous: insert a literal tab",
      before: "Bob walks in.", caret: 13, after: "Bob walks in.\t"),
  ]
}

/// REQUIREMENTS.md § Fountain Tab and Return, driven through the real Tab key on both
/// platforms.
///
/// The rules themselves are asserted in `FountainAffordanceTests`, where no framework can
/// stand in for them. **This suite proves something different and equally necessary**: that
/// the rules are reached by the Tab key at all, that the scanner's classification of a real
/// document selects the row the table names, and — on macOS — that the whole rewrite is one
/// undo action.
///
/// Platform-neutral where it can be. Undo assertions are macOS-only, because REQUIREMENTS.md
/// Known limitations §1 defers iOS undo deliberately. The *text* assertions run on both, which
/// is what Architecture §10 requires: the affordance is not a macOS feature.
@MainActor
@Suite("Fountain Tab through the text view's own input path")
struct FountainInputPathTests {

  @Test(
    "One Tab produces exactly the document the table says",
    arguments: FountainTabDocument.all)
  func tabProducesTheDocumentTheTableSays(testCase: FountainTabDocument) {
    let editor = EscriboTextView(language: .fountain, theme: .fountainLight)
    editor.applyExternalText(testCase.before)
    placeCaret(editor, at: testCase.caret)

    pressTab(editor)

    #expect(Array(editor.currentText.utf8) == Array(testCase.after.utf8))
  }

  /// The scaffolding is only worth inserting if it makes the *next* thing the writer types
  /// come out as the element they meant. Each row below types the name or the speech that the
  /// row's Tab was preparing for and asks the scanner what it got.
  ///
  /// This is what separates "the document text changed" from "the affordance worked". A Tab
  /// that inserted a newline in the wrong place would satisfy the table above for row 1 and
  /// fail here.
  @Test("Row 1 — after Tab, a name typed on the caret's line is a character cue")
  func afterTabAnEmptyLineBecomesACueLine() {
    let editor = EscriboTextView(language: .fountain, theme: .fountainLight)
    editor.applyExternalText("BOB\nHello.\n")
    placeCaretAtEnd(editor)

    pressTab(editor)
    typeText(editor, "JIM")
    // A natural cue needs a non-blank line under it, which is the line of speech that follows.
    typeText(editor, "\nHi.")

    #expect(editor.currentText == "BOB\nHello.\n\nJIM\nHi.")
    let jim = (editor.currentText as NSString).range(of: "JIM")
    #expect(editor.coordinator.elementKind(atUTF16Offset: jim.location) == .character)

    // And without the Tab, the same typing would have been a second line of Bob's speech —
    // which is the whole reason the row exists.
    let control = EscriboTextView(language: .fountain, theme: .fountainLight)
    control.applyExternalText("BOB\nHello.\nJIM\nHi.")
    let controlJim = (control.currentText as NSString).range(of: "JIM")
    #expect(control.coordinator.elementKind(atUTF16Offset: controlJim.location) == .dialogue)
  }

  @Test("Row 2 — after Tab on a cue, the caret's line is the cue's dialogue")
  func afterTabACueIsFollowedByDialogue() {
    let editor = EscriboTextView(language: .fountain, theme: .fountainLight)
    editor.applyExternalText("@BOB")
    placeCaretAtEnd(editor)

    pressTab(editor)
    typeText(editor, "Hello.")

    #expect(editor.currentText == "@BOB\nHello.")
    #expect(editor.coordinator.elementKind(atUTF16Offset: 5) == .dialogue)
  }

  @Test("Row 3 — the wrapped line really is a parenthetical to the scanner")
  func aWrappedDialogueLineIsAParenthetical() {
    let editor = EscriboTextView(language: .fountain, theme: .fountainLight)
    editor.applyExternalText("BOB\nHello.")
    placeCaretAtEnd(editor)

    pressTab(editor)

    #expect(editor.currentText == "BOB\n(Hello.)")
    #expect(editor.coordinator.elementKind(atUTF16Offset: 4) == .parenthetical)
  }

  /// The table's cycle, walked end to end: speech becomes a parenthetical, and a second Tab
  /// moves off it to the next line as dialogue. Only correct if the rewrite was rescanned as
  /// an ordinary edit — the second Tab reads a classification that did not exist before the
  /// first one.
  @Test("Row 3 then Row 4 — Tab twice wraps the line, then moves below it")
  func tabTwiceWrapsThenMovesOn() {
    let editor = EscriboTextView(language: .fountain, theme: .fountainLight)
    editor.applyExternalText("BOB\nHello.")
    placeCaretAtEnd(editor)

    pressTab(editor)
    #expect(editor.currentText == "BOB\n(Hello.)")

    pressTab(editor)
    #expect(editor.currentText == "BOB\n(Hello.)\n")
  }

  @Test("Row 3 — an indented dialogue line keeps its indent outside the parentheses")
  func indentSurvivesTheWrap() {
    let editor = EscriboTextView(language: .fountain, theme: .fountainLight)
    editor.applyExternalText("BOB\n\tHello.")
    placeCaretAtEnd(editor)

    pressTab(editor)

    #expect(editor.currentText == "BOB\n\t(Hello.)")
  }

  // MARK: - Row 5, the row that matters most

  /// REQUIREMENTS.md: "**The last row is the important one.** When context is ambiguous, an
  /// affordance does the boring thing."
  ///
  /// One `\t`, and nothing else: not a newline as well, not a tab in place of the line, and
  /// not two tabs from a handler that both rewrote and let `super` run.
  @Test(
    "An ambiguous Tab inserts exactly one tab character and nothing else",
    arguments: [
      // Action — the commonest ambiguous context in a screenplay.
      ("Bob walks in.", "Bob walks in.\t"),
      // A scene heading.
      ("INT. HOUSE - DAY", "INT. HOUSE - DAY\t"),
      // A transition.
      ("CUT TO:", "CUT TO:\t"),
      // An empty line under action: not "dialogue or blank", so not row 1.
      ("Bob walks in.\n", "Bob walks in.\n\t"),
      // A section heading.
      ("# Act One", "# Act One\t"),
    ])
  func ambiguousTabInsertsOneLiteralTab(before: String, after: String) {
    let editor = EscriboTextView(language: .fountain, theme: .fountainLight)
    editor.applyExternalText(before)
    placeCaretAtEnd(editor)

    pressTab(editor)

    #expect(Array(editor.currentText.utf8) == Array(after.utf8))
    #expect(editor.currentText.filter { $0 == "\t" }.count == 1)
    #expect(editor.currentText.filter { $0 == "\n" }.count == before.filter { $0 == "\n" }.count)
  }

  @Test("A mid-line Tab is ambiguous and inserts a literal tab, splitting nothing")
  func midLineTabIsALiteralTab() {
    let editor = EscriboTextView(language: .fountain, theme: .fountainLight)
    editor.applyExternalText("BOB\nHello.")
    placeCaret(editor, at: 6)

    pressTab(editor)

    #expect(editor.currentText == "BOB\nHe\tllo.")
  }

  @Test("Tab with a selection is ambiguous — the selection is replaced by a tab")
  func tabWithASelectionIsALiteralTab() {
    let editor = EscriboTextView(language: .fountain, theme: .fountainLight)
    editor.applyExternalText("BOB\nHello.")
    editor.textView.selectedRange = NSRange(location: 4, length: 6)

    pressTab(editor)

    #expect(editor.currentText == "BOB\n\t")
  }

  /// Markdown has no Tab affordance at all — REQUIREMENTS.md gives Tab a column only under
  /// § Fountain Tab and Return. A dialogue-shaped Markdown document must therefore get a tab.
  @Test("Markdown documents get a literal tab, whatever their lines look like")
  func markdownGetsALiteralTab() {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    editor.applyExternalText("BOB\nHello.")
    placeCaretAtEnd(editor)

    pressTab(editor)

    #expect(editor.currentText == "BOB\nHello.\t")
  }

  // MARK: - Return

  /// REQUIREMENTS.md § Fountain Tab and Return: "On a character cue | Next line as dialogue,
  /// **no blank line between**."
  ///
  /// ⚠️ Stated honestly: a plain newline already satisfies this, so the assertion below is
  /// green with every line of Sortie 26's Return path deleted. It is not vacuous — it fails
  /// for the implementation the requirement is warning against, one that inserts a blank line
  /// to separate the cue from what follows, and it fails if Markdown's list continuation ever
  /// leaks into Fountain — but it cannot distinguish "implemented" from "correctly left
  /// alone". `FountainAffordanceTests` says the same thing about the rule function.
  @Test("Return on a character cue produces a dialogue line with no blank line between")
  func returnOnACueProducesDialogueWithNoBlankLine() {
    let editor = EscriboTextView(language: .fountain, theme: .fountainLight)
    editor.applyExternalText("@BOB")
    placeCaretAtEnd(editor)

    pressReturn(editor)
    typeText(editor, "Hello.")

    // No blank line anywhere, and the cue and its speech are adjacent lines.
    #expect(editor.currentText == "@BOB\nHello.")
    #expect(editor.currentText.contains("\n\n") == false)

    // And the line Return created is dialogue, which is the claim the row actually makes.
    #expect(editor.coordinator.elementKind(atUTF16Offset: 5) == .dialogue)
  }

  @Test("Return on a natural cue does the same, with the speech that follows pushed down")
  func returnOnANaturalCueKeepsTheBlockOpen() {
    let editor = EscriboTextView(language: .fountain, theme: .fountainLight)
    editor.applyExternalText("BOB\nHello.")
    placeCaret(editor, at: 3)

    pressReturn(editor)
    typeText(editor, "Hi.")

    #expect(editor.currentText == "BOB\nHi.\nHello.")
    #expect(editor.coordinator.elementKind(atUTF16Offset: 4) == .dialogue)
    #expect(editor.coordinator.elementKind(atUTF16Offset: 8) == .dialogue)
  }

  @Test("Return on a dialogue line continues dialogue")
  func returnOnDialogueContinuesDialogue() {
    let editor = EscriboTextView(language: .fountain, theme: .fountainLight)
    editor.applyExternalText("BOB\nHello.")
    placeCaretAtEnd(editor)

    pressReturn(editor)
    typeText(editor, "And again.")

    #expect(editor.currentText == "BOB\nHello.\nAnd again.")
    #expect(editor.coordinator.elementKind(atUTF16Offset: 11) == .dialogue)
  }

  @Test("Return on a parenthetical moves to the next line as dialogue")
  func returnOnAParentheticalContinuesDialogue() {
    let editor = EscriboTextView(language: .fountain, theme: .fountainLight)
    editor.applyExternalText("BOB\n(beat)")
    placeCaretAtEnd(editor)

    pressReturn(editor)
    typeText(editor, "Hello.")

    #expect(editor.currentText == "BOB\n(beat)\nHello.")
    #expect(editor.coordinator.elementKind(atUTF16Offset: 11) == .dialogue)
  }
}

// MARK: - Proving the input path was taken

/// The witness that works on both platforms: `textDidChange` (AppKit) and `textViewDidChange`
/// (UIKit) are posted by the **text view**, so a storage mutation behind its back reads zero
/// and two transactions read two.
///
/// On iOS this is the only assertion available — undo is deferred there (Known limitations
/// §1) — and the shape is exactly what Architecture §10 requires to be identical across
/// platforms, so it is measured on both with the same assertion.
@MainActor
@Suite("Every Fountain rewrite goes through the text view, not around it")
struct FountainInputPathIsActuallyUsedTests {

  @Test("Wrapping a dialogue line in parentheses is one transaction")
  func wrapNotifiesTheTextViewOnce() {
    let editor = EscriboTextView(language: .fountain, theme: .fountainLight)
    let counter = TextChangeCounter()
    editor.textView.delegate = counter

    editor.applyExternalText("BOB\nHello.")
    placeCaretAtEnd(editor)
    counter.reset()

    pressTab(editor)

    #expect(editor.currentText == "BOB\n(Hello.)")
    #expect(counter.count == 1)
  }

  @Test("Beginning a character cue is one transaction")
  func cueScaffoldingNotifiesTheTextViewOnce() {
    let editor = EscriboTextView(language: .fountain, theme: .fountainLight)
    let counter = TextChangeCounter()
    editor.textView.delegate = counter

    editor.applyExternalText("BOB\nHello.\n")
    placeCaretAtEnd(editor)
    counter.reset()

    pressTab(editor)

    #expect(editor.currentText == "BOB\nHello.\n\n")
    #expect(counter.count == 1)
  }

  /// The ``FountainAffordanceOutcome/consume`` row, which is the one place in this package
  /// where a keystroke is swallowed. It must not reach the text view at all: an empty edit
  /// through the input path would notify, and on macOS would register an undo action that
  /// appears to do nothing.
  @Test("A consumed Tab does not touch the document and does not notify the text view")
  func aConsumedTabChangesNothing() {
    let editor = EscriboTextView(language: .fountain, theme: .fountainLight)
    let counter = TextChangeCounter()
    editor.textView.delegate = counter

    editor.applyExternalText("BOB\nHello.\n\n")
    placeCaretAtEnd(editor)
    counter.reset()

    pressTab(editor)

    #expect(editor.currentText == "BOB\nHello.\n\n")
    #expect(counter.count == 0)

    // Idempotent: pressing it again still changes nothing, rather than walking the writer
    // down the page one blank line per press.
    pressTab(editor)
    pressTab(editor)
    #expect(editor.currentText == "BOB\nHello.\n\n")
    #expect(counter.count == 0)
  }

  @Test("A declined Tab is the text view's own tab, not a second transaction")
  func declinedTabIsOneOrdinaryInsertion() {
    let editor = EscriboTextView(language: .fountain, theme: .fountainLight)
    let counter = TextChangeCounter()
    editor.textView.delegate = counter

    editor.applyExternalText("Bob walks in.")
    placeCaretAtEnd(editor)
    counter.reset()

    pressTab(editor)

    #expect(editor.currentText == "Bob walks in.\t")
    #expect(counter.count == 1)
  }
}

#if os(macOS)

  // MARK: - One undo action

  /// REQUIREMENTS.md § Undo: "**Every affordance-driven rewrite is one undo action, together
  /// with the keystroke that triggered it.**"
  ///
  /// Both measurements Sortie 25 established are needed here for the same reasons, and the
  /// first one is the one that makes the rest mean anything: ``settleEventGroup()`` spins the
  /// run loop so each keystroke lands in its own undo group. Without it `UndoManager`'s
  /// `groupsByEvent` observer never fires in a unit test, every mutation since
  /// `removeAllActions()` accumulates into one group, and "one Cmd-Z returns to exactly the
  /// prior state" is true for **any** implementation, including one that rewrote the document
  /// in four separate transactions.
  ///
  /// ``CountingUndoManager`` supplies the second: the count of undo *registrations*, which is
  /// this package's business rather than AppKit's grouping. A rewrite applied as two trips
  /// through the input path registers two and fails here while still restoring correctly after
  /// two Cmd-Zs; a direct storage mutation registers zero and leaves a half-undone document.
  @MainActor
  @Suite("Coalesced undo — a Fountain rewrite and its keystroke are one action")
  struct FountainCoalescedUndoTests {

    @Test("Tab then one undo on a dialogue line restores exactly the prior document")
    func wrappingIsOneUndoAction() {
      let fixture = UndoableEditor(seededWith: "BOB\nHello.", language: .fountain)
      let before = fixture.text
      placeCaretAtEnd(fixture.editor)

      pressTab(fixture.editor)
      settleEventGroup()

      #expect(fixture.text == "BOB\n(Hello.)")
      // The opening and the closing parenthesis together are ONE registered undo operation.
      #expect(fixture.registrations == 1)

      #expect(fixture.undo.canUndo == true)
      fixture.undo.undo()

      // Byte for byte, not merely equal-looking. A rewrite applied as two edits would leave
      // "BOB\n(Hello." here.
      #expect(Array(fixture.text.utf8) == Array(before.utf8))
      #expect(fixture.undo.canUndo == false)
    }

    @Test("Tab then one undo on a character cue restores exactly the prior document")
    func cueScaffoldingIsOneUndoAction() {
      let fixture = UndoableEditor(seededWith: "@BOB", language: .fountain)
      let before = fixture.text
      placeCaretAtEnd(fixture.editor)

      pressTab(fixture.editor)
      settleEventGroup()
      #expect(fixture.text == "@BOB\n")
      #expect(fixture.registrations == 1)

      fixture.undo.undo()
      #expect(Array(fixture.text.utf8) == Array(before.utf8))
      #expect(fixture.undo.canUndo == false)
    }

    @Test("Tab then one undo on an empty line under speech restores exactly the prior document")
    func beginningACueIsOneUndoAction() {
      let fixture = UndoableEditor(seededWith: "BOB\nHello.\n", language: .fountain)
      let before = fixture.text
      placeCaretAtEnd(fixture.editor)

      pressTab(fixture.editor)
      settleEventGroup()
      #expect(fixture.text == "BOB\nHello.\n\n")
      #expect(fixture.registrations == 1)

      fixture.undo.undo()
      #expect(Array(fixture.text.utf8) == Array(before.utf8))
      #expect(fixture.undo.canUndo == false)
    }

    /// A consumed keystroke registers nothing. Anything else would give the writer a Cmd-Z
    /// that appears to do nothing at all.
    @Test("A consumed Tab registers no undo action")
    func consumedTabRegistersNothing() {
      let fixture = UndoableEditor(seededWith: "BOB\nHello.\n\n", language: .fountain)
      placeCaretAtEnd(fixture.editor)

      pressTab(fixture.editor)
      settleEventGroup()

      #expect(fixture.text == "BOB\nHello.\n\n")
      #expect(fixture.registrations == 0)
      #expect(fixture.undo.canUndo == false)
    }

    /// The affordance must not absorb the typing that preceded it — that is the difference
    /// between "returns to exactly the prior state" and "unwinds the sentence as well".
    @Test("A Tab rewrite does not absorb the typing that came before it")
    func wrappingDoesNotSwallowPrecedingTyping() {
      let fixture = UndoableEditor(seededWith: "BOB\n", language: .fountain)
      placeCaretAtEnd(fixture.editor)
      typeText(fixture.editor, "Hello.")
      settleEventGroup()
      #expect(fixture.text == "BOB\nHello.")

      pressTab(fixture.editor)
      settleEventGroup()
      #expect(fixture.text == "BOB\n(Hello.)")

      fixture.undo.undo()
      #expect(fixture.text == "BOB\nHello.")
    }

    /// Undo has to survive being used, or "one action" is true only for the first keystroke.
    @Test("A run of Tab keystrokes unwinds one keystroke at a time")
    func tabsUnwindOneAtATime() {
      let fixture = UndoableEditor(seededWith: "BOB\nHello.", language: .fountain)
      placeCaretAtEnd(fixture.editor)

      pressTab(fixture.editor)
      settleEventGroup()
      pressTab(fixture.editor)
      settleEventGroup()

      #expect(fixture.text == "BOB\n(Hello.)\n")
      // Two keystrokes, two undo registrations. Not one, and not three.
      #expect(fixture.registrations == 2)

      fixture.undo.undo()
      #expect(fixture.text == "BOB\n(Hello.)")
      fixture.undo.undo()
      #expect(fixture.text == "BOB\nHello.")
      #expect(fixture.undo.canUndo == false)
    }

    /// The ambiguous row goes through `NSTextView`'s own tab insertion, which is still one
    /// undo action — this is AppKit's doing, and it is asserted so that a future handler that
    /// both rewrites *and* lets `super` run shows up as two.
    @Test("An ambiguous Tab is one undo action too, and AppKit's own")
    func ambiguousTabIsOneUndoAction() {
      let fixture = UndoableEditor(seededWith: "Bob walks in.", language: .fountain)
      let before = fixture.text
      placeCaretAtEnd(fixture.editor)

      pressTab(fixture.editor)
      settleEventGroup()
      #expect(fixture.text == "Bob walks in.\t")
      #expect(fixture.registrations == 1)

      fixture.undo.undo()
      #expect(Array(fixture.text.utf8) == Array(before.utf8))
    }

    /// Return in a Fountain document is a plain newline, and a plain newline is one undo
    /// action. ⚠️ AppKit's, not this package's — see the honesty note in
    /// `FountainInputPathTests`.
    @Test("Return on a cue is one undo action")
    func returnOnACueIsOneUndoAction() {
      let fixture = UndoableEditor(seededWith: "@BOB", language: .fountain)
      let before = fixture.text
      placeCaretAtEnd(fixture.editor)

      pressReturn(fixture.editor)
      settleEventGroup()
      #expect(fixture.text == "@BOB\n")
      #expect(fixture.registrations == 1)

      fixture.undo.undo()
      #expect(Array(fixture.text.utf8) == Array(before.utf8))
    }
  }

#endif
