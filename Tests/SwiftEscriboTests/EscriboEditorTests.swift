import EscriboCore
import Foundation
import SwiftUI
import Testing

@testable import SwiftEscribo

#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

/// Sortie 12: live ↔ source mode switching.
///
/// REQUIREMENTS.md Editor §2: "Both edit the same string; switching is a theme swap, not a
/// content transformation." DL-40 makes that a property of the type graph rather than a
/// rule someone remembers — ``EditorMode`` stops at ``EditorStyleEnvironment``, which folds
/// it into a theme with ``EscriboTheme/strippedToSource()`` before ``EscriboStyler`` sees
/// either. These tests assert both halves: the characters never move, and the attributes
/// really do.
@MainActor
@Suite("Mode switching is a theme swap, not a content transformation")
struct EditorModeSwitchingTests {

  /// A document with a heading, a paragraph, and a fence, so live mode has something to
  /// disagree with source mode about.
  private static let document = """
    # Heading

    A plain paragraph.

    ```swift
    let answer = 42
    ```

    """

  private func makeEditor() -> EscriboTextView {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    editor.applyExternalText(Self.document)
    return editor
  }

  private func setMode(_ mode: EditorMode, on editor: EscriboTextView) {
    editor.applyConfiguration(
      language: .markdown, mode: mode, theme: .markdownLight, appearance: .light)
  }

  @Test("live → source → live leaves the document byte-identical")
  func modeRoundTripIsByteIdentical() {
    let editor = makeEditor()
    let before = Array(Self.document.utf8)
    #expect(Array(editor.currentText.utf8) == before)

    setMode(.source, on: editor)
    #expect(Array(editor.currentText.utf8) == before)

    setMode(.live, on: editor)
    #expect(Array(editor.currentText.utf8) == before)
  }

  @Test("A mode switch performs zero character mutations")
  func modeSwitchMutatesNoCharacters() {
    let editor = makeEditor()
    let lengthBefore = editor.documentStorage.length
    let editsBefore = editor.coordinator.lastEdit

    setMode(.source, on: editor)
    setMode(.live, on: editor)

    #expect(editor.documentStorage.length == lengthBefore)
    // The coordinator's last *character* edit is untouched: nothing arrived through the
    // text-storage delegate's character path, because nothing changed a character.
    #expect(editor.coordinator.lastEdit == editsBefore)
  }

  @Test("The switch really happens: source mode flattens attributes that live mode varies")
  func sourceModeFlattensWhatLiveModeVaries() throws {
    let editor = makeEditor()
    let storage = editor.documentStorage

    let headingContent = 2  // past the "# " marker
    let paragraphStart = (Self.document as NSString).range(of: "A plain paragraph").location
    #expect(paragraphStart != NSNotFound)

    // Live: markdownLight recolors and rescales a heading, so the two differ.
    let liveHeading = StylingFixtures.comparable(
      storage.attributes(at: headingContent, effectiveRange: nil))
    let liveParagraph = StylingFixtures.comparable(
      storage.attributes(at: paragraphStart, effectiveRange: nil))
    #expect(liveHeading != liveParagraph)

    setMode(.source, on: editor)

    // Source: every kind, every style combination, and both roles resolve through the same
    // untouched base, so there is nothing left for them to differ by.
    let sourceHeadingMarker = StylingFixtures.comparable(
      storage.attributes(at: 0, effectiveRange: nil))
    let sourceHeading = StylingFixtures.comparable(
      storage.attributes(at: headingContent, effectiveRange: nil))
    let sourceParagraph = StylingFixtures.comparable(
      storage.attributes(at: paragraphStart, effectiveRange: nil))
    #expect(sourceHeading == sourceParagraph)
    #expect(sourceHeadingMarker == sourceParagraph)

    setMode(.live, on: editor)

    // And back: byte-identical text, and the live attributes restored.
    #expect(
      StylingFixtures.comparable(storage.attributes(at: headingContent, effectiveRange: nil))
        == liveHeading)
    #expect(
      StylingFixtures.comparable(storage.attributes(at: paragraphStart, effectiveRange: nil))
        == liveParagraph)
  }

  @Test("A mode switch runs the styler's one invalidation path and then restyles")
  func modeSwitchInvalidatesAndRestyles() {
    let editor = makeEditor()
    let restylesBefore = editor.coordinator.restyleCount

    setMode(.source, on: editor)

    #expect(editor.coordinator.styler.environment.mode == .source)
    #expect(editor.coordinator.restyleCount > restylesBefore)
  }

  @Test("Re-applying an unchanged configuration does no work")
  func unchangedConfigurationIsANoOp() {
    let editor = makeEditor()
    let restylesBefore = editor.coordinator.restyleCount
    let counter = TextStorageMutationCounter(observing: editor.documentStorage)

    setMode(.live, on: editor)  // already live

    #expect(editor.coordinator.restyleCount == restylesBefore)
    #expect(counter.count == 0)

    // Positive control on the same counter and the same storage.
    setMode(.source, on: editor)
    #expect(counter.count > 0)
  }
}

/// Sortie 12 / DL-63: the SwiftUI surface itself.
///
/// A `Representable.Context` cannot be constructed in a test, which is exactly why
/// ``EscriboEditorBridge`` holds every line of logic the Representables run and the
/// Representables themselves hold none. What is asserted here is therefore what
/// `makeNSView` / `makeUIView` actually do, reached by the same call they make.
@MainActor
@Suite("The SwiftUI editor surface")
struct EscriboEditorSurfaceTests {

  @Test("The bridge builds a real EscriboTextView, seeds it, and takes the view delegate")
  func bridgeBuildsAndSeedsTheEditor() {
    let bridge = EscriboEditorBridge(text: .constant("# Seeded\n"))
    let editor = bridge.makeEditor(
      language: .markdown, mode: .live, theme: .markdownLight, appearance: .light)

    // It is the object the Representable returns a view *of*, retained for the document's
    // lifetime because `NSTextStorage.delegate` is weak.
    #expect(bridge.editor === editor)
    #expect(editor.currentText == "# Seeded\n")
    #expect(editor.coordinator.language == .markdown)

    // The bridge is the *view* delegate; the coordinator is the *storage* delegate. Two
    // protocols, two objects, no competition.
    #expect(editor.textView.delegate === bridge)
    #expect(editor.documentStorage.delegate === editor.coordinator)
  }

  @Test("The bridge does not re-configure the text view the owning class already configured")
  func bridgePreservesTheShippedTextViewConfiguration() {
    let bridge = EscriboEditorBridge(text: .constant(""))
    let editor = bridge.makeEditor(
      language: .markdown, mode: .live, theme: .markdownLight, appearance: .light)

    // The TextKit 2 guarantee and the hygiene settings are Sorties 10 and 11's, asserted
    // against the object the Representable returns rather than a second one built here.
    #expect(editor.textView.textLayoutManager != nil)
    #if os(macOS)
      #expect(editor.textView.isAutomaticQuoteSubstitutionEnabled == false)
      #expect(editor.textView.isAutomaticDashSubstitutionEnabled == false)
      // DL-65: load-bearing for Sortie 25, and nothing in this sortie may disturb them.
      #expect(editor.textView.allowsUndo == true)
      #expect(editor.textView.isRichText == false)
    #elseif os(iOS)
      #expect(editor.textView.smartQuotesType == .no)
      #expect(editor.textView.smartDashesType == .no)
      #expect(editor.textView.spellCheckingType == .yes)
    #endif
  }

  @Test("The update path switches language, mode, and text through the same guarded rules")
  func updateAppliesLanguageModeAndText() {
    let bridge = EscriboEditorBridge(text: .constant(""))
    let editor = bridge.makeEditor(
      language: .markdown, mode: .live, theme: .markdownLight, appearance: .light)

    bridge.update(
      language: .fountain, mode: .source, theme: .fountainLight, appearance: .dark,
      text: "INT. HOUSE - DAY\n")

    #expect(editor.coordinator.language == .fountain)
    #expect(editor.coordinator.styler.environment.mode == .source)
    #expect(editor.coordinator.styler.environment.appearance == .dark)
    #expect(editor.currentText == "INT. HOUSE - DAY\n")
  }

  @Test("An update pass in which nothing changed mutates nothing — the SwiftUI feedback loop")
  func idempotentUpdatePassDoesNoWork() {
    let bridge = EscriboEditorBridge(text: .constant("# Heading\n"))
    let editor = bridge.makeEditor(
      language: .markdown, mode: .live, theme: .markdownLight, appearance: .light)
    let counter = TextStorageMutationCounter(observing: editor.documentStorage)
    let restylesBefore = editor.coordinator.restyleCount

    // Five passes, exactly as SwiftUI would run them on unrelated layout invalidations.
    for _ in 0..<5 {
      bridge.update(
        language: .markdown, mode: .live, theme: .markdownLight, appearance: .light,
        text: "# Heading\n")
    }

    #expect(counter.count == 0)
    #expect(editor.coordinator.restyleCount == restylesBefore)

    // Positive control on the same counter.
    bridge.update(
      language: .markdown, mode: .live, theme: .markdownLight, appearance: .light,
      text: "# Changed\n")
    #expect(counter.count > 0)
  }

  @Test("Typing pushes the document back out to the binding, and only when it differs")
  func typingPushesToTheBinding() {
    let box = BindingBox(value: "")
    let bridge = EscriboEditorBridge(text: box.binding)
    let editor = bridge.makeEditor(
      language: .markdown, mode: .live, theme: .markdownLight, appearance: .light)

    // An ordinary storage edit — the shape a keystroke produces.
    editor.documentStorage.replaceCharacters(
      in: NSRange(location: 0, length: 0), with: "# Typed")
    bridge.pushToBinding()

    #expect(box.value == "# Typed")
    #expect(box.writeCount == 1)

    // Equal content: the setter must not fire, or the host re-invalidates and hands the
    // string straight back.
    bridge.pushToBinding()
    #expect(box.writeCount == 1)
  }

  @Test("EscriboEditor is constructible over every documented configuration")
  func publicViewIsConstructible() {
    _ = EscriboEditor(text: .constant(""), language: .markdown)
    _ = EscriboEditor(text: .constant(""), language: .fountain, mode: .source)
    _ = EscriboEditor(
      text: .constant("# Hi"), language: .markdown, mode: .live, theme: .markdownDark)

    // The type annotation is the assertion: `EscriboEditor` is a SwiftUI `View`, and its
    // `body` is the platform Representable rather than a placeholder.
    let view: any View = EscriboEditor(text: .constant(""), language: .markdown)
    #expect(view is EscriboEditor)
  }

  /// Source compatibility for `findBar:`, and it is the *absence* of edits above that carries
  /// it: every call form in ``publicViewIsConstructible()`` predates the parameter and still
  /// compiles unchanged, which is only true because the parameter is defaulted. This test adds
  /// the new forms rather than rewriting the old ones, so a future non-defaulted parameter
  /// breaks the older test and not this one.
  @Test("findBar is opt-in and platform-neutral in the public signature")
  func findBarIsAnOptInParameter() {
    _ = EscriboEditor(text: .constant(""), language: .markdown, findBar: true)
    _ = EscriboEditor(
      text: .constant(""), language: .fountain, mode: .source, theme: .fountainDark,
      findBar: true)

    // The signature is the same on both platforms — no `#if` at the call site. What differs
    // is what the parameter *does*, which is asserted in `MacTextViewFindBarTests`.
    let view: any View = EscriboEditor(
      text: .constant(""), language: .markdown, findBar: true)
    #expect(view is EscriboEditor)
  }
}

/// A mutable target for a `Binding` that also counts writes.
///
/// `Binding.constant` cannot observe a write and `@State` needs a view graph, so the
/// binding-hygiene assertion — "the setter fires for a real change and not for an equal
/// one" — needs a plain object behind the binding.
@MainActor
final class BindingBox {

  /// The current value.
  private(set) var value: String

  /// How many times the binding's setter has run.
  private(set) var writeCount = 0

  init(value: String) {
    self.value = value
  }

  /// A `Binding` reading and writing this box.
  var binding: Binding<String> {
    Binding(
      get: { self.value },
      set: {
        self.value = $0
        self.writeCount += 1
      })
  }
}
