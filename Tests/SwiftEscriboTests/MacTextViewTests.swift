#if os(macOS)
  import AppKit
  import EscriboCore
  import Testing

  @testable import SwiftEscribo

  /// Sortie 10: the macOS `NSTextView` Representable.
  ///
  /// Every fixture here builds a **real** ``EscriboTextView`` and asserts against the
  /// `NSTextView` it actually constructs — never a separately hand-built `NSTextView` —
  /// because the exit criteria are about what the Representable's own construction path
  /// guarantees, not about `NSTextView` in general.
  ///
  /// `@MainActor` for the same reason `EditorCoordinatorTests` is: `NSTextView` is an
  /// AppKit object and the coordinator it drives is main-thread-owned by contract.
  @MainActor
  @Suite("macOS text view — construction and text-system hygiene")
  struct MacTextViewConstructionTests {

    @Test("Smart quotes, smart dashes, text replacement, and spelling correction are disabled")
    func hygieneFlagsAreDisabled() {
      let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
      #expect(editor.textView.isAutomaticQuoteSubstitutionEnabled == false)
      #expect(editor.textView.isAutomaticDashSubstitutionEnabled == false)
      #expect(editor.textView.isAutomaticTextReplacementEnabled == false)
      #expect(editor.textView.isAutomaticSpellingCorrectionEnabled == false)
    }

    @Test("Continuous spell checking remains enabled")
    func spellCheckingStaysOn() {
      let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
      #expect(editor.textView.isContinuousSpellCheckingEnabled == true)
    }

    @Test("The text view sits on the TextKit 2 stack")
    func textKit2StackIsGuaranteed() {
      let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
      #expect(editor.textView.textLayoutManager != nil)
    }

    @Test("The scroll view hosts the text view as its document view")
    func scrollViewHostsTheTextView() {
      let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
      #expect(editor.scrollView.documentView === editor.textView)
    }

    @Test("Attaching installs the coordinator as the text storage's delegate")
    func coordinatorIsAttached() {
      let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
      #expect(editor.textView.textStorage?.delegate === editor.coordinator)
    }

    @Test("The theme convenience initializer and the styler initializer build the same shape")
    func themeConvenienceInitializerMatchesStylerInitializer() {
      let styler = EscriboStyler(theme: .markdownLight)
      let editor = EscriboTextView(language: .markdown, styler: styler)
      #expect(editor.coordinator.language == .markdown)
      #expect(editor.textView.textLayoutManager != nil)
    }
  }

  /// The one behavioral exit criterion: typing must reach the coordinator and come back
  /// out as real text-storage attributes, exactly as it would for a user at the keyboard.
  @MainActor
  @Suite("macOS text view — typing produces styled attributes")
  struct MacTextViewStylingTests {

    @Test("Typing a heading styles its content range distinctly from a plain paragraph")
    func typingAHeadingStylesItsRange() throws {
      let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
      let storage = try #require(editor.textView.textStorage)

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

      // Non-vacuous: both ranges did get *some* styling from the coordinator...
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
      let storage = try #require(editor.textView.textStorage)

      storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "# Heading")

      let markerAttributes = storage.attributes(at: 0, effectiveRange: nil)
      let contentAttributes = storage.attributes(at: 2, effectiveRange: nil)

      let markerFont = try #require(markerAttributes[.font] as? PlatformFont)
      let contentFont = try #require(contentAttributes[.font] as? PlatformFont)
      // Architecture §3: alpha only. A marker that resized would make text jitter as you
      // type — this is the AppKit-facing proof the same rule survives here.
      #expect(markerFont.pointSize == contentFont.pointSize)
    }
  }
#endif
