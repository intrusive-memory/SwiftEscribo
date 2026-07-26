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

    override func insertNewline(_ sender: Any?) {
      if returnKeyHandler?() == true { return }
      super.insertNewline(sender)
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

    override func insertText(_ text: String) {
      if text == "\n", returnKeyHandler?() == true { return }
      super.insertText(text)
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
    guard case .rewrite(let range, let replacement) = listContinuationOutcome() else {
      return false
    }
    return performInputPathEdit(InputPathEdit(replacing: range, with: replacement))
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
