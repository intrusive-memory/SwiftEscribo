/// The convergence engine: the one algorithm every grammar in this package depends on.
///
/// A scanner owns a ``LineIndex`` and one ``LineState`` per line, and turns a document
/// plus a stream of ``TextEdit`` values into ``ScanResult`` values. It is grammar-
/// agnostic — everything language-specific arrives through ``LineGrammar`` — which is
/// what lets the hard part be written and tested once instead of once per language.
///
/// ## The two entry points
///
/// - ``fullScan(_:)`` scans a document from ``LineState/documentStart``.
/// - ``incrementalScan(_:in:)`` takes an edit in **old-text coordinates** and rescans
///   the smallest line window that can be proved sufficient.
///
/// Both are total: no `throws`, no `async`, no optional result, and no `precondition` on
/// the scan path (REQUIREMENTS.md § Concurrency and failure). Out-of-range edits are
/// clamped, a scanner used before any full scan behaves as if the document were empty,
/// and an unterminated construct scans to the end of the document. There is no error
/// path because there is nothing an error could mean: every byte sequence is a document.
///
/// ## The rescan window, stated exactly
///
/// Given an edit, rescanning covers lines `start..<stop`:
///
/// - `start = max(0, firstEditedLine - backwardWidening)` — see ``backwardWidening``.
/// - `stop` is the first line at which **all three** convergence conditions hold, plus
///   the grammar's declared ``LineGrammar/lookahead`` lines — see ``hasConverged``.
///   If they never hold, `stop` is the end of the document.
///
/// Lines before `start` are untouched. Lines at or after `stop` keep the states they
/// already had; their text is unchanged and they begin in a state that was just proved
/// identical, so rescanning them could only reproduce what they already say.
///
/// ## What it deliberately does not do
///
/// It does not retain spans for the whole document. Spans exist only for the range the
/// editor is about to restyle (REQUIREMENTS.md § Spans), so the only thing carried
/// across edits is one `LineState` per line — small, `Equatable`, and the only thing
/// convergence needs.
/// The longest block whose inline pass runs over **joined** content. Longer blocks fall
/// back to line-scoped inline scanning.
///
/// A block-scoped inline pass costs one rescan of the whole block per keystroke inside it,
/// because an edit on any line can change how every other line pairs. A blank line bounds
/// a block and therefore bounds the cost — but a pathological document has no blank line,
/// and there the cost is unbounded.
///
/// Two hundred lines, because real hard-wrapped prose paragraphs are five to twenty lines
/// and nobody's emphasis spans two hundred. Above that the pairing a writer would notice
/// has certainly already closed, and the reading a block-scoped pass would add is one
/// nobody intended.
///
/// It is a guard against a pathological document, **not** a correctness boundary: crossing
/// it degrades to the 0.3.0 behaviour, which is a worse reading of the same text, never a
/// broken one. This codebase already tolerates unbounded dirty ranges where correctness
/// demands them — opening a fence on line 1 of a 500-line document dirties it to the end,
/// and that is a green test. The difference is that a fence *has* to dirty the rest and a
/// two-hundred-line emphasis pair does not.
///
/// One named constant so it is tunable in one place and its reasoning survives.
let joinedContentLineLimit = 200

/// The block kinds whose content is re-scanned as one run.
///
/// Paragraphs, blockquotes, and list items — the three things a writer hard-wraps. A
/// heading is one line, so there is nothing of it to join; a table must never join,
/// because a delimiter in a header cell pairing with one in a body cell is not something
/// CommonMark does; frontmatter and code are not prose. Grouping decides the extents (see
/// ``EscriboBlockGrouper``) and this decides which of them are eligible.
///
/// At file scope rather than on ``IncrementalScanner``, because Swift does not allow a
/// static stored property in a generic type — and it belongs here anyway: the set is a
/// property of this file's logic, not of any one grammar instantiation, and building it
/// once beats rebuilding it per access on the scan path.
private let joinableBlockKinds: Set<BlockKind> = [.paragraph, .blockquote, .listItem]

struct IncrementalScanner<Grammar: LineGrammar> {

  /// The grammar every line is scanned with.
  let grammar: Grammar

  /// Where the lines are. Adjusted incrementally, never rebuilt on an edit.
  private(set) var index: LineIndex

  /// The state each line begins in — `startStates[i]` for line `i`. Exactly
  /// `index.lineCount` entries, always.
  ///
  /// This is the entire memory the scanner carries between edits, and the reason
  /// convergence can be decided by comparing one value instead of re-deriving a
  /// document.
  ///
  /// Readable but not writable: a scan of a long document after a hundred edits must be
  /// indistinguishable from a full scan of the same text, and that is asserted by
  /// comparing this array — the only place a divergence can hide once spans and records
  /// have been checked.
  private(set) var startStates: [LineState]

  /// Creates a scanner over an empty document.
  ///
  /// Call ``fullScan(_:)`` before the first ``incrementalScan(_:in:)``. Skipping it is
  /// not a trap — the scanner simply believes the document was empty, and the resulting
  /// scan is a well-formed `ScanResult` for a document it has wrong. Totality here is
  /// worth more than a `precondition`, which would turn a caller's sequencing bug into a
  /// crash inside a text-view delegate callback.
  init(grammar: Grammar) {
    self.grammar = grammar
    self.index = LineIndex("")
    self.startStates = [.documentStart]
  }

  /// How many lines before the first edited line rescanning starts. Never below one.
  ///
  /// **This is not ``LineIndex``'s backward-widening rule and must never be conflated
  /// with it.** `LineIndex` widens back one line because a `\r` and an `\n` on opposite
  /// sides of the rescan boundary would otherwise be split into two terminators; that is
  /// a code-unit argument with a proof attached, and one line is provably exactly
  /// enough. This rule is about *grammar state*: a line's classification can depend on
  /// the lines after it, so an edit can change how an **earlier** line scans without
  /// touching a single code unit of it. Fountain is the standing example — `BOB`
  /// followed by a blank line is action, and typing a word on the following line
  /// retroactively makes it a character cue.
  ///
  /// The floor of one line holds even for a grammar that declares zero lookahead,
  /// because the edit may have deleted the terminator that separated two lines: the
  /// "first edited line" is then a line that no longer exists in the form the index
  /// described, and starting one line back is the cheapest way to be sure the line the
  /// edit landed in is scanned from its true beginning.
  var backwardWidening: Int { max(1, grammar.backwardExtent, grammar.lookahead) }

  // MARK: - Entry points

  /// Scans `source` in full, from ``LineState/documentStart``.
  ///
  /// Resets everything the scanner carries. The returned result covers every line, and
  /// its ``ScanResult/dirtyRange`` is the whole document.
  @discardableResult
  mutating func fullScan(_ source: some UTF16TextSource) -> ScanResult {
    index = LineIndex(source)
    let scan = scanLines(from: 0, incoming: .documentStart, in: source, convergence: nil)
    startStates = scan.states
    return scan.result
  }

  /// Applies `edit` and rescans the smallest sufficient window.
  ///
  /// - Parameters:
  ///   - edit: The mutation, in **old-text coordinates** — see ``TextEdit``. Its `range`
  ///     indexes the document as this scanner currently describes it, and its length
  ///     delta is read from ``TextEdit/changeInLength`` rather than recomputed.
  ///   - source: The document **after** the edit.
  /// - Returns: A result whose ``ScanResult/dirtyRange`` is line-aligned at both ends and
  ///   contains the edited range, and whose spans exactly tile it.
  @discardableResult
  mutating func incrementalScan(_ edit: TextEdit, in source: some UTF16TextSource) -> ScanResult {
    // Everything in this block is read in OLD coordinates, before the index moves.
    let oldLineCount = index.lineCount
    let previousStates = startStates
    let editStart = min(max(edit.range.lowerBound, 0), index.utf16Count)
    let firstEditedLine = index.lineIndex(containing: editStart)
    let startLine = max(0, firstEditedLine - backwardWidening)

    index.apply(edit, to: source)

    let newLineCount = index.lineCount
    let editEnd = min(max(editStart + max(0, edit.replacementLength), editStart), index.utf16Count)
    let convergence = Convergence(
      previousStates: previousStates,
      // Positive when the edit added lines, negative when it removed them. New line `j`
      // is old line `j - lineDelta` — but only past `firstComparableLine`, which is why
      // the two travel together.
      lineDelta: newLineCount - oldLineCount,
      firstComparableLine: index.lineIndex(containing: editEnd) + 1,
      editEnd: editEnd
    )

    // A block-scoped inline pass makes an edit on any line of a block able to change how
    // every other line of that block pairs, so when the pass will run the window has to
    // cover the whole block — and one line past it on each side, so the block is strictly
    // interior and `rescanJoinedBlocks` can tell it was not truncated.
    //
    // **Widen only when the pass will actually run.** `joinableRun` answers that with a
    // scalar walk before anything is rescanned, so a run past the backstop costs one cheap
    // probe and then keeps the 0.3.0 window. Widening it would buy a 400-line rescan for a
    // pass that is about to be skipped, which is what broke `ordinaryEditsStayLocal`.
    //
    // Both ends of the edit are probed: a multi-line paste can begin in one run and end in
    // another, and widening for a joinable head while the tail's run is over the limit
    // would leave the tail's blocks truncated.
    var windowFloor = startLine
    var windowCeiling = 0
    if grammar.joinsBlockContent {
      let lastLine = max(0, convergence.firstComparableLine - 1)
      let head = joinableRun(
        containing: min(firstEditedLine, max(0, newLineCount - 1)), in: source)
      let tail = joinableRun(containing: min(lastLine, max(0, newLineCount - 1)), in: source)
      // Both ends of the edit are probed, and both must be joinable: a multi-line paste can
      // begin in one run and end in another, and widening for a joinable head while the
      // tail's run is declined would leave the tail's blocks truncated.
      if head.isJoinable, tail.isJoinable {
        // Exactly the runs, with no padding. The completeness test above recognizes a block
        // that ends where its run ends, so there is no need to buy a spare line on each
        // side — and those two lines are the difference between passing the DL-138 window
        // budget and blowing it.
        windowFloor = min(startLine, head.lines.lowerBound)
        windowCeiling = min(index.lineCount, tail.lines.upperBound)
      }
    }

    // Whatever the floor works out to, it survives the edit unchanged — every line before
    // it is entirely before the edit, so its text and, inductively, the state it began in
    // are untouched. The clamp is belt and braces: it cannot bind, because the lines below
    // the edit are exactly the lines an edit cannot move.
    let start = min(windowFloor, newLineCount - 1)
    let incoming = start < previousStates.count ? previousStates[start] : .documentStart
    let scan = scanLines(
      from: start, incoming: incoming, in: source, convergence: convergence,
      minimumStop: windowCeiling)
    startStates = rebuiltStates(
      scanned: scan.states,
      from: start,
      previous: previousStates,
      convergence: convergence,
      newLineCount: newLineCount
    )
    return scan.result
  }

  // MARK: - Convergence

  /// What ``joinableRun(containing:in:)`` found.
  private struct JoinableRun {
    /// The extent walked: the whole run, or a prefix of it when the walk hit the limit.
    let lines: Range<Int>

    /// Whether the joined inline pass should run over the blocks inside ``lines``.
    let isJoinable: Bool
  }

  /// What the forward rule needs to know about the edit that just landed.
  private struct Convergence {
    /// The states from before the edit, indexed by **old** line number.
    let previousStates: [LineState]

    /// `newLineCount - oldLineCount`. New line `j` is old line `j - lineDelta`.
    let lineDelta: Int

    /// The first line whose text the edit provably did not touch: one past the line
    /// containing the edit's end in new coordinates.
    let firstComparableLine: Int

    /// The end of the edited range in **new** coordinates.
    let editEnd: Int
  }

  /// Whether rescanning may stop before line `line`, which begins in `state`.
  ///
  /// The rule, in full, and all three parts are load-bearing:
  ///
  /// 1. **The edit is behind us, in lines.** `line >= firstComparableLine`, which is one
  ///    past the line containing the edit's end. Below that threshold the text differs
  ///    from what produced `previousStates`, so there is nothing meaningful to compare
  ///    against — and the old-to-new line mapping is not even defined, because the edit
  ///    may have added or removed lines inside the region.
  /// 2. **The edit is behind us, in code units.** `line`'s first code unit is at or after
  ///    the edit's end. Condition 1 is stated in lines and this one in offsets; they
  ///    agree on every input the author could construct, and keeping both means a future
  ///    change to either coordinate system cannot silently weaken the rule.
  /// 3. **The state matches.** The recomputed state entering `line` equals the state the
  ///    previous scan recorded for the same line of text. `LineState`'s `==` is real,
  ///    total equality; a state that omits a field satisfies this early and produces
  ///    exactly the "correct on full parse, wrong while typing" defect the whole design
  ///    exists to prevent.
  ///
  /// State equality **alone** is not convergence, and this is the mistake worth naming:
  /// with a grammar whose state is uniform — one that classifies lines by their own
  /// content — condition 3 is true at every boundary, including the boundary
  /// immediately before the edited line. A loop that stopped there would rescan one line
  /// and repaint nothing that changed.
  ///
  /// The grammar's declared ``LineGrammar/lookahead`` does **not** appear here. It is
  /// applied by the caller of this method, which continues for `lookahead` further lines
  /// after the first line where all three conditions hold — see ``scanLines(from:incoming:in:convergence:)``.
  private func hasConverged(at line: Int, state: LineState, _ convergence: Convergence) -> Bool {
    // Past the last line there is nothing to converge to; the loop is about to end on
    // its own. Checked here rather than at the call site so that no caller can reach
    // `index.line(at:)` with an out-of-range line — this is the scan path, and the scan
    // path does not trap.
    guard line < index.lineCount else { return false }
    guard line >= convergence.firstComparableLine else { return false }
    guard index.line(at: line).range.lowerBound >= convergence.editEnd else { return false }
    let previousLine = line - convergence.lineDelta
    guard previousLine >= 0, previousLine < convergence.previousStates.count else { return false }
    return state == convergence.previousStates[previousLine]
  }

  // MARK: - The scanning loop

  /// Scans forward from `startLine` until convergence, or to the end of the document.
  ///
  /// - Parameter convergence: `nil` for a full scan, which never stops early.
  /// - Returns: The assembled result, and the start state of every line scanned.
  private func scanLines(
    from startLine: Int,
    incoming: LineState,
    in source: some UTF16TextSource,
    convergence: Convergence?,
    minimumStop: Int = 0
  ) -> (result: ScanResult, states: [LineState]) {
    let lineCount = index.lineCount
    let lookahead = max(0, grammar.lookahead)

    // One array per line rather than one flat array, because the joined-content pass below
    // replaces a whole line's spans and needs to find them. Flattened on the way out, in
    // line order, so the result still tiles `dirtyRange` exactly.
    var lineSpans: [[EscriboSpan]] = []
    // The marker half of each line's spans, kept untiled so the joined pass can re-tile a
    // line as `markers + joined inline` and leave its `> ` or `- ` exactly as the grammar
    // emitted it. Cheap to hold: zero to two small values per line, against the line's own
    // text, which is deliberately never retained.
    var lineMarkers: [[EscriboSpan]] = []
    var records: [LineRecord] = []
    var states: [LineState] = []
    var state = incoming
    var line = startLine

    // The window holds the current line at `[0]` and up to `lookahead` lines after it.
    // Each line is read from the source exactly once, no matter how many windows it
    // appears in — the reason the window is carried rather than rebuilt per line.
    var window: [GrammarLine] = []
    var nextToRead = startLine

    /// The exclusive line at which to stop, once convergence has fixed it. `nil` while
    /// still searching.
    var stopLine: Int?

    while line < lineCount {
      let lastNeeded = min(line + lookahead, lineCount - 1)
      while nextToRead <= lastNeeded {
        window.append(grammarLine(at: nextToRead, in: source))
        nextToRead += 1
      }

      let current = window[0]
      let entering = state
      let scan = grammar.scanLine(LineWindow(window), state: entering)

      states.append(entering)
      records.append(
        LineRecord(
          index: current.index,
          range: current.range,
          contentRange: clamped(scan.contentRange ?? current.contentRange, into: current.range),
          element: scan.element,
          startState: entering,
          depth: max(0, scan.depth),
          tableAlignments: scan.tableAlignments
        ))
      lineMarkers.append(scan.spans)
      lineSpans.append(
        SpanTiling.tile(
          scan.spans + scan.inlineSpans,
          into: current.range,
          contentUnits: current.units,
          contentStart: current.contentRange.lowerBound
        ))

      state = scan.endState
      window.removeFirst()
      line += 1

      if let stop = stopLine {
        if line >= stop { break }
      } else if let convergence, line >= minimumStop,
        hasConverged(at: line, state: state, convergence)
      {
        // The forward rule's third clause: converged, but keep going for as many lines
        // as the grammar declared it looks ahead. Those lines had the edited text inside
        // their window on the previous scan — or, for a grammar whose lookahead is not
        // fully reflected in its state, may have — and repainting them costs `lookahead`
        // lines while omitting them costs a wrong screen.
        let stop = min(lineCount, line + lookahead)
        if line >= stop { break }
        stopLine = stop
      }
    }

    // Grouping happens once, here, and feeds both the joined inline pass and the result.
    let blocks = EscriboBlockGrouper.blocks(from: records, dialect: grammar.blockDialect)
    if grammar.joinsBlockContent {
      rescanJoinedBlocks(
        blocks, records: records, markers: lineMarkers, lineSpans: &lineSpans, in: source)
    }
    let spans = lineSpans.flatMap { $0 }

    let lines = startLine..<line
    let dirtyRange: Range<Int>
    if let first = records.first, let last = records.last {
      // Line-aligned at both ends by construction: both bounds come from line geometry,
      // never from the edit. Containment of the edited range follows from the window —
      // `startLine` is at or before the line the edit begins in, and convergence cannot
      // trigger before `firstComparableLine`, which is past the line the edit ends in.
      dirtyRange = first.range.lowerBound..<last.range.upperBound
    } else {
      let edge = min(
        max(
          startLine < lineCount ? index.line(at: startLine).range.lowerBound : index.utf16Count, 0),
        index.utf16Count)
      dirtyRange = edge..<edge
    }

    return (
      ScanResult(
        dirtyRange: dirtyRange, spans: spans, lines: lines, lineRecords: records,
        // Grouping is a pure function of the records, so it runs here for both entry
        // points and there is no second code path for the incremental case to drift from.
        // On an incremental scan it groups the window, which is what `ScanResult.blocks`
        // documents it as.
        blocks: blocks),
      states
    )
  }

  // MARK: - State bookkeeping

  /// Splices the freshly computed states into the states carried from before the edit.
  ///
  /// Three regions, and the middle one is the only one that was recomputed:
  ///
  /// - Before `start`: unchanged, and at unchanged line numbers.
  /// - `start..<start + scanned.count`: the rescan.
  /// - After the rescan: carried over from old line `j - lineDelta`, whose text is
  ///   identical and whose state was just proved identical at the join.
  ///
  /// Every lookup is bounds-checked rather than asserted. A mismatch cannot happen given
  /// how the callers compute their arguments, and if it ever did, a scanner that quietly
  /// reverts a line to ``LineState/documentStart`` produces a wrong repaint that the next
  /// keystroke corrects — where a trap would take the host application down.
  private func rebuiltStates(
    scanned: [LineState],
    from start: Int,
    previous: [LineState],
    convergence: Convergence,
    newLineCount: Int
  ) -> [LineState] {
    var states = [LineState](repeating: .documentStart, count: newLineCount)
    for line in 0..<min(start, newLineCount) where line < previous.count {
      states[line] = previous[line]
    }
    for (offset, state) in scanned.enumerated() where start + offset < newLineCount {
      states[start + offset] = state
    }
    for line in min(start + scanned.count, newLineCount)..<newLineCount {
      let previousLine = line - convergence.lineDelta
      if previousLine >= 0, previousLine < previous.count {
        states[line] = previous[previousLine]
      }
    }
    return states
  }

  // MARK: - The joined-content inline pass

  /// Re-scans every joinable block's inline structure over the block's **joined** content
  /// and swaps the result in for those lines, leaving their block markers untouched.
  ///
  /// ## Why it runs here and not in the grammar
  ///
  /// A block is unbounded in length, and ``LineWindow`` physically prevents a grammar from
  /// reading more than ``LineGrammar/lookahead`` lines ahead and any at all behind. That
  /// limit is what makes the forward convergence rule sound, so it is not negotiable. The
  /// scanner, by contrast, has every record for the window already built — so this is the
  /// first point at which a block's whole content is knowable.
  ///
  /// ## How the markers survive
  ///
  /// Each line is re-tiled as `markers + joined inline spans`, where `markers` is exactly
  /// what the grammar put in ``LineScan/spans`` for that line and the joined spans replace
  /// what it put in ``LineScan/inlineSpans``. Nothing infers which is which after the fact,
  /// because nothing can — see `LineScan.inlineSpans` for why role and kind both fail to
  /// separate them. For a paragraph the marker array is empty, which is why paragraphs
  /// could ship a sortie ahead of containers.
  ///
  /// ## What is skipped, and why each skip is safe
  ///
  /// - **Blocks of one line.** Joining one piece reproduces the line-scoped spans exactly,
  ///   so skipping makes a single-line block **byte-identical** to 0.3.0.
  /// - **Blocks the window truncated.** A block that begins at the window's first line, or
  ///   ends at its last, may continue outside it — so a full scan would join more lines
  ///   than are here, and joining the fragment would make the two disagree. A block is
  ///   known-complete when it ends where its run ends (runs are blank-delimited, so nothing
  ///   can extend it) or when the grouper saw the line past it and ended the block there
  ///   anyway. Same test at the start. A fail-safe rather than a live path: the widening in
  ///   ``incrementalScan(_:in:)`` makes every joinable block strictly interior, so if this
  ///   guard fires it turns an under-widening bug into a loud convergence-gate failure
  ///   instead of silently wrong spans.
  /// - **Blocks in a run past the backstop.** Decided by ``joinableRun(containing:in:)``,
  ///   the same predicate the rescan window uses, so the two cannot disagree about which
  ///   blocks join.
  /// - **Blocks holding a line with no content at all.** A `>` on its own inside a
  ///   blockquote is a blank line *within* the container: CommonMark ends the paragraph
  ///   there, so joining across it would pair delimiters the spec keeps apart. Grouping
  ///   still puts those lines in one block — that rule is committed, and correct for the
  ///   well's purposes — so declining here is how the inline pass disagrees with it without
  ///   changing it. Paragraph blocks never reach this, because a blank line is its own
  ///   block.
  /// - **Blocks holding a line the grammar will not name a content kind for.** The honest
  ///   answer for an element nobody has considered yet.
  private func rescanJoinedBlocks(
    _ blocks: [EscriboBlock],
    records: [LineRecord],
    markers: [[EscriboSpan]],
    lineSpans: inout [[EscriboSpan]],
    in source: some UTF16TextSource
  ) {
    guard let windowStart = records.first?.index else { return }
    let windowEnd = (records.last?.index).map { $0 + 1 } ?? windowStart
    // One probe per run rather than per block: blocks arrive in ascending order, so a run's
    // blocks are contiguous and the verdict is reused across them. Without this, a document
    // that is one long non-blank run of many short blocks would re-walk the run once per
    // block on every full scan.
    var probed: JoinableRun?

    for block in blocks where joinableBlockKinds.contains(block.kind) {
      guard block.lines.count > 1 else { continue }

      let run: JoinableRun
      if let probed, probed.lines.contains(block.lines.lowerBound) {
        run = probed
      } else {
        run = joinableRun(containing: block.lines.lowerBound, in: source)
        probed = run
      }
      guard run.isJoinable else { continue }

      let completeAtStart =
        block.lines.lowerBound == run.lines.lowerBound || block.lines.lowerBound > windowStart
      let completeAtEnd =
        block.lines.upperBound == run.lines.upperBound || block.lines.upperBound < windowEnd
      guard completeAtStart, completeAtEnd else { continue }

      var pieces: [ContentPiece] = []
      var targets: [JoinTarget] = []
      var usable = true

      for lineIndex in block.lines {
        let slot = lineIndex - windowStart
        guard slot >= 0, slot < records.count, slot < markers.count,
          records[slot].index == lineIndex,
          let kind = grammar.joinedContentKind(for: records[slot].element)
        else {
          usable = false
          break
        }
        let record = records[slot]
        // A content-free line inside a container is a paragraph break there — see above.
        // Decline the whole block rather than join across it.
        guard !record.contentRange.isEmpty else {
          usable = false
          break
        }
        // Re-read rather than retain: holding every line's code units for the window would
        // make a full scan carry the whole document's text, which is the one thing this
        // scanner is careful never to do.
        let line = grammarLine(at: lineIndex, in: source)
        let lower = record.contentRange.lowerBound - line.contentRange.lowerBound
        let upper = record.contentRange.upperBound - line.contentRange.lowerBound
        guard lower >= 0, upper >= lower, upper <= line.units.count else {
          usable = false
          break
        }
        pieces.append(
          ContentPiece(
            documentRange: record.contentRange,
            units: Array(line.units[lower..<upper]),
            kind: kind))
        targets.append(
          JoinTarget(
            slot: slot, lineRange: record.range, units: line.units,
            contentStart: line.contentRange.lowerBound))
      }
      guard usable, pieces.count > 1 else { continue }

      let joined = grammar.joinedBlockSpans(pieces)
      for target in targets {
        // Content ranges of distinct lines are disjoint and each sits inside its own line,
        // so testing the lower bound partitions the joined spans by line exactly. The
        // markers go back in front of them, unchanged.
        lineSpans[target.slot] = SpanTiling.tile(
          markers[target.slot] + joined.filter { target.lineRange.contains($0.range.lowerBound) },
          into: target.lineRange,
          contentUnits: target.units,
          contentStart: target.contentStart)
      }
    }
  }

  /// One line of a block the joined pass is about to rewrite.
  ///
  /// A named type rather than a tuple: four members is past the point where positional
  /// access reads clearly, and three of them are integers or ranges that would silently
  /// accept one another's values.
  private struct JoinTarget {
    /// The line's index into the window's parallel arrays.
    let slot: Int

    /// The line's full extent, terminator included — what the re-tiling must cover.
    let lineRange: Range<Int>

    /// The line's content code units, for the tiler's surrogate-pair alignment.
    let units: [UInt16]

    /// The document offset ``units`` begins at.
    let contentStart: Int
  }

  /// What the joined inline pass needs to know about the non-blank run containing `line`:
  /// how far it reaches, and whether joining it could change anything.
  ///
  /// This is the **one** joinability predicate. Both the joined pass and the rescan window
  /// ask it, which is what makes an incremental scan produce the spans a full scan of the
  /// same text would. If the two used different rules, a window that joined a block the
  /// full scan declined to join would disagree, and the convergence gate would be right to
  /// fail.
  ///
  /// ## Walking is cheap; rescanning is not
  ///
  /// The first cut of this sortie widened the window *before* knowing whether the joined
  /// pass would run, so a 500-line paragraph paid a 403-line rescan for a pass that was
  /// then skipped — breaking `ordinaryEditsStayLocal`, which encodes typing latency and is
  /// the deliberate counterweight to "a fence on line 1 dirties the document to the end".
  /// The fix is to ask first. This walk is a scalar read per line to find the run's extent,
  /// then at most one text read per line of it, and it bails before reading any text at all
  /// once the run is over the limit.
  ///
  /// ## Two conditions, and the second is what keeps typing fast
  ///
  /// 1. **The run is at most ``joinedContentLineLimit`` lines.** The perf backstop.
  /// 2. **At least one of its lines carries inline syntax.** Ordinary prose carries no
  ///    delimiters, so an edit in the middle of a two-hundred-line paragraph of plain text
  ///    still rescans three lines — joining it could not have changed a single span, so
  ///    buying two hundred lines of rescan for it would be pure loss.
  ///
  /// ## Why the threshold is one and not two
  ///
  /// An earlier cut of this required **two** syntax-carrying lines, on the argument that a
  /// single one cannot pair across a line and so joins to the same spans either way. That
  /// argument is true about **computing** the spans of the current text and false about
  /// **invalidating** spans computed from the previous text, which is the failure
  /// `deletingTheCloserUnstylesTheFirstLine` exists to catch: delete the closer from
  /// `**bold` / … / `text**` and the run drops to one syntax line, so a two-line threshold
  /// declines to widen and line 0 keeps the `.strong` it was given before the edit. Stale
  /// attributes on screen, which is the one defect this whole design exists to prevent.
  ///
  /// The general rule, worth stating because it is easy to re-derive wrongly: **a widening
  /// predicate evaluated on post-edit text cannot be a function of delimiter presence**,
  /// because an edit's whole purpose may be to remove the delimiters that justified the
  /// previous scan's widening.
  ///
  /// A threshold of one is nonetheless sound, and this is the argument. Styling that
  /// crosses a line boundary needs an opener and a closer on two *different* lines — a pair
  /// on one line styles only that line. So if the previous text had cross-line styling it
  /// had two syntax-carrying lines, and for the new text to have **none** the edit must have
  /// removed delimiters from at least two lines. A ``TextEdit`` range is contiguous, so such
  /// an edit spans every line between the first and the last delimiter it removed — which is
  /// exactly the region the old styling covered, since that region lay between those same
  /// two delimiters. Those lines are inside the edit and are rescanned whatever this
  /// predicate says. Zero syntax-carrying lines therefore needs no widening, and one always
  /// gets it.
  ///
  /// ## The run, not the block
  ///
  /// The limit is measured on the non-blank **run**, not on the block, because a run is
  /// what this type can see: deciding where a block ends is grouping's job, and
  /// ``IncrementalScanner`` is generic over ``LineGrammar`` and must not acquire a second
  /// opinion about it. The consequence is a narrowing worth naming: a short paragraph inside
  /// an unbroken non-blank run of more than two hundred lines does not join, even though the
  /// paragraph itself is short. Such a document is a wall of text with no blank line in it,
  /// which is exactly the case the backstop is for.
  ///
  /// - Returns: The extent walked — the true run, or a prefix of it when the walk hit the
  ///   limit — and the verdict. The extent is returned even when the verdict is `false` so
  ///   that a caller iterating many blocks can reuse one probe per run.
  private func joinableRun(
    containing line: Int, in source: some UTF16TextSource
  ) -> JoinableRun {
    guard line >= 0, line < index.lineCount, !isBlankLine(line) else {
      return JoinableRun(lines: line..<line, isJoinable: false)
    }

    var floor = line
    var ceiling = line + 1
    var length = 1
    var overLimit = false
    while floor > 0, !isBlankLine(floor - 1) {
      if length >= joinedContentLineLimit {
        overLimit = true
        break
      }
      floor -= 1
      length += 1
    }
    while ceiling < index.lineCount, !isBlankLine(ceiling) {
      if length >= joinedContentLineLimit {
        overLimit = true
        break
      }
      ceiling += 1
      length += 1
    }
    // Bail before touching any text: an over-long run is declined on its length alone.
    guard !overLimit else { return JoinableRun(lines: floor..<ceiling, isJoinable: false) }

    var carriesSyntax = false
    for candidate in floor..<ceiling {
      let content = index.line(at: candidate).contentRange
      guard !content.isEmpty else { continue }
      var units = [UInt16](repeating: 0, count: content.count)
      units.withUnsafeMutableBufferPointer { buffer in
        source.copyUTF16CodeUnits(in: content, into: buffer)
      }
      if grammar.containsJoinableInlineSyntax(units) {
        carriesSyntax = true
        break
      }
    }
    return JoinableRun(lines: floor..<ceiling, isJoinable: carriesSyntax)
  }

  /// Whether `line` is blank, by line geometry: an empty content range.
  ///
  /// Out of range counts as blank, so both walks stop at the document's edges.
  private func isBlankLine(_ line: Int) -> Bool {
    guard line >= 0, line < index.lineCount else { return true }
    return index.line(at: line).contentRange.isEmpty
  }

  // MARK: - Reading

  /// Reads one line out of `source` — **one** bulk copy, never one per code unit.
  private func grammarLine(at lineIndex: Int, in source: some UTF16TextSource) -> GrammarLine {
    let line = index.line(at: lineIndex)
    let content = line.contentRange
    var units = [UInt16](repeating: 0, count: content.count)
    if !content.isEmpty {
      units.withUnsafeMutableBufferPointer { buffer in
        source.copyUTF16CodeUnits(in: content, into: buffer)
      }
    }
    return GrammarLine(
      index: lineIndex,
      range: line.range,
      contentRange: content,
      terminatorLength: line.terminatorLength,
      units: units
    )
  }

  private func clamped(_ range: Range<Int>, into bounds: Range<Int>) -> Range<Int> {
    let lower = min(max(range.lowerBound, bounds.lowerBound), bounds.upperBound)
    let upper = min(max(range.upperBound, lower), bounds.upperBound)
    return lower..<upper
  }
}
