/// One text mutation, expressed in **old-text coordinates**.
///
/// This is the single most load-bearing convention in the package, so it is stated
/// without hedging:
///
/// - ``range`` indexes the document **as it was before the edit**, in UTF-16 code
///   units. It is the range that was *replaced*.
/// - ``replacementLength`` is the length, in UTF-16 code units, of the text that
///   replaced it. A **length**, never the replacement string — the scanner reads the
///   new text through the document, not through the edit, so carrying the string would
///   allocate per keystroke and buy nothing.
///
/// The reverse convention — a range in the *new* text plus a delta — is not
/// unambiguous, and mixing the two silently corrupts offsets rather than failing. Read
/// this type exactly one way: old-text coordinates, replacement expressed as a length.
///
/// ## Worked example
///
/// The document is `"Hello world"`. The user selects `world` and types `there`:
///
/// ```swift
/// TextEdit(range: 6..<11, replacementLength: 5)
/// ```
///
/// `6..<11` are offsets into `"Hello world"` — the old text, where `world` lives.
/// `5` is the length of `"there"`. ``changeInLength`` is `0`; the document is now
/// `"Hello there"`. Three more cases against that same starting document:
///
/// | Edit                        | `range`  | `replacementLength` | `changeInLength` |
/// | --------------------------- | -------- | ------------------- | ---------------- |
/// | Delete `" world"`           | `5..<11` | `0`                 | `-6`             |
/// | Insert `"!"` at the end     | `11..<11`| `1`                 | `+1`             |
/// | Type `x` over the whole doc | `0..<11` | `1`                 | `-10`            |
///
/// An insertion is an **empty range in old coordinates**, not a position in new ones.
///
/// ## Deriving one from `NSTextStorage`
///
/// `textStorage(_:didProcessEditing:range:changeInLength:)` reports `editedRange` in
/// **new**-text coordinates, so the translation is:
///
/// ```swift
/// TextEdit(
///   range: editedRange.location ..< (editedRange.location + editedRange.length - changeInLength),
///   replacementLength: editedRange.length
/// )
/// ```
///
/// The location needs no adjustment — an edit does not move its own start — but the
/// length does, and that is precisely the subtraction that gets forgotten.
public struct TextEdit: Equatable, Sendable {
  /// The range that was replaced, in **UTF-16 code units of the text before the edit**.
  ///
  /// Empty for a pure insertion.
  public let range: Range<Int>

  /// The length in UTF-16 code units of the text that replaced ``range``.
  ///
  /// Zero for a pure deletion.
  public let replacementLength: Int

  /// How much the document grew or shrank: `replacementLength - range.count`.
  ///
  /// Named for `NSTextStorage`'s `changeInLength` because it is the same quantity, and
  /// because every offset held across an edit is adjusted by exactly this value.
  public var changeInLength: Int { replacementLength - range.count }

  /// Creates an edit in old-text coordinates.
  ///
  /// - Parameters:
  ///   - range: The replaced range, in UTF-16 offsets into the text *before* the edit.
  ///   - replacementLength: The UTF-16 length of the replacing text.
  public init(range: Range<Int>, replacementLength: Int) {
    self.range = range
    self.replacementLength = replacementLength
  }
}
