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

    /// The id of the *Edit as Text* action: the writer wants the block's source back as
    /// ordinary text.
    ///
    /// The editor never performs this itself; it only reports it. `⌥↩` with an embed
    /// selected **always** calls `onEmbedAction:` with the block and this id, on macOS and
    /// on iOS (a `UIKeyCommand`, with a hardware keyboard), whether or not the host lists
    /// the action. To offer *Edit as Text* to touch and VoiceOver users as well, the host
    /// lists an ``Action`` with this id in ``EscriboEmbed/actions``, so it appears among the
    /// embed's accessibility custom actions. The host answers by returning `nil` for that
    /// block from its provider and calling ``EscriboEditorHandle/invalidateEmbeds()``.
    public static let editAsTextID = "escribo.editAsText"

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

  /// One stretch of the subtitle, drawn either in the row's secondary colour or, when
  /// ``isDeEmphasized``, in a fainter one.
  ///
  /// A host uses de-emphasized runs for text that is shown but not the block's own — a
  /// value inherited from a default, say — so the reader can tell the two apart at a
  /// glance. Both colours derive from the theme's base foreground; the package assigns no
  /// meaning to either.
  public struct SubtitleRun: Equatable, Sendable {

    /// The run's text.
    public var text: String

    /// Whether the run is drawn in the fainter, de-emphasized colour.
    public var isDeEmphasized: Bool

    /// Creates a run.
    ///
    /// - Parameters:
    ///   - text: The run's text.
    ///   - isDeEmphasized: Whether the run is drawn in the fainter colour. Defaults to
    ///     `false`, the subtitle's ordinary secondary colour.
    public init(_ text: String, isDeEmphasized: Bool = false) {
      self.text = text
      self.isDeEmphasized = isDeEmphasized
    }
  }

  /// A second accessibility element for the embed's state — typically what its ``badge``
  /// says — so UI automation and assistive technology can read the state on its own.
  ///
  /// The element is exposed **right after** the embed's own element, as its sibling (on iOS
  /// an accessible view cannot have accessible children, so a sibling is the only shape
  /// that works on both platforms). It is static text, not a button, and has no actions.
  /// Its frame is the badge's capsule when a badge is drawn, otherwise a small square at
  /// the row's trailing edge, so it exists even for a state that draws no badge.
  public struct StateElement: Equatable, Sendable {

    /// The element's accessibility label.
    public var label: String

    /// The element's accessibility value — the state itself.
    public var value: String

    /// The element's accessibility identifier, for UI automation, or `nil` for none.
    public var identifier: String?

    /// Creates a state element.
    ///
    /// - Parameters:
    ///   - label: The accessibility label.
    ///   - value: The accessibility value.
    ///   - identifier: The accessibility identifier. Defaults to none.
    public init(label: String, value: String, identifier: String? = nil) {
      self.label = label
      self.value = value
      self.identifier = identifier
    }
  }

  /// The row's leading SF Symbol name.
  public var symbolName: String

  /// The row's first line.
  public var title: String

  /// The row's second line, as runs drawn in turn on one line, truncated at the tail as a
  /// whole. Empty for none.
  public var subtitleRuns: [SubtitleRun]

  /// The row's second line as plain text: the runs' text, joined, or `""` for none.
  ///
  /// Setting it replaces the runs with one ordinary run (none for `""`).
  public var subtitle: String {
    get { subtitleRuns.map(\.text).joined() }
    set { subtitleRuns = Self.runs(plain: newValue) }
  }

  /// The trailing badge, or `nil` for none.
  public var badge: Badge?

  /// The accessibility label of the embed's element. Defaults to ``title``.
  public var accessibilityLabel: String

  /// The accessibility value of the embed's element. Defaults to ``subtitle``.
  public var accessibilityValue: String

  /// The accessibility identifier of the embed's element, for UI automation, or `nil` for
  /// none.
  public var accessibilityIdentifier: String?

  /// The host's actions on the embed, in the order they are offered.
  public var actions: [Action]

  /// The embed's separate state element, or `nil` for none — the default, which exposes
  /// the embed as exactly one element.
  public var stateElement: StateElement?

  /// Help text shown when the pointer rests on the row, or `nil` for none.
  ///
  /// On macOS a tool tip over the row; on iPadOS with a pointer, a `UIToolTipInteraction`
  /// tool tip.
  public var toolTip: String?

  /// Creates an embed.
  ///
  /// - Parameters:
  ///   - symbolName: The row's leading SF Symbol name.
  ///   - title: The row's first line.
  ///   - subtitle: The row's second line, as plain text. Defaults to none. Ignored when
  ///     `subtitleRuns` is given.
  ///   - badge: The trailing badge. Defaults to none.
  ///   - accessibilityLabel: The element's label, or `nil` to use `title`.
  ///   - accessibilityValue: The element's value, or `nil` to use the subtitle's text.
  ///   - accessibilityIdentifier: The element's identifier. Defaults to none.
  ///   - actions: The host's actions. Defaults to none.
  ///   - subtitleRuns: The row's second line as runs, or `nil` to use `subtitle`.
  ///   - stateElement: A separate accessibility element for the embed's state. Defaults to
  ///     none.
  ///   - toolTip: Help text shown when the pointer rests on the row. Defaults to none.
  public init(
    symbolName: String,
    title: String,
    subtitle: String = "",
    badge: Badge? = nil,
    accessibilityLabel: String? = nil,
    accessibilityValue: String? = nil,
    accessibilityIdentifier: String? = nil,
    actions: [Action] = [],
    subtitleRuns: [SubtitleRun]? = nil,
    stateElement: StateElement? = nil,
    toolTip: String? = nil
  ) {
    self.symbolName = symbolName
    self.title = title
    self.subtitleRuns = subtitleRuns ?? Self.runs(plain: subtitle)
    self.badge = badge
    self.accessibilityLabel = accessibilityLabel ?? title
    self.accessibilityValue = accessibilityValue ?? self.subtitleRuns.map(\.text).joined()
    self.accessibilityIdentifier = accessibilityIdentifier
    self.actions = actions
    self.stateElement = stateElement
    self.toolTip = toolTip
  }

  /// One ordinary run for `text`, or none for `""`, so a plain subtitle and the same text
  /// given as one ordinary run compare equal.
  private static func runs(plain text: String) -> [SubtitleRun] {
    text.isEmpty ? [] : [SubtitleRun(text)]
  }
}
