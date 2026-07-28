import EscriboCore
import Foundation
import Testing

@testable import SwiftEscribo

#if os(macOS)
  import AppKit
#elseif os(iOS)
  import UIKit
#endif

// MARK: - Driving the real Return key

/// Presses Return the way the platform's keyboard does.
///
/// macOS routes Return through `doCommandBySelector(insertNewline:)`; UIKit routes it
/// through `UIKeyInput.insertText("\n")`. Both are the *entry points this package overrides*,
/// so a test that calls them exercises the shipped affordance rather than a test-only hook.
/// Nothing below ever calls `handleReturnKey()` directly, because that would prove the
/// method works and not that the Return key reaches it.
@MainActor
func pressReturn(_ editor: EscriboTextView) {
  #if os(macOS)
    editor.textView.insertNewline(nil)
  #elseif os(iOS)
    editor.textView.insertText("\n")
  #endif
}

/// Puts the caret at `offset` with nothing selected.
@MainActor
func placeCaret(_ editor: EscriboTextView, at offset: Int) {
  editor.textView.selectedRange = NSRange(location: offset, length: 0)
}

/// Puts the caret at the end of the document.
@MainActor
func placeCaretAtEnd(_ editor: EscriboTextView) {
  placeCaret(editor, at: editor.documentStorage.length)
}

/// Types `text` at the caret, through the same input path the keyboard uses.
@MainActor
func typeText(_ editor: EscriboTextView, _ text: String) {
  #if os(macOS)
    editor.textView.insertText(text, replacementRange: editor.textView.selectedRange)
  #elseif os(iOS)
    editor.textView.insertText(text)
  #endif
}

#if os(macOS)

  /// Vends a test-owned `UndoManager` to an `NSTextView`.
  ///
  /// ## Why this is necessary, and why it is not a cheat
  ///
  /// `NSResponder.undoManager` walks the responder chain to a window. An `NSTextView` built
  /// in a unit test has no window, so without this the text view has no undo manager and
  /// every undo assertion would vacuously pass or vacuously fail — the exact shape of
  /// unfalsifiable criterion this mission has found seven of.
  ///
  /// `undoManager(for:)` is `NSTextViewDelegate`'s own documented hook and is the *first*
  /// place `NSTextView` looks, ahead of the responder chain. So the undo that gets registered
  /// here is registered by `NSTextView` itself, through exactly the mechanism a real host
  /// would use — this supplies the manager and nothing else. It registers no actions, groups
  /// nothing, and coalesces nothing.
  ///
  /// `EscriboEditorBridge` deliberately does **not** implement this method, so a shipped
  /// editor still reaches its host's real undo stack.
  @MainActor
  final class TestUndoManagerProvider: NSObject, NSTextViewDelegate {

    let manager = CountingUndoManager()

    func undoManager(for view: NSTextView) -> UndoManager? { manager }
  }

  /// An `UndoManager` that counts how many undo operations were registered against it.
  ///
  /// ## Why counting, and not `canUndo`
  ///
  /// `canUndo` measures `UndoManager`'s **grouping**, which is AppKit's business and, in a
  /// unit test, is dominated by `groupsByEvent`. The count measures **registrations**, which
  /// is this package's business: one trip through the text view's input path registers one
  /// operation, two trips register two, and a direct text-storage mutation registers none.
  /// That is exactly the distinction REQUIREMENTS.md § Undo is about, so it is the thing to
  /// count.
  ///
  /// Both spellings are overridden because `NSTextView` uses both: the selector form for some
  /// operations and `prepare(withInvocationTarget:)` for others. Counting only one would read
  /// zero for the wrong reason, which every test here would then report as a pass.
  @MainActor
  final class CountingUndoManager: UndoManager {

    /// Undo operations registered since the last ``resetCount()``.
    private(set) var registrations = 0

    func resetCount() { registrations = 0 }

    override func registerUndo(
      withTarget target: Any, selector: Selector, object anObject: Any?
    ) {
      registrations += 1
      super.registerUndo(withTarget: target, selector: selector, object: anObject)
    }

    override func prepare(withInvocationTarget target: Any) -> Any {
      registrations += 1
      return super.prepare(withInvocationTarget: target)
    }
  }

  /// Closes the current event's undo group, the way a running application does between
  /// keystrokes.
  ///
  /// `UndoManager` defaults to `groupsByEvent = true` and closes its top-level group from a
  /// **run-loop observer**. A unit test that never spins the run loop therefore accumulates
  /// every mutation into one group, and every "one undo returns to the prior state" assertion
  /// passes vacuously — the first draft of this suite did exactly that and was green for a
  /// reason unrelated to any implementation.
  ///
  /// Spinning the loop is the only way to get the real behaviour. Closing the group by hand
  /// with `endUndoGrouping()` is not an alternative: `NSUndoManager` opens its event group
  /// once per run-loop iteration, so the next registration in the same iteration finds no
  /// group open and Foundation raises `NSInternalInconsistencyException`. Neither is
  /// `groupsByEvent = false`, which fails the same way.
  @MainActor
  func settleEventGroup() {
    _ = CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.02, false)
  }

  /// An editor whose undo manager is observable, seeded and with the seeding already dropped
  /// off the undo stack.
  ///
  /// A type rather than a tuple because `NSTextView.delegate` is **weak**: the provider has
  /// to be owned by something that outlives the call, and a returned tuple of
  /// `(editor, manager)` would let it deallocate before the first assertion — at which point
  /// the text view silently falls back to having no undo manager and every undo assertion
  /// below becomes untrue for a reason unrelated to this package.
  @MainActor
  final class UndoableEditor {

    let editor: EscriboTextView
    let provider: TestUndoManagerProvider

    var undo: CountingUndoManager { provider.manager }
    var text: String { editor.currentText }

    /// How many undo operations have been registered since the fixture was seeded.
    var registrations: Int { provider.manager.registrations }

    /// Builds the editor, seeds it with `document`, and clears both the undo stack and the
    /// registration count so the seeding is not part of what a later assertion measures.
    init(seededWith document: String, language: Language = .markdown) {
      let provider = TestUndoManagerProvider()
      let editor = EscriboTextView(
        language: language,
        theme: language == .fountain ? .fountainLight : .markdownLight)
      editor.textView.delegate = provider

      self.editor = editor
      self.provider = provider

      editor.applyExternalText(document)
      settleEventGroup()
      provider.manager.removeAllActions()
      provider.manager.resetCount()
    }
  }

#endif

// MARK: - Continuation through the input path

/// REQUIREMENTS.md § Editing behavior, driven through the real Return key on both platforms.
///
/// The rule itself is asserted in `MarkdownListContinuationTests`, where no framework can
/// stand in for it. **This suite proves something different and equally necessary**: that the
/// rule is reached by the Return key at all, that the document ends up in the state the rule
/// describes, and — on macOS — that the whole rewrite is one undo action.
///
/// Platform-neutral where it can be. Undo assertions are macOS-only, because
/// REQUIREMENTS.md Known limitations §1 defers iOS undo deliberately: "`UITextView` gives far
/// less control over undo grouping than `NSUndoManager` does… macOS ships undo; iOS ships
/// without it and gets it as a follow-up." The *text* assertions run on both, which is what
/// Architecture §10 requires — the affordance is not a macOS feature.
@MainActor
@Suite("List continuation through the text view's own input path")
struct EditorInputPathTests {

  @Test("Return at the end of an unordered item continues the list")
  func unorderedItemContinues() {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    editor.applyExternalText("- item")
    placeCaretAtEnd(editor)

    pressReturn(editor)

    #expect(editor.currentText == "- item\n- ")
    #expect(editor.textView.selectedRange == NSRange(location: 9, length: 0))
  }

  @Test("Return at the end of `3. item` inserts `4. `")
  func orderedItemIncrements() {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    editor.applyExternalText("1. one\n2. two\n3. item")
    placeCaretAtEnd(editor)

    pressReturn(editor)

    #expect(editor.currentText == "1. one\n2. two\n3. item\n4. ")
  }

  @Test("Return at the end of a task item continues it unchecked, even from a ticked one")
  func taskItemContinuesUnchecked() {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    editor.applyExternalText("- [x] done")
    placeCaretAtEnd(editor)

    pressReturn(editor)

    #expect(editor.currentText == "- [x] done\n- [ ] ")
  }

  @Test("Return at the end of an indented item continues at the same indent")
  func nestedItemContinuesAtTheSameIndent() {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    editor.applyExternalText("- outer\n  - inner")
    placeCaretAtEnd(editor)

    pressReturn(editor)

    #expect(editor.currentText == "- outer\n  - inner\n  - ")
  }

  @Test("Return on `- ` yields an empty line with no marker, and inserts no second line")
  func markerOnlyItemLosesItsMarker() {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    editor.applyExternalText("- item\n- ")
    placeCaretAtEnd(editor)

    pressReturn(editor)

    // The marker is gone and the line count is unchanged: two lines before, two after.
    #expect(editor.currentText == "- item\n")
    #expect(editor.currentText.components(separatedBy: "\n").count == 2)
    #expect(editor.textView.selectedRange == NSRange(location: 7, length: 0))
  }

  @Test("Return on an indented marker-only item leaves a line carrying no indent")
  func markerOnlyNestedItemClearsTheWholeLine() {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    editor.applyExternalText("- outer\n  - ")
    placeCaretAtEnd(editor)

    pressReturn(editor)

    #expect(editor.currentText == "- outer\n")
  }

  // MARK: - Where the affordance must not fire

  /// DL-108. Sortie 20 put YAML frontmatter in `LineState` specifically so this could be
  /// known rather than guessed: a `- ` line inside frontmatter is a YAML sequence entry, and
  /// continuing it as a Markdown list would corrupt the document's metadata.
  @Test("A `- ` line inside YAML frontmatter is YAML, and Return leaves it alone")
  func frontmatterIsNotAList() {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    editor.applyExternalText("---\ntags:\n  - alpha")
    placeCaretAtEnd(editor)

    pressReturn(editor)

    // A plain newline and nothing else. A continuation would have produced `  - `.
    #expect(editor.currentText == "---\ntags:\n  - alpha\n")
  }

  @Test("A bullet inside a fenced code block is code, and Return leaves it alone")
  func fencedCodeIsNotAList() {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    editor.applyExternalText("```\n- not a list")
    placeCaretAtEnd(editor)

    pressReturn(editor)

    #expect(editor.currentText == "```\n- not a list\n")
  }

  @Test("Fountain's Return is a different affordance, so Markdown's must not fire there")
  func fountainDocumentsGetAPlainNewline() {
    let editor = EscriboTextView(language: .fountain, theme: .fountainLight)
    editor.applyExternalText("- not markdown")
    placeCaretAtEnd(editor)

    pressReturn(editor)

    #expect(editor.currentText == "- not markdown\n")
  }

  @Test("A Return in the middle of an item is ambiguous and splits it with a plain newline")
  func midItemReturnSplitsTheLine() {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    editor.applyExternalText("- item")
    placeCaret(editor, at: 4)

    pressReturn(editor)

    #expect(editor.currentText == "- it\nem")
  }

  @Test("Return with a selection replaces it with a plain newline, marker or not")
  func returnWithASelectionIsAPlainNewline() {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    editor.applyExternalText("- item")
    editor.textView.selectedRange = NSRange(location: 2, length: 4)

    pressReturn(editor)

    #expect(editor.currentText == "- \n")
  }

  @Test("A paragraph is not a list, and Return in one inserts one newline and nothing else")
  func paragraphGetsAPlainNewline() {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    editor.applyExternalText("just a sentence")
    placeCaretAtEnd(editor)

    pressReturn(editor)

    #expect(editor.currentText == "just a sentence\n")
  }

  // MARK: - Repeated use

  @Test("Continuing three times builds a list whose markers are all correct")
  func repeatedReturnsBuildAList() {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    editor.applyExternalText("1. one")
    placeCaretAtEnd(editor)

    pressReturn(editor)
    typeText(editor, "two")
    placeCaretAtEnd(editor)
    pressReturn(editor)
    typeText(editor, "three")
    placeCaretAtEnd(editor)

    #expect(editor.currentText == "1. one\n2. two\n3. three")
  }

  /// The affordance runs off the scanner's classification, and the scanner's classification
  /// comes from a scan of a document that has to already be in its post-edit state. A
  /// continuation whose own insertion left the scanner describing the *previous* document
  /// would continue correctly once and wrongly forever after.
  @Test("A continuation is rescanned as an ordinary edit, so the next one is still right")
  func continuationRescansLikeAnyOtherEdit() {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    editor.applyExternalText("- alpha")
    placeCaretAtEnd(editor)
    pressReturn(editor)

    // The scanner has already classified the line the continuation just created — the
    // coordinator answers for an offset that did not exist before the keystroke, which it
    // could only do from a scan of the post-edit document.
    let caret = editor.textView.selectedRange.location
    #expect(editor.coordinator.elementKind(atUTF16Offset: caret - 2) != nil)

    // And Return on it — now marker-only — clears it, which only works if the scan is
    // current.
    pressReturn(editor)
    #expect(editor.currentText == "- alpha\n")
  }
}

#if os(macOS)

  // MARK: - One undo action

  /// REQUIREMENTS.md § Undo: "**Every affordance-driven rewrite is one undo action, together
  /// with the keystroke that triggered it.** Pressing Return once and Cmd-Z once must return
  /// to exactly the prior state — not to a half-inserted list marker."
  ///
  /// ## Two measurements, because one of them is a lie on its own
  ///
  /// `NSTextView` does a great deal of undo work by itself, so an assertion here can very
  /// easily measure AppKit rather than this package. **This suite was written wrong first and
  /// the wrong version passed**, which is worth recording:
  ///
  /// The first draft asserted `canUndo == false` after one `undo()`. It was green — and it
  /// was green with the *whole test* replaced by anything at all, because `UndoManager`
  /// defaults to `groupsByEvent = true` and closes its top-level group from a run-loop
  /// observer. A unit test never spins the run loop, so **every** mutation from
  /// `removeAllActions()` onward landed in one group: typing four characters and then
  /// pressing Return undid, in one step, all of it. That assertion could not have failed for
  /// any implementation.
  ///
  /// So this suite does two things instead, and needs both:
  ///
  /// 1. ``settleEventGroup()`` spins the run loop between keystrokes, which is what a real
  ///    application does and what makes each keystroke its own undo group. Only then does
  ///    "one Cmd-Z returns to exactly the prior state" mean anything. (`groupsByEvent = false`
  ///    is not an alternative: `NSTextView` then registers undo with no group open and
  ///    Foundation raises `NSInternalInconsistencyException`.)
  /// 2. ``CountingUndoManager`` counts undo **registrations**, so the claim is not "the text
  ///    came back" but "the text came back *and* the keystroke registered exactly one undo
  ///    operation". A rewrite applied as two trips through the input path registers two and
  ///    fails here while still restoring correctly after two Cmd-Zs.
  ///
  /// Between them they catch both ways of getting REQUIREMENTS.md § Undo wrong: the
  /// storage-mutation-after-the-fact shape registers **zero** for the marker and leaves a
  /// half-undone document (caught by the byte-for-byte assertion), and the
  /// two-transactions shape registers two (caught by the count).
  @MainActor
  @Suite("Coalesced undo — a rewrite and its keystroke are one action")
  struct CoalescedUndoTests {

    @Test("Return then one undo on `- item` restores exactly the prior document")
    func continuationIsOneUndoAction() {
      let fixture = UndoableEditor(seededWith: "- item")
      let before = fixture.text
      placeCaretAtEnd(fixture.editor)

      pressReturn(fixture.editor)
      settleEventGroup()

      #expect(fixture.text == "- item\n- ")
      // The newline and the marker together are ONE registered undo operation, not two.
      #expect(fixture.registrations == 1)

      #expect(fixture.undo.canUndo == true)
      fixture.undo.undo()

      // Byte for byte, not merely equal-looking. A half-undone continuation would leave
      // "- item- " here.
      #expect(Array(fixture.text.utf8) == Array(before.utf8))

      // And nothing is left on the stack, which is only a meaningful claim because
      // `settleEventGroup` closed the keystroke's group.
      #expect(fixture.undo.canUndo == false)
    }

    @Test("Return then one undo on an ordered item restores exactly the prior document")
    func orderedContinuationIsOneUndoAction() {
      let fixture = UndoableEditor(seededWith: "1. one\n2. two\n3. item")
      let before = fixture.text
      placeCaretAtEnd(fixture.editor)

      pressReturn(fixture.editor)
      settleEventGroup()
      #expect(fixture.text == "1. one\n2. two\n3. item\n4. ")
      #expect(fixture.registrations == 1)

      fixture.undo.undo()
      #expect(Array(fixture.text.utf8) == Array(before.utf8))
      #expect(fixture.undo.canUndo == false)
    }

    @Test("Return then one undo on a task item restores exactly the prior document")
    func taskContinuationIsOneUndoAction() {
      let fixture = UndoableEditor(seededWith: "- [x] done")
      let before = fixture.text
      placeCaretAtEnd(fixture.editor)

      pressReturn(fixture.editor)
      settleEventGroup()
      #expect(fixture.text == "- [x] done\n- [ ] ")
      #expect(fixture.registrations == 1)

      fixture.undo.undo()
      #expect(Array(fixture.text.utf8) == Array(before.utf8))
      #expect(fixture.undo.canUndo == false)
    }

    /// The marker-only case is a *deletion*, which is the other half of the affordance and
    /// registers a different undo operation.
    @Test("Deleting a marker-only item's marker is also one undo action")
    func markerDeletionIsOneUndoAction() {
      let fixture = UndoableEditor(seededWith: "- item\n- ")
      let before = fixture.text
      placeCaretAtEnd(fixture.editor)

      pressReturn(fixture.editor)
      settleEventGroup()
      #expect(fixture.text == "- item\n")
      #expect(fixture.registrations == 1)

      fixture.undo.undo()
      #expect(Array(fixture.text.utf8) == Array(before.utf8))
      #expect(fixture.undo.canUndo == false)
    }

    /// Undo has to survive being used, or "one action" is true only for the first keystroke.
    @Test("Building a list with Return unwinds one keystroke at a time")
    func continuationsUnwindOneAtATime() {
      let fixture = UndoableEditor(seededWith: "- one")
      placeCaretAtEnd(fixture.editor)

      pressReturn(fixture.editor)
      settleEventGroup()
      typeText(fixture.editor, "two")
      settleEventGroup()
      pressReturn(fixture.editor)
      settleEventGroup()
      typeText(fixture.editor, "three")
      settleEventGroup()

      #expect(fixture.text == "- one\n- two\n- three")
      // Four keystrokes, four undo registrations. Not three, and not one.
      #expect(fixture.registrations == 4)

      fixture.undo.undo()
      #expect(fixture.text == "- one\n- two\n- ")
      fixture.undo.undo()
      #expect(fixture.text == "- one\n- two")
      fixture.undo.undo()
      #expect(fixture.text == "- one\n- ")
      fixture.undo.undo()
      #expect(fixture.text == "- one")
      #expect(fixture.undo.canUndo == false)
    }

    /// A continuation must not absorb the typing that preceded it — that is the difference
    /// between "returns to exactly the prior state" and "unwinds the sentence as well".
    @Test("A continuation does not absorb the typing that came before it")
    func continuationDoesNotSwallowPrecedingTyping() {
      let fixture = UndoableEditor(seededWith: "- ")
      placeCaretAtEnd(fixture.editor)
      typeText(fixture.editor, "item")
      settleEventGroup()
      #expect(fixture.text == "- item")

      pressReturn(fixture.editor)
      settleEventGroup()
      #expect(fixture.text == "- item\n- ")

      fixture.undo.undo()
      #expect(fixture.text == "- item")
    }

    // MARK: - Rule 4 of § External text replacement

    /// REQUIREMENTS.md § External text replacement rule 4: "Register as a single undo
    /// action."
    ///
    /// **This shipped unmet until Sortie 25.** The reset used to mutate `NSTextStorage`
    /// directly inside an `NSUndoManager` grouping, which bounds a reset at *at most* one
    /// action but registers **zero** on macOS, because `NSTextView` records undo from
    /// `shouldChangeText(in:replacementString:)`/`didChangeText()` and a direct storage
    /// mutation reaches neither. An external reset was simply not undoable.
    ///
    /// The count below is the assertion that was false before: it read zero.
    @Test("Rule 4: an external reset is undoable at all, and is exactly one undo action")
    func externalResetIsOneUndoAction() {
      let fixture = UndoableEditor(seededWith: "first document\n")
      let before = fixture.text

      #expect(fixture.registrations == 0)
      #expect(fixture.editor.applyExternalText("a completely different document\n") == true)
      settleEventGroup()

      // Was 0 before Sortie 25: a direct storage mutation registered nothing at all.
      #expect(fixture.registrations == 1)
      #expect(fixture.undo.canUndo == true)

      fixture.undo.undo()
      #expect(Array(fixture.text.utf8) == Array(before.utf8))
      #expect(fixture.undo.canUndo == false)
    }

    @Test("Rule 4 holds when the reset empties the document")
    func externalResetToEmptyIsOneUndoAction() {
      let fixture = UndoableEditor(seededWith: "# Heading\n\nBody.\n")
      let before = fixture.text

      #expect(fixture.editor.applyExternalText("") == true)
      settleEventGroup()
      #expect(fixture.text == "")
      #expect(fixture.registrations == 1)

      fixture.undo.undo()
      #expect(fixture.text == before)
      #expect(fixture.undo.canUndo == false)
    }

    @Test("Rule 1 still fires first: an equal string registers no undo action at all")
    func equalExternalTextRegistersNoUndoAction() {
      let fixture = UndoableEditor(seededWith: "unchanged\n")
      #expect(fixture.editor.applyExternalText("unchanged\n") == false)
      settleEventGroup()
      #expect(fixture.registrations == 0)
      #expect(fixture.undo.canUndo == false)
    }
  }

  // MARK: - Paste

  /// REQUIREMENTS.md § Undo: "Paste inserts verbatim with no transformation, as a single undo
  /// action, and rescans as an ordinary edit."
  ///
  /// ## Nothing here implements paste, and that is the finding
  ///
  /// `NSTextView` already pastes through its own input path, so paste is one undo action
  /// without this package doing anything. What this package *does* own is the **verbatim**
  /// half, and it owns it through one line: `isRichText = false` in ``EscriboTextView``'s
  /// construction (DL-65).
  ///
  /// The assertions are split accordingly and labelled honestly. The undo assertion
  /// characterises AppKit — it would pass with every line of Sortie 25 deleted, and it is
  /// here because the exit criteria ask for it and because the input path this sortie added
  /// is now the thing that must not break it. The verbatim assertions are this package's, and
  /// ``pasteboardCarryingBothFlavours(plain:)`` is what gives them teeth: with
  /// `isRichText = true` the RTF flavour wins and they go red.
  @MainActor
  @Suite("Paste — verbatim, and one undo action")
  struct PasteIsVerbatimTests {

    /// Ten lines, with Markdown that a rich-text paste would style differently.
    static let block = (1...10).map { "\($0). line \($0) with **bold**" }.joined(separator: "\n")

    /// A pasteboard carrying the same insertion in **two** flavours: RTF with a 36-point bold
    /// font, and plain text.
    ///
    /// This is what makes `isRichText = false` falsifiable. With it, `NSTextView` advertises
    /// only `.string` among its readable types and takes the plain flavour; without it, it
    /// prefers RTF and the document ends up carrying the pasteboard's fonts and its text. A
    /// test against a string-only pasteboard could not tell the two configurations apart.
    static func pasteboardCarryingBothFlavours(plain: String) -> NSPasteboard {
      let pasteboard = NSPasteboard.withUniqueName()
      let rich = NSAttributedString(
        string: "RICH TEXT WON",
        attributes: [.font: NSFont.boldSystemFont(ofSize: 36)])
      let rtf = rich.rtf(
        from: NSRange(location: 0, length: rich.length), documentAttributes: [:])

      pasteboard.declareTypes([.rtf, .string], owner: nil)
      if let rtf { pasteboard.setData(rtf, forType: .rtf) }
      pasteboard.setString(plain, forType: .string)
      return pasteboard
    }

    @Test("A ten-line paste inserts verbatim — the plain flavour wins over the RTF one")
    func pasteIsVerbatim() {
      let fixture = UndoableEditor(seededWith: "")
      let pasteboard = Self.pasteboardCarryingBothFlavours(plain: Self.block)

      #expect(fixture.editor.textView.readSelection(from: pasteboard) == true)

      #expect(Array(fixture.text.utf8) == Array(Self.block.utf8))
      #expect(fixture.text.contains("RICH TEXT WON") == false)
    }

    @Test("A paste carries none of the pasteboard's typography into the document")
    func pasteCarriesNoForeignAttributes() throws {
      let fixture = UndoableEditor(seededWith: "")
      let pasteboard = Self.pasteboardCarryingBothFlavours(plain: Self.block)
      fixture.editor.textView.readSelection(from: pasteboard)

      // Every font in the document is the styler's, at the theme's size — never the 36-point
      // face the RTF flavour carried.
      let storage = fixture.editor.documentStorage
      var offset = 0
      while offset < storage.length {
        var effective = NSRange()
        let attributes = storage.attributes(at: offset, effectiveRange: &effective)
        let font = try #require(attributes[.font] as? PlatformFont)
        #expect(font.pointSize < 36)
        offset = max(offset + 1, NSMaxRange(effective))
      }
    }

    @Test("A ten-line paste is a single undo action")
    func pasteIsOneUndoAction() {
      // ⚠️ Largely AppKit's behaviour, not this package's. `readSelection(from:)` goes through
      // `NSTextView`'s own input path, so the count below would read 1 with every line of
      // Sortie 25 deleted. Asserted because the exit criteria ask for it, and because the
      // input path this sortie added is now what must not break it.
      let fixture = UndoableEditor(seededWith: "before\n")
      let before = fixture.text
      placeCaretAtEnd(fixture.editor)

      let pasteboard = Self.pasteboardCarryingBothFlavours(plain: Self.block)
      fixture.editor.textView.readSelection(from: pasteboard)
      settleEventGroup()

      #expect(fixture.text == before + Self.block)
      #expect(fixture.registrations == 1)

      fixture.undo.undo()
      #expect(Array(fixture.text.utf8) == Array(before.utf8))
      #expect(fixture.undo.canUndo == false)
    }

    @Test("A pasted block rescans as an ordinary edit — the whole insertion is styled")
    func pasteRescansLikeAnOrdinaryEdit() throws {
      let fixture = UndoableEditor(seededWith: "")
      let pasteboard = Self.pasteboardCarryingBothFlavours(plain: Self.block)
      fixture.editor.textView.readSelection(from: pasteboard)

      let applied = try #require(fixture.editor.coordinator.lastAppliedRange)
      #expect(applied.lowerBound == 0)
      #expect(applied.upperBound == fixture.editor.documentStorage.length)

      // Non-vacuous: the pasted text was classified, which only a scan of it could do.
      #expect(fixture.editor.coordinator.elementKind(atUTF16Offset: 0) == .orderedListItem)
      let tenth = (fixture.text as NSString).range(of: "10. line 10")
      #expect(tenth.location != NSNotFound)
      #expect(fixture.editor.coordinator.elementKind(atUTF16Offset: tenth.location) != nil)
    }

    /// Paste must not be transformed by the continuation affordance. A pasted block full of
    /// list markers and newlines goes in exactly as it is — the affordance is bound to the
    /// Return *key*, not to newlines in general.
    @Test("Pasting list markers inserts them verbatim, with no continuation applied")
    func pasteOfListMarkersIsNotContinued() {
      let fixture = UndoableEditor(seededWith: "")
      let block = "- one\n- two\n- \n1. three\n"
      let pasteboard = Self.pasteboardCarryingBothFlavours(plain: block)
      fixture.editor.textView.readSelection(from: pasteboard)

      #expect(fixture.text == block)
    }
  }

#endif

// MARK: - Proving the input path was taken

/// Counts the text view's own "the text changed" delegate callback.
///
/// ## Why this is the witness that the input path was used
///
/// `textDidChange` (AppKit) and `textViewDidChange` (UIKit) are posted by the **text view**,
/// from `didChangeText()` and from `replace(_:withText:)` respectively. A direct
/// `NSTextStorage.replaceCharacters` behind the text view's back does not reach either — the
/// document changes and the view delegate never hears about it.
///
/// That makes this the one assertion available on iOS that distinguishes the real input path
/// from ``EscriboTextView/performInputPathEdit(_:)``'s fallback branch. Undo is deferred on
/// iOS (Known limitations §1), so the registration count that proves it on macOS is not
/// available there — but the *shape* is what Architecture §10 requires to be identical, and
/// this measures the shape on both platforms with the same assertion.
@MainActor
final class TextChangeCounter: NSObject {

  private(set) var count = 0

  func reset() { count = 0 }
}

#if os(macOS)
  extension TextChangeCounter: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) { count += 1 }
  }
#elseif os(iOS)
  extension TextChangeCounter: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) { count += 1 }
  }
#endif

@MainActor
@Suite("Every rewrite goes through the text view, not around it")
struct InputPathIsActuallyUsedTests {

  @Test("A list continuation reaches the text view's own change notification")
  func continuationNotifiesTheTextView() {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    let counter = TextChangeCounter()
    editor.textView.delegate = counter

    editor.applyExternalText("- item")
    placeCaretAtEnd(editor)
    counter.reset()

    pressReturn(editor)

    #expect(editor.currentText == "- item\n- ")
    // Exactly one: one keystroke, one transaction. A storage mutation behind the view's back
    // would read zero; two transactions would read two.
    #expect(counter.count == 1)
  }

  @Test("Deleting a marker-only item's marker reaches it too")
  func markerDeletionNotifiesTheTextView() {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    let counter = TextChangeCounter()
    editor.textView.delegate = counter

    editor.applyExternalText("- item\n- ")
    placeCaretAtEnd(editor)
    counter.reset()

    pressReturn(editor)

    #expect(editor.currentText == "- item\n")
    #expect(counter.count == 1)
  }

  /// Rule 4's other half. The reset is one transaction through the same path, on both
  /// platforms, which is what makes the iOS undo limitation a scheduling fact rather than a
  /// structural one.
  @Test("An external reset reaches the text view's own change notification")
  func externalResetNotifiesTheTextView() {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    let counter = TextChangeCounter()
    editor.textView.delegate = counter

    editor.applyExternalText("first")
    counter.reset()

    #expect(editor.applyExternalText("second") == true)
    #expect(counter.count == 1)

    // Rule 1: an equal string is not a rewrite and must not notify at all.
    counter.reset()
    #expect(editor.applyExternalText("second") == false)
    #expect(counter.count == 0)
  }

  @Test("A declined Return is the text view's own newline, not a second transaction")
  func declinedReturnIsOneOrdinaryInsertion() {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    let counter = TextChangeCounter()
    editor.textView.delegate = counter

    editor.applyExternalText("just a sentence")
    placeCaretAtEnd(editor)
    counter.reset()

    pressReturn(editor)

    #expect(editor.currentText == "just a sentence\n")
    #expect(counter.count == 1)
  }
}
