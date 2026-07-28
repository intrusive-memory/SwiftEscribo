/// What one line *is* — the semantic half of a scan's output.
///
/// Where ``EscriboSpan`` values become character attributes, line records become
/// paragraph attributes: the editor looks up indents and spacing by
/// `(``element``, ``depth``)` and applies them to ``range``. The split is the answer to
/// "who owns geometry" — an edit that changes only emphasis touches spans; an edit
/// that turns action into a character cue touches both.
///
/// Records are lossless by design. Everything needed to write the line back out
/// verbatim — including its terminator and its forced-element markers — is recoverable
/// from ``range`` and ``contentRange`` against the source text, which is what makes the
/// writer cheap and its idempotence test meaningful.
///
/// There is no public initializer. Records are produced by a scan; a caller fabricating
/// one could not supply a ``startState`` anyway, since that type is opaque.
public struct LineRecord: Equatable, Sendable {
  /// The line's zero-based index in the document.
  public let index: Int

  /// The line's full extent in **UTF-16 code units**, *including its terminator*.
  ///
  /// Two code units for `\r\n`, one for `\n` or a lone `\r`, and zero for the final
  /// line of a document that ends without one. Terminators are never normalized, so a
  /// scanner that assumes a terminator is one code unit breaks every offset after the
  /// first CRLF.
  ///
  /// Summing the ranges of every line reconstructs the source byte for byte.
  public let range: Range<Int>

  /// The line's payload in **UTF-16 code units**, *excluding* leading indent, syntax
  /// markers, and the terminator.
  ///
  /// For `  ## Heading\n` this is the extent of `Heading` — not the indent, not the
  /// `## `, not the `\n`. Always a subrange of ``range``. Empty for a blank line.
  ///
  /// Stated explicitly against ``range`` because leaving the terminator's membership
  /// ambiguous guarantees an off-by-one at every call site.
  public let contentRange: Range<Int>

  /// The line's classification, which keys its paragraph geometry.
  public let element: ElementKind

  /// The multi-line grammar state this line begins in — the convergence key.
  ///
  /// Opaque. Comparing two of these is the only thing a caller can do with one, and is
  /// the only thing anyone needs to.
  public let startState: LineState

  /// Nesting depth: list nesting level, section depth, heading level.
  ///
  /// Carried here rather than encoded in ``element`` so that geometry keyed by
  /// `(ElementKind, depth)` covers all six heading levels — and any list depth — with
  /// one entry shape. Zero for anything unnested.
  public let depth: Int

  /// The column alignments a GFM table **delimiter row** declares, left to right. Empty
  /// on every other line.
  ///
  /// This is the one thing a table's geometry depends on that neither ``element`` nor
  /// ``depth`` can carry: alignment is per *column*, and both of those are per *line*.
  /// Packing four two-bit fields into `depth` was the alternative and was rejected — it
  /// would make geometry keyed by `(element, depth)` meaningless for tables, which is the
  /// one thing `depth` exists for.
  ///
  /// **Only the delimiter row carries it.** A body row's record has an empty array, and a
  /// consumer that wants to align a cell reads the delimiter row above it. The reason is
  /// the reason every field on ``LineState`` is a scalar: one `LineState` is stored per
  /// line for the whole document, so carrying an alignment array in the state to hand down
  /// to each body row would cost one allocation per line of every document, table or not.
  /// An empty Swift `Array` allocates nothing, so the field itself is free on the
  /// overwhelming majority of lines that have none.
  public let tableAlignments: [TableAlignment]

  /// Creates a line record.
  ///
  /// `internal` on purpose: records are scanner output, and ``startState`` is not
  /// constructible from outside `EscriboCore`.
  init(
    index: Int,
    range: Range<Int>,
    contentRange: Range<Int>,
    element: ElementKind,
    startState: LineState,
    depth: Int = 0,
    tableAlignments: [TableAlignment] = []
  ) {
    self.index = index
    self.range = range
    self.contentRange = contentRange
    self.element = element
    self.startState = startState
    self.depth = depth
    self.tableAlignments = tableAlignments
  }
}
