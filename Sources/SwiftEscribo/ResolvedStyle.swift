#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

/// The output of composition: one span's appearance, as a comparable value.
///
/// The styler caches *these*, not attribute dictionaries, and produces a dictionary from
/// one only at the moment it is applied. Three reasons:
///
/// 1. `[NSAttributedString.Key: Any]` is not `Equatable`, so a cache of dictionaries
///    cannot be checked for the properties this layer exists to guarantee. "A marker and
///    its content differ only in foreground alpha" is a one-line comparison against this
///    type and an object-graph interrogation against a dictionary.
/// 2. Font *identity* is not font *equality*: two `NSFont`s built by different routes to
///    the same face and size are not reliably the same object. ``FontSpec`` compares by
///    intent, which is what the invariant is actually about.
/// 3. No family name appears anywhere in this type, so no test can assert one (D-4).
struct ResolvedStyle: Equatable, Sendable {

  /// The font, by intent. Its point size comes from the *line*, never from the span.
  var font: FontSpec

  /// The foreground color, with the marker stage's alpha multiplication already applied.
  var foreground: EscriboColor

  /// The background color, or `nil` for "emit no background attribute".
  var background: EscriboColor?

  /// Whether the run is underlined.
  var underline: Bool

  /// Whether the run is struck through.
  var strikethrough: Bool
}

extension ResolvedStyle {

  /// This style as text-storage attributes.
  ///
  /// - Parameter resolver: Supplies the concrete face for ``font``. Passed in rather than
  ///   owned so the font cache is shared across every span of a scan.
  ///
  /// Keys are emitted only when they carry something: no background attribute when there
  /// is no background, no underline attribute when there is no underline. Total tiling
  /// means `setAttributes(_:range:)` replaces everything on the range anyway, so an
  /// absent key is genuinely absent rather than stale.
  func attributes(resolver: inout FontResolver) -> [NSAttributedString.Key: Any] {
    var attributes: [NSAttributedString.Key: Any] = [
      .font: resolver.font(for: font),
      .foregroundColor: foreground.platformColor,
    ]
    if let background {
      attributes[.backgroundColor] = background.platformColor
    }
    if underline {
      attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
    }
    if strikethrough {
      attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
    }
    return attributes
  }
}
