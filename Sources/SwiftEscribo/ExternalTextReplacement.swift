import EscriboCore
import Foundation

#if os(macOS)
  import AppKit
#elseif os(iOS)
  import UIKit
#endif

/// The host-facing operations on ``EscriboTextView``: pushing a new document in from
/// outside, and pushing a new configuration in from outside.
///
/// ## Why this is an extension in its own file
///
/// `MacTextView.swift` and `IOSTextView.swift` own *construction* and nothing else, and
/// Sorties 10 and 11 both state that deliberately. The rules below are not construction —
/// they are what happens on every subsequent SwiftUI `update…View(_:context:)` pass, which
/// runs many times per document and never during construction. Keeping them here means the
/// owning classes stay exactly as those sorties shipped them, and it means these rules are
/// callable — and therefore assertable — without a `Representable.Context`, which cannot be
/// constructed in a test.
///
/// ## The two platforms differ in three spellings and nothing else
///
/// `NSTextView.textStorage` is optional and `UITextView.textStorage` is not; the rest —
/// `selectedRange`, `undoManager`, `NSTextStorage` itself — is spelled identically on both.
/// So there is exactly one `#if` below, over one property, and every rule is shared code.
extension EscriboTextView {

  // MARK: - The document

  /// The text storage backing this editor.
  ///
  /// The one place the two SDKs disagree: AppKit vends `textStorage` as an `Optional`
  /// (an `NSTextView` can in principle be detached from a layout stack), UIKit does not.
  /// ``EscriboTextView`` has already established the invariant on both platforms — it
  /// reads this same storage in its own initializer to attach the coordinator — so this
  /// restates it rather than introducing it.
  var documentStorage: NSTextStorage {
    #if os(macOS)
      guard let storage = textView.textStorage else {
        preconditionFailure("an NSTextView always vends a textStorage")
      }
      return storage
    #else
      return textView.textStorage
    #endif
  }

  /// The document as a Swift `String`.
  ///
  /// **The binding boundary, and nothing else.** REQUIREMENTS.md § Edits and text access
  /// forbids bridging the document per edit — "bridging 120 KB on every keystroke would
  /// exceed the whole budget before scanning began" — and the scanner honours that by
  /// reading UTF-16 through ``UTF16TextSource``. This property is the one place a bridge
  /// is unavoidable, because `@Binding var text: String` is a `String` by definition. It is
  /// read once per change notification on the way *out* to SwiftUI, never on the way in and
  /// never on the scan path.
  var currentText: String { documentStorage.string }

  // MARK: - External text replacement

  /// Applies an externally supplied document, following REQUIREMENTS.md
  /// § External text replacement rule for rule.
  ///
  /// "Setting the `@Binding` from outside is a reset, not an edit," and the four numbered
  /// rules are implemented below in the order the requirement states them.
  ///
  /// ### Rule 1 — equal string, do nothing
  ///
  /// > If the incoming string equals the current storage contents, **do nothing.** Not an
  /// > optimization — without this check, SwiftUI's update cycle feeds the editor its own
  /// > output and the view fights the user's typing.
  ///
  /// This is the reason the function returns a `Bool`: a caller that cannot distinguish
  /// "nothing happened" from "the document was replaced" cannot be held to the rule.
  ///
  /// The comparison runs against `mutableString`, the backing `NSMutableString` itself,
  /// for the same reason `NSTextStorageBridge` reads through it: `NSAttributedString.string`
  /// is imported as a `String` and bridging it copies the whole document. `isEqual(to:)`
  /// bridges only the *argument*, which the caller already holds as a `String`. Rule 1
  /// fires on every SwiftUI update pass, so a rule whose own check copied the document
  /// would cost more than the mutation it exists to avoid.
  ///
  /// ### Rule 2 — replace the full range inside an editing transaction, then full-scan
  ///
  /// > Otherwise replace the full range with `replaceCharacters(in:with:)` inside
  /// > `beginEditing()`/`endEditing()` … then full-scan and restyle.
  ///
  /// The whole-string attributed assignment that Architecture §8 forbids appears nowhere in
  /// this package; it "destroys selection, undo stack, and marked text," and
  /// ``EditorTextStorage`` is deliberately too narrow to express it.
  ///
  /// ``EditorCoordinator/restyleEverything()`` is called **explicitly**, and that is not
  /// belt-and-braces. A `replaceCharacters` reaches the coordinator through the
  /// text-storage delegate as an ordinary *incremental* edit — the coordinator has no way
  /// to tell an external reset from a 3 000-character paste, and should not — so without
  /// this call the document would be styled by an incremental scan when the rule demands a
  /// full one. The cost is that a reset scans twice: once incrementally from inside
  /// `endEditing()`, once in full here. That is a real cost, paid once per external reset
  /// and never on a keystroke, and the alternative is a mode flag on the coordinator that
  /// every other edit path would have to reason about.
  ///
  /// ### Rule 3 — clamp the selection
  ///
  /// > Clamp the selection to the new length rather than dropping it to zero.
  ///
  /// Captured *before* the mutation, because the text system will have moved it by the
  /// time the mutation returns. The anchor is clamped to the new length and the extent to
  /// what remains after it, so a caret past the end of a shortened document lands at the
  /// end rather than at the beginning.
  ///
  /// ### Rule 4 — one undo action
  ///
  /// > Register as a single undo action.
  ///
  /// An explicit undo grouping around the whole reset, on the platform's own
  /// `UndoManager`. Deliberately *not* an undo seam: REQUIREMENTS.md Known limitations §1
  /// accepts each platform's native undo granularity, and the coordinator "must not grow an
  /// AppKit-shaped undo seam that UIKit cannot adopt." The grouping guarantees that
  /// whatever the platform registers for this reset is **at most one** action; it does not
  /// attempt to manufacture an action the platform did not register. See the note on
  /// `EscriboEditorBridge` for what that means in practice on macOS today.
  ///
  /// - Parameter incoming: The document the host wants displayed.
  /// - Returns: `true` if the document was replaced, `false` if rule 1 fired.
  @discardableResult
  func applyExternalText(_ incoming: String) -> Bool {
    let storage = documentStorage

    // Rule 1.
    guard !storage.mutableString.isEqual(to: incoming) else { return false }

    // Rule 3, first half: the selection as it stood before the reset.
    let previousSelection = textView.selectedRange
    let previousAnchor =
      previousSelection.location == NSNotFound ? 0 : max(0, previousSelection.location)
    let previousExtent = max(0, previousSelection.length)

    // Rule 4.
    let undoManager = textView.undoManager
    undoManager?.beginUndoGrouping()

    // Rule 2, first half.
    storage.beginEditing()
    storage.replaceCharacters(
      in: NSRange(location: 0, length: storage.length), with: incoming)
    storage.endEditing()

    undoManager?.endUndoGrouping()

    // Rule 2, second half.
    coordinator.restyleEverything()

    // Rule 3, second half.
    let newLength = storage.length
    let anchor = min(previousAnchor, newLength)
    let extent = min(previousExtent, newLength - anchor)
    textView.selectedRange = NSRange(location: anchor, length: extent)

    return true
  }

  // MARK: - External configuration

  /// Applies an externally supplied language, mode, theme, and appearance.
  ///
  /// ## Mode never reaches the styler
  ///
  /// REQUIREMENTS.md § Source mode is a theme: "switching between live and source mode is
  /// a theme swap rather than a content transformation," and DL-40 makes that structural.
  /// ``EditorStyleEnvironment/resolvedTheme`` folds the mode into the theme with
  /// ``EscriboTheme/strippedToSource()`` *before* ``EscriboStyler`` sees either, so the
  /// styler has no mode parameter, no mode field, and no branch on one. This function
  /// therefore switches modes by assigning the whole environment — which runs the styler's
  /// one invalidation path — and then restyling. It does not transform a single character,
  /// which is why a live → source → live round trip is byte-identical by construction
  /// rather than by test.
  ///
  /// ## Why the environment is compared rather than assigned unconditionally
  ///
  /// SwiftUI calls `update…View(_:context:)` on every layout pass, not only when something
  /// changed. Assigning an equal environment is already a no-op inside the styler (its
  /// `didSet` compares), but the *restyle* is not — an unconditional
  /// ``EditorCoordinator/restyleEverything()`` here would rescan the whole document on
  /// every layout pass, which is the same failure mode rule 1 above exists to prevent, one
  /// layer up. ``EditorCoordinator/setLanguage(_:)`` guards itself the same way (DL-28).
  ///
  /// - Parameters:
  ///   - language: The grammar. A change replaces the scanner and full-scans (DL-28).
  ///   - mode: Live or source.
  ///   - theme: The host's theme, *before* the mode is folded in.
  ///   - appearance: The system appearance the editor is drawn in.
  func applyConfiguration(
    language: Language,
    mode: EditorMode,
    theme: EscriboTheme,
    appearance: EscriboAppearance
  ) {
    // DL-28: a new scanner and a full scan, and a no-op when unchanged.
    coordinator.setLanguage(language)

    let styler = coordinator.styler
    let environment = EditorStyleEnvironment(
      theme: theme,
      mode: mode,
      appearance: appearance,
      // Font metrics are the text system's business, not the host's; carry whatever the
      // styler already holds rather than resetting it from a view update.
      metrics: styler.environment.metrics)

    guard styler.environment != environment else { return }
    styler.environment = environment
    coordinator.restyleEverything()
  }
}
