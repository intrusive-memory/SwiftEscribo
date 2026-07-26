// Deliberately NOT `@testable`. The invariant harness is written against exactly the
// surface a consumer sees, for two reasons. First, `ScanResult`, `EscriboSpan`,
// `LineRecord`, and `ElementKind` are all public, so nothing internal is needed to check
// the contract — and a harness that reached inside would be checking the scanner's
// bookkeeping rather than its output. Second, it lets `PublicSurfaceTests` and
// `PublicScannerTests`, which must stay non-`@testable`, call it without losing the one
// assertion they exist to make.
import EscriboCore
import Testing

/// The always-on span invariant harness.
///
/// Every invariant in ``ScanResult``'s doc comment is checked here, in that document's
/// order, and this type is the *only* place any of them is written down as executable
/// code. It is not a test case and must never become one: an invariant asserted in one
/// test is a test, and an invariant asserted on every scan the suite performs is a
/// harness. Every call site that produces a `ScanResult` — full scan, incremental scan,
/// through the generic engine or through the public facade — calls ``check(_:text:editedRange:_:sourceLocation:)``
/// on it.
///
/// ## What is checked, against ``ScanResult``'s enumerated contract
///
/// 1. ``ScanResult/spans`` are ordered, non-overlapping, contiguous, non-empty, and
///    **exactly tile** ``ScanResult/dirtyRange``.
/// 2. ``ScanResult/dirtyRange`` contains the edited range and is **line-aligned at both
///    ends**, measured against an oracle that does not use `LineIndex`.
/// 3. ``ScanResult/dirtyRange`` is well-formed and inside the document — the "never
///    smaller than the edit" half of invariant 3 is the containment check in 2, and the
///    "may be much larger" half is not a constraint to check but a permission to grant.
/// 4. ``ScanResult/lineRecords`` has one record per index in ``ScanResult/lines``, in
///    strictly increasing gapless order, each content range inside its own line range,
///    and the records tile `dirtyRange` exactly as the spans do.
/// 5. No span boundary — and neither end of `dirtyRange` — splits a surrogate pair.
///    A boundary through a surrogate pair hands `setAttributes(_:range:)` a range the
///    text system rounds outward, so the attributes applied would not be the attributes
///    computed.
enum ScanInvariants {

  // MARK: - Independent oracles
  //
  // Deliberately not built on `LineIndex`. An invariant checked with the same code that
  // produced the value under test is not checked at all, and line alignment is exactly
  // the invariant where that mistake would be invisible.

  /// The offset every line begins at: `0`, and one past every terminator.
  ///
  /// A document ending in a terminator therefore has a final, empty line whose start is
  /// the document's length — exactly how `LineIndex` models it, arrived at independently.
  static func lineStarts(_ units: [UInt16]) -> [Int] {
    var starts = [0]
    var offset = 0
    while offset < units.count {
      if units[offset] == 0x0A {
        starts.append(offset + 1)
        offset += 1
      } else if units[offset] == 0x0D {
        let pair = offset + 1 < units.count && units[offset + 1] == 0x0A
        starts.append(offset + (pair ? 2 : 1))
        offset += pair ? 2 : 1
      } else {
        offset += 1
      }
    }
    return starts
  }

  /// How many lines `text` has, counted without asking `LineIndex`.
  static func lineCount(of text: String) -> Int {
    lineStarts(Array(text.utf16)).count
  }

  /// Every offset a line may start or end at: `0`, one past each terminator, and the end
  /// of the document. Hand-written, no regex, and no `LineIndex`.
  static func lineBoundaries(of text: String) -> Set<Int> {
    let units = Array(text.utf16)
    var boundaries = Set(lineStarts(units))
    boundaries.insert(units.count)
    return boundaries
  }

  /// Splices `replacement` over `range` (UTF-16 code units) of `text`.
  ///
  /// Valid only when both bounds sit between characters. Splitting a surrogate pair here
  /// produces a string the **test** corrupted — `String(decoding:as:)` substitutes
  /// U+FFFD for the orphan and every offset after it moves — rather than one the scanner
  /// mishandled. Callers that choose offsets programmatically must filter them through
  /// ``isCharacterBoundary(_:in:)`` first.
  static func splice(_ text: String, _ range: Range<Int>, _ replacement: String) -> String {
    var units = Array(text.utf16)
    units.replaceSubrange(range, with: Array(replacement.utf16))
    return String(decoding: units, as: UTF16.self)
  }

  /// Whether `offset` sits between characters rather than inside a surrogate pair.
  static func isCharacterBoundary(_ offset: Int, in units: [UInt16]) -> Bool {
    guard offset > 0, offset < units.count else { return offset >= 0 && offset <= units.count }
    return !splitsSurrogatePair(at: offset, in: units)
  }

  /// Whether a boundary at `offset` falls between a high and a low surrogate.
  static func splitsSurrogatePair(at offset: Int, in units: [UInt16]) -> Bool {
    guard offset > 0, offset < units.count else { return false }
    let before = units[offset - 1]
    let at = units[offset]
    return (0xD800...0xDBFF).contains(before) && (0xDC00...0xDFFF).contains(at)
  }

  // MARK: - The harness

  /// Asserts every ``ScanResult`` invariant against `text`.
  ///
  /// - Parameters:
  ///   - result: The scan to check.
  ///   - text: The document the scan describes — the text **after** the edit, for an
  ///     incremental scan.
  ///   - editedRange: The edited range in **new-text** coordinates, or `nil` when there
  ///     was no edit (a full scan) or when the edit was deliberately out of range and so
  ///     has no meaningful new-text extent.
  ///   - context: A description of the case, evaluated only when something fails.
  ///   - sourceLocation: Defaulted so a failure points at the caller's line rather than
  ///     at this file. A harness that reports its own line number for every failure in
  ///     the suite is a harness nobody can debug.
  static func check(
    _ result: ScanResult,
    text: String,
    editedRange: Range<Int>? = nil,
    _ context: @autoclosure () -> String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let units = Array(text.utf16)
    let boundaries = lineBoundaries(of: text)
    let note = context()

    // 2. `dirtyRange` is well-formed, inside the document, and line-aligned at BOTH ends.
    #expect(
      result.dirtyRange.lowerBound <= result.dirtyRange.upperBound,
      "dirtyRange inverted — \(note)", sourceLocation: sourceLocation)
    #expect(
      result.dirtyRange.lowerBound >= 0, "dirtyRange below zero — \(note)",
      sourceLocation: sourceLocation)
    #expect(
      result.dirtyRange.upperBound <= units.count, "dirtyRange past EOF — \(note)",
      sourceLocation: sourceLocation)
    #expect(
      boundaries.contains(result.dirtyRange.lowerBound),
      "dirtyRange lower bound \(result.dirtyRange.lowerBound) is not line-aligned — \(note)",
      sourceLocation: sourceLocation)
    #expect(
      boundaries.contains(result.dirtyRange.upperBound),
      "dirtyRange upper bound \(result.dirtyRange.upperBound) is not line-aligned — \(note)",
      sourceLocation: sourceLocation)

    // 2, continued. `dirtyRange` CONTAINS the edited range, in new-text coordinates.
    if let editedRange {
      #expect(
        result.dirtyRange.lowerBound <= editedRange.lowerBound,
        "dirtyRange starts after the edit — \(note)", sourceLocation: sourceLocation)
      #expect(
        result.dirtyRange.upperBound >= editedRange.upperBound,
        "dirtyRange ends before the edit — \(note)", sourceLocation: sourceLocation)
    }

    // 1. Spans are ordered, non-overlapping, contiguous, and exactly tile `dirtyRange`.
    if result.dirtyRange.isEmpty {
      #expect(
        result.spans.isEmpty, "spans over an empty dirty range — \(note)",
        sourceLocation: sourceLocation)
    } else {
      #expect(
        result.spans.first?.range.lowerBound == result.dirtyRange.lowerBound,
        "first span does not start at the dirty range — \(note)", sourceLocation: sourceLocation)
      #expect(
        result.spans.last?.range.upperBound == result.dirtyRange.upperBound,
        "last span does not end at the dirty range — \(note)", sourceLocation: sourceLocation)
      var cursor = result.dirtyRange.lowerBound
      for span in result.spans {
        #expect(
          span.range.lowerBound == cursor, "span gap or overlap at \(cursor) — \(note)",
          sourceLocation: sourceLocation)
        #expect(
          !span.range.isEmpty, "empty span at \(cursor) — \(note)", sourceLocation: sourceLocation)
        cursor = span.range.upperBound
      }
      #expect(
        cursor == result.dirtyRange.upperBound, "spans tile short of the dirty range — \(note)",
        sourceLocation: sourceLocation)
    }

    // 4. `lineRecords` covers `lines` completely, in strictly increasing order, no gaps.
    #expect(
      result.lineRecords.count == result.lines.count, "record count != line count — \(note)",
      sourceLocation: sourceLocation)
    for (offset, record) in result.lineRecords.enumerated() {
      #expect(
        record.index == result.lines.lowerBound + offset,
        "record index gap at offset \(offset) — \(note)", sourceLocation: sourceLocation)
      #expect(
        record.range.lowerBound <= record.range.upperBound, "record range inverted — \(note)",
        sourceLocation: sourceLocation)
      #expect(
        record.contentRange.lowerBound >= record.range.lowerBound,
        "content range starts below its line — \(note)", sourceLocation: sourceLocation)
      #expect(
        record.contentRange.upperBound <= record.range.upperBound,
        "content range ends above its line — \(note)", sourceLocation: sourceLocation)
    }
    // Records tile the dirty range too — they are the paragraph-attribute half of the
    // same output and must agree with the span half about where the region is.
    if let first = result.lineRecords.first, let last = result.lineRecords.last {
      #expect(
        first.range.lowerBound == result.dirtyRange.lowerBound,
        "first record does not start at the dirty range — \(note)", sourceLocation: sourceLocation)
      #expect(
        last.range.upperBound == result.dirtyRange.upperBound,
        "last record does not end at the dirty range — \(note)", sourceLocation: sourceLocation)
      var cursor = first.range.lowerBound
      for record in result.lineRecords {
        #expect(
          record.range.lowerBound == cursor, "record gap at \(cursor) — \(note)",
          sourceLocation: sourceLocation)
        cursor = record.range.upperBound
      }
    }

    // 5. No boundary the editor will hand to `setAttributes(_:range:)` splits a
    //    surrogate pair. Span boundaries and both ends of the dirty range qualify;
    //    line boundaries cannot, because no terminator is a surrogate.
    for span in result.spans {
      #expect(
        !splitsSurrogatePair(at: span.range.lowerBound, in: units),
        "span boundary at \(span.range.lowerBound) splits a surrogate pair — \(note)",
        sourceLocation: sourceLocation)
      #expect(
        !splitsSurrogatePair(at: span.range.upperBound, in: units),
        "span boundary at \(span.range.upperBound) splits a surrogate pair — \(note)",
        sourceLocation: sourceLocation)
    }
    #expect(
      !splitsSurrogatePair(at: result.dirtyRange.lowerBound, in: units),
      "dirtyRange lower bound splits a surrogate pair — \(note)", sourceLocation: sourceLocation)
    #expect(
      !splitsSurrogatePair(at: result.dirtyRange.upperBound, in: units),
      "dirtyRange upper bound splits a surrogate pair — \(note)", sourceLocation: sourceLocation)
  }

  // MARK: - The painted document

  /// One span as the editor would have applied it, stated **relative to its line**.
  ///
  /// Relative, not absolute, because the comparison it exists for is between a document
  /// the editor painted over many edits and a document painted in one pass. Absolute
  /// offsets would make every line after an insertion compare unequal for a reason that
  /// is not a defect.
  struct PaintedSpan: Equatable, CustomStringConvertible {
    let offset: Int
    let length: Int
    let kind: SpanKind
    let style: StyleSet
    let role: SpanRole

    var description: String {
      "\(kind.rawValue)/\(role.rawValue)/\(style.rawValue) at +\(offset)…+\(offset + length)"
    }
  }

  /// One line as the editor would have painted it.
  struct PaintedLine: Equatable, CustomStringConvertible {
    let element: ElementKind
    let depth: Int
    let length: Int
    let contentOffset: Int
    let contentLength: Int
    let startState: LineState
    let spans: [PaintedSpan]

    var description: String {
      "\(element.rawValue)(depth \(depth), \(length) units, content +\(contentOffset)…"
        + "+\(contentOffset + contentLength), spans \(spans))"
    }
  }

  /// Decomposes a scan into one ``PaintedLine`` per record it covers.
  ///
  /// Spans are bucketed into the record whose range contains them, which is well defined
  /// because the engine tiles each line separately and no span ever straddles a line.
  static func paintedLines(of result: ScanResult) -> [PaintedLine] {
    var buckets = [[PaintedSpan]](repeating: [], count: result.lineRecords.count)
    var line = 0
    for span in result.spans {
      while line < result.lineRecords.count,
        span.range.lowerBound >= result.lineRecords[line].range.upperBound
      {
        line += 1
      }
      guard line < result.lineRecords.count else { break }
      let base = result.lineRecords[line].range.lowerBound
      buckets[line].append(
        PaintedSpan(
          offset: span.range.lowerBound - base,
          length: span.range.count,
          kind: span.kind,
          style: span.style,
          role: span.role))
    }

    return result.lineRecords.enumerated().map { offset, record in
      PaintedLine(
        element: record.element,
        depth: record.depth,
        length: record.range.count,
        contentOffset: record.contentRange.lowerBound - record.range.lowerBound,
        contentLength: record.contentRange.count,
        startState: record.startState,
        spans: buckets[offset])
    }
  }

  /// The document as an editor driven by incremental scans would have it painted.
  ///
  /// ## Why this exists, and why comparing the returned `ScanResult` is not enough
  ///
  /// A `ScanResult` describes only the window the scanner chose to rescan. Comparing it
  /// against the matching *slice* of a full scan asks "is what you repainted correct?"
  /// and never asks "did you repaint everything that changed?" — so a scanner whose
  /// window is too **small** passes: the lines it wrongly left alone are outside the
  /// window and are therefore never compared.
  ///
  /// That is not a hypothetical. Deleting the lookahead extension from the convergence
  /// loop — stopping at the converged line instead of `lookahead` lines past it — leaves
  /// an ALL-CAPS line painted as a character cue after the line below it goes blank, and
  /// a window-slice comparison stays green for every seed in the corpus. This type is
  /// what turns it red: it accumulates every repaint the way a text view would, and the
  /// gate compares the **whole accumulated document** against a full scan of the same
  /// text. A line the scanner declined to repaint is then compared against what a full
  /// scan says it should be, which is the only way "correct on full parse, wrong while
  /// typing" can be detected at all.
  struct PaintedDocument {
    private(set) var lines: [PaintedLine]

    /// Starts from a full scan, which covers every line.
    init(_ full: ScanResult) {
      self.lines = ScanInvariants.paintedLines(of: full)
    }

    /// Applies one incremental result the way the editor would: replace the lines the
    /// scan covered, keep everything before it, and carry everything after it across the
    /// line-count change.
    mutating func apply(_ result: ScanResult, newLineCount: Int) {
      let lineDelta = newLineCount - lines.count
      let head = lines.prefix(min(max(result.lines.lowerBound, 0), lines.count))
      let repainted = ScanInvariants.paintedLines(of: result)
      let carriedFrom = min(max(result.lines.upperBound - lineDelta, 0), lines.count)
      lines = Array(head) + repainted + Array(lines.suffix(from: carriedFrom))
    }
  }

  // MARK: - Legible array comparison

  /// Compares two arrays and, on a mismatch, reports the **first divergent index** rather
  /// than both arrays.
  ///
  /// `ScanResult` is `Equatable` and `#expect(a == b)` is one line shorter, but an
  /// equality failure printed over ten thousand spans is output nobody reads. Every
  /// array comparison in the gate goes through here.
  static func expectSameElements<Element: Equatable>(
    _ actual: [Element],
    _ expected: [Element],
    _ label: String,
    _ context: @autoclosure () -> String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    if actual == expected { return }
    let shared = min(actual.count, expected.count)
    var index = 0
    while index < shared, actual[index] == expected[index] {
      index += 1
    }
    if index < shared {
      Issue.record(
        """
        \(label) diverged at index \(index) of \(actual.count)/\(expected.count).
          incremental: \(actual[index])
          full scan:   \(expected[index])
          \(context())
        """,
        sourceLocation: sourceLocation)
    } else {
      Issue.record(
        """
        \(label) length differs: incremental \(actual.count), full scan \(expected.count); \
        the first \(shared) agree.
          \(context())
        """,
        sourceLocation: sourceLocation)
    }
  }
}
