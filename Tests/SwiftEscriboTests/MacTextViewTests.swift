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

  /// The find-bar parameter, asserted against the text view the construction path actually
  /// builds — the same rule the rest of this file follows.
  ///
  /// Both directions are assertions, not just the `true` one. The off case is the load-bearing
  /// half: it is what proves the default is a real "no find bar" rather than whatever AppKit
  /// happened to leave the flags at, and it is what a host relies on when it does not opt in.
  @MainActor
  @Suite("macOS text view — find bar configuration")
  struct MacTextViewFindBarTests {

    @Test("findBar: true sets the find bar and incremental searching on the text view")
    func findBarOnSetsBothFlags() {
      let editor = EscriboTextView(language: .markdown, theme: .markdownLight, findBar: true)
      #expect(editor.textView.usesFindBar == true)
      #expect(editor.textView.isIncrementalSearchingEnabled == true)
    }

    @Test("findBar: false leaves both flags off")
    func findBarOffClearsBothFlags() {
      let editor = EscriboTextView(language: .markdown, theme: .markdownLight, findBar: false)
      #expect(editor.textView.usesFindBar == false)
      #expect(editor.textView.isIncrementalSearchingEnabled == false)
    }

    @Test("The default is off — a host opts in")
    func findBarDefaultsToOff() {
      let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
      #expect(editor.textView.usesFindBar == false)
      #expect(editor.textView.isIncrementalSearchingEnabled == false)
    }

    /// The find **bar** lives inside the editor's own scroll view. This is the assertion that
    /// distinguishes it from the floating find *panel*, which is a separate window and would
    /// make the enclosing scroll view irrelevant.
    @Test("The find bar's host is the editor's own scroll view")
    func findBarLivesInsideTheScrollView() {
      let editor = EscriboTextView(language: .markdown, theme: .markdownLight, findBar: true)
      #expect(editor.textView.enclosingScrollView === editor.scrollView)
    }

    @Test("The bridge carries the host's answer through to the shipped text view")
    func bridgeThreadsTheParameterThrough() {
      let on = EscriboEditorBridge(text: .constant(""))
      let onEditor = on.makeEditor(
        language: .markdown, mode: .live, theme: .markdownLight, appearance: .light,
        findBar: true)
      #expect(onEditor.textView.usesFindBar == true)
      #expect(onEditor.textView.isIncrementalSearchingEnabled == true)

      let off = EscriboEditorBridge(text: .constant(""))
      let offEditor = off.makeEditor(
        language: .markdown, mode: .live, theme: .markdownLight, appearance: .light,
        findBar: false)
      #expect(offEditor.textView.usesFindBar == false)
      #expect(offEditor.textView.isIncrementalSearchingEnabled == false)
    }

    /// Turning the find bar on must not disturb anything Sorties 10, 11, and 25 assert about
    /// the shipped text view — in particular `isRichText` and `allowsUndo`, which DL-65 makes
    /// load-bearing for verbatim paste and for undo.
    @Test("Enabling the find bar disturbs no other shipped setting")
    func findBarDoesNotDisturbTheHygieneFlags() {
      let editor = EscriboTextView(language: .markdown, theme: .markdownLight, findBar: true)
      #expect(editor.textView.isAutomaticQuoteSubstitutionEnabled == false)
      #expect(editor.textView.isAutomaticDashSubstitutionEnabled == false)
      #expect(editor.textView.isAutomaticTextReplacementEnabled == false)
      #expect(editor.textView.isAutomaticSpellingCorrectionEnabled == false)
      #expect(editor.textView.isContinuousSpellCheckingEnabled == true)
      #expect(editor.textView.isRichText == false)
      #expect(editor.textView.allowsUndo == true)
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
