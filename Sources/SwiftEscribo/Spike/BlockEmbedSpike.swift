// SPIKE — throwaway code for the atomic block-embed experiment. Never merged.
import EscriboCore
import Foundation

/// What a host supplies to draw one embedded block as a single row.
struct SpikeEmbedContent: Equatable {
  var symbolName: String
  var title: String
  var subtitle: String
  var badge: String
  var accessibilityLabel: String
  var accessibilityValue: String
}

/// Embeds keyed by the UTF-16 offset of the block's first character, plus the set of
/// those that are currently expanded (drawn as ordinary text).
struct SpikeEmbedRegistry {
  var embeds: [Int: SpikeEmbedContent] = [:]
  var expanded: Set<Int> = []

  /// The ranges of blocks that are embedded and not expanded, in document order.
  func embeddedRanges(in blocks: [EscriboBlock]) -> [NSRange] {
    blocks
      .filter { embeds[$0.range.lowerBound] != nil && !expanded.contains($0.range.lowerBound) }
      .map { NSRange(location: $0.range.lowerBound, length: $0.range.count) }
      .sorted { $0.location < $1.location }
  }
}

/// Pure selection and deletion rules shared by both platforms.
enum SpikeEmbedSelection {

  /// Constrains a proposed selection so an embed is never entered.
  ///
  /// - A caret strictly inside an embed snaps to the edge in the direction of travel
  ///   (`proposed` after `previous` goes to the end; before goes to the start; a click that
  ///   does not move snaps to the nearer edge).
  /// - A non-empty selection that overlaps an embed grows to cover it whole.
  static func constrain(proposed: NSRange, previous: NSRange, embeds: [NSRange]) -> NSRange {
    var result = proposed
    for embed in embeds.sorted(by: { $0.location < $1.location }) {
      let start = embed.location
      let end = NSMaxRange(embed)
      if result.length == 0 {
        let loc = result.location
        guard loc > start && loc < end else { continue }
        let travel = loc - previous.location
        if travel > 0 {
          result = NSRange(location: end, length: 0)
        } else if travel < 0 {
          result = NSRange(location: start, length: 0)
        } else {
          result = NSRange(location: (loc - start) * 2 < embed.length ? start : end, length: 0)
        }
      } else {
        let lo = result.location
        let hi = NSMaxRange(result)
        // Overlap of positive length with the embed.
        guard lo < end && hi > start else { continue }
        let newLo = min(lo, start)
        let newHi = max(hi, end)
        result = NSRange(location: newLo, length: newHi - newLo)
      }
    }
    return result
  }

  /// The range to remove when an embed is deleted: the block, plus the following blank
  /// line; or, when no blank line follows, the preceding blank line; otherwise the block
  /// alone. `embed` follows the block-range convention (its final terminator is inside).
  static func deletionRange(for embed: NSRange, in text: NSString) -> NSRange {
    let end = NSMaxRange(embed)
    if let blank = blankLine(startingAt: end, in: text) {
      return NSRange(location: embed.location, length: NSMaxRange(blank) - embed.location)
    }
    if let blank = blankLine(endingAt: embed.location, in: text) {
      return NSRange(location: blank.location, length: end - blank.location)
    }
    return embed
  }

  /// The blank line (terminator included) that begins at `start`, if there is one.
  private static func blankLine(startingAt start: Int, in text: NSString) -> NSRange? {
    guard start < text.length else { return nil }
    var i = start
    while i < text.length {
      let c = text.character(at: i)
      if c == 0x0A { return NSRange(location: start, length: i + 1 - start) }
      if c != 0x20 && c != 0x09 && c != 0x0D { return nil }
      i += 1
    }
    return NSRange(location: start, length: text.length - start)
  }

  /// The blank line (terminator included) that ends exactly at `end`, if there is one.
  private static func blankLine(endingAt end: Int, in text: NSString) -> NSRange? {
    guard end >= 1, end <= text.length, text.character(at: end - 1) == 0x0A else { return nil }
    var i = end - 1
    while i > 0 {
      let c = text.character(at: i - 1)
      if c == 0x0A { break }
      if c != 0x20 && c != 0x09 && c != 0x0D { return nil }
      i -= 1
    }
    return NSRange(location: i, length: end - i)
  }
}

#if os(macOS) || os(iOS)
  #if os(macOS)
    import AppKit
    typealias SpikePlatformFont = NSFont
  #else
    import UIKit
    typealias SpikePlatformFont = UIFont
  #endif
  import ObjectiveC

  /// How the N−1 trailing paragraphs of an embedded block are made to take no height.
  ///
  /// Kept as a switch so the spike tests can show, side by side, which mechanism collapses
  /// a multi-paragraph block and which do not. Findings (macOS 26 and iOS 26, TextKit 2 —
  /// identical on both):
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

  /// The platform-neutral half of the spike controller: owns the two TextKit 2 delegate
  /// slots the spike uses (layout manager and content storage), the registry, block lookup,
  /// invalidation and the registry's offset bookkeeping. Nothing here writes to
  /// `textStorage`; everything is display-side. `MacBlockEmbedController` and
  /// `IOSBlockEmbedController` subclass it for the platform's input and accessibility hooks.
  @MainActor
  class SpikeBlockEmbedController: NSObject {

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

    /// Installs this controller into the free TextKit 2 delegate slots and starts tracking
    /// storage edits. The storage's own delegate slot belongs to the coordinator.
    func install(on textView: EscriboNativeTextView, storage: NSTextStorage) {
      let layoutManager = textView.textLayoutManager
      let contentStorage = layoutManager?.textContentManager as? NSTextContentStorage
      // Evidence: any delegate the text view had already put in these slots. macOS: none.
      // iOS 26: UITextView's own `_UITextKit2LayoutController` holds the layout-manager slot.
      displacedDelegates = [
        layoutManager?.delegate.map { "layoutManager: \(type(of: $0))" },
        contentStorage?.delegate.map { "contentStorage: \(type(of: $0))" },
      ].compactMap { $0 }
      // Displaced delegates are chained, not dropped: every call the spike does not answer
      // goes to them (`responds(to:)` / `forwardingTarget(for:)`), and a non-embedded
      // paragraph gets whatever fragment they would have vended.
      forwardedLayoutDelegate = layoutManager?.delegate
      forwardedContentDelegate = contentStorage?.delegate
      layoutManager?.delegate = self
      contentStorage?.delegate = self
      observe(storage: storage)
    }

    /// The layout-manager delegate this controller displaced (UIKit's, on iOS). Weak, like
    /// the slot itself; its owner is the text view.
    private(set) weak var forwardedLayoutDelegate: NSTextLayoutManagerDelegate?

    /// The content-storage delegate this controller displaced, if any.
    private(set) weak var forwardedContentDelegate: NSTextContentStorageDelegate?

    override func responds(to aSelector: Selector!) -> Bool {
      if super.responds(to: aSelector) { return true }
      return (forwardedLayoutDelegate as AnyObject?)?.responds(to: aSelector) == true
        || (forwardedContentDelegate as AnyObject?)?.responds(to: aSelector) == true
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
      if let target = forwardedLayoutDelegate as AnyObject?, target.responds(to: aSelector) {
        return target
      }
      if let target = forwardedContentDelegate as AnyObject?, target.responds(to: aSelector) {
        return target
      }
      return super.forwardingTarget(for: aSelector)
    }

    /// Type names of delegates found in the two slots at install time (empty = both free).
    private(set) var displacedDelegates: [String] = []

    /// Blocks from the spike's own scan, used when the coordinator's spliced cache is not
    /// trustworthy. Cleared on every character edit (`storageWillProcessEditing`).
    private var fallbackBlocks: [EscriboBlock]?

    /// How many times the fallback full scan ran (row 11 instrumentation).
    private(set) var fallbackScans = 0

    /// The document's blocks: the coordinator's document-wide cache while it is sound
    /// (`blocksSpanDocument`), otherwise a read-only scan of the storage string. Row 11 found
    /// that an ordinary keystroke above a block can leave the cache unspliced (stale offsets),
    /// and the coordinator's own fallback (`block(atUTF16Offset:)`) restyles the storage,
    /// which must not happen from inside a layout-fragment request.
    func documentBlocks() -> [EscriboBlock] {
      guard let editor else { return [] }
      let coordinator = editor.coordinator
      if coordinator.blocksSpanDocument { return coordinator.documentBlocks }
      if let fallbackBlocks { return fallbackBlocks }
      var scanner = EscriboScanner(language: coordinator.language)
      let blocks = scanner.fullScan(editor.documentStorage.string).blocks
      fallbackScans += 1
      fallbackBlocks = blocks
      return blocks
    }

    /// Embedded (collapsed) block ranges, from the document's blocks.
    func embeddedRanges() -> [NSRange] {
      guard !registry.embeds.isEmpty else { return [] }
      return registry.embeddedRanges(in: documentBlocks())
    }

    /// The live embedded ranges, dropped if they no longer fit the storage (the coordinator's
    /// blocks can lag the storage by one edit while the text view fixes up the selection).
    func liveEmbeds() -> [NSRange] {
      guard let length = editor?.documentStorage.length else { return [] }
      return embeddedRanges().filter { NSMaxRange($0) <= length }
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
      guard let storage = editor?.documentStorage, offset < storage.length,
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
      // hears of it (asserted by the row 2 tests via `restyleCount`).
      contentStorage.performEditingTransaction {
        contentStorage.recordEditAction(in: textRange, newTextRange: textRange)
      }
      layoutManager.invalidateLayout(for: textRange)
      #if os(macOS)
        textView.needsDisplay = true
      #else
        textView.setNeedsLayout()
        textView.setNeedsDisplay()
      #endif
    }

    // MARK: - Edit veto (row 7, and a guard for row 5)

    /// An edit may not put characters into, or remove part of, an embed. Pure deletions that
    /// cover every embed they touch are allowed.
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

    // MARK: - Keeping registry keys in step with edits (row 11)

    /// Registry keys are block start offsets, so an edit above a block moves its key.
    /// `willProcessEditing` fires before the storage delegate (the coordinator) re-scans, so
    /// the keys already match the new blocks when the scan and the next layout run.
    /// Observes a notification — the storage's delegate slot belongs to the coordinator.
    func observe(storage: NSTextStorage) {
      NotificationCenter.default.addObserver(
        self, selector: #selector(storageWillProcessEditing(_:)),
        name: NSTextStorage.willProcessEditingNotification, object: storage)
    }

    @objc private func storageWillProcessEditing(_ note: Notification) {
      guard let storage = note.object as? NSTextStorage,
        storage.editedMask.contains(.editedCharacters)
      else { return }
      fallbackBlocks = nil
      let delta = storage.changeInLength
      let edited = storage.editedRange
      // The range the edit replaced, in pre-edit offsets.
      let oldStart = edited.location
      let oldEnd = NSMaxRange(edited) - delta
      func moved(_ key: Int) -> Int? {
        if key < oldStart { return key }
        if key >= oldEnd { return key + delta }
        return nil  // the block's first character was replaced: the embed goes with it
      }
      registry.embeds = Dictionary(
        uniqueKeysWithValues: registry.embeds.compactMap { key, value in
          moved(key).map { ($0, value) }
        })
      registry.expanded = Set(registry.expanded.compactMap(moved))
    }

    // MARK: - Expand / collapse (row 8)

    /// Expands (draws as ordinary text, caret may enter) or collapses one embedded block.
    func setExpanded(_ expanded: Bool, forBlockStartingAt offset: Int) {
      guard registry.embeds[offset] != nil,
        let block = documentBlocks().first(where: { $0.range.lowerBound == offset })
      else { return }
      if expanded { registry.expanded.insert(offset) } else { registry.expanded.remove(offset) }
      invalidate(range: NSRange(location: offset, length: block.range.count))
      // Collapsing under a caret that is inside the block: push it through the filter again.
      if !expanded { reassertSelection() }
    }

    /// Re-applies the current selection so the platform's selection filter sees it.
    func reassertSelection() {
      guard let textView = editor?.textView else { return }
      #if os(macOS)
        textView.setSelectedRange(textView.selectedRange())
      #else
        textView.selectedRange = textView.selectedRange
      #endif
    }

    // MARK: - Fragment vending

    fileprivate func makeFragment(
      _ textLayoutManager: NSTextLayoutManager, location: any NSTextLocation,
      element: NSTextElement
    ) -> NSTextLayoutFragment {
      let plain = { [forwardedLayoutDelegate] in
        forwardedLayoutDelegate?.textLayoutManager?(
          textLayoutManager, textLayoutFragmentFor: location, in: element)
          ?? NSTextLayoutFragment(textElement: element, range: element.elementRange)
      }
      guard let contentManager = textLayoutManager.textContentManager,
        let elementRange = element.elementRange
      else { return plain() }
      let offset = contentManager.offset(
        from: contentManager.documentRange.location, to: elementRange.location)
      guard let hit = embed(containingParagraphAt: offset) else { return plain() }

      let fragment: SpikeEmbedFragment
      if hit.isFirst, let content = content(for: hit.range) {
        rowFragmentCreations += 1
        let row = SpikeEmbedRowFragment(textElement: element, range: elementRange)
        row.content = content
        row.indent = leadingIndent(at: hit.range.location)
        fragment = row
      } else {
        fragment = SpikeEmbedCollapsedFragment(textElement: element, range: elementRange)
      }
      fragment.rowHeight = rowHeight
      fragment.scale = scale
      fragment.overridesFrame = mechanism == .fragmentFrameOverride
      return fragment
    }

    fileprivate func displayParagraph(_ storage: NSTextContentStorage, range: NSRange)
      -> NSTextParagraph?
    {
      let forwarded = { [forwardedContentDelegate] in
        forwardedContentDelegate?.textContentStorage?(storage, textParagraphWith: range)
      }
      guard mechanism == .contentStorageParagraph,
        let hit = embed(containingParagraphAt: range.location),
        let source = storage.textStorage
      else { return forwarded() }

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
      display.addAttribute(.font, value: SpikePlatformFont.systemFont(ofSize: 0.01), range: whole)
      displayParagraphCount += 1
      return NSTextParagraph(attributedString: display)
    }
  }

  // MARK: - NSTextLayoutManagerDelegate

  extension SpikeBlockEmbedController: @preconcurrency NSTextLayoutManagerDelegate {
    func textLayoutManager(
      _ textLayoutManager: NSTextLayoutManager,
      textLayoutFragmentFor location: any NSTextLocation,
      in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
      makeFragment(textLayoutManager, location: location, element: textElement)
    }
  }

  // MARK: - NSTextContentStorageDelegate

  extension SpikeBlockEmbedController: @preconcurrency NSTextContentStorageDelegate {
    func textContentStorage(
      _ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange
    ) -> NSTextParagraph? {
      displayParagraph(textContentStorage, range: range)
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

  /// The first paragraph of an embedded block: draws the whole row. The drawing itself is
  /// per platform (`drawRow(_:in:context:)` in `MacBlockEmbed.swift` / `IOSBlockEmbed.swift`).
  final class SpikeEmbedRowFragment: SpikeEmbedFragment {
    var content: SpikeEmbedContent?

    /// How many times `draw(at:in:)` ran (evidence that the row is actually drawn).
    private(set) var drawCount = 0

    override func draw(at point: CGPoint, in context: CGContext) {
      guard let content else { return }
      drawCount += 1
      let rect = CGRect(
        x: point.x + indent, y: point.y,
        width: max(0, rowWidth - indent), height: rowHeight
      ).insetBy(dx: 0, dy: 2 * scale)
      drawRow(content, in: rect, context: context)
    }
  }

  /// Paragraphs 2…N of an embedded block: draw nothing and (when the mechanism allows)
  /// take no height.
  final class SpikeEmbedCollapsedFragment: SpikeEmbedFragment {
    override var claimedHeight: CGFloat { 0 }
    override var renderingSurfaceBounds: CGRect { .zero }
    override func draw(at point: CGPoint, in context: CGContext) {}
  }

  // MARK: - Entry points on the text view

  extension EscriboTextView {

    /// Embeds (or, with `nil`, un-embeds) the block starting at `offset`. Updates the
    /// registry and invalidates layout for that block only. Never touches `textStorage`.
    /// `spikeEmbeds` is the platform's controller (macOS / iOS file).
    func spikeSetEmbed(_ content: SpikeEmbedContent?, forBlockStartingAt offset: Int) {
      let controller = spikeEmbeds
      controller.registry.embeds[offset] = content
      guard let block = controller.documentBlocks().first(where: { $0.range.lowerBound == offset })
      else { return }
      controller.invalidate(range: NSRange(location: offset, length: block.range.count))
    }

    /// Row 8: the host's *Edit as Text* toggle for one embedded block.
    func spikeSetExpanded(_ expanded: Bool, forBlockStartingAt offset: Int) {
      spikeEmbeds.setExpanded(expanded, forBlockStartingAt: offset)
    }
  }
#endif
