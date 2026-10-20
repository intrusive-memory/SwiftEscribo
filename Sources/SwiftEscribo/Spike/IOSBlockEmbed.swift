// SPIKE — throwaway code for the atomic block-embed experiment. Never merged.
#if os(iOS)
  import EscriboCore
  import Foundation
  import ObjectiveC
  import UIKit

  /// The iOS half of the spike controller. Everything that collapses and draws the block —
  /// the layout-manager delegate vending `SpikeEmbedRowFragment` / `SpikeEmbedCollapsedFragment`
  /// with an overridden `layoutFragmentFrame`, and the same-range content-storage edit that
  /// invalidates — is the shared `SpikeBlockEmbedController`, unchanged from macOS.
  /// This adds the UIKit selection and delete hooks (rows 3–7) and accessibility (row 9).
  /// Expand / collapse (row 8) and the registry bookkeeping for edits (row 11) are shared.
  @MainActor
  final class IOSBlockEmbedController: SpikeBlockEmbedController {

    // MARK: - Atomic behaviour (rows 3–7)

    /// Rows 3/4: every proposed selection (from the `selectedTextRange` / `selectedRange`
    /// setters) goes through `SpikeEmbedSelection.constrain`. As on macOS the collapsed
    /// fragments keep their real line fragments, so UIKit's own position APIs
    /// (`position(from:in:offset:)`, `closestPosition(to:)`) still return offsets inside the
    /// block; the filter is what keeps the caret out.
    func filterSelection(_ proposed: NSRange, current: NSRange) -> NSRange {
      let embeds = liveEmbeds()
      guard !embeds.isEmpty, let length = editor?.documentStorage.length else { return proposed }
      let constrained = SpikeEmbedSelection.constrain(
        proposed: proposed, previous: current, embeds: embeds)
      return NSMaxRange(constrained) <= length ? constrained : proposed
    }

    /// Row 5: with an embed exactly selected, Backspace removes the embed's `deletionRange`
    /// (block + one adjacent blank line) through `UITextInput.replace(_:withText:)` — UIKit's
    /// own input path, which registers the undo — as one edit.
    func deleteSelectedEmbed() -> Bool {
      guard let editor else { return false }
      let textView = editor.textView
      let selection = textView.selectedRange
      guard let embed = liveEmbeds().first(where: { $0 == selection }) else { return false }
      let removal = SpikeEmbedSelection.deletionRange(
        for: embed, in: editor.documentStorage.string as NSString)
      // The registry entry is dropped (and later keys shifted) by `storageWillProcessEditing`.
      editor.performInputPathEdit(InputPathEdit(replacing: removal, with: ""))
      textView.selectedRange = NSRange(location: removal.location, length: 0)
      return true
    }

    // MARK: - Accessibility (row 9)

    /// Called with the block's start offset when an embed's accessibility element activates.
    var onSpikeEmbedActivate: ((Int) -> Void)?

    /// Elements kept by block offset so VoiceOver sees stable identities across queries.
    private var accessibilityCache: [Int: SpikeEmbedAccessibilityElement] = [:]

    /// The row's rectangle in the text view's bounds (content) coordinates, from its layout
    /// fragment. Content coordinates are the container space of a scroll view's elements,
    /// so UIKit moves the element with scrolling.
    func rowRect(forBlockAt range: NSRange) -> CGRect? {
      guard let textView = editor?.textView,
        let layoutManager = textView.textLayoutManager,
        let contentManager = layoutManager.textContentManager,
        let location = contentManager.location(
          contentManager.documentRange.location, offsetBy: range.location),
        let fragment = layoutManager.textLayoutFragment(for: location) as? SpikeEmbedRowFragment
      else { return nil }
      let frame = fragment.layoutFragmentFrame
      let inset = textView.textContainerInset
      return CGRect(
        x: frame.minX + inset.left + fragment.indent, y: frame.minY + inset.top,
        width: max(0, fragment.rowWidth - fragment.indent), height: frame.height)
    }

    /// One element per collapsed embed: trait button, label = title, value = subtitle + badge,
    /// frame = the row in the text view's coordinate space.
    func accessibilityElements() -> [SpikeEmbedAccessibilityElement] {
      guard let textView = editor?.textView else { return [] }
      var result: [SpikeEmbedAccessibilityElement] = []
      var live: [Int: SpikeEmbedAccessibilityElement] = [:]
      for range in liveEmbeds() {
        guard let content = content(for: range) else { continue }
        let element =
          accessibilityCache[range.location]
          ?? SpikeEmbedAccessibilityElement(accessibilityContainer: textView)
        element.accessibilityTraits = .button
        element.accessibilityLabel = content.title
        element.accessibilityValue = "\(content.subtitle), \(content.badge)"
        element.accessibilityFrameInContainerSpace = rowRect(forBlockAt: range) ?? .zero
        let offset = range.location
        element.onActivate = { [weak self] in self?.onSpikeEmbedActivate?(offset) }
        live[offset] = element
        result.append(element)
      }
      accessibilityCache = live
      return result
    }
  }

  /// Row 9: the accessibility element standing for one collapsed embed.
  final class SpikeEmbedAccessibilityElement: UIAccessibilityElement {
    var onActivate: (@MainActor () -> Void)?

    /// Screen coordinates. Observed in the simulator test host: UIKit's default conversion
    /// from `accessibilityFrameInContainerSpace` returns `.zero` (it lives in the accessibility
    /// runtime, which is not loaded there), so convert explicitly through the container view.
    override var accessibilityFrame: CGRect {
      get {
        guard let view = accessibilityContainer as? UIView, view.window != nil else {
          return super.accessibilityFrame
        }
        return UIAccessibility.convertToScreenCoordinates(accessibilityFrameInContainerSpace, in: view)
      }
      set { super.accessibilityFrame = newValue }
    }

    override func accessibilityActivate() -> Bool {
      guard let onActivate else { return false }
      MainActor.assumeIsolated { onActivate() }
      return true
    }
  }

  // MARK: - Row drawing

  extension SpikeEmbedRowFragment {
    /// Draws the row (rounded background, SF Symbol, title, subtitle, badge) into `rect`.
    /// UIKit's text drawing draws into the current UIKit context, so `context` is pushed.
    func drawRow(_ content: SpikeEmbedContent, in rect: CGRect, context: CGContext) {
      UIGraphicsPushContext(context)
      defer { UIGraphicsPopContext() }

      UIColor.quaternaryLabel.setFill()
      UIBezierPath(roundedRect: rect, cornerRadius: 6 * scale).fill()

      let pad = 8 * scale
      let iconSide = rect.height - 2 * pad
      var x = rect.minX + pad
      if let image = UIImage(systemName: content.symbolName)?
        .withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
      {
        image.draw(in: CGRect(x: x, y: rect.minY + pad, width: iconSide, height: iconSide))
      }
      x += iconSide + pad

      let titleFont = UIFont.systemFont(ofSize: 12 * scale, weight: .semibold)
      let subtitleFont = UIFont.systemFont(ofSize: 10 * scale)
      let badgeFont = UIFont.systemFont(ofSize: 10 * scale, weight: .medium)

      let badge = NSAttributedString(
        string: content.badge,
        attributes: [.font: badgeFont, .foregroundColor: UIColor.secondaryLabel])
      let badgeSize = badge.size()
      let badgeRect = CGRect(
        x: rect.maxX - pad - badgeSize.width - 8 * scale, y: rect.midY - badgeSize.height / 2 - 2 * scale,
        width: badgeSize.width + 8 * scale, height: badgeSize.height + 4 * scale)
      UIColor.tertiaryLabel.setFill()
      UIBezierPath(roundedRect: badgeRect, cornerRadius: badgeRect.height / 2).fill()
      badge.draw(at: CGPoint(x: badgeRect.minX + 4 * scale, y: badgeRect.minY + 2 * scale))

      let textWidth = max(0, badgeRect.minX - pad - x)
      NSAttributedString(
        string: content.title,
        attributes: [.font: titleFont, .foregroundColor: UIColor.label]
      ).draw(in: CGRect(x: x, y: rect.minY + pad - 2 * scale, width: textWidth, height: titleFont.lineHeight))
      NSAttributedString(
        string: content.subtitle,
        attributes: [.font: subtitleFont, .foregroundColor: UIColor.secondaryLabel]
      ).draw(in: CGRect(x: x, y: rect.midY + 1 * scale, width: textWidth, height: subtitleFont.lineHeight))
    }
  }

  // MARK: - Entry point on the text view

  @MainActor private var spikeControllerKey: UInt8 = 0

  extension EscriboTextView {

    /// The spike controller, installed lazily into the two TextKit 2 delegate slots
    /// `UITextView` leaves free (`textLayoutManager.delegate`, content-storage delegate).
    var spikeEmbeds: IOSBlockEmbedController {
      if let existing = objc_getAssociatedObject(textView, &spikeControllerKey)
        as? IOSBlockEmbedController
      {
        return existing
      }
      let controller = IOSBlockEmbedController(editor: self)
      objc_setAssociatedObject(
        textView, &spikeControllerKey, controller, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
      controller.install(on: textView, storage: documentStorage)
      // Rows 3–7: the `// SPIKE` hooks on the text view subclass (not the delegate, which
      // belongs to the SwiftUI bridge — `textViewDidChangeSelection` exists only there).
      textView.spikeSelectionFilter = { [weak controller] proposed, current in
        controller?.filterSelection(proposed, current: current) ?? proposed
      }
      textView.spikeEditFilter = { [weak controller] range, replacement in
        controller?.allowsEdit(in: range, replacement: replacement) ?? true
      }
      textView.spikeDeleteHandler = { [weak controller] in
        controller?.deleteSelectedEmbed() ?? false
      }
      textView.spikeAccessibilityElements = { [weak controller] in
        controller?.accessibilityElements() ?? []
      }
      return controller
    }
  }
#endif
