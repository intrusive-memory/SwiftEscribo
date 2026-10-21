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

  /// The character whose advance stands for one **em** of a proportional face.
  ///
  /// Typography's own definition: an em is historically the width of the letter `m`. For a
  /// monospaced face it measures the same as ``advanceProbe`` — every glyph does — which is
  /// why ``EscriboTheme/columnAdvance(for:)`` and ``EscriboTheme/emWidth(for:)`` agree
  /// there and diverge for the body face.
  static let emProbe: Unicode.Scalar = "m"

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
    let resolved = Self.font(for: spec)
    cache[spec] = resolved
    return resolved
  }

  /// The concrete face for `spec`, with no cache in front of it.
  ///
  /// The same resolution the instance method performs — chain, fallback, traits — lifted
  /// out so that a value type with nowhere to put a cache can still measure. ``EscriboTheme``
  /// is that caller: it is `Equatable` and `Sendable`, so it cannot hold a mutable
  /// resolver, and a published measurement that resolved its face by a *second* route
  /// would be a second D-4 chain with its own way of being wrong.
  ///
  /// Uncached on purpose. A caller on the styling hot path uses the instance method and
  /// gets the cache; a caller measuring a page once per layout does not need one.
  static func font(for spec: FontSpec) -> PlatformFont {
    apply(spec.traits, to: baseFont(for: spec))
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
  private static func baseFont(for spec: FontSpec) -> PlatformFont {
    let size = CGFloat(spec.pointSize)
    switch spec.family {
    case .monospaced:
      return Self.monospacedFont(named: Self.monospacedNames, size: size)
    case .serif:
      return Self.serifSystemFont(ofSize: size)
    default:
      return PlatformFont.systemFont(ofSize: size)
    }
  }

  // MARK: - The serif face

  /// The system font at `size` in its serif design — New York on Apple platforms — or the
  /// plain system font when the platform declines to supply one.
  ///
  /// Name-free, by the same rule as the chain below: the design is requested through the
  /// system font's descriptor, and which face answers is the platform's business. Both
  /// halves of the descriptor round trip can decline, and both fall back to the face the
  /// ``FontFamilyRole/body`` role resolves to — a reader who asked for serif and got the
  /// body face has a cosmetic defect; one who got no font at all does not.
  static func serifSystemFont(ofSize size: CGFloat) -> PlatformFont {
    let system = PlatformFont.systemFont(ofSize: size)
    guard let descriptor = system.fontDescriptor.withDesign(.serif) else { return system }
    #if canImport(AppKit)
      return NSFont(descriptor: descriptor, size: size) ?? system
    #elseif canImport(UIKit)
      return UIFont(descriptor: descriptor, size: size)
    #endif
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
    firstAvailable(of: names, size: size) ?? systemMonospacedFont(ofSize: size)
  }

  /// The system monospaced face at `size`.
  ///
  /// The font service has been seen answering this call with a face whose point size is
  /// zero when it is busy, which collapses every measurement made from it. A face that did
  /// not come back at the size asked for is asked for again, and the plain system font
  /// stands in if the service still will not answer properly.
  private static func systemMonospacedFont(ofSize size: CGFloat) -> PlatformFont {
    for _ in 0..<3 {
      let font = PlatformFont.monospacedSystemFont(ofSize: size, weight: .regular)
      if font.pointSize == size { return font }
    }
    return PlatformFont.systemFont(ofSize: size)
  }

  /// The first of `names` that exists on this system, or `nil` if none does.
  ///
  /// `PlatformFont(name:size:)` rather than `CTFontCreateWithName` deliberately: the
  /// CoreText constructor never fails — it substitutes a face for an unknown name — so a
  /// chain built on it would always stop at its first entry and the fallback would be
  /// unreachable. CoreText does the measuring here, not the choosing.
  ///
  /// A name is only handed to `PlatformFont(name:size:)` after a listing of the installed
  /// families says it exists. That constructor makes a synchronous round trip to the font
  /// registry for a name it does not already know, and that reply has been observed not to
  /// arrive (a test sat for 29 minutes in `NSFont(name:size:)`). The listing is read once
  /// and cached; a name it does not contain resolves to `nil` without the lookup.
  /// `lookup` and `isInstalled` are parameters so a test can observe that.
  static func firstAvailable(
    of names: [String],
    size: CGFloat,
    isInstalled: (String) -> Bool = FontResolver.isInstalled,
    lookup: (String, CGFloat) -> PlatformFont? = FontResolver.namedFont
  ) -> PlatformFont? {
    for name in names where isInstalled(name) {
      if let font = lookup(name, size) { return font }
    }
    return nil
  }

  /// `PlatformFont(name:size:)`, one caller at a time and once per name and size.
  ///
  /// Every resolver instance used to repeat this registry round trip, and when many ran at
  /// once (a parallel test run, several editors opening together) the replies stopped
  /// arriving. Serialising the calls and remembering the answers keeps at most one request
  /// in flight and none repeated; the result for a given name and size is the same font.
  static func namedFont(_ name: String, size: CGFloat) -> PlatformFont? {
    let key = "\(name)\u{0}\(size)"
    namedFontLock.lock()
    defer { namedFontLock.unlock() }
    if let cached = namedFontCache[key] { return cached }
    let font = PlatformFont(name: name, size: size)
    namedFontCache[key] = .some(font)
    return font
  }

  private static let namedFontLock = NSLock()
  nonisolated(unsafe) private static var namedFontCache: [String: PlatformFont?] = [:]

  /// Whether `name` is an installed family or face name, case-insensitively, answered from
  /// a listing read once per process.
  static func isInstalled(_ name: String) -> Bool {
    installedNames.contains(name.lowercased())
  }

  private static let installedNames: Set<String> = {
    var names = Set<String>()
    #if canImport(AppKit)
      let manager = NSFontManager.shared
      names.formUnion(manager.availableFontFamilies.map { $0.lowercased() })
      names.formUnion(manager.availableFonts.map { $0.lowercased() })
    #elseif canImport(UIKit)
      for family in UIFont.familyNames {
        names.insert(family.lowercased())
        names.formUnion(UIFont.fontNames(forFamilyName: family).map { $0.lowercased() })
      }
    #endif
    return names
  }()

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
  private static func apply(_ traits: FontTraits, to font: PlatformFont) -> PlatformFont {
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
