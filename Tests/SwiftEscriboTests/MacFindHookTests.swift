#if os(macOS)
  import AppKit
  import EscriboCore
  import Foundation
  import Testing

  @testable import SwiftEscribo

  /// REQUIREMENTS.md § 1.3, Find, on macOS: a Find match inside an embed is reported to the
  /// host through `onFindMatchInEmbed`, once, and is let through unsnapped.
  ///
  /// These drive AppKit's real `NSTextFinder` through the text view's own
  /// `performTextFinderAction(_:)` / `performFindPanelAction(_:)` with a real search string,
  /// in a window: Use Selection for Find (⌘E) sets the string from a selection, then Find
  /// Next (⌘G) walks the matches. That is the menu path; the find bar's own field and
  /// buttons reach the same `NSTextFinderClient` setter (`EscriboNativeTextView.selectedRanges`)
  /// but search asynchronously, which a headless test cannot wait on reliably.
  ///
  /// The fixture has "the" twice: once in "Bob waits by the door." (plain text) and once in
  /// the note's "First line of the note" (inside the embed).
  @MainActor
  @Suite("macOS find current-match hook", .serialized)
  struct MacFindHookTests {

    /// A windowed harness with the find bar on, and the two matches of "the".
    struct FindFixture {
      let h: MacEmbedHarness
      let window: NSWindow
      let outside: NSRange
      let inside: NSRange
    }

    private func makeFixture() throws -> FindFixture {
      let h = try MacEmbedHarness()
      h.textView.usesFindBar = true
      h.textView.isIncrementalSearchingEnabled = true
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 600, height: 800), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = h.editor.scrollView
      window.makeFirstResponder(h.textView)
      _ = h.layout.layout()

      let text = h.string as NSString
      let outside = text.range(of: "the door")
      let inside = text.range(of: "the note")
      #expect(outside.location != NSNotFound && inside.location != NSNotFound)
      #expect(!NSLocationInRange(outside.location, h.note))
      #expect(NSLocationInRange(inside.location, h.note))
      return FindFixture(
        h: h, window: window,
        outside: NSRange(location: outside.location, length: 3),
        inside: NSRange(location: inside.location, length: 3))
    }

    private func finderAction(_ h: MacEmbedHarness, _ action: NSTextFinder.Action) {
      let item = NSMenuItem()
      item.tag = action.rawValue
      h.textView.performTextFinderAction(item)
    }

    /// ⌘E on the plain-text "the", then the caret back at the top, so the next ⌘G finds the
    /// plain-text match first.
    private func searchForThe(_ f: FindFixture) {
      f.h.select(f.outside)
      finderAction(f.h, .setSearchString)
      f.h.caret(0)
      f.h.findMatches.removeAll()
    }

    @Test("Find Next onto a match inside an embed reports it once and keeps the match selected")
    func findNextInsideEmbed() throws {
      let f = try makeFixture()
      defer { f.window.close() }
      let h = f.h
      searchForThe(f)

      finderAction(h, .nextMatch)
      #expect(h.selection == f.outside)
      #expect(h.findMatches.isEmpty)

      finderAction(h, .nextMatch)
      #expect(h.selection == f.inside, "the match is not snapped to the whole block")
      #expect(h.findMatches.count == 1)
      #expect(h.findMatches.first?.range == h.layout.note)

      // NSTextFinder re-asserts its current match (the find bar does on every change to its
      // field): the same match is not reported twice.
      h.textView.selectedRanges = [NSValue(range: f.inside)]
      #expect(h.selection == f.inside)
      #expect(h.findMatches.count == 1)

      // Wrapping round to the plain-text match and back is a new match: reported again,
      // here through the Find menu's older action, which reaches the same finder.
      finderAction(h, .nextMatch)
      #expect(h.selection == f.outside)
      let item = NSMenuItem()
      item.tag = Int(NSFindPanelAction.next.rawValue)
      h.textView.performFindPanelAction(item)
      #expect(h.selection == f.inside)
      #expect(h.findMatches.count == 2)
      #expect(h.activations.isEmpty, "a Find match is not a click")
    }

    @Test("A match outside any embed never calls onFindMatchInEmbed")
    func matchOutsideEmbedDoesNotReport() throws {
      let f = try makeFixture()
      defer { f.window.close() }
      let h = f.h
      searchForThe(f)

      finderAction(h, .nextMatch)
      #expect(h.selection == f.outside)
      #expect(h.findMatches.isEmpty)

      // Again from the top, and from just past the embed (so Find Next wraps straight to
      // the plain-text match): a match outside the embed is never reported.
      h.caret(0)
      finderAction(h, .nextMatch)
      h.caret(NSMaxRange(h.note))
      finderAction(h, .nextMatch)
      #expect(h.selection == f.outside)
      #expect(h.findMatches.isEmpty)
    }

    @Test("When the host stops the embed and invalidates, the block draws as text, match selected")
    func hostExpandsTheEmbed() throws {
      let f = try makeFixture()
      defer { f.window.close() }
      let h = f.h
      let controller = try #require(h.editor.embedLayout)
      let embedded = try #require(h.editor.coordinator.embeddedBlocks.first)
      #expect(controller.rowRect(for: embedded) != nil)

      // What a host does: stop returning an embed for the block and invalidate, from inside
      // the callback.
      h.onFindMatch = { block in
        h.layout.provider.refused.insert(block.range.lowerBound)
        h.editor.coordinator.invalidateEmbeds()
      }
      searchForThe(f)
      finderAction(h, .nextMatch)
      finderAction(h, .nextMatch)
      settleEventGroup()

      #expect(h.findMatches.count == 1)
      #expect(h.editor.coordinator.embeddedBlocks.isEmpty)
      #expect(controller.rowRect(for: embedded) == nil, "no row is drawn for the block")
      for paragraph in h.layout.noteParagraphs(h.layout.layout()) {
        #expect(!(paragraph.fragment is EmbedRowFragment), "paragraph at \(paragraph.offset)")
        #expect(!(paragraph.fragment is EmbedCollapsedFragment), "paragraph at \(paragraph.offset)")
      }
      #expect(h.selection == f.inside, "the match is still selected")

      // Now ordinary text: a selection inside it is no longer snapped.
      let caret = NSRange(location: f.inside.location + 1, length: 0)
      h.select(caret)
      #expect(h.selection == caret)
    }

    @Test("A programmatic selection inside an embed still snaps while Find is in use")
    func nonFindSelectionStillSnaps() throws {
      let f = try makeFixture()
      defer { f.window.close() }
      let h = f.h
      searchForThe(f)

      h.select(f.inside)
      #expect(h.selection == h.note)

      // A Find match left inside the embed (a host that does not expand it) is no shelter:
      // the next selection that is not a match snaps again.
      finderAction(h, .nextMatch)
      finderAction(h, .nextMatch)
      #expect(h.selection == f.inside)
      h.select(NSRange(location: f.inside.location + 1, length: 2))
      #expect(h.selection == h.note)
      #expect(!h.textView.isApplyingFindSelection)
    }
  }
#endif
