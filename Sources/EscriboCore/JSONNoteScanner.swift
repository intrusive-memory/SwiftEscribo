/// Structural JSON scanning for a Fountain note whose content is a GLOSA block directive.
///
/// ## Trigger
///
/// A note is JSON only when its trimmed content is `{`, optional whitespace, then `"`
/// (``startsJSONNote(_:in:)``). `{sic}`, `{}` and `{ 1 }` are not, so they stay plain
/// ``SpanKind/note``.
///
/// ## Shape
///
/// ``JSONNoteState`` is a small resumable tokenizer: everything it knows between tokens
/// (the container stack and what token is expected next) lives in the struct, and
/// ``JSONNoteState/consume(_:in:base:)`` takes one chunk at a time. Today's only caller
/// hands it a note's single line; carrying the state across lines is a later sortie's
/// job, and needs nothing from this file except storing the struct.
///
/// ## Output
///
/// Only recognised tokens are emitted. Whitespace and anything after the first error are
/// left for ``fill(_:in:base:)`` to cover with ``SpanKind/note``, so the result tiles the
/// chunk exactly and a malformed note never throws, traps, or leaves a gap.
struct JSONNoteState {

  /// Containers nested deeper than this are treated as malformed.
  static let maxDepth = 64

  private enum Container { case object, array }

  /// What the next non-whitespace token must be.
  private enum Expect {
    case value, valueOrArrayEnd, keyOrObjectEnd, key, colon, commaOrEnd, done
  }

  private var stack: [Container] = []
  private var expect: Expect = .value

  /// Whether the scan hit an error; once set, ``consume(_:in:base:)`` emits nothing.
  private(set) var failed = false

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
        if unit == 0x2C, let top = stack.last {
          punct(i)
          i += 1
          expect = top == .object ? .key : .value
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
          guard stack.count < Self.maxDepth else {
            failed = true
            break
          }
          punct(i)
          i += 1
          stack.append(unit == 0x7B ? .object : .array)
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
    guard let top = stack.last,
      (unit == 0x7D && top == .object) || (unit == 0x5D && top == .array)
    else { return false }
    stack.removeLast()
    valueFinished()
    return true
  }

  private mutating func valueFinished() {
    expect = stack.isEmpty ? .done : .commaOrEnd
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

  private static func isBlank(_ unit: UInt16) -> Bool { unit == 0x20 || unit == 0x09 }

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
