import Testing

@testable import EscriboCore

/// Fountain's inline emphasis: `*italics*`, `**bold**`, `***bold italics***`, `_underline_`,
/// and the backslash escapes.
///
/// Every expectation is written **by hand** from the source text, in the convention
/// ``FountainGrammarTests`` explains: a grammar that is wrong agrees with itself, so nothing
/// here was produced by running it.
@Suite("Fountain grammar — inline emphasis")
struct FountainEmphasisTests {

  /// One piece of a line: its text, whether it is syntax, and its style.
  struct Piece: Equatable, CustomStringConvertible {
    let text: String
    let isMarker: Bool
    let style: StyleSet

    init(_ text: String, marker: Bool = false, _ style: StyleSet = []) {
      self.text = text
      self.isMarker = marker
      self.style = style
    }

    var description: String {
      "\(text.debugDescription)\(isMarker ? " marker" : "") style:\(style.rawValue)"
    }
  }

  /// The pieces of line `line` of `text`, terminator excluded, adjacent spans that agree
  /// on role and style merged — so an expectation reads as the line reads.
  static func pieces(
    _ text: String, line: Int = 0, sourceLocation: SourceLocation = #_sourceLocation
  ) -> [Piece] {
    let result = FountainGrammarTests.fullScan(text, sourceLocation: sourceLocation)
    let record = result.lineRecords[line]
    let units = Array(text.utf16)
    var pieces: [Piece] = []
    for span in result.spans
    where span.range.lowerBound >= record.range.lowerBound
      && span.range.upperBound <= record.range.upperBound
    {
      let slice = String(
        decoding: units[span.range].filter { $0 != 0x0A && $0 != 0x0D }, as: UTF16.self)
      guard !slice.isEmpty else { continue }
      let piece = Piece(slice, marker: span.role == .marker, span.style)
      if let last = pieces.last, last.isMarker == piece.isMarker, last.style == piece.style {
        pieces[pieces.count - 1] = Piece(last.text + slice, marker: last.isMarker, last.style)
      } else {
        pieces.append(piece)
      }
    }
    return pieces
  }

  @Test("`*not*` in action is italic, and its stars are markers")
  func italicInAction() {
    #expect(
      Self.pieces("She waits. It is *not* over.") == [
        Piece("She waits. It is "),
        Piece("*", marker: true, .emphasis),
        Piece("not", .emphasis),
        Piece("*", marker: true, .emphasis),
        Piece(" over."),
      ])
  }

  @Test("Dialogue carries italics and bold — issue #40's own line")
  func emphasisInDialogue() {
    let text = "TOMAS\nI never *left*. The log has **forty years** of weather in it.\n"
    #expect(
      Self.pieces(text, line: 1) == [
        Piece("I never "),
        Piece("*", marker: true, .emphasis),
        Piece("left", .emphasis),
        Piece("*", marker: true, .emphasis),
        Piece(". The log has "),
        Piece("**", marker: true, .strong),
        Piece("forty years", .strong),
        Piece("**", marker: true, .strong),
        Piece(" of weather in it."),
      ])
    let result = FountainGrammarTests.fullScan(text)
    let content = result.lineRecords[1].contentRange
    let dialogue = result.spans.filter {
      content.contains($0.range.lowerBound) && $0.role == .content
    }
    #expect(dialogue.allSatisfy { $0.kind == .dialogue }, "emphasis keeps the element's kind")
  }

  @Test("`***both***` is bold and italic, markers included")
  func boldItalic() {
    #expect(
      Self.pieces("A ***loud*** word.") == [
        Piece("A "),
        Piece("*", marker: true, .emphasis),
        Piece("**", marker: true, [.emphasis, .strong]),
        Piece("loud", [.emphasis, .strong]),
        Piece("**", marker: true, [.emphasis, .strong]),
        Piece("*", marker: true, .emphasis),
        Piece(" word."),
      ])
  }

  @Test("`_under_` is underlined; `**_both_**` nests")
  func underline() {
    #expect(
      Self.pieces("An _underlined_ word.") == [
        Piece("An "),
        Piece("_", marker: true, .underline),
        Piece("underlined", .underline),
        Piece("_", marker: true, .underline),
        Piece(" word."),
      ])
    #expect(
      Self.pieces("**_SIGN_**") == [
        Piece("**", marker: true, .strong),
        Piece("_", marker: true, [.strong, .underline]),
        Piece("SIGN", [.strong, .underline]),
        Piece("_", marker: true, [.strong, .underline]),
        Piece("**", marker: true, .strong),
      ])
  }

  @Test("Centered text and parentheticals carry emphasis")
  func centeredAndParenthetical() {
    #expect(
      Self.pieces(">_VACANCY_<") == [
        Piece(">", marker: true),
        Piece("_", marker: true, .underline),
        Piece("VACANCY", .underline),
        Piece("_", marker: true, .underline),
        Piece("<", marker: true),
      ])
    #expect(
      Self.pieces("TOMAS\n(*quietly*)\nNo.\n", line: 1) == [
        Piece("("),
        Piece("*", marker: true, .emphasis),
        Piece("quietly", .emphasis),
        Piece("*", marker: true, .emphasis),
        Piece(")"),
      ])
  }

  @Test("A backslash escapes a star, an underscore, and itself")
  func escapes() {
    #expect(
      Self.pieces(#"Not \*italic\* at all."#) == [
        Piece("Not "),
        Piece(#"\"#, marker: true),
        Piece("*italic"),
        Piece(#"\"#, marker: true),
        Piece("* at all."),
      ])
    #expect(
      Self.pieces(#"A \_ and a \\."#) == [
        Piece("A "),
        Piece(#"\"#, marker: true),
        Piece("_ and a "),
        Piece(#"\"#, marker: true),
        Piece(#"\."#),
      ])
  }

  @Test("Stars and underscores that flank nothing stay text")
  func nonEmphasis() {
    #expect(Self.pieces("She counts 2 * 3 * 4.") == [Piece("She counts 2 * 3 * 4.")])
    #expect(Self.pieces("He types snake_case_name.") == [Piece("He types snake_case_name.")])
    #expect(Self.pieces("An *unclosed star.") == [Piece("An *unclosed star.")])
    #expect(Self.pieces("Two ** stars.") == [Piece("Two ** stars.")])
  }

  @Test("Emphasis never reaches into a note or a boneyard")
  func regions() {
    let pieces = Self.pieces("He *waits* [[a *note*]] here /* cut * it */ now.")
    let styled = pieces.filter { !$0.style.isEmpty }
    #expect(
      styled == [
        Piece("*", marker: true, .emphasis),
        Piece("waits", .emphasis),
        Piece("*", marker: true, .emphasis),
      ])
  }

  @Test("Emphasis does not cross a line break")
  func singleLine() {
    let text = "She *starts\nand stops* here.\n"
    #expect(Self.pieces(text, line: 0).allSatisfy { $0.style.isEmpty })
    #expect(Self.pieces(text, line: 1).allSatisfy { $0.style.isEmpty })
  }

  @Test("Scene headings and cues are not emphasis surfaces")
  func excludedElements() {
    #expect(Self.pieces("INT. *HOUSE* - DAY").allSatisfy { $0.style.isEmpty && !$0.isMarker })
  }
}
