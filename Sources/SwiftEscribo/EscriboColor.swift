#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

/// A color, as a theme stores it: four sRGB components and nothing else.
///
/// ## Why not `NSColor` / `UIColor`
///
/// A theme is a `Sendable` value type holding a lookup table (REQUIREMENTS.md § Theme),
/// and it is compared for equality by the styler to decide whether its cache is still
/// valid. Platform color classes are reference types whose `Sendable` story is awkward,
/// whose equality depends on color-space bookkeeping a theme author never asked about,
/// and whose *dynamic* (appearance-aware) instances would make "appearance change" an
/// invisible mutation rather than one of the styler's four declared invalidation
/// triggers. Storing components makes light and dark two theme *values*, which is what
/// the built-ins already are.
///
/// ## Why alpha is a stored component
///
/// Marker dimming is alpha-only on the foreground (Architecture §3), and
/// ``EscriboTheme/markerOpacity`` is a single scalar. Multiplying one `Double` is exact,
/// order-independent, and directly assertable — "the marker and its content differ only
/// in foreground alpha" is a test that compares two `Double`s rather than one that
/// interrogates a color object.
public struct EscriboColor: Hashable, Sendable {

  /// The red component, 0…1 in the sRGB color space.
  public var red: Double

  /// The green component, 0…1 in the sRGB color space.
  public var green: Double

  /// The blue component, 0…1 in the sRGB color space.
  public var blue: Double

  /// The alpha component, 0…1. `1` is fully opaque.
  public var alpha: Double

  /// Creates a color from sRGB components.
  public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  /// Creates an opaque gray.
  public init(white: Double, alpha: Double = 1) {
    self.init(red: white, green: white, blue: white, alpha: alpha)
  }

  /// This color with its alpha multiplied by `factor`, clamped to 0…1.
  ///
  /// The whole of the role stage of composition. Nothing else about the color moves,
  /// which is what makes Architecture §3 a property of the type rather than a rule an
  /// implementer has to remember.
  public func withAlphaMultiplied(by factor: Double) -> EscriboColor {
    var copy = self
    copy.alpha = min(max(alpha * factor, 0), 1)
    return copy
  }

  /// Opaque black — the foreground of last resort when a theme's base sets none.
  ///
  /// A theme with no base foreground is a malformed theme, but "malformed theme" is not
  /// an error path here for the same reason "malformed document" is not one in the
  /// scanner: there is nothing useful an error could mean at the point of a per-keystroke
  /// attribute lookup.
  public static let black = EscriboColor(white: 0)

  /// Opaque white.
  public static let white = EscriboColor(white: 1)
}

extension EscriboColor {

  /// This color as the platform's concrete color class.
  ///
  /// Built in sRGB explicitly on both platforms so a color round-trips to the same
  /// components it was declared with.
  var platformColor: PlatformColor {
    #if canImport(AppKit)
      return NSColor(
        srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    #elseif canImport(UIKit)
      return UIColor(
        red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    #endif
  }
}
