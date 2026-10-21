/// Whether the editor renders its document styled or raw.
///
/// Switching between the two is a **theme swap, not a content transformation** (REQUIREMENTS.md
/// § Source mode is a theme). The document's characters are identical in both modes; only
/// the attributes applied over them change. That is why this type never reaches the
/// styler: ``EditorStyleEnvironment`` resolves a mode plus a theme into one theme, and the
/// styler is handed the result.
///
/// ## The one code path a mode does select
///
/// With no ``EscriboEmbedProvider`` installed, switching modes is not a code path either.
/// With one, it is: the provider is asked **only** in ``live``, so ``source`` draws every
/// block as text and never calls the provider, and returning to ``live`` asks every block
/// again. The styler still never sees the mode; the branch is the editor's single check
/// before it consults the provider.
///
/// A struct with static members rather than an enum, matching the rest of the package's
/// vocabulary types.
public struct EditorMode: Hashable, Sendable {

  /// The stable identifier for this mode.
  public let rawValue: String

  /// Creates a mode from a raw value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Styled: the theme's kind, style, and marker rules all apply.
  public static let live = EditorMode(rawValue: "live")

  /// Raw: every kind, every style combination, and both roles resolve to the theme's
  /// base attributes. Implemented as ``EscriboTheme/strippedToSource()``, so it is
  /// literally a different theme value and not a branch anywhere.
  public static let source = EditorMode(rawValue: "source")
}
