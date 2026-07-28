import EscriboCore
import Testing

#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

@testable import SwiftEscribo

/// Floating-point comparisons for a layer whose numbers are measured from a face this test
/// is forbidden to name.
///
/// Every assertion in these suites is a **ratio or a proportionality**, never an absolute:
/// "twice the size is twice the indent", "twice the characters is twice the points". An
/// absolute expectation would encode the advance width of whichever face happened to
/// resolve on the machine the test was written on, which is exactly the CI failure D-4
/// exists to prevent.
enum GeometryChecks {

  /// Whether `value` is `expected` to within a relative tolerance.
  static func isClose(_ value: Double, _ expected: Double, tolerance: Double = 1e-6) -> Bool {
    abs(value - expected) <= tolerance * Swift.max(1, abs(expected))
  }

  /// Whether `value` is `expected` to within a relative tolerance.
  static func isClose(_ value: CGFloat, _ expected: CGFloat, tolerance: Double = 1e-6) -> Bool {
    isClose(Double(value), Double(expected), tolerance: tolerance)
  }

  /// The `ElementKind` values 1.0 defines, plus one nothing emits.
  ///
  /// Listed rather than derived: `ElementKind` is a struct with static members precisely so
  /// that adding one is a minor release, which means there is no `allCases` and a theme
  /// must survive a kind it has never seen.
  static let everyElement: [ElementKind] = [
    .paragraph, .blank, .heading, .codeFence, .codeBlock,
    ElementKind(rawValue: "an-element-no-grammar-emits"),
  ]

  /// The five fields ``ParagraphMetrics`` controls, as the text system spells them.
  static func controlledFields(_ style: NSParagraphStyle) -> [Double] {
    [
      Double(style.headIndent),
      Double(style.firstLineHeadIndent),
      Double(style.tailIndent),
      Double(style.paragraphSpacingBefore),
      Double(style.alignment.rawValue),
    ]
  }
}

/// Character-declared geometry, converted to points against the resolved face.
///
/// REQUIREMENTS.md § Geometry: "the theme stores characters and the styler converts to
/// points against the resolved font's advance width. Storing points would silently break
/// every margin the moment a user changes font size."
@Suite("Paragraph geometry")
struct ParagraphGeometryTests {

  // MARK: - Fixtures

  /// Geometry for every element 1.0 defines, with values chosen so no two fields and no
  /// two elements coincide — a conversion that swapped `headIndent` for
  /// `firstLineHeadIndent`, or a lookup that answered the wrong element, would show.
  ///
  /// This lives in a test, not in a built-in theme. The Fountain and Markdown rule sets
  /// are a later sortie's work; what is under test here is the layer they will populate.
  static let geometryTable: [ElementKind: [Int: ParagraphMetrics]] = [
    .paragraph: [
      0: ParagraphMetrics(
        leftIndentChars: 4, rightIndentChars: 6, firstLineIndentChars: 2,
        spaceBeforeLines: 0.5, alignment: .left)
    ],
    .heading: [
      0: ParagraphMetrics(leftIndentChars: 1, spaceBeforeLines: 1),
      1: ParagraphMetrics(leftIndentChars: 2, spaceBeforeLines: 2, alignment: .center),
      3: ParagraphMetrics(leftIndentChars: 3, firstLineIndentChars: -3, alignment: .right),
    ],
    .blank: [0: ParagraphMetrics(spaceBeforeLines: 0.25)],
    .codeFence: [0: ParagraphMetrics(leftIndentChars: 8, alignment: .left)],
    .codeBlock: [0: ParagraphMetrics(leftIndentChars: 8, rightIndentChars: 1)],
  ]

  /// A theme with real geometry and a real per-element size scale, so "the margin is
  /// measured against the *line's* font" is observable.
  static func probeTheme(geometryEnabled: Bool = true) -> EscriboTheme {
    EscriboTheme(
      name: "geometry probe",
      baseFontSize: 12,
      base: TokenStyle(foreground: .black, family: .monospaced),
      elementSizeScales: [.heading: [0: 1.0, 1: 2.0]],
      elementParagraphMetrics: geometryTable,
      isGeometryEnabled: geometryEnabled,
      markerOpacity: 0.4
    )
  }

  /// The advance width and line height the probe theme's *paragraph* lines are measured
  /// against — the same numbers the styler will use, obtained the same way.
  static func paragraphFontGeometry(_ styler: EscriboStyler) -> FontGeometry {
    var resolver = FontResolver()
    return resolver.geometry(for: styler.baseStyle(element: .paragraph, depth: 0).font)
  }

  // MARK: - Default geometry is the text system's default

  @Test("Default metrics convert to the text system's own default paragraph style")
  func defaultMetricsAreTheDefaultStyle() {
    // Across wildly different faces, because "no geometry" must not depend on what was
    // measured: zero characters is zero points at any advance width.
    for geometry in [
      FontGeometry(advanceWidth: 7.2, lineHeight: 14),
      FontGeometry(advanceWidth: 100, lineHeight: 400),
      FontGeometry(advanceWidth: 0, lineHeight: 0),
    ] {
      let style = ParagraphMetrics.default.paragraphStyle(in: geometry)
      #expect(style.isEqual(NSParagraphStyle.default))
      #expect(
        GeometryChecks.controlledFields(style)
          == GeometryChecks.controlledFields(NSParagraphStyle.default))
    }
    #expect(ParagraphMetrics.default.isDefault)
  }

  @Test("Geometry switched off produces the default paragraph style for every ElementKind")
  func geometryOffIsAlwaysTheDefaultStyle() {
    let off = EscriboStyler(theme: Self.probeTheme(geometryEnabled: false))
    let on = EscriboStyler(theme: Self.probeTheme())

    var differences = 0
    for element in GeometryChecks.everyElement {
      for depth in [0, 1, 2, 3, 6, 99] {
        let disabled = off.paragraphStyle(element: element, depth: depth)
        #expect(
          disabled.isEqual(NSParagraphStyle.default),
          "\(element.rawValue)@\(depth) is not the default style with geometry off")
        #expect(off.environment.theme.paragraphMetrics(for: element, depth: depth).isDefault)

        if !on.paragraphStyle(element: element, depth: depth).isEqual(NSParagraphStyle.default) {
          differences += 1
        }
      }
    }
    // The same sweep with geometry on must mostly *not* be the default style, or the
    // assertion above is passing because the table is empty.
    #expect(differences >= 20)
  }

  // MARK: - Characters to points

  @Test("Doubling the resolved font size doubles the computed point indent")
  func indentDoublesWithFontSize() {
    let styler = EscriboStyler(theme: Self.probeTheme())
    let single = styler.paragraphStyle(element: .paragraph, depth: 0)

    // A font-metric change — one of the four triggers — is what a user changing text size
    // actually does. It runs through the same single invalidation path as any other.
    styler.environment.metrics = FontMetrics(pointSizeScale: 2)
    let doubled = styler.paragraphStyle(element: .paragraph, depth: 0)

    // Non-vacuous: the margins are real before they are doubled.
    #expect(single.headIndent > 0)
    #expect(single.firstLineHeadIndent > single.headIndent)
    #expect(single.tailIndent < 0)
    #expect(single.paragraphSpacingBefore > 0)

    #expect(GeometryChecks.isClose(doubled.headIndent, single.headIndent * 2))
    #expect(GeometryChecks.isClose(doubled.firstLineHeadIndent, single.firstLineHeadIndent * 2))
    #expect(GeometryChecks.isClose(doubled.tailIndent, single.tailIndent * 2))
    // Vertical metrics may be rounded by the face; horizontal advances are not.
    #expect(
      GeometryChecks.isClose(
        doubled.paragraphSpacingBefore, single.paragraphSpacingBefore * 2, tolerance: 0.02))
  }

  @Test("Indents are the declared character count times the resolved advance width")
  func indentsAreCharactersTimesAdvanceWidth() throws {
    let styler = EscriboStyler(theme: Self.probeTheme())
    let geometry = Self.paragraphFontGeometry(styler)
    let declared = try #require(Self.geometryTable[.paragraph]?[0])
    let style = styler.paragraphStyle(element: .paragraph, depth: 0)

    #expect(geometry.advanceWidth > 0)
    #expect(
      GeometryChecks.isClose(style.headIndent, declared.leftIndentChars * geometry.advanceWidth))
    #expect(
      GeometryChecks.isClose(
        style.tailIndent, -declared.rightIndentChars * geometry.advanceWidth))
    #expect(
      GeometryChecks.isClose(
        style.paragraphSpacingBefore, declared.spaceBeforeLines * geometry.lineHeight))
  }

  @Test("Twice the characters is twice the points, at a fixed size")
  func pointsAreLinearInCharacters() {
    let geometry = FontGeometry(advanceWidth: 7.2, lineHeight: 14)
    let single = ParagraphMetrics(leftIndentChars: 5, rightIndentChars: 3, spaceBeforeLines: 1)
    let doubled = ParagraphMetrics(leftIndentChars: 10, rightIndentChars: 6, spaceBeforeLines: 2)

    let a = single.paragraphStyle(in: geometry)
    let b = doubled.paragraphStyle(in: geometry)
    #expect(GeometryChecks.isClose(b.headIndent, a.headIndent * 2))
    #expect(GeometryChecks.isClose(b.tailIndent, a.tailIndent * 2))
    #expect(GeometryChecks.isClose(b.paragraphSpacingBefore, a.paragraphSpacingBefore * 2))
  }

  @Test("The first-line indent is an offset from the left indent, so hanging indents work")
  func firstLineIndentIsRelative() {
    let geometry = FontGeometry(advanceWidth: 10, lineHeight: 20)

    let flush = ParagraphMetrics(leftIndentChars: 4).paragraphStyle(in: geometry)
    #expect(flush.firstLineHeadIndent == flush.headIndent)

    let indented =
      ParagraphMetrics(leftIndentChars: 4, firstLineIndentChars: 2).paragraphStyle(in: geometry)
    #expect(indented.headIndent == 40)
    #expect(indented.firstLineHeadIndent == 60)

    // A hanging indent — a list item whose continuation lines sit under its text — is a
    // negative offset, and must not be able to pull the first line past the container.
    let hanging =
      ParagraphMetrics(leftIndentChars: 4, firstLineIndentChars: -4).paragraphStyle(in: geometry)
    #expect(hanging.headIndent == 40)
    #expect(hanging.firstLineHeadIndent == 0)
  }

  @Test("A line's margins are measured against that line's own point size")
  func marginsFollowTheLinesSize() {
    // The probe theme sets depth-1 headings at 2× and gives them 2 characters of indent
    // against the paragraph's 4. A layer that measured every element against the base size
    // would report exactly half the paragraph's indent; measuring against the line's own
    // font reports the same number, because twice the size is twice the advance.
    let styler = EscriboStyler(theme: Self.probeTheme())
    let paragraph = styler.paragraphStyle(element: .paragraph, depth: 0)
    let heading = styler.paragraphStyle(element: .heading, depth: 1)

    #expect(styler.environment.theme.sizeScale(for: .heading, depth: 1) == 2)
    #expect(GeometryChecks.isClose(heading.headIndent, paragraph.headIndent))
    // And the two really are different character counts on differently sized lines.
    #expect(
      styler.environment.theme.paragraphMetrics(for: .heading, depth: 1).leftIndentChars
        != styler.environment.theme.paragraphMetrics(for: .paragraph, depth: 0).leftIndentChars)
  }

  // MARK: - Lookup

  @Test("Geometry is keyed by (ElementKind, depth), and unlisted depths fall back")
  func lookupIsKeyedByElementAndDepth() {
    let theme = Self.probeTheme()

    #expect(theme.paragraphMetrics(for: .heading, depth: 1).leftIndentChars == 2)
    #expect(theme.paragraphMetrics(for: .heading, depth: 3).alignment == .right)
    // A depth no entry mentions falls back to the element's depth-0 entry — the same rule
    // as the size scale, so a rule set author learns one shape rather than two.
    #expect(
      theme.paragraphMetrics(for: .heading, depth: 99)
        == theme.paragraphMetrics(for: .heading, depth: 0))
    // An element no entry mentions has no geometry. Never a trap, never a crash.
    #expect(theme.paragraphMetrics(for: ElementKind(rawValue: "nothing-emits-this"), depth: 0)
      .isDefault)
  }

  @Test("Alignment reaches the paragraph style, in every direction a theme can ask for")
  func alignmentIsCarriedThrough() {
    let geometry = FontGeometry(advanceWidth: 10, lineHeight: 20)
    let cases: [(ParagraphAlignment, NSTextAlignment)] = [
      (.natural, .natural), (.left, .left), (.right, .right), (.center, .center),
      (ParagraphAlignment(rawValue: "diagonal"), .natural),
    ]
    for (alignment, expected) in cases {
      let style = ParagraphMetrics(alignment: alignment).paragraphStyle(in: geometry)
      #expect(style.alignment == expected, "\(alignment.rawValue)")
    }
  }

  @Test("Stripping a theme to source drops its geometry")
  func sourceModeHasNoGeometry() {
    let stripped = Self.probeTheme().strippedToSource()
    #expect(stripped.elementParagraphMetrics.isEmpty)
    for element in GeometryChecks.everyElement {
      #expect(stripped.paragraphMetrics(for: element, depth: 0).isDefault)
    }
  }

  // MARK: - Application over line records

  @Test("Every line record gets a style over its full range, terminator included")
  func runsCoverEveryLineRecord() throws {
    let result = StylingFixtures.scan(StylingFixtures.mixedMarkdown)
    let styler = EscriboStyler(theme: Self.probeTheme())
    let runs = styler.paragraphStyleRuns(for: result.lineRecords)

    #expect(runs.count == result.lineRecords.count)
    #expect(runs.count > 5)

    for (run, record) in zip(runs, result.lineRecords) {
      // The record's `range`, not its `contentRange`: a paragraph style that stops short of
      // its terminator leaves the newline carrying the previous paragraph's geometry.
      #expect(run.range == record.range)
      #expect(run.style.isEqual(styler.paragraphStyle(for: record)))
    }

    // The runs tile the document, so applying them leaves no line unstyled.
    var expectedStart = 0
    for run in runs {
      #expect(run.range.lowerBound == expectedStart)
      expectedStart = run.range.upperBound
    }
    #expect(expectedStart == StylingFixtures.mixedMarkdown.utf16.count)

    // Lines classified differently really do get different geometry, or this suite is
    // asserting that one style applies everywhere.
    let byElement = Dictionary(grouping: runs.indices) { result.lineRecords[$0].element }
    #expect(byElement.count >= 3)
  }

  @Test("Lines sharing an element and depth share one cached paragraph style")
  func stylesAreCachedPerLineKey() throws {
    let result = StylingFixtures.scan(StylingFixtures.mixedMarkdown)
    let styler = EscriboStyler(theme: Self.probeTheme())
    let runs = styler.paragraphStyleRuns(for: result.lineRecords)

    let distinctKeys = Set(
      result.lineRecords.map { LineStyleKey(element: $0.element, depth: $0.depth) })
    #expect(styler.cachedParagraphStyleCount == distinctKeys.count)
    #expect(styler.cachedParagraphStyleCount < result.lineRecords.count)

    // Cached objects are shared by identity, which is what makes a per-line run list cheap
    // — and why the conversion hands back an immutable style rather than a mutable one.
    let paragraphRuns = runs.indices.filter { result.lineRecords[$0].element == .paragraph }
    let styles = paragraphRuns.map { runs[$0].style }
    #expect(styles.count >= 2)
    for style in styles.dropFirst() {
      #expect(style === styles[0])
    }
    #expect(!(styles[0] is NSMutableParagraphStyle))
  }
}
