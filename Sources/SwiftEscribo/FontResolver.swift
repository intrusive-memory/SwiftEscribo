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
/// ## Caching
///
/// Resolution walks a name list and builds a descriptor, which is far too much work to
/// repeat per span. The cache is keyed by the whole spec, so a size change or a trait
/// change is a different entry rather than a wrong hit.
struct FontResolver {

  /// The screenplay chain, in preference order. The only family names in the package.
  private static let monospacedNames = ["Courier Prime", "Courier New", "Courier"]

  private var cache: [FontSpec: PlatformFont] = [:]

  init() {}

  /// How many faces are currently cached. Cleared alongside the style cache.
  var cachedFontCount: Int { cache.count }

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

  /// Drops every cached face. One of the things the styler's single invalidation path
  /// does — a font-metric change invalidates sizes, and a size is part of the key.
  mutating func invalidate() {
    cache.removeAll(keepingCapacity: true)
  }

  /// The untraited face for `spec`'s family and size.
  private func baseFont(for spec: FontSpec) -> PlatformFont {
    let size = CGFloat(spec.pointSize)
    switch spec.family {
    case .monospaced:
      return Self.firstAvailable(of: Self.monospacedNames, size: size)
        ?? PlatformFont.monospacedSystemFont(ofSize: size, weight: .regular)
    default:
      return PlatformFont.systemFont(ofSize: size)
    }
  }

  /// The first of `names` that exists on this system, or `nil` if none does.
  ///
  /// Exposed to the type rather than to the instance so a test can exercise the fallback
  /// with a list of deliberately bogus families without owning a resolver.
  static func firstAvailable(of names: [String], size: CGFloat) -> PlatformFont? {
    for name in names {
      if let font = PlatformFont(name: name, size: size) { return font }
    }
    return nil
  }

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
