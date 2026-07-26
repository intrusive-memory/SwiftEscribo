import EscriboCore
import Foundation

#if os(macOS)
  import AppKit
#elseif os(iOS)
  import UIKit
#endif

/// Rule 3 of REQUIREMENTS.md § External text replacement, as arithmetic.
///
/// > Clamp the selection to the new length rather than dropping it to zero.
///
/// ## Why this is a free function and not four lines inside `applyExternalText`
///
/// Because inline, **the rule is untestable**, and worse, it looks tested.
///
/// The Sortie 12 supervisor deleted both `min`s from the inline version and the whole
/// suite stayed green — including the two integration tests written specifically to cover
/// this rule. The cause is that `NSTextView.selectedRange`'s *setter* clamps an
/// out-of-range value on its own, so setting a selection, shortening the document, and
/// reading the selection back measures AppKit and not this package. A test that passes
/// with the implementation removed certifies nothing.
///
/// Pulled out here the rule is input → output with no text view anywhere in it, so
/// `SelectionClampTests` can drive it over a table and a deletion goes red immediately.
/// That is the entire justification for the indirection; there is no other reason for this
/// type to exist.
///
/// The integration tests remain, as a second leg proving the clamp is actually *wired* to
/// the replacement path — a thing the pure test cannot see — but they carry a comment
/// saying they cannot fail on their own, so that a later sortie does not "simplify" the
/// table-driven test away as redundant.
enum SelectionClamp {

  /// `anchor..<(anchor + extent)` confined to `0..<newLength`.
  ///
  /// Total by construction: every input, including nonsensical ones, yields a well-formed
  /// `NSRange` inside the new document. There is no failure mode, because the caller is a
  /// text-view mutation and an ill-formed `NSRange` there is an `NSRangeException` inside
  /// the host app rather than a diagnosable error here.
  ///
  /// - Parameters:
  ///   - anchor: The selection's location **before** the replacement, exactly as the text
  ///     view reported it — including `NSNotFound`, which is the text system's "there is
  ///     no selection" and is normalised to a caret at the start rather than propagated.
  ///   - extent: The selection's length before the replacement.
  ///   - newLength: The document's length in UTF-16 code units **after** the replacement.
  /// - Returns: The clamped selection. The anchor moves only as far as it must, so a caret
  ///   past the end of a shortened document lands at the **end** and not at zero; the
  ///   extent is trimmed to whatever survives after the anchor, so a selection straddling
  ///   the new end keeps the part that still exists rather than collapsing.
  static func clampedSelection(anchor: Int, extent: Int, toLength newLength: Int) -> NSRange {
    let length = max(0, newLength)

    // `NSNotFound` is a sentinel, not a large number. Clamping it arithmetically would put
    // the caret at the end of the document on every reset that happened to follow a
    // "no selection" state.
    guard anchor != NSNotFound else { return NSRange(location: 0, length: 0) }

    let location = min(max(0, anchor), length)
    return NSRange(location: location, length: min(max(0, extent), length - location))
  }
}

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
  /// time the mutation returns. The arithmetic lives in ``SelectionClamp`` rather than
  /// inline here, and that is a testability decision with a specific history: `NSTextView`
  /// clamps an out-of-range `selectedRange` in its own setter, so an integration test that
  /// sets a selection, shortens the document, and reads the selection back **passes with
  /// this clamp deleted**. Discovered by the Sortie 12 supervisor doing exactly that.
  /// A pure function is the only shape of this rule that can be asserted against.
  ///
  /// AppKit's forgiveness is also not something to lean on. UIKit makes no such promise,
  /// and without the clamp `newLength - anchor` can go negative, which is an `NSRange`
  /// with a length of roughly 2^63 handed to a text view.
  ///
  /// ### Rule 4 — one undo action
  ///
  /// > Register as a single undo action.
  ///
  /// **Closed by Sortie 25, and it was genuinely unmet before.** The reset now goes through
  /// ``EscriboTextView/performInputPathEdit(_:)`` — the text view's *own* input path —
  /// rather than mutating text storage directly.
  ///
  /// The history is worth keeping, because the old shape looked correct. Sortie 12 bracketed
  /// the mutation in `beginUndoGrouping()`/`endUndoGrouping()`, which bounds a reset at **at
  /// most one** undo action but cannot manufacture an action the platform never registered.
  /// On macOS it registered **zero**: `NSTextView` records undo from
  /// `shouldChangeText(in:replacementString:)` / `didChangeText()`, and a direct
  /// `NSTextStorage.replaceCharacters` goes through neither. An external reset was therefore
  /// not undoable on macOS at all, and rule 4 was met only in the "not more than one"
  /// direction. Sortie 12 said so rather than claiming the rule, and deferred it here
  /// deliberately.
  ///
  /// The deferral had a specific reason and it is the reason this call is now one line:
  /// closing it then would have meant a second, external-reset-only input path, which is the
  /// duplicate AppKit-shaped seam Known limitations §1 warns against. Sortie 25 builds the
  /// path **once**, for list continuation and this reset together, so there is exactly one
  /// place in the package where a document's characters change and exactly one undo story to
  /// reason about. Do not add a private one here.
  ///
  /// On iOS undo granularity remains whatever UIKit provides (Known limitations §1). The
  /// *shape* is identical on both platforms — one transaction through the text view's own
  /// input path — which is what makes that limitation a scheduling fact rather than an
  /// architectural one.
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

    // Rules 2 (first half) and 4, together, and they are the same call on purpose. The input
    // path replaces the full range with `replaceCharacters(in:with:)` inside
    // `beginEditing()`/`endEditing()` — never `setAttributedString` (Architecture §8) — and
    // registers exactly one undo action while doing it.
    performInputPathEdit(
      InputPathEdit(
        replacing: NSRange(location: 0, length: storage.length), with: incoming))

    // Rule 2, second half.
    coordinator.restyleEverything()

    // Rule 3, second half.
    textView.selectedRange = SelectionClamp.clampedSelection(
      anchor: previousSelection.location,
      extent: previousSelection.length,
      toLength: storage.length)

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
