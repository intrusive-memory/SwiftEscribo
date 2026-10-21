#if os(macOS) || os(iOS)
  import Foundation

  #if os(macOS)
    import AppKit
  #else
    import UIKit
  #endif

  /// The colours an embed row is drawn in, all taken from the editor's theme.
  struct EmbedRowColors: Equatable {

    /// The title: the theme's base foreground.
    var title: EscriboColor = .black

    /// The subtitle and the leading symbol: the base foreground, dimmed.
    var secondary: EscriboColor = EscriboColor(white: 0, alpha: 0.6)

    /// The row's fill: the base foreground, faint, so it reads on the theme's background.
    var fill: EscriboColor = EscriboColor(white: 0, alpha: 0.06)

    init() {}

    init(theme: EscriboTheme) {
      let foreground = theme.base.foreground ?? .black
      title = foreground
      secondary = foreground.withAlphaMultiplied(by: 0.6)
      fill = foreground.withAlphaMultiplied(by: 0.06)
    }
  }

  /// Draws one embed row: a rounded fill, the leading symbol, the title over the
  /// subtitle, and the trailing badge (its symbol and word, in the badge's tint).
  ///
  /// The row is two lines tall. The title sits on the first line and the subtitle on the
  /// second, each in the theme's base face at a slightly smaller size so both fit with
  /// the row's inner padding.
  struct EmbedRowRenderer {
    var embed: EscriboEmbed
    var colors: EmbedRowColors
    var fontSpec: FontSpec
    var scale: CGFloat

    /// Draws into `rect`, in `context`. `rect` is in the context's coordinates, top-left
    /// origin (a flipped context on macOS, as the text view is).
    func draw(in rect: CGRect, context: CGContext) {
      guard rect.width > 0, rect.height > 0 else { return }
      #if os(macOS)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
      #else
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
      #endif

      let radius = 6 * scale
      let pad = 6 * scale
      fillRoundedRect(rect, radius: radius, color: colors.fill)

      // Leading symbol: square, as tall as the row's content area.
      let iconSide = max(0, rect.height - 2 * pad)
      var x = rect.minX + pad
      drawSymbol(
        embed.symbolName, in: CGRect(x: x, y: rect.minY + pad, width: iconSide, height: iconSide),
        color: colors.secondary)
      x += iconSide + pad

      let lineHeight = (rect.height - 2 * pad) / 2
      let titleFont = font(size: lineHeight * 0.8, bold: true)
      let subtitleFont = font(size: lineHeight * 0.7, bold: false)

      // Trailing badge: symbol + word in the tint, over a faint capsule of the same tint.
      var textRight = rect.maxX - pad
      if let badge = embed.badge {
        let badgeFont = font(size: lineHeight * 0.7, bold: true)
        let word = NSAttributedString(
          string: badge.word,
          attributes: [.font: badgeFont, .foregroundColor: badge.tint.platformColor])
        let wordSize = word.size()
        let symbolSide = wordSize.height
        let inner = 4 * scale
        let width = inner + symbolSide + inner / 2 + wordSize.width + inner
        let height = wordSize.height + inner
        let capsule = CGRect(
          x: rect.maxX - pad - width, y: rect.midY - height / 2, width: width, height: height)
        if capsule.minX > x {
          fillRoundedRect(
            capsule, radius: height / 2, color: badge.tint.withAlphaMultiplied(by: 0.15))
          drawSymbol(
            badge.symbolName,
            in: CGRect(
              x: capsule.minX + inner, y: capsule.midY - symbolSide / 2, width: symbolSide,
              height: symbolSide),
            color: badge.tint)
          word.draw(
            at: CGPoint(
              x: capsule.minX + inner + symbolSide + inner / 2, y: capsule.midY - wordSize.height / 2))
          textRight = capsule.minX - pad
        }
      }

      let textWidth = max(0, textRight - x)
      guard textWidth > 0 else { return }
      let truncating = NSMutableParagraphStyle()
      truncating.lineBreakMode = .byTruncatingTail
      NSAttributedString(
        string: embed.title,
        attributes: [
          .font: titleFont, .foregroundColor: colors.title.platformColor,
          .paragraphStyle: truncating,
        ]
      ).draw(in: CGRect(x: x, y: rect.minY + pad, width: textWidth, height: lineHeight))
      NSAttributedString(
        string: embed.subtitle,
        attributes: [
          .font: subtitleFont, .foregroundColor: colors.secondary.platformColor,
          .paragraphStyle: truncating,
        ]
      ).draw(
        in: CGRect(x: x, y: rect.minY + pad + lineHeight, width: textWidth, height: lineHeight))
    }

    // MARK: - Platform primitives

    /// The theme's base face at `size` points, bold or not.
    private func font(size: CGFloat, bold: Bool) -> PlatformFont {
      var spec = fontSpec
      spec.pointSize = Double(max(1, size))
      if bold { spec.traits.insert(.bold) }
      return FontResolver.font(for: spec)
    }

    private func fillRoundedRect(_ rect: CGRect, radius: CGFloat, color: EscriboColor) {
      color.platformColor.setFill()
      #if os(macOS)
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
      #else
        UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
      #endif
    }

    /// Draws the SF Symbol `name` in `color`, fitted into `rect`. An unknown name draws
    /// nothing.
    private func drawSymbol(_ name: String, in rect: CGRect, color: EscriboColor) {
      guard rect.width > 0, rect.height > 0 else { return }
      #if os(macOS)
        guard
          let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [color.platformColor]))
        else { return }
        image.draw(
          in: fitted(image.size, in: rect), from: .zero, operation: .sourceOver, fraction: 1,
          respectFlipped: true, hints: nil)
      #else
        guard
          let image = UIImage(systemName: name)?
            .withTintColor(color.platformColor, renderingMode: .alwaysOriginal)
        else { return }
        image.draw(in: fitted(image.size, in: rect))
      #endif
    }

    /// `size` scaled to fit `rect`, aspect kept, centred.
    private func fitted(_ size: CGSize, in rect: CGRect) -> CGRect {
      guard size.width > 0, size.height > 0 else { return rect }
      let factor = min(rect.width / size.width, rect.height / size.height)
      let width = size.width * factor
      let height = size.height * factor
      return CGRect(
        x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }
  }
#endif
