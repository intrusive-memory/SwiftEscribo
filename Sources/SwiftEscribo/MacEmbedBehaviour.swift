#if os(macOS)
  import AppKit
  import EscriboCore
  import Foundation

  /// The macOS behaviour of an embed row (REQUIREMENTS.md § 1.3): the caret never enters
  /// it, a selection that touches it covers all of it, Delete removes it (with one adjacent
  /// blank line) as one undo step, typing over it is ignored, a click selects it and
  /// activates it, and Option-Return asks the host for *Edit as Text*.
  ///
  /// Every rule is ``EmbedSelection``'s; this file only feeds it the drawn embeds and
  /// applies its answers through the handlers on ``EscriboNativeTextView``. Copy needs no
  /// code: the text storage holds the block's source, so `NSTextView`'s own copy writes it.
  extension EscriboTextView {

    /// Wires the text view's embed handlers. Called once, from the initializer.
    ///
    /// Each handler reads the coordinator's embed cache when it runs, so with no provider
    /// (an empty cache) each declines at once and the text view behaves as before.
    func installEmbedBehaviour() {
      textView.embedSelectionConstraint = { [weak self] proposed, current, isFindMatch in
        self?.constrainEmbedSelection(proposed, current: current, isFindMatch: isFindMatch)
          ?? proposed
      }
      textView.embedEditFilter = { [weak self] range, replacement in
        self?.allowsEmbedInput(in: range, replacement: replacement) ?? true
      }
      textView.embedDeleteHandler = { [weak self] forward in
        self?.handleEmbedDelete(forward: forward) ?? false
      }
      textView.embedClickHandler = { [weak self] point in
        self?.handleEmbedClick(at: point) ?? false
      }
      textView.embedEditAsTextHandler = { [weak self] in
        self?.handleEmbedEditAsText() ?? false
      }
    }

    // MARK: - The drawn embeds

    /// The ranges of the embedded blocks that fit the current storage, in document order.
    ///
    /// A cache entry past the end (one edit behind) is left out, as the layout controller
    /// leaves it out of drawing.
    var drawnEmbedRanges: [NSRange] {
      let blocks = coordinator.embeddedBlocks
      guard !blocks.isEmpty else { return [] }
      let length = documentStorage.length
      return blocks.compactMap { entry in
        let range = entry.block.range
        guard range.upperBound <= length else { return nil }
        return NSRange(location: range.lowerBound, length: range.count)
      }
    }

    /// The drawn embedded block whose range is exactly `range`, or `nil`.
    private func embeddedBlock(exactly range: NSRange) -> EmbeddedBlock? {
      guard range.length > 0,
        let hit = coordinator.embeddedBlock(containingUTF16Offset: range.location),
        hit.block.range.lowerBound == range.location, hit.block.range.count == range.length,
        hit.block.range.upperBound <= documentStorage.length
      else { return nil }
      return hit
    }

    // MARK: - Selection

    /// The selection rule: every proposed range through ``EmbedSelection/constrain(proposed:previous:embeds:isFindMatch:)``.
    func constrainEmbedSelection(
      _ proposed: [NSValue], current: NSRange, isFindMatch: Bool
    ) -> [NSValue] {
      let embeds = drawnEmbedRanges
      guard !embeds.isEmpty else { return proposed }
      let length = documentStorage.length
      return proposed.map { value in
        let constrained = EmbedSelection.constrain(
          proposed: value.rangeValue, previous: current, embeds: embeds,
          isFindMatch: isFindMatch)
        guard NSMaxRange(constrained) <= length else { return value }
        return NSValue(range: constrained)
      }
    }

    // MARK: - Edits

    /// The edit rule for the writer's input: ``EmbedSelection/allowsInput(range:replacement:embeds:in:)``.
    ///
    /// Exempt, because they are not the writer's input and must never be refused:
    /// - an external reset (``applyExternalText(_:)`` runs inside
    ///   ``EditorCoordinator/withEmbedEditRefreshDeferred(_:)``), which replaces the whole
    ///   document and so contains every embed;
    /// - undo and redo, which put back exactly what an allowed edit took away;
    /// - attribute-only changes (`replacement == nil`).
    func allowsEmbedInput(in range: NSRange, replacement: String?) -> Bool {
      guard let replacement, !coordinator.embeds.isEditRefreshDeferred else { return true }
      if let undoManager = textView.undoManager, undoManager.isUndoing || undoManager.isRedoing {
        return true
      }
      let embeds = drawnEmbedRanges
      guard !embeds.isEmpty else { return true }
      return EmbedSelection.allowsInput(
        range: range, replacement: replacement, embeds: embeds, in: documentStorage.mutableString)
    }

    /// Backspace / forward-delete: ``EmbedSelection/deleteAction(selection:forward:embeds:in:)``.
    ///
    /// The first press next to an embed selects it; the press with it selected removes its
    /// ``EmbedSelection/deletionRange(for:in:)`` through the input path, as one undo step.
    /// That step also restores the selection: undoing it puts the block back **selected**,
    /// and redo removes it again.
    func handleEmbedDelete(forward: Bool) -> Bool {
      let embeds = drawnEmbedRanges
      guard !embeds.isEmpty else { return false }
      let selection = textView.selectedRange()
      switch EmbedSelection.deleteAction(
        selection: selection, forward: forward, embeds: embeds, in: documentStorage.mutableString)
      {
      case .passThrough:
        return false
      case .select(let embed):
        textView.setSelectedRange(embed)
        return true
      case .delete(let removal):
        // Registered before the text change, so undo runs it after the text is back.
        registerEmbedReselection(selection)
        if performInputPathEdit(InputPathEdit(replacing: removal, with: "")) {
          textView.setSelectedRange(NSRange(location: removal.location, length: 0))
        }
        return true
      }
    }

    /// Registers an undo operation that selects `block`, and re-registers itself on each
    /// undo and redo so the pairing survives any number of round trips.
    ///
    /// It shares the deletion's undo group. Undo performs a group's operations in reverse
    /// order of registration, so registering this first makes it run **after** `NSTextView`
    /// has put the text back (and the scan has re-asked the provider for the restored
    /// block), which is when the block can be selected whole.
    private func registerEmbedReselection(_ block: NSRange) {
      guard let undoManager = textView.undoManager else { return }
      undoManager.registerUndo(withTarget: textView) { [weak self] textView in
        MainActor.assumeIsolated {
          if NSMaxRange(block) <= (textView.textStorage?.length ?? 0) {
            textView.setSelectedRange(block)
          }
          self?.registerEmbedReselection(block)
        }
      }
    }

    // MARK: - Click

    /// A click on an embed row selects the whole block and calls `onEmbedActivate:` once.
    ///
    /// Hit-tested against the row's own rectangle (``EmbedLayoutController/rowRect(for:)``),
    /// so a click beside the row, or anywhere with no embed drawn, returns `false` and
    /// AppKit handles it as usual. Programmatic selection never comes here, so it never
    /// activates.
    func handleEmbedClick(at point: CGPoint) -> Bool {
      guard let controller = embedLayout, !coordinator.embeddedBlocks.isEmpty else { return false }
      let index = textView.characterIndexForInsertion(at: point)
      // An insertion index can land on either side of a row: at the block's start, inside
      // it, or at its end (the next line's start), so the offset before it is tried too.
      let candidates = [index, index - 1].compactMap {
        $0 >= 0 ? controller.embeddedBlock(containingUTF16Offset: $0) : nil
      }
      guard
        let hit = candidates.first(where: { controller.rowRect(for: $0)?.contains(point) == true })
      else { return false }

      textView.window?.makeFirstResponder(textView)
      let caret = NSRange(location: hit.block.range.lowerBound, length: 0)
      textView.setSelectedRange(
        EmbedSelection.constrainClick(proposed: caret, embeds: drawnEmbedRanges))
      coordinator.embeds.onActivate(hit.block)
      return true
    }

    // MARK: - Option-Return

    /// Option-Return with exactly one embed selected sends *Edit as Text*
    /// (``EscriboEmbed/Action/editAsTextID``) to `onEmbedAction:`.
    func handleEmbedEditAsText() -> Bool {
      guard let hit = embeddedBlock(exactly: textView.selectedRange()) else { return false }
      coordinator.embeds.onAction(hit.block, EscriboEmbed.Action.editAsTextID)
      return true
    }
  }
#endif
