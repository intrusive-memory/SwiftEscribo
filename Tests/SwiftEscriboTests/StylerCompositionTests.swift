import EscriboCore
import Testing

@testable import SwiftEscribo

/// Composition order, marker dimming, unknown-kind fallback, and the rule that point size
/// is a property of the line rather than of the span.
@Suite("Styler composition")
struct StylerCompositionTests {

  // MARK: - Marker dimming

  @Test("A marker and its content sibling differ only in foreground alpha")
  func markerDiffersOnlyInAlpha() throws {
    let theme = EscriboTheme.markdownLight
    let result = StylingFixtures.scan("## Heading text\n")
    let styler = EscriboStyler(theme: theme)

    let headings = result.spans.filter { $0.kind == .heading }
    let markerSpan = try #require(headings.first { $0.role == .marker })
    let contentSpan = try #require(headings.first { $0.role == .content })
    // The scanner's own guarantee, restated here because everything below depends on it:
    // the two spans differ in nothing but their role.
    #expect(markerSpan.kind == contentSpan.kind)
    #expect(markerSpan.style == contentSpan.style)

    let line = try StylingFixtures.record(for: contentSpan, in: result)
    let marker = styler.style(for: markerSpan, on: line)
    let content = styler.style(for: contentSpan, on: line)

    // Same font, same point size — Architecture §3. Marker dimming is alpha-only;
    // altering metrics mid-line makes text jitter while typing.
    #expect(marker.font == content.font)
    #expect(marker.font.pointSize == content.font.pointSize)
    #expect(marker.font.traits == content.font.traits)
    #expect(marker.font.family == content.font.family)

    // Same color, dimmed. Only the alpha channel moved.
    #expect(marker.foreground.red == content.foreground.red)
    #expect(marker.foreground.green == content.foreground.green)
    #expect(marker.foreground.blue == content.foreground.blue)
    #expect(marker.foreground.alpha == content.foreground.alpha * theme.markerOpacity)
    #expect(marker.foreground.alpha < content.foreground.alpha)

    // "Differ *only* in foreground alpha", asserted as a whole-value equality rather than
    // field by field, so a field added to `ResolvedStyle` later cannot slip through.
    #expect(marker != content)
    var undimmed = marker
    undimmed.foreground = content.foreground
    #expect(undimmed == content)
  }

  @Test("Marker dimming applies to every kind the mixed document contains")
  func markerDimmingIsUniversal() throws {
    let theme = EscriboTheme.markdownDark
    let result = StylingFixtures.scan(StylingFixtures.mixedMarkdown)
    let styler = EscriboStyler(theme: theme)

    var markerCount = 0
    for span in result.spans where span.role == .marker {
      markerCount += 1
      let line = try StylingFixtures.record(for: span, in: result)
      let marker = styler.style(for: span, on: line)
      let asContent = styler.style(
        kind: span.kind, style: span.style, role: .content,
        element: line.element, depth: line.depth)
      var undimmed = marker
      undimmed.foreground = asContent.foreground
      #expect(undimmed == asContent)
      #expect(marker.foreground.alpha == asContent.foreground.alpha * theme.markerOpacity)
    }
    // A vacuously passing loop would be worse than no test.
    #expect(markerCount >= 5)
  }

  // MARK: - Unknown kinds

  @Test("An unrecognized SpanKind resolves to the base style instead of trapping")
  func unknownKindFallsBackToBase() {
    let styler = EscriboStyler(theme: .markdownLight)
    let unknown = SpanKind(rawValue: "sortie-7-kind-no-scanner-emits")

    let resolved = styler.style(
      kind: unknown, style: [], role: .content, element: .paragraph, depth: 0)
    #expect(resolved == styler.baseStyle(element: .paragraph, depth: 0))

    // And the theme really does style *something*, so the assertion above is not passing
    // because every kind resolves to base.
    let heading = styler.style(
      kind: .heading, style: [], role: .content, element: .paragraph, depth: 0)
    #expect(heading != resolved)
  }

  @Test("An unrecognized kind still honors the line's size and the marker role")
  func unknownKindStillGetsLineGeometry() {
    let styler = EscriboStyler(theme: .markdownLight)
    let unknown = SpanKind(rawValue: "sortie-7-kind-no-scanner-emits")

    let onHeading = styler.style(
      kind: unknown, style: [], role: .content, element: .heading, depth: 1)
    let onParagraph = styler.style(
      kind: unknown, style: [], role: .content, element: .paragraph, depth: 0)
    #expect(onHeading.font.pointSize > onParagraph.font.pointSize)

    let dimmed = styler.style(
      kind: unknown, style: [], role: .marker, element: .paragraph, depth: 0)
    #expect(
      dimmed.foreground.alpha
        == onParagraph.foreground.alpha * EscriboTheme.markdownLight.markerOpacity)
  }

  @Test("An unrecognized StyleSet flag contributes nothing rather than trapping")
  func unknownStyleFlagFallsBack() {
    let styler = EscriboStyler(theme: .markdownLight)
    // Bit 15 is not a 1.0 member. A theme has no entry for it, so it must contribute
    // nothing — the same forward-compatibility story as an unknown kind.
    let future = StyleSet(rawValue: 1 << 15)
    let withFlag = styler.style(
      kind: .text, style: future, role: .content, element: .paragraph, depth: 0)
    let without = styler.style(
      kind: .text, style: [], role: .content, element: .paragraph, depth: 0)
    #expect(withFlag == without)
  }

  // MARK: - Composition order

  @Test("Traits union across stages while everything else overrides")
  func traitsUnionAndTheRestOverrides() {
    let theme = EscriboTheme(
      name: "composition probe",
      baseFontSize: 10,
      base: TokenStyle(foreground: .black, family: .body, traits: [], underline: false),
      kindStyles: [
        .heading: TokenStyle(foreground: EscriboColor(red: 1, green: 0, blue: 0), traits: .bold)
      ],
      styleStyles: [
        .inlineCode: TokenStyle(family: .monospaced),
        .emphasis: TokenStyle(traits: .italic),
      ],
      markerOpacity: 0.5
    )
    let styler = EscriboStyler(theme: theme)

    let codeInHeading = styler.style(
      kind: .heading, style: [.inlineCode, .emphasis], role: .content,
      element: .paragraph, depth: 0)

    // Traits union: the kind stage's bold survives the style stage's italic. This is the
    // difference between bold-mono and mono-only, and it is the thing REQUIREMENTS.md
    // says two implementers would not guess the same way.
    #expect(codeInHeading.font.traits == [.bold, .italic])
    // Family overrides: the style stage's monospaced beats the base's body face.
    #expect(codeInHeading.font.family == .monospaced)
    // Foreground overrides: the kind stage's red survives, because neither style entry
    // contributes a foreground.
    #expect(codeInHeading.foreground == EscriboColor(red: 1, green: 0, blue: 0))
  }

  @Test("The role stage touches the foreground alpha and nothing else")
  func roleStageIsAlphaOnly() {
    let theme = EscriboTheme(
      name: "role probe",
      baseFontSize: 11,
      base: TokenStyle(
        foreground: EscriboColor(red: 0.2, green: 0.4, blue: 0.6),
        background: EscriboColor(red: 0.9, green: 0.9, blue: 0.9),
        family: .monospaced,
        traits: .bold,
        underline: true,
        strikethrough: true
      ),
      markerOpacity: 0.25
    )
    let styler = EscriboStyler(theme: theme)
    let content = styler.style(
      kind: .text, style: [], role: .content, element: .paragraph, depth: 0)
    let marker = styler.style(
      kind: .text, style: [], role: .marker, element: .paragraph, depth: 0)

    #expect(marker.background == content.background)
    #expect(marker.underline == content.underline)
    #expect(marker.strikethrough == content.strikethrough)
    #expect(marker.font == content.font)
    #expect(marker.foreground.alpha == 0.25)
  }

  // MARK: - DL-26: point size comes from the line

  @Test("Every span on an indented heading line resolves to the same point size")
  func pointSizeIsUniformWithinALine() throws {
    // The grammar emits this line's three-space indent as a `.text`-KIND span, not as
    // part of the heading's marker. A styler that scaled size off `SpanKind` would render
    // that indent at body size on a line set at heading size — within-line uniformity
    // broken by the construct the scale exists for. Size therefore comes from the line's
    // `ElementKind` and `depth`.
    let result = StylingFixtures.scan("   ### Indented heading\nbody\n")
    let styler = EscriboStyler(theme: .markdownLight)

    let headingLine = try #require(result.lineRecords.first { $0.element == .heading })
    #expect(headingLine.depth == 3)

    let lineSpans = result.spans.filter { headingLine.range.contains($0.range.lowerBound) }
    // The indent span is the point of this fixture; if the grammar ever stops emitting it
    // the test must be revisited rather than silently weakened.
    #expect(lineSpans.contains { $0.kind == .text })
    #expect(lineSpans.contains { $0.kind == .heading && $0.role == .marker })
    #expect(lineSpans.contains { $0.kind == .heading && $0.role == .content })

    let sizes = Set(lineSpans.map { styler.style(for: $0, on: headingLine).font.pointSize })
    #expect(sizes.count == 1)

    // And the line really is scaled — otherwise uniformity is trivially true.
    let bodyLine = try #require(result.lineRecords.first { $0.element == .paragraph })
    let bodySize = styler.baseStyle(element: bodyLine.element, depth: bodyLine.depth).font.pointSize
    let headingSize = try #require(sizes.first)
    #expect(headingSize > bodySize)
  }

  @Test("Heading size scales are keyed by depth, and unlisted depths fall back")
  func headingSizeScaleIsKeyedByDepth() {
    let theme = EscriboTheme.markdownLight
    #expect(theme.sizeScale(for: .heading, depth: 1) > theme.sizeScale(for: .heading, depth: 2))
    #expect(theme.sizeScale(for: .heading, depth: 6) == 1.0)
    // A depth no entry mentions falls back to the element's depth-0 entry.
    #expect(theme.sizeScale(for: .heading, depth: 99) == theme.sizeScale(for: .heading, depth: 0))
    // An element no entry mentions is unscaled. Never a trap, never a zero.
    #expect(theme.sizeScale(for: ElementKind(rawValue: "nothing-emits-this"), depth: 0) == 1.0)
  }

  @Test("Font metrics scale every line uniformly")
  func fontMetricsScaleEverything() {
    let styler = EscriboStyler(theme: .markdownLight)
    let nominal = styler.baseStyle(element: .heading, depth: 2).font.pointSize
    styler.environment.metrics = FontMetrics(pointSizeScale: 2)
    #expect(styler.baseStyle(element: .heading, depth: 2).font.pointSize == nominal * 2)
  }
}
