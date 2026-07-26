@testable import EscriboCore

// Grammars used to exercise the convergence engine, and nothing else. They live in the
// test target on purpose: Sortie 4 builds the seam, Sortie 5 builds the first real
// grammar through it, and a grammar in `Sources/` written to make the engine's tests
// pass would be a grammar written against the engine's bugs.
//
// Between them they cover the three shapes the engine has to handle:
//
// - stateless and lookahead-free (`PlainTextGrammar`) — the degenerate case,
// - stateful (`FenceGrammar`) — convergence has something real to converge on,
// - lookahead (`CueGrammar`) — the classification of a line depends on what follows it,
//   which is what the forward rule's third condition exists for.
//
// Plus two adversaries: one that splits a surrogate pair and one that emits deliberate
// garbage, because "the engine repairs whatever a grammar hands it" is a claim about
// bad grammars and cannot be tested with good ones.

// MARK: - Kinds these grammars need

extension SpanKind {
  static let character = SpanKind(rawValue: "test.character")
  static let fenceMarker = SpanKind(rawValue: "test.fenceMarker")
}

extension ElementKind {
  static let character = ElementKind(rawValue: "test.character")
}

// MARK: - Shared scanning helpers

/// `~`, the fence marker these tests use.
private let tildeUnit: UInt16 = 0x7E

/// Whether `units` opens or closes a fence: three tildes at the start of the line.
private func isFenceLine(_ units: [UInt16]) -> Bool {
  units.count >= 3 && units[0] == tildeUnit && units[1] == tildeUnit && units[2] == tildeUnit
}

/// Whether every unit is an ASCII uppercase letter, and there is at least one.
private func isAllCaps(_ units: [UInt16]) -> Bool {
  guard !units.isEmpty else { return false }
  for unit in units where unit < 0x41 || unit > 0x5A { return false }
  return true
}

// MARK: - 1. Stateless, lookahead-free

/// Every line is one `.text` span. No state, no lookahead.
///
/// The engine's degenerate case, and the one that proves the tiling machinery does the
/// work: this grammar emits a span covering only the line's *content*, so every line's
/// terminator comes back as engine-supplied filler. If the filler were missing, the
/// spans would not tile and every invariant assertion in the suite would fail at once.
struct PlainTextGrammar: LineGrammar {
  var lookahead: Int { 0 }

  func scanLine(_ window: LineWindow, state: LineState) -> LineScan {
    let line = window.current
    return LineScan(
      spans: [EscriboSpan(range: line.contentRange, kind: .text)],
      element: line.isEmpty ? .blank : .paragraph,
      endState: state
    )
  }
}

// MARK: - 2. Stateful

/// A fence-like open/close construct carried in ``LineState``.
///
/// A line beginning `~~~` toggles the construct; lines between the toggles are code.
/// That is deliberately *not* Markdown's fenced code block — no info string, no
/// backticks, no matching fence lengths — because Sortie 5 owns the real one. What it
/// shares with the real one is the only thing the engine cares about: the classification
/// of a line depends on a state that arrived from an arbitrary distance above it, so
/// convergence has something to converge on and an edit to line 1 can legitimately
/// change how line 400 scans.
///
/// An unterminated fence is not an error. The state simply stays open to the end of the
/// document, which is REQUIREMENTS.md § Concurrency and failure's "unterminated
/// constructs degrade" expressed as the absence of a special case.
struct FenceGrammar: LineGrammar {
  /// The `openConstruct` tag this grammar uses. Its meaning is the grammar's; the
  /// scanner only ever compares it.
  static let fenceTag: UInt16 = 1

  var lookahead: Int { 0 }

  func scanLine(_ window: LineWindow, state: LineState) -> LineScan {
    let line = window.current
    let isOpen = state.openConstruct == Self.fenceTag
    let isFence = isFenceLine(line.units)

    if isFence {
      let markerEnd = line.contentRange.lowerBound + 3
      return LineScan(
        spans: [
          EscriboSpan(
            range: line.contentRange.lowerBound..<markerEnd, kind: .fenceMarker, role: .marker),
          EscriboSpan(range: markerEnd..<line.contentRange.upperBound, kind: .codeInfoString),
        ],
        element: .codeFence,
        contentRange: markerEnd..<line.contentRange.upperBound,
        endState: LineState(openConstruct: isOpen ? 0 : Self.fenceTag)
      )
    }

    if isOpen {
      return LineScan(
        spans: [EscriboSpan(range: line.contentRange, kind: .codeBlock)],
        element: .codeBlock,
        endState: state
      )
    }

    return LineScan(
      spans: [EscriboSpan(range: line.contentRange, kind: .text)],
      element: line.isEmpty ? .blank : .paragraph,
      endState: state
    )
  }
}

// MARK: - 3. Lookahead

/// An ALL-CAPS line is a character cue **only by virtue of what follows it**.
///
/// This is Fountain's cue rule (REQUIREMENTS.md § Fountain 4) reduced to its skeleton,
/// and it is in the suite because a lookahead that is never non-zero is a lookahead that
/// is not tested. The declared distance is a **parameter**, so the same grammar can be
/// instantiated at 0, 1, and 2 lines of lookahead and the engine's rescan window
/// compared across them — which is how "lookahead is a property the grammar declares,
/// not a constant" gets proved rather than asserted.
///
/// Its state is deliberately **uniform**: every line begins in the same `LineState`, so
/// the convergence rule's state-equality condition is true at *every* boundary,
/// including the one immediately before the edit. Correctness here therefore rests
/// entirely on the other two conditions — the edit being behind us, and the declared
/// lookahead being satisfied. A convergence loop that stops on state equality alone
/// rescans exactly one line on this grammar and repaints nothing that changed.
struct CueGrammar: LineGrammar {
  let lookahead: Int

  init(lookahead: Int) {
    self.lookahead = lookahead
  }

  func scanLine(_ window: LineWindow, state: LineState) -> LineScan {
    let line = window.current
    var isCue = isAllCaps(line.units) && lookahead > 0
    if isCue {
      for distance in 1...max(1, lookahead) {
        guard let ahead = window.line(ahead: distance), !ahead.isEmpty else {
          isCue = false
          break
        }
      }
    }

    return LineScan(
      spans: [EscriboSpan(range: line.contentRange, kind: isCue ? .character : .text)],
      element: isCue ? .character : (line.isEmpty ? .blank : .paragraph),
      endState: state
    )
  }
}

// MARK: - 4. Adversary: splits a surrogate pair

/// Emits a span boundary one code unit into the line, whatever is there.
///
/// On a line beginning with an astral-plane character that boundary falls between the
/// high and the low surrogate — half a character. The engine is required to move it, and
/// this grammar is the only way to make it try.
struct SurrogateSplittingGrammar: LineGrammar {
  var lookahead: Int { 0 }

  func scanLine(_ window: LineWindow, state: LineState) -> LineScan {
    let line = window.current
    guard !line.units.isEmpty else {
      return LineScan(element: .blank, endState: state)
    }
    let boundary = line.contentRange.lowerBound + 1
    return LineScan(
      spans: [
        EscriboSpan(range: line.contentRange.lowerBound..<boundary, kind: .heading, role: .marker),
        EscriboSpan(range: boundary..<line.contentRange.upperBound, kind: .heading),
      ],
      element: .heading,
      endState: state
    )
  }
}

/// Emits overlapping, unordered, empty, and out-of-bounds spans for every line.
///
/// Every one of these is something a grammar author will eventually do by accident. The
/// engine's contract is that none of them can reach a `ScanResult`, and a contract about
/// bad input cannot be tested with good input.
struct HostileGrammar: LineGrammar {
  var lookahead: Int { 0 }

  func scanLine(_ window: LineWindow, state: LineState) -> LineScan {
    let line = window.current
    let start = line.contentRange.lowerBound
    let end = line.contentRange.upperBound
    return LineScan(
      spans: [
        EscriboSpan(range: (end + 50)..<(end + 90), kind: .heading),  // past the line
        EscriboSpan(range: (start + 1)..<(end + 40), kind: .codeBlock),  // overruns the line
        EscriboSpan(range: start..<start, kind: .heading),  // empty
        EscriboSpan(range: start..<(start + 2), kind: .character),  // out of order, overlapping
        EscriboSpan(range: (start - 30)..<(start - 10), kind: .text),  // before the line
      ],
      element: .paragraph,
      endState: state
    )
  }
}
