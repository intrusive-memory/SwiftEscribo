#if os(iOS)
  import EscriboCore
  import Foundation
  import UIKit.UIGestureRecognizerSubclass

  /// The iOS input behaviour of block embeds (REQUIREMENTS.md § 1.3): the caret never enters
  /// an embed, a tap selects the whole block and activates it, typing and paste over it are
  /// ignored, Backspace and forward-delete select it first and then remove it as one undo
  /// step, `⌥↩` is *Edit as Text*, and undo puts it back selected.
  ///
  /// ## Where UIKit's input arrives
  ///
  /// UIKit has no single selection or edit funnel, so ``EscriboNativeTextView`` overrides
  /// each public entry point and asks this object. The live check (IOS_LIVE_CHECK.md) is
  /// what names them:
  ///
  /// | Input | Entry point |
  /// |---|---|
  /// | Tap, caret drag, handle-drag release, hardware arrows, programmatic selection | the `selectedTextRange` and `selectedRange` setters |
  /// | Typing, Return, Tab, dictation | `insertText(_:)` |
  /// | Marked text (IME) | `setMarkedText(_:selectedRange:)` |
  /// | Autocorrect, system replacements | `replace(_:withText:)` |
  /// | Paste | `paste(_:)`, `pasteAndMatchStyle(_:)`, `paste(itemProviders:)`, gated in `canPerformAction(_:withSender:)` |
  /// | Backspace; forward-delete with a selection | `deleteBackward()` |
  /// | Hardware forward-delete | `pressesBegan(_:with:)`, on key-down (a `UIKeyCommand` for it never fires) |
  /// | `⌥↩` | a `UIKeyCommand` for `"\r"` with `.alternate` |
  ///
  /// The selection-handle drag *preview* is drawn by UIKit without calling any public API
  /// and can show a range ending inside the row while the finger is down. It never changes
  /// the selection, and the release commits through the setter, which widens it to the
  /// whole embed. That cosmetic gap stays (IOS_LIVE_CHECK.md, "Range-handle drag").
  ///
  /// ## Telling a tap from a programmatic selection
  ///
  /// A tap on the row and a host setting the selection both arrive as one call to the
  /// `selectedTextRange` setter with a caret inside the block, so the setter alone cannot
  /// tell them apart. An ``EmbedTapRecognizer`` on the text view does. It receives only
  /// touches that land on a drawn embed row (its delegate's `shouldReceive` hit-tests the
  /// row rectangles, so a touch anywhere else never reaches it and UIKit's own gestures are
  /// untouched), and it recognises simultaneously with everything:
  ///
  /// - **Touch down** on a row records that block as ``touchedBlock``. While it is set, the
  ///   setter uses ``EmbedSelection/constrainClick(proposed:embeds:)``: UIKit's tap proposal
  ///   (a caret inside the block) becomes the **whole block**, never an edge caret.
  /// - **Touch up** clears it on the next turn of the main run loop, after UIKit's own tap handling
  ///   in the same event has committed its selection — whichever recognizer's action runs
  ///   first.
  /// - **Tap recognised** selects the whole block and calls `onEmbedActivate` once.
  ///
  /// A programmatic selection happens with no touch on a row, so it goes through
  /// ``EmbedSelection/constrain(proposed:previous:embeds:isFindMatch:)`` (step over in the
  /// direction of travel) and never activates. The recognizer also sees iPad pointer clicks
  /// (`UITapGestureRecognizer` accepts indirect-pointer touches); live pointer input could
  /// not be driven in the simulator (IOS_LIVE_CHECK.md row e).
  ///
  /// ## Typing over an embed
  ///
  /// ``EmbedSelection/allowsEdit(range:replacementLength:embeds:)`` vetoes an edit inside
  /// or partly over an embed, and allows a range covering whole embeds, which deletion
  /// needs. Text replacing such a range — typing, marked text, autocorrect or paste with
  /// the block (or a wider range holding it) selected — is ignored here too. Only deleting
  /// it (Backspace, forward-delete) removes an embed.
  ///
  /// Edits the package makes itself through
  /// ``EscriboTextView/performInputPathEdit(_:)`` (affordances, the host's external text)
  /// are not the writer's input and are not checked.
  ///
  /// ## Typing at an embed's start edge
  ///
  /// The caret may sit at either edge of an embed, and ``EmbedSelection/allowsEdit(range:replacementLength:embeds:)``
  /// allows an insertion there. At the **start** edge, though, an inserted character would
  /// join the embed's first line (`x[[note…`), the scanner would no longer see the same
  /// block, and the embed would silently become text. So an edit that ends at an embed's
  /// start must leave a line break (or the document's start) directly before it:
  ///
  /// - Return there inserts a plain newline — the block moves down a line, intact. The
  ///   Return and Tab affordances are skipped there, since they rewrite the caret's line,
  ///   which is the embed's first line.
  /// - Text that ends with a line break forms its own lines above the block and is
  ///   inserted the same way.
  /// - Any other text there (typing, marked text) is ignored, like typing into the embed.
  ///   Paste there is always ignored: its text is never read before the paste, so it is
  ///   judged as text that does not end with a line break.
  /// - Backspace there is ignored when it would pull the embed's first line up onto a
  ///   non-empty line; deleting a blank line above it is allowed.
  ///
  /// The end edge needs no rule: a block's range includes its final terminator, so the
  /// end edge is already the start of the next line.
  @MainActor
  final class IOSEmbedInput: NSObject {

    /// What ``EscriboNativeTextView/insertText(_:)`` should do with typed text.
    enum TypingVerdict: Equatable {
      /// No embed involved: the usual path, affordances included.
      case normal
      /// Allowed at an embed's start edge: insert as typed, without the affordances.
      case plain
      /// Ignored.
      case veto
    }

    private weak var editor: EscriboTextView?

    /// The embedded block a touch went down on, until that touch's selection commits are
    /// over. Non-`nil` means "the next selection proposals come from a tap on a row".
    private(set) var touchedBlock: EmbeddedBlock?

    /// Bumped on every touch down, so a stale clear from an earlier touch is ignored.
    private var touchGeneration = 0

    /// The recognizer installed by ``EscriboTextView/installEmbedInput()``.
    private(set) weak var tapRecognizer: EmbedTapRecognizer?

    init(editor: EscriboTextView) {
      self.editor = editor
      super.init()
    }

    // MARK: - The embeds

    /// Every drawn embed as a UTF-16 range (final terminator included), in document order.
    /// Empty with no provider, in `.source`, or when the provider answered no block.
    var embeds: [NSRange] {
      guard let editor else { return [] }
      let length = editor.documentStorage.length
      return editor.coordinator.embeddedBlocks.compactMap {
        let range = $0.block.range
        guard range.upperBound <= length else { return nil }
        return NSRange(location: range.lowerBound, length: range.count)
      }
    }

    /// The embed that is exactly the current selection, or `nil`.
    func selectedEmbed() -> EmbeddedBlock? {
      guard let editor else { return nil }
      let selection = editor.textView.selectedRange
      guard selection.length > 0,
        let hit = editor.coordinator.embeddedBlock(containingUTF16Offset: selection.location),
        hit.block.range.lowerBound == selection.location,
        hit.block.range.count == selection.length
      else { return nil }
      return hit
    }

    // MARK: - Selection

    /// The selection the text view actually takes for a proposed one.
    func constrainSelection(_ proposed: NSRange, current: NSRange) -> NSRange {
      let embeds = self.embeds
      guard !embeds.isEmpty else { return proposed }
      if touchedBlock != nil {
        return EmbedSelection.constrainClick(proposed: proposed, embeds: embeds)
      }
      return EmbedSelection.constrain(proposed: proposed, previous: current, embeds: embeds)
    }

    // MARK: - Taps

    /// The embedded block whose drawn row contains `point` (text-view coordinates), or `nil`.
    func embeddedBlock(atRowPoint point: CGPoint) -> EmbeddedBlock? {
      guard let editor, let layout = editor.embedLayout, !embeds.isEmpty,
        let offset = editor.coordinator.utf16Offset?(point)
      else { return nil }
      // A point on the row resolves inside the block (its first line keeps a real line
      // fragment); near the row's bottom it can resolve to the next line's start.
      for candidate in [offset, offset - 1] {
        guard let hit = layout.embeddedBlock(containingUTF16Offset: candidate),
          let rect = layout.rowRect(for: hit), rect.contains(point)
        else { continue }
        return hit
      }
      return nil
    }

    /// A touch went down at `point`.
    func touchBegan(at point: CGPoint) {
      touchGeneration += 1
      touchedBlock = embeddedBlock(atRowPoint: point)
    }

    /// The touch ended or was cancelled. Cleared on the next turn of the main run loop, so UIKit's
    /// own handling of the same touch-up still sees ``touchedBlock``.
    func touchFinished() {
      let generation = touchGeneration
      RunLoop.main.perform(inModes: [.common]) { [weak self] in
        MainActor.assumeIsolated {
          guard let self, self.touchGeneration == generation else { return }
          self.touchedBlock = nil
        }
      }
    }

    /// A tap was recognised at `point`: select the whole block and activate it once.
    func tapRecognized(at point: CGPoint) {
      guard let editor, let hit = embeddedBlock(atRowPoint: point) ?? touchedBlock else { return }
      editor.textView.selectedRange = NSRange(
        location: hit.block.range.lowerBound, length: hit.block.range.count)
      editor.coordinator.embeds.onActivate(hit.block)
    }

    /// The tap recognizer's action.
    @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
      guard recognizer.state == .ended, let view = recognizer.view else { return }
      tapRecognized(at: recognizer.location(in: view))
    }

    // MARK: - Edits

    /// The verdict on typing `text` over `range`. See "Typing at an embed's start edge".
    func typingVerdict(range: NSRange, text: String) -> TypingVerdict {
      let embeds = self.embeds
      guard !embeds.isEmpty, let editor else { return .normal }
      guard
        EmbedSelection.allowsEdit(
          range: range, replacementLength: text.utf16.count, embeds: embeds)
      else { return .veto }
      // `allowsEdit` lets a range that covers whole embeds through, which deleting one needs.
      // Text over such a range would replace the embed: "typing with it selected is ignored".
      if !text.isEmpty,
        embeds.contains(where: { NSIntersectionRange($0, range).length > 0 })
      {
        return .veto
      }
      let end = NSMaxRange(range)
      guard range.length > 0 || !text.isEmpty, embeds.contains(where: { $0.location == end })
      else { return .normal }
      // The character that will sit directly before the embed after the edit.
      let before: UInt16?
      if let last = text.utf16.last {
        before = last
      } else if range.location > 0 {
        before = (editor.documentStorage.string as NSString).character(at: range.location - 1)
      } else {
        before = nil
      }
      guard before == nil || before == 0x0A else { return .veto }
      return .plain
    }

    /// Whether an edit replacing `range` with `text` passes the embed edit rule.
    func allowsInput(range: NSRange, text: String) -> Bool {
      typingVerdict(range: range, text: text) != .veto
    }

    // MARK: - Delete keys

    /// Whether forward-delete would act on an embed now (select it, or delete it).
    func forwardDeleteActs() -> Bool {
      guard let editor else { return false }
      let embeds = self.embeds
      guard !embeds.isEmpty else { return false }
      return EmbedSelection.deleteAction(
        selection: editor.textView.selectedRange, forward: true, embeds: embeds,
        in: editor.documentStorage.string as NSString) != .passThrough
    }

    /// Backspace (`forward == false`) or forward-delete through
    /// ``EmbedSelection/deleteAction(selection:forward:embeds:in:)``.
    ///
    /// - Returns: `true` when the key press was handled here (an embed was selected or
    ///   deleted, or a partial delete was vetoed); `false` lets the text view's default
    ///   deletion run.
    func handleDeleteKey(forward: Bool) -> Bool {
      guard let editor else { return false }
      let embeds = self.embeds
      guard !embeds.isEmpty else { return false }
      let textView = editor.textView
      let selection = textView.selectedRange
      let text = editor.documentStorage.string as NSString
      switch EmbedSelection.deleteAction(
        selection: selection, forward: forward, embeds: embeds, in: text)
      {
      case .select(let embed):
        textView.selectedRange = embed
        return true
      case .delete(let removal):
        deleteEmbed(removing: removal, reselecting: selection)
        return true
      case .passThrough:
        let target: NSRange
        if selection.length > 0 {
          target = selection
        } else if forward {
          guard selection.location < text.length else { return false }
          target = text.rangeOfComposedCharacterSequence(at: selection.location)
        } else {
          guard selection.location > 0 else { return false }
          target = text.rangeOfComposedCharacterSequence(at: selection.location - 1)
        }
        return !allowsInput(range: target, text: "")
      }
    }

    /// Removes `removal` (an embed plus its adjacent blank line) as **one** undo step, and
    /// arranges for undo to select `embed` again once its text is back.
    ///
    /// The group holds two actions. UIKit's own, registered by `replace(_:withText:)` (the
    /// input path), restores the text; the editor then re-asks the provider for the
    /// restored block like any other rescanned block, so the embed comes back. The
    /// reselection is registered **first** so that undo, which runs a group's actions in
    /// reverse, runs it **after** the text is restored.
    private func deleteEmbed(removing removal: NSRange, reselecting embed: NSRange) {
      guard let editor else { return }
      let undo = editor.textView.undoManager
      undo?.beginUndoGrouping()
      registerReselection(of: embed)
      editor.performInputPathEdit(InputPathEdit(replacing: removal, with: ""))
      undo?.endUndoGrouping()
      editor.textView.selectedRange = NSRange(location: removal.location, length: 0)
    }

    /// Registers "select `embed`" as an undo action. Undoing it registers its own
    /// counterpart, which on redo re-registers this, so undo / redo / undo keeps
    /// reselecting the block.
    private func registerReselection(of embed: NSRange) {
      editor?.textView.undoManager?.registerUndo(withTarget: self) { input in
        MainActor.assumeIsolated { input.reselect(embed) }
      }
    }

    /// Undo of an embed deletion: select the restored block.
    ///
    /// UIKit selects the text an undo restored (the block plus its blank line) when its
    /// undo finishes, after every action of the group — and after the undo manager's
    /// did-undo notification — and it does so without calling the public selection setters.
    /// So the block is selected now and again on the next turn of the main run loop, once
    /// UIKit is done.
    private func reselect(_ embed: NSRange) {
      guard let textView = editor?.textView else { return }
      select(embed)
      RunLoop.main.perform(inModes: [.common]) { [weak self] in
        MainActor.assumeIsolated { self?.select(embed) }
      }
      // Runs during undo, so this lands on the redo stack. Redo runs it before UIKit's
      // redo of the deletion, and it puts the reselection back for the next undo.
      textView.undoManager?.registerUndo(withTarget: self) { input in
        MainActor.assumeIsolated { input.registerReselection(of: embed) }
      }
    }

    /// Selects `embed` if it is still exactly a drawn embed.
    private func select(_ embed: NSRange) {
      guard let editor, embeds.contains(embed) else { return }
      editor.textView.selectedRange = embed
    }

    // MARK: - ⌥↩

    /// `⌥↩` with an embed selected: calls `onEmbedAction` with ``EscriboEmbed/Action/editAsTextID``.
    func editSelectedEmbedAsText() {
      guard let editor, let hit = selectedEmbed() else { return }
      editor.coordinator.embeds.onAction(hit.block, EscriboEmbed.Action.editAsTextID)
    }
  }

  // MARK: - Gesture delegate

  extension IOSEmbedInput: UIGestureRecognizerDelegate {

    /// Only touches on a drawn embed row, and never a touch meant for a control drawn over
    /// the text (a well button).
    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch
    ) -> Bool {
      guard !(touch.view is UIControl), let view = gestureRecognizer.view else { return false }
      return embeddedBlock(atRowPoint: touch.location(in: view)) != nil
    }

    /// Never competes with UIKit's own text gestures.
    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      true
    }
  }

  // MARK: - The tap recognizer

  /// A single-tap recognizer that also reports touch down and touch up, which is how
  /// ``IOSEmbedInput`` knows a selection proposal comes from a tap on a row.
  final class EmbedTapRecognizer: UITapGestureRecognizer {

    /// Called with the touch's location in the view on touch down.
    var onTouchDown: ((CGPoint) -> Void)?

    /// Called when the touch ends or is cancelled.
    var onTouchUp: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
      super.touchesBegan(touches, with: event)
      if let touch = touches.first, let view { onTouchDown?(touch.location(in: view)) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
      super.touchesEnded(touches, with: event)
      onTouchUp?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
      super.touchesCancelled(touches, with: event)
      onTouchUp?()
    }
  }

  // MARK: - Installing on the editor

  extension EscriboTextView {

    /// Wires the embed input rules into the text view. Called once, from the initializer.
    ///
    /// Inert without embeds: every rule answers "pass through" while the coordinator's embed
    /// cache is empty, and the tap recognizer receives no touch that is not on a row.
    func installEmbedInput() {
      let input = IOSEmbedInput(editor: self)
      textView.embedInput = input
      let recognizer = EmbedTapRecognizer(
        target: input, action: #selector(IOSEmbedInput.handleTap(_:)))
      recognizer.cancelsTouchesInView = false
      recognizer.delaysTouchesBegan = false
      recognizer.delaysTouchesEnded = false
      recognizer.delegate = input
      recognizer.onTouchDown = { [weak input] in input?.touchBegan(at: $0) }
      recognizer.onTouchUp = { [weak input] in input?.touchFinished() }
      textView.addGestureRecognizer(recognizer)
      input.attach(recognizer)
    }
  }

  extension IOSEmbedInput {
    fileprivate func attach(_ recognizer: EmbedTapRecognizer) {
      tapRecognizer = recognizer
    }
  }
#endif
