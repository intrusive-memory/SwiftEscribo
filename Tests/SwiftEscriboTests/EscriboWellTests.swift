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

/// Sortie 5 of the 1.1.0 plan: the paragraph well's model, its lane, and its eligibility
/// (REQUIREMENTS-1.1.0 § 5.1, § 5.3, D-5).
///
/// Nothing here draws. These tests pin the three things the drawing will stand on: an
/// adopter who passes no well is untouched, the lane is the width the requirements name on
/// each platform and size class, and eligibility is the host's data rather than a language
/// rule inside the package.
///
/// `@MainActor` for the reason `CoordinatorFixtures` documents: every test that builds a
/// real text view is exercising main-thread-owned AppKit/UIKit objects.
@MainActor
@Suite("Paragraph well — model, lane, and eligibility")
struct EscriboWellTests {

  // MARK: - Source compatibility

  /// The default-nil exit criterion, carried by what is *absent* from these calls: none of
  /// them mentions `well:` or `onWellAction:`, and all of them compile only because both are
  /// defaulted and trail the parameter list.
  @Test("EscriboEditor constructs without a well, exactly as every pre-0.4.0 call site does")
  func editorConstructsWithoutAWell() {
    _ = EscriboEditor(text: .constant(""), language: .markdown)
    _ = EscriboEditor(
      text: .constant(""), language: .fountain, mode: .source, theme: .fountainDark,
      findBar: true, focusOnAppear: true, handle: nil)

    let view: any View = EscriboEditor(text: .constant(""), language: .markdown)
    #expect(view is EscriboEditor)
  }

  @Test("EscriboEditor accepts a well and a well action")
  func editorConstructsWithAWell() {
    let view: any View = EscriboEditor(
      text: .constant(""), language: .markdown, well: EscriboWell(),
      onWellAction: { _, _ in })
    #expect(view is EscriboEditor)
  }

  @Test("A well is EscriboWellItem.readAloud by default and nothing else")
  func wellDefaults() {
    let well = EscriboWell()
    #expect(well.items == [.readAloud])
    #expect(well.activeBlock == nil)
    #expect(well.progress == nil)
    #expect(well.spokenRange == nil)
    #expect(well.eligibleKinds == nil)
  }

  @Test("EscriboWell is Equatable across every field, eligibility included")
  func wellIsEquatable() {
    #expect(EscriboWell() == EscriboWell())
    #expect(EscriboWell(progress: 0.5) != EscriboWell())
    #expect(EscriboWell(spokenRange: NSRange(location: 3, length: 4)) != EscriboWell())
    #expect(EscriboWell(eligibleKinds: [.paragraph]) != EscriboWell())
    #expect(EscriboWell(eligibleKinds: [.paragraph]) == EscriboWell(eligibleKinds: [.paragraph]))
  }

  // MARK: - Lane width (§ 5.1, D-5)

  /// The iOS assertion is platform-neutral on purpose — `WellLane` is a pure function of a
  /// named platform and size class — so it runs on the iOS test pass *and* the macOS one.
  @Test("iOS lane: 0 at compact, 44 at regular, 0 when the size class is unknown")
  func iOSLaneWidthFollowsSizeClass() {
    #expect(WellLane.width(on: .iOS, horizontalSizeClass: .compact) == 0)
    #expect(WellLane.width(on: .iOS, horizontalSizeClass: .regular) == 44)
    #expect(WellLane.width(on: .iOS, horizontalSizeClass: nil) == 0)
  }

  @Test("macOS lane: 28 regardless of size class")
  func macOSLaneWidthIsFixed() {
    #expect(WellLane.width(on: .macOS, horizontalSizeClass: nil) == 28)
    #expect(WellLane.width(on: .macOS, horizontalSizeClass: .compact) == 28)
    #expect(WellLane.width(on: .macOS, horizontalSizeClass: .regular) == 28)
  }

  @Test("No well reserves no lane, on any platform or size class")
  func noWellReservesNothing() {
    #expect(WellLane.reservedWidth(for: nil, horizontalSizeClass: .regular) == 0)
    #expect(WellLane.reservedWidth(for: nil, horizontalSizeClass: .compact) == 0)
    #expect(WellLane.reservedWidth(for: nil, horizontalSizeClass: nil) == 0)
  }

  @Test("The compiled platform is the one the text view asks about")
  func currentPlatformMatchesTheBuild() {
    #if os(macOS)
      #expect(WellLane.Platform.current == .macOS)
      #expect(WellLane.reservedWidth(for: EscriboWell(), horizontalSizeClass: nil) == 28)
    #else
      #expect(WellLane.Platform.current == .iOS)
      #expect(WellLane.reservedWidth(for: EscriboWell(), horizontalSizeClass: .regular) == 44)
      #expect(WellLane.reservedWidth(for: EscriboWell(), horizontalSizeClass: .compact) == 0)
    #endif
  }

  #if os(iOS)
    @Test("SwiftUI's size class maps onto the lane's, and nil stays nil")
    func swiftUISizeClassMaps() {
      #expect(WellLane.HorizontalSizeClass(UserInterfaceSizeClass.regular) == .regular)
      #expect(WellLane.HorizontalSizeClass(UserInterfaceSizeClass.compact) == .compact)
      #expect(WellLane.HorizontalSizeClass(nil) == nil)
    }
  #endif

  // MARK: - The lane in the text-container inset

  @Test("A bridge given no well leaves the text view's inset exactly as its initializer set it")
  func nilWellPreservesTodaysInset() {
    let reference = EscriboTextView(language: .markdown, theme: .markdownLight)

    let bridge = EscriboEditorBridge(text: .constant("# Heading\n"))
    let editor = bridge.makeEditor(
      language: .markdown, mode: .live, theme: .markdownLight, appearance: .light)
    #expect(editor.well == nil)
    #expect(editor.wellLaneWidth == 0)
    #expect(editor.textView.textContainerInset == reference.textView.textContainerInset)

    bridge.update(
      language: .markdown, mode: .live, theme: .markdownLight, appearance: .light,
      text: "# Heading\n")
    #expect(editor.textView.textContainerInset == reference.textView.textContainerInset)
  }

  @Test("The well is stored, re-applied on update, and removed without disturbing the inset")
  func wellRoundTripsThroughTheBridge() {
    let reference = EscriboTextView(language: .markdown, theme: .markdownLight)
    let bridge = EscriboEditorBridge(text: .constant(""))
    let well = EscriboWell(progress: 0.25)
    let editor = bridge.makeEditor(
      language: .markdown, mode: .live, theme: .markdownLight, appearance: .light,
      well: well, horizontalSizeClass: .regular)
    #expect(editor.well == well)

    let playing = EscriboWell(progress: 0.75)
    bridge.update(
      language: .markdown, mode: .live, theme: .markdownLight, appearance: .light, text: "",
      well: playing, horizontalSizeClass: .regular)
    #expect(editor.well == playing)

    bridge.update(
      language: .markdown, mode: .live, theme: .markdownLight, appearance: .light, text: "",
      well: nil, horizontalSizeClass: .regular)
    #expect(editor.well == nil)
    #expect(editor.wellLaneWidth == 0)
    #expect(editor.textView.textContainerInset == reference.textView.textContainerInset)
  }

  #if os(macOS)
    @Test("macOS: the inset grows by 28 on the width axis only, added to the existing inset")
    func macOSInsetIsSymmetricAndAdditive() {
      let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
      editor.textView.textContainerInset = NSSize(width: 5, height: 7)

      editor.applyWell(EscriboWell(), horizontalSizeClass: nil)
      #expect(editor.textView.textContainerInset == NSSize(width: 33, height: 7))

      // Re-applying the same lane is a no-op, not a second 28 pt.
      editor.applyWell(EscriboWell(progress: 0.5), horizontalSizeClass: nil)
      #expect(editor.textView.textContainerInset == NSSize(width: 33, height: 7))

      editor.applyWell(nil, horizontalSizeClass: nil)
      #expect(editor.textView.textContainerInset == NSSize(width: 5, height: 7))
    }

    /// Installs `editor`'s scroll view in a 600 × 400 window and returns the window.
    ///
    /// **Why a window.** The lane arithmetic is a fact about a text view with a real width:
    /// with `widthTracksTextView`, AppKit recomputes the container as
    /// `frame.width - 2 × textContainerInset.width` the moment the inset changes, so a
    /// container sized by hand is overwritten from the frame, and a windowless view's frame
    /// is zero. Resizing a windowless view directly is not an option either — it hangs this
    /// test process. Hosting the scroll view the way `MacTextViewFocusOnAppearTests` does
    /// gives the text view its width the way the app does: the clip view autoresizes the
    /// document view, whose mask is `[.width]`.
    ///
    /// The vertical scroller may take some of the 600 pt, so every assertion below measures
    /// against the text view's actual `frame.width`, never against the window's.
    ///
    /// `NSApplication.shared` is touched first because AppKit's window machinery expects an
    /// initialized app object, and an `xctest` process has not necessarily created one.
    private func host(_ editor: EscriboTextView) throws -> NSWindow {
      _ = NSApplication.shared
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
        styleMask: [.titled, .resizable],
        backing: .buffered,
        defer: false)
      let content = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
      window.contentView = content
      editor.scrollView.frame = content.bounds
      content.addSubview(editor.scrollView)

      let container = try #require(editor.textView.textContainer)
      #expect(container.widthTracksTextView, "the lane arithmetic assumes a tracking container")
      // A text view too narrow to hold both lanes would make every width below meaningless.
      try #require(editor.textView.frame.width > 4 * 28, "hosting gave the text view no width")
      return window
    }

    /// The width AppKit's tracking gives `editor`'s container for its current frame and inset.
    private func trackedWidth(_ editor: EscriboTextView) -> CGFloat {
      editor.textView.frame.width - 2 * editor.textView.textContainerInset.width
    }

    @Test("macOS: usable container width shrinks by exactly 2 × 28 with a well, and not without")
    func macOSUsableWidthShrinksByTwiceTheLane() throws {
      let plain = EscriboTextView(language: .markdown, theme: .markdownLight)
      let plainWindow = try host(plain)
      plain.applyWell(nil, horizontalSizeClass: nil)
      let plainWidth = try #require(plain.textView.textContainer).size.width

      // The nil-well control: an editor never given a well at all measures the same.
      let untouched = EscriboTextView(language: .markdown, theme: .markdownLight)
      let untouchedWindow = try host(untouched)
      #expect(try #require(untouched.textView.textContainer).size.width == plainWidth)

      let welled = EscriboTextView(language: .markdown, theme: .markdownLight)
      let welledWindow = try host(welled)
      welled.applyWell(EscriboWell(), horizontalSizeClass: nil)
      let welledWidth = try #require(welled.textView.textContainer).size.width

      // Identical windows and scrollers, so the frames agree and the difference is the lane.
      #expect(plain.textView.frame.width == welled.textView.frame.width)
      #expect(plainWidth - welledWidth == CGFloat(2 * 28))

      // And the narrower width is the one AppKit's tracking computes for the same view with
      // the widened inset, so the next real resize agrees with it rather than undoing it.
      #expect(welledWidth == trackedWidth(welled))
      #expect(plainWidth == trackedWidth(plain))

      withExtendedLifetime((plainWindow, untouchedWindow, welledWindow)) {}
    }

    @Test("macOS: a live, already-hosted editor reflows when its well appears and disappears")
    func macOSLiveEditorReflows() throws {
      let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
      let window = try host(editor)
      let container = try #require(editor.textView.textContainer)
      let before = container.size.width
      #expect(before == trackedWidth(editor))

      editor.applyWell(EscriboWell(), horizontalSizeClass: nil)
      #expect(before - container.size.width == CGFloat(2 * 28))
      #expect(container.size.width == trackedWidth(editor))

      // A playback update carries a new well every frame; the lane is already reserved, so
      // the container must not shrink a second time.
      editor.applyWell(EscriboWell(progress: 0.5), horizontalSizeClass: nil)
      #expect(before - container.size.width == CGFloat(2 * 28))
      #expect(container.size.width == trackedWidth(editor))

      editor.applyWell(nil, horizontalSizeClass: nil)
      #expect(container.size.width == before)
      #expect(container.size.width == trackedWidth(editor))

      withExtendedLifetime(window) {}
    }
  #endif

  #if os(iOS)
    @Test("iOS: the lane is left-only, 44 at regular, nothing at compact, added to the inset")
    func iOSInsetIsLeftOnlyAndFollowsSizeClass() {
      let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
      let original = editor.textView.textContainerInset

      editor.applyWell(EscriboWell(), horizontalSizeClass: .compact)
      #expect(editor.textView.textContainerInset == original, "D-5: no lane at compact")

      editor.applyWell(EscriboWell(), horizontalSizeClass: .regular)
      let regular = editor.textView.textContainerInset
      #expect(regular.left == original.left + 44)
      #expect(regular.right == original.right)
      #expect(regular.top == original.top)
      #expect(regular.bottom == original.bottom)

      // Regular → compact, as a split-view resize would: the lane is released exactly.
      editor.applyWell(EscriboWell(), horizontalSizeClass: .compact)
      #expect(editor.textView.textContainerInset == original)

      editor.applyWell(EscriboWell(), horizontalSizeClass: .regular)
      editor.applyWell(nil, horizontalSizeClass: .regular)
      #expect(editor.textView.textContainerInset == original)
    }
  #endif

  // MARK: - Eligibility is data

  @Test("Default eligibility: every kind with content, and nothing without it")
  func defaultEligibilityEncodesNoLanguage() {
    //   "one\n\ntwo" — a paragraph, a blank run, a paragraph.
    let editor = CoordinatorFixtures.makeEditor("one\n\ntwo")
    let blocks = editor.coordinator.documentBlocks
    #expect(blocks.map(\.kind) == [.paragraph, .blank, .paragraph])

    let well = EscriboWell()
    #expect(blocks.map { well.isEligible($0) } == [true, false, true])
  }

  @Test("A caller-supplied kind set decides eligibility")
  func eligibleKindsAreTheCallersChoice() throws {
    let editor = CoordinatorFixtures.makeEditor("one\n\ntwo")
    let paragraph = try #require(editor.coordinator.documentBlocks.first)
    #expect(paragraph.kind == .paragraph)

    #expect(EscriboWell(eligibleKinds: [.paragraph]).isEligible(paragraph))
    #expect(EscriboWell(eligibleKinds: [.speech, .action]).isEligible(paragraph) == false)
    #expect(EscriboWell(eligibleKinds: []).isEligible(paragraph) == false)
  }
}
