/// The grammar a document is scanned with.
///
/// A struct with static members rather than an enum, for the same reason as
/// ``SpanKind`` and ``ElementKind``: adding a language must not break a consumer's
/// exhaustive `switch`.
public struct Language: Hashable, Sendable {
  /// The stable identifier for this language.
  public let rawValue: String

  /// Creates a language from a raw value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }
}

extension Language {
  /// CommonMark, plus the GitHub-flavored extensions and YAML frontmatter.
  ///
  /// Markdown is the only language that hosts another: a fence tagged `fountain` is
  /// scanned with the Fountain grammar at an offset into the outer document.
  public static let markdown = Language(rawValue: "markdown")

  /// Fountain, the plain-text screenplay format. Hosts no other language — it has no
  /// fence syntax — so nesting never goes beyond depth one.
  public static let fountain = Language(rawValue: "fountain")
}
