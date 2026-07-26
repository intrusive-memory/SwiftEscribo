/// What a run of text *is* — the first of the two orthogonal axes a span carries.
///
/// The second axis is ``StyleSet`` (how the text is emphasized). Keeping them
/// separate is what stops `***bold italic***` inside dialogue from needing a
/// `.boldItalicDialogue` case: it is `kind: .dialogue, style: [.strong, .emphasis]`.
///
/// This is a struct with static members rather than an enum, deliberately. A public
/// enum is source-breaking to extend — every consumer's exhaustive `switch` stops
/// compiling the day a Fountain construct is added, which would make routine grammar
/// work a major release. Static members on a struct still pattern-match in a `switch`
/// and still require a `default:`, which is exactly the forward compatibility wanted.
/// Adding a member here is a *minor* release; changing what an existing member is
/// emitted for is *major*.
///
/// Raw values are stable API. Never renumber or respell one.
public struct SpanKind: Hashable, Sendable {
  /// The stable identifier for this kind.
  public let rawValue: String

  /// Creates a kind from a raw value.
  ///
  /// Unrecognized kinds are legal by design: the styler resolves an unknown kind to
  /// its base style rather than trapping, so a consumer scanning with a newer core
  /// against an older theme degrades in appearance, never in correctness.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }
}

extension SpanKind {
  /// Plain text carrying no grammatical meaning of its own.
  ///
  /// Spans exactly tile the scanned range, so unstyled text is emitted as a `.text`
  /// span rather than left as a gap. A gap would require a clear-then-restyle pass
  /// and reintroduce the whole class of stale-attribute bugs that total tiling makes
  /// structurally impossible.
  public static let text = SpanKind(rawValue: "text")

  /// An ATX heading — both the `#` run (as `SpanRole/marker`) and the heading text
  /// (as `SpanRole/content`).
  ///
  /// A marker span carries the *same* kind and style as the content it delimits and
  /// differs only in its role, which is how "the hashes show, dimmed, while the
  /// heading renders large" falls out of the data model instead of a special case.
  public static let heading = SpanKind(rawValue: "heading")

  /// A fenced code block — both the fence delimiter runs (as `SpanRole/marker`) and
  /// the code inside them (as `SpanRole/content`).
  public static let codeBlock = SpanKind(rawValue: "codeBlock")

  /// The info string trailing an opening code fence — the `swift` in ```` ```swift ````.
  ///
  /// Distinct from ``codeBlock`` because it is prose about the block rather than code
  /// in it, and because language dispatch reads it.
  public static let codeInfoString = SpanKind(rawValue: "codeInfoString")
}
