import EscriboCore
import Testing

#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

@testable import SwiftEscribo

/// Sortie 27: the Fountain and Markdown paragraph-geometry **rule sets**, populated onto
/// the Sortie 8 geometry layer in `BuiltInThemes.swift`.
///
/// Everything here exercises the **built-in** themes rather than a synthetic probe theme —
/// `ParagraphGeometryTests` already covers the layer itself (characters-to-points
/// conversion, caching, lookup fallback) against a fixture table built for that purpose.
/// This suite is the one place that would notice if the two rule sets were never actually
/// wired into `EscriboTheme.fountainLight` / `.markdownLight` and friends.
@Suite("Fountain and Markdown geometry rule sets")
struct GeometryRuleSetTests {

  // MARK: - Fountain: character cue, dialogue, and parenthetical margins

  @Test("A character cue and a dialogue line get different headIndents, both from the resolved advance width")
  func cueAndDialogueHaveDifferentHeadIndents() {
    let theme = EscriboTheme.fountainLight
    let styler = EscriboStyler(theme: theme)

    let cue = styler.paragraphStyle(element: .character, depth: 0)
    let dialogue = styler.paragraphStyle(element: .dialogue, depth: 0)
    let parenthetical = styler.paragraphStyle(element: .parenthetical, depth: 0)

    // Non-vacuous: all three are indented at all.
    #expect(cue.headIndent > 0)
    #expect(dialogue.headIndent > 0)
    #expect(parenthetical.headIndent > 0)

    // The three margins are genuinely distinct — a styler that answered one indent for
    // every element would pass a weaker "differs from zero" check trivially.
    #expect(cue.headIndent != dialogue.headIndent)
    #expect(cue.headIndent != parenthetical.headIndent)
    #expect(dialogue.headIndent != parenthetical.headIndent)

    // And both derive from the resolved advance width: declared characters times the same
    // measurement `FontResolver` would hand the styler, not two independently chosen point
    // values that merely happen to differ.
    var resolver = FontResolver()
    let geometry = resolver.geometry(for: styler.baseStyle(element: .character, depth: 0).font)
    #expect(geometry.advanceWidth > 0)

    let declaredCue = theme.paragraphMetrics(for: .character, depth: 0).leftIndentChars
    let declaredDialogue = theme.paragraphMetrics(for: .dialogue, depth: 0).leftIndentChars
    #expect(declaredCue > 0)
    #expect(declaredDialogue > 0)
    #expect(GeometryChecks.isClose(cue.headIndent, declaredCue * geometry.advanceWidth))
    #expect(GeometryChecks.isClose(dialogue.headIndent, declaredDialogue * geometry.advanceWidth))

    // Same story in the dark theme, which shares the rule set.
    let darkStyler = EscriboStyler(theme: .fountainDark)
    let darkCue = darkStyler.paragraphStyle(element: .character, depth: 0)
    let darkDialogue = darkStyler.paragraphStyle(element: .dialogue, depth: 0)
    #expect(darkCue.headIndent != darkDialogue.headIndent)
  }

  @Test("Transitions are right-aligned and centered text is centered, in both Fountain themes")
  func transitionsAndCenteredTextAlign() {
    for theme in [EscriboTheme.fountainLight, .fountainDark] {
      #expect(theme.paragraphMetrics(for: .transition, depth: 0).alignment == .right)
      #expect(theme.paragraphMetrics(for: .centered, depth: 0).alignment == .center)

      let styler = EscriboStyler(theme: theme)
      #expect(styler.paragraphStyle(element: .transition, depth: 0).alignment == .right)
      #expect(styler.paragraphStyle(element: .centered, depth: 0).alignment == .center)
    }
  }

  // MARK: - Fountain is LTR-only; Markdown is RTL-capable (a scope statement, not a defect)

  @Test("Fountain geometry uses .natural nowhere, in either Fountain theme")
  func fountainNeverUsesNaturalAlignment() {
    for theme in [EscriboTheme.fountainLight, .fountainDark] {
      var entries = 0
      for (_, byDepth) in theme.elementParagraphMetrics {
        for (_, metrics) in byDepth {
          entries += 1
          #expect(metrics.alignment != .natural)
        }
      }
      // Non-vacuous: an empty table would pass "uses `.natural` nowhere" trivially, which
      // is exactly the unfalsifiable shape this mission has caught before. Assert the rule
      // set is actually populated — one entry per Fountain element this sortie declares.
      #expect(entries >= 7)
    }
  }

  @Test("Markdown paragraphs use natural alignment, in both Markdown themes")
  func markdownParagraphsUseNaturalAlignment() {
    for theme in [EscriboTheme.markdownLight, .markdownDark] {
      let paragraph = theme.paragraphMetrics(for: .paragraph, depth: 0)
      #expect(paragraph.alignment == .natural)
      // Non-vacuous the other way: `.natural` is also `ParagraphMetrics.default`'s own
      // alignment, so an *absent* table entry would answer `.natural` too, by fallback
      // rather than by rule. Prove this is a real entry, not the absent-element default.
      #expect(!paragraph.isDefault)
      #expect(theme.elementParagraphMetrics[.paragraph] != nil)
    }
  }

  // MARK: - Markdown: heading size scale vs. paragraph geometry

  @Test("A heading's marker span and its content span resolve to the same point size despite the heading's size scale")
  func headingMarkerAndContentShareOnePointSize() throws {
    let theme = EscriboTheme.markdownLight
    let result = StylingFixtures.scan("## Heading text\n")
    let styler = EscriboStyler(theme: theme)

    let headingLine = try #require(result.lineRecords.first { $0.element == .heading })
    // The scale really is non-trivial at this depth, or "same size despite the scale" is
    // proving nothing.
    #expect(theme.sizeScale(for: .heading, depth: headingLine.depth) != 1.0)

    let markerSpan = try #require(
      result.spans.first { $0.kind == .heading && $0.role == .marker })
    let contentSpan = try #require(
      result.spans.first { $0.kind == .heading && $0.role == .content })

    let marker = styler.style(for: markerSpan, on: headingLine)
    let content = styler.style(for: contentSpan, on: headingLine)

    // Architecture §3: size varies per line, never within a line. Markers are never
    // resized, even though the line's own size scale is very much in effect.
    #expect(marker.font.pointSize == content.font.pointSize)
    #expect(marker.font.pointSize == theme.baseFontSize * theme.sizeScale(for: .heading, depth: headingLine.depth))
  }

  // MARK: - Markdown: list and blockquote indents keyed by (ElementKind, depth)

  @Test("A Markdown list at depth 2 has exactly twice the indent of depth 1")
  func listDepth2IsExactlyTwiceDepth1() {
    for theme in [EscriboTheme.markdownLight, .markdownDark] {
      for element in [ElementKind.unorderedListItem, .orderedListItem] {
        let depth1 = theme.paragraphMetrics(for: element, depth: 1).leftIndentChars
        let depth2 = theme.paragraphMetrics(for: element, depth: 2).leftIndentChars

        // Non-vacuous: depth 1 is indented at all, so "twice" is not "zero is twice zero".
        #expect(depth1 > 0)
        #expect(depth2 == depth1 * 2)
      }
    }
  }

  @Test("List indent doubling survives conversion to points, against the resolved advance width")
  func listDepthDoublingHoldsInPoints() {
    let styler = EscriboStyler(theme: .markdownLight)
    let depth1 = styler.paragraphStyle(element: .unorderedListItem, depth: 1)
    let depth2 = styler.paragraphStyle(element: .unorderedListItem, depth: 2)

    #expect(depth1.headIndent > 0)
    #expect(GeometryChecks.isClose(depth2.headIndent, depth1.headIndent * 2))
  }

  @Test("Deeper list depths keep increasing rather than falling back to depth 0's bare geometry")
  func listDepthsBeyondTwoKeepGrowing() {
    let theme = EscriboTheme.markdownLight
    var previous = theme.paragraphMetrics(for: .unorderedListItem, depth: 0).leftIndentChars
    for depth in 1...7 {
      let current = theme.paragraphMetrics(for: .unorderedListItem, depth: depth).leftIndentChars
      #expect(current > previous, "depth \(depth) did not increase over depth \(depth - 1)")
      previous = current
    }
    // Depth 8 is past the scanner's saturation point (`MarkdownBlockState.maxTrackedDepth`
    // is 8, so the deepest depth a line record ever carries is 7) — falling back to depth
    // 0 there is the documented, harmless behavior the lookup already guarantees.
    #expect(
      theme.paragraphMetrics(for: .unorderedListItem, depth: 8)
        == theme.paragraphMetrics(for: .unorderedListItem, depth: 0))
  }

  @Test("Blockquote nesting is indented at depth 0 too, unlike a list's bare top level")
  func blockquoteIndentsEvenAtDepthZero() {
    let theme = EscriboTheme.markdownLight
    let quoteDepth0 = theme.paragraphMetrics(for: .blockquote, depth: 0).leftIndentChars
    let listDepth0 = theme.paragraphMetrics(for: .unorderedListItem, depth: 0).leftIndentChars

    #expect(quoteDepth0 > 0)
    #expect(listDepth0 == 0)
    #expect(theme.paragraphMetrics(for: .blockquote, depth: 1).leftIndentChars > quoteDepth0)
  }

  // MARK: - One geometry layer, two rule sets

  @Test("Both rule sets convert through the same ParagraphMetrics.paragraphStyle(in:) shape")
  func bothRuleSetsShareOneConversion() {
    // Not a test of the conversion itself (ParagraphGeometryTests owns that) — a test that
    // the *rule sets* are ordinary `ParagraphMetrics` values with nothing element-specific
    // about how they become an `NSParagraphStyle`. Same geometry, fed through the same
    // function, produces the same style, whichever rule set it came from.
    let geometry = FontGeometry(advanceWidth: 6, lineHeight: 14)
    let fountainMetrics = EscriboTheme.fountainLight.paragraphMetrics(for: .dialogue, depth: 0)
    let markdownMetrics = EscriboTheme.markdownLight.paragraphMetrics(
      for: .unorderedListItem, depth: 1)

    let fountainStyle = fountainMetrics.paragraphStyle(in: geometry)
    let markdownStyle = markdownMetrics.paragraphStyle(in: geometry)

    #expect(type(of: fountainStyle) == type(of: markdownStyle))
    #expect(GeometryChecks.isClose(
      fountainStyle.headIndent, fountainMetrics.leftIndentChars * geometry.advanceWidth))
    #expect(GeometryChecks.isClose(
      markdownStyle.headIndent, markdownMetrics.leftIndentChars * geometry.advanceWidth))
  }

  // MARK: - Geometry stays theme-controlled and switchable off, for the populated themes too

  @Test("Switching geometry off on a populated theme still answers the default paragraph style")
  func geometryOffOnRealThemesIsStillDefault() {
    var off = EscriboTheme.fountainLight
    off.isGeometryEnabled = false
    let styler = EscriboStyler(theme: off)

    #expect(styler.paragraphStyle(element: .character, depth: 0).isEqual(NSParagraphStyle.default))
    #expect(styler.paragraphStyle(element: .dialogue, depth: 0).isEqual(NSParagraphStyle.default))
  }

  @Test("Stripping a real theme to source drops its populated geometry")
  func sourceStrippingDropsRealGeometry() {
    for theme in [EscriboTheme.fountainLight, .markdownLight] {
      #expect(!theme.elementParagraphMetrics.isEmpty)
      let stripped = theme.strippedToSource()
      #expect(stripped.elementParagraphMetrics.isEmpty)
    }
  }
}
