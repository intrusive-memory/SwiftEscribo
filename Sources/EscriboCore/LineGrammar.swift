/// One line, as a grammar sees it.
///
/// The code units are read **once per line** through
/// ``UTF16TextSource/copyUTF16CodeUnits(in:into:)`` and handed over as a value, so a
/// grammar never touches the source and never pays a witness-table dispatch per
/// character. ``units`` holds the line's *content* — the terminator is deliberately
/// absent, because no grammar decision may depend on which of the three terminators the
/// line happened to use, and a grammar that cannot see them cannot accidentally branch
/// on them.
struct GrammarLine: Equatable, Sendable {

  /// The line's zero-based index in the document.
  let index: Int

  /// The line's full extent in UTF-16 code units, **including its terminator**.
  let range: Range<Int>

  /// The line's extent **excluding** its terminator. `units` covers exactly this.
  let contentRange: Range<Int>

  /// `2` for `\r\n`, `1` for `\n` or a lone `\r`, `0` for a final line without one.
  let terminatorLength: Int

  /// The content code units, in order. `units[i]` is the unit at `contentRange.lowerBound + i`.
  let units: [UInt16]

  /// Whether the line is empty apart from its terminator.
  ///
  /// This — and only this — is a property of a line's *shape* rather than of any
  /// grammar, which is why it is offered here rather than left to each grammar to
  /// rediscover. Whitespace-only lines are **not** blank by this definition; whether
  /// they should be is a grammar's decision and differs between Markdown and Fountain.
  var isEmpty: Bool { units.isEmpty }
}

/// The current line plus however many lines ahead the grammar declared it may look.
///
/// A window is the *entire* input to ``LineGrammar/scanLine(_:state:)`` besides the
/// incoming ``LineState``, and that is the point: a grammar physically cannot read
/// further ahead than it declared, so the convergence engine's forward rule cannot be
/// invalidated by a grammar quietly peeking one more line. `line(ahead:)` returns `nil`
/// past the declared lookahead and past the end of the document, and those two cases are
/// deliberately indistinguishable — "there is nothing there" is the only answer a
/// grammar is entitled to.
struct LineWindow {

  /// The current line at `0`, followed by up to `lookahead` following lines. Never empty.
  private let lines: [GrammarLine]

  init(_ lines: [GrammarLine]) {
    self.lines = lines
  }

  /// The line being scanned.
  var current: GrammarLine { lines[0] }

  /// The line `distance` lines after ``current``, or `nil` if that line does not exist
  /// or lies past the grammar's declared lookahead.
  ///
  /// - Parameter distance: `1` is the next line. `0` and below return `nil`; ask for
  ///   ``current`` by name.
  func line(ahead distance: Int) -> GrammarLine? {
    guard distance >= 1, distance < lines.count else { return nil }
    return lines[distance]
  }
}

/// What scanning one line produced.
///
/// Every field is advisory except ``endState``: the engine clamps ``contentRange`` into
/// the line, floors ``depth`` at zero, and repairs ``spans`` into an exact tiling of the
/// line. A grammar therefore cannot break ``ScanResult``'s invariants no matter how
/// wrong it is — which is the property that lets grammars be written quickly and
/// reviewed cheaply.
struct LineScan {

  /// The spans this line contributes.
  ///
  /// They need not cover the line and need not be sorted: gaps are filled with
  /// ``SpanKind/text``, overlaps are trimmed, and anything outside the line is clipped.
  /// Emitting nothing is legal and yields one `.text` span for the whole line, which is
  /// exactly how "malformed constructs degrade to text" is implemented — by doing
  /// nothing.
  var spans: [EscriboSpan]

  /// The line's classification.
  var element: ElementKind

  /// The line's payload, excluding indent, markers, and terminator. Clamped into the
  /// line's range by the engine; defaults to the whole line minus its terminator.
  var contentRange: Range<Int>?

  /// List nesting or section depth. Negative values are floored to zero.
  var depth: Int

  /// The state the **next** line begins in.
  ///
  /// This is the convergence key, and it must be exact: it has to carry everything that
  /// affects how the following line scans. A state that omits one field converges early,
  /// which is the single defect class the incremental design exists to prevent.
  var endState: LineState

  init(
    spans: [EscriboSpan] = [],
    element: ElementKind,
    contentRange: Range<Int>? = nil,
    depth: Int = 0,
    endState: LineState
  ) {
    self.spans = spans
    self.element = element
    self.contentRange = contentRange
    self.depth = depth
    self.endState = endState
  }
}

/// A grammar: a per-line scan step plus the two numbers the convergence engine needs
/// from it.
///
/// ## Why a grammar is a *line* function
///
/// The whole incremental design rests on a document being scannable as a fold over its
/// lines — `(state, line) -> (spans, state)` — because that is what makes "resume from
/// line *n* with the state line *n* began in" meaningful. A grammar that needed the
/// whole document could still be correct on a full parse and could never be correct
/// while typing.
///
/// ## Access level
///
/// `internal`, and it must stay that way. A conformer has to produce a ``LineState``,
/// and `LineState`'s initializer is `internal` on purpose (REQUIREMENTS.md § What is
/// public in 1.0 makes the type public but opaque). A public grammar protocol would
/// therefore force `LineState`'s shape into the public API and freeze the scanner's
/// internals at 1.0 — the exact outcome the opacity exists to prevent. Grammars ship as
/// ``Language`` values instead: the caller names a language, `EscriboCore` owns the
/// grammar behind it.
protocol LineGrammar {

  /// How many lines **past** the line being scanned this grammar may read.
  ///
  /// Zero means the line is self-contained given its incoming state. One means the
  /// line's classification depends on what follows it — Fountain's character cue is the
  /// canonical case: an ALL-CAPS line is a cue only by virtue of the next line being
  /// non-empty (REQUIREMENTS.md § Fountain 4).
  ///
  /// The engine consults this value in two places, and it is a value rather than a
  /// constant in both:
  ///
  /// 1. It sizes the ``LineWindow`` handed to ``scanLine(_:state:)``.
  /// 2. It extends the incremental rescan this many lines **past** the line where state
  ///    converged. Stopping at the convergence point when the grammar looks ahead leaves
  ///    the lines whose output was decided by the edited text unrepainted — "correct on
  ///    full parse, wrong while typing".
  var lookahead: Int { get }

  /// How many lines **before** the first edited line rescanning must start.
  ///
  /// This is a language property, not a constant (REQUIREMENTS.md Architecture §5): a
  /// grammar that looks *ahead* `n` lines has, symmetrically, `n` lines behind any edit
  /// whose output the edit may have changed. The default implementation is therefore
  /// `max(1, lookahead)`, and the engine floors whatever a grammar declares at `1` —
  /// see ``IncrementalScanner/backwardWidening`` for why one line is the floor even for
  /// a grammar that looks nowhere.
  var backwardExtent: Int { get }

  /// Scans one line.
  ///
  /// - Parameters:
  ///   - window: The line to scan, plus up to ``lookahead`` lines after it.
  ///   - state: The state this line begins in.
  /// - Returns: The line's spans, classification, and the state the next line begins in.
  ///
  /// Total by construction: no `throws`, no optional, no error path. An unterminated or
  /// malformed construct is scanned as text and, if it is multi-line, carried in the
  /// returned state until the end of the document.
  func scanLine(_ window: LineWindow, state: LineState) -> LineScan
}

extension LineGrammar {
  var backwardExtent: Int { max(1, lookahead) }
}
