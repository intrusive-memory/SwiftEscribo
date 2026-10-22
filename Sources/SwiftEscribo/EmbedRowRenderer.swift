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

    /// De-emphasized subtitle runs (``EscriboEmbed/SubtitleRun/isDeEmphasized``): the base
    /// foreground, fainter than ``secondary``.
    var deEmphasized: EscriboColor = EscriboColor(white: 0, alpha: 0.35)

    /// The row's fill: the base foreground, faint, so it reads on the theme's background.
    var fill: EscriboColor = EscriboColor(white: 0, alpha: 0.06)

    init() {}

    init(theme: EscriboTheme) {
      let foreground = theme.base.foreground ?? .black
      title = foreground
      secondary = foreground.withAlphaMultiplied(by: 0.6)
      deEmphasized = foreground.withAlphaMultiplied(by: 0.35)
      fill = foreground.withAlphaMultiplied(by: 0.06)
    }
  }

  /// Where the parts of an embed row go: the one place the row's geometry is computed, so
  /// the renderer and the accessibility code cannot drift apart.
  ///
  /// All rectangles are in the coordinates of the `rect` passed in — the drawn rectangle,
  /// ``drawnRect(forRow:scale:)`` of the row.
  struct EmbedRowGeometry {
    var embed: EscriboEmbed
    var fontSpec: FontSpec
    var scale: CGFloat

    /// The badge's drawn parts.
    struct BadgeLayout {
      /// The capsule the badge is drawn on.
      var capsule: CGRect
      /// The badge's symbol.
      var symbol: CGRect
      /// Where the badge's word is drawn from.
      var wordOrigin: CGPoint
      /// The badge's word, in its font and tint.
      var word: NSAttributedString
    }

    /// The rectangle a row is drawn in: the row, less a little vertical breathing room.
    static func drawnRect(forRow row: CGRect, scale: CGFloat) -> CGRect {
      row.insetBy(dx: 0, dy: 2 * scale)
    }

    /// The inner padding, and the gap between the row's parts.
    var pad: CGFloat { 6 * scale }

    /// The corner radius of the row's fill.
    var radius: CGFloat { 6 * scale }

    /// The leading symbol's square.
    func icon(in rect: CGRect) -> CGRect {
      let side = max(0, rect.height - 2 * pad)
      return CGRect(x: rect.minX + pad, y: rect.minY + pad, width: side, height: side)
    }

    /// The height of each of the two text lines.
    func lineHeight(in rect: CGRect) -> CGFloat {
      (rect.height - 2 * pad) / 2
    }

    /// Where the text starts: after the leading symbol.
    func textLeft(in rect: CGRect) -> CGFloat {
      icon(in: rect).maxX + pad
    }

    /// The badge's parts, or `nil` when the embed has no badge or the row has no room for
    /// it (the capsule would reach the leading symbol).
    func badge(in rect: CGRect) -> BadgeLayout? {
      guard let badge = embed.badge else { return nil }
      let badgeFont = font(size: lineHeight(in: rect) * 0.7, bold: true)
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
      guard capsule.minX > textLeft(in: rect) else { return nil }
      return BadgeLayout(
        capsule: capsule,
        symbol: CGRect(
          x: capsule.minX + inner, y: capsule.midY - symbolSide / 2, width: symbolSide,
          height: symbolSide),
        wordOrigin: CGPoint(
          x: capsule.minX + inner + symbolSide + inner / 2, y: capsule.midY - wordSize.height / 2),
        word: word)
    }

    /// The frame of the embed's state element (``EscriboEmbed/StateElement``): the badge's
    /// capsule when one is drawn, else a square one text line tall at the row's trailing
    /// edge, vertically centred.
    func stateRect(in rect: CGRect) -> CGRect {
      if let badge = badge(in: rect) { return badge.capsule }
      let side = max(1, min(lineHeight(in: rect), rect.width))
      return CGRect(
        x: max(rect.minX, rect.maxX - pad - side), y: rect.midY - side / 2, width: side,
        height: side)
    }

    /// The theme's base face at `size` points, bold or not.
    func font(size: CGFloat, bold: Bool) -> PlatformFont {
      var spec = fontSpec
      spec.pointSize = Double(max(1, size))
      if bold { spec.traits.insert(.bold) }
      return FontResolver.font(for: spec)
    }
  }

  /// Draws one embed row: a rounded fill, the leading symbol, the title over the
  /// subtitle, and the trailing badge (its symbol and word, in the badge's tint).
  ///
  /// The row is two lines tall. The title sits on the first line and the subtitle on the
  /// second, each in the theme's base face at a slightly smaller size so both fit with
  /// the row's inner padding. The subtitle's runs are drawn in ``EmbedRowColors/secondary``,
  /// or ``EmbedRowColors/deEmphasized`` for a de-emphasized run, and truncate at the tail as
  /// one line. Where everything goes is ``EmbedRowGeometry``'s answer.
  struct EmbedRowRenderer {
    var embed: EscriboEmbed
    var colors: EmbedRowColors
    var fontSpec: FontSpec
    var scale: CGFloat

    var geometry: EmbedRowGeometry {
      EmbedRowGeometry(embed: embed, fontSpec: fontSpec, scale: scale)
    }

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

      let geometry = geometry
      let pad = geometry.pad
      fillRoundedRect(rect, radius: geometry.radius, color: colors.fill)

      // Leading symbol: square, as tall as the row's content area.
      drawSymbol(embed.symbolName, in: geometry.icon(in: rect), color: colors.secondary)
      let x = geometry.textLeft(in: rect)
      let lineHeight = geometry.lineHeight(in: rect)

      // Trailing badge: symbol + word in the tint, over a faint capsule of the same tint.
      var textRight = rect.maxX - pad
      if let badge = embed.badge, let layout = geometry.badge(in: rect) {
        fillRoundedRect(
          layout.capsule, radius: layout.capsule.height / 2,
          color: badge.tint.withAlphaMultiplied(by: 0.15))
        drawSymbol(badge.symbolName, in: layout.symbol, color: badge.tint)
        layout.word.draw(at: layout.wordOrigin)
        textRight = layout.capsule.minX - pad
      }

      let textWidth = max(0, textRight - x)
      guard textWidth > 0 else { return }
      NSAttributedString(
        string: embed.title,
        attributes: [
          .font: geometry.font(size: lineHeight * 0.8, bold: true),
          .foregroundColor: colors.title.platformColor,
          .paragraphStyle: Self.truncating,
        ]
      ).draw(in: CGRect(x: x, y: rect.minY + pad, width: textWidth, height: lineHeight))
      subtitle(fontSize: lineHeight * 0.7).draw(
        in: CGRect(x: x, y: rect.minY + pad + lineHeight, width: textWidth, height: lineHeight))
    }

    /// The subtitle line: every run in turn, each in its colour, one truncating paragraph.
    func subtitle(fontSize: CGFloat) -> NSAttributedString {
      let font = geometry.font(size: fontSize, bold: false)
      let line = NSMutableAttributedString()
      for run in embed.subtitleRuns {
        let color = run.isDeEmphasized ? colors.deEmphasized : colors.secondary
        line.append(
          NSAttributedString(
            string: run.text,
            attributes: [
              .font: font, .foregroundColor: color.platformColor,
              .paragraphStyle: Self.truncating,
            ]))
      }
      return line
    }

    /// Truncates at the tail: one line, ending in an ellipsis when it does not fit.
    private static var truncating: NSParagraphStyle {
      let style = NSMutableParagraphStyle()
      style.lineBreakMode = .byTruncatingTail
      return style
    }

    // MARK: - Platform primitives

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
