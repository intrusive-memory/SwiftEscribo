// SPIKE — throwaway code for the atomic block-embed experiment. Never merged.
#if os(macOS)
  import AppKit
  import EscriboCore
  import Foundation
  import ObjectiveC

  /// How the N−1 trailing paragraphs of an embedded block are made to take no height.
  ///
  /// Kept as a switch so the spike tests can show, side by side, which mechanism collapses
  /// a multi-paragraph block and which do not. Findings (macOS 26, TextKit 2):
  ///
  /// - ``fragmentDrawOnly`` — **fails.** Drawing is cosmetic; `NSTextLayoutManager` stacks
  ///   fragments by their own line-fragment geometry, so the block keeps N line heights.
  /// - ``fragmentFrameOverride`` — **works; the spike ships it.** `NSTextLayoutManager`
  ///   positions each fragment directly below the previous fragment's *overridden*
  ///   `layoutFragmentFrame`, so the first fragment claiming `rowHeight` and the rest claiming
  ///   0 collapses N fragments into one row. It is recomputed whenever the layout manager
  ///   asks the delegate for fragments, so it survives a coordinator restyle and a zoom.
  /// - ``contentStorageParagraph`` — **collapses only on first vend; cannot be switched on
  ///   for an already-laid-out document without a storage edit.** `NSTextContentStorage`
  ///   consults `textContentStorage(_:textParagraphWith:)` when it first vends a paragraph or
  ///   when the backing `NSTextStorage` reports an edit (the coordinator's restyle does, so it
  ///   does survive one). `recordEditAction(in:newTextRange:)` re-creates layout fragments but
  ///   does not re-vend cached paragraphs, so embedding a block on a document already on screen
  ///   does nothing until the next storage edit — forcing one means writing to (or posting
  ///   `edited(_:range:changeInLength:)` on) `textStorage`, which the spike forbids. It also
  ///   re-attributes the real characters (tiny font, pinned line heights), which distorts
  ///   caret and selection geometry inside the block.
  enum SpikeCollapseMechanism: CaseIterable {
    case fragmentDrawOnly
    case fragmentFrameOverride
    case contentStorageParagraph
  }

  /// Owns the two TextKit 2 delegate slots the spike uses. Nothing here writes to
  /// `textStorage`; everything is display-side.
  @MainActor
  final class MacBlockEmbedController: NSObject {

    /// The mechanism the spike ships with. Tests may flip it to compare the alternatives.
    var mechanism: SpikeCollapseMechanism = .fragmentFrameOverride

    /// Row height at a `pointSizeScale` of 1. Scaled with the editor's zoom.
    nonisolated static let baseRowHeight: CGFloat = 44

    /// Tiny line height used for the collapsed (non-first) paragraphs. TextKit 2 treats a
    /// `maximumLineHeight` of exactly 0 as "no limit", so this is the smallest positive
    /// value it honours without treating it as unset.
    nonisolated static let collapsedLineHeight: CGFloat = 0.001

    var registry = SpikeEmbedRegistry()

    /// Instrumentation for later sorties (row 11): how many row fragments were created.
    private(set) var rowFragmentCreations = 0

    /// Instrumentation: how many display paragraphs the content-storage delegate vended.
    private(set) var displayParagraphCount = 0

    weak var editor: EscriboTextView?

    init(editor: EscriboTextView) {
      self.editor = editor
      super.init()
    }

    /// The zoom factor the styler is composing with.
    var scale: CGFloat {
      CGFloat(editor?.coordinator.styler.environment.metrics.pointSizeScale ?? 1)
    }

    var rowHeight: CGFloat { Self.baseRowHeight * scale }

    /// Embedded (collapsed) block ranges, from the coordinator's document-wide blocks.
    func embeddedRanges() -> [NSRange] {
      guard let coordinator = editor?.coordinator, !registry.embeds.isEmpty else { return [] }
      return registry.embeddedRanges(in: coordinator.documentBlocks)
    }

    /// The embedded range containing a paragraph starting at `offset`, and whether the
    /// paragraph is the block's first.
    func embed(containingParagraphAt offset: Int) -> (range: NSRange, isFirst: Bool)? {
      for range in embeddedRanges() where offset >= range.location && offset < NSMaxRange(range) {
        return (range, offset == range.location)
      }
      return nil
    }

    func content(for range: NSRange) -> SpikeEmbedContent? {
      registry.embeds[range.location]
    }

    /// Leading indent of the block's first paragraph, read from the real storage.
    func leadingIndent(at offset: Int) -> CGFloat {
      guard let storage = editor?.textView.textStorage, offset < storage.length,
        let style = storage.attribute(.paragraphStyle, at: offset, effectiveRange: nil)
          as? NSParagraphStyle
      else { return 0 }
      return style.firstLineHeadIndent
    }

    // MARK: - Invalidation

    func invalidate(range: NSRange) {
      guard let textView = editor?.textView,
        let layoutManager = textView.textLayoutManager,
        let contentStorage = layoutManager.textContentManager as? NSTextContentStorage,
        let start = contentStorage.location(contentStorage.documentRange.location, offsetBy: range.location),
        let end = contentStorage.location(start, offsetBy: range.length),
        let textRange = NSTextRange(location: start, end: end)
      else { return }
      // `invalidateLayout(for:)` alone keeps the existing fragment objects, so the delegate
      // would never be asked again. A same-range edit recorded on the content manager only
      // makes the layout manager discard and re-request the block's fragments. The backing
      // NSTextStorage is not edited, so `processEditing` never runs and the coordinator never
      // hears of it (asserted by the row 2 test via `restyleCount`).
      contentStorage.performEditingTransaction {
        contentStorage.recordEditAction(in: textRange, newTextRange: textRange)
      }
      layoutManager.invalidateLayout(for: textRange)
      textView.needsDisplay = true
    }

    // MARK: - Atomic behaviour (rows 3–7)

    /// The live embedded ranges, dropped if they no longer fit the storage (the coordinator's
    /// blocks can lag the storage by one edit while `NSTextView` fixes up the selection).
    private func liveEmbeds() -> [NSRange] {
      guard let length = editor?.textView.textStorage?.length else { return [] }
      return embeddedRanges().filter { NSMaxRange($0) <= length }
    }

    /// Row 3/4: every proposed selection goes through `SpikeEmbedSelection.constrain`.
    /// Needed because the zero-height fragments keep their real line fragments, so AppKit's
    /// own caret movement and hit-testing still find positions inside the block.
    func filterSelection(_ proposed: [NSValue], current: [NSValue]) -> [NSValue] {
      let embeds = liveEmbeds()
      guard !embeds.isEmpty, let length = editor?.textView.textStorage?.length else {
        return proposed
      }
      let previous = current.first?.rangeValue ?? NSRange(location: 0, length: 0)
      return proposed.map { value in
        let range = value.rangeValue
        let constrained = SpikeEmbedSelection.constrain(
          proposed: range, previous: previous, embeds: embeds)
        guard NSMaxRange(constrained) <= length else { return value }
        return NSValue(range: constrained)
      }
    }

    /// Row 7 (and a guard for row 5): an edit may not put characters into, or remove part
    /// of, an embed. Pure deletions that cover every embed they touch are allowed.
    func allowsEdit(in range: NSRange, replacement: String?) -> Bool {
      // Attribute-only changes (`nil` replacement) are never the user's keystroke.
      guard let replacement else { return true }
      for embed in liveEmbeds() {
        let start = embed.location
        let end = NSMaxRange(embed)
        let touches: Bool
        if range.length == 0 {
          touches = range.location > start && range.location < end
        } else {
          touches = range.location < end && NSMaxRange(range) > start
        }
        guard touches else { continue }
        if !replacement.isEmpty { return false }
        let coversWhole = range.location <= start && NSMaxRange(range) >= end
        if !coversWhole { return false }
      }
      return true
    }

    /// Row 5: with an embed exactly selected, Delete removes the embed's `deletionRange`
    /// (block + one adjacent blank line) as one `shouldChangeText`/`didChangeText` pair, i.e.
    /// one undo action.
    func deleteSelectedEmbed() -> Bool {
      guard let textView = editor?.textView, let storage = textView.textStorage else {
        return false
      }
      let selection = textView.selectedRange()
      guard let embed = liveEmbeds().first(where: { $0 == selection }) else { return false }
      let removal = SpikeEmbedSelection.deletionRange(for: embed, in: storage.string as NSString)
      guard textView.shouldChangeText(in: removal, replacementString: "") else { return true }
      // The block is gone: drop its registry entry and shift later keys before storage
      // processing re-scans, so the filter never sees a stale offset.
      registry.embeds[embed.location] = nil
      registry.expanded.remove(embed.location)
      registry.embeds = Dictionary(
        uniqueKeysWithValues: registry.embeds.map { key, value in
          (key > embed.location ? key - removal.length : key, value)
        })
      registry.expanded = Set(
        registry.expanded.map { $0 > embed.location ? $0 - removal.length : $0 })
      storage.replaceCharacters(in: removal, with: "")
      textView.didChangeText()
      textView.setSelectedRange(NSRange(location: removal.location, length: 0))
      return true
    }
  }

  // MARK: - NSTextLayoutManagerDelegate

  extension MacBlockEmbedController: @preconcurrency NSTextLayoutManagerDelegate {
    func textLayoutManager(
      _ textLayoutManager: NSTextLayoutManager,
      textLayoutFragmentFor location: any NSTextLocation,
      in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
      makeFragment(textLayoutManager, location: location, element: textElement)
    }

    private func makeFragment(
      _ textLayoutManager: NSTextLayoutManager, location: any NSTextLocation,
      element: NSTextElement
    ) -> NSTextLayoutFragment {
      let plain = { NSTextLayoutFragment(textElement: element, range: element.elementRange) }
      guard let contentManager = textLayoutManager.textContentManager,
        let elementRange = element.elementRange
      else { return plain() }
      let offset = contentManager.offset(
        from: contentManager.documentRange.location, to: elementRange.location)
      guard let hit = embed(containingParagraphAt: offset) else { return plain() }

      let fragment: SpikeEmbedFragment
      if hit.isFirst, let content = content(for: hit.range) {
        rowFragmentCreations += 1
        fragment = SpikeEmbedRowFragment(textElement: element, range: elementRange)
        (fragment as! SpikeEmbedRowFragment).content = content
        fragment.indent = leadingIndent(at: hit.range.location)
      } else {
        fragment = SpikeEmbedCollapsedFragment(textElement: element, range: elementRange)
      }
      fragment.rowHeight = rowHeight
      fragment.scale = scale
      fragment.overridesFrame = mechanism == .fragmentFrameOverride
      return fragment
    }
  }

  // MARK: - NSTextContentStorageDelegate

  extension MacBlockEmbedController: @preconcurrency NSTextContentStorageDelegate {
    func textContentStorage(
      _ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange
    ) -> NSTextParagraph? {
      displayParagraph(textContentStorage, range: range)
    }

    private func displayParagraph(_ storage: NSTextContentStorage, range: NSRange)
      -> NSTextParagraph?
    {
      guard mechanism == .contentStorageParagraph,
        let hit = embed(containingParagraphAt: range.location),
        let source = storage.textStorage
      else { return nil }

      // Same characters, display-only attributes. The real storage is only read.
      let display = NSMutableAttributedString(attributedString: source.attributedSubstring(from: range))
      let style = NSMutableParagraphStyle()
      if let original = display.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
        as? NSParagraphStyle
      {
        style.setParagraphStyle(original)
      }
      let height = hit.isFirst ? rowHeight : Self.collapsedLineHeight
      style.minimumLineHeight = height
      style.maximumLineHeight = height
      style.lineSpacing = 0
      style.paragraphSpacing = 0
      style.paragraphSpacingBefore = 0
      style.lineHeightMultiple = 0
      // No wrapping: the whole paragraph is one (clipped) line, so a long note line cannot
      // add a second line of height.
      style.lineBreakMode = .byClipping
      let whole = NSRange(location: 0, length: display.length)
      display.addAttribute(.paragraphStyle, value: style, range: whole)
      // A tiny font keeps the glyph run inside one line whatever the paragraph's length.
      display.addAttribute(.font, value: NSFont.systemFont(ofSize: 0.01), range: whole)
      displayParagraphCount += 1
      return NSTextParagraph(attributedString: display)
    }
  }

  // MARK: - Fragments

  /// Base for the spike's fragments: carries the row geometry and the frame override.
  class SpikeEmbedFragment: NSTextLayoutFragment {
    /// The row spans the text container's usable width, not the paragraph's own text width.
    var rowWidth: CGFloat {
      if let container = textLayoutManager?.textContainer, container.size.width > 0 {
        return max(0, container.size.width - 2 * container.lineFragmentPadding)
      }
      return super.layoutFragmentFrame.width
    }

    var rowHeight: CGFloat = 44
    var scale: CGFloat = 1
    var indent: CGFloat = 0
    var overridesFrame = false

    /// The height this fragment claims when it overrides its frame.
    var claimedHeight: CGFloat { rowHeight }

    override var layoutFragmentFrame: CGRect {
      var frame = super.layoutFragmentFrame
      if overridesFrame { frame.size.height = claimedHeight }
      return frame
    }

    override var renderingSurfaceBounds: CGRect {
      CGRect(x: 0, y: 0, width: rowWidth, height: rowHeight)
    }
  }

  /// The first paragraph of an embedded block: draws the whole row.
  final class SpikeEmbedRowFragment: SpikeEmbedFragment {
    var content: SpikeEmbedContent?

    override func draw(at point: CGPoint, in context: CGContext) {
      guard let content else { return }
      let width = rowWidth
      let rect = CGRect(
        x: point.x + indent, y: point.y,
        width: max(0, width - indent), height: rowHeight
      ).insetBy(dx: 0, dy: 2 * scale)

      NSGraphicsContext.saveGraphicsState()
      defer { NSGraphicsContext.restoreGraphicsState() }
      let ns = NSGraphicsContext(cgContext: context, flipped: true)
      NSGraphicsContext.current = ns

      NSColor.quaternaryLabelColor.setFill()
      NSBezierPath(roundedRect: rect, xRadius: 6 * scale, yRadius: 6 * scale).fill()

      let pad = 8 * scale
      let iconSide = rect.height - 2 * pad
      var x = rect.minX + pad
      if let image = NSImage(systemSymbolName: content.symbolName, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(paletteColors: [.secondaryLabelColor]))
      {
        image.draw(
          in: CGRect(x: x, y: rect.minY + pad, width: iconSide, height: iconSide),
          from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
      }
      x += iconSide + pad

      let titleFont = NSFont.systemFont(ofSize: 12 * scale, weight: .semibold)
      let subtitleFont = NSFont.systemFont(ofSize: 10 * scale)
      let badgeFont = NSFont.systemFont(ofSize: 10 * scale, weight: .medium)

      let badge = NSAttributedString(
        string: content.badge,
        attributes: [.font: badgeFont, .foregroundColor: NSColor.secondaryLabelColor])
      let badgeSize = badge.size()
      let badgeRect = CGRect(
        x: rect.maxX - pad - badgeSize.width - 8 * scale, y: rect.midY - badgeSize.height / 2 - 2 * scale,
        width: badgeSize.width + 8 * scale, height: badgeSize.height + 4 * scale)
      NSColor.tertiaryLabelColor.setFill()
      NSBezierPath(roundedRect: badgeRect, xRadius: badgeRect.height / 2, yRadius: badgeRect.height / 2)
        .fill()
      badge.draw(at: CGPoint(x: badgeRect.minX + 4 * scale, y: badgeRect.minY + 2 * scale))

      let textWidth = max(0, badgeRect.minX - pad - x)
      NSAttributedString(
        string: content.title,
        attributes: [.font: titleFont, .foregroundColor: NSColor.labelColor]
      ).draw(in: CGRect(x: x, y: rect.minY + pad - 2 * scale, width: textWidth, height: titleFont.boundingRectForFont.height))
      NSAttributedString(
        string: content.subtitle,
        attributes: [.font: subtitleFont, .foregroundColor: NSColor.secondaryLabelColor]
      ).draw(in: CGRect(x: x, y: rect.midY + 1 * scale, width: textWidth, height: subtitleFont.boundingRectForFont.height))
    }
  }

  /// Paragraphs 2…N of an embedded block: draw nothing and (when the mechanism allows)
  /// take no height.
  final class SpikeEmbedCollapsedFragment: SpikeEmbedFragment {
    override var claimedHeight: CGFloat { 0 }
    override var renderingSurfaceBounds: CGRect { .zero }
    override func draw(at point: CGPoint, in context: CGContext) {}
  }

  // MARK: - Entry point on the text view

  @MainActor private var spikeControllerKey: UInt8 = 0

  extension EscriboTextView {

    /// The spike controller, installed lazily into the two free TextKit 2 delegate slots.
    var spikeEmbeds: MacBlockEmbedController {
      if let existing = objc_getAssociatedObject(textView, &spikeControllerKey)
        as? MacBlockEmbedController
      {
        return existing
      }
      let controller = MacBlockEmbedController(editor: self)
      objc_setAssociatedObject(
        textView, &spikeControllerKey, controller, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
      textView.textLayoutManager?.delegate = controller
      (textView.textLayoutManager?.textContentManager as? NSTextContentStorage)?.delegate =
        controller
      // Rows 3–7: the `// SPIKE` hooks on the text view subclass (not the delegate, which
      // belongs to the SwiftUI bridge).
      textView.spikeSelectionFilter = { [weak controller] proposed, current in
        controller?.filterSelection(proposed, current: current) ?? proposed
      }
      textView.spikeEditFilter = { [weak controller] range, replacement in
        controller?.allowsEdit(in: range, replacement: replacement) ?? true
      }
      textView.spikeDeleteHandler = { [weak controller] in
        controller?.deleteSelectedEmbed() ?? false
      }
      return controller
    }

    /// Embeds (or, with `nil`, un-embeds) the block starting at `offset`. Updates the
    /// registry and invalidates layout for that block only. Never touches `textStorage`.
    func spikeSetEmbed(_ content: SpikeEmbedContent?, forBlockStartingAt offset: Int) {
      let controller = spikeEmbeds
      controller.registry.embeds[offset] = content
      guard let block = coordinator.documentBlocks.first(where: { $0.range.lowerBound == offset })
      else { return }
      controller.invalidate(range: NSRange(location: offset, length: block.range.count))
    }
  }
#endif
