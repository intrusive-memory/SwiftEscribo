#if os(macOS) || os(iOS)
  import EscriboCore
  import Foundation

  #if os(macOS)
    import AppKit
  #else
    import UIKit
  #endif

  // MARK: - The layout controller

  /// Draws every embedded block as one row (REQUIREMENTS.md § 1.2), on both platforms.
  ///
  /// ## Mechanism
  ///
  /// TextKit 2 asks the text layout manager's delegate for one layout fragment per
  /// paragraph (`textLayoutManager(_:textLayoutFragmentFor:in:)`). For a paragraph inside
  /// an embedded block this vends an ``EmbedLayoutFragment`` instead of the default:
  ///
  /// - the block's **first** paragraph gets an ``EmbedRowFragment``, which claims the row's
  ///   height and draws the row;
  /// - its other paragraphs get an ``EmbedCollapsedFragment``, which claims zero height
  ///   and draws nothing.
  ///
  /// `NSTextLayoutManager` stacks each fragment directly below the previous fragment's
  /// `layoutFragmentFrame`, and both classes override that frame, so N paragraphs occupy
  /// exactly one row. A fragment that only draws differently does not collapse anything:
  /// the stacking uses the frame, not the drawing.
  ///
  /// **The text storage is never modified.** Not a character and not an attribute: the
  /// row is display-side only, so copy, find, word count and the host's binding all see
  /// the block's source.
  ///
  /// ## Driven by the coordinator's embed cache
  ///
  /// Which blocks are embeds, and with what, is read at vend time from
  /// ``EditorCoordinator/embeddedBlock(containingUTF16Offset:)``. When that cache changes
  /// the coordinator calls ``EditorCoordinator/onEmbedsChange`` with the affected ranges,
  /// and ``revend(_:)`` makes TextKit ask for those paragraphs' fragments again.
  ///
  /// ## Installation
  ///
  /// Nothing is installed until the cache first holds an embed
  /// (``EscriboTextView/installEmbedLayout()``): an editor with no provider, or whose
  /// provider never answers with an embed, keeps the text view's stock layout manager
  /// delegate and therefore today's exact geometry (§ 1.5).
  ///
  /// - **macOS** installs this object as the layout manager's delegate directly. AppKit
  ///   leaves that slot empty (RECON_REPORT.md A-35).
  /// - **iOS** cannot: `UITextView` already keeps its own delegate there. The chaining
  ///   lives in one type, ``UIKitLayoutDelegateChain``, and nowhere else.
  ///
  /// ## Queries for the input and accessibility code
  ///
  /// ``embeddedBlock(containingUTF16Offset:)`` answers "is this offset inside a drawn
  /// embed row", and ``rowRect(for:)`` gives that row's rectangle in the text view's
  /// coordinates.
  @MainActor
  final class EmbedLayoutController: NSObject {

    /// The coordinator whose embed cache this draws.
    private weak var coordinator: EditorCoordinator?

    /// The text view whose layout manager this serves.
    private weak var textView: EscriboNativeTextView?

    #if os(iOS)
      /// The delegate installed in the layout manager's slot, in front of UIKit's own.
      /// Strong here because the slot itself is weak.
      private(set) var delegateChain: UIKitLayoutDelegateChain?
    #endif

    /// How many row fragments have been vended. Lets a test prove a re-vend happened.
    private(set) var rowFragmentCount = 0

    /// How many re-vends waited for the storage's edit processing to finish.
    private(set) var deferredRevendCount = 0

    /// The nominal line height last measured, keyed by the font it was measured for.
    private var lineHeightCache: (spec: FontSpec, lineHeight: Double)?

    init(textView: EscriboNativeTextView, coordinator: EditorCoordinator) {
      self.textView = textView
      self.coordinator = coordinator
      super.init()
    }

    // MARK: - Installation

    /// Puts this controller in front of the text view's layout manager.
    func install() {
      guard let layoutManager = textView?.textLayoutManager else { return }
      #if os(macOS)
        layoutManager.delegate = self
      #else
        let vend: (NSTextLayoutManager, NSTextElement) -> NSTextLayoutFragment? = { [weak self] in
          self?.embedFragment(in: $0, for: $1)
        }
        let chain = UIKitLayoutDelegateChain(displacing: layoutManager.delegate, vend: vend)
        delegateChain = chain
        layoutManager.delegate = chain
      #endif
    }

    // MARK: - Queries

    /// The embedded block drawn as a row over `offset`, or `nil`.
    ///
    /// Start inclusive, end exclusive, like a block's range: the offset just after a
    /// block's final terminator belongs to the next block. Only blocks that fit the
    /// current storage count, so a cache one edit behind never reports a row past the end.
    func embeddedBlock(containingUTF16Offset offset: Int) -> EmbeddedBlock? {
      guard let coordinator, let hit = coordinator.embeddedBlock(containingUTF16Offset: offset),
        hit.block.range.upperBound <= storageLength
      else { return nil }
      return hit
    }

    /// The rectangle `embedded`'s row is drawn in, in the text view's coordinates, or `nil`
    /// when it is not laid out as a row.
    ///
    /// Lays out up to the block first, so the answer is right even for a row that has not
    /// been scrolled into view.
    func rowRect(for embedded: EmbeddedBlock) -> CGRect? {
      guard let textView, let layoutManager = textView.textLayoutManager,
        let contentManager = layoutManager.textContentManager,
        let location = contentManager.location(
          contentManager.documentRange.location, offsetBy: embedded.block.range.lowerBound)
      else { return nil }
      layoutManager.ensureLayout(for: NSTextRange(location: location))
      guard let fragment = layoutManager.textLayoutFragment(for: location) as? EmbedRowFragment
      else { return nil }
      let origin = Self.containerOrigin(of: textView)
      let row = fragment.rowRect
      let frame = fragment.layoutFragmentFrame
      return CGRect(
        x: frame.minX + origin.x + row.minX, y: frame.minY + origin.y + row.minY,
        width: row.width, height: row.height)
    }

    /// The row height: two lines of the theme's base font at its declared size, times the
    /// editor's zoom (`FontMetrics.pointSizeScale`).
    ///
    /// A line is the font's ascent + descent + leading — the same measure paragraph
    /// geometry converts "lines" with (``FontGeometry/lineHeight``). Paragraph metrics add
    /// no space between the lines of a paragraph, only before it, so there is nothing else
    /// to add.
    var rowHeight: CGFloat {
      guard let coordinator else { return 0 }
      let environment = coordinator.styler.environment
      let theme = environment.resolvedTheme
      let spec = Self.nominalFontSpec(of: theme)
      let lineHeight: Double
      if let cached = lineHeightCache, cached.spec == spec {
        lineHeight = cached.lineHeight
      } else {
        lineHeight = FontResolver.geometry(of: FontResolver.font(for: spec)).lineHeight
        lineHeightCache = (spec, lineHeight)
      }
      return CGFloat(2 * lineHeight * environment.metrics.pointSizeScale)
    }

    /// The font a row's height is measured in: the theme's base face at its declared size.
    static func nominalFontSpec(of theme: EscriboTheme) -> FontSpec {
      FontSpec(
        family: theme.base.family ?? .monospaced, traits: theme.base.traits,
        pointSize: theme.baseFontSize)
    }

    // MARK: - Re-vending

    /// Makes TextKit ask again for the fragments of every paragraph in `ranges`.
    ///
    /// `invalidateLayout(for:)` alone keeps the existing fragment objects, so the delegate
    /// would never be asked. A same-range edit recorded on the content storage makes the
    /// layout manager discard and re-request the paragraphs' fragments. The backing text
    /// storage is not edited, so `processEditing` never runs and the coordinator never
    /// hears of it.
    ///
    /// Called from inside the text storage's own edit processing (an edit that made an
    /// embed appear or vanish), the content storage is about to process that edit itself.
    /// A nested transaction there is not safe, so the re-vend waits for the next turn of
    /// the main run loop.
    func redraw(_ ranges: [Range<Int>]) {
      guard !ranges.isEmpty, let storage = textView?.textStorage else { return }
      if storage.editedMask.isEmpty {
        revend(ranges)
      } else {
        deferredRevendCount += 1
        DispatchQueue.main.async { [weak self] in self?.revend(ranges) }
      }
    }

    /// The body of ``redraw(_:)``: re-vends now. Ranges are clamped to the storage.
    func revend(_ ranges: [Range<Int>]) {
      guard let textView, let layoutManager = textView.textLayoutManager,
        let contentStorage = layoutManager.textContentManager as? NSTextContentStorage
      else { return }
      let length = storageLength
      let documentStart = contentStorage.documentRange.location
      var textRanges: [NSTextRange] = []
      for range in ranges {
        let lower = min(max(0, range.lowerBound), length)
        let upper = min(max(lower, range.upperBound), length)
        guard let start = contentStorage.location(documentStart, offsetBy: lower),
          let end = contentStorage.location(start, offsetBy: upper - lower),
          let textRange = NSTextRange(location: start, end: end)
        else { continue }
        textRanges.append(textRange)
      }
      guard !textRanges.isEmpty else { return }
      contentStorage.performEditingTransaction {
        for textRange in textRanges {
          contentStorage.recordEditAction(in: textRange, newTextRange: textRange)
        }
      }
      for textRange in textRanges { layoutManager.invalidateLayout(for: textRange) }
      #if os(macOS)
        textView.needsDisplay = true
      #else
        textView.setNeedsLayout()
        textView.setNeedsDisplay()
      #endif
    }

    // MARK: - Vending

    /// The fragment for `element` when it is a paragraph of an embedded block, else `nil`
    /// (the caller vends whatever it would have vended without embeds).
    func embedFragment(
      in layoutManager: NSTextLayoutManager, for element: NSTextElement
    ) -> EmbedLayoutFragment? {
      guard let coordinator, !coordinator.embeddedBlocks.isEmpty,
        let contentManager = layoutManager.textContentManager,
        let elementRange = element.elementRange
      else { return nil }
      let offset = contentManager.offset(
        from: contentManager.documentRange.location, to: elementRange.location)
      guard let hit = embeddedBlock(containingUTF16Offset: offset) else { return nil }

      let height = rowHeight
      guard offset == hit.block.range.lowerBound else {
        let collapsed = EmbedCollapsedFragment(textElement: element, range: elementRange)
        collapsed.rowHeight = height
        return collapsed
      }
      rowFragmentCount += 1
      let row = EmbedRowFragment(textElement: element, range: elementRange)
      row.rowHeight = height
      row.embed = hit.embed
      row.scale = CGFloat(coordinator.styler.environment.metrics.pointSizeScale)
      row.colors = EmbedRowColors(theme: coordinator.styler.environment.resolvedTheme)
      row.fontSpec = Self.nominalFontSpec(of: coordinator.styler.environment.resolvedTheme)
      if let style = paragraphStyle(at: hit.block.range.lowerBound) {
        row.indent = style.firstLineHeadIndent
        row.tailIndent = style.tailIndent
      }
      return row
    }

    // MARK: - Helpers

    private var storageLength: Int {
      #if os(macOS)
        textView?.textStorage?.length ?? 0
      #else
        textView?.textStorage.length ?? 0
      #endif
    }

    /// The paragraph style the coordinator wrote at `offset`, read from the storage.
    private func paragraphStyle(at offset: Int) -> NSParagraphStyle? {
      guard let storage = textView?.textStorage, offset < storage.length else { return nil }
      return storage.attribute(.paragraphStyle, at: offset, effectiveRange: nil)
        as? NSParagraphStyle
    }

    /// Where the text container's origin sits in the text view.
    private static func containerOrigin(of textView: EscriboNativeTextView) -> CGPoint {
      #if os(macOS)
        textView.textContainerOrigin
      #else
        CGPoint(x: textView.textContainerInset.left, y: textView.textContainerInset.top)
      #endif
    }
  }

  #if os(macOS)
    // MARK: - NSTextLayoutManagerDelegate (macOS: the slot is free)

    extension EmbedLayoutController: @preconcurrency NSTextLayoutManagerDelegate {
      func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
      ) -> NSTextLayoutFragment {
        embedFragment(in: textLayoutManager, for: textElement)
          ?? NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
      }
    }
  #endif

  // MARK: - Fragments

  /// A paragraph of an embedded block. Overrides the frame TextKit stacks paragraphs by.
  class EmbedLayoutFragment: NSTextLayoutFragment {

    /// The row's height, already scaled by the editor's zoom.
    var rowHeight: CGFloat = 0

    /// The height this fragment claims in the layout.
    var claimedHeight: CGFloat { rowHeight }

    /// The usable width of the text container: its width less the line-fragment padding
    /// on both sides — the text column.
    var columnWidth: CGFloat {
      if let container = textLayoutManager?.textContainer, container.size.width > 0 {
        return max(0, container.size.width - 2 * container.lineFragmentPadding)
      }
      return super.layoutFragmentFrame.width
    }

    override var layoutFragmentFrame: CGRect {
      var frame = super.layoutFragmentFrame
      frame.size.height = claimedHeight
      return frame
    }
  }

  /// The first paragraph of an embedded block: claims the row's height and draws the row.
  final class EmbedRowFragment: EmbedLayoutFragment {

    /// What to draw.
    var embed: EscriboEmbed?

    /// The block's leading indent (its first line's), in points.
    var indent: CGFloat = 0

    /// The block's trailing indent, with `NSParagraphStyle.tailIndent`'s sign convention:
    /// negative is inward from the trailing edge, positive is from the leading edge, zero is
    /// the column's own edge.
    var tailIndent: CGFloat = 0

    /// The editor's zoom, which scales the row's inner spacing.
    var scale: CGFloat = 1

    /// The theme's colours.
    var colors = EmbedRowColors()

    /// The theme's base font at its declared size; the row's text is derived from it.
    var fontSpec = FontSpec(family: .monospaced, pointSize: 12)

    /// How many times the row has been drawn.
    private(set) var drawCount = 0

    /// The row's rectangle relative to the fragment's origin: at the block's indent, as tall
    /// as the row, and no wider than the text column.
    var rowRect: CGRect {
      let trailing: CGFloat
      if tailIndent < 0 {
        trailing = columnWidth + tailIndent
      } else if tailIndent > 0 {
        trailing = min(columnWidth, tailIndent)
      } else {
        trailing = columnWidth
      }
      let leading = min(max(0, indent), trailing)
      return CGRect(x: leading, y: 0, width: max(0, trailing - leading), height: rowHeight)
    }

    override var renderingSurfaceBounds: CGRect {
      CGRect(x: 0, y: 0, width: max(columnWidth, rowRect.maxX), height: rowHeight)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
      guard let embed else { return }
      drawCount += 1
      let rect = rowRect.offsetBy(dx: point.x, dy: point.y).insetBy(dx: 0, dy: 2 * scale)
      EmbedRowRenderer(
        embed: embed, colors: colors, fontSpec: fontSpec, scale: scale
      ).draw(in: rect, context: context)
    }
  }

  /// Paragraphs 2…N of an embedded block: no height, nothing drawn.
  final class EmbedCollapsedFragment: EmbedLayoutFragment {
    override var claimedHeight: CGFloat { 0 }
    override var renderingSurfaceBounds: CGRect { .zero }
    override func draw(at point: CGPoint, in context: CGContext) {}
  }

  // MARK: - Installing on the editor

  extension EscriboTextView {

    /// Hooks the editor up to the coordinator's embed cache. Called once, from the
    /// initializer, on both platforms.
    ///
    /// Installs nothing by itself: the ``EmbedLayoutController`` is created and put in front
    /// of the layout manager the first time the cache holds an embed. With no provider the
    /// hook never fires.
    func installEmbedLayout() {
      coordinator.onEmbedsChange = { [weak self] ranges in
        self?.embedsDidChange(ranges)
      }
    }

    /// The change hook's body: install on the first embed, then re-vend what changed.
    private func embedsDidChange(_ ranges: [Range<Int>]) {
      if embedLayout == nil {
        guard !coordinator.embeddedBlocks.isEmpty else { return }
        let controller = EmbedLayoutController(textView: textView, coordinator: coordinator)
        controller.install()
        embedLayout = controller
      }
      embedLayout?.redraw(ranges)
    }
  }
#endif
