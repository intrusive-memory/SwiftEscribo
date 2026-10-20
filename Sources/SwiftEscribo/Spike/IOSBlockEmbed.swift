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
  /// Selection, delete and accessibility hooks for `UITextView` arrive in later sorties.
  @MainActor
  final class IOSBlockEmbedController: SpikeBlockEmbedController {}

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
      return controller
    }
  }
#endif
