import EscriboCore
import Testing

@testable import SwiftEscribo

/// The four invalidation triggers, and the one path they all run through.
///
/// REQUIREMENTS.md § Theme: "One invalidation path, four triggers — a fifth trigger that
/// forgets to invalidate is how an editor ends up with dark-mode text on a light
/// background."
@Suite("Styler cache")
struct StylerCacheTests {

  /// The four things — and only these four — that may change a resolved answer.
  enum Trigger: String, CaseIterable, Sendable {
    case theme
    case mode
    case appearance
    case fontMetrics
  }

  /// A styler with a populated cache, over a real scan.
  private func warmedStyler() throws -> EscriboStyler {
    let result = StylingFixtures.scan(StylingFixtures.mixedMarkdown)
    let styler = EscriboStyler(
      environment: EditorStyleEnvironment(
        theme: .markdownLight, mode: .live, appearance: .light, metrics: .nominal))
    for span in result.spans {
      let line = try StylingFixtures.record(for: span, in: result)
      _ = styler.attributes(for: span, on: line)
    }
    // Paragraph geometry is cached alongside the styles and dropped by the same single
    // invalidation path, so it is warmed here rather than in a suite of its own — a
    // geometry cache with its own clearing rule would be the fifth trigger this suite
    // exists to make impossible.
    _ = styler.paragraphStyleRuns(for: result.lineRecords)
    #expect(styler.cachedStyleCount > 0)
    #expect(styler.cachedParagraphStyleCount > 0)
    #expect(styler.fontResolver.cachedFontCount > 0)
    #expect(styler.fontResolver.cachedGeometryCount > 0)
    #expect(!styler.isCacheEmpty)
    return styler
  }

  @Test("Each of the four triggers empties the cache", arguments: Trigger.allCases)
  func triggerEmptiesTheCache(trigger: Trigger) throws {
    let styler = try warmedStyler()

    switch trigger {
    case .theme:
      styler.environment.theme = .markdownDark
    case .mode:
      styler.environment.mode = .source
    case .appearance:
      styler.environment.appearance = .dark
    case .fontMetrics:
      styler.environment.metrics = FontMetrics(pointSizeScale: 1.5)
    }

    #expect(styler.cachedStyleCount == 0)
    #expect(styler.cachedParagraphStyleCount == 0)
    #expect(styler.fontResolver.cachedFontCount == 0)
    #expect(styler.fontResolver.cachedGeometryCount == 0)
    #expect(styler.isCacheEmpty)
  }

  @Test("A repeated lookup with no trigger is a cache hit")
  func repeatedLookupHits() {
    let styler = EscriboStyler(theme: .markdownLight)
    styler.resetStatistics()

    _ = styler.style(kind: .heading, style: [], role: .marker, element: .heading, depth: 2)
    #expect(styler.cacheMisses == 1)
    #expect(styler.cacheHits == 0)

    for _ in 0..<10 {
      _ = styler.style(kind: .heading, style: [], role: .marker, element: .heading, depth: 2)
    }
    #expect(styler.cacheHits == 10)
    #expect(styler.cacheMisses == 1)
    #expect(styler.cachedStyleCount == 1)
  }

  @Test("Reassigning an equal environment is not a trigger")
  func equalEnvironmentDoesNotInvalidate() throws {
    let styler = try warmedStyler()
    let cached = styler.cachedStyleCount

    // A host that pushes its full configuration on every layout pass must not throw away
    // the cache for saying the same thing twice.
    let snapshot = styler.environment
    styler.environment = snapshot
    styler.environment.theme = .markdownLight
    styler.environment.mode = .live
    styler.environment.appearance = .light
    styler.environment.metrics = .nominal

    #expect(styler.cachedStyleCount == cached)

    styler.resetStatistics()
    let result = StylingFixtures.scan(StylingFixtures.mixedMarkdown)
    for span in result.spans {
      let line = try StylingFixtures.record(for: span, in: result)
      _ = styler.style(for: span, on: line)
    }
    #expect(styler.cacheMisses == 0)
    #expect(styler.cacheHits == result.spans.count)
  }

  @Test("The cache key is (SpanKind, StyleSet, SpanRole) within a line key")
  func cacheKeyDistinguishesTheThreeAxes() {
    let styler = EscriboStyler(theme: .markdownLight)
    styler.resetStatistics()

    _ = styler.style(kind: .heading, style: [], role: .content, element: .heading, depth: 1)
    _ = styler.style(kind: .text, style: [], role: .content, element: .heading, depth: 1)
    _ = styler.style(kind: .heading, style: .strong, role: .content, element: .heading, depth: 1)
    _ = styler.style(kind: .heading, style: [], role: .marker, element: .heading, depth: 1)
    // Four distinct keys, four misses — no axis is being collapsed.
    #expect(styler.cacheMisses == 4)
    #expect(styler.cachedStyleCount == 4)

    // The line key partitions the cache: the same span key on a differently sized line is
    // a different entry, which is what makes per-line point size cacheable at all.
    _ = styler.style(kind: .heading, style: [], role: .content, element: .heading, depth: 2)
    #expect(styler.cacheMisses == 5)
    #expect(styler.cachedStyleCount == 5)
  }

  @Test("Invalidation actually changes the answer, not just the cache count")
  func invalidationYieldsFreshAnswers() {
    let styler = EscriboStyler(theme: .markdownLight)
    let light = styler.style(kind: .heading, style: [], role: .content, element: .heading, depth: 1)
    styler.environment.theme = .markdownDark
    let dark = styler.style(kind: .heading, style: [], role: .content, element: .heading, depth: 1)
    #expect(light != dark)
    #expect(light.font.pointSize == dark.font.pointSize)
  }
}
