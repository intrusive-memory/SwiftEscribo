import CoreGraphics
import EscriboCore
import Foundation

#if os(macOS)
  import AppKit

  /// The view the well's subviews are added to: the text view itself.
  typealias WellHostView = NSView
#elseif os(iOS)
  import UIKit

  /// The view the well's subviews are added to: the text view itself.
  typealias WellHostView = UIView
#endif

// MARK: - Geometry, supplied by the text view

/// The two layout facts the well needs, as closures (REQUIREMENTS-1.1.0 § 5.1).
///
/// The same seam as ``EditorCoordinator/utf16Offset``, for the same two reasons. Resolving a
/// block's line fragments needs TextKit **layout**, which the overlay has no business owning.
/// And forcing layout on a text view inside a test process is not safe — so a test supplies
/// literal rects here and the reconciliation that adds and removes subviews runs against
/// them, while production supplies ``lineFragmentRects(in:utf16Range:origin:)``.
struct WellGeometry {

  /// The x of the text container's leading edge, in text-view coordinates.
  var textEdge: () -> CGFloat

  /// Every line fragment of the text in a UTF-16 range, in text-view coordinates, top to
  /// bottom. Empty when the range has no layout.
  var lineFragmentRects: (Range<Int>) -> [CGRect]

  /// Geometry with no layout: every block has no fragments, so nothing is ever placed.
  static var none: WellGeometry {
    WellGeometry(textEdge: { 0 }, lineFragmentRects: { _ in [] })
  }

  /// The line fragments of `utf16Range` from TextKit 2, offset by the container `origin`.
  ///
  /// Walks layout fragments — one per source paragraph — from the range's start until one
  /// begins at or past its end, and yields each fragment's text line fragments: a
  /// hard-wrapped block is several layout fragments, and a soft-wrapped line is several text
  /// line fragments, and the span bar must cover both. `.ensuresLayout` because a well is
  /// only ever asked for beside text the pointer, the caret, or playback is on, so this lays
  /// out a few paragraphs, not the document.
  @MainActor
  static func lineFragmentRects(
    in textLayoutManager: NSTextLayoutManager?, utf16Range: Range<Int>, origin: CGPoint
  ) -> [CGRect] {
    guard let textLayoutManager,
      let storage = textLayoutManager.textContentManager as? NSTextContentStorage
    else { return [] }
    let documentStart = storage.documentRange.location
    guard let start = storage.location(documentStart, offsetBy: utf16Range.lowerBound),
      let end = storage.location(documentStart, offsetBy: utf16Range.upperBound)
    else { return [] }

    var rects: [CGRect] = []
    _ = textLayoutManager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) {
      fragment in
      if !rects.isEmpty, fragment.rangeInElement.location.compare(end) != .orderedAscending {
        return false
      }
      let frame = fragment.layoutFragmentFrame
      let lines = fragment.textLineFragments
      if lines.isEmpty {
        rects.append(frame.offsetBy(dx: origin.x, dy: origin.y))
      } else {
        for line in lines {
          rects.append(
            line.typographicBounds.offsetBy(dx: frame.minX + origin.x, dy: frame.minY + origin.y))
        }
      }
      return true
    }
    return rects
  }
}

// MARK: - The overlay

/// Draws the paragraph well as real subviews of the text view and tracks what should show
/// (REQUIREMENTS-1.1.0 § 5.1, § 5.2).
///
/// ## Division of labour
///
/// ``WellTracker`` decides which wells show; ``WellPlacement`` decides where; this type only
/// **reconciles** — it turns the tracker's presentations into subviews, adding the ones
/// that are missing, moving the ones that remain, and removing the rest. Every input it
/// reads is a closure or a value a test can supply: the clock, Reduce Motion, the geometry,
/// and the block lookups. So the one piece of this feature that must touch real views can be
/// exercised on a text view that is never laid out.
///
/// ## Subviews of the text view
///
/// The well's views are added to the text view itself, not to a sibling overlay, so they
/// scroll with the text for free and share the layout manager's coordinate space: a line
/// fragment's rect *is* the rect to place beside, with no conversion.
///
/// An `NSObject` because the button's target and the iOS hover recognizer's target must be
/// one.
@MainActor
final class WellOverlay: NSObject {

  /// The text view the well draws into.
  weak var host: WellHostView?

  /// The well, as last applied.
  private(set) var well: EscriboWell?

  /// The state machine.
  private(set) var tracker = WellTracker()

  /// The line-fragment and text-edge seam. ``WellGeometry/none`` until a text view installs
  /// its own.
  var geometry: WellGeometry = .none

  /// The clock every event is stamped with.
  var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

  /// Whether the viewer has Reduce Motion on.
  var reduceMotion: () -> Bool = { false }

  /// The lane width currently reserved. No lane — iOS at compact width — means no well.
  var laneWidth: () -> CGFloat = { 0 }

  /// The block under a point in text-view coordinates.
  var blockAtPoint: (CGPoint) -> EscriboBlock? = { _ in nil }

  /// The block containing a UTF-16 offset.
  var blockAtOffset: (Int) -> EscriboBlock? = { _ in nil }

  /// The caret's UTF-16 offset when the editor is first responder with an insertion point,
  /// or `nil`. Only iOS installs one: Caret is a touch state.
  var caretOffset: () -> Int? = { nil }

  /// Called when a well button is activated.
  var onAction: (EscriboWellItem, EscriboBlock) -> Void = { _, _ in }

  /// Whether a timer is scheduled for the tracker's next deadline. Tests turn it off and
  /// step the clock themselves.
  var schedulesTicks = true

  /// The views on screen, one slot per block.
  private(set) var slots: [EscriboBlock.ID: WellSlot] = [:]

  private var tickTask: Task<Void, Never>?
  private var isLayoutReconcilePending = false

  override init() {
    super.init()
  }

  // MARK: Inputs

  /// Stores `well`, feeds any change of active block to the tracker, and reconciles.
  func apply(_ well: EscriboWell?) {
    self.well = well
    guard let well else {
      tracker = WellTracker()
      removeAllSlots()
      return
    }
    tracker.activeBlockChanged(to: well.activeBlock, at: now())
    reconcile()
  }

  /// The pointer moved to `point` in text-view coordinates, or left the view (`nil`).
  ///
  /// The block must be eligible and the point must be inside the block's vertical band.
  /// The second check matters below the last line: closest-position resolves a point in the
  /// empty space under the text to the last block, and a well there would follow a pointer
  /// that is nowhere near it.
  func pointerMoved(to point: CGPoint?) {
    guard well != nil else { return }
    tracker.pointerMoved(over: point.flatMap { eligibleBlockID(at: $0) }, at: now())
    reconcile()
  }

  /// A key was typed.
  func typed() {
    guard well != nil else { return }
    tracker.typed(at: now())
    reconcile()
  }

  /// A drag-selection began.
  func dragBegan() {
    guard well != nil else { return }
    tracker.dragBegan(at: now())
    reconcile()
  }

  /// A drag-selection ended.
  func dragEnded() {
    guard well != nil else { return }
    tracker.dragEnded(at: now())
    reconcile()
  }

  /// The selection or the first-responder status changed.
  func caretChanged() {
    guard let well else { return }
    let block = caretOffset()
      .flatMap { blockAtOffset($0) }
      .flatMap { well.isEligible($0) ? $0 : nil }
    tracker.caretMoved(to: block?.id, at: now())
    reconcile()
  }

  /// The text view's size changed, so every placed well may be in the wrong place.
  ///
  /// Deferred to the next main-actor turn rather than reconciled inline: this is called from
  /// inside the text view's own resize, and asking TextKit for layout from there would lay
  /// out against a frame that is still changing.
  func layoutDidChange() {
    guard !slots.isEmpty, !isLayoutReconcilePending else { return }
    isLayoutReconcilePending = true
    Task { @MainActor [weak self] in
      guard let self else { return }
      self.isLayoutReconcilePending = false
      self.reconcile()
    }
  }

  @objc func wellButtonPressed(_ sender: WellButton) {
    guard let block = sender.block else { return }
    onAction(sender.item, block)
  }

  #if os(iOS)
    /// The iPad pointer, delivered by a hover recognizer on the text view.
    @objc func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
      switch recognizer.state {
      case .began, .changed:
        pointerMoved(to: recognizer.location(in: recognizer.view))
      default:
        pointerMoved(to: nil)
      }
    }
  #endif

  // MARK: Reconciliation

  /// Makes the subviews match the tracker at the current time.
  func reconcile() {
    guard let host, let well, laneWidth() > 0 else {
      removeAllSlots()
      return
    }
    let time = now()
    tracker.advance(to: time)
    let textEdge = geometry.textEdge()
    let lane = laneWidth()

    var kept = Set<EscriboBlock.ID>()
    for presentation in tracker.presentations(at: time) {
      // Ineligible blocks show nothing (rule 5) — checked here as well as at the pointer,
      // because the host's active block is not filtered on its way in.
      guard let block = blockWithID(presentation.block), well.isEligible(block) else { continue }
      let fragments = geometry.lineFragmentRects(block.range)
      guard let firstLine = fragments.first,
        let blockRect = WellPlacement.blockRect(enclosing: fragments)
      else { continue }
      let isPlaying = presentation.role == .playing
      let items = well.items.filter {
        WellPlacement.symbolName(for: $0, isPlaying: isPlaying) != nil
      }
      guard !items.isEmpty else { continue }

      let existing = slots[block.id]
      let slot = existing ?? WellSlot()
      if existing == nil {
        slots[block.id] = slot
        host.addSubview(slot.bar)
      }
      slot.bar.frame = WellPlacement.spanBarFrame(blockRect: blockRect, textEdge: textEdge)
      slot.bar.style(isAccent: isPlaying || presentation.role == .finished)

      slot.setItems(items, in: host, target: self)
      for (index, button) in slot.buttons.enumerated() {
        button.block = block
        button.frame = WellPlacement.buttonFrame(
          slot: index, firstLineFragment: firstLine, textEdge: textEdge, laneWidth: lane,
          platform: .current)
        button.style(isPlaying: isPlaying)
      }

      if existing == nil {
        let fades = presentation.role == .hover || presentation.role == .caret
        slot.appear(
          fadeDuration: fades ? WellTiming.fadeInDuration(reduceMotion: reduceMotion()) : 0)
      }
      kept.insert(block.id)
    }

    for id in Array(slots.keys) where !kept.contains(id) {
      slots[id]?.remove()
      slots[id] = nil
    }
    scheduleTick()
  }

  /// The block with `id`, if it still exists: block IDs are offsets, so an edit can leave an
  /// ID that now names the middle of some other block.
  private func blockWithID(_ id: EscriboBlock.ID) -> EscriboBlock? {
    guard let block = blockAtOffset(id.offset), block.id == id else { return nil }
    return block
  }

  private func eligibleBlockID(at point: CGPoint) -> EscriboBlock.ID? {
    guard let well, let block = blockAtPoint(point), well.isEligible(block) else { return nil }
    guard let band = WellPlacement.blockRect(enclosing: geometry.lineFragmentRects(block.range)),
      point.y >= band.minY, point.y <= band.maxY
    else { return nil }
    return block.id
  }

  private func removeAllSlots() {
    for slot in slots.values { slot.remove() }
    slots = [:]
    tickTask?.cancel()
    tickTask = nil
  }

  /// One timer, for the tracker's next deadline, replacing any earlier one.
  private func scheduleTick() {
    tickTask?.cancel()
    tickTask = nil
    guard schedulesTicks, let deadline = tracker.nextDeadline else { return }
    let delay = max(0, deadline - now())
    tickTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(delay))
      guard !Task.isCancelled else { return }
      self?.reconcile()
    }
  }
}

// MARK: - One block's views

/// The span bar and buttons for one block.
@MainActor
final class WellSlot {

  let bar = WellSpanBar(frame: .zero)
  private(set) var buttons: [WellButton] = []

  /// Rebuilds the buttons when the well's items changed; otherwise leaves them alone, so a
  /// playback update every word does not churn subviews.
  func setItems(_ items: [EscriboWellItem], in host: WellHostView, target: WellOverlay) {
    guard buttons.map({ $0.item }) != items else { return }
    for button in buttons { button.removeFromSuperview() }
    buttons = items.map { item in
      let button = WellButton(frame: .zero)
      button.configure(item: item, target: target)
      host.addSubview(button)
      return button
    }
  }

  func appear(fadeDuration: TimeInterval) {
    let views: [WellHostView] = [bar as WellHostView] + buttons.map { $0 as WellHostView }
    guard fadeDuration > 0 else {
      for view in views { view.setWellAlpha(1) }
      return
    }
    for view in views { view.setWellAlpha(0) }
    #if os(macOS)
      NSAnimationContext.runAnimationGroup { context in
        context.duration = fadeDuration
        for view in views { view.animator().alphaValue = 1 }
      }
    #else
      UIView.animate(withDuration: fadeDuration) {
        for view in views { view.alpha = 1 }
      }
    #endif
  }

  func remove() {
    bar.removeFromSuperview()
    for button in buttons { button.removeFromSuperview() }
  }
}

extension WellHostView {
  fileprivate func setWellAlpha(_ value: CGFloat) {
    #if os(macOS)
      alphaValue = value
    #else
      alpha = value
    #endif
  }
}

// MARK: - The views

#if os(macOS)

  /// The span bar. A type of its own so it can be found among the text view's subviews.
  final class WellSpanBar: NSView {

    func style(isAccent: Bool) {
      wantsLayer = true
      layer?.cornerRadius = WellPlacement.spanBarWidth / 2
      layer?.backgroundColor =
        (isAccent ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).cgColor
    }
  }

  /// A well button: borderless, a 10 pt semibold symbol, a quaternary fill on hover, and the
  /// arrow cursor — macOS buttons do not take the pointing hand, and the text view's I-beam
  /// would otherwise show over it.
  final class WellButton: NSButton {

    /// The item this button acts on.
    private(set) var item: EscriboWellItem = .readAloud

    /// The block this button acts on, refreshed on every reconciliation.
    var block: EscriboBlock?

    private var showsStop: Bool?
    private var hoverArea: NSTrackingArea?

    func configure(item: EscriboWellItem, target: WellOverlay) {
      self.item = item
      title = ""
      isBordered = false
      imagePosition = .imageOnly
      wantsLayer = true
      layer?.cornerRadius = 5
      self.target = target
      action = #selector(WellOverlay.wellButtonPressed(_:))
      setAccessibilityIdentifier(WellPlacement.accessibilityIdentifier(for: item))
    }

    func style(isPlaying: Bool) {
      guard showsStop != isPlaying,
        let name = WellPlacement.symbolName(for: item, isPlaying: isPlaying)
      else { return }
      showsStop = isPlaying
      let label = isPlaying ? "Stop" : "Read Aloud"
      image = NSImage(systemSymbolName: name, accessibilityDescription: label)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
      contentTintColor = isPlaying ? .controlAccentColor : .tertiaryLabelColor
      setAccessibilityLabel(label)
    }

    override func updateTrackingAreas() {
      super.updateTrackingAreas()
      if let hoverArea { removeTrackingArea(hoverArea) }
      let area = NSTrackingArea(
        rect: .zero,
        options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
        owner: self, userInfo: nil)
      addTrackingArea(area)
      hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
      super.mouseEntered(with: event)
      layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
    }

    override func mouseExited(with event: NSEvent) {
      super.mouseExited(with: event)
      layer?.backgroundColor = nil
    }

    override func cursorUpdate(with event: NSEvent) {
      NSCursor.arrow.set()
    }

    override func resetCursorRects() {
      addCursorRect(bounds, cursor: .arrow)
    }
  }

#elseif os(iOS)

  /// The span bar. A type of its own so it can be found among the text view's subviews.
  final class WellSpanBar: UIView {

    func style(isAccent: Bool) {
      layer.cornerRadius = WellPlacement.spanBarWidth / 2
      backgroundColor = isAccent ? .tintColor : .tertiaryLabel
    }
  }

  /// A well button: a 44 pt hit area around a 17 pt symbol, with the system pointer effect.
  final class WellButton: UIButton {

    /// The item this button acts on.
    private(set) var item: EscriboWellItem = .readAloud

    /// The block this button acts on, refreshed on every reconciliation.
    var block: EscriboBlock?

    private var showsStop: Bool?

    func configure(item: EscriboWellItem, target: WellOverlay) {
      self.item = item
      isPointerInteractionEnabled = true
      addTarget(
        target, action: #selector(WellOverlay.wellButtonPressed(_:)), for: .primaryActionTriggered)
      accessibilityIdentifier = WellPlacement.accessibilityIdentifier(for: item)
    }

    func style(isPlaying: Bool) {
      guard showsStop != isPlaying,
        let name = WellPlacement.symbolName(for: item, isPlaying: isPlaying)
      else { return }
      showsStop = isPlaying
      setImage(
        UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17)),
        for: .normal)
      tintColor = isPlaying ? .tintColor : .tertiaryLabel
      accessibilityLabel = isPlaying ? "Stop" : "Read Aloud"
    }
  }

#endif

// MARK: - Installing the well on a text view

extension EscriboTextView {

  /// Connects ``wellOverlay`` to this editor's text view and coordinator.
  ///
  /// Called once, from the initializer, on both platforms. Everything the overlay reads
  /// from the live editor is set here as a closure, which is what lets a test replace any
  /// one of them — the geometry above all — without a subclass.
  func installWellOverlay() {
    let overlay = wellOverlay
    let textView = self.textView
    let coordinator = self.coordinator

    overlay.host = textView
    textView.wellOverlay = overlay
    overlay.blockAtPoint = { [weak coordinator] point in coordinator?.block(at: point) }
    overlay.blockAtOffset = { [weak coordinator] offset in
      coordinator?.block(atUTF16Offset: offset)
    }
    overlay.laneWidth = { [weak self] in self?.wellLaneWidth ?? 0 }
    overlay.onAction = { [weak self] item, block in self?.onWellAction(item, block) }

    #if os(macOS)
      overlay.geometry = WellGeometry(
        textEdge: { [weak textView] in textView?.textContainerOrigin.x ?? 0 },
        lineFragmentRects: { [weak textView] range in
          guard let textView else { return [] }
          return WellGeometry.lineFragmentRects(
            in: textView.textLayoutManager, utf16Range: range, origin: textView.textContainerOrigin)
        })
      overlay.reduceMotion = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    #else
      overlay.geometry = WellGeometry(
        textEdge: { [weak textView] in textView?.textContainerInset.left ?? 0 },
        lineFragmentRects: { [weak textView] range in
          guard let textView else { return [] }
          let inset = textView.textContainerInset
          return WellGeometry.lineFragmentRects(
            in: textView.textLayoutManager, utf16Range: range,
            origin: CGPoint(x: inset.left, y: inset.top))
        })
      overlay.reduceMotion = { UIAccessibility.isReduceMotionEnabled }
      overlay.caretOffset = { [weak textView] in
        guard let textView, textView.isFirstResponder else { return nil }
        let selection = textView.selectedRange
        return selection.length == 0 ? selection.location : nil
      }
      textView.addGestureRecognizer(
        UIHoverGestureRecognizer(target: overlay, action: #selector(WellOverlay.hoverChanged(_:))))
    #endif
  }
}
