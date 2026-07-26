/// How one column of a GFM table is aligned, as declared by its cell in the delimiter row.
///
/// A struct with static members rather than an enum, for the reason ``SpanKind`` and
/// ``ElementKind`` are: a public enum is source-breaking to extend, and a consumer's
/// exhaustive `switch` must keep compiling the day a sixth spelling of alignment turns up.
/// Static members still pattern-match in a `switch` and still require a `default:`.
///
/// Backed by a `UInt8` rather than a `String`, unlike the two kind vocabularies. One of
/// these exists per column of every table row scanned, held in an array on
/// ``LineRecord/tableAlignments``, and a `String` raw value would put a retain and a
/// release on each one. Nothing about alignment needs a spelling — it is never matched
/// against source text, only compared and switched on.
///
/// Raw values are stable API. Never renumber one.
public struct TableAlignment: Hashable, Sendable {

  /// The stable identifier for this alignment.
  public let rawValue: UInt8

  /// Creates an alignment from a raw value.
  ///
  /// Unrecognized values are legal by design, for the same reason an unrecognized
  /// ``SpanKind`` is: a consumer reading output from a newer core degrades in appearance,
  /// never in correctness.
  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  /// No alignment declared — `---`. The renderer picks, which in practice means left.
  ///
  /// Distinct from ``left`` on purpose. `---` and `:---` render the same and mean
  /// different things to a writer round-tripping the document, and this package's records
  /// are lossless for the writer (AGENTS.md).
  public static let unspecified = TableAlignment(rawValue: 0)

  /// Left-aligned — `:---`.
  public static let left = TableAlignment(rawValue: 1)

  /// Right-aligned — `---:`.
  public static let right = TableAlignment(rawValue: 2)

  /// Centered — `:---:`.
  public static let center = TableAlignment(rawValue: 3)
}
