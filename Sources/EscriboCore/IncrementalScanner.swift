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

    // `startLine` survives the edit unchanged — every line before it is entirely before
    // the edit, so its text and, inductively, the state it began in are untouched. The
    // clamp is belt and braces: it cannot bind, because the lines below the edit are
    // exactly the lines an edit cannot move.
    let start = min(startLine, newLineCount - 1)
    let incoming = start < previousStates.count ? previousStates[start] : .documentStart
    let scan = scanLines(from: start, incoming: incoming, in: source, convergence: convergence)
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
    convergence: Convergence?
  ) -> (result: ScanResult, states: [LineState]) {
    let lineCount = index.lineCount
    let lookahead = max(0, grammar.lookahead)

    var spans: [EscriboSpan] = []
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
      spans.append(
        contentsOf: SpanTiling.tile(
          scan.spans,
          into: current.range,
          contentUnits: current.units,
          contentStart: current.contentRange.lowerBound
        ))

      state = scan.endState
      window.removeFirst()
      line += 1

      if let stop = stopLine {
        if line >= stop { break }
      } else if let convergence, hasConverged(at: line, state: state, convergence) {
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
      ScanResult(dirtyRange: dirtyRange, spans: spans, lines: lines, lineRecords: records),
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
