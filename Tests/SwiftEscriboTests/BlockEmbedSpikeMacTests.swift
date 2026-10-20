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
  }
#endif
