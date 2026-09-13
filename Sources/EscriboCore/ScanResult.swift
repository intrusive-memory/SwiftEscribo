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

  /// The blocks ``lineRecords`` group into — a writer's units of thought, not the
  /// editor's lines (REQUIREMENTS-1.1.0 § 4).
  ///
  /// A third payload alongside spans and records, applied on a third path: spans become
  /// character attributes, records become paragraph attributes, and blocks drive the
  /// paragraph well's lane, read-aloud's granularity, and the script preview's grouping.
  ///
  /// **Scoped to ``lines``, like everything else here.** On a full scan that is the whole
  /// document and the blocks are the document's. On an *incremental* scan it is the
  /// rescanned window, so the first and last block may be truncated by the window's edge —
  /// a paragraph that begins three lines above the window appears as a paragraph block
  /// starting at the window's first line. A consumer that needs a document-wide answer
  /// keeps its own blocks and splices, exactly as it does for records.
  ///
  /// Empty for a language with no block structure, and empty rather than absent for a
  /// dialect whose grouping has not shipped: nothing downstream may treat "no blocks" as
  /// an error.
  ///
  /// Ordered ascending, and for a non-empty result they tile ``lines`` with no gaps and no
  /// overlaps — every line is in exactly one block, blank runs included. That is what lets
  /// an offset-to-block lookup be a search with no fallback path.
  public let blocks: [EscriboBlock]

  /// How many lines the **whole document** has, as the scanner's line index counts them.
  ///
  /// The one field here that describes the document rather than the scan. Everything else
  /// is scoped to ``lines`` or ``dirtyRange``; this is the denominator those are a fraction
  /// of.
  ///
  /// ## Why a consumer needs it
  ///
  /// A caller retaining its own document-wide picture — the editor's block cache is the
  /// first — has to splice each incremental result into what it already holds, and a splice
  /// needs the **line delta**: an edit that adds or removes a newline moves every line
  /// after it, so blocks past the rescanned window must shift before they are kept.
  /// Comparing this against the value from the previous scan is the only way to know by how
  /// much. Without it a consumer can only detect that its cache *might* be stale, never
  /// repair it, and must re-scan the document to answer anything.
  ///
  /// A document ending in a terminator has a final empty line, and it is counted — the same
  /// convention ``lines`` uses, arrived at from the same line index.
  public let documentLineCount: Int

  /// Creates a scan result.
  ///
  /// `internal` on purpose: a result is scanner output, and ``LineRecord`` is not
  /// constructible from outside `EscriboCore`.
  init(
    dirtyRange: Range<Int>,
    spans: [EscriboSpan],
    lines: Range<Int>,
    lineRecords: [LineRecord],
    blocks: [EscriboBlock] = [],
    documentLineCount: Int = 0
  ) {
    self.dirtyRange = dirtyRange
    self.spans = spans
    self.lines = lines
    self.lineRecords = lineRecords
    self.blocks = blocks
    self.documentLineCount = documentLineCount
  }
}
