import EscriboCore
import Testing

@testable import SwiftEscribo

#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

/// ``EscriboTheme/hidesForcedElementMarkers``: a Fountain line's forcing prefix is drawn
/// clear with a negative kern equal to its own width, so it takes no space, and the
/// document's characters are untouched.
@MainActor
@Suite("Hidden forced-element markers")
struct HiddenForcedMarkerTests {

  static let script = """
    .SHOT 1 - WIDE - EXT. DUMPSTER - DAY

    !Forced action.

    @McAvoy
    Hello.

    > CUT TO:

    > THE END <

    # Act One

    Plain action with **bold**.
    """

  static func theme(hiding: Bool) -> EscriboTheme {
    var theme = CoordinatorFixtures.probeTheme
    theme.hidesForcedElementMarkers = hiding
    return theme
  }

  static func attributes(
    _ storage: NSTextStorage, atFirst needle: String
  ) throws -> [NSAttributedString.Key: Any] {
    let offset = try CoordinatorFixtures.offset(of: needle, in: script)
    return storage.attributes(at: offset, effectiveRange: nil)
  }

  static func isHidden(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
    guard let kern = attributes[.kern] as? CGFloat, kern < 0,
      let color = attributes[.foregroundColor] as? PlatformColor
    else { return false }
    return color.cgColor.alpha == 0 && attributes[.underlineStyle] == nil
  }

  @Test("The four forcing prefixes are hidden, and take their own width away")
  func prefixesAreHidden() throws {
    let editor = CoordinatorFixtures.makeEditor(
      Self.script, language: .fountain, theme: Self.theme(hiding: true))
    for needle in [".SHOT", "!Forced", "@McAvoy", "> CUT"] {
      let attributes = try Self.attributes(editor.storage, atFirst: needle)
      #expect(Self.isHidden(attributes), "\(needle.prefix(1)) should be hidden")
      let font = try #require(attributes[.font] as? PlatformFont)
      let width = NSAttributedString(
        string: String(needle.prefix(1)), attributes: [.font: font]
      ).size().width
      #expect((attributes[.kern] as? CGFloat) == -width)
    }
    // The heading's own text is drawn as usual.
    #expect(!Self.isHidden(try Self.attributes(editor.storage, atFirst: "SHOT 1")))
  }

  @Test("The document's characters are unchanged")
  func textIsUntouched() {
    let editor = CoordinatorFixtures.makeEditor(
      Self.script, language: .fountain, theme: Self.theme(hiding: true))
    #expect(editor.storage.string == Self.script)
  }

  @Test("Centered text, sections and emphasis delimiters stay visible")
  func otherMarkersStayDimmed() throws {
    let editor = CoordinatorFixtures.makeEditor(
      Self.script, language: .fountain, theme: Self.theme(hiding: true))
    for needle in ["> THE END", "# Act", "**bold"] {
      #expect(!Self.isHidden(try Self.attributes(editor.storage, atFirst: needle)), "\(needle)")
    }
  }

  @Test("Off by default, and off in source mode even when the theme asks")
  func offByDefaultAndInSource() throws {
    #expect(EscriboTheme.fountainLight.hidesForcedElementMarkers == false)
    #expect(Self.theme(hiding: true).strippedToSource().hidesForcedElementMarkers == false)

    let shown = CoordinatorFixtures.makeEditor(
      Self.script, language: .fountain, theme: Self.theme(hiding: false))
    #expect(!Self.isHidden(try Self.attributes(shown.storage, atFirst: ".SHOT")))

    let source = CoordinatorFixtures.makeEditor(
      Self.script, language: .fountain, theme: Self.theme(hiding: true))
    source.styler.environment.mode = .source
    source.coordinator.restyleEverything()
    #expect(!Self.isHidden(try Self.attributes(source.storage, atFirst: ".SHOT")))
  }

  @Test("Typing the prefix hides it; deleting it un-forces the line")
  func editsRestyle() throws {
    let editor = CoordinatorFixtures.makeEditor(
      "Hello there\n", language: .fountain, theme: Self.theme(hiding: true))
    editor.storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: ".")
    #expect(Self.isHidden(editor.storage.attributes(at: 0, effectiveRange: nil)))
    editor.storage.replaceCharacters(in: NSRange(location: 0, length: 1), with: "")
    #expect(!Self.isHidden(editor.storage.attributes(at: 0, effectiveRange: nil)))
  }
}
