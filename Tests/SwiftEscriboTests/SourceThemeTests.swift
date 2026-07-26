import EscriboCore
import Testing

@testable import SwiftEscribo

/// The cheapest possible proof that the styling abstraction did not leak: under the
/// source theme, every span in a document resolves to identical attributes regardless of
/// kind, style, or role.
///
/// REQUIREMENTS.md § Source mode is a theme states the consequence plainly — if this test
/// cannot be written, mode switching has grown a code path it was not supposed to have.
@Suite("Source theme")
struct SourceThemeTests {

  /// The three ways a source-mode styler can legitimately be built. All three must
  /// collapse identically.
  static let sourceEnvironments: [EditorStyleEnvironment] = [
    EditorStyleEnvironment(theme: .source),
    EditorStyleEnvironment(theme: .markdownLight, mode: .source),
    EditorStyleEnvironment(theme: .fountainDark, mode: .source, appearance: .dark),
  ]

  @Test(
    "Every span in a mixed document resolves to one attribute dictionary",
    arguments: sourceEnvironments)
  func everySpanCollapsesToBase(environment: EditorStyleEnvironment) throws {
    let result = StylingFixtures.scan(StylingFixtures.mixedMarkdown)
    let styler = EscriboStyler(environment: environment)

    // The fixture has to actually vary, or "identical regardless of kind and role" is a
    // statement about one span.
    #expect(Set(result.spans.map(\.kind)).count >= 3)
    #expect(Set(result.spans.map(\.role)).count == 2)
    #expect(result.spans.count >= 20)

    let firstSpan = try #require(result.spans.first)
    let firstLine = try StylingFixtures.record(for: firstSpan, in: result)
    let expected = styler.style(for: firstSpan, on: firstLine)
    let expectedAttributes = StylingFixtures.comparable(styler.attributes(for: expected))

    for span in result.spans {
      let line = try StylingFixtures.record(for: span, in: result)
      let resolved = styler.style(for: span, on: line)
      #expect(resolved == expected, "kind \(span.kind.rawValue) role \(span.role.rawValue)")

      let attributes = StylingFixtures.comparable(styler.attributes(for: span, on: line))
      #expect(attributes.isEqual(expectedAttributes))
    }
  }

  @Test(
    "Every kind, every style combination, and both roles collapse to base",
    arguments: sourceEnvironments)
  func everyAxisCollapsesToBase(environment: EditorStyleEnvironment) {
    let styler = EscriboStyler(environment: environment)
    // The scanner emits no emphasis until Sortie 19, so the style axis is swept here
    // rather than harvested from a scan. Kinds and elements are the real vocabulary,
    // plus one kind and one element nothing emits.
    let kinds: [SpanKind] = [
      .text, .heading, .codeBlock, .codeInfoString, SpanKind(rawValue: "unregistered"),
    ]
    let elements: [ElementKind] = [
      .paragraph, .blank, .heading, .codeFence, .codeBlock,
      ElementKind(rawValue: "unregistered"),
    ]
    let expected = styler.baseStyle(element: .paragraph, depth: 0)

    // Mismatches are collected rather than asserted per iteration: this sweep is several
    // thousand combinations, and one failure naming itself is more useful than several
    // thousand recorded expectations.
    var mismatches: [String] = []
    var combinations = 0
    for kind in kinds {
      for style in StylingFixtures.allStyleCombinations {
        for role in [SpanRole.content, .marker] {
          for element in elements {
            for depth in [0, 1, 3, 6] {
              combinations += 1
              let resolved = styler.style(
                kind: kind, style: style, role: role, element: element, depth: depth)
              if resolved != expected {
                mismatches.append(
                  "\(kind.rawValue)/\(style.rawValue)/\(role.rawValue)"
                    + "/\(element.rawValue)@\(depth)")
              }
            }
          }
        }
      }
    }
    #expect(combinations == 7680)
    #expect(mismatches.isEmpty, "\(mismatches.prefix(5))")
  }

  @Test("Stripping a theme to source empties every table and stops marker dimming")
  func strippingEmptiesTheTables() {
    let stripped = EscriboTheme.markdownDark.strippedToSource()
    #expect(stripped.kindStyles.isEmpty)
    #expect(stripped.styleStyles.isEmpty)
    #expect(stripped.elementSizeScales.isEmpty)
    #expect(stripped.markerOpacity == 1)
    // The base survives, so switching modes keeps the reader's family and size.
    #expect(stripped.base == EscriboTheme.markdownDark.base)
    #expect(stripped.baseFontSize == EscriboTheme.markdownDark.baseFontSize)
  }

  @Test("Switching live to source and back restores the original resolution")
  func modeSwitchIsReversible() throws {
    let result = StylingFixtures.scan(StylingFixtures.mixedMarkdown)
    let styler = EscriboStyler(environment: EditorStyleEnvironment(theme: .markdownLight))

    var before: [ResolvedStyle] = []
    for span in result.spans {
      let line = try StylingFixtures.record(for: span, in: result)
      before.append(styler.style(for: span, on: line))
    }

    styler.environment.mode = .source
    var sourceStyles: [ResolvedStyle] = []
    for span in result.spans {
      let line = try StylingFixtures.record(for: span, in: result)
      sourceStyles.append(styler.style(for: span, on: line))
    }
    #expect(Set(sourceStyles.map(\.font.pointSize)).count == 1)

    styler.environment.mode = .live
    var after: [ResolvedStyle] = []
    for span in result.spans {
      let line = try StylingFixtures.record(for: span, in: result)
      after.append(styler.style(for: span, on: line))
    }
    #expect(before == after)
    #expect(before != sourceStyles)
  }

  @Test("The built-in themes cover both languages in both appearances")
  func builtInsCoverBothLanguages() {
    let combinations: [(Language, EscriboAppearance)] = [
      (.markdown, .light), (.markdown, .dark), (.fountain, .light), (.fountain, .dark),
    ]
    var seen: Set<String> = []
    for (language, appearance) in combinations {
      seen.insert(EscriboTheme.builtIn(language: language, appearance: appearance).name)
    }
    #expect(seen.count == 4)
    // An unknown language is not an error — it resolves to the Markdown theme, matching
    // the core's own treatment of an unknown language as plain text.
    #expect(
      EscriboTheme.builtIn(language: Language(rawValue: "klingon"), appearance: .light)
        == EscriboTheme.markdownLight)
  }
}
