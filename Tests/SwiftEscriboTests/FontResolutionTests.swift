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

// MARK: - The published measurement (0.4.0)

/// ``EscriboTheme/columnAdvance(for:)`` and ``EscriboTheme/emWidth(for:)``, the two
/// measurements 0.4.0 publishes so that a host laying out a page stops transcribing the
/// D-4 chain.
///
/// **No test here asserts a point constant**, for the reason the suite above gives at
/// length: the value is the output of whichever face the chain resolves to on this
/// machine, and Courier Prime is present on a developer's Mac and absent from a runner.
/// Escribir's own screenplay-page test already states this rule about itself — "asserted
/// against the type's own advance measurement rather than a point constant, because the
/// point value is the output of the measured face and this test must pass on a machine
/// whose chain resolves differently" — and these tests follow it.
///
/// What is asserted instead: positivity, linearity in point size, the `0.6` em ratio the
/// monospaced chain produces, and the agree/differ relationship between the two calls.
///
/// ## Deliberately **not** `@MainActor`, unlike every coordinator suite
///
/// `CoordinatorFixtures` explains why those are pinned: the coordinator is main-thread-owned
/// by contract and `NSTextStorage` is an AppKit/UIKit object. Neither applies here. Nothing
/// in this suite builds an editor, a coordinator, a styler, or a text storage — it calls two
/// pure methods on an `EscriboTheme` value and, once, a local `FontResolver`. The rationale
/// is "annotate where the thing under test lives", and what lives here is CoreText
/// measurement over `Sendable` values, which the sibling ``FontResolutionTests`` suite above
/// already exercises unannotated in this same file. An unnecessary `@MainActor` would assert
/// an isolation requirement the measurement does not have.
@Suite("Published font measurement")
struct ThemeFontMeasurementTests {

  static let theme = EscriboTheme.markdownLight

  static func monospaced(_ size: Double) -> FontSpec {
    FontSpec(family: .monospaced, pointSize: size)
  }

  static func body(_ size: Double) -> FontSpec {
    FontSpec(family: .body, pointSize: size)
  }

  @Test("A column advance is positive at the theme's base size")
  func columnAdvanceIsPositive() {
    // The floor. A zero advance collapses every margin on the page and does so silently,
    // which is why `FontResolver` has an unmeasurable-glyph fallback at all.
    #expect(Self.theme.columnAdvance(for: Self.monospaced(12)) > 0)
    #expect(Self.theme.emWidth(for: Self.monospaced(12)) > 0)
    #expect(Self.theme.columnAdvance(for: Self.body(12)) > 0)
    #expect(Self.theme.emWidth(for: Self.body(12)) > 0)
  }

  @Test("A column advance scales linearly with point size")
  func columnAdvanceScalesLinearly() {
    // The property 10 CPI geometry actually depends on: doubling the size doubles the
    // measure, so a page laid out in characters survives a size change. Asserted as a
    // ratio rather than a difference so it holds whatever the face measures.
    let single = Self.theme.columnAdvance(for: Self.monospaced(12))
    let double = Self.theme.columnAdvance(for: Self.monospaced(24))
    let triple = Self.theme.columnAdvance(for: Self.monospaced(36))

    #expect(abs(double - single * 2) < 0.01, "24 pt must measure twice 12 pt")
    #expect(abs(triple - single * 3) < 0.01, "36 pt must measure three times 12 pt")
    #expect(abs(Self.theme.emWidth(for: Self.monospaced(24)) - single * 2) < 0.01)
  }

  @Test("A monospaced column advance is very nearly six tenths of an em")
  func monospacedAdvanceIsSixTenthsOfAnEm() {
    // Courier's ratio, and the same 0.6 the unmeasurable-advance fallback assumes. It is
    // also the relationship behind Escribir's page anchor: sixty characters of 12 pt
    // monospaced text is 60 × 0.6 × 12 = 432 pt, which is six inches at 72 pt to the inch.
    //
    // A window rather than an equality, because the chain may resolve to the system's own
    // monospaced face on a machine with no Courier at all, and that face is near 0.6
    // without being exactly it.
    for size in [8.0, 12.0, 18.0, 36.0] {
      let ratio = Self.theme.columnAdvance(for: Self.monospaced(size)) / size
      #expect(ratio > 0.5, "a monospaced advance of \(ratio) em is implausibly narrow")
      #expect(ratio < 0.7, "a monospaced advance of \(ratio) em is implausibly wide")
    }

    // The six-inch measure, stated as the app states it: a relationship, not a constant.
    let sixtyColumns = Self.theme.columnAdvance(for: Self.monospaced(12)) * 60
    #expect(sixtyColumns > 380, "sixty columns of 12 pt is in the region of six inches")
    #expect(sixtyColumns < 480)
  }

  @Test("The two measurements agree for a monospaced face and differ for a proportional one")
  func emAndColumnAgreeOnlyWhereTheyShould() {
    // The distinction that makes both calls worth having. Every glyph in a monospaced face
    // has the same advance, so the column and the em are the same number; in a
    // proportional face `m` is the widest lowercase letter and `0` is not, so they are not.
    let monoColumn = Self.theme.columnAdvance(for: Self.monospaced(12))
    let monoEm = Self.theme.emWidth(for: Self.monospaced(12))
    #expect(
      abs(monoColumn - monoEm) < 0.01,
      "a monospaced face measures `0` and `m` identically — that is what monospaced means")

    let bodyColumn = Self.theme.columnAdvance(for: Self.body(12))
    let bodyEm = Self.theme.emWidth(for: Self.body(12))
    #expect(
      bodyEm > bodyColumn,
      "in a proportional face `m` is wider than `0`; measured \(bodyEm) against \(bodyColumn)")
  }

  @Test("The published measurement is the same number the styler lays out with")
  func publishedMeasurementMatchesTheStylersOwn() {
    // The point of publishing it: one chain, one number. If these diverged, a host would
    // lay its page out to a width the editor inside it does not agree with — which is
    // exactly the bug that deleting Escribir's transcribed copy is meant to prevent.
    let spec = Self.monospaced(12)
    var resolver = FontResolver()
    #expect(Self.theme.columnAdvance(for: spec) == resolver.geometry(for: spec).advanceWidth)
  }

  @Test("Traits do not change a monospaced advance")
  func traitsDoNotChangeTheColumn() {
    // Bold Courier is still Courier-width. Asserted because the trait path goes through a
    // font descriptor round trip that could silently substitute a proportional face.
    let plain = Self.theme.columnAdvance(for: Self.monospaced(12))
    let bold = Self.theme.columnAdvance(
      for: FontSpec(family: .monospaced, traits: .bold, pointSize: 12))
    #expect(
      abs(plain - bold) < 0.01,
      "a bold monospaced face must keep its advance; \(plain) against \(bold)")
  }
}
