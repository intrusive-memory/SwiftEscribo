/// Light or dark. The system appearance the editor is currently drawn in.
///
/// A styler input rather than something a theme reads, because ``EscriboColor`` stores
/// components and cannot adapt on its own. Changing this is one of the four things that
/// invalidates the styler's cache — "a fifth trigger that forgets to invalidate is how an
/// editor ends up with dark-mode text on a light background" (REQUIREMENTS.md § Theme).
struct EscriboAppearance: Hashable, Sendable {

  /// The stable identifier for this appearance.
  let rawValue: String

  /// Light appearance.
  static let light = EscriboAppearance(rawValue: "light")

  /// Dark appearance.
  static let dark = EscriboAppearance(rawValue: "dark")
}

/// Everything outside the document that decides how a span looks.
///
/// The four fields are exactly the four things REQUIREMENTS.md § Theme names as cache
/// invalidation triggers: theme, mode, appearance, and font metrics. Collecting them in
/// one `Equatable` value is what gives ``EscriboStyler`` **one** invalidation path rather
/// than four — the styler compares the whole environment and empties the cache when it
/// differs, so a fifth trigger added here cannot be forgotten at the invalidation site.
///
/// ## Where the mode goes
///
/// It stops here. ``resolvedTheme`` folds `mode` into `theme` before the styler sees
/// either, which is the API-level statement of "source mode is a theme, not a code path"
/// (REQUIREMENTS.md § Source mode is a theme). The styler has no mode parameter, no mode
/// field, and no branch on one; there is nothing for a future author to add a third mode
/// to.
struct EditorStyleEnvironment: Equatable, Sendable {

  /// The theme the host chose, before the mode is applied.
  var theme: EscriboTheme

  /// Styled or raw.
  var mode: EditorMode

  /// The appearance the editor is drawn in.
  var appearance: EscriboAppearance

  /// The text system's current metrics.
  var metrics: FontMetrics

  init(
    theme: EscriboTheme,
    mode: EditorMode = .live,
    appearance: EscriboAppearance = .light,
    metrics: FontMetrics = .nominal
  ) {
    self.theme = theme
    self.mode = mode
    self.appearance = appearance
    self.metrics = metrics
  }

  /// The theme the styler actually resolves against: ``theme``, stripped when the mode is
  /// ``EditorMode/source``.
  var resolvedTheme: EscriboTheme {
    mode == .source ? theme.strippedToSource() : theme
  }
}
