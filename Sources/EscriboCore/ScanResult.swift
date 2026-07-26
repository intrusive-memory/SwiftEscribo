/// Everything one scan produces: what to restyle, and what to restyle it with.
///
/// The two payloads drive two different application paths. ``spans`` become character
/// attributes on ``dirtyRange``; ``lineRecords`` become `NSParagraphStyle` on their
/// own line ranges. Keeping them in one result keeps them in one transaction.
///
/// The invariants below are the type's contract. Assembling a result that satisfies
/// them is the scanner's job and the invariant harness enforces them, but they are
/// documented here so that nobody downstream ever treats a violation as legal input:
///
/// 1. ``spans`` are ordered, non-overlapping, contiguous, and **exactly tile**
///    ``dirtyRange``. The first begins at `dirtyRange.lowerBound`, the last ends at
///    `dirtyRange.upperBound`, and each begins where its predecessor ended. Plain text
///    is a ``SpanKind/text`` span, never a gap — a gap would force a clear-then-restyle
///    pass and reintroduce stale-attribute bugs.
/// 2. ``dirtyRange`` **contains the edited range** and is **line-aligned at both ends**.
///    Line alignment is required because paragraph attributes are per-paragraph;
///    applying them to a partial paragraph produces layout that depends on where the
///    range happened to start.
/// 3. ``dirtyRange`` may be much larger than the edit — an edit can change how the rest
///    of the document scans — and is never smaller.
/// 4. ``lineRecords`` covers ``lines`` completely, in order, with no gaps: one record
///    per index in `lines`, in ascending index order.
///
/// Scanning never fails. There is no `throws` and no optional here: malformed and
/// hostile input degrades to ``SpanKind/text`` and still produces a total tokenization.
public struct ScanResult: Equatable, Sendable {
  /// The range whose character attributes must be reapplied, in **UTF-16 code units**.
  ///
  /// Line-aligned at both ends, and a superset of the range that was edited.
  public let dirtyRange: Range<Int>

  /// The spans covering ``dirtyRange``, exactly tiling it in order.
  public let spans: [EscriboSpan]

  /// The half-open range of **line indices** that were rescanned.
  ///
  /// Line indices, not code-unit offsets — the one range in this type that is not a
  /// UTF-16 coordinate.
  public let lines: Range<Int>

  /// One record per line index in ``lines``, in ascending order.
  public let lineRecords: [LineRecord]

  /// Creates a scan result.
  ///
  /// `internal` on purpose: a result is scanner output, and ``LineRecord`` is not
  /// constructible from outside `EscriboCore`.
  init(
    dirtyRange: Range<Int>,
    spans: [EscriboSpan],
    lines: Range<Int>,
    lineRecords: [LineRecord]
  ) {
    self.dirtyRange = dirtyRange
    self.spans = spans
    self.lines = lines
    self.lineRecords = lineRecords
  }
}
