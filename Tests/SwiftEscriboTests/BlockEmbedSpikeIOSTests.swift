#if os(iOS)
  import EscriboCore
  import Foundation
  import Testing
  import UIKit

  @testable import SwiftEscribo

  // SPIKE — throwaway tests for the atomic block-embed experiment (iOS column).

  /// One laid-out paragraph: its UTF-16 offset, frame, and fragment class.
  struct SpikeIOSLaidOutParagraph {
    var offset: Int
    var frame: CGRect
    var fragment: NSTextLayoutFragment
  }

  @MainActor
  struct SpikeIOSHarness {
    let editor: EscriboTextView
    let note: NSRange

    static let content = SpikeEmbedContent(
      symbolName: "note.text", title: "Note", subtitle: "First line of the note",
      badge: "3 lines", accessibilityLabel: "Note", accessibilityValue: "First line of the note")

    init(mechanism: SpikeCollapseMechanism = .fragmentFrameOverride, scale: Double = 1) throws {
      let editor = EscriboTextView(language: .fountain, theme: .fountainLight)
      editor.textView.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
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
    func layout() -> [SpikeIOSLaidOutParagraph] {
      guard let tlm = editor.textView.textLayoutManager,
        let content = tlm.textContentManager
      else { return [] }
      tlm.ensureLayout(for: tlm.documentRange)
      var result: [SpikeIOSLaidOutParagraph] = []
      tlm.enumerateTextLayoutFragments(from: tlm.documentRange.location, options: [.ensuresLayout]) {
        fragment in
        let offset = content.offset(
          from: content.documentRange.location, to: fragment.rangeInElement.location)
        result.append(
          SpikeIOSLaidOutParagraph(offset: offset, frame: fragment.layoutFragmentFrame, fragment: fragment))
        return true
      }
      return result
    }

    func noteParagraphs(_ laid: [SpikeIOSLaidOutParagraph]) -> [SpikeIOSLaidOutParagraph] {
      laid.filter { $0.offset >= note.location && $0.offset < NSMaxRange(note) }
    }

    /// Total vertical extent the note's paragraphs occupy (top of first to bottom of last).
    func noteExtent(_ laid: [SpikeIOSLaidOutParagraph]) -> CGFloat {
      let paras = noteParagraphs(laid)
      guard let first = paras.first, let last = paras.last else { return 0 }
      return last.frame.maxY - first.frame.minY
    }
  }

  @MainActor
  @Suite("Block embed spike — iOS draw", .serialized, .timeLimit(.minutes(2)))
  struct BlockEmbedSpikeIOSTests {

    // MARK: - Row 1: draw

    @Test("row 1: the embed draws as one fixed-height custom row; the rest lays out normally")
    func row1FixedHeightRow() throws {
      let h = try SpikeIOSHarness()
      // Unlike NSTextView, UITextView already holds the layout-manager delegate slot (its own
      // `_UITextKit2LayoutController`); the spike chains to it rather than replacing it.
      let displaced = h.editor.spikeEmbeds.displacedDelegates
      print("SPIKE iOS displaced delegates: \(displaced)")
      #expect(displaced.allSatisfy { $0.hasPrefix("layoutManager:") })
      #expect(h.editor.spikeEmbeds.forwardedLayoutDelegate != nil || displaced.isEmpty)
      let before = h.layout()
      h.embed()
      let after = h.layout()
      let rowHeight = h.editor.spikeEmbeds.rowHeight

      #expect(before.count == after.count)
      let paras = h.noteParagraphs(after)
      let first = try #require(paras.first)
      let row = try #require(first.fragment as? SpikeEmbedRowFragment)
      #expect(abs(first.frame.height - rowHeight) <= 0.5)
      #expect(row.content == SpikeIOSHarness.content)
      // At the paragraph's leading indent, read from the real storage.
      let style = h.editor.textView.textStorage.attribute(
        .paragraphStyle, at: h.note.location, effectiveRange: nil) as? NSParagraphStyle
      #expect(row.indent == (style?.firstLineHeadIndent ?? 0))

      // Before the block: untouched. After: own heights kept.
      for (b, a) in zip(before, after) where a.offset < h.note.location {
        #expect(a.frame == b.frame)
        // Whatever UIKit's own delegate vends, unchanged.
        #expect(type(of: a.fragment) == type(of: b.fragment))
        #expect(!(a.fragment is SpikeEmbedFragment))
      }
      for (b, a) in zip(before, after) where a.offset >= NSMaxRange(h.note) {
        #expect(abs(a.frame.height - b.frame.height) <= 0.5)
        #expect(type(of: a.fragment) == type(of: b.fragment))
        #expect(!(a.fragment is SpikeEmbedFragment))
      }
      // Contiguous: every fragment starts where the previous one ends.
      for (prev, next) in zip(after, after.dropFirst()) {
        #expect(abs(next.frame.minY - prev.frame.maxY) <= 0.5, "gap before offset \(next.offset)")
      }

      // The row actually draws (symbol, two lines, badge) and puts pixels down.
      let side = CGSize(width: row.rowWidth, height: rowHeight)
      let image = UIGraphicsImageRenderer(size: side).image { ctx in
        row.draw(at: .zero, in: ctx.cgContext)
      }
      #expect(row.drawCount >= 1)
      #expect(Self.hasInk(image))

      // And through UITextView's own rendering, hosted in a window.
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
      window.addSubview(h.editor.textView)
      window.isHidden = false
      defer { window.isHidden = true }
      let drawsBefore = row.drawCount
      h.editor.textView.layoutIfNeeded()
      _ = UIGraphicsImageRenderer(bounds: h.editor.textView.bounds).image { ctx in
        h.editor.textView.layer.render(in: ctx.cgContext)
      }
      let live = try #require(h.noteParagraphs(h.layout()).first?.fragment as? SpikeEmbedRowFragment)
      print("SPIKE iOS plain fragment class: \(type(of: after[0].fragment))")
      print("SPIKE iOS row 1: view-render draw calls: \(live === row ? row.drawCount - drawsBefore : live.drawCount)")
    }

    @Test("row 1: zoom (pointSizeScale 2) scales the row, and it survives the coordinator's restyle")
    func row1ZoomScalesRow() throws {
      let h = try SpikeIOSHarness()
      h.embed()
      let baseline = try #require(h.noteParagraphs(h.layout()).first)
      #expect(baseline.fragment is SpikeEmbedRowFragment)

      // Zoom the way the package does: new metrics, then the coordinator rewrites every
      // attribute (paragraph styles included) into storage.
      h.editor.coordinator.styler.environment.metrics = FontMetrics(pointSizeScale: 2)
      h.editor.coordinator.restyleEverything()

      let zoomed = h.layout()
      let first = try #require(h.noteParagraphs(zoomed).first)
      #expect(first.fragment is SpikeEmbedRowFragment)
      #expect(first.frame.height > 1.5 * baseline.frame.height)
      #expect(abs(h.noteExtent(zoomed) - first.frame.height) <= 0.5)

      // A harness built at 2× from the start agrees.
      let h2 = try SpikeIOSHarness(scale: 2)
      h2.embed()
      let fresh = try #require(h2.noteParagraphs(h2.layout()).first)
      #expect(abs(fresh.frame.height - first.frame.height) <= 0.5)
    }

    // MARK: - Row 2: storage untouched

    @Test("row 2: textStorage is byte-identical with the embed; find, copy-all and word count see the source")
    func row2StorageUntouched() throws {
      let h = try SpikeIOSHarness()
      let storage = h.editor.textView.textStorage
      let original = storage.string
      let originalData = Data(original.utf8)
      let originalAttrs = NSAttributedString(attributedString: storage)
      let restyles = h.editor.coordinator.restyleCount

      h.embed()
      _ = h.layout()

      #expect(Data(storage.string.utf8) == originalData)
      #expect(storage.string == BlockEmbedSpikeFixture.text)
      #expect(h.editor.textView.text == BlockEmbedSpikeFixture.text)
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

      // Copy-all: what UITextView's `copy(_:)` writes is the text it vends for the selected
      // range. `copy(_:)` always targets the system general pasteboard (it cannot be
      // redirected to a named one), and reading `UIPasteboard.general` from the simulator test
      // host blocks indefinitely on pasteboard services, so the test asserts the copy path's
      // source — the selected range's plain and attributed text — instead of the pasteboard.
      let tv = h.editor.textView
      tv.selectAll(nil)
      let all = try #require(tv.selectedTextRange)
      #expect(tv.text(in: all) == BlockEmbedSpikeFixture.text)
      #expect(tv.attributedText.attributedSubstring(from: tv.selectedRange).string == BlockEmbedSpikeFixture.text)

      // And after a full restyle (the coordinator writes paragraph attributes), still so.
      h.editor.coordinator.restyleEverything()
      #expect(storage.string == BlockEmbedSpikeFixture.text)
      #expect(h.noteParagraphs(h.layout()).first?.fragment is SpikeEmbedRowFragment)
    }

    // MARK: - Row 10: multi-line block

    @Test("row 10: the three note paragraphs (three layout fragments) together occupy exactly one row")
    func row10MultiLineCollapse() throws {
      let h = try SpikeIOSHarness()
      let unembedded = h.noteExtent(h.layout())
      h.editor.textView.layoutIfNeeded()
      let usedBefore = h.editor.textView.textLayoutManager?.usageBoundsForTextContainer.height ?? 0
      h.embed()
      let laid = h.layout()
      let paras = h.noteParagraphs(laid)
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

      // The layout manager's used height (what UITextView sizes its content from) shrinks by
      // what the block gave up.
      h.editor.textView.layoutIfNeeded()
      let usedAfter = h.editor.textView.textLayoutManager?.usageBoundsForTextContainer.height ?? 0
      #expect(abs((usedBefore - usedAfter) - (unembedded - rowHeight)) <= 0.5)
    }

    @Test("row 10: mechanism comparison — only the frame override collapses N fragments without a storage edit")
    func row10MechanismComparison() throws {
      var extents: [SpikeCollapseMechanism: CGFloat] = [:]
      var rowHeight: CGFloat = 0
      for mechanism in SpikeCollapseMechanism.allCases {
        let h = try SpikeIOSHarness(mechanism: mechanism)
        // The realistic case: the document is already laid out when the host embeds.
        _ = h.layout()
        h.embed()
        extents[mechanism] = h.noteExtent(h.layout())
        rowHeight = h.editor.spikeEmbeds.rowHeight
      }
      print("SPIKE iOS row 10 extents: \(extents), rowHeight \(rowHeight)")
      // Draw-only keeps three line heights.
      #expect(abs((extents[.fragmentDrawOnly] ?? 0) - rowHeight) > 0.5)
      // The frame override collapses to one row.
      #expect(abs((extents[.fragmentFrameOverride] ?? 0) - rowHeight) <= 0.5)
      // The content-storage paragraph is never re-vended without a storage edit.
      #expect(abs((extents[.contentStorageParagraph] ?? 0) - rowHeight) > 0.5)
    }

    // MARK: - Helpers

    /// Whether any pixel in `image` is not fully transparent.
    static func hasInk(_ image: UIImage) -> Bool {
      guard let cg = image.cgImage else { return false }
      let width = cg.width
      let height = cg.height
      var pixels = [UInt8](repeating: 0, count: width * height * 4)
      guard
        let ctx = CGContext(
          data: &pixels, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
      return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] != 0 }
    }
  }
#endif
