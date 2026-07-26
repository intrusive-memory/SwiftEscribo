/// How a run of text is emphasized — the second of the two orthogonal axes a span
/// carries, alongside ``SpanKind``.
///
/// Nesting is flattened at scan time rather than resolved at style time, so a span
/// carries the *union* of every emphasis covering it: the `` `code` `` inside
/// `**bold `code` bold**` is one span with `[.strong, .inlineCode]`.
///
/// Bit positions are API. Adding a member is a minor release precisely because the
/// existing positions never move; renumbering one is a major release and would
/// silently re-render every persisted theme.
public struct StyleSet: OptionSet, Hashable, Sendable {
  /// The bitfield backing this style set.
  public let rawValue: UInt16

  /// Creates a style set from its raw bitfield.
  public init(rawValue: UInt16) {
    self.rawValue = rawValue
  }

  /// Bold. `**x**` or `__x__` in Markdown.
  public static let strong = StyleSet(rawValue: 1 << 0)

  /// Italic. `*x*` or `_x_` in Markdown.
  public static let emphasis = StyleSet(rawValue: 1 << 1)

  /// Struck through. `~~x~~` in GitHub-flavored Markdown.
  public static let strikethrough = StyleSet(rawValue: 1 << 2)

  /// An inline code span. `` `x` `` in Markdown.
  public static let inlineCode = StyleSet(rawValue: 1 << 3)

  /// Underlined. `_x_` in Fountain, which does not share Markdown's reading of that
  /// delimiter — the same characters mean different things per language, which is
  /// exactly why style is a set of flags and not part of the kind.
  public static let underline = StyleSet(rawValue: 1 << 4)
}
