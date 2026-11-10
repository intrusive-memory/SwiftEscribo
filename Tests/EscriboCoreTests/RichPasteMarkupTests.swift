import Testing

@testable import EscriboCore

@Suite("RichPasteMarkup")
struct RichPasteMarkupTests {

  typealias Run = RichPasteMarkup.Run

  @Test("Fountain writes underline, bold and italics as _x_, **x** and *x*")
  func fountainStyles() {
    let runs = [
      Run("An "), Run("underlined", .underline), Run(", a "), Run("bold", .strong),
      Run(" and an "), Run("italic", .emphasis), Run(" word."),
    ]
    #expect(
      RichPasteMarkup.markup(runs, language: .fountain)
        == "An _underlined_, a **bold** and an *italic* word.")
  }

  @Test("Markdown drops underline, which it has no markup for, and keeps the rest")
  func markdownStyles() {
    let runs = [
      Run("An "), Run("underlined", .underline), Run(" and "),
      Run("bold italic", [.strong, .emphasis]), Run(" and "), Run("gone", .strikethrough),
    ]
    #expect(
      RichPasteMarkup.markup(runs, language: .markdown)
        == "An underlined and ***bold italic*** and ~~gone~~")
  }

  @Test("Whitespace at a run's edge goes outside its markers")
  func markersHugText() {
    let runs = [Run("Say"), Run(" this ", .underline), Run("now.")]
    #expect(RichPasteMarkup.markup(runs, language: .fountain) == "Say _this_ now.")
  }

  @Test("A style that continues stays open; the inner one nests")
  func stylesNest() {
    let runs = [Run("bold ", .strong), Run("both", [.strong, .emphasis]), Run(" bold", .strong)]
    #expect(RichPasteMarkup.markup(runs, language: .fountain) == "**bold *both* bold**")
  }

  @Test("Markers close at a line break and reopen on the next line")
  func perLine() {
    let runs = [Run("Hold it.\nRight there.", .underline)]
    #expect(
      RichPasteMarkup.markup(runs, language: .fountain) == "_Hold it._\n_Right there._")
  }

  @Test("Fountain scene headings, cues and transitions keep no markers")
  func fountainStructureIsLeftAlone() {
    let runs = [
      Run("INT. HOUSE - DAY", .underline), Run("\n\n"), Run("BILLY", .strong), Run("\n"),
      Run("Hey, "), Run("you", .underline), Run(".\n\n"), Run("CUT TO:", .strong),
      Run("\n\n"), Run(".the alley", .underline),
    ]
    #expect(
      RichPasteMarkup.markup(runs, language: .fountain)
        == "INT. HOUSE - DAY\n\nBILLY\nHey, _you_.\n\nCUT TO:\n\n.the alley")
  }

  @Test("Unstyled text is inserted exactly as copied")
  func plainIsVerbatim() {
    let text = "2 * 3 * 4 and snake_case_name\n\twith a tab"
    #expect(RichPasteMarkup.markup([Run(text)], language: .fountain) == text)
    #expect(RichPasteMarkup.hasMarkup([Run(text)], language: .fountain) == false)
  }

  @Test("Only styles the language writes count as markup")
  func hasMarkup() {
    #expect(RichPasteMarkup.hasMarkup([Run("u", .underline)], language: .fountain))
    #expect(!RichPasteMarkup.hasMarkup([Run("u", .underline)], language: .markdown))
    #expect(!RichPasteMarkup.hasMarkup([Run("  ", .strong)], language: .fountain))
  }
}
