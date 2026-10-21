/// Structural JSON scanning for a Fountain note whose content is a GLOSA block directive.
///
/// ## Trigger
///
/// A note is JSON only when its trimmed content is `{`, optional whitespace (line breaks
/// included), then `"` (``startsJSONNote(_:in:)`` for one chunk, ``JSONNoteContext`` across
/// lines). `{sic}`, `{}` and `{ 1 }` are not, so they stay plain ``SpanKind/note``.
///
/// ## Shape
///
/// ``JSONNoteState`` is a small resumable tokenizer: everything it knows between tokens
/// (the container stack and what token is expected next) lives in the struct, and
/// ``JSONNoteState/consume(_:in:base:)`` takes one chunk at a time. It is fixed-size and
/// allocation-free — the container stack is a bit set, one bit per level — because a copy
/// of it is carried in ``LineState`` for every line of a document.
///
/// ## Strings never span lines
///
/// JSON forbids a raw line break inside a string, so a string still open when its chunk
/// ends is malformed, exactly like any other error. That is why no "inside a string" or
/// "after a backslash" bit is ever carried to the next line: the only state a string can be
/// in at a line boundary is "failed", and failed is one uniform value.
///
/// ## Output
///
/// Only recognised tokens are emitted. Whitespace and anything after the first error are
/// left for ``fill(_:in:base:)`` to cover with ``SpanKind/note``, so the result tiles the
/// chunk exactly and a malformed note never throws, traps, or leaves a gap.
struct JSONNoteState: Equatable, Sendable {

  /// Containers nested deeper than this are treated as malformed. Also the width of
  /// ``stackBits``.
  static let maxDepth = 64

  /// What the next non-whitespace token must be.
  private enum Expect: UInt8, Equatable, Sendable {
    case value, valueOrArrayEnd, keyOrObjectEnd, key, colon, commaOrEnd, done
  }

  /// The container stack: bit `i` is set when level `i` is an array, clear when it is an
  /// object. Bits at and above ``depth`` are always zero, so equality is exact.
  private var stackBits: UInt64 = 0
  private var depth: UInt8 = 0
  private var expect: Expect = .value

  /// Whether the scan hit an error; once set, ``consume(_:in:base:)`` emits nothing.
  private(set) var failed = false

  /// A tokenizer that has already read an object's opening `{` and expects a key (or `}`).
  static var afterOpeningBrace: JSONNoteState {
    var state = JSONNoteState()
    state.push(array: false)
    state.expect = .keyOrObjectEnd
    return state
  }

  /// The single value every failed tokenizer collapses to, so two notes that went wrong
  /// in different places carry identical state from then on.
  static var malformed: JSONNoteState {
    var state = JSONNoteState()
    state.failed = true
    return state
  }

  private var topIsArray: Bool? {
    depth == 0 ? nil : (stackBits >> UInt64(depth - 1)) & 1 == 1
  }

  private mutating func push(array: Bool) {
    if array { stackBits |= 1 << UInt64(depth) }
    depth += 1
  }

  private mutating func pop() {
    depth -= 1
    stackBits &= ~(1 << UInt64(depth))
  }

  // MARK: - Trigger

  /// Whether `units[range]` begins (after leading spaces and tabs) with `{`, optional
  /// spaces and tabs, then `"`.
  static func startsJSONNote(_ units: [UInt16], in range: Range<Int>) -> Bool {
    var i = range.lowerBound
    while i < range.upperBound, isBlank(units[i]) { i += 1 }
    guard i < range.upperBound, units[i] == 0x7B else { return false }
    i += 1
    while i < range.upperBound, isBlank(units[i]) { i += 1 }
    return i < range.upperBound && units[i] == 0x22
  }

  // MARK: - Tokenizing

  /// Tokenizes `units[range]`, returning the token spans in ascending order.
  mutating func consume(_ units: [UInt16], in range: Range<Int>, base: Int) -> [EscriboSpan] {
    var spans: [EscriboSpan] = []
    var i = range.lowerBound
    let limit = range.upperBound

    func punct(_ at: Int) {
      spans.append(
        EscriboSpan(range: (base + at)..<(base + at + 1), kind: .glosaPunctuation, role: .marker))
    }

    defer { if failed { self = .malformed } }
    while !failed {
      while i < limit, Self.isBlank(units[i]) { i += 1 }
      guard i < limit else { break }
      let unit = units[i]

      switch expect {
      case .done:
        failed = true

      case .colon:
        if unit == 0x3A {
          punct(i)
          i += 1
          expect = .value
        } else {
          failed = true
        }

      case .commaOrEnd:
        if unit == 0x2C, let isArray = topIsArray {
          punct(i)
          i += 1
          expect = isArray ? .value : .key
        } else if closes(unit) {
          punct(i)
          i += 1
        } else {
          failed = true
        }

      case .key, .keyOrObjectEnd:
        if unit == 0x22, let end = stringEnd(units, from: i, limit: limit) {
          spans.append(EscriboSpan(range: (base + i)..<(base + end), kind: .glosaJSONKey))
          i = end
          expect = .colon
        } else if unit == 0x7D, expect == .keyOrObjectEnd, closes(unit) {
          punct(i)
          i += 1
        } else {
          failed = true
        }

      case .value, .valueOrArrayEnd:
        if unit == 0x5D, expect == .valueOrArrayEnd, closes(unit) {
          punct(i)
          i += 1
        } else if unit == 0x7B || unit == 0x5B {
          guard depth < Self.maxDepth else {
            failed = true
            break
          }
          punct(i)
          i += 1
          push(array: unit == 0x5B)
          expect = unit == 0x7B ? .keyOrObjectEnd : .valueOrArrayEnd
        } else if unit == 0x22 {
          if let end = stringEnd(units, from: i, limit: limit) {
            spans.append(EscriboSpan(range: (base + i)..<(base + end), kind: .glosaJSONString))
            i = end
            valueFinished()
          } else {
            failed = true
          }
        } else if let end = numberEnd(units, from: i, limit: limit) {
          spans.append(EscriboSpan(range: (base + i)..<(base + end), kind: .glosaJSONNumber))
          i = end
          valueFinished()
        } else if let end = literalEnd(units, from: i, limit: limit) {
          spans.append(EscriboSpan(range: (base + i)..<(base + end), kind: .glosaJSONLiteral))
          i = end
          valueFinished()
        } else {
          failed = true
        }
      }
    }
    return spans
  }

  /// Pops the container `unit` closes, if it matches the innermost one.
  private mutating func closes(_ unit: UInt16) -> Bool {
    guard let isArray = topIsArray, unit == (isArray ? 0x5D : 0x7D) else { return false }
    pop()
    valueFinished()
    return true
  }

  private mutating func valueFinished() {
    expect = depth == 0 ? .done : .commaOrEnd
  }

  // MARK: - Token shapes

  /// The index just past the closing quote of the string opening at `start`, or `nil`
  /// when the chunk ends first. A backslash always consumes the following unit, so `\"`
  /// and `\\` need no further validation to find the real terminator.
  private func stringEnd(_ units: [UInt16], from start: Int, limit: Int) -> Int? {
    var i = start + 1
    while i < limit {
      if units[i] == 0x5C {
        i += 2
      } else if units[i] == 0x22 {
        return i + 1
      } else {
        i += 1
      }
    }
    return nil
  }

  /// The index past a JSON number at `start` (`-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?`)
  /// that is followed by a delimiter, or `nil`.
  private func numberEnd(_ units: [UInt16], from start: Int, limit: Int) -> Int? {
    var i = start
    func digits() -> Bool {
      let begin = i
      while i < limit, units[i] >= 0x30, units[i] <= 0x39 { i += 1 }
      return i > begin
    }
    if i < limit, units[i] == 0x2D { i += 1 }
    guard i < limit, units[i] >= 0x30, units[i] <= 0x39 else { return nil }
    if units[i] == 0x30 { i += 1 } else { _ = digits() }
    if i < limit, units[i] == 0x2E {
      i += 1
      guard digits() else { return nil }
    }
    if i < limit, units[i] == 0x65 || units[i] == 0x45 {
      i += 1
      if i < limit, units[i] == 0x2B || units[i] == 0x2D { i += 1 }
      guard digits() else { return nil }
    }
    return atDelimiter(units, i, limit) ? i : nil
  }

  /// The index past `true`, `false` or `null` at `start` when followed by a delimiter.
  private func literalEnd(_ units: [UInt16], from start: Int, limit: Int) -> Int? {
    for word in Self.literals {
      let end = start + word.count
      guard end <= limit, Array(units[start..<end]) == word else { continue }
      return atDelimiter(units, end, limit) ? end : nil
    }
    return nil
  }

  private static let literals: [[UInt16]] = [
    Array("true".utf16), Array("false".utf16), Array("null".utf16),
  ]

  /// Whether a value token may end at `i`: end of chunk, whitespace, `,`, `}` or `]`.
  private func atDelimiter(_ units: [UInt16], _ i: Int, _ limit: Int) -> Bool {
    guard i < limit else { return true }
    let u = units[i]
    return Self.isBlank(u) || u == 0x2C || u == 0x7D || u == 0x5D
  }

  static func isBlank(_ unit: UInt16) -> Bool { unit == 0x20 || unit == 0x09 }

  // MARK: - Tiling

  /// Covers every gap in `tokens` (and the tail) within `range` with ``SpanKind/note``,
  /// so the result tiles `range` exactly.
  static func fill(_ tokens: [EscriboSpan], in range: Range<Int>, base: Int) -> [EscriboSpan] {
    var out: [EscriboSpan] = []
    var cursor = base + range.lowerBound
    for token in tokens {
      if token.range.lowerBound > cursor {
        out.append(EscriboSpan(range: cursor..<token.range.lowerBound, kind: .note))
      }
      out.append(token)
      cursor = token.range.upperBound
    }
    if cursor < base + range.upperBound {
      out.append(EscriboSpan(range: cursor..<(base + range.upperBound), kind: .note))
    }
    return out
  }
}

/// Where a Fountain note stands with respect to the JSON trigger, carried from one line of
/// the note to the next in ``LineState`` (and ``NestedFountainState`` inside a `fountain`
/// fence).
///
/// The trigger (`{`, optional whitespace including line breaks, `"`) can take several lines
/// to decide: `[[` may sit alone on its line, and `[[{` may be followed by a line break
/// before the `"`. The two "pending" phases carry that undecided prefix; once the rule is
/// decided the note is either a JSON note (``Phase/json``), a plain note (``Phase/inactive``,
/// tag directives scanned as before) or a JSON note that went wrong (``Phase/malformed``,
/// the rest of the note is plain ``SpanKind/note``).
///
/// Every phase but ``Phase/json`` keeps ``tokenizer`` at its default and every failure
/// collapses to one value, so the incremental scanner converges as soon as two scans agree
/// on the phase — the error state is uniform. Outside a note the context is always the
/// default (``Phase/inactive``).
struct JSONNoteContext: Equatable, Sendable {

  enum Phase: UInt8, Equatable, Sendable {
    /// Not in a note, or in a note that is not JSON.
    case inactive
    /// A note is open and nothing but whitespace has followed its `[[` yet.
    case awaitingContent
    /// A note's content so far is `{` plus whitespace; a `"` decides it is JSON.
    case awaitingQuote
    /// Inside a JSON note; ``tokenizer`` holds the container stack and expectation.
    case json
    /// A JSON note hit an error; the rest of it is plain ``SpanKind/note``.
    case malformed
  }

  private(set) var phase: Phase = .inactive
  private(set) var tokenizer = JSONNoteState()

  /// The context at the start of a freshly opened note's content.
  static let noteOpened = JSONNoteContext(phase: .awaitingContent, tokenizer: JSONNoteState())

  /// Scans one chunk of a note's content and advances the context past it.
  ///
  /// - Parameters:
  ///   - units: The line's content code units (line-relative).
  ///   - range: The chunk of note content on this line, markers excluded.
  ///   - base: The document offset `units[0]` sits at.
  ///   - continues: Whether the note stays open past this chunk (no `]]` on this line).
  ///     A note that closes while the trigger is still undecided is not JSON.
  /// - Returns: Spans that tile `range` exactly, in ascending order, or `nil` when the
  ///   chunk is not JSON and should be tag-scanned as ordinary note content.
  mutating func scan(
    _ units: [UInt16], in range: Range<Int>, base: Int, continues: Bool
  ) -> [EscriboSpan]? {
    switch phase {
    case .inactive:
      return nil

    case .malformed:
      return JSONNoteState.fill([], in: range, base: base)

    case .json:
      return tokenize(units, in: range, base: base)

    case .awaitingContent:
      if JSONNoteState.startsJSONNote(units, in: range) {
        phase = .json
        tokenizer = JSONNoteState()
        return tokenize(units, in: range, base: base)
      }
      var i = range.lowerBound
      while i < range.upperBound, JSONNoteState.isBlank(units[i]) { i += 1 }
      if i == range.upperBound {
        // Still nothing but whitespace: undecided if the note goes on, plain if it closes.
        if !continues { phase = .inactive }
        return JSONNoteState.fill([], in: range, base: base)
      }
      if continues, units[i] == 0x7B, isBlankRun(units, (i + 1)..<range.upperBound) {
        // `{` then the line ends. Coloured as JSON punctuation now, because a span may only
        // depend on what precedes it; a later line that turns out not to start with `"`
        // leaves this one `{` coloured and scans the rest as a plain note.
        phase = .awaitingQuote
        let brace = EscriboSpan(
          range: (base + i)..<(base + i + 1), kind: .glosaPunctuation, role: .marker)
        return JSONNoteState.fill([brace], in: range, base: base)
      }
      phase = .inactive
      return nil

    case .awaitingQuote:
      var i = range.lowerBound
      while i < range.upperBound, JSONNoteState.isBlank(units[i]) { i += 1 }
      if i == range.upperBound {
        if !continues { phase = .inactive }
        return JSONNoteState.fill([], in: range, base: base)
      }
      guard units[i] == 0x22 else {
        phase = .inactive
        return nil
      }
      phase = .json
      tokenizer = .afterOpeningBrace
      return tokenize(units, in: range, base: base)
    }
  }

  private mutating func tokenize(
    _ units: [UInt16], in range: Range<Int>, base: Int
  ) -> [EscriboSpan] {
    let tokens = tokenizer.consume(units, in: range, base: base)
    if tokenizer.failed {
      phase = .malformed
      tokenizer = JSONNoteState()
    }
    return JSONNoteState.fill(tokens, in: range, base: base)
  }

  private func isBlankRun(_ units: [UInt16], _ range: Range<Int>) -> Bool {
    for i in range where !JSONNoteState.isBlank(units[i]) { return false }
    return true
  }
}
