#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

/// The measurements a resolved face contributes to paragraph geometry.
///
/// Two numbers, both measured through CoreText from the face the chain actually produced
/// (D-4). Neither is a constant and neither can be, because the face is not guaranteed:
/// Courier Prime is a user-installed font on the machine this package was written on, and
/// none of the three Courier names is present on a CI runner or an iOS device. What
/// 10 CPI geometry depends on is the face being *monospaced* — so that one character's
/// advance describes every character's — not on which monospaced face it is.
///
/// `internal`: nothing in the 1.0 public surface exposes a measured font, and nothing
/// becomes public speculatively.
struct FontGeometry: Equatable, Sendable {

  /// The advance width of one character, in points. The unit ``ParagraphMetrics``
  /// horizontal fields are counted in.
  var advanceWidth: Double

  /// Ascent + descent + leading, in points. The unit
  /// ``ParagraphMetrics/spaceBeforeLines`` is counted in.
  var lineHeight: Double
}

extension ParagraphAlignment {

  /// This alignment as the text system spells it.
  ///
  /// Total: an alignment this version has never heard of is ``natural``, for the same
  /// reason an unrecognized `SpanKind` resolves to the base style. A paragraph that fails
  /// to align is not a useful error at the point of a per-keystroke attribute lookup.
  var textAlignment: NSTextAlignment {
    switch self {
    case .left: .left
    case .right: .right
    case .center: .center
    default: .natural
    }
  }
}

extension ParagraphMetrics {

  /// This geometry as an `NSParagraphStyle`, converted to points against `geometry`.
  ///
  /// The **only** place in the package where a character count becomes a point value, and
  /// the only place a paragraph style is built. There is no branch here for "geometry
  /// off": switching geometry off resolves every element to ``ParagraphMetrics/default``,
  /// whose fields are all `0`, and `0` characters times any advance width is `0` points.
  /// The off state is the on state's own arithmetic at zero, so the two cannot drift.
  ///
  /// Returned immutable: the styler caches these and hands the same object to every line
  /// sharing an element and depth, so a mutable one would let a caller silently restyle
  /// every paragraph it did not touch.
  func paragraphStyle(in geometry: FontGeometry) -> NSParagraphStyle {
    let style = NSMutableParagraphStyle()
    let left = leftIndentChars * geometry.advanceWidth
    style.headIndent = CGFloat(left)
    style.firstLineHeadIndent = CGFloat(left + firstLineIndentChars * geometry.advanceWidth)
    // Negative is how the text system spells "inward from the trailing edge"; zero is the
    // container's own margin.
    style.tailIndent = CGFloat(-rightIndentChars * geometry.advanceWidth)
    style.paragraphSpacingBefore = CGFloat(spaceBeforeLines * geometry.lineHeight)
    style.alignment = alignment.textAlignment
    return style.copy() as? NSParagraphStyle ?? style
  }
}

/// One line's paragraph style, and the range it applies to.
///
/// Ranges are the **full** `LineRecord.range`, terminator included: a paragraph style that
/// stops short of its terminator leaves the newline carrying the previous paragraph's
/// geometry, which the layout manager resolves by using the wrong one.
///
/// Offsets are UTF-16 code units (Architecture §4), so this converts to `NSRange` for free
/// on the hot path.
struct ParagraphStyleRun: Equatable {

  /// The line's full extent in UTF-16 code units, including its terminator.
  var range: Range<Int>

  /// The style to apply over ``range``.
  var style: NSParagraphStyle
}
