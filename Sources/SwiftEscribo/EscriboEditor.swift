import EscriboCore
import SwiftUI

/// A stylized Markdown or Fountain editor bound to a plain `String`.
///
/// ```swift
/// import EscriboCore
/// import SwiftEscribo
///
/// struct ScreenplayView: View {
///   @State private var screenplay = ""
///   @State private var mode = EditorMode.live
///
///   var body: some View {
///     EscriboEditor(text: $screenplay, language: .fountain, mode: mode)
///   }
/// }
/// ```
///
/// ## The raw string is the value
///
/// REQUIREMENTS.md Architecture §1: "The editor edits a `String` of source. Nothing is
/// derived, round-tripped, or reconstructed — what you set is what you get back, byte for
/// byte." That is why the binding is `String` and not `AttributedString`, and it is why
/// Non-goals §5 rejects `TextEditor(text:selection:)`, whose value *is* the attributed
/// string and which would make Markdown a lossy derivation.
///
/// It is also why ``EditorMode`` is a display setting rather than a document setting.
/// Switching between ``EditorMode/live`` and ``EditorMode/source`` swaps the theme and
/// restyles; it never touches a character, so the bound `String` is byte-identical across
/// any sequence of mode changes.
///
/// ## Themes
///
/// Pass `theme:` to take control, or leave it `nil` and get the built-in theme for the
/// language under the current `ColorScheme` — `markdownLight`, `markdownDark`,
/// `fountainLight`, or `fountainDark`. Appearance is read from the SwiftUI environment
/// rather than taken as a parameter, because it is the system's answer and not the host's.
///
/// ## Documents are the host's job
///
/// Non-goals §8: no `DocumentGroup`, no `NSDocument`, no `FileDocument`. This view is bound
/// to a `String`; opening, saving, URLs, and security-scoped access belong to the app.
public struct EscriboEditor: View {

  /// The document. The value, byte for byte.
  @Binding private var text: String

  /// The grammar to scan and style with.
  private let language: Language

  /// Styled or raw.
  private let mode: EditorMode

  /// The host's theme, or `nil` to follow the built-in theme for `language` and the
  /// current appearance.
  private let theme: EscriboTheme?

  /// Whether the editor offers the system find bar. macOS only; a no-op on iOS.
  private let findBar: Bool

  /// The system appearance, which selects between a theme pair when `theme` is `nil`.
  @Environment(\.colorScheme) private var colorScheme

  /// Creates an editor over `text`.
  ///
  /// - Parameters:
  ///   - text: The document. Setting this from outside is a **reset, not an edit**, and
  ///     follows REQUIREMENTS.md § External text replacement: an incoming string equal to
  ///     the current document does nothing at all, so a host may pass its state through on
  ///     every layout pass without the view fighting the user's typing.
  ///   - language: `.markdown` or `.fountain`. Changing it replaces the scanner and
  ///     rescans the document; the text is untouched.
  ///   - mode: ``EditorMode/live`` (styled, markers dimmed) or ``EditorMode/source``
  ///     (plain). Both edit the same string.
  ///   - theme: The theme to style with, or `nil` for the built-in theme matching
  ///     `language` and the current `ColorScheme`.
  ///   - findBar: Whether the editor offers the system **find bar** — the one that slides
  ///     in at the top of the editor's own scroll view, with incremental searching on —
  ///     rather than the floating find *panel*. Defaulted to `false` so a host opts in;
  ///     the menu items and their key equivalents remain the host's to supply, because
  ///     Non-goals §8 keeps document-level chrome out of this view.
  ///
  ///     Platform-neutral in this signature and honoured on macOS only. `UITextView` has
  ///     no find-bar equivalent, so on iOS the parameter is accepted and ignored rather
  ///     than fenced out of the API — a host that compiles for both platforms writes one
  ///     call site, not two.
  public init(
    text: Binding<String>,
    language: Language,
    mode: EditorMode = .live,
    theme: EscriboTheme? = nil,
    findBar: Bool = false
  ) {
    self._text = text
    self.language = language
    self.mode = mode
    self.theme = theme
    self.findBar = findBar
  }

  public var body: some View {
    let appearance: EscriboAppearance = colorScheme == .dark ? .dark : .light
    EscriboEditorRepresentable(
      text: $text,
      language: language,
      mode: mode,
      theme: theme ?? .builtIn(language: language, appearance: appearance),
      appearance: appearance,
      findBar: findBar)
  }
}
