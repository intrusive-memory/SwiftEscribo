#if os(iOS)
  import EscriboCore
  import Testing
  import UIKit
  import UniformTypeIdentifiers

  @testable import SwiftEscribo

  /// The iOS half of rich paste: a pasteboard's RTF flavour, written as the document's markup
  /// when the host opted in, and left to UIKit's own plain paste when it did not.
  ///
  /// Driven through ``EscriboNativeTextView/pasteFormattingAsMarkup(from:)`` with a named
  /// pasteboard, never `UIPasteboard.general`: the general pasteboard is the simulator's and
  /// the person's, and reading it from a test raises the paste prompt.
  @MainActor
  @Suite("iOS rich paste")
  struct IOSRichPasteTests {

    /// A named pasteboard whose RTF flavour underlines "underlined" and bolds "bold".
    static func formattedPasteboard() throws -> UIPasteboard {
      let pasteboard = try #require(UIPasteboard(name: .init(UUID().uuidString), create: true))
      let rich = NSMutableAttributedString(
        string: "An underlined and bold word.",
        attributes: [.font: UIFont.systemFont(ofSize: 12)])
      rich.addAttribute(
        .underlineStyle, value: NSUnderlineStyle.single.rawValue,
        range: NSRange(location: 3, length: 10))
      rich.addAttribute(
        .font, value: UIFont.boldSystemFont(ofSize: 12), range: NSRange(location: 18, length: 4))
      let rtf = try rich.data(
        from: NSRange(location: 0, length: rich.length),
        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
      pasteboard.setData(rtf, forPasteboardType: UTType.rtf.identifier)
      return pasteboard
    }

    @Test("Opted out: nothing is pasted here, and UIKit's plain paste goes on")
    func optedOut() throws {
      let editor = EscriboTextView(language: .fountain, theme: .fountainLight)
      let pasteboard = try Self.formattedPasteboard()
      #expect(editor.textView.pasteFormattingAsMarkup(from: pasteboard) == false)
      #expect(editor.currentText == "")
    }

    @Test("Opted in: underline and bold become Fountain markup")
    func fountainMarkup() throws {
      let editor = EscriboTextView(language: .fountain, theme: .fountainLight)
      editor.textView.richPasteLanguage = .fountain
      let pasteboard = try Self.formattedPasteboard()
      #expect(editor.textView.pasteFormattingAsMarkup(from: pasteboard))
      #expect(editor.currentText == "An _underlined_ and **bold** word.")
    }

    @Test("Opted in with a plain-only pasteboard: left to UIKit")
    func plainOnly() throws {
      let editor = EscriboTextView(language: .fountain, theme: .fountainLight)
      editor.textView.richPasteLanguage = .fountain
      let pasteboard = try #require(UIPasteboard(name: .init(UUID().uuidString), create: true))
      pasteboard.string = "plain"
      #expect(editor.textView.pasteFormattingAsMarkup(from: pasteboard) == false)
    }
  }
#endif
