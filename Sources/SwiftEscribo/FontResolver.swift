import CoreText

#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

/// Turns a ``FontSpec`` into a concrete face, and is the only place in the package that
/// knows a font family has a name.
///
/// ## The chain (D-4)
///
/// Courier Prime → Courier New → Courier → `.monospacedSystemFont`. The last step is not
/// optional and not a defensive flourish: **none** of the three Courier faces is
/// guaranteed present on a GitHub Actions runner or on an iOS device, and Courier Prime
/// in particular is a user-installed font on the machine this package was written on. A
/// chain that ends at Courier resolves locally and returns `nil` in CI.
///
/// What screenplay geometry actually depends on is the face being *monospaced*, not which
/// monospaced face it is — margins are declared in characters at 10 CPI and converted
/// against the resolved advance width (REQUIREMENTS.md § Geometry). So no test may assert
/// a resolved family name, and ``FontSpec`` deliberately gives them no way to.
///
/// No font is bundled as a package resource. `Package.swift` declares no `resources:`
/// block on either shipping target and this sortie does not add one.
///
/// ## Measurement
///
/// This is also where a face becomes numbers. Geometry is declared in characters and
/// multiples of line height (REQUIREMENTS.md § Geometry), so something has to ask the
/// resolved face how wide a character is — and that something must be *here*, holding the
/// same cache and the same chain, or the layer ends up with two resolvers that can
/// disagree about which face it measured.
///
/// ## Caching
///
/// Resolution walks a name list and builds a descriptor, which is far too much work to
/// repeat per span. The cache is keyed by the whole spec, so a size change or a trait
/// change is a different entry rather than a wrong hit. Measurements are cached by the
/// same key and dropped by the same ``invalidate()``: a second store with its own
/// lifetime is a second invalidation path, and there is exactly one.
struct FontResolver {

  /// The screenplay chain, in preference order. The only family names in the package.
  private static let monospacedNames = ["Courier Prime", "Courier New", "Courier"]

  /// The character whose advance stands for every character's.
  ///
  /// Sound only because the face is monospaced, which is the property the chain exists to
  /// guarantee and the property the tests assert in place of a family name.
  private static let advanceProbe: Unicode.Scalar = "0"

  private var cache: [FontSpec: PlatformFont] = [:]

  private var geometries: [FontSpec: FontGeometry] = [:]

  init() {}

  /// How many faces are currently cached. Cleared alongside the style cache.
  var cachedFontCount: Int { cache.count }

  /// How many measurements are currently cached. Cleared alongside the faces.
  var cachedGeometryCount: Int { geometries.count }

  /// The concrete face for `spec`.
  ///
  /// Total: every branch ends at a real font. There is no optional and no trap, because
  /// this runs inside a text-view callback where neither has a useful meaning.
  mutating func font(for spec: FontSpec) -> PlatformFont {
    if let cached = cache[spec] { return cached }
    let resolved = apply(spec.traits, to: baseFont(for: spec))
    cache[spec] = resolved
    return resolved
  }

  /// The measurements paragraph geometry converts against, for `spec`'s face.
  mutating func geometry(for spec: FontSpec) -> FontGeometry {
    if let cached = geometries[spec] { return cached }
    let measured = Self.geometry(of: font(for: spec))
    geometries[spec] = measured
    return measured
  }

  /// Drops every cached face and every cached measurement. One of the things the styler's
  /// single invalidation path does — a font-metric change invalidates sizes, and a size is
  /// part of the key.
  mutating func invalidate() {
    cache.removeAll(keepingCapacity: true)
    geometries.removeAll(keepingCapacity: true)
  }

  /// The untraited face for `spec`'s family and size.
  private func baseFont(for spec: FontSpec) -> PlatformFont {
    let size = CGFloat(spec.pointSize)
    switch spec.family {
    case .monospaced:
      return Self.monospacedFont(named: Self.monospacedNames, size: size)
    default:
      return PlatformFont.systemFont(ofSize: size)
    }
  }

  // MARK: - The chain (D-4)

  /// The first of `names` that exists on this system, falling back to the system's own
  /// monospaced face when **none** of them does.
  ///
  /// The whole of D-4, in one total function. It takes the name list as a parameter rather
  /// than reading ``monospacedNames`` so that a test can drive the exact code path the
  /// editor uses with a list of deliberately unavailable families — which is the only way
  /// to exercise the final fallback on a machine where the first name resolves.
  static func monospacedFont(named names: [String], size: CGFloat) -> PlatformFont {
    firstAvailable(of: names, size: size)
      ?? PlatformFont.monospacedSystemFont(ofSize: size, weight: .regular)
  }

  /// The first of `names` that exists on this system, or `nil` if none does.
  ///
  /// `PlatformFont(name:size:)` rather than `CTFontCreateWithName` deliberately: the
  /// CoreText constructor never fails — it substitutes a face for an unknown name — so a
  /// chain built on it would always stop at its first entry and the fallback would be
  /// unreachable. CoreText does the measuring here, not the choosing.
  static func firstAvailable(of names: [String], size: CGFloat) -> PlatformFont? {
    for name in names {
      if let font = PlatformFont(name: name, size: size) { return font }
    }
    return nil
  }

  // MARK: - Measurement

  /// `font`'s advance width and line height, measured through CoreText.
  static func geometry(of font: PlatformFont) -> FontGeometry {
    let ctFont = font as CTFont
    return FontGeometry(
      advanceWidth: advanceWidth(of: font, for: advanceProbe),
      lineHeight: Double(
        CTFontGetAscent(ctFont) + CTFontGetDescent(ctFont) + CTFontGetLeading(ctFont))
    )
  }

  /// The advance width of `character` in `font`, in points.
  ///
  /// Also the shape of the test that stands in for asserting a family name: a face is
  /// monospaced when `i` and `W` measure the same here, and that is the only property
  /// 10 CPI geometry actually needs from it (D-4).
  ///
  /// Total. A face with no glyph for the probe — which the digit zero does not have in any
  /// text face, but a caller may ask about anything — falls back to a fraction of the
  /// point size rather than to zero, because a zero advance collapses every margin on the
  /// page and does so silently.
  static func advanceWidth(of font: PlatformFont, for character: Unicode.Scalar) -> Double {
    let ctFont = font as CTFont
    var utf16 = Array(String(character).utf16)
    var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
    guard
      CTFontGetGlyphsForCharacters(ctFont, &utf16, &glyphs, utf16.count),
      let glyph = glyphs.first
    else {
      return Double(font.pointSize) * unmeasurableAdvanceRatio
    }
    var advance = CGSize.zero
    CTFontGetAdvancesForGlyphs(ctFont, .horizontal, [glyph], &advance, 1)
    return Double(advance.width)
  }

  /// The advance-to-point-size ratio assumed when a glyph cannot be measured at all.
  /// Roughly Courier's, and never reached in practice — it exists so the measuring path
  /// has no failure mode rather than to be accurate.
  private static let unmeasurableAdvanceRatio = 0.6

  /// `font` with `traits` applied through its descriptor.
  ///
  /// The one function whose body differs by platform: AppKit and UIKit spell the same two
  /// symbolic traits differently and disagree about which half of the round trip is
  /// failable. Both fall back to the untraited face rather than to nothing — a heading
  /// that lost its bold is a cosmetic defect; a heading that lost its font is not.
  private func apply(_ traits: FontTraits, to font: PlatformFont) -> PlatformFont {
    guard !traits.isEmpty else { return font }
    var symbolic: PlatformSymbolicTraits = []
    #if canImport(AppKit)
      if traits.contains(.bold) { symbolic.insert(.bold) }
      if traits.contains(.italic) { symbolic.insert(.italic) }
      let descriptor = font.fontDescriptor.withSymbolicTraits(symbolic)
      return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    #elseif canImport(UIKit)
      if traits.contains(.bold) { symbolic.insert(.traitBold) }
      if traits.contains(.italic) { symbolic.insert(.traitItalic) }
      guard let descriptor = font.fontDescriptor.withSymbolicTraits(symbolic) else { return font }
      return UIFont(descriptor: descriptor, size: font.pointSize)
    #endif
  }
}
