#if os(macOS) || os(iOS)
  import EscriboCore
  import Foundation
  import Testing

  @testable import SwiftEscribo

  #if os(macOS)
    import AppKit
  #else
    import UIKit
  #endif

  /// A document with one three-line note between ordinary paragraphs.
  enum EmbedLayoutFixture {
    static let noteLines = "[[First line of the note\nsecond line\nthird line]]\n"
    static let text =
      "INT. HOUSE - DAY\n\nBob waits by the door.\n\n" + noteLines + "\nJane enters.\n"

    static let embed = EscriboEmbed(
      symbolName: "note.text", title: "Note", subtitle: "First line of the note",
      badge: .init(
        symbolName: "checkmark.circle", word: "valid",
        tint: EscriboColor(red: 0, green: 0.6, blue: 0)))
  }

  /// Answers with ``EmbedLayoutFixture/embed`` for every note block it has not been told to
  /// refuse.
  final class NoteEmbedProvider: EscriboEmbedProvider {
    var refused: Set<Int> = []
    var answersNothing = false

    /// A note whose text contains this is refused.
    var refusingMarker = "EDIT"

    func embed(for block: EscriboBlock, in text: String) -> EscriboEmbed? {
      guard !answersNothing, block.kind == .note, !refused.contains(block.range.lowerBound),
        !text.contains(refusingMarker)
      else { return nil }
      return EmbedLayoutFixture.embed
    }
  }

  /// One laid-out paragraph: its UTF-16 offset, frame and fragment.
  struct LaidOutParagraph {
    var offset: Int
    var frame: CGRect
    var fragment: NSTextLayoutFragment
  }

  @MainActor
  struct EmbedLayoutHarness {
    let editor: EscriboTextView
    let note: Range<Int>
    let provider = NoteEmbedProvider()

    init(scale: Double = 1) throws {
      let editor = EscriboTextView(language: .fountain, theme: .fountainLight)
      #if os(macOS)
        editor.scrollView.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
        editor.textView.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
      #else
        editor.textView.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
      #endif
      if scale != 1 {
        editor.coordinator.styler.environment.metrics = FontMetrics(pointSizeScale: scale)
      }
      _ = editor.applyExternalText(EmbedLayoutFixture.text)
      editor.coordinator.restyleEverything()
      let block = try #require(editor.coordinator.documentBlocks.first { $0.kind == .note })
      self.editor = editor
      self.note = block.range
    }

    func embed() {
      editor.coordinator.setEmbedProvider(provider)
    }

    var layoutManager: NSTextLayoutManager? { editor.textView.textLayoutManager }

    /// Every paragraph's layout fragment, with layout ensured over the whole document.
    func layout() -> [LaidOutParagraph] {
      guard let layoutManager, let content = layoutManager.textContentManager else { return [] }
      layoutManager.ensureLayout(for: layoutManager.documentRange)
      var result: [LaidOutParagraph] = []
      layoutManager.enumerateTextLayoutFragments(
        from: layoutManager.documentRange.location, options: [.ensuresLayout]
      ) { fragment in
        let offset = content.offset(
          from: content.documentRange.location, to: fragment.rangeInElement.location)
        result.append(
          LaidOutParagraph(offset: offset, frame: fragment.layoutFragmentFrame, fragment: fragment))
        return true
      }
      return result
    }

    func noteParagraphs(_ laid: [LaidOutParagraph]) -> [LaidOutParagraph] {
      laid.filter { note.contains($0.offset) }
    }

    /// Top of the note's first paragraph to the bottom of its last.
    func noteExtent(_ laid: [LaidOutParagraph]) -> CGFloat {
      let paragraphs = noteParagraphs(laid)
      guard let first = paragraphs.first, let last = paragraphs.last else { return 0 }
      return last.frame.maxY - first.frame.minY
    }

    /// Two lines of the theme's base font at its declared size, times `scale` — measured
    /// here independently of the controller.
    static func expectedRowHeight(scale: Double) -> CGFloat {
      let theme = EscriboTheme.fountainLight
      let spec = FontSpec(
        family: theme.base.family ?? .monospaced, traits: theme.base.traits,
        pointSize: theme.baseFontSize)
      return CGFloat(2 * FontResolver.geometry(of: FontResolver.font(for: spec)).lineHeight * scale)
    }

    var storage: NSTextStorage { editor.documentStorage }
  }

  /// REQUIREMENTS.md § 1.2: embed rows are drawn by layout fragments, never by editing the
  /// text storage.
  @MainActor
  @Suite("Embed layout: rows, collapse, zoom, invalidation", .serialized)
  struct EmbedLayoutTests {

    @Test("The note draws as one row two lines tall, at its indent, within the text column")
    func rowHeightAndFrame() throws {
      let harness = try EmbedLayoutHarness()
      let before = harness.layout()
      harness.embed()
      let after = harness.layout()
      let expected = EmbedLayoutHarness.expectedRowHeight(scale: 1)
      let controller = try #require(harness.editor.embedLayout)

      #expect(before.count == after.count)
      #expect(abs(controller.rowHeight - expected) < 0.001)
      let first = try #require(harness.noteParagraphs(after).first)
      let row = try #require(first.fragment as? EmbedRowFragment)
      #expect(abs(first.frame.height - expected) < 0.001)
      #expect(row.embed == EmbedLayoutFixture.embed)

      // At the block's indent, as the coordinator wrote it into storage.
      let style =
        harness.storage.attribute(
          .paragraphStyle, at: harness.note.lowerBound, effectiveRange: nil) as? NSParagraphStyle
      #expect(row.rowRect.minX == (style?.firstLineHeadIndent ?? 0))
      // No wider than the text column.
      let container = try #require(harness.layoutManager?.textContainer)
      #expect(row.rowRect.maxX <= container.size.width - 2 * container.lineFragmentPadding + 0.001)
      #expect(row.rowRect.width > 0)
      #expect(row.colors == EmbedRowColors(theme: .fountainLight))

      // Paragraphs before the block are untouched; after it, their own heights are kept.
      for (old, new) in zip(before, after) where new.offset < harness.note.lowerBound {
        #expect(new.frame == old.frame)
        #expect(!(new.fragment is EmbedLayoutFragment))
      }
      for (old, new) in zip(before, after) where new.offset >= harness.note.upperBound {
        #expect(abs(new.frame.height - old.frame.height) <= 0.5)
        #expect(!(new.fragment is EmbedLayoutFragment))
      }
      // Contiguous: every fragment starts where the previous one ends.
      for (previous, next) in zip(after, after.dropFirst()) {
        #expect(abs(next.frame.minY - previous.frame.maxY) <= 0.5, "gap before \(next.offset)")
      }

      // The query the input code uses, and the row's rectangle in the text view.
      let hit = try #require(
        controller.embeddedBlock(containingUTF16Offset: harness.note.lowerBound + 3))
      #expect(hit.block.range == harness.note)
      #expect(controller.embeddedBlock(containingUTF16Offset: harness.note.upperBound) == nil)
      let rect = try #require(controller.rowRect(for: hit))
      #expect(abs(rect.height - expected) < 0.001)
      #expect(abs(rect.width - row.rowRect.width) < 0.001)
    }

    @Test("Zoom 2x doubles the row, both after a restyle and when built zoomed")
    func zoomScalesRow() throws {
      let harness = try EmbedLayoutHarness()
      harness.embed()
      let baseline = try #require(harness.noteParagraphs(harness.layout()).first)
      #expect(baseline.fragment is EmbedRowFragment)

      harness.editor.coordinator.styler.environment.metrics = FontMetrics(pointSizeScale: 2)
      harness.editor.coordinator.restyleEverything()
      let zoomed = harness.layout()
      let first = try #require(harness.noteParagraphs(zoomed).first)
      #expect(first.fragment is EmbedRowFragment)
      let expected = EmbedLayoutHarness.expectedRowHeight(scale: 2)
      #expect(abs(first.frame.height - expected) < 0.001)
      #expect(abs(first.frame.height - 2 * baseline.frame.height) < 0.001)
      #expect(abs(harness.noteExtent(zoomed) - expected) <= 0.5)

      let fresh = try EmbedLayoutHarness(scale: 2)
      fresh.embed()
      let freshFirst = try #require(fresh.noteParagraphs(fresh.layout()).first)
      #expect(abs(freshFirst.frame.height - expected) < 0.001)
    }

    @Test("The text storage is byte- and attribute-identical with embeds, and never restyled")
    func storageUntouched() throws {
      let harness = try EmbedLayoutHarness()
      let storage = harness.storage
      let originalData = Data(storage.string.utf8)
      let originalAttributes = NSAttributedString(attributedString: storage)
      let restyles = harness.editor.coordinator.restyleCount

      harness.embed()
      _ = harness.layout()
      #expect(harness.editor.embedLayout != nil)
      #expect(Data(storage.string.utf8) == originalData)
      #expect(storage.string == EmbedLayoutFixture.text)
      #expect(storage.isEqual(to: originalAttributes))
      #expect(harness.editor.coordinator.restyleCount == restyles)

      // Re-vending on invalidation does not write either.
      harness.editor.coordinator.invalidateEmbeds()
      _ = harness.layout()
      #expect(storage.isEqual(to: originalAttributes))
      #expect(harness.editor.coordinator.restyleCount == restyles)
    }

    @Test("A three-paragraph note collapses into exactly one row")
    func paragraphsCollapse() throws {
      let harness = try EmbedLayoutHarness()
      let unembedded = harness.noteExtent(harness.layout())
      harness.embed()
      let laid = harness.layout()
      let paragraphs = harness.noteParagraphs(laid)
      let expected = EmbedLayoutHarness.expectedRowHeight(scale: 1)

      #expect(paragraphs.count == 3)
      #expect(paragraphs.first?.fragment is EmbedRowFragment)
      for paragraph in paragraphs.dropFirst() {
        #expect(paragraph.fragment is EmbedCollapsedFragment)
        #expect(paragraph.frame.height == 0)
      }
      #expect(abs(harness.noteExtent(laid) - expected) <= 0.5)
      // Not vacuous: unembedded, the note is three lines, not one row.
      #expect(abs(unembedded - expected) > 0.5)

      let next = try #require(laid.first { $0.offset == harness.note.upperBound })
      let first = try #require(paragraphs.first)
      #expect(abs(next.frame.minY - (first.frame.minY + expected)) <= 0.5)
    }

    @Test("A provider that answers nil after invalidateEmbeds() gets its text drawn again")
    func invalidateRestoresText() throws {
      let harness = try EmbedLayoutHarness()
      let before = harness.layout()
      let unembedded = harness.noteExtent(before)
      harness.embed()
      #expect(harness.noteParagraphs(harness.layout()).first?.fragment is EmbedRowFragment)

      // Edit as Text: the host's provider stops answering for this block.
      harness.provider.refused = [harness.note.lowerBound]
      harness.editor.coordinator.invalidateEmbeds()
      let after = harness.layout()
      #expect(harness.editor.coordinator.embeddedBlocks.isEmpty)
      for paragraph in harness.noteParagraphs(after) {
        #expect(!(paragraph.fragment is EmbedLayoutFragment))
      }
      #expect(abs(harness.noteExtent(after) - unembedded) <= 0.5)
      #expect(after.map(\.frame) == before.map(\.frame))

      // And back.
      let vended = try #require(harness.editor.embedLayout).rowFragmentCount
      harness.provider.refused = []
      harness.editor.coordinator.invalidateEmbeds()
      #expect(harness.noteParagraphs(harness.layout()).first?.fragment is EmbedRowFragment)
      #expect(try #require(harness.editor.embedLayout).rowFragmentCount > vended)
    }

    @Test("An edit that changes the cache re-vends after the storage's own edit processing")
    func editInsideProcessEditingDefersRevend() async throws {
      let harness = try EmbedLayoutHarness()
      harness.embed()
      _ = harness.layout()
      let storage = harness.storage

      // Typing the provider's refusal marker into the note: the edit re-asks the block and
      // its embed goes. The change hook fires from inside the storage's edit processing.
      let inside = (storage.string as NSString).range(of: "second").location
      storage.replaceCharacters(in: NSRange(location: inside, length: 0), with: "EDIT")
      #expect(harness.editor.coordinator.embeddedBlocks.isEmpty)
      #expect(harness.editor.embedLayout?.deferredRevendCount == 1)
      try await Task.sleep(for: .milliseconds(50))
      for paragraph in harness.layout() {
        #expect(!(paragraph.fragment is EmbedLayoutFragment))
      }

      // Taken out again: the embed returns as a row.
      storage.replaceCharacters(in: NSRange(location: inside, length: 4), with: "")
      #expect(harness.editor.coordinator.embeddedBlocks.count == 1)
      try await Task.sleep(for: .milliseconds(50))
      #expect(harness.noteParagraphs(harness.layout()).first?.fragment is EmbedRowFragment)
      #expect(storage.string == EmbedLayoutFixture.text)
    }

    @Test("No provider, or one that never answers: nothing installed, geometry unchanged")
    func noProviderInstallsNothing() throws {
      let reference = try EmbedLayoutHarness()
      let referenceFrames = reference.layout().map(\.frame)

      let harness = try EmbedLayoutHarness()
      let stockDelegate = harness.layoutManager?.delegate
      #expect(harness.editor.embedLayout == nil)
      #if os(macOS)
        // AppKit leaves the slot empty, and the editor leaves it so.
        #expect(stockDelegate == nil)
      #endif
      #expect(harness.layout().map(\.frame) == referenceFrames)

      // A provider that answers nil everywhere installs nothing either.
      harness.provider.answersNothing = true
      harness.embed()
      #expect(harness.editor.embedLayout == nil)
      #expect((harness.layoutManager?.delegate as AnyObject?) === (stockDelegate as AnyObject?))
      #expect(harness.layout().map(\.frame) == referenceFrames)
    }

    @Test("Installing takes the delegate slot: directly on macOS, through the chain on iOS")
    func delegateInstallation() throws {
      let harness = try EmbedLayoutHarness()
      harness.embed()
      let controller = try #require(harness.editor.embedLayout)
      #if os(macOS)
        #expect((harness.layoutManager?.delegate as AnyObject?) === controller)
      #else
        let chain = try #require(controller.delegateChain)
        #expect((harness.layoutManager?.delegate as AnyObject?) === chain)
      #endif
    }

    @Test("The row draws: symbol, title, subtitle and badge paint pixels")
    func rowDraws() throws {
      let harness = try EmbedLayoutHarness()
      harness.embed()
      let first = try #require(harness.noteParagraphs(harness.layout()).first)
      let row = try #require(first.fragment as? EmbedRowFragment)

      let width = Int(ceil(row.renderingSurfaceBounds.width))
      let height = Int(ceil(row.rowHeight))
      let context = try #require(
        CGContext(
          data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      row.draw(at: .zero, in: context)
      #expect(row.drawCount == 1)
      let data = try #require(context.data)
      let bytes = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * height)
      var painted = 0
      for y in 0..<height {
        for x in 0..<width where bytes[y * context.bytesPerRow + x * 4 + 3] != 0 {
          painted += 1
        }
      }
      #expect(painted > width * height / 4)
    }

    @Test("Subtitle runs: plain in secondary, de-emphasized fainter, one truncating line")
    func subtitleRunColours() throws {
      let colors = EmbedRowColors(theme: .fountainLight)
      #expect(colors.deEmphasized != colors.secondary)
      let foreground = EscriboTheme.fountainLight.base.foreground ?? .black
      #expect(colors.deEmphasized == foreground.withAlphaMultiplied(by: 0.35))

      let runs: [EscriboEmbed.SubtitleRun] = [
        .init("MS · "), .init("35mm", isDeEmphasized: true), .init(" · dolly"),
      ]
      let embed = EscriboEmbed(symbolName: "film", title: "Shot", subtitleRuns: runs)
      let renderer = EmbedRowRenderer(
        embed: embed, colors: colors, fontSpec: FontSpec(family: .monospaced, pointSize: 12),
        scale: 1)
      let line = renderer.subtitle(fontSize: 10)
      #expect(line.string == embed.subtitle)
      var location = 0
      for run in runs {
        let length = (run.text as NSString).length
        var effective = NSRange()
        let color =
          line.attribute(.foregroundColor, at: location, effectiveRange: &effective)
          as? PlatformColor
        let expected = run.isDeEmphasized ? colors.deEmphasized : colors.secondary
        #expect(color == expected.platformColor, "run \(run.text)")
        #expect(effective == NSRange(location: location, length: length))
        let style =
          line.attribute(.paragraphStyle, at: location, effectiveRange: nil)
          as? NSParagraphStyle
        #expect(style?.lineBreakMode == .byTruncatingTail)
        location += length
      }
    }

    @Test("A de-emphasized subtitle draws different pixels from the same plain subtitle")
    func deEmphasizedRunsDraw() throws {
      func pixels(_ embed: EscriboEmbed) throws -> [UInt8] {
        let width = 400
        let height = 48
        let context = try #require(
          CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        EmbedRowRenderer(
          embed: embed, colors: EmbedRowColors(theme: .fountainLight),
          fontSpec: FontSpec(family: .monospaced, pointSize: 12), scale: 1
        ).draw(in: CGRect(x: 0, y: 0, width: width, height: height), context: context)
        let data = try #require(context.data)
        return Array(
          UnsafeBufferPointer(
            start: data.bindMemory(to: UInt8.self, capacity: width * height * 4),
            count: width * height * 4))
      }
      let plain = try pixels(
        EscriboEmbed(symbolName: "film", title: "Shot", subtitleRuns: [.init("inherited 35mm")]))
      let dimmed = try pixels(
        EscriboEmbed(
          symbolName: "film", title: "Shot",
          subtitleRuns: [.init("inherited 35mm", isDeEmphasized: true)]))
      let same = try pixels(
        EscriboEmbed(symbolName: "film", title: "Shot", subtitle: "inherited 35mm"))
      #expect(plain == same)
      #expect(plain != dimmed)
    }

    @Test("The state rectangle is the drawn badge capsule, else a trailing square")
    func stateRectGeometry() throws {
      let spec = FontSpec(family: .monospaced, pointSize: 12)
      let row = CGRect(x: 10, y: 20, width: 400, height: 40)
      let drawn = EmbedRowGeometry.drawnRect(forRow: row, scale: 1)
      let badged = EmbedRowGeometry(embed: EmbedLayoutFixture.embed, fontSpec: spec, scale: 1)
      let capsule = try #require(badged.badge(in: drawn)).capsule
      #expect(badged.stateRect(in: drawn) == capsule)
      #expect(capsule.maxX <= drawn.maxX && capsule.minX > badged.textLeft(in: drawn))

      var bare = badged
      bare.embed.badge = nil
      let square = bare.stateRect(in: drawn)
      #expect(square.width == square.height && square.width > 0)
      #expect(abs(square.maxX - (drawn.maxX - bare.pad)) < 0.001)
      #expect(abs(square.midY - drawn.midY) < 0.001)

      // A row too narrow for the badge draws none, so the state falls back to the square.
      let narrow = EmbedRowGeometry.drawnRect(
        forRow: CGRect(x: 0, y: 0, width: 60, height: 40), scale: 1)
      #expect(badged.badge(in: narrow) == nil)
      #expect(badged.stateRect(in: narrow).width == badged.stateRect(in: narrow).height)
    }
  }
#endif
