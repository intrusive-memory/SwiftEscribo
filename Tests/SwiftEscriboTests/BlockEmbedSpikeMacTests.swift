#if os(macOS)
  import AppKit
  import EscriboCore
  import Foundation
  import Testing

  @testable import SwiftEscribo

  // SPIKE — throwaway tests for the atomic block-embed experiment.

  /// One laid-out paragraph: its UTF-16 offset, frame, and fragment class.
  struct SpikeLaidOutParagraph {
    var offset: Int
    var frame: CGRect
    var fragment: NSTextLayoutFragment
  }

  @MainActor
  struct SpikeMacHarness {
    let editor: EscriboTextView
    let note: NSRange

    static let content = SpikeEmbedContent(
      symbolName: "note.text", title: "Note", subtitle: "First line of the note",
      badge: "3 lines", accessibilityLabel: "Note", accessibilityValue: "First line of the note")

    init(mechanism: SpikeCollapseMechanism = .fragmentFrameOverride, scale: Double = 1) throws {
      let editor = EscriboTextView(language: .fountain, theme: .fountainLight)
      editor.scrollView.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
      editor.textView.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
      if scale != 1 {
        editor.coordinator.styler.environment.metrics = FontMetrics(pointSizeScale: scale)
      }
      editor.applyExternalText(BlockEmbedSpikeFixture.text)
      editor.coordinator.restyleEverything()
      editor.spikeEmbeds.mechanism = mechanism
      let block = try #require(editor.coordinator.documentBlocks.first { $0.kind == .note })
      self.editor = editor
      self.note = NSRange(location: block.range.lowerBound, length: block.range.count)
    }

    func embed() {
      editor.spikeSetEmbed(Self.content, forBlockStartingAt: note.location)
    }

    /// Every paragraph's layout fragment, with layout ensured over the whole document.
    func layout() -> [SpikeLaidOutParagraph] {
      guard let tlm = editor.textView.textLayoutManager,
        let content = tlm.textContentManager
      else { return [] }
      tlm.ensureLayout(for: tlm.documentRange)
      var result: [SpikeLaidOutParagraph] = []
      tlm.enumerateTextLayoutFragments(from: tlm.documentRange.location, options: [.ensuresLayout]) {
        fragment in
        let offset = content.offset(
          from: content.documentRange.location, to: fragment.rangeInElement.location)
        result.append(
          SpikeLaidOutParagraph(offset: offset, frame: fragment.layoutFragmentFrame, fragment: fragment))
        return true
      }
      return result
    }

    func notParagraphs(_ laid: [SpikeLaidOutParagraph]) -> [SpikeLaidOutParagraph] {
      laid.filter { $0.offset >= note.location && $0.offset < NSMaxRange(note) }
    }

    /// Total vertical extent the note's paragraphs occupy (top of first to bottom of last).
    func noteExtent(_ laid: [SpikeLaidOutParagraph]) -> CGFloat {
      let paras = notParagraphs(laid)
      guard let first = paras.first, let last = paras.last else { return 0 }
      return last.frame.maxY - first.frame.minY
    }
  }

  @MainActor
  @Suite("Block embed spike — macOS draw", .serialized)
  struct BlockEmbedSpikeMacTests {

    // MARK: - Row 1: draw

    @Test("row 1: the embed draws as one fixed-height custom row; the rest lays out normally")
    func row1FixedHeightRow() throws {
      let h = try SpikeMacHarness()
      let before = h.layout()
      h.embed()
      let after = h.layout()
      let rowHeight = h.editor.spikeEmbeds.rowHeight

      #expect(before.count == after.count)
      let paras = h.notParagraphs(after)
      let first = try #require(paras.first)
      let row = try #require(first.fragment as? SpikeEmbedRowFragment)
      #expect(abs(first.frame.height - rowHeight) <= 0.5)
      #expect(row.content == SpikeMacHarness.content)
      // At the paragraph's leading indent, read from the real storage.
      let style = h.editor.textView.textStorage?.attribute(
        .paragraphStyle, at: h.note.location, effectiveRange: nil) as? NSParagraphStyle
      #expect(row.indent == (style?.firstLineHeadIndent ?? 0))

      // Before the block: untouched. After: own heights kept.
      for (b, a) in zip(before, after) where a.offset < h.note.location {
        #expect(a.frame == b.frame)
        #expect(type(of: a.fragment) == NSTextLayoutFragment.self)
      }
      for (b, a) in zip(before, after) where a.offset >= NSMaxRange(h.note) {
        #expect(abs(a.frame.height - b.frame.height) <= 0.5)
        #expect(type(of: a.fragment) == NSTextLayoutFragment.self)
      }
      // Contiguous: every fragment starts where the previous one ends.
      for (prev, next) in zip(after, after.dropFirst()) {
        #expect(abs(next.frame.minY - prev.frame.maxY) <= 0.5, "gap before offset \(next.offset)")
      }

      // Drawing the row runs without trapping (symbol, two lines, badge).
      let tv = h.editor.textView
      let rep = try #require(tv.bitmapImageRepForCachingDisplay(in: tv.bounds))
      tv.cacheDisplay(in: tv.bounds, to: rep)
    }

    @Test("row 1: zoom (pointSizeScale 2) scales the row, and it survives the coordinator's restyle")
    func row1ZoomScalesRow() throws {
      let h = try SpikeMacHarness()
      h.embed()
      let baseline = try #require(h.notParagraphs(h.layout()).first)
      #expect(baseline.fragment is SpikeEmbedRowFragment)

      // Zoom the way the package does: new metrics, then the coordinator rewrites every
      // attribute (paragraph styles included) into storage.
      h.editor.coordinator.styler.environment.metrics = FontMetrics(pointSizeScale: 2)
      h.editor.coordinator.restyleEverything()

      let zoomed = h.layout()
      let first = try #require(h.notParagraphs(zoomed).first)
      #expect(first.fragment is SpikeEmbedRowFragment)
      #expect(first.frame.height > 1.5 * baseline.frame.height)
      #expect(abs(h.noteExtent(zoomed) - first.frame.height) <= 0.5)

      // A harness built at 2× from the start agrees.
      let h2 = try SpikeMacHarness(scale: 2)
      h2.embed()
      let fresh = try #require(h2.notParagraphs(h2.layout()).first)
      #expect(abs(fresh.frame.height - first.frame.height) <= 0.5)
    }

    // MARK: - Row 2: storage untouched

    @Test("row 2: textStorage is byte-identical with the embed; find, copy-all and word count see the source")
    func row2StorageUntouched() throws {
      let h = try SpikeMacHarness()
      let storage = try #require(h.editor.textView.textStorage)
      let original = storage.string
      let originalData = Data(original.utf8)
      let originalAttrs = NSAttributedString(attributedString: storage)
      let restyles = h.editor.coordinator.restyleCount

      h.embed()
      _ = h.layout()

      #expect(Data(storage.string.utf8) == originalData)
      #expect(storage.string == BlockEmbedSpikeFixture.text)
      // Not even attributes moved, and the coordinator was never asked to restyle.
      #expect(storage.isEqual(to: originalAttrs))
      #expect(h.editor.coordinator.restyleCount == restyles)

      // Find a note word through the storage string.
      let found = (storage.string as NSString).range(of: "second line")
      #expect(found.location != NSNotFound)
      #expect(NSLocationInRange(found.location, h.note))

      // Word count over the source.
      func words(_ s: String) -> Int {
        var n = 0
        s.enumerateSubstrings(in: s.startIndex..., options: .byWords) { _, _, _, _ in n += 1 }
        return n
      }
      #expect(words(storage.string) == words(BlockEmbedSpikeFixture.text))
      #expect(words(storage.string) > 0)

      // Copy-all puts the original characters on the pasteboard.
      let pasteboard = NSPasteboard(name: NSPasteboard.Name("escribo.spike.row2.\(UUID())"))
      defer { pasteboard.releaseGlobally() }
      h.editor.textView.selectAll(nil)
      #expect(
        h.editor.textView.writeSelection(
          to: pasteboard, types: h.editor.textView.writablePasteboardTypes))
      #expect(pasteboard.string(forType: .string) == BlockEmbedSpikeFixture.text)

      // And after a full restyle (the coordinator writes paragraph attributes), still so.
      h.editor.coordinator.restyleEverything()
      #expect(storage.string == BlockEmbedSpikeFixture.text)
      #expect(h.notParagraphs(h.layout()).first?.fragment is SpikeEmbedRowFragment)
    }

    // MARK: - Row 10: multi-line block

    @Test("row 10: the three note paragraphs (three layout fragments) together occupy exactly one row")
    func row10MultiLineCollapse() throws {
      let h = try SpikeMacHarness()
      let unembedded = h.noteExtent(h.layout())
      h.embed()
      let laid = h.layout()
      let paras = h.notParagraphs(laid)
      let rowHeight = h.editor.spikeEmbeds.rowHeight

      #expect(paras.count == 3)
      #expect(paras.first?.fragment is SpikeEmbedRowFragment)
      for p in paras.dropFirst() {
        #expect(p.fragment is SpikeEmbedCollapsedFragment)
        #expect(p.frame.height == 0)
      }
      #expect(abs(h.noteExtent(laid) - rowHeight) <= 0.5)
      // Non-vacuous: un-embedded, the note is three lines tall, not one row.
      #expect(abs(unembedded - rowHeight) > 0.5)

      // The paragraph after the block starts right below the row.
      let next = try #require(laid.first { $0.offset == NSMaxRange(h.note) })
      let first = try #require(paras.first)
      #expect(abs(next.frame.minY - (first.frame.minY + rowHeight)) <= 0.5)
    }

    @Test("row 10: mechanism comparison — only the frame override collapses N fragments without a storage edit")
    func row10MechanismComparison() throws {
      var extents: [SpikeCollapseMechanism: CGFloat] = [:]
      var rowHeight: CGFloat = 0
      for mechanism in SpikeCollapseMechanism.allCases {
        let h = try SpikeMacHarness(mechanism: mechanism)
        // The realistic case: the document is already laid out when the host embeds.
        _ = h.layout()
        h.embed()
        extents[mechanism] = h.noteExtent(h.layout())
        rowHeight = h.editor.spikeEmbeds.rowHeight
      }
      // Draw-only keeps three line heights.
      #expect(abs((extents[.fragmentDrawOnly] ?? 0) - rowHeight) > 0.5)
      // The frame override collapses to one row.
      #expect(abs((extents[.fragmentFrameOverride] ?? 0) - rowHeight) <= 0.5)
      // The content-storage paragraph is never re-vended without a storage edit.
      #expect(abs((extents[.contentStorageParagraph] ?? 0) - rowHeight) > 0.5)
    }

    // MARK: - Rows 3–7: atomic behaviour

    /// True when `location` is strictly inside `range` (an edge is not inside).
    static func strictlyInside(_ location: Int, _ range: NSRange) -> Bool {
      location > range.location && location < NSMaxRange(range)
    }

    @Test("row 3: left/right arrows from the block's edges step over it; never inside")
    func row3LeftRightStepOver() throws {
      let h = try SpikeMacHarness()
      h.embed()
      _ = h.layout()
      let tv = h.editor.textView
      let note = h.note

      // Right from the start edge lands on the end edge.
      tv.setSelectedRange(NSRange(location: note.location, length: 0))
      tv.moveRight(nil)
      #expect(tv.selectedRange() == NSRange(location: NSMaxRange(note), length: 0))
      // Left from the end edge lands on the start edge.
      tv.moveLeft(nil)
      #expect(tv.selectedRange() == NSRange(location: note.location, length: 0))

      // Walk right across the whole document, then left: never strictly inside.
      tv.setSelectedRange(NSRange(location: 0, length: 0))
      var visited: [Int] = []
      for _ in 0..<((tv.string as NSString).length + 2) {
        tv.moveRight(nil)
        visited.append(tv.selectedRange().location)
      }
      for _ in 0..<((tv.string as NSString).length + 2) {
        tv.moveLeft(nil)
        visited.append(tv.selectedRange().location)
      }
      #expect(!visited.contains { Self.strictlyInside($0, note) })
      #expect(visited.contains(note.location) && visited.contains(NSMaxRange(note)))
    }

    @Test("row 3: up/down from the adjacent lines land after/before the block; never inside")
    func row3UpDownStepOver() throws {
      let h = try SpikeMacHarness()
      h.embed()
      _ = h.layout()
      let tv = h.editor.textView
      let note = h.note

      // Down from the blank line just above the block: AppKit's own step lands on the
      // block's start edge (the row's leading edge — "before" it, not inside); the next Down
      // lands after it.
      tv.setSelectedRange(NSRange(location: note.location - 1, length: 0))
      tv.moveDown(nil)
      let firstDown = tv.selectedRange()
      #expect(firstDown.length == 0)
      #expect(firstDown.location == note.location || firstDown.location == NSMaxRange(note),
        "first down → \(firstDown.location); note \(note)")
      if firstDown.location == note.location {
        tv.moveDown(nil)
        #expect(tv.selectedRange() == NSRange(location: NSMaxRange(note), length: 0),
          "second down → \(tv.selectedRange().location); note \(note)")
      }
      // Up from the blank line just below the block lands before it.
      tv.setSelectedRange(NSRange(location: NSMaxRange(note), length: 0))
      tv.moveUp(nil)
      #expect(tv.selectedRange() == NSRange(location: note.location, length: 0),
        "up → \(tv.selectedRange().location); note \(note)")

      // Walk down from the top and up from the bottom: never inside, and the walk crosses.
      tv.setSelectedRange(NSRange(location: 0, length: 0))
      var down: [Int] = []
      for _ in 0..<10 {
        tv.moveDown(nil)
        down.append(tv.selectedRange().location)
      }
      #expect(!down.contains { Self.strictlyInside($0, note) }, "down: \(down)")
      #expect(down.contains { $0 > NSMaxRange(note) }, "down never got past: \(down)")

      tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
      var up: [Int] = []
      for _ in 0..<10 {
        tv.moveUp(nil)
        up.append(tv.selectedRange().location)
      }
      #expect(!up.contains { Self.strictlyInside($0, note) }, "up: \(up)")
      #expect(up.contains { $0 < note.location }, "up never got past: \(up)")
    }

    @Test("row 3: a click inside the row lands the caret on one of the block's edges")
    func row3ClickLandsOnEdge() throws {
      let h = try SpikeMacHarness()
      h.embed()
      let laid = h.layout()
      let tv = h.editor.textView
      let note = h.note
      let row = try #require(h.notParagraphs(laid).first)
      let origin = tv.textContainerOrigin

      let points = [
        CGPoint(x: row.frame.midX, y: row.frame.midY),
        CGPoint(x: row.frame.minX + 4, y: row.frame.minY + 2),
        CGPoint(x: row.frame.maxX - 4, y: row.frame.maxY - 2),
      ]
      var rawInside = 0
      for point in points {
        let viewPoint = CGPoint(x: point.x + origin.x, y: point.y + origin.y)
        let index = tv.characterIndexForInsertion(at: viewPoint)
        if Self.strictlyInside(index, note) { rawInside += 1 }
        for start in [0, (tv.string as NSString).length] {
          tv.setSelectedRange(NSRange(location: start, length: 0))
          tv.setSelectedRange(NSRange(location: index, length: 0))
          let loc = tv.selectedRange().location
          #expect(tv.selectedRange().length == 0)
          #expect(loc == note.location || loc == NSMaxRange(note) || !NSLocationInRange(index, note),
            "click index \(index) → \(loc)")
          #expect(!Self.strictlyInside(loc, note))
        }
      }
      // Non-vacuous: AppKit's own hit-testing does find positions inside the row.
      #expect(rawInside > 0)
    }

    @Test("row 4: shift-arrows that touch the block extend the selection over all of it")
    func row4ShiftArrowSelectsWhole() throws {
      let h = try SpikeMacHarness()
      h.embed()
      _ = h.layout()
      let tv = h.editor.textView
      let note = h.note

      tv.setSelectedRange(NSRange(location: note.location, length: 0))
      tv.moveRightAndModifySelection(nil)
      #expect(tv.selectedRange() == note)

      tv.setSelectedRange(NSRange(location: NSMaxRange(note), length: 0))
      tv.moveLeftAndModifySelection(nil)
      #expect(tv.selectedRange() == note)

      // From the blank line above: the second shift-right touches the block.
      tv.setSelectedRange(NSRange(location: note.location - 1, length: 0))
      tv.moveRightAndModifySelection(nil)
      #expect(tv.selectedRange() == NSRange(location: note.location - 1, length: 1))
      tv.moveRightAndModifySelection(nil)
      let sel = tv.selectedRange()
      #expect(sel.location == note.location - 1 && NSMaxRange(sel) >= NSMaxRange(note))
    }

    @Test("row 4: a drag (stillSelecting) that touches the block extends over all of it")
    func row4DragSelectsWhole() throws {
      let h = try SpikeMacHarness()
      h.embed()
      _ = h.layout()
      let tv = h.editor.textView
      let note = h.note

      tv.setSelectedRange(NSRange(location: note.location - 5, length: 0))
      // Dragging forward into the block's first characters.
      tv.setSelectedRange(
        NSRange(location: note.location - 5, length: 8), affinity: .downstream, stillSelecting: true)
      #expect(tv.selectedRange() == NSRange(location: note.location - 5, length: NSMaxRange(note) - (note.location - 5)))
      // Dragging backward from below into the block's last characters, then releasing.
      let below = NSMaxRange(note) + 3
      tv.setSelectedRange(
        NSRange(location: NSMaxRange(note) - 2, length: below - (NSMaxRange(note) - 2)),
        affinity: .upstream, stillSelecting: true)
      #expect(tv.selectedRange() == NSRange(location: note.location, length: below - note.location))
      tv.setSelectedRange(
        NSRange(location: NSMaxRange(note) - 2, length: below - (NSMaxRange(note) - 2)),
        affinity: .upstream, stillSelecting: false)
      #expect(tv.selectedRange() == NSRange(location: note.location, length: below - note.location))
    }

    @Test("row 5: Delete with the block selected removes exactly deletionRange as one undo step")
    func row5DeleteWhole() throws {
      for forward in [false, true] {
        let h = try SpikeMacHarness()
        let provider = TestUndoManagerProvider()
        h.editor.textView.delegate = provider
        h.embed()
        _ = h.layout()
        settleEventGroup()
        provider.manager.removeAllActions()
        provider.manager.resetCount()

        let tv = h.editor.textView
        let original = tv.string
        let removal = SpikeEmbedSelection.deletionRange(for: h.note, in: original as NSString)
        #expect(removal.length == h.note.length + 1)  // block plus the following blank line
        let expected = (original as NSString).replacingCharacters(in: removal, with: "")

        tv.setSelectedRange(h.note)
        #expect(tv.selectedRange() == h.note)
        if forward { tv.deleteForward(nil) } else { tv.deleteBackward(nil) }
        settleEventGroup()

        #expect(tv.string == expected, "forward: \(forward)")
        #expect(provider.manager.registrations == 1, "forward: \(forward)")
        #expect(h.editor.spikeEmbeds.registry.embeds.isEmpty)

        #expect(provider.manager.canUndo)
        provider.manager.undo()
        #expect(Array(tv.string.utf8) == Array(original.utf8), "forward: \(forward)")
        #expect(!provider.manager.canUndo)
        withExtendedLifetime(provider) {}
      }
    }

    @Test("row 6: copy with the block selected writes the original characters")
    func row6CopySource() throws {
      let h = try SpikeMacHarness()
      h.embed()
      _ = h.layout()
      let tv = h.editor.textView

      let pasteboard = NSPasteboard(name: NSPasteboard.Name("escribo.spike.row6.\(UUID())"))
      defer { pasteboard.releaseGlobally() }
      tv.setSelectedRange(h.note)
      #expect(tv.selectedRange() == h.note)
      #expect(tv.writeSelection(to: pasteboard, types: tv.writablePasteboardTypes))
      #expect(pasteboard.string(forType: .string) == BlockEmbedSpikeFixture.noteLines)

      // A selection that was extended onto the block copies the whole block's source.
      tv.setSelectedRange(NSRange(location: h.note.location - 1, length: 3))
      pasteboard.clearContents()
      #expect(tv.writeSelection(to: pasteboard, types: tv.writablePasteboardTypes))
      #expect(pasteboard.string(forType: .string) == "\n" + BlockEmbedSpikeFixture.noteLines)
    }

    @Test("row 7: typing with the block selected changes nothing")
    func row7TypingIgnored() throws {
      let h = try SpikeMacHarness()
      h.embed()
      _ = h.layout()
      let tv = h.editor.textView
      let original = tv.string

      tv.setSelectedRange(h.note)
      tv.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
      #expect(tv.string == original)
      tv.insertText("x", replacementRange: h.note)
      #expect(tv.string == original)
      tv.insertNewline(nil)  // Return goes through the package's own handler
      #expect(tv.string == original)
      tv.insertTab(nil)
      #expect(tv.string == original)

      // A wider selection containing the block, too.
      tv.setSelectedRange(NSRange(location: h.note.location - 1, length: h.note.length + 2))
      tv.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
      #expect(tv.string == original)

      // Non-vacuous: typing at the block's start edge (outside it) still edits.
      tv.setSelectedRange(NSRange(location: h.note.location, length: 0))
      tv.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
      #expect(tv.string != original)
    }

    // MARK: - Row 8: expand / collapse

    @Test("row 8: expand draws the block as text and lets the caret in; collapse restores the row and the snap")
    func row8ExpandCollapse() throws {
      let h = try SpikeMacHarness()
      h.embed()
      let tv = h.editor.textView
      let note = h.note
      let inside = note.location + 5
      #expect(h.notParagraphs(h.layout()).first?.fragment is SpikeEmbedRowFragment)

      // Expanded: ordinary fragments, ordinary heights, caret may enter.
      h.editor.spikeSetExpanded(true, forBlockStartingAt: note.location)
      let expanded = h.notParagraphs(h.layout())
      #expect(expanded.count == 3)
      for p in expanded {
        #expect(type(of: p.fragment) == NSTextLayoutFragment.self)
        #expect(p.frame.height > 0)
      }
      tv.setSelectedRange(NSRange(location: inside, length: 0))
      #expect(tv.selectedRange() == NSRange(location: inside, length: 0))
      tv.moveRight(nil)
      #expect(tv.selectedRange() == NSRange(location: inside + 1, length: 0))
      #expect(h.editor.spikeEmbeds.accessibilityElements().isEmpty)

      // Collapsed again with the caret inside: the row returns and the caret is pushed out.
      h.editor.spikeSetExpanded(false, forBlockStartingAt: note.location)
      let collapsed = h.layout()
      let paras = h.notParagraphs(collapsed)
      #expect(paras.first?.fragment is SpikeEmbedRowFragment)
      #expect(abs(h.noteExtent(collapsed) - h.editor.spikeEmbeds.rowHeight) <= 0.5)
      #expect(!Self.strictlyInside(tv.selectedRange().location, note))
      tv.setSelectedRange(NSRange(location: inside, length: 0))
      let loc = tv.selectedRange().location
      #expect(loc == note.location || loc == NSMaxRange(note))
    }

    // MARK: - Row 9: accessibility

    @Test("row 9: one accessibility element per embed, label/value from the host, press fires the callback once")
    func row9Accessibility() throws {
      let h = try SpikeMacHarness()
      let tv = h.editor.textView
      let before = tv.accessibilityChildren() ?? []
      #expect(!before.contains { $0 is SpikeEmbedAccessibilityElement })

      h.embed()
      _ = h.layout()
      var activations: [Int] = []
      h.editor.spikeEmbeds.onSpikeEmbedActivate = { activations.append($0) }

      let children = tv.accessibilityChildren() ?? []
      let elements = children.compactMap { $0 as? SpikeEmbedAccessibilityElement }
      #expect(elements.count == 1)
      let element = try #require(elements.first)
      #expect(element.accessibilityRole() == .button)
      #expect(element.accessibilityLabel() == SpikeMacHarness.content.title)
      #expect(
        element.accessibilityValue() as? String
          == "\(SpikeMacHarness.content.subtitle), \(SpikeMacHarness.content.badge)")
      #expect((element.accessibilityParent() as AnyObject?) === tv)
      // Stable identity across queries.
      #expect((tv.accessibilityChildren() ?? []).contains { ($0 as AnyObject) === element })

      // The element's frame is the row.
      let row = try #require(h.notParagraphs(h.layout()).first)
      let frame = element.accessibilityFrameInParentSpace()
      let origin = tv.textContainerOrigin
      #expect(abs(frame.minY - (row.frame.minY + origin.y)) <= 0.5)
      #expect(abs(frame.height - h.editor.spikeEmbeds.rowHeight) <= 0.5)
      #expect(frame.width > 0)

      // In a window, AppKit reports it in screen coordinates.
      let window = NSWindow(
        contentRect: CGRect(x: 100, y: 100, width: 600, height: 800), styleMask: [.titled],
        backing: .buffered, defer: true)
      window.contentView = h.editor.scrollView
      let screenFrame = element.accessibilityFrame()
      let expected = window.convertToScreen(tv.convert(frame, to: nil))
      #expect(abs(screenFrame.minX - expected.minX) <= 1 && abs(screenFrame.minY - expected.minY) <= 1,
        "screen \(screenFrame) vs \(expected)")
      #expect(abs(screenFrame.height - expected.height) <= 1)

      #expect(element.accessibilityPerformPress())
      #expect(activations == [h.note.location])

      // Expanded: no element.
      h.editor.spikeSetExpanded(true, forBlockStartingAt: h.note.location)
      #expect(!(tv.accessibilityChildren() ?? []).contains { $0 is SpikeEmbedAccessibilityElement })
      withExtendedLifetime(window) {}
    }

    // MARK: - Row 11: scroll and edit elsewhere

    @Test("row 11: typing above the block and scrolling keep the row drawn; ≤ 2 row-fragment creations per step")
    func row11ScrollAndEditStability() throws {
      let h = try SpikeMacHarness()
      // A short viewport so the document actually scrolls.
      h.editor.scrollView.frame = CGRect(x: 0, y: 0, width: 600, height: 120)
      h.embed()
      _ = h.layout()
      let tv = h.editor.textView
      let controller = h.editor.spikeEmbeds
      let rowHeight = controller.rowHeight
      let original = tv.string

      func checkRow(_ step: String, noteStart: Int) throws -> Void {
        tv.textLayoutManager?.textViewportLayoutController.layoutViewport()
        let laid = h.layout()
        let paras = laid.filter { $0.offset >= noteStart && $0.offset < noteStart + h.note.length }
        let first = try #require(paras.first, "\(step): no note paragraphs")
        #expect(first.offset == noteStart, "\(step)")
        #expect(first.fragment is SpikeEmbedRowFragment, "\(step): \(type(of: first.fragment))")
        #expect(abs(first.frame.height - rowHeight) <= 0.5, "\(step): height \(first.frame.height)")
        let extent = (paras.last?.frame.maxY ?? 0) - first.frame.minY
        #expect(abs(extent - rowHeight) <= 0.5, "\(step): extent \(extent)")
      }

      // Insert 20 characters, one keystroke at a time, at the end of the action line above.
      let lineEnd = (original as NSString).range(of: "door.").upperBound
      var perEdit: [Int] = []
      for i in 0..<20 {
        let before = controller.rowFragmentCreations
        tv.setSelectedRange(NSRange(location: lineEnd + i, length: 0))
        tv.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        try checkRow("edit \(i + 1)", noteStart: h.note.location + i + 1)
        perEdit.append(controller.rowFragmentCreations - before)
      }
      #expect(tv.string.count == original.count + 20)
      #expect(controller.registry.embeds.keys.sorted() == [h.note.location + 20])
      #expect(perEdit.allSatisfy { $0 <= 2 }, "row fragment creations per edit: \(perEdit)")
      let noteStart = h.note.location + 20

      // Scroll to the bottom and back, several times.
      let clip = h.editor.scrollView.contentView
      let docHeight = h.editor.scrollView.documentView?.frame.height ?? 0
      #expect(docHeight > h.editor.scrollView.frame.height)
      var perScroll: [Int] = []
      for (i, y) in [docHeight, 0, docHeight / 2, docHeight, 0].enumerated() {
        let before = controller.rowFragmentCreations
        clip.scroll(to: NSPoint(x: 0, y: max(0, y - clip.bounds.height)))
        h.editor.scrollView.reflectScrolledClipView(clip)
        try checkRow("scroll \(i)", noteStart: noteStart)
        perScroll.append(controller.rowFragmentCreations - before)
      }
      #expect(perScroll.allSatisfy { $0 <= 2 }, "row fragment creations per scroll: \(perScroll)")
      print("SPIKE row 11 creations per edit: \(perEdit); per scroll: \(perScroll); fallback scans: \(controller.fallbackScans); blocksSpanDocument: \(h.editor.coordinator.blocksSpanDocument)")
    }

    // MARK: - Screenshot evidence

    @Test("evidence: renders collapsed / expanded / zoom2x PNGs when ESCRIBO_SPIKE_EVIDENCE_DIR is set")
    func screenshotEvidence() throws {
      guard let dir = ProcessInfo.processInfo.environment["ESCRIBO_SPIKE_EVIDENCE_DIR"],
        !dir.isEmpty
      else { return }  // CI: no-op
      let url = URL(fileURLWithPath: dir, isDirectory: true)
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

      func render(_ h: SpikeMacHarness, height: CGFloat, to name: String) throws {
        let scroll = h.editor.scrollView
        scroll.appearance = NSAppearance(named: .aqua)
        h.editor.textView.appearance = NSAppearance(named: .aqua)
        scroll.frame = CGRect(x: 0, y: 0, width: 600, height: height)
        _ = h.layout()
        h.editor.textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
        scroll.layoutSubtreeIfNeeded()
        let rep = try #require(scroll.bitmapImageRepForCachingDisplay(in: scroll.bounds))
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
          scroll.cacheDisplay(in: scroll.bounds, to: rep)
        }
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: url.appendingPathComponent(name))
      }

      let collapsed = try SpikeMacHarness()
      collapsed.embed()
      try render(collapsed, height: 260, to: "mac-embed-collapsed.png")

      let expanded = try SpikeMacHarness()
      expanded.embed()
      expanded.editor.spikeSetExpanded(true, forBlockStartingAt: expanded.note.location)
      try render(expanded, height: 260, to: "mac-embed-expanded.png")

      let zoomed = try SpikeMacHarness(scale: 2)
      zoomed.embed()
      try render(zoomed, height: 480, to: "mac-embed-zoom2x.png")
    }
  }
#endif
