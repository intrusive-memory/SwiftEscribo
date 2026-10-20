// SPIKE — throwaway code for the atomic block-embed experiment. Never merged.
#if os(macOS)
  import AppKit
  import EscriboCore
  import Foundation
  import ObjectiveC

  /// The macOS half of the spike controller. The platform-neutral parts (delegate slots,
  /// registry, block lookup, invalidation, collapse mechanisms, fragments) live in
  /// `SpikeBlockEmbedController` (`BlockEmbedSpike.swift`); this adds the AppKit selection,
  /// delete and accessibility hooks.
  @MainActor
  final class MacBlockEmbedController: SpikeBlockEmbedController {

    // MARK: - Atomic behaviour (rows 3–7)

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
      // The registry entry is dropped (and later keys shifted) by `storageWillProcessEditing`,
      // before the coordinator re-scans.
      storage.replaceCharacters(in: removal, with: "")
      textView.didChangeText()
      textView.setSelectedRange(NSRange(location: removal.location, length: 0))
      return true
    }


    // MARK: - Accessibility (row 9)

    /// Called with the block's start offset when an embed's accessibility element is pressed.
    var onSpikeEmbedActivate: ((Int) -> Void)?

    /// Elements kept by block offset so VoiceOver sees stable identities across queries.
    private var accessibilityCache: [Int: SpikeEmbedAccessibilityElement] = [:]

    /// The row's rectangle in the text view's coordinates, from its layout fragment.
    func rowRect(forBlockAt range: NSRange) -> CGRect? {
      guard let textView = editor?.textView,
        let layoutManager = textView.textLayoutManager,
        let contentManager = layoutManager.textContentManager,
        let location = contentManager.location(
          contentManager.documentRange.location, offsetBy: range.location),
        let fragment = layoutManager.textLayoutFragment(for: location) as? SpikeEmbedRowFragment
      else { return nil }
      let frame = fragment.layoutFragmentFrame
      let origin = textView.textContainerOrigin
      return CGRect(
        x: frame.minX + origin.x + fragment.indent, y: frame.minY + origin.y,
        width: max(0, fragment.rowWidth - fragment.indent), height: frame.height)
    }

    /// One element per collapsed embed: role button, label = title, value = subtitle + badge,
    /// frame = the row (in parent space, which AppKit converts to screen coordinates).
    func accessibilityElements() -> [SpikeEmbedAccessibilityElement] {
      guard let textView = editor?.textView else { return [] }
      var result: [SpikeEmbedAccessibilityElement] = []
      var live: [Int: SpikeEmbedAccessibilityElement] = [:]
      for range in liveEmbeds() {
        guard let content = content(for: range) else { continue }
        let element = accessibilityCache[range.location] ?? SpikeEmbedAccessibilityElement()
        element.setAccessibilityRole(.button)
        element.setAccessibilityLabel(content.title)
        element.setAccessibilityValue("\(content.subtitle), \(content.badge)")
        element.setAccessibilityParent(textView)
        element.view = textView
        element.rowRect = rowRect(forBlockAt: range) ?? .zero
        element.setAccessibilityFrameInParentSpace(element.rowRect)
        let offset = range.location
        element.onPress = { [weak self] in self?.onSpikeEmbedActivate?(offset) }
        live[offset] = element
        result.append(element)
      }
      accessibilityCache = live
      return result
    }
  }

  /// Row 9: the accessibility element standing for one collapsed embed.
  final class SpikeEmbedAccessibilityElement: NSAccessibilityElement {
    var onPress: (@MainActor () -> Void)?
    weak var view: NSView?
    /// The row in `view`'s (flipped) coordinates.
    var rowRect: CGRect = .zero

    /// Screen coordinates. AppKit's default conversion from `accessibilityFrameInParentSpace`
    /// did not match the view's own conversion for the flipped text view (row 9), so convert
    /// explicitly.
    override func accessibilityFrame() -> NSRect {
      guard let view, view.window != nil else { return super.accessibilityFrame() }
      return NSAccessibility.screenRect(fromView: view, rect: rowRect)
    }

    override func accessibilityPerformPress() -> Bool {
      guard let onPress else { return false }
      MainActor.assumeIsolated { onPress() }
      return true
    }
  }

  // MARK: - Row drawing

  extension SpikeEmbedRowFragment {
    /// Draws the row (rounded background, SF Symbol, title, subtitle, badge) into `rect`.
    func drawRow(_ content: SpikeEmbedContent, in rect: CGRect, context: CGContext) {
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
      controller.install(on: textView, storage: documentStorage)
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
      textView.spikeAccessibilityChildren = { [weak controller] in
        controller?.accessibilityElements() ?? []
      }
      return controller
    }
  }
#endif
