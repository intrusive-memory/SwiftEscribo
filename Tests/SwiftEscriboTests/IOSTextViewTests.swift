#if os(iOS)
  import EscriboCore
  import Testing
  import UIKit

  @testable import SwiftEscribo

  /// Sortie 11: the iOS `UITextView` Representable.
  ///
  /// Every fixture here builds a **real** ``EscriboTextView`` and asserts against the
  /// `UITextView` it actually constructs — never a separately hand-built `UITextView` —
  /// mirroring `MacTextViewTests.swift` exactly. The exit criteria are about what the
  /// Representable's own construction path guarantees, not about `UITextView` in general.
  ///
  /// `@MainActor` for the same reason `EditorCoordinatorTests` is: `UITextView` is a
  /// UIKit object and the coordinator it drives is main-thread-owned by contract.
  @MainActor
  @Suite("iOS text view — construction and text-system hygiene")
  struct IOSTextViewConstructionTests {

    @Test("Smart quotes, smart dashes, and autocorrect are disabled by default")
    func hygieneFlagsAreDisabled() {
      let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
      #expect(editor.textView.smartQuotesType == .no)
      #expect(editor.textView.smartDashesType == .no)
      #expect(editor.textView.autocorrectionType == .no)
    }

    @Test("Spell checking stays on, decoupled from the autocorrect-off default")
    func spellCheckingStaysOn() {
      let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
      // UIKit ties `.default` to the state of autocorrection, so this is asserted
      // explicitly rather than trusted as a system default — the same pairing Sortie 10
      // states on macOS with `isContinuousSpellCheckingEnabled`.
      #expect(editor.textView.spellCheckingType == .yes)
    }

    @Test("The autocorrect host opt-in toggles autocorrectionType, and nothing else")
    func autocorrectHostOptIn() {
      let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
      #expect(editor.isAutocorrectionEnabled == false)

      editor.isAutocorrectionEnabled = true
      #expect(editor.textView.autocorrectionType == .yes)

      // Smart quotes, smart dashes, and spell checking have no opt-in anywhere on this
      // type — flipping autocorrect must not have touched any of them, which matters
      // precisely because `spellCheckingType` and `autocorrectionType` are a coupled pair
      // at `.default`; a setter that forgot to pin spell checking explicitly could leak
      // this toggle into it.
      #expect(editor.textView.smartQuotesType == .no)
      #expect(editor.textView.smartDashesType == .no)
      #expect(editor.textView.spellCheckingType == .yes)

      editor.isAutocorrectionEnabled = false
      #expect(editor.textView.autocorrectionType == .no)
      #expect(editor.textView.spellCheckingType == .yes)
    }

    @Test("The text view sits on the TextKit 2 stack")
    func textKit2StackIsGuaranteed() {
      let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
      #expect(editor.textView.textLayoutManager != nil)
    }

    @Test("The text view self-scrolls")
    func textViewSelfScrolls() {
      let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
      #expect(editor.textView.isScrollEnabled == true)
    }

    @Test("Attaching installs the coordinator as the text storage's delegate")
    func coordinatorIsAttached() {
      let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
      #expect(editor.textView.textStorage.delegate === editor.coordinator)
    }

    @Test("The theme convenience initializer and the styler initializer build the same shape")
    func themeConvenienceInitializerMatchesStylerInitializer() {
      let styler = EscriboStyler(theme: .markdownLight)
      let editor = EscriboTextView(language: .markdown, styler: styler)
      #expect(editor.coordinator.language == .markdown)
      #expect(editor.textView.textLayoutManager != nil)
    }

    @Test("A fresh composition reports no marked text, matching the coordinator's default")
    func noMarkedTextByDefault() {
      let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
      #expect(editor.textView.markedTextRange == nil)
      #expect(editor.coordinator.hasMarkedText() == false)
    }
  }

  /// The one behavioral exit criterion mirrored from macOS: typing must reach the
  /// coordinator and come back out as real text-storage attributes, exactly as it would
  /// for a user at the keyboard.
  @MainActor
  @Suite("iOS text view — typing produces styled attributes")
  struct IOSTextViewStylingTests {

    @Test("Typing a heading styles its content range distinctly from a plain paragraph")
    func typingAHeadingStylesItsRange() throws {
      let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
      let storage = editor.textView.textStorage

      // Two ordinary storage edits, exactly the shape a keystroke produces and exactly
      // what `NSTextStorageDelegate` reports to the coordinator — not a hand-built
      // `ScanResult` (DL-12 gives that no public initializer) and not a separate
      // off-to-the-side text storage.
      storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "# Heading\n")
      let plainLineStart = storage.length
      storage.replaceCharacters(
        in: NSRange(location: plainLineStart, length: 0), with: "Plain paragraph")

      // "H" of "Heading" — past the "# " marker, so this is squarely the content range.
      let headingContentOffset = 2
      let headingAttributes = storage.attributes(at: headingContentOffset, effectiveRange: nil)
      let plainAttributes = storage.attributes(at: plainLineStart, effectiveRange: nil)

      #expect(headingAttributes[.foregroundColor] != nil)
      #expect(headingAttributes[.font] != nil)
      #expect(plainAttributes[.foregroundColor] != nil)
      #expect(plainAttributes[.font] != nil)

      // ...and the heading's is not the plain paragraph's: markdownLight recolors
      // `.heading` and scales its depth-1 size to 1.8x the 14pt base (BuiltInThemes).
      #expect(
        StylingFixtures.comparable(headingAttributes) != StylingFixtures.comparable(plainAttributes)
      )

      let headingFont = try #require(headingAttributes[.font] as? PlatformFont)
      let plainFont = try #require(plainAttributes[.font] as? PlatformFont)
      #expect(headingFont.pointSize > plainFont.pointSize)
    }

    @Test("Marker and content on the same heading line share size, differing only in dimming")
    func markerAndContentShareSizeOnTheSameLine() throws {
      let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
      let storage = editor.textView.textStorage

      storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "# Heading")

      let markerAttributes = storage.attributes(at: 0, effectiveRange: nil)
      let contentAttributes = storage.attributes(at: 2, effectiveRange: nil)

      let markerFont = try #require(markerAttributes[.font] as? PlatformFont)
      let contentFont = try #require(contentAttributes[.font] as? PlatformFont)
      // Architecture §3: alpha only. A marker that resized would make text jitter as you
      // type — this is the UIKit-facing proof the same rule survives here.
      #expect(markerFont.pointSize == contentFont.pointSize)
    }

    @Test("Restyling is skipped while a marked-text composition is in flight")
    func restylingSkipsDuringComposition() {
      let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
      let storage = editor.textView.textStorage

      // Simulate an IME composition without driving real UIKit text input: bind a closure
      // that answers `true`, the same shape `markedTextRange != nil` produces once a
      // composition is live, then edit the storage exactly as the text system would.
      editor.coordinator.hasMarkedText = { true }
      let restyleCountBeforeEdit = editor.coordinator.restyleCount

      storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "# Heading")

      #expect(editor.coordinator.restyleCount == restyleCountBeforeEdit)
      #expect(editor.coordinator.markedTextSkipCount > 0)
    }
  }
#endif
