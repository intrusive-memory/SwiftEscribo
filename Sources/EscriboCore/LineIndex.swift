/// U+000A LINE FEED. One of exactly two code units this package treats as terminator
/// material — terminator detection is a hand-written comparison against these two
/// constants and nothing else. No regex, per this package's charter.
private let lineFeedUnit: UInt16 = 0x0A

/// U+000D CARRIAGE RETURN.
private let carriageReturnUnit: UInt16 = 0x0D

/// The chunk size for terminator scanning. Large enough that a 1 MB single line costs
/// 256 bulk reads rather than a million, small enough that the staging buffer stays
/// cache-resident.
private let scanChunkSize = 4096

/// Where the lines are — and only that.
///
/// `LineIndex` answers "which UTF-16 offsets belong to line *n*". It does **not** scan
/// grammar: it has no idea what a heading is, and Sortie 4's scanner is what turns
/// these ranges into classified ``LineRecord`` values. Keeping the two apart is what
/// lets the expensive thing (grammar) run over a few lines while the cheap thing (line
/// geometry) stays correct for the whole document.
///
/// ## Terminators
///
/// `\n`, `\r\n`, and a lone `\r` are all terminators, they may be **mixed within one
/// document**, and they are **never normalized** — the writer (Sortie 23) has to
/// reproduce the document byte for byte, so which one each line used has to survive
/// indexing. `\r\n` is **one** terminator of **two** code units, never two terminators.
///
/// ``Line/range`` **includes** the terminator; ``Line/contentRange`` excludes it. Summing
/// every line's `range` reconstructs the source byte for byte, which is the strongest
/// invariant this type has and the one its tests assert on every fixture.
///
/// Unicode's other line breaks — U+0085, U+2028, U+2029 — are deliberately *not*
/// terminators here. REQUIREMENTS.md § Line termination names three and only three, and
/// a text view that disagrees with the model about line count is unrecoverable; both
/// AppKit and UIKit paragraph-break on the same three.
///
/// ## Degenerate documents
///
/// There is never a zero-line document. `""` is one empty line, `"a"` is one line, and
/// a trailing terminator produces a final empty line, so `"a\n"` is **two** lines:
/// `"a\n"` and `""`. That last rule matches where a text view lets the caret go.
///
/// ## Access level
///
/// `internal`. REQUIREMENTS.md § What is public in 1.0 does not list it, and nothing in
/// `SwiftEscribo` needs to name the type — the editor consumes ``LineRecord`` values,
/// which the scanner produces. Contrast ``UTF16TextSource``, which must be public
/// because `SwiftEscribo` conforms `NSTextStorage` to it across a module boundary.
struct LineIndex: Equatable, Sendable {

  /// One line's geometry.
  struct Line: Equatable, Sendable {
    /// Zero-based line number.
    let index: Int

    /// The line's full extent in UTF-16 code units, **including its terminator**.
    let range: Range<Int>

    /// `2` for `\r\n`, `1` for `\n` or a lone `\r`, `0` for a final line that ends
    /// without one.
    ///
    /// Stored rather than recomputed because every offset after a CRLF depends on it
    /// and re-reading the source to answer "how long was that terminator" is both
    /// slower and a place to get it wrong twice.
    let terminatorLength: Int

    /// The line's extent **excluding** its terminator.
    ///
    /// Not the same as ``LineRecord/contentRange``, which additionally excludes indent
    /// and syntax markers — those are grammar, and this type has no grammar.
    var contentRange: Range<Int> { range.lowerBound..<(range.upperBound - terminatorLength) }

    /// Whether this line ends with a terminator. Only a document's final line can be
    /// without one.
    var hasTerminator: Bool { terminatorLength > 0 }
  }

  /// A line's start plus the length of the terminator that ends it. The line's *end* is
  /// the next slot's start — or ``utf16Count`` for the last — so ends can never drift
  /// out of agreement with starts.
  private struct Slot: Equatable, Sendable {
    var start: Int
    var terminatorLength: Int
  }

  /// One entry per line, ascending by `start`. Never empty.
  private var slots: [Slot]

  /// The indexed document's length in UTF-16 code units.
  private(set) var utf16Count: Int

  // MARK: - Building

  /// Indexes `source` in full.
  ///
  /// Linear in the document's length, with one bulk read per 4 096 code units — not one
  /// per code unit, and not one per line. A one-megabyte single line costs 256 reads.
  init(_ source: some UTF16TextSource) {
    var buffer = UTF16LineBuffer()
    let count = source.utf16Count
    self.slots = Self.scanSlots(
      in: source,
      range: 0..<count,
      isDocumentTail: true,
      buffer: &buffer
    )
    self.utf16Count = count
  }

  // MARK: - Reading

  /// The number of lines. Always at least one.
  var lineCount: Int { slots.count }

  /// The line at `index`.
  func line(at index: Int) -> Line {
    Line(
      index: index,
      range: slots[index].start..<endOfLine(at: index),
      terminatorLength: slots[index].terminatorLength
    )
  }

  /// Every line, in order. Materializes an array — for walking a document prefer
  /// ``line(at:)`` in a loop.
  var lines: [Line] { (0..<slots.count).map(line(at:)) }

  /// The index of the line containing `offset`.
  ///
  /// A position sitting exactly on a line boundary belongs to the line that **starts**
  /// there, and `utf16Count` belongs to the last line. Binary search, so a 1 MB
  /// document costs the same lookup as a 1 KB one.
  func lineIndex(containing offset: Int) -> Int {
    let clamped = min(max(offset, 0), utf16Count)
    var low = 0
    var high = slots.count - 1
    while low < high {
      let mid = (low + high + 1) / 2
      if slots[mid].start <= clamped {
        low = mid
      } else {
        high = mid - 1
      }
    }
    return low
  }

  private func endOfLine(at index: Int) -> Int {
    index + 1 < slots.count ? slots[index + 1].start : utf16Count
  }

  // MARK: - Provisional records

  /// The line at `index` as a ``LineRecord`` carrying **only what a line index knows**.
  ///
  /// "Provisional" is the operative word, and it is not hedging:
  ///
  /// - ``LineRecord/range`` and ``LineRecord/contentRange`` are final. The content range
  ///   here excludes the terminator only; a grammar later narrows it past indent and
  ///   syntax markers.
  /// - ``LineRecord/element`` is ``ElementKind/blank`` or ``ElementKind/paragraph`` and
  ///   nothing else. That distinction is a property of the line's *shape* — "empty apart
  ///   from its terminator" — not of any grammar, and both grammars agree on it.
  /// - ``LineRecord/startState`` is ``LineState/documentStart`` for every line, which is
  ///   true only of line zero. Multi-line state is the convergence engine's output
  ///   (Sortie 4) and cannot be known here.
  /// - ``LineRecord/depth`` is zero.
  ///
  /// Nothing but tests should consume these until a scanner exists to fill them in.
  func provisionalRecord(at index: Int) -> LineRecord {
    let line = line(at: index)
    return LineRecord(
      index: line.index,
      range: line.range,
      contentRange: line.contentRange,
      element: line.contentRange.isEmpty ? .blank : .paragraph,
      startState: .documentStart,
      depth: 0
    )
  }

  /// Every line as a provisional record. See ``provisionalRecord(at:)`` for what
  /// "provisional" excludes.
  var provisionalRecords: [LineRecord] { (0..<slots.count).map(provisionalRecord(at:)) }

  // MARK: - Incremental adjustment

  /// Adjusts the index for `edit` without re-indexing the whole document.
  ///
  /// - Parameters:
  ///   - edit: The mutation, in **old-text coordinates** — see ``TextEdit``. `range`
  ///     indexes the document as this index currently describes it.
  ///   - source: The document **after** the edit.
  ///
  /// ## The rule, stated exactly
  ///
  /// 1. `first` is the line containing `edit.range.lowerBound`, then **widened back one
  ///    line** whenever one exists.
  /// 2. `last` is the line containing `edit.range.upperBound`, where a position on a
  ///    line boundary belongs to the line starting there.
  /// 3. Lines `first...last` are **re-scanned** from the new text.
  /// 4. Lines before `first` are **untouched** — an edit does not move text ahead of
  ///    itself.
  /// 5. Lines after `last` keep their terminators and shift their starts by
  ///    ``TextEdit/changeInLength``. Their *text* did not change, so re-scanning them
  ///    could only reproduce what they already say.
  ///
  /// ## Why step 1 widens backward
  ///
  /// Without it, inserting `"\n"` at the end of `"a\r"` would rescan only the final
  /// empty line and leave the `\r` sitting in a previous line's terminator — splitting
  /// the resulting `\r\n` pair across a line boundary, which is the one thing this index
  /// must never do. One line of backward widening is exactly enough: a `\r` can only
  /// couple with an `\n` immediately after it, and that `\n` can only be the first code
  /// unit of the next line.
  ///
  /// Forward widening is *not* needed, and the reason is worth writing down because it
  /// looks asymmetric. The rescan region ends at `last`'s end, and `last` is the line
  /// *containing* the edit's end — so the code unit at `edit.range.upperBound` is always
  /// inside the region. Anything past it is unedited text whose terminators the old
  /// index already got right, and an unedited lone `\r` could not have been followed by
  /// an unedited `\n` without the old scan having paired them.
  ///
  /// ## An edit landing between the `\r` and the `\n`
  ///
  /// That offset is *inside* line `first`'s terminator, so the line is re-scanned and
  /// the pair simply stops being a pair: inserting `"X"` at offset 2 of `"a\r\nb"` gives
  /// `"a\r"` (lone-CR terminator), `"X\n"`, and `"b"` — three lines where there were two.
  /// Nothing is normalized and nothing is split, because after the edit there is no
  /// `\r\n` left to split.
  mutating func apply(_ edit: TextEdit, to source: some UTF16TextSource) {
    let newCount = source.utf16Count
    let delta = edit.changeInLength

    let editStart = min(max(edit.range.lowerBound, 0), utf16Count)
    let editEnd = min(max(edit.range.upperBound, editStart), utf16Count)

    var first = lineIndex(containing: editStart)
    if first > 0 { first -= 1 }
    let last = lineIndex(containing: editEnd)

    let isDocumentTail = last + 1 == slots.count
    let regionStart = slots[first].start
    let oldRegionEnd = endOfLine(at: last)
    let regionEnd =
      isDocumentTail
      ? newCount
      : min(max(oldRegionEnd + delta, regionStart), newCount)

    var buffer = UTF16LineBuffer()
    let replacement = Self.scanSlots(
      in: source,
      range: regionStart..<regionEnd,
      isDocumentTail: isDocumentTail,
      buffer: &buffer
    )

    slots.replaceSubrange(first...last, with: replacement)
    for index in (first + replacement.count)..<slots.count {
      slots[index].start += delta
    }
    utf16Count = newCount
  }

  // MARK: - Terminator scanning

  /// Scans `range` of `source` for terminators and returns one slot per line start in
  /// it.
  ///
  /// - Parameter isDocumentTail: Whether `range` ends at the end of the document. This
  ///   is what implements the trailing-terminator rule, and it is a parameter rather
  ///   than a constant because incremental adjustment re-scans interior regions too: a
  ///   region ending mid-document must **not** emit a final line at its own end, since
  ///   the untouched slot that already starts there is about to be shifted into place.
  ///   A tail region always emits one, which is what makes `"a\n"` two lines and `""`
  ///   one.
  private static func scanSlots(
    in source: some UTF16TextSource,
    range: Range<Int>,
    isDocumentTail: Bool,
    buffer: inout UTF16LineBuffer
  ) -> [Slot] {
    var slots: [Slot] = []
    var lineStart = range.lowerBound
    var position = range.lowerBound
    let end = range.upperBound

    while position < end {
      let chunkStart = position
      let chunkEnd = min(chunkStart + scanChunkSize, end)
      var nextPosition = chunkEnd

      buffer.withCodeUnits(of: chunkStart..<chunkEnd, in: source) { units in
        var offset = 0
        let count = units.count
        while offset < count {
          let unit = units[offset]

          if unit == lineFeedUnit {
            slots.append(Slot(start: lineStart, terminatorLength: 1))
            lineStart = chunkStart + offset + 1
            offset += 1
          } else if unit == carriageReturnUnit {
            if offset + 1 < count {
              // The next code unit is in this chunk, so the CRLF question is answerable
              // here. A `\r\n` is ONE terminator of TWO code units.
              let isPair = units[offset + 1] == lineFeedUnit
              let terminatorLength = isPair ? 2 : 1
              slots.append(Slot(start: lineStart, terminatorLength: terminatorLength))
              lineStart = chunkStart + offset + terminatorLength
              offset += terminatorLength
            } else if chunkEnd == end {
              // Last code unit of the region: a lone `\r`, with nothing that could pair
              // with it.
              slots.append(Slot(start: lineStart, terminatorLength: 1))
              lineStart = chunkStart + offset + 1
              offset += 1
            } else {
              // A `\r` on a chunk boundary. Rather than peek across it — which would be
              // a second read shape to get wrong — restart the next chunk *at* the `\r`
              // so the pair is decided by the ordinary path. Progress is guaranteed
              // because the next chunk then begins one code unit before this one ended.
              nextPosition = chunkStart + offset
              offset = count
            }
          } else {
            offset += 1
          }
        }
      }

      position = nextPosition
    }

    // The trailing rule. A tail region always contributes a final line — empty when the
    // region ended with a terminator, which is precisely why `"a\n"` is two lines and
    // `""` is one rather than zero. An interior region contributes one only if it ended
    // mid-line, which a well-formed region never does; emitting it anyway keeps this
    // total rather than trapping on input that cannot happen.
    if isDocumentTail || lineStart < end {
      slots.append(Slot(start: lineStart, terminatorLength: 0))
    }

    return slots
  }
}
