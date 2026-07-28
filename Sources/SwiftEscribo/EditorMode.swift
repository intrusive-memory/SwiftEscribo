/// Whether the editor renders its document styled or raw.
///
/// Switching between the two is a **theme swap, not a content transformation and not a
/// code path** (REQUIREMENTS.md § Source mode is a theme). The document's characters are
/// identical in both modes; only the attributes applied over them change. That is why
/// this type never reaches the styler: ``EditorStyleEnvironment`` resolves a mode plus a
/// theme into one theme, and the styler is handed the result.
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
