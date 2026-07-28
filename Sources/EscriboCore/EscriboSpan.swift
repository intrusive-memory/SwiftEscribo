/// A run of text and everything the styler needs to know about it.
///
/// Spans are **flat, non-overlapping, ordered, and totally tiling** — not a tree.
/// Every UTF-16 offset in a scanned range belongs to exactly one span, and plain text
/// is emitted as a ``SpanKind/text`` span rather than left as a gap. That is the
/// model, not a simplification of one:
///
/// 1. It maps 1:1 onto `setAttributes(_:range:)`, which replaces *every* attribute on
///    a range. Total tiling therefore makes stale attributes structurally impossible:
///    no clear-then-restyle pass, no leftover bold after deleting a `*`.
/// 2. Styling is a linear walk — no recursion, no accumulation stack, no allocation
///    per nesting level — on the one path with a per-keystroke budget.
/// 3. Equality is array equality, which is what the incremental-equals-full gate test
///    compares.
///
/// Nesting is flattened at scan time, never resolved at style time: `` **bold `code`
/// bold** `` becomes consecutive spans each carrying the union of the styles covering
/// it.
///
/// Spans are produced for a requested range on demand and are **not** retained for the
/// whole document. The editor only ever needs the range it is about to restyle.
public struct EscriboSpan: Equatable, Sendable {
  /// The span's extent, in **UTF-16 code units** from the start of the document.
  ///
  /// Always UTF-16 offsets — never `String.Index`, never a `Character` count. The
  /// scanner reads `NSTextStorage`, which is `NSString`-backed, so UTF-16 is the only
  /// coordinate space in which an offset means the same thing on both sides of the
  /// seam. A boundary never splits a surrogate pair.
  public let range: Range<Int>

  /// What the run *is* — the first of the two orthogonal axes.
  public let kind: SpanKind

  /// How the run is emphasized — the second axis, carrying the union of every
  /// emphasis covering it.
  public let style: StyleSet

  /// Whether this run is content or the syntax delimiting it.
  ///
  /// A marker span carries the *same* ``kind`` and ``style`` as the content it
  /// delimits and differs only here, which is what makes "the asterisks show, dimmed,
  /// while the word renders bold" a consequence of the data model.
  public let role: SpanRole

  /// Creates a span.
  ///
  /// - Parameters:
  ///   - range: UTF-16 offsets into the document.
  ///   - kind: What the run is.
  ///   - style: The union of emphasis covering the run. Defaults to unstyled.
  ///   - role: Content or marker. Defaults to ``SpanRole/content``, since a run the
  ///     grammar did not identify as syntax is content.
  public init(
    range: Range<Int>,
    kind: SpanKind,
    style: StyleSet = [],
    role: SpanRole = .content
  ) {
    self.range = range
    self.kind = kind
    self.style = style
    self.role = role
  }
}
