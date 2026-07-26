import Testing

#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

@testable import SwiftEscribo

/// The D-4 resolution chain, asserted by the properties 10 CPI geometry depends on rather
/// than by a family name.
///
/// **No test here names a face.** Courier Prime is installed on the machine this package
/// was written on and is absent from a GitHub Actions runner and from an iOS device; a
/// test that asserted a family name, or an advance width derived from one, would pass here
/// and fail in CI — a flaky test authored on day one and diagnosed on day thirty. What
/// makes character-declared geometry correct is that the resolved face is *monospaced* and
/// that its advance scales with its point size. Both are asserted; which face satisfies
/// them is not this layer's business.
@Suite("Font resolution")
struct FontResolutionTests {

  /// Families that exist on no system, used to drive the chain past every named entry and
  /// into its final fallback. Deliberately absurd: a plausible name might one day be real.
  static let unavailableFamilies = [
    "Escribo Nonexistent Face Alpha",
    "Escribo Nonexistent Face Beta",
    "Escribo Nonexistent Face Gamma",
  ]

  /// The advance widths of a narrow and a wide letter. Equal exactly when the face is
  /// monospaced, which is the property that lets one character's advance describe a
  /// margin measured in characters.
  static func narrowAndWideAdvances(_ font: PlatformFont) -> (narrow: Double, wide: Double) {
    (FontResolver.advanceWidth(of: font, for: "i"), FontResolver.advanceWidth(of: font, for: "W"))
  }

  // MARK: - The face is monospaced

  @Test("The resolved screenplay face is monospaced", arguments: [8.0, 12.0, 24.0, 48.0])
  func resolvedFaceIsMonospaced(size: Double) {
    var resolver = FontResolver()
    let font = resolver.font(for: FontSpec(family: .monospaced, pointSize: size))
    let (narrow, wide) = Self.narrowAndWideAdvances(font)

    #expect(narrow > 0)
    #expect(narrow == wide)
  }

  @Test("Resolution still yields a monospaced face when no named family is available")
  func fallbackFaceIsMonospaced() {
    // The real path with the real function, driven with a name list that cannot resolve.
    // This is the only way to exercise the final fallback on a machine where the first
    // name in the chain does resolve — and the fallback is the branch CI actually takes.
    let font = FontResolver.monospacedFont(named: Self.unavailableFamilies, size: 12)
    let (narrow, wide) = Self.narrowAndWideAdvances(font)

    #expect(FontResolver.firstAvailable(of: Self.unavailableFamilies, size: 12) == nil)
    #expect(narrow > 0)
    #expect(narrow == wide)
    #expect(font.pointSize == 12)
  }

  @Test("An empty name list resolves rather than failing")
  func emptyNameListResolves() {
    // Total on every input: there is no arrangement of the chain that produces no font,
    // because a text-view callback has nothing useful to do with one.
    let font = FontResolver.monospacedFont(named: [], size: 10)
    let (narrow, wide) = Self.narrowAndWideAdvances(font)
    #expect(narrow == wide)
    #expect(narrow > 0)
  }

  // MARK: - Measurement

  @Test("Advance width and line height scale linearly with point size")
  func measurementScalesWithPointSize() {
    var resolver = FontResolver()
    let single = resolver.geometry(for: FontSpec(family: .monospaced, pointSize: 12))
    let doubled = resolver.geometry(for: FontSpec(family: .monospaced, pointSize: 24))

    #expect(single.advanceWidth > 0)
    #expect(single.lineHeight > 0)
    #expect(GeometryChecks.isClose(doubled.advanceWidth, single.advanceWidth * 2))
    // Vertical metrics can be rounded by the face itself, so this is proportional rather
    // than exact. Horizontal is exact, and horizontal is what margins are made of.
    #expect(GeometryChecks.isClose(doubled.lineHeight, single.lineHeight * 2, tolerance: 0.02))
  }

  @Test("The body face is measured too, whatever its advances turn out to be")
  func bodyFaceIsMeasurable() {
    var resolver = FontResolver()
    let geometry = resolver.geometry(for: FontSpec(family: .body, pointSize: 14))
    // Not asserted monospaced: the reading face is not required to be, and Markdown
    // geometry is expressed in the same units regardless.
    #expect(geometry.advanceWidth > 0)
    #expect(geometry.lineHeight > 0)
  }

  // MARK: - Caching

  @Test("Measurements are cached by spec and dropped by the resolver's invalidation")
  func measurementsAreCachedAndInvalidated() {
    var resolver = FontResolver()
    _ = resolver.geometry(for: FontSpec(family: .monospaced, pointSize: 12))
    _ = resolver.geometry(for: FontSpec(family: .monospaced, pointSize: 12))
    #expect(resolver.cachedGeometryCount == 1)

    // Size is part of the key, so a size change is a different entry rather than a wrong
    // hit — the whole reason margins may be cached at all.
    _ = resolver.geometry(for: FontSpec(family: .monospaced, pointSize: 24))
    #expect(resolver.cachedGeometryCount == 2)

    resolver.invalidate()
    #expect(resolver.cachedGeometryCount == 0)
    #expect(resolver.cachedFontCount == 0)
  }
}
