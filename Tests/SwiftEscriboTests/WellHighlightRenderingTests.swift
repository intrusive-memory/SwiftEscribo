#if os(macOS)
  import AppKit
  import EscriboCore
  import Testing

  @testable import SwiftEscribo

  /// The spoken-word highlight as something **on screen**, not as attribute bookkeeping.
  ///
  /// Escribir 1.1.0 rc.1 shipped the highlight as a `.backgroundColor` rendering attribute.
  /// Every attribute-level test passed, and no word ever lit up: a layer-backed TextKit 2
  /// `NSTextView` does not paint rendering-attribute backgrounds on screen (it does in a
  /// forced `draw(_:)`, which is what `cacheDisplay` exercises — so a pixel test alone would
  /// have passed too). These tests therefore pin the thing that fixes it: the highlight is a
  /// ``WellHighlightView`` in the text view's hierarchy, placed exactly where TextKit lays
  /// the word's glyphs, there is no rendering attribute at all, and it follows a relayout.
  @MainActor
  @Suite("Well highlight — a view over the glyphs")
  struct WellHighlightRenderingTests {

    /// Wide enough that nothing wraps.
    private static let viewSize = NSSize(width: 720, height: 240)

    /// An editor in a window with a real frame, laid out once.
    private func makeEditor(language: Language, text: String) -> EscriboTextView {
      let theme: EscriboTheme = language == .fountain ? .fountainLight : .markdownLight
      let editor = EscriboTextView(language: language, theme: theme)
      editor.scrollView.frame = NSRect(origin: .zero, size: Self.viewSize)
      editor.textView.frame = NSRect(origin: .zero, size: Self.viewSize)
      let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: Self.viewSize), styleMask: [.borderless],
        backing: .buffered, defer: false)
      window.contentView = editor.scrollView
      _ = editor.applyExternalText(text)
      editor.coordinator.restyleEverything()
      editor.textView.layoutSubtreeIfNeeded()
      return editor
    }

    /// Where TextKit lays the glyphs of `range`, in text-view points — the independent
    /// measurement the highlight is compared against.
    private func glyphFrame(_ editor: EscriboTextView, _ range: NSRange) throws -> CGRect {
      let manager = try #require(editor.textView.textLayoutManager)
      let span = try #require(WellHighlight.textRange(for: range, in: manager))
      manager.ensureLayout(for: span)
      var union = CGRect.null
      manager.enumerateTextSegments(in: span, type: .standard, options: []) { _, frame, _, _ in
        union = union.union(frame)
        return true
      }
      let origin = editor.textView.textContainerOrigin
      return union.offsetBy(dx: origin.x, dy: origin.y)
    }

    private func highlightViews(_ editor: EscriboTextView) -> [WellHighlightView] {
      editor.textView.subviews.compactMap { $0 as? WellHighlightView }
    }

    private func renderingAttributeRuns(_ editor: EscriboTextView) throws -> Int {
      let manager = try #require(editor.textView.textLayoutManager)
      var runs = 0
      manager.enumerateRenderingAttributes(
        from: manager.documentRange.location, reverse: false
      ) { _, attributes, _ in
        if attributes[.backgroundColor] != nil { runs += 1 }
        return true
      }
      return runs
    }

    /// The bounding box, in points, of accent-tinted pixels **inside the text area** of a
    /// forced draw, or `nil`. The lane is excluded because the span bar and button live
    /// there and are accent too.
    private func tintedBounds(_ editor: EscriboTextView) -> CGRect? {
      let view = editor.textView
      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
      view.cacheDisplay(in: view.bounds, to: rep)
      let scale = CGFloat(rep.pixelsWide) / rep.size.width
      let textLeft = Int((view.textContainerOrigin.x + 2) * scale)
      var minX = Int.max
      var minY = Int.max
      var maxX = -1
      var maxY = -1
      for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
        for x in stride(from: textLeft, to: rep.pixelsWide, by: 2) {
          guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
            color.blueComponent > color.redComponent + 0.1
          else { continue }
          minX = min(minX, x)
          maxX = max(maxX, x)
          minY = min(minY, y)
          maxY = max(maxY, y)
        }
      }
      guard maxX >= 0 else { return nil }
      return CGRect(
        x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
        width: CGFloat(maxX - minX + 2) / scale, height: CGFloat(maxY - minY + 2) / scale)
    }

    private func firstBlock(_ editor: EscriboTextView, kind: BlockKind) throws -> EscriboBlock {
      try #require(editor.coordinator.documentBlocks.first { $0.kind == kind })
    }

    private func expectCovers(_ frame: CGRect, _ glyphs: CGRect, _ label: String) {
      #expect(abs(frame.minX - glyphs.minX) <= 1, "\(label) left: \(frame) vs \(glyphs)")
      #expect(abs(frame.maxX - glyphs.maxX) <= 1, "\(label) right: \(frame) vs \(glyphs)")
      #expect(abs(frame.midY - glyphs.midY) <= 1, "\(label) line: \(frame) vs \(glyphs)")
    }

    @Test("A Markdown word's highlight is one view framed on its glyphs, and no attribute")
    func markdownWordIsAViewOverItsGlyphs() throws {
      let text = "The keeper's ledger began with a lie.\n\nThere was a great deal to report."
      let editor = makeEditor(language: .markdown, text: text)
      let word = (text as NSString).range(of: "ledger began")
      let block = try firstBlock(editor, kind: .paragraph)
      #expect(highlightViews(editor).isEmpty)
      #expect(tintedBounds(editor) == nil)

      editor.applyWell(
        EscriboWell(activeBlock: block.id, progress: 0.3, spokenRange: word),
        horizontalSizeClass: .regular)

      let view = try #require(highlightViews(editor).first)
      #expect(highlightViews(editor).count == 1)
      let glyphs = try glyphFrame(editor, word)
      expectCovers(view.frame, glyphs, "view")
      #expect(view.rects.count == 1, "one line, one segment")
      try #expect(renderingAttributeRuns(editor) == 0, "no rendering attribute is involved")
      let painted = try #require(tintedBounds(editor), "the tint must be drawn")
      expectCovers(painted, glyphs, "pixels")

      editor.applyWell(
        EscriboWell(activeBlock: block.id, progress: 0.6, spokenRange: nil),
        horizontalSizeClass: .regular)
      #expect(highlightViews(editor).isEmpty)
      #expect(tintedBounds(editor) == nil)
    }

    @Test("A Fountain dialogue word's highlight sits on the indented glyphs, not in the lane")
    func fountainDialogueWordSitsOnItsIndentedGlyphs() throws {
      let text = "INT. OFFICE - NIGHT\n\nDANNY\nThe studio called again.\n"
      let editor = makeEditor(language: .fountain, text: text)
      let word = (text as NSString).range(of: "called")
      let speech = try firstBlock(editor, kind: .speech)

      editor.applyWell(
        EscriboWell(activeBlock: speech.id, progress: 0.3, spokenRange: word),
        horizontalSizeClass: .regular)

      let view = try #require(highlightViews(editor).first)
      let glyphs = try glyphFrame(editor, word)
      expectCovers(view.frame, glyphs, "view")
      #expect(
        view.frame.minX > editor.textView.textContainerOrigin.x + 100,
        "dialogue is indented well past the lane: \(view.frame)")
      let painted = try #require(tintedBounds(editor))
      expectCovers(painted, glyphs, "pixels")
    }

    @Test("Moving to the next word moves the same view; the old word is not left lit")
    func nextWordMovesTheView() throws {
      let text = "Rain streaks the windows of a cramped office."
      let editor = makeEditor(language: .markdown, text: text)
      let block = try firstBlock(editor, kind: .paragraph)
      let first = (text as NSString).range(of: "streaks")
      let second = (text as NSString).range(of: "cramped")

      editor.applyWell(
        EscriboWell(activeBlock: block.id, progress: 0.2, spokenRange: first),
        horizontalSizeClass: .regular)
      let view = try #require(highlightViews(editor).first)
      editor.applyWell(
        EscriboWell(activeBlock: block.id, progress: 0.7, spokenRange: second),
        horizontalSizeClass: .regular)

      #expect(highlightViews(editor).count == 1)
      #expect(highlightViews(editor).first === view)
      expectCovers(view.frame, try glyphFrame(editor, second), "second word")
      let painted = try #require(tintedBounds(editor))
      expectCovers(painted, try glyphFrame(editor, second), "pixels")
    }

    @Test("After the view resizes, the highlight is re-placed where the glyphs moved")
    func highlightFollowsARelayout() async throws {
      let text = "Rain streaks the windows of a cramped office. A single desk lamp. Marisol."
      let editor = makeEditor(language: .markdown, text: text)
      let block = try firstBlock(editor, kind: .paragraph)
      let word = (text as NSString).range(of: "Marisol")

      editor.applyWell(
        EscriboWell(activeBlock: block.id, progress: 0.9, spokenRange: word),
        horizontalSizeClass: .regular)
      let view = try #require(highlightViews(editor).first)
      let before = view.frame

      // Halve the width so the paragraph wraps and the last word drops to a new line.
      let narrow = NSSize(width: 360, height: Self.viewSize.height)
      editor.scrollView.window?.setContentSize(narrow)
      editor.scrollView.frame = NSRect(origin: .zero, size: narrow)
      editor.textView.frame = NSRect(origin: .zero, size: narrow)
      editor.textView.layoutSubtreeIfNeeded()
      editor.wellOverlay.layoutDidChange()
      for _ in 0..<50 where view.frame == before { await Task.yield() }

      let glyphs = try glyphFrame(editor, word)
      #expect(glyphs.minY > before.minY, "the fixture must actually wrap: \(glyphs)")
      expectCovers(view.frame, glyphs, "after relayout")
    }
  }
#endif
