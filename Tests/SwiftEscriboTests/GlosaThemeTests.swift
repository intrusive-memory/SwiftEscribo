import EscriboCore
import Testing

@testable import SwiftEscribo

/// Every GLOSA span kind is coloured by every built-in language theme, and the source
/// theme stays uncoloured.
@Suite("GLOSA theme colours")
struct GlosaThemeTests {

  static let glosaKinds: [SpanKind] = [
    .glosaTag, .glosaAttributeName, .glosaAttributeValue, .glosaPunctuation,
    .glosaJSONKey, .glosaJSONString, .glosaJSONNumber, .glosaJSONLiteral,
  ]

  static let themes: [EscriboTheme] = [
    .markdownLight, .markdownDark, .fountainLight, .fountainDark,
  ]

  @Test("Every glosa kind has a style in every language theme", arguments: themes)
  func everyKindStyled(theme: EscriboTheme) {
    for kind in Self.glosaKinds {
      #expect(theme.kindStyles[kind] != nil, "\(theme.name) lacks \(kind.rawValue)")
      #expect(theme.kindStyles[kind]?.foreground != nil, "\(theme.name) \(kind.rawValue)")
    }
  }

  @Test("Punctuation differs from tags, and keys differ from values", arguments: themes)
  func distinctRoles(theme: EscriboTheme) {
    let k = theme.kindStyles
    #expect(k[.glosaPunctuation]?.foreground != k[.glosaTag]?.foreground)
    #expect(k[.glosaJSONKey]?.foreground != k[.glosaJSONString]?.foreground)
    #expect(k[.glosaAttributeName]?.foreground != k[.glosaAttributeValue]?.foreground)
  }

  @Test("The source theme colours no glosa kind")
  func sourceStaysUncoloured() {
    for kind in Self.glosaKinds {
      #expect(EscriboTheme.source.kindStyles[kind] == nil, "\(kind.rawValue)")
    }
  }
}
