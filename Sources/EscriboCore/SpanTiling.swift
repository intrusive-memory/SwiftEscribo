/// The first UTF-16 code unit of the high-surrogate range.
private let highSurrogateFirst: UInt16 = 0xD800

/// The last UTF-16 code unit of the high-surrogate range.
private let highSurrogateLast: UInt16 = 0xDBFF

/// The first UTF-16 code unit of the low-surrogate range.
private let lowSurrogateFirst: UInt16 = 0xDC00

/// The last UTF-16 code unit of the low-surrogate range.
private let lowSurrogateLast: UInt16 = 0xDFFF

/// Turns whatever a grammar emitted for one line into an exact tiling of that line.
///
/// ``ScanResult``'s first invariant — spans ordered, non-overlapping, contiguous, and
/// exactly tiling ``ScanResult/dirtyRange`` — is enforced **here**, once, rather than in
/// every grammar. That placement is deliberate:
///
/// - A grammar that emits nothing for a line still produces a total tokenization: the
///   whole line comes back as one ``SpanKind/text`` span. "Malformed constructs degrade
///   to text" is therefore the *absence* of code in a grammar rather than a case every
///   grammar has to remember to write.
/// - A grammar cannot ship a gap. Gaps are what force a clear-then-restyle pass and are
///   where "the styling is haunted" bugs come from, because `setAttributes(_:range:)`
///   replaces every attribute on the range it is given and nothing anywhere else.
/// - Reviewing a new grammar never involves re-checking the tiling.
///
/// The repairs, in order: clip to the line, snap boundaries off surrogate pairs, sort,
/// drop what an earlier span already covered, fill the holes with `.text`.
enum SpanTiling {

  /// Tiles `spans` across `lineRange` exactly.
  ///
  /// - Parameters:
  ///   - spans: What the grammar emitted. May be unsorted, overlapping, empty, or
  ///     partly outside the line.
  ///   - lineRange: The line's full extent, **including its terminator**. The returned
  ///     spans begin at its lower bound and end at its upper bound.
  ///   - contentUnits: The line's content code units, used only to keep a boundary from
  ///     landing between a high and a low surrogate.
  ///   - contentStart: The offset `contentUnits[0]` sits at.
  /// - Returns: Ordered, non-overlapping, contiguous spans covering `lineRange`, or an
  ///   empty array when `lineRange` is empty.
  static func tile(
    _ spans: [EscriboSpan],
    into lineRange: Range<Int>,
    contentUnits: [UInt16],
    contentStart: Int
  ) -> [EscriboSpan] {
    guard !lineRange.isEmpty else { return [] }

    // Deterministic order without relying on the sort being stable: ties go to whichever
    // span the grammar emitted first, so a grammar's own ordering is what breaks them.
    let ordered = spans.enumerated().sorted { left, right in
      let leftStart = left.element.range.lowerBound
      let rightStart = right.element.range.lowerBound
      if leftStart != rightStart { return leftStart < rightStart }
      return left.offset < right.offset
    }

    var tiled: [EscriboSpan] = []
    tiled.reserveCapacity(ordered.count * 2 + 1)
    var cursor = lineRange.lowerBound

    for (_, span) in ordered {
      let lower = clamp(
        align(span.range.lowerBound, contentUnits: contentUnits, contentStart: contentStart),
        into: lineRange)
      let upper = clamp(
        align(span.range.upperBound, contentUnits: contentUnits, contentStart: contentStart),
        into: lineRange)
      guard upper > cursor else { continue }  // entirely behind us, or empty
      let start = max(lower, cursor)
      guard upper > start else { continue }

      if start > cursor {
        tiled.append(EscriboSpan(range: cursor..<start, kind: .text))
      }
      tiled.append(
        EscriboSpan(range: start..<upper, kind: span.kind, style: span.style, role: span.role))
      cursor = upper
    }

    if cursor < lineRange.upperBound {
      tiled.append(EscriboSpan(range: cursor..<lineRange.upperBound, kind: .text))
    }
    return tiled
  }

  /// Moves `offset` forward off the tail of a surrogate pair.
  ///
  /// A span boundary between a high and a low surrogate would hand `setAttributes` half
  /// a character, which AppKit and UIKit both round outward — so the attributes applied
  /// would not be the attributes computed, and no amount of correct scanning upstream
  /// would show. Snapping **forward** rather than backward is what keeps the walk
  /// monotonic: a boundary never moves behind the cursor, so no span is retroactively
  /// shortened to nothing.
  private static func align(_ offset: Int, contentUnits: [UInt16], contentStart: Int) -> Int {
    let position = offset - contentStart
    guard position >= 1, position < contentUnits.count else { return offset }
    let before = contentUnits[position - 1]
    let at = contentUnits[position]
    let splitsPair =
      before >= highSurrogateFirst && before <= highSurrogateLast
      && at >= lowSurrogateFirst && at <= lowSurrogateLast
    return splitsPair ? offset + 1 : offset
  }

  private static func clamp(_ offset: Int, into range: Range<Int>) -> Int {
    min(max(offset, range.lowerBound), range.upperBound)
  }
}
