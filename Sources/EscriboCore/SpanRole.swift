/// Whether a span is the text a reader cares about or the syntax that delimits it.
///
/// A marker span carries the **same** ``SpanKind`` and ``StyleSet`` as the content it
/// wraps and differs only in its role. The styler therefore resolves attributes from
/// kind and style, then — if the role is ``marker`` — multiplies the foreground
/// alpha and does nothing else. "The asterisks show, dimmed, while the word renders
/// bold" is then a consequence of the data model rather than a special case, and
/// "dim the marker but keep its metrics" is the path of least resistance. Marker
/// dimming is alpha-only: changing metrics mid-line makes text jitter while typing.
///
/// A struct with static members, not an enum, for consistency with the rest of the
/// span vocabulary and for the same forward-compatibility reason. `Hashable` because
/// the styler's attribute cache is keyed by `(SpanKind, StyleSet, SpanRole)`.
public struct SpanRole: Hashable, Sendable {
  /// The stable identifier for this role.
  public let rawValue: String

  /// Creates a role from a raw value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Text the document is about. The default for any span the grammar does not
  /// identify as syntax.
  public static let content = SpanRole(rawValue: "content")

  /// Syntax that delimits content — the `#` run of a heading, a code fence, an
  /// emphasis delimiter, a forced-element prefix. Never hidden, only dimmed.
  public static let marker = SpanRole(rawValue: "marker")
}
