import CoreGraphics
import Foundation
import QuartzCore

#if os(macOS)
  import AppKit
#elseif os(iOS)
  import UIKit
#endif

// MARK: - The seam

/// The three things the spoken-word highlight needs from a text view, as closures.
///
/// The same seam shape as ``WellGeometry``: production draws through TextKit 2, a test
/// records the calls. Keeping the bounds check and the remove-before-add bookkeeping on the
/// overlay's side of this seam means the part that can go wrong — a stale range after an
/// edit, a highlight left behind — is exercised without asking a text view for anything.
struct WellHighlightRenderer {

  /// The document's length in UTF-16 code units, as the backing store counts it now.
  var documentLength: () -> Int

  /// Draws the highlight over a range already known to be inside the document.
  var add: (NSRange) -> Void

  /// Removes the highlight from a range already known to be inside the document.
  var remove: (NSRange) -> Void

  /// A renderer that draws nothing, for an overlay no text view has installed.
  static var none: WellHighlightRenderer {
    WellHighlightRenderer(documentLength: { 0 }, add: { _ in }, remove: { _ in })
  }
}

// MARK: - The rules

/// The spoken-word highlight (REQUIREMENTS-1.1.0 § 5.2 Playing, D-7).
///
/// ## A view placed from TextKit's geometry, never a character attribute
///
/// The highlight is a ``WellHighlightView`` — one accent-tinted view, a sublayer per line
/// segment of the word — that the overlay positions over the glyphs using TextKit 2's
/// segment geometry, the same source ``WellGeometry`` places the span bar from.
///
/// It is **not** a background-colour attribute on the text storage: the storage is the
/// document (Architecture §1), and an attribute written there would be clobbered by the next
/// restyle, would mark the document edited, would register with undo, and would ride along
/// into a copy. ``WellHighlightRenderer/documentLength`` and the remove-before-add
/// bookkeeping in ``WellOverlay/updateHighlight(_:)`` keep that invariant testable.
///
/// It is also **not** a `.backgroundColor` *rendering* attribute on the text layout manager,
/// which is what 1.1.0 rc.1 shipped and why nothing lit up. A layer-backed `NSTextView` on
/// the TextKit 2 stack paints its fragments through a path that honours rendering attributes
/// for glyph drawing but never paints their backgrounds on screen — measured 2026-10-05: the
/// attribute was on the manager over the right range, a forced `draw(_:)` painted it, and the
/// composited window never did, through `needsDisplay`, `invalidateLayout(for:)`,
/// `invalidateRenderingAttributes(for:)` and a viewport relayout alike. A view is drawn by the
/// view system, so it cannot be skipped the same way.
enum WellHighlight {

  /// The highlight's opacity over the accent colour: enough to find the word at a glance,
  /// little enough that the word stays readable through it.
  static let opacity: CGFloat = 0.25

  /// `range` if it can be drawn in a document of `documentLength` UTF-16 units, else `nil`.
  ///
  /// A range the host reports can be stale: the writer may edit while the engine speaks
  /// text it captured earlier. A range that runs past the end is **dropped**, not clamped —
  /// clamped, it would highlight whatever text now sits there, which is a word nobody is
  /// saying. An empty range has nothing to highlight.
  static func drawableRange(_ range: NSRange?, documentLength: Int) -> NSRange? {
    guard let range, range.location != NSNotFound,
      range.location >= 0, range.length > 0,
      range.location <= documentLength, range.length <= documentLength - range.location
    else { return nil }
    return range
  }

  /// The part of a previously drawn `range` still inside a document of `documentLength`
  /// units, or `nil` when none of it is.
  ///
  /// Removal clamps where drawing drops: what matters when removing is that no highlight
  /// survives, and the part of an old range that is still inside the document is exactly
  /// where one could.
  static func removableRange(_ range: NSRange, documentLength: Int) -> NSRange? {
    guard range.location != NSNotFound, range.location >= 0, documentLength > 0 else {
      return nil
    }
    let start = Swift.min(range.location, documentLength)
    let end = Swift.min(range.location + Swift.max(range.length, 0), documentLength)
    guard end > start else { return nil }
    return NSRange(location: start, length: end - start)
  }

  /// `range` as a TextKit 2 text range in `textLayoutManager`'s content storage, or `nil`
  /// when there is no content storage or either end falls outside the document.
  ///
  /// Walks from the document's start by UTF-16 offset — the same conversion
  /// ``WellGeometry/lineFragmentRects(in:utf16Range:origin:)`` uses, because
  /// `NSTextContentStorage` counts locations in the backing string's UTF-16 units.
  @MainActor
  static func textRange(for range: NSRange, in textLayoutManager: NSTextLayoutManager?)
    -> NSTextRange?
  {
    guard let storage = textLayoutManager?.textContentManager as? NSTextContentStorage else {
      return nil
    }
    let documentStart = storage.documentRange.location
    guard let start = storage.location(documentStart, offsetBy: range.location),
      let end = storage.location(documentStart, offsetBy: range.location + range.length)
    else { return nil }
    return NSTextRange(location: start, end: end)
  }

  /// The rectangles the glyphs of `range` occupy, in text-view coordinates: one per line
  /// segment, so a word that soft-wraps gets two. Empty when the range cannot be resolved.
  ///
  /// `.standard` segments are the glyph boxes TextKit draws selection with, so the highlight
  /// sits exactly where a selection of the word would. `ensureLayout` first: playback can
  /// reach a word before the viewport has laid its paragraph out, and an unlaid range has no
  /// segments at all.
  @MainActor
  static func segmentRects(
    for range: NSRange, in textLayoutManager: NSTextLayoutManager?, origin: CGPoint
  ) -> [CGRect] {
    guard let textLayoutManager, let span = textRange(for: range, in: textLayoutManager)
    else { return [] }
    textLayoutManager.ensureLayout(for: span)
    var rects: [CGRect] = []
    textLayoutManager.enumerateTextSegments(in: span, type: .standard, options: []) { _, frame, _, _ in
      if !frame.isEmpty {
        rects.append(frame.offsetBy(dx: origin.x, dy: origin.y))
      }
      return true
    }
    return rects
  }

  /// The accent colour at ``opacity``.
  static var color: PlatformColor {
    #if os(macOS)
      return NSColor.controlAccentColor.withAlphaComponent(opacity)
    #else
      return UIColor.tintColor.withAlphaComponent(opacity)
    #endif
  }

  /// The production renderer: a ``WellHighlightView`` among the text view's subviews, placed
  /// from ``segmentRects(for:in:origin:)``, bounded by the text storage's length.
  ///
  /// `add` is idempotent — it moves the one view rather than stacking another — so
  /// ``WellOverlay/layoutDidChange()`` can call it again after a resize to put the highlight
  /// back over glyphs that moved. A range that resolves to no segments shows nothing rather
  /// than a stale box.
  @MainActor
  static func renderer(for textView: EscriboNativeTextView) -> WellHighlightRenderer {
    let view = WellHighlightView(frame: .zero)
    return WellHighlightRenderer(
      documentLength: { [weak textView] in
        guard let textView else { return 0 }
        #if os(macOS)
          return textView.textStorage?.length ?? 0
        #else
          return textView.textStorage.length
        #endif
      },
      add: { [weak textView] range in
        guard let textView else { return }
        let rects = segmentRects(
          for: range, in: textView.textLayoutManager, origin: Self.containerOrigin(of: textView))
        guard !rects.isEmpty else {
          view.removeFromSuperview()
          return
        }
        if view.superview !== textView {
          // Beneath the slots, so a word under the span bar's lane edge never covers a button.
          #if os(macOS)
            textView.addSubview(view, positioned: .below, relativeTo: nil)
          #else
            textView.insertSubview(view, at: 0)
          #endif
        }
        view.render(rects: rects)
      },
      remove: { _ in
        view.removeFromSuperview()
      })
  }

  /// Where the text container's origin is, in the text view's coordinates — what every
  /// TextKit frame must be offset by to become a subview frame.
  @MainActor
  static func containerOrigin(of textView: EscriboNativeTextView) -> CGPoint {
    #if os(macOS)
      return textView.textContainerOrigin
    #else
      let inset = textView.textContainerInset
      return CGPoint(x: inset.left, y: inset.top)
    #endif
  }
}

// MARK: - The view

/// The highlight on screen: one view whose frame is the union of the word's segment rects,
/// with a sublayer per segment. A type of its own so a test can find it among the text
/// view's subviews and read ``rects`` back.
///
/// Not an accessibility element and never hit-testable: it is drawing, and the text under it
/// must keep receiving the pointer.
#if os(macOS)
  final class WellHighlightView: NSView {

    /// The segment rectangles last rendered, in the text view's coordinates.
    private(set) var rects: [CGRect] = []

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
      super.init(frame: frame)
      wantsLayer = true
      setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func render(rects: [CGRect]) {
      self.rects = rects
      let union = rects.reduce(CGRect.null) { $0.union($1) }
      frame = union
      WellHighlight.layoutSegmentLayers(on: layer, rects: rects, origin: union.origin)
    }
  }
#else
  final class WellHighlightView: UIView {

    /// The segment rectangles last rendered, in the text view's coordinates.
    private(set) var rects: [CGRect] = []

    override init(frame: CGRect) {
      super.init(frame: frame)
      isUserInteractionEnabled = false
      isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { nil }

    func render(rects: [CGRect]) {
      self.rects = rects
      let union = rects.reduce(CGRect.null) { $0.union($1) }
      frame = union
      WellHighlight.layoutSegmentLayers(on: layer, rects: rects, origin: union.origin)
    }
  }
#endif

extension WellHighlight {

  /// One accent sublayer per segment, positioned relative to `origin`, reusing layers so a
  /// word-per-word update does not churn them. Rounded like a selection, not like a bar.
  @MainActor
  static func layoutSegmentLayers(on layer: CALayer?, rects: [CGRect], origin: CGPoint) {
    guard let layer else { return }
    var sublayers = layer.sublayers ?? []
    while sublayers.count < rects.count {
      let segment = CALayer()
      segment.cornerRadius = 2
      layer.addSublayer(segment)
      sublayers.append(segment)
    }
    while sublayers.count > rects.count {
      sublayers.removeLast().removeFromSuperlayer()
    }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for (segment, rect) in zip(sublayers, rects) {
      segment.backgroundColor = color.cgColor
      segment.frame = rect.offsetBy(dx: -origin.x, dy: -origin.y)
    }
    CATransaction.commit()
  }
}
