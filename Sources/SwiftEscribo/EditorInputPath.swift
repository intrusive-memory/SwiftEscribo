import EscriboCore
import Foundation

#if os(macOS)
  import AppKit
#elseif os(iOS)
  import UIKit
#endif

/// One rewrite, expressed the way the text system takes it.
///
/// A range and a replacement, and nothing else — no selection, no undo name, no "insert
/// then delete". REQUIREMENTS.md § Undo is why: "the rewrite must go through the text
/// view's own input path, in the same transaction as the user's input… This is a design
/// constraint, not an implementation detail — it determines the shape of the coordinator."
/// One trip through the input path is one undo action, so an affordance that cannot state
/// itself as one replacement cannot be one undo action either, and the type refuses to let
/// one try.
struct InputPathEdit: Equatable {

  /// The range to replace, in document UTF-16 code units.
  let range: NSRange

  /// What to put there.
  let replacement: String

  /// Builds an edit from the scanner's coordinate system.
  init(replacing range: Range<Int>, with replacement: String) {
    self.range = NSRange(location: range.lowerBound, length: range.count)
    self.replacement = replacement
  }

  /// Builds an edit from the text system's coordinate system.
  init(replacing range: NSRange, with replacement: String) {
    self.range = range
    self.replacement = replacement
  }
}

/// The caret's line as an affordance sees it: text, position, and the scanner's verdict on it
/// and on the line above.
///
/// Assembled once per keystroke by ``EscriboTextView/caretLine()`` and consumed by the pure
/// rules. It carries no text view and no storage, so a rule that takes one of these cannot
/// reach back into the editor and cannot be satisfied by a framework standing in for it —
/// the property `MarkdownListContinuationTests`' header explains at length.
struct CaretLineContext: Equatable {

  /// The caret's line, **without its terminator**.
  let line: String

  /// That line's first UTF-16 offset in the document.
  let lineStart: Int

  /// The caret's UTF-16 offset in the document.
  let caret: Int

  /// The scanner's classification of the caret's line.
  let element: ElementKind

  /// The scanner's classification of the line above, or `nil` at the top of the document.
  let previousElement: ElementKind?
}

// MARK: - The text view that owns the Return key

#if os(macOS)

  /// The `NSTextView` this package ships, and the reason there is a subclass at all.
  ///
  /// ## Why a subclass rather than a delegate method
  ///
  /// AppKit offers `textView(_:doCommandBy:)` on `NSTextViewDelegate`, which would reach
  /// Return without subclassing. It was rejected for one structural reason: the delegate is
  /// `EscriboEditorBridge`, which exists **only** when the editor is driven from SwiftUI. An
  /// affordance installed there would be absent from every ``EscriboTextView`` built
  /// directly — including every one in the test suite — so the shipped behaviour and the
  /// tested behaviour would be two different things. Overriding here makes the affordance a
  /// property of the text view itself, reached by exactly the call the Return key makes.
  ///
  /// ## `insertNewline(_:)` is the input path, not a shortcut around it
  ///
  /// Return arrives as `doCommandBySelector(insertNewline:)`. Overriding it and **not**
  /// calling `super` means the whole keystroke — the newline and the list marker together —
  /// is one call to ``EscriboTextView/performInputPathEdit(_:)``, one
  /// `shouldChangeText(in:replacementString:)`/`didChangeText()` pair, and therefore one
  /// undo action. Letting `super` insert the newline first and adding the marker afterwards
  /// is the shape REQUIREMENTS.md § Undo forbids by name.
  ///
  /// Sortie 26 adds Fountain's Tab and Return here the same way: another handler property,
  /// another override that returns without calling `super` when it handled the key. Nothing
  /// about this class is list-specific.
  final class EscriboNativeTextView: NSTextView {

    /// Called on every Return. Returns `true` when it has already performed the edit, in
    /// which case `super` must not run.
    ///
    /// `@MainActor` on the closure type rather than on its uses: an `NSTextView` is
    /// main-actor-isolated, so the handler is only ever invoked there, and saying so in the
    /// type lets the handler call main-actor API without a hop or an assumption.
    var returnKeyHandler: (@MainActor () -> Bool)?

    /// Called on every Tab. Returns `true` when it has already done whatever the keystroke
    /// meant — which for one row of REQUIREMENTS.md § Fountain Tab and Return is *nothing*
    /// (``FountainAffordanceOutcome/consume``), so a `true` here does not imply the document
    /// changed. It implies only that `super` must not also insert a tab.
    ///
    /// Tab arrives as `doCommandBySelector(insertTab:)`, the same route Return takes, so
    /// Sortie 26 hangs here rather than inventing a second mechanism.
    var tabKeyHandler: (@MainActor () -> Bool)?

    /// Whether this view claims the caret the moment it has a window to claim it in.
    ///
    /// Set from ``EscriboTextView``'s construction path, never from a host — the public
    /// answer is ``EscriboEditor``'s `focusOnAppear:`, and this is where that answer lands.
    ///
    /// It lives on the text view for the same structural reason `returnKeyHandler` does: the
    /// behaviour must be a property of the object this package ships, not of the SwiftUI
    /// bridge, so the shipped behaviour and the tested behaviour are the same behaviour.
    ///
    /// And it is why no host needs to go looking for this view. A `NSViewRepresentable`'s
    /// view is unreachable from SwiftUI's focus system, so the alternative a consumer is
    /// left with is a sibling probe that walks the window's content view for the first
    /// `NSTextView` it can find. This package **owns** the view it is focusing and has no
    /// reason to search for it: the object that would be found is `self`.
    var focusesOnAppear = false

    /// One-shot latch for ``focusesOnAppear``.
    ///
    /// `viewDidMoveToWindow()` fires on every attachment, not only the first — SwiftUI moves
    /// its hosted views between windows, and a re-attachment is not an "appear". Without this
    /// latch, a window the user has already clicked into somewhere else would have its
    /// selection yanked back to the editor.
    private var hasTakenInitialFocus = false

    /// Claims first responder, once, when the view is installed in a window.
    ///
    /// This is the whole mechanism. `viewDidMoveToWindow()` is AppKit telling the view that
    /// it now has a window — which is precisely the "the representable's view is installed"
    /// moment, arriving at the one object that already knows both halves of the question.
    /// Nothing is deferred to a later turn of the run loop and nothing is searched for,
    /// because by the time this runs the view exists, the window exists, and `self` is the
    /// view to focus.
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      guard focusesOnAppear, !hasTakenInitialFocus, let window else { return }
      hasTakenInitialFocus = true
      window.makeFirstResponder(self)
    }

    override func insertNewline(_ sender: Any?) {
      if returnKeyHandler?() == true { return }
      super.insertNewline(sender)
    }

    override func insertTab(_ sender: Any?) {
      if tabKeyHandler?() == true { return }
      super.insertTab(sender)
    }

    // SPIKE — block-embed hooks (Sources/SwiftEscribo/Spike/MacBlockEmbed.swift). Never merged.

    /// SPIKE: rewrites every proposed selection (arrows, shift-arrows, clicks, drags) given the
    /// current one. `nil` leaves selection behaviour untouched.
    var spikeSelectionFilter: (@MainActor (_ proposed: [NSValue], _ current: [NSValue]) -> [NSValue])?

    /// SPIKE: vetoes an edit (`false`) before `super` sees it. Typing, paste and deletion all
    /// reach `shouldChangeText(in:replacementString:)`.
    var spikeEditFilter: (@MainActor (_ range: NSRange, _ replacement: String?) -> Bool)?

    /// SPIKE: called on Delete / forward-delete; returns `true` when it performed the edit.
    var spikeDeleteHandler: (@MainActor () -> Bool)?

    override func setSelectedRanges(
      _ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool
    ) {
      let filtered = spikeSelectionFilter?(ranges, selectedRanges) ?? ranges
      super.setSelectedRanges(filtered, affinity: affinity, stillSelecting: stillSelecting)
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
      if spikeEditFilter?(affectedCharRange, replacementString) == false { return false }
      return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }

    override func deleteBackward(_ sender: Any?) {
      if spikeDeleteHandler?() == true { return }
      super.deleteBackward(sender)
    }

    override func deleteForward(_ sender: Any?) {
      if spikeDeleteHandler?() == true { return }
      super.deleteForward(sender)
    }

    /// SPIKE: extra accessibility children (one element per collapsed embed, row 9).
    var spikeAccessibilityChildren: (@MainActor () -> [Any])?

    override func accessibilityChildren() -> [Any]? {
      let base = super.accessibilityChildren()
      guard let extra = spikeAccessibilityChildren?(), !extra.isEmpty else { return base }
      return (base ?? []) + extra
    }

    // MARK: The paragraph well's inputs (REQUIREMENTS-1.1.0 § 5.2)

    /// The well drawn into this view, which these overrides feed. Weak: the editor owns it.
    ///
    /// Overrides here rather than a delegate for the reason the Return key gives above — the
    /// pointer, the keyboard, and a drag reach this object whether or not SwiftUI built it.
    weak var wellOverlay: WellOverlay?

    /// The tracking area that delivers pointer moves across the whole visible text view,
    /// which is what makes a block's vertical band span the lane *and* the text.
    private var wellTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
      super.updateTrackingAreas()
      if let wellTrackingArea { removeTrackingArea(wellTrackingArea) }
      let area = NSTrackingArea(
        rect: .zero,
        options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
        owner: self, userInfo: nil)
      addTrackingArea(area)
      wellTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
      super.mouseMoved(with: event)
      wellOverlay?.pointerMoved(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
      super.mouseExited(with: event)
      guard event.trackingArea === wellTrackingArea else { return }
      wellOverlay?.pointerMoved(to: nil)
    }

    /// Typing hides the well, as the system hides the cursor; the next pointer move brings
    /// it back.
    override func keyDown(with event: NSEvent) {
      wellOverlay?.typed()
      super.keyDown(with: event)
    }

    /// `NSTextView` tracks a drag-selection inside `mouseDown(with:)` and returns on mouse-up,
    /// so the call to `super` *is* the drag, and bracketing it is exact.
    override func mouseDown(with event: NSEvent) {
      wellOverlay?.dragBegan()
      super.mouseDown(with: event)
      wellOverlay?.dragEnded()
    }

    /// A resize reflows the text, so every placed well may be beside the wrong line.
    override func setFrameSize(_ newSize: NSSize) {
      super.setFrameSize(newSize)
      wellOverlay?.layoutDidChange()
    }
  }

#elseif os(iOS)

  /// The `UITextView` this package ships — the UIKit half of ``EscriboNativeTextView``, with
  /// the identical purpose and the identical handler property.
  ///
  /// ## `insertText(_:)` is UIKit's spelling of the same event
  ///
  /// UIKit has no `insertNewline(_:)`. Return on a `UITextView` arrives through `UIKeyInput`
  /// as `insertText("\n")`, from the hardware key and from the on-screen keyboard alike, so
  /// that is where the affordance hangs. Returning without calling `super` means the newline
  /// and the marker are one call to ``EscriboTextView/performInputPathEdit(_:)`` — the same
  /// structure as macOS, which is what REQUIREMENTS.md Architecture §10 means by both
  /// Representables shipping together rather than one being a later port.
  ///
  /// Undo granularity here is whatever UIKit provides (Known limitations §1). What this file
  /// guarantees on iOS is the *shape*: one transaction, through the text view's own input
  /// path, never a storage mutation behind the text view's back.
  final class EscriboNativeTextView: UITextView {

    /// Called on every Return. Returns `true` when it has already performed the edit.
    var returnKeyHandler: (@MainActor () -> Bool)?

    /// Called on every Tab — the UIKit half of ``EscriboNativeTextView/tabKeyHandler`` on
    /// macOS, with the identical contract.
    ///
    /// UIKit has no `insertTab(_:)` any more than it has `insertNewline(_:)`. A hardware Tab
    /// in a `UITextView` arrives through `UIKeyInput` as `insertText("\t")`, so both
    /// affordances hang off the same override and are told apart by the string, which is the
    /// only thing UIKit gives to tell them apart by.
    var tabKeyHandler: (@MainActor () -> Bool)?

    override func insertText(_ text: String) {
      wellOverlay?.typed()
      // SPIKE: typing (and Return/Tab) with an embed in the selection changes nothing.
      if spikeEditFilter?(selectedRange, text) == false { return }
      if text == "\n", returnKeyHandler?() == true { return }
      if text == "\t", tabKeyHandler?() == true { return }
      super.insertText(text)
    }

    // MARK: The paragraph well's inputs (REQUIREMENTS-1.1.0 § 5.2)

    /// The well drawn into this view, which these overrides feed. Weak: the editor owns it.
    /// The iPad pointer arrives through a hover recognizer the editor installs, and the
    /// caret through the view delegate.
    weak var wellOverlay: WellOverlay?

    /// The width the well was last placed for. `layoutSubviews` runs on every scroll, and a
    /// scroll moves the well with its superview for free; only a width change reflows text.
    private var wellLayoutWidth: CGFloat = 0

    override func deleteBackward() {
      wellOverlay?.typed()
      // SPIKE: with an embed exactly selected the handler deletes it whole (row 5).
      if spikeDeleteHandler?() == true { return }
      if spikeEditFilter?(spikeDeletionRange(), "") == false { return }
      super.deleteBackward()
    }

    // SPIKE — block-embed hooks (Sources/SwiftEscribo/Spike/IOSBlockEmbed.swift). Never merged.

    /// SPIKE: rewrites every proposed selection given the current one. UIKit has no
    /// `setSelectedRanges(_:affinity:stillSelecting:)`; the public funnels are the
    /// `selectedTextRange` and `selectedRange` setters, both overridden below. `nil` leaves
    /// selection behaviour untouched.
    var spikeSelectionFilter: (@MainActor (_ proposed: NSRange, _ current: NSRange) -> NSRange)?

    /// SPIKE: vetoes an edit (`false`). UIKit has no `shouldChangeText(in:replacementString:)`
    /// on the view (only the delegate's, which belongs to the SwiftUI bridge), so the input
    /// entry points consult it: `insertText`, `setMarkedText`, `replace(_:withText:)`,
    /// `deleteBackward`.
    var spikeEditFilter: (@MainActor (_ range: NSRange, _ replacement: String?) -> Bool)?

    /// SPIKE: called on Backspace; returns `true` when it performed the edit.
    var spikeDeleteHandler: (@MainActor () -> Bool)?

    /// SPIKE: how many times the `selectedTextRange` setter ran (tests use it to see which
    /// input routes reach the filter).
    private(set) var spikeSelectedTextRangeSets = 0

    /// What a plain Backspace would remove: the selection, or the character before the caret.
    private func spikeDeletionRange() -> NSRange {
      let sel = selectedRange
      if sel.length > 0 || sel.location == 0 { return sel }
      return (textStorage.string as NSString).rangeOfComposedCharacterSequence(at: sel.location - 1)
    }

    private func spikeNSRange(_ range: UITextRange) -> NSRange {
      let start = offset(from: beginningOfDocument, to: range.start)
      return NSRange(location: start, length: offset(from: range.start, to: range.end))
    }

    override var selectedTextRange: UITextRange? {
      get { super.selectedTextRange }
      set {
        spikeSelectedTextRangeSets += 1
        guard let filter = spikeSelectionFilter, let newValue else {
          super.selectedTextRange = newValue
          return
        }
        let proposed = spikeNSRange(newValue)
        let constrained = filter(proposed, selectedRange)
        guard constrained != proposed,
          let start = position(from: beginningOfDocument, offset: constrained.location),
          let end = position(from: start, offset: constrained.length),
          let range = textRange(from: start, to: end)
        else {
          super.selectedTextRange = newValue
          return
        }
        super.selectedTextRange = range
      }
    }

    override var selectedRange: NSRange {
      get { super.selectedRange }
      set { super.selectedRange = spikeSelectionFilter?(newValue, super.selectedRange) ?? newValue }
    }

    override func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
      let target = markedTextRange.map(spikeNSRange) ?? self.selectedRange
      if spikeEditFilter?(target, markedText ?? "") == false { return }
      super.setMarkedText(markedText, selectedRange: selectedRange)
    }

    override func replace(_ range: UITextRange, withText text: String) {
      if spikeEditFilter?(spikeNSRange(range), text) == false { return }
      super.replace(range, withText: text)
    }

    /// SPIKE: extra accessibility elements (one per collapsed embed, row 9).
    var spikeAccessibilityElements: (@MainActor () -> [Any])?

    override var accessibilityElements: [Any]? {
      get {
        let base = super.accessibilityElements
        guard let extra = spikeAccessibilityElements?(), !extra.isEmpty else { return base }
        return (base ?? []) + extra
      }
      set { super.accessibilityElements = newValue }
    }

    /// SPIKE: the informal `UIAccessibilityContainer` index API, which is what VoiceOver walks.
    /// Without the accessibility runtime loaded (a test host) UIKit's default reports 0
    /// elements even when `accessibilityElements` returns some, so answer it explicitly.
    override func accessibilityElementCount() -> Int {
      guard spikeAccessibilityElements != nil else { return super.accessibilityElementCount() }
      return accessibilityElements?.count ?? 0
    }

    override func accessibilityElement(at index: Int) -> Any? {
      guard spikeAccessibilityElements != nil else { return super.accessibilityElement(at: index) }
      guard let elements = accessibilityElements, elements.indices.contains(index) else { return nil }
      return elements[index]
    }

    override func index(ofAccessibilityElement element: Any) -> Int {
      guard spikeAccessibilityElements != nil else {
        return super.index(ofAccessibilityElement: element)
      }
      return accessibilityElements?.firstIndex { ($0 as AnyObject) === (element as AnyObject) }
        ?? NSNotFound
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      guard bounds.width != wellLayoutWidth else { return }
      wellLayoutWidth = bounds.width
      wellOverlay?.layoutDidChange()
    }
  }

#endif

// MARK: - The input path

extension EscriboTextView {

  /// Performs `edit` through the text view's **own input path**, as one undo action.
  ///
  /// This is the single seam REQUIREMENTS.md § Undo requires, and the only place in this
  /// package that changes a document's characters. Everything that rewrites text goes
  /// through it: list continuation, external replacement (§ External text replacement rule
  /// 4), and whatever Sortie 26 adds for Fountain.
  ///
  /// ## macOS
  ///
  /// `shouldChangeText(in:replacementString:)` → mutate → `didChangeText()`. This is not a
  /// convention, it is where `NSTextView` registers its undo: the first call records an undo
  /// operation restoring the old contents of `range`, and the second closes the change and
  /// notifies. A direct `NSTextStorage.replaceCharacters` skips both and therefore registers
  /// **no undo at all** — which is exactly the defect this method exists to close, and the
  /// reason `applyExternalText` was not undoable on macOS before it existed.
  ///
  /// `breakUndoCoalescing()` on both sides makes "one action" mean one action. `NSTextView`
  /// merges consecutive typing into a single undo group; without the breaks, an affordance
  /// rewrite would be absorbed into whatever the writer typed before it and Cmd-Z would
  /// unwind more than the keystroke that triggered it. Bracketing it means Cmd-Z returns to
  /// exactly the prior state — the wording REQUIREMENTS.md uses.
  ///
  /// ## iOS
  ///
  /// `replace(_:withText:)` from `UITextInput` is UIKit's input path, and it is what the
  /// keyboard itself calls. It registers undo in UIKit's own manager, notifies the delegate,
  /// and places the caret after the replacement. Positions are derived from
  /// `beginningOfDocument` with UTF-16 offsets, which is the same coordinate system every
  /// range in this package uses (Architecture §4).
  ///
  /// If UIKit declines to vend a `UITextRange` for the offsets — it can, for a view detached
  /// from a text-input session — the edit still has to happen, so it falls back to a direct
  /// storage mutation. That fallback is *correct in content and weaker in undo*, which is
  /// the tradeoff Known limitations §1 already accepts on this platform. It is deliberately
  /// not the primary path and it is deliberately not mirrored on macOS.
  ///
  /// - Returns: `true` if the document was changed. `false` means the text system refused
  ///   the change — an uneditable view, or a delegate that vetoed it — and the caller must
  ///   treat the keystroke as unhandled rather than retrying behind the text view's back.
  @discardableResult
  func performInputPathEdit(_ edit: InputPathEdit) -> Bool {
    let storage = documentStorage
    guard edit.range.location >= 0, edit.range.length >= 0,
      edit.range.location + edit.range.length <= storage.length
    else { return false }

    #if os(macOS)
      textView.breakUndoCoalescing()
      guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement)
      else { return false }

      // Architecture §8: `replaceCharacters` inside an editing transaction, never
      // `setAttributedString`.
      storage.beginEditing()
      storage.replaceCharacters(in: edit.range, with: edit.replacement)
      storage.endEditing()

      textView.didChangeText()
      textView.breakUndoCoalescing()
      return true
    #elseif os(iOS)
      if let start = textView.position(
        from: textView.beginningOfDocument,
        offset: edit.range.location),
        let end = textView.position(from: start, offset: edit.range.length),
        let range = textView.textRange(from: start, to: end)
      {
        textView.replace(range, withText: edit.replacement)
        return true
      }

      storage.beginEditing()
      storage.replaceCharacters(in: edit.range, with: edit.replacement)
      storage.endEditing()
      return true
    #else
      return false
    #endif
  }

  // MARK: - The Return key

  /// The Return-key affordance: Markdown list continuation.
  ///
  /// Wired to ``EscriboNativeTextView/returnKeyHandler`` at construction, so it runs for
  /// every Return the writer presses and for no other key.
  ///
  /// - Returns: `true` when it performed a rewrite and the text view must not also insert a
  ///   newline. `false` means "do the boring thing", and the boring thing is `super`'s.
  @discardableResult
  func handleReturnKey() -> Bool {
    if coordinator.language == .fountain { return perform(fountainReturnOutcome()) }

    guard case .rewrite(let range, let replacement) = listContinuationOutcome() else {
      return false
    }
    return performInputPathEdit(InputPathEdit(replacing: range, with: replacement))
  }

  // MARK: - The Tab key

  /// The Tab-key affordance: Fountain's positional scaffolding (Sortie 26).
  ///
  /// Wired to ``EscriboNativeTextView/tabKeyHandler`` at construction, so it runs for every
  /// Tab the writer presses and for no other key. Markdown has no Tab affordance at all —
  /// REQUIREMENTS.md gives Tab a column only in § Fountain Tab and Return — so in a Markdown
  /// document this declines before it asks the scanner anything.
  ///
  /// - Returns: `true` when the text view must **not** also insert a tab. That covers two
  ///   different situations, which is why this is not spelled "performed a rewrite": a
  ///   rewrite happened, or the row's post-condition already held and the keystroke was
  ///   swallowed (``FountainAffordanceOutcome/consume``).
  @discardableResult
  func handleTabKey() -> Bool {
    perform(fountainTabOutcome())
  }

  /// Applies an outcome, and is the only place the three cases are turned into behaviour.
  ///
  /// ``FountainAffordanceOutcome/consume`` returns `true` **without** touching the document,
  /// which is the whole reason it is a separate case: performing it as an empty edit would
  /// travel the input path, register an undo action, and give the writer a Cmd-Z that appears
  /// to do nothing.
  private func perform(_ outcome: FountainAffordanceOutcome) -> Bool {
    switch outcome {
    case .literal:
      return false
    case .consume:
      return true
    case .rewrite(let range, let replacement):
      return performInputPathEdit(InputPathEdit(replacing: range, with: replacement))
    }
  }

  /// What Tab should do at the current caret.
  ///
  /// Assembles the inputs ``FountainAffordances/tabOutcome(line:lineStart:caret:element:previousElement:)``
  /// needs and does no deciding of its own, exactly as ``listContinuationOutcome()`` does for
  /// Return. Every guard is a *precondition of asking*:
  ///
  /// - **Fountain only.** Markdown's Tab is not an affordance in this package.
  /// - **An empty selection.** Tab with a selection replaces it, and what the writer wants
  ///   from the selected lines' structure is not knowable.
  /// - **A classification for the line.** If the scanner cannot say what the line is, this
  ///   package will not guess.
  ///
  /// The classification of the line *above* comes from the same seam
  /// (``EditorCoordinator/elementKind(atUTF16Offset:)``) rather than from re-reading the text:
  /// "the previous block is dialogue" is a question only the scanner can answer, because
  /// whether `BOB` is a cue or a shouted line of action depends on the lines around it.
  func fountainTabOutcome() -> FountainAffordanceOutcome {
    guard coordinator.language == .fountain else { return .literal }
    guard let caret = caretLine() else { return .literal }

    return FountainAffordances.tabOutcome(
      line: caret.line,
      lineStart: caret.lineStart,
      caret: caret.caret,
      element: caret.element,
      previousElement: caret.previousElement)
  }

  /// What Return should do at the current caret in a Fountain document.
  ///
  /// It is a literal newline in every row, and ``FountainAffordances/returnOutcome(element:)``
  /// is where that is written down and asserted. This function exists so the decision is
  /// reached the same way Tab's is — through the scanner's classification, from the text
  /// view's own key handler — rather than by Fountain simply never being asked.
  func fountainReturnOutcome() -> FountainAffordanceOutcome {
    guard coordinator.language == .fountain else { return .literal }
    guard let caret = caretLine() else { return .literal }
    return FountainAffordances.returnOutcome(element: caret.element)
  }

  /// The caret's line, its classification, and the classification of the line above it.
  ///
  /// `nil` whenever an affordance must decline outright: a non-empty selection, a caret
  /// outside the document, or a line the scanner cannot classify.
  ///
  /// The line is bridged to a `String` here, and only the line. REQUIREMENTS.md § Edits and
  /// text access forbids bridging *the document* per edit — "bridging 120 KB on every
  /// keystroke would exceed the whole budget before scanning began" — and this is one line,
  /// once per keystroke, off the scan path entirely.
  private func caretLine() -> CaretLineContext? {
    let selection = textView.selectedRange
    guard selection.length == 0 else { return nil }

    let text = documentStorage.mutableString
    let caret = selection.location
    guard caret >= 0, caret <= text.length else { return nil }

    // `getLineStart(_:end:contentsEnd:for:)` is the one call that gets `\r\n` right: it
    // reports `contentsEnd` before the terminator and `end` after it, whether that terminator
    // is one code unit or two. REQUIREMENTS.md § Line termination — terminators are never
    // normalized, so nothing here may assume a length.
    var lineStart = 0
    var lineEnd = 0
    var contentsEnd = 0
    text.getLineStart(
      &lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
      for: NSRange(location: caret, length: 0))

    guard let element = coordinator.elementKind(atUTF16Offset: lineStart) else { return nil }

    var previousElement: ElementKind?
    if lineStart > 0 {
      var previousStart = 0
      var previousEnd = 0
      var previousContentsEnd = 0
      text.getLineStart(
        &previousStart, end: &previousEnd, contentsEnd: &previousContentsEnd,
        for: NSRange(location: lineStart - 1, length: 0))
      previousElement = coordinator.elementKind(atUTF16Offset: previousStart)
    }

    return CaretLineContext(
      line: text.substring(
        with: NSRange(location: lineStart, length: max(0, contentsEnd - lineStart))),
      lineStart: lineStart,
      caret: caret,
      element: element,
      previousElement: previousElement)
  }

  /// What Return should do at the current caret.
  ///
  /// Assembles the four inputs ``MarkdownListContinuation/outcome(line:lineStart:caret:element:)``
  /// needs and does no deciding of its own. Every guard here is a *precondition of asking*,
  /// not a rule about lists:
  ///
  /// - **Markdown only.** Fountain's Return is a different affordance with different rules
  ///   (Sortie 26) and any other language has none.
  /// - **An empty selection.** Return with a selection replaces it; what the writer wants
  ///   from a list marker in that case is not knowable, so it is ambiguous.
  /// - **A classification for the line.** If the scanner cannot say what the line is, this
  ///   package will not guess.
  ///
  /// The line is bridged to a `String` here, and only the line. REQUIREMENTS.md § Edits and
  /// text access forbids bridging *the document* per edit — "bridging 120 KB on every
  /// keystroke would exceed the whole budget before scanning began" — and this is one line,
  /// once per Return, off the scan path entirely.
  func listContinuationOutcome() -> ListContinuation {
    guard coordinator.language == .markdown else { return .literalNewline }

    let selection = textView.selectedRange
    guard selection.length == 0 else { return .literalNewline }

    let text = documentStorage.mutableString
    let caret = selection.location
    guard caret >= 0, caret <= text.length else { return .literalNewline }

    // `getLineStart(_:end:contentsEnd:for:)` is the one call that gets `\r\n` right: it
    // reports `contentsEnd` before the terminator and `end` after it, whether that
    // terminator is one code unit or two. REQUIREMENTS.md § Line termination — terminators
    // are never normalized, so nothing here may assume a length.
    var lineStart = 0
    var lineEnd = 0
    var contentsEnd = 0
    text.getLineStart(
      &lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
      for: NSRange(location: caret, length: 0))

    guard let element = coordinator.elementKind(atUTF16Offset: lineStart) else {
      return .literalNewline
    }

    let line = text.substring(
      with: NSRange(location: lineStart, length: max(0, contentsEnd - lineStart)))
    return MarkdownListContinuation.outcome(
      line: line,
      previousLine: lineContents(before: lineStart, in: text),
      lineStart: lineStart,
      caret: caret,
      element: element)
  }

  /// The contents of the line ending at `lineStart`, without its terminator, or `nil` when
  /// `lineStart` is the top of the document.
  ///
  /// Read by exactly one rule — the DL-118 tight-list fallback in
  /// ``MarkdownListContinuation/isListContext(element:previousLine:)`` — and by nothing else.
  ///
  /// `lineStart - 1` lands on the last code unit of the previous line's terminator, which for
  /// `\r\n` is the `\n`. `getLineStart(_:end:contentsEnd:for:)` resolves that to the whole
  /// previous line either way, so no length is assumed for a terminator anywhere here
  /// (REQUIREMENTS.md § Line termination).
  private func lineContents(before lineStart: Int, in text: NSString) -> String? {
    guard lineStart > 0 else { return nil }
    var previousStart = 0
    var previousEnd = 0
    var previousContentsEnd = 0
    text.getLineStart(
      &previousStart, end: &previousEnd, contentsEnd: &previousContentsEnd,
      for: NSRange(location: lineStart - 1, length: 0))
    return text.substring(
      with: NSRange(
        location: previousStart, length: max(0, previousContentsEnd - previousStart)))
  }
}
