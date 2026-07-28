/// A document the scanner can read as **UTF-16 code units**, a run at a time.
///
/// This is the seam that lets `EscriboCore` stay pure Foundation while the editor
/// scans an `NSTextStorage` in place. REQUIREMENTS.md § Edits and text access is
/// explicit about why it exists: `NSTextStorage` is `NSString`-backed, and bridging
/// 120 KB to a Swift `String` on every keystroke would exceed the entire per-keystroke
/// budget before scanning began. `String` conforms here; `NSTextStorage` conforms in
/// `SwiftEscribo` (Sortie 9), which is why this protocol is `public` — a conformance
/// across a module boundary is impossible otherwise.
///
/// ## The one requirement that matters: reads are bulk, never per code unit
///
/// ``copyUTF16CodeUnits(in:into:)`` takes a **range** and fills a buffer. It is called
/// once per line — or once per scan chunk — and never once per character. That is not
/// a convenience, it is the performance contract: a `func codeUnit(at: Int) -> UInt16`
/// requirement would put a witness-table dispatch and an `NSString` `characterAtIndex:`
/// call on the innermost loop of every scan, and a one-megabyte line would pay it a
/// million times. REQUIREMENTS.md § Degenerate input forbids any algorithm worse than
/// linear in line length; this shape is how the constant factor stays small too.
///
/// Use ``UTF16LineBuffer`` to do the reading, so the destination buffer is reused
/// across lines rather than allocated per line.
///
/// ## Coordinates
///
/// Every offset in this protocol — and everywhere else in the package — is a **UTF-16
/// code-unit offset**, never a `String.Index` and never a `Character` count. An
/// astral-plane character occupies two of them.
public protocol UTF16TextSource {

  /// The document's length in UTF-16 code units.
  var utf16Count: Int { get }

  /// Copies the code units in `range` into the front of `buffer`.
  ///
  /// - Parameters:
  ///   - range: A UTF-16 code-unit range, which must lie within `0..<utf16Count`.
  ///   - buffer: A destination with at least `range.count` elements. Only the first
  ///     `range.count` elements are written; anything beyond them is left alone.
  func copyUTF16CodeUnits(in range: Range<Int>, into buffer: UnsafeMutableBufferPointer<UInt16>)
}

extension String: UTF16TextSource {

  public var utf16Count: Int { utf16.count }

  public func copyUTF16CodeUnits(
    in range: Range<Int>,
    into buffer: UnsafeMutableBufferPointer<UInt16>
  ) {
    guard !range.isEmpty else { return }
    let view = utf16
    let lower = view.index(view.startIndex, offsetBy: range.lowerBound)
    let upper = view.index(lower, offsetBy: range.count)
    var out = 0
    for unit in view[lower..<upper] {
      buffer[out] = unit
      out += 1
    }
  }
}

/// A reusable staging buffer for reading whole lines out of a ``UTF16TextSource``.
///
/// The buffer grows to the largest run ever asked of it and is then reused, so a scan
/// over a 4 000-line document performs one allocation rather than 4 000. Keep one per
/// scan, not one per line — a fresh instance per call would reintroduce exactly the
/// allocation this type exists to avoid.
///
/// The yielded buffer is valid only for the duration of `body`, and is exactly
/// `range.count` elements long; the scratch storage behind it is generally larger and
/// its tail holds stale code units from previous reads. Reading past `count` is
/// therefore a correctness bug, not merely a bounds question, which is why the closure
/// receives a right-sized `UnsafeBufferPointer` rather than the whole scratch.
struct UTF16LineBuffer {

  /// Storage, reused across reads. Never handed out directly.
  private var scratch: [UInt16] = []

  /// The smallest allocation worth making — one read of a typical line, or of a scan
  /// chunk, without a second growth step immediately after.
  private static let minimumCapacity = 4096

  init() {}

  /// Reads `range` out of `source` and yields it as a contiguous buffer.
  ///
  /// One call to ``UTF16TextSource/copyUTF16CodeUnits(in:into:)`` — one dispatch —
  /// per call to this method. Call it once per line, never once per code unit.
  mutating func withCodeUnits<R>(
    of range: Range<Int>,
    in source: some UTF16TextSource,
    _ body: (UnsafeBufferPointer<UInt16>) -> R
  ) -> R {
    if scratch.count < range.count {
      scratch = [UInt16](repeating: 0, count: max(range.count, Self.minimumCapacity))
    }
    return scratch.withUnsafeMutableBufferPointer { storage in
      let destination = UnsafeMutableBufferPointer(rebasing: storage[0..<range.count])
      source.copyUTF16CodeUnits(in: range, into: destination)
      return body(UnsafeBufferPointer(destination))
    }
  }
}
