import EscriboCore
import SwiftUI

#if os(macOS)
  import AppKit
#elseif os(iOS)
  import UIKit
#endif

// MARK: - The SwiftUI coordinator

/// The object SwiftUI keeps alive across `update…View(_:context:)` passes: it owns the
/// ``EscriboTextView``, and it is the text view's *view* delegate so typing reaches the
/// `@Binding`.
///
/// ## Two delegates, two different jobs
///
/// This type is the text **view**'s delegate (`NSTextViewDelegate` / `UITextViewDelegate`),
/// which reports "the user changed the text." ``EditorCoordinator`` is the text
/// **storage**'s delegate (`NSTextStorageDelegate`), which reports "these characters
/// changed, here." They are different protocols on different objects and do not compete:
/// the storage delegate drives scanning and styling, this one drives the binding, and
/// neither knows the other exists.
///
/// ## Why it holds the editor
///
/// `NSTextStorage.delegate` is a **weak** reference (see
/// ``EditorCoordinator/attach(to:)``), so something must retain the coordinator for the
/// document's lifetime. A `Representable` struct is recreated on every SwiftUI update and
/// cannot; its coordinator is created once by `makeCoordinator()` and survives, so it is
/// the only correct owner.
///
/// ## Undo, and what rule 4 actually buys on macOS today
///
/// ``EscriboTextView/applyExternalText(_:)`` groups its reset on the platform's
/// `UndoManager`, which bounds it to at most one undo action. It does not route the reset
/// through `NSTextView.shouldChangeText(in:replacementString:)` /
/// `didChangeText()`, which is what would make a programmatic storage mutation *register*
/// an undo action on macOS at all. That is deliberate: REQUIREMENTS.md § Undo requires that
/// affordance-driven rewrites go through the text view's own input path, and Sortie 25 owns
/// building that path once, for the affordances and for paste together. Adding a
/// second, external-reset-only input path here would be the AppKit-shaped seam Known
/// limitations §1 warns against, built before the sortie that has to live with it.
///
/// `@MainActor` for the reason DL-64 gives: views are main-actor-isolated, and
/// ``EditorCoordinator`` deliberately is not.
@MainActor
final class EscriboEditorBridge: NSObject {

  /// The host's binding. Reassigned on every update pass, because SwiftUI hands out a new
  /// `Binding` value each time and the old one's setter targets a stale view graph.
  var text: Binding<String>

  /// The editor this bridge owns, once `makeEditor` has run.
  private(set) var editor: EscriboTextView?

  /// Creates a bridge over `text`.
  init(text: Binding<String>) {
    self.text = text
    super.init()
  }

  // MARK: - Construction

  /// Builds the editor, takes its view delegate, and seeds it from the binding.
  ///
  /// Called from `makeNSView(context:)` / `makeUIView(context:)` and from nowhere else.
  /// It lives here rather than inline in those methods for one reason: a
  /// `Representable.Context` cannot be constructed in a test, so anything written inside
  /// `makeNSView` is unassertable. Everything the Representable does is therefore a call to
  /// a method on this object, and the Representable itself is three lines with no logic in
  /// them.
  ///
  /// Note what is *not* here: no text-view configuration of any kind. TextKit 2 selection,
  /// the hygiene flags, spell checking, `isRichText`, and `allowsUndo` are all set by
  /// ``EscriboTextView``'s own initializer (Sorties 10 and 11) and are asserted against the
  /// view that initializer builds. Duplicating or overriding any of it here would put the
  /// shipped configuration out of reach of those tests.
  func makeEditor(
    language: Language,
    mode: EditorMode,
    theme: EscriboTheme,
    appearance: EscriboAppearance
  ) -> EscriboTextView {
    let styler = EscriboStyler(
      environment: EditorStyleEnvironment(theme: theme, mode: mode, appearance: appearance))
    let editor = EscriboTextView(language: language, styler: styler)
    self.editor = editor

    editor.textView.delegate = self

    // The initial document arrives through the same four rules every later update uses.
    // Rule 1 makes this free when the host starts from an empty string.
    editor.applyExternalText(text.wrappedValue)

    return editor
  }

  // MARK: - Update

  /// Pushes the host's current configuration and document into the editor.
  ///
  /// Configuration first, then text. Both are idempotent and both are guarded, so a SwiftUI
  /// layout pass in which nothing changed does no work at all — no rescan, no styler
  /// invalidation, and above all no text-storage mutation (REQUIREMENTS.md § External text
  /// replacement rule 1).
  func update(
    language: Language,
    mode: EditorMode,
    theme: EscriboTheme,
    appearance: EscriboAppearance,
    text incoming: String
  ) {
    guard let editor else { return }
    editor.applyConfiguration(
      language: language, mode: mode, theme: theme, appearance: appearance)
    editor.applyExternalText(incoming)
  }

  /// Pushes the editor's document back out to the binding.
  ///
  /// Guarded against writing an equal value: a `@Binding` setter that fires with unchanged
  /// content still invalidates the host's view, which comes straight back as an update pass
  /// carrying the same string. Rule 1 would absorb it, but the cheaper place to stop the
  /// loop is before it starts.
  func pushToBinding() {
    guard let editor else { return }
    let document = editor.currentText
    guard text.wrappedValue != document else { return }
    text.wrappedValue = document
  }
}

// MARK: - The view delegate

#if os(macOS)
  extension EscriboEditorBridge: NSTextViewDelegate {

    /// AppKit's "the user changed the text."
    func textDidChange(_ notification: Notification) {
      pushToBinding()
    }
  }
#elseif os(iOS)
  extension EscriboEditorBridge: UITextViewDelegate {

    /// UIKit's "the user changed the text" — the same event, spelled with the view as an
    /// argument instead of wrapped in a `Notification`.
    func textViewDidChange(_ textView: UITextView) {
      pushToBinding()
    }
  }
#endif

// MARK: - The Representables

#if os(macOS)

  /// The macOS half of "both Representables ship together" (REQUIREMENTS.md Architecture
  /// §10).
  ///
  /// A **thin wrapper**, on purpose. It constructs an ``EscriboTextView`` and returns that
  /// view's `scrollView`; it configures nothing, styles nothing, and knows nothing about
  /// scanning. Everything Sorties 10 and 11 assert about the shipped text view — the
  /// TextKit 2 stack, the hygiene flags, spell checking, `isRichText`, `allowsUndo` — is
  /// asserted against the object this returns, because this returns that object rather than
  /// building a second one.
  struct EscriboEditorRepresentable: NSViewRepresentable {

    @Binding var text: String
    let language: Language
    let mode: EditorMode
    let theme: EscriboTheme
    let appearance: EscriboAppearance

    func makeCoordinator() -> EscriboEditorBridge {
      EscriboEditorBridge(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
      context.coordinator.makeEditor(
        language: language, mode: mode, theme: theme, appearance: appearance
      ).scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
      context.coordinator.text = $text
      context.coordinator.update(
        language: language, mode: mode, theme: theme, appearance: appearance, text: text)
    }
  }

#elseif os(iOS)

  /// The iOS half of "both Representables ship together" (REQUIREMENTS.md Architecture
  /// §10), identical to the macOS one except for the view it returns.
  ///
  /// `UITextView` self-scrolls, so there is no scroll container to return — the text view
  /// *is* the root view. That is the only difference between this type and its AppKit
  /// counterpart, and it is a difference in what UIKit vends rather than in anything this
  /// package does.
  struct EscriboEditorRepresentable: UIViewRepresentable {

    @Binding var text: String
    let language: Language
    let mode: EditorMode
    let theme: EscriboTheme
    let appearance: EscriboAppearance

    func makeCoordinator() -> EscriboEditorBridge {
      EscriboEditorBridge(text: $text)
    }

    func makeUIView(context: Context) -> UITextView {
      context.coordinator.makeEditor(
        language: language, mode: mode, theme: theme, appearance: appearance
      ).textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
      context.coordinator.text = $text
      context.coordinator.update(
        language: language, mode: mode, theme: theme, appearance: appearance, text: text)
    }
  }

#endif
