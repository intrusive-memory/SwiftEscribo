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

  /// Whether the editor takes the caret when it is installed. macOS only; a no-op on iOS.
  private let focusOnAppear: Bool

  /// The host's handle on the live editor, or `nil`.
  private let handle: EscriboEditorHandle?

  /// The paragraph well, or `nil` for no well and no lane.
  private let well: EscriboWell?

  /// Called with the slot and the block when a well slot is activated — a click or tap on
  /// the well's button. Handed to the text view, whose well invokes it.
  private let onWellAction: (EscriboWellItem, EscriboBlock) -> Void

  /// The host's embed provider, or `nil` to draw every block as text.
  private let embedProvider: (any EscriboEmbedProvider)?

  /// Called with the block when an embed row is clicked or tapped.
  private let onEmbedActivate: (EscriboBlock) -> Void

  /// Called with the block and the action's id when an embed's action is performed.
  private let onEmbedAction: (EscriboBlock, String) -> Void

  /// Called with the block when Find lands a match inside an embed. macOS only; a no-op on
  /// iOS.
  private let onFindMatchInEmbed: (EscriboBlock) -> Void

  /// The host's per-block well notice, or `nil` for none.
  private let wellNotice: ((EscriboBlock) -> (symbolName: String, help: String)?)?

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
  ///   - focusOnAppear: Whether the editor's text view claims **first responder** the moment
  ///     it is installed in a window, so the first thing typed into a freshly-opened
  ///     document lands in the document instead of nowhere. Defaulted to `false`, because a
  ///     view that seizes the caret on sight is wrong in any host that puts something else
  ///     first.
  ///
  ///     It fires **once**, on the first window the view is given. A later re-attachment is
  ///     not an appearance, and an editor that yanked the selection back on every layout
  ///     pass would be worse than no focus at all.
  ///
  ///     This is a hook rather than a suggestion: the package owns the text view, so it
  ///     focuses it directly. A host cannot do the same — a `NSViewRepresentable`'s view is
  ///     unreachable from SwiftUI's focus system, which leaves a consumer no option but a
  ///     sibling probe that walks the window's content view hunting for an `NSTextView`.
  ///     This parameter exists to delete that walk.
  ///
  ///     Platform-neutral in this signature and honoured on macOS only, like `findBar` — but
  ///     the iOS no-op is a *decision*, not a gap. `becomeFirstResponder()` on a
  ///     `UITextView` raises the software keyboard, and doing that the instant a document
  ///     opens is an interruption rather than a convenience.
  ///   - handle: A handle the editor points at the live document, so a host can ask which
  ///     block is under a point or on screen **without casting to `NSTextView` or
  ///     `UITextView`** (REQUIREMENTS-1.1.0 § 4.3). Hold it in `@StateObject`; it is empty
  ///     until the editor is installed and empties again when the editor goes away, and
  ///     every query on it answers `nil` or `[]` rather than trapping in either state.
  ///
  ///     Defaulted to `nil` so a host that asks the editor nothing writes nothing, and so
  ///     every pre-0.4.0 call site keeps compiling unchanged.
  ///   - well: The paragraph well (REQUIREMENTS-1.1.0 § 5): its slots, the playing block,
  ///     its progress, the spoken word, and which block kinds are eligible. Supplying one
  ///     reserves the well's lane in the text view's text-container inset — 28 pt on macOS,
  ///     symmetric, so the right margin gains the same; 44 pt on iOS at regular width,
  ///     left-only; **none** on iOS at compact width (D-5). The lane is added to the inset
  ///     the text view already uses.
  ///
  ///     Defaulted to `nil`, which reserves nothing: an adopter that does not mention the
  ///     well gets exactly the insets and layout it had before `0.4.0`. Pass a fresh value on
  ///     every update — progress and the spoken range are the host's to report.
  ///   - onWellAction: Called with the slot and the block when a well slot is activated.
  ///     The package draws and tracks; the host acts — for `.readAloud`, it speaks. Defaulted
  ///     to a no-op so every pre-0.4.0 call site keeps compiling unchanged.
  ///   - embedProvider: Draws blocks as **embeds** — one atomic row in place of the block's
  ///     text, while its characters stay in the document (REQUIREMENTS.md § 1). Asked per
  ///     block in ``EditorMode/live`` only; see ``EscriboEmbedProvider`` for exactly when.
  ///     Because a provider is not `Equatable`, a new value on an update pass is not a
  ///     re-ask: call ``EscriboEditorHandle/invalidateEmbeds()`` when its answers change
  ///     without an edit. Defaulted to `nil`, which changes nothing — no layout, inset or
  ///     behaviour differs from an editor that never heard of embeds.
  ///   - onEmbedActivate: Called once with the block when an embed row is clicked or
  ///     tapped. The block stays selected. Defaulted to a no-op.
  ///   - onEmbedAction: Called with the block and the ``EscriboEmbed/Action/id`` when one of
  ///     the embed's ``EscriboEmbed/actions`` is performed. Option-Return with an embed
  ///     selected always calls it with ``EscriboEmbed/Action/editAsTextID``, whether or not
  ///     the embed lists that action; list an ``EscriboEmbed/Action`` with that id to offer
  ///     *Edit as Text* in the accessibility custom actions too. Defaulted to a no-op.
  ///   - onFindMatchInEmbed: Called with the block when the find bar's current match lies
  ///     inside an embed. The host typically stops returning an embed for that block and
  ///     calls ``EscriboEditorHandle/invalidateEmbeds()``, so the match shows as text.
  ///     Defaulted to a no-op.
  ///
  ///     Platform-neutral in this signature and honoured on macOS only, like `findBar`:
  ///     iOS has no find bar, so there it is accepted and never called.
  ///
  ///   - wellNotice: Per-block well content (REQUIREMENTS.md § 2): return a notice glyph
  ///     (an SF Symbol name) and its help text for a block that has one, or `nil`. A block
  ///     with a notice shows it in the well's one slot **at all times**, in place of
  ///     `.readAloud`, regardless of ``EscriboWell/eligibleKinds`` and whether the block
  ///     has content; a click calls `onWellAction(.notice, block)`. Needs a non-nil `well`
  ///     (that is what reserves the lane); `well.items` need not contain `.notice`.
  ///
  ///     Asked in **both** ``EditorMode``s, unlike embeds. Asked at the same points as the
  ///     embed provider — on install, after every full scan, for each edit's rescanned
  ///     blocks, and for every block on ``EscriboEditorHandle/invalidateEmbeds()`` — and
  ///     never on a SwiftUI update pass. Defaulted to `nil`: no notices, no change.
  ///
  /// Every parameter after `onWellAction` is new in this release and comes **after** it on
  /// purpose: a call site that passes `onWellAction` as a trailing closure keeps binding it
  /// there.
  public init(
    text: Binding<String>,
    language: Language,
    mode: EditorMode = .live,
    theme: EscriboTheme? = nil,
    findBar: Bool = false,
    focusOnAppear: Bool = false,
    handle: EscriboEditorHandle? = nil,
    well: EscriboWell? = nil,
    onWellAction: @escaping (EscriboWellItem, EscriboBlock) -> Void = { _, _ in },
    embedProvider: (any EscriboEmbedProvider)? = nil,
    onEmbedActivate: @escaping (EscriboBlock) -> Void = { _ in },
    onEmbedAction: @escaping (EscriboBlock, String) -> Void = { _, _ in },
    onFindMatchInEmbed: @escaping (EscriboBlock) -> Void = { _ in },
    wellNotice: ((EscriboBlock) -> (symbolName: String, help: String)?)? = nil
  ) {
    self._text = text
    self.language = language
    self.mode = mode
    self.theme = theme
    self.findBar = findBar
    self.focusOnAppear = focusOnAppear
    self.handle = handle
    self.well = well
    self.onWellAction = onWellAction
    self.embedProvider = embedProvider
    self.onEmbedActivate = onEmbedActivate
    self.onEmbedAction = onEmbedAction
    self.onFindMatchInEmbed = onFindMatchInEmbed
    self.wellNotice = wellNotice
  }

  public var body: some View {
    let appearance: EscriboAppearance = colorScheme == .dark ? .dark : .light
    EscriboEditorRepresentable(
      text: $text,
      language: language,
      mode: mode,
      theme: theme ?? .builtIn(language: language, appearance: appearance),
      appearance: appearance,
      findBar: findBar,
      focusOnAppear: focusOnAppear,
      handle: handle,
      well: well,
      onWellAction: onWellAction,
      embeds: EmbedConfiguration(
        provider: embedProvider,
        onActivate: onEmbedActivate,
        onAction: onEmbedAction,
        onFindMatch: onFindMatchInEmbed,
        wellNotice: wellNotice))
  }
}
