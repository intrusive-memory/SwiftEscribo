import CoreGraphics
import Foundation

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
/// ## A rendering attribute, never a character attribute
///
/// The highlight is drawn with a TextKit 2 **rendering attribute** on the text layout
/// manager, not with a background-colour attribute on the text storage. The storage is the
/// document (Architecture §1): an attribute written there would be clobbered by the next
/// restyle, would mark the document edited, would register with undo, and would ride along
/// into a copy. A rendering attribute is drawing state only — the same class of thing as the
/// spelling underline — so none of that can happen.
///
/// Only `.backgroundColor` is added and removed. `setRenderingAttributes(_:for:)` would
/// replace *every* rendering attribute over the word, spelling state included.
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

  /// The accent colour at ``opacity``.
  static var color: PlatformColor {
    #if os(macOS)
      return NSColor.controlAccentColor.withAlphaComponent(opacity)
    #else
      return UIColor.tintColor.withAlphaComponent(opacity)
    #endif
  }

  /// The production renderer: `.backgroundColor` rendering attributes on the text view's
  /// `textLayoutManager`, bounded by its text storage's length.
  @MainActor
  static func renderer(for textView: EscriboNativeTextView) -> WellHighlightRenderer {
    WellHighlightRenderer(
      documentLength: { [weak textView] in
        guard let textView else { return 0 }
        #if os(macOS)
          return textView.textStorage?.length ?? 0
        #else
          return textView.textStorage.length
        #endif
      },
      add: { [weak textView] range in
        guard let manager = textView?.textLayoutManager,
          let span = WellHighlight.textRange(for: range, in: manager)
        else { return }
        manager.addRenderingAttribute(.backgroundColor, value: WellHighlight.color, for: span)
      },
      remove: { [weak textView] range in
        guard let manager = textView?.textLayoutManager,
          let span = WellHighlight.textRange(for: range, in: manager)
        else { return }
        manager.removeRenderingAttribute(.backgroundColor, for: span)
      })
  }
}
