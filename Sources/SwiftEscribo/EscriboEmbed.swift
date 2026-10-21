import EscriboCore

// MARK: - The provider

/// The host's answer to "should this block be drawn as an embed, and if so, as what?"
///
/// An **embed** is one atomic row — a glyph, a title, a subtitle, an optional badge —
/// drawn in place of a block, while the block's characters stay in the document byte for
/// byte. The package knows nothing about what an embed *means*: a screenplay host might
/// draw a structured directive note as a compact object instead of its markup, and the
/// editor neither parses the note nor remembers why it was asked.
///
/// Pass a provider to ``EscriboEditor`` as `embedProvider:`. With none — the default — the
/// editor draws every block as text, exactly as before embeds existed.
///
/// ## When the editor asks
///
/// `any EscriboEmbedProvider` is not `Equatable`, so a SwiftUI update pass cannot show that
/// a provider's answers changed, and the editor does **not** re-ask on every update. It asks:
///
/// - for **every block** when the provider is first installed, and when the document is
///   loaded or replaced;
/// - for the blocks inside each edit's rescanned window — the blocks the incremental scan
///   returns — on every edit;
/// - for **every block** when the host calls ``EscriboEditorHandle/invalidateEmbeds()``.
///
/// So whenever the provider's answers change *without* a text edit — the writer chose
/// *Edit as Text* and the provider now returns `nil` for that block, or Find expanded the
/// embed holding a match — the host calls `invalidateEmbeds()`. Swapping one provider value
/// for another on an update pass is not a re-ask either; it is the same signal and needs
/// the same call.
///
/// The provider is asked in ``EditorMode/live`` **only**. In ``EditorMode/source`` it is
/// never called and no block is an embed.
///
/// ## Isolation
///
/// The editor calls ``embed(for:in:)`` **synchronously on the main thread**, from inside
/// its text-storage edit processing — the same thread and the same moment it restyles.
/// The protocol is deliberately not `@MainActor`: the editor's coordinator is not
/// main-actor-isolated (it is an `NSTextStorageDelegate`, which is not), and calling an
/// isolated requirement from there would need `MainActor.assumeIsolated`, a trap on the
/// typing path. A main-actor host type can conform with an isolated conformance
/// (`extension MyProvider: @MainActor EscriboEmbedProvider`) or with a `nonisolated`
/// method; either is sound because the call really is made on the main thread.
///
/// Answer quickly and without side effects. The method runs once per rescanned block on
/// every keystroke, and once per block in the document on load and on invalidation.
///
/// ## Identity
///
/// ``EscriboBlock/ID`` is **not** stable across edits, so a provider must not key its
/// state on it. Key *Edit as Text* and similar choices on something stable to the host —
/// for a directive note, its content or an id written inside it — and return `nil` for
/// that block.
public protocol EscriboEmbedProvider {

  /// The embed to draw for `block`, or `nil` to draw its text as usual.
  ///
  /// - Parameters:
  ///   - block: The block, as the scanner grouped it. Its ``EscriboBlock/range`` is in
  ///     UTF-16 code units of the current document.
  ///   - text: The block's own source text — the document's characters over
  ///     ``EscriboBlock/range``, final line terminator included — so the provider can
  ///     read the block without holding the whole document.
  /// - Returns: The embed, or `nil` for "not an embed".
  func embed(for block: EscriboBlock, in text: String) -> EscriboEmbed?
}

// MARK: - The embed

/// What an embed row shows, and what it tells assistive technology.
///
/// A plain value. The package draws it and reports clicks and actions back through
/// ``EscriboEditor``'s `onEmbedActivate:` and `onEmbedAction:`; it never interprets
/// any field.
///
/// `Equatable` for the same reason ``EscriboWell`` is: the editor compares a block's new
/// answer with its old one, and only a changed answer redraws. A stored closure would make
/// that comparison impossible, which is why an ``Action`` is an id and a title rather than
/// a callback.
public struct EscriboEmbed: Equatable, Sendable {

  /// A small coloured tag drawn at the trailing edge of the row: a glyph and a word.
  public struct Badge: Equatable, Sendable {

    /// The badge's SF Symbol name.
    public var symbolName: String

    /// The badge's word, e.g. a status or a type name.
    public var word: String

    /// The badge's colour.
    public var tint: EscriboColor

    /// Creates a badge.
    ///
    /// - Parameters:
    ///   - symbolName: The badge's SF Symbol name.
    ///   - word: The badge's word.
    ///   - tint: The badge's colour.
    public init(symbolName: String, word: String, tint: EscriboColor) {
      self.symbolName = symbolName
      self.word = word
      self.tint = tint
    }
  }

  /// A host-defined action offered on the embed — as an accessibility custom action and in
  /// the host's own menus. Performing one calls `onEmbedAction:` with the block and ``id``.
  public struct Action: Equatable, Sendable {

    /// The host's identifier for the action, handed back verbatim when it is performed.
    public var id: String

    /// The action's user-visible title.
    public var title: String

    /// Creates an action.
    ///
    /// - Parameters:
    ///   - id: The host's identifier, handed back when the action is performed.
    ///   - title: The user-visible title.
    public init(id: String, title: String) {
      self.id = id
      self.title = title
    }
  }

  /// The row's leading SF Symbol name.
  public var symbolName: String

  /// The row's first line.
  public var title: String

  /// The row's second line, or `""` for none.
  public var subtitle: String

  /// The trailing badge, or `nil` for none.
  public var badge: Badge?

  /// The accessibility label of the embed's single element. Defaults to ``title``.
  public var accessibilityLabel: String

  /// The accessibility value of the embed's single element. Defaults to ``subtitle``.
  public var accessibilityValue: String

  /// The accessibility identifier of the embed's single element, for UI automation, or
  /// `nil` for none.
  public var accessibilityIdentifier: String?

  /// The host's actions on the embed, in the order they are offered.
  public var actions: [Action]

  /// Creates an embed.
  ///
  /// - Parameters:
  ///   - symbolName: The row's leading SF Symbol name.
  ///   - title: The row's first line.
  ///   - subtitle: The row's second line. Defaults to none.
  ///   - badge: The trailing badge. Defaults to none.
  ///   - accessibilityLabel: The element's label, or `nil` to use `title`.
  ///   - accessibilityValue: The element's value, or `nil` to use `subtitle`.
  ///   - accessibilityIdentifier: The element's identifier. Defaults to none.
  ///   - actions: The host's actions. Defaults to none.
  public init(
    symbolName: String,
    title: String,
    subtitle: String = "",
    badge: Badge? = nil,
    accessibilityLabel: String? = nil,
    accessibilityValue: String? = nil,
    accessibilityIdentifier: String? = nil,
    actions: [Action] = []
  ) {
    self.symbolName = symbolName
    self.title = title
    self.subtitle = subtitle
    self.badge = badge
    self.accessibilityLabel = accessibilityLabel ?? title
    self.accessibilityValue = accessibilityValue ?? subtitle
    self.accessibilityIdentifier = accessibilityIdentifier
    self.actions = actions
  }
}
