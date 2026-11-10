import EscriboCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
  import AppKit
#elseif os(iOS)
  import UIKit
#endif

extension View {
  /// Whether a paste keeps its bold, italics and underline by rewriting them as the
  /// document's markup — `**x**`, `*x*`, and in Fountain `_x_` — instead of dropping them.
  ///
  /// Off by default: the editor's value is plain text and a paste is verbatim (DL-65). A host
  /// whose writers paste from word processors and screenwriting apps turns it on, and a paste
  /// that carries a rich flavour with formatting the language can write is inserted as
  /// ``RichPasteMarkup`` produces it. A paste with no such formatting is the plain flavour,
  /// exactly as before. See ``RichPasteMarkup`` for what is written and what is left alone.
  public func escriboPastesFormattingAsMarkup(_ enabled: Bool = true) -> some View {
    environment(\.escriboPastesFormattingAsMarkup, enabled)
  }
}

extension EnvironmentValues {
  @Entry var escriboPastesFormattingAsMarkup = false
}

/// Reads a pasteboard's rich flavour into ``RichPasteMarkup`` runs.
@MainActor
enum RichPasteReader {

  /// The pasteboard's rich text as `language` markup, or `nil` when it has no rich flavour or
  /// the flavour carries no formatting `language` writes — the plain paste is then the answer.
  #if os(macOS)
    static func markup(from pasteboard: NSPasteboard, language: Language) -> String? {
      guard
        let attributed = pasteboard.readObjects(forClasses: [NSAttributedString.self])?
          .first as? NSAttributedString
      else { return nil }
      return markup(of: attributed, language: language)
    }
  #elseif os(iOS)
    static func markup(from pasteboard: UIPasteboard, language: Language) -> String? {
      let flavours: [(UTType, NSAttributedString.DocumentType)] = [
        (.rtf, .rtf), (.flatRTFD, .rtfd), (.html, .html),
      ]
      for (type, documentType) in flavours {
        guard let data = pasteboard.data(forPasteboardType: type.identifier),
          let attributed = try? NSAttributedString(
            data: data, options: [.documentType: documentType], documentAttributes: nil)
        else { continue }
        return markup(of: attributed, language: language)
      }
      return nil
    }
  #endif

  /// `attributed` as `language` markup, or `nil` when it carries no formatting to write.
  static func markup(of attributed: NSAttributedString, language: Language) -> String? {
    let runs = Self.runs(of: attributed)
    guard RichPasteMarkup.hasMarkup(runs, language: language) else { return nil }
    return RichPasteMarkup.markup(runs, language: language)
  }

  /// One run per attribute run, its styles read from the font's traits and the underline
  /// and strikethrough attributes. Line separators from rich text become `\n`.
  static func runs(of attributed: NSAttributedString) -> [RichPasteMarkup.Run] {
    var runs: [RichPasteMarkup.Run] = []
    let whole = NSRange(location: 0, length: attributed.length)
    attributed.enumerateAttributes(in: whole) { attributes, range, _ in
      var styles: StyleSet = []
      #if os(macOS)
        if let font = attributes[.font] as? NSFont {
          let traits = font.fontDescriptor.symbolicTraits
          if traits.contains(.bold) { styles.insert(.strong) }
          if traits.contains(.italic) { styles.insert(.emphasis) }
        }
      #elseif os(iOS)
        if let font = attributes[.font] as? UIFont {
          let traits = font.fontDescriptor.symbolicTraits
          if traits.contains(.traitBold) { styles.insert(.strong) }
          if traits.contains(.traitItalic) { styles.insert(.emphasis) }
        }
      #endif
      if let underline = attributes[.underlineStyle] as? Int, underline != 0 {
        styles.insert(.underline)
      }
      if let strike = attributes[.strikethroughStyle] as? Int, strike != 0 {
        styles.insert(.strikethrough)
      }
      let text = (attributed.string as NSString).substring(with: range)
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\u{2028}", with: "\n")
        .replacingOccurrences(of: "\u{2029}", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
      runs.append(RichPasteMarkup.Run(text, styles))
    }
    return runs
  }
}
