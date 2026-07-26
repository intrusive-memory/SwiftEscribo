/// What a *line* is — the semantic classification carried by a line record.
///
/// Where ``SpanKind`` drives character attributes, `ElementKind` drives paragraph
/// geometry: the editor looks up indents and spacing by `(ElementKind, depth)`. The
/// two outputs travel different application paths, which is why they are different
/// vocabularies rather than one shared enum.
///
/// A struct with static members, never an enum, for the same reason as ``SpanKind``:
/// adding a member must be a minor release, not a source break.
public struct ElementKind: Hashable, Sendable {
  /// The stable identifier for this element.
  public let rawValue: String

  /// Creates an element kind from a raw value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }
}

extension ElementKind {
  /// A line of ordinary prose. The default classification — a line the grammar
  /// recognized nothing special about is a paragraph line, not an error.
  public static let paragraph = ElementKind(rawValue: "paragraph")

  /// A line that is empty apart from its terminator.
  ///
  /// Distinct from an empty ``paragraph`` because blank lines are block separators in
  /// both grammars: they end paragraphs in Markdown and dialogue blocks in Fountain.
  public static let blank = ElementKind(rawValue: "blank")

  /// An ATX heading line. The heading level is carried in the line record's `depth`,
  /// not in a separate member per level, so geometry keyed by `(ElementKind, depth)`
  /// covers all six levels with one entry shape.
  public static let heading = ElementKind(rawValue: "heading")

  /// An opening or closing code-fence line. Not code itself — it delimits code — so
  /// it is classified apart from ``codeBlock``.
  public static let codeFence = ElementKind(rawValue: "codeFence")

  /// A line inside a fenced code block.
  public static let codeBlock = ElementKind(rawValue: "codeBlock")
}
