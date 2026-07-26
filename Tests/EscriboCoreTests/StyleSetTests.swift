import Testing

@testable import EscriboCore

/// `StyleSet` bit positions are API. Adding a member is a minor release *because*
/// existing positions never move; moving one is a major release that would silently
/// re-render every persisted theme rather than failing to compile. These assertions
/// are the tripwire for that — they are deliberately literal, not derived, so an
/// accidental reordering of the declarations cannot make them agree with themselves.
@Suite("StyleSet")
struct StyleSetTests {

  @Test(
    "Bit positions are fixed",
    arguments: [
      (StyleSet.strong, UInt16(1)),
      (StyleSet.emphasis, UInt16(2)),
      (StyleSet.strikethrough, UInt16(4)),
      (StyleSet.inlineCode, UInt16(8)),
      (StyleSet.underline, UInt16(16)),
    ]
  )
  func bitPositionsAreFixed(style: StyleSet, expected: UInt16) {
    #expect(style.rawValue == expected)
  }

  @Test("Each member occupies a distinct single bit")
  func membersAreDisjointSingleBits() {
    let all: [StyleSet] = [.strong, .emphasis, .strikethrough, .inlineCode, .underline]
    for style in all {
      #expect(style.rawValue.nonzeroBitCount == 1)
    }
    let union = all.reduce(into: StyleSet()) { $0.formUnion($1) }
    #expect(union.rawValue == 0b1_1111)
    #expect(union.rawValue.nonzeroBitCount == all.count)
  }

  @Test("Styles compose as a union rather than a new case")
  func stylesCompose() {
    // The whole point of the two-axis model: bold italic inline code inside dialogue
    // is one span carrying three flags, not a `.boldItalicCodeDialogue` case.
    let combined: StyleSet = [.strong, .emphasis, .inlineCode]
    #expect(combined.rawValue == 1 | 2 | 8)
    #expect(combined.contains(.strong))
    #expect(combined.contains(.emphasis))
    #expect(combined.contains(.inlineCode))
    #expect(!combined.contains(.strikethrough))
    #expect(!combined.contains(.underline))
  }

  @Test("The empty set is unstyled and is the default")
  func emptySetIsUnstyled() {
    #expect(StyleSet().rawValue == 0)
    #expect(StyleSet([]).isEmpty)
    #expect(!StyleSet().contains(.strong))
  }

  @Test("Set algebra behaves")
  func setAlgebra() {
    var style: StyleSet = [.strong, .emphasis]
    style.remove(.emphasis)
    #expect(style == .strong)
    style.formUnion(.strikethrough)
    #expect(style == [.strong, .strikethrough])
    #expect(style.intersection([.strikethrough, .underline]) == .strikethrough)
    #expect(style.isSuperset(of: .strong))
  }
}
