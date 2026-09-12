import CoreGraphics
import EscriboCore
import Foundation

// MARK: - Timing

/// The paragraph well's three durations (REQUIREMENTS-1.1.0 § 5.2).
///
/// Named constants rather than literals scattered through the view code so that the state
/// machine, the view that animates it, and the tests that pin it all read the same number.
enum WellTiming {

  /// The fade-in when a hover or caret well appears.
  static let fadeIn: TimeInterval = 0.12

  /// How long a hover well outlives the pointer leaving its block (rule 1). Long enough for
  /// the pointer to cross whitespace on its way to the button without the button vanishing.
  static let leaveHysteresis: TimeInterval = 0.15

  /// How long a finished block's well holds before returning to Hover or Rest.
  static let finishedHold: TimeInterval = 0.4

  /// The fade-in to animate, given the viewer's Reduce Motion setting (rule 4): none at all
  /// when motion is reduced, so the well simply appears.
  static func fadeInDuration(reduceMotion: Bool) -> TimeInterval {
    reduceMotion ? 0 : fadeIn
  }

  /// How long the span bar's fill takes to catch up with a new ``EscriboWell/progress``.
  ///
  /// A host reports progress about once a word. Jumping the fill that often reads as a
  /// stutter; easing each step over a little less than a typical word's duration reads as
  /// one continuous descent, and never leaves the fill lagging a whole word behind.
  static let progressStep: TimeInterval = 0.2
}

// MARK: - Progress

/// The host's ``EscriboWell/progress``, made safe to draw.
enum WellProgress {

  /// `progress` clamped to `0…1`, or `nil` when the host reports none.
  ///
  /// A speech engine's arithmetic is not this package's to trust: a character offset
  /// divided by a length that has just changed can land below zero, above one, or on NaN.
  /// NaN is drawn as `0` — no progress claimed — and is handled explicitly because
  /// `min`/`max` pass a NaN straight through.
  static func clamped(_ progress: Double?) -> Double? {
    guard let progress else { return nil }
    guard !progress.isNaN else { return 0 }
    return Swift.min(Swift.max(progress, 0), 1)
  }
}

// MARK: - The state machine

/// The paragraph well's state machine (REQUIREMENTS-1.1.0 § 5.2), as a pure value.
///
/// ## Why a value with explicit timestamps
///
/// Every rule in § 5.2 that is hard to get right is a rule about **time**: a 150 ms
/// hysteresis on leave, a 400 ms Finished hold, a fade. Written against timers, each of
/// those is testable only by sleeping, and a test that sleeps is a test that flakes. So
/// every event carries the time it happened, nothing here reads a clock, and "what is
/// showing" is a function of the state *and a moment*. The view owns the clock and one
/// timer that fires at ``nextDeadline``; the tests own neither and step time by hand.
///
/// It also keeps the view out of the rules. The text view that hosts the well must not be
/// laid out by a test, so everything that decides *whether* a well shows lives here, where
/// no text view exists.
///
/// ## States
///
/// Rest is the empty presentation list. Hover, Caret, Playing, and Finished are the roles a
/// ``Presentation`` can carry, and several can be showing at once for *different* blocks —
/// that is rule 3, which keeps the playing block's well pinned while another block is
/// hovered.
struct WellTracker: Equatable {

  /// The role a visible well is playing.
  enum Role: Equatable, Sendable {
    /// The pointer is in the block's vertical band.
    case hover
    /// The editor is first responder and its caret is in the block (touch).
    case caret
    /// The host reports this block as the active one.
    case playing
    /// The block just stopped being active and is holding before returning to Hover or Rest.
    case finished
  }

  /// One well that should be on screen.
  struct Presentation: Equatable, Sendable {
    let block: EscriboBlock.ID
    let role: Role
  }

  /// The eligible block the pointer was last over, whether or not it is currently shown.
  private(set) var hoverBlock: EscriboBlock.ID?

  /// When ``hoverBlock`` stops showing because the pointer left it, or `nil` while the
  /// pointer is still inside.
  private(set) var hoverHidesAt: TimeInterval?

  /// The eligible block holding the caret, or `nil`.
  private(set) var caretBlock: EscriboBlock.ID?

  /// Set by a keystroke and cleared by the next pointer move — the well's version of
  /// `NSCursor.setHiddenUntilMouseMoves` (rule 2).
  private(set) var isHiddenByTyping = false

  /// Set for the duration of a drag-selection (rule 2).
  private(set) var isDragging = false

  /// The host's active block.
  private(set) var activeBlock: EscriboBlock.ID?

  /// The block whose playback just ended, while it holds.
  private(set) var finishedBlock: EscriboBlock.ID?

  /// When ``finishedBlock`` stops holding.
  private(set) var finishedEndsAt: TimeInterval?

  // MARK: Events

  /// The pointer moved. `block` is the **eligible** block whose vertical band it is in, or
  /// `nil` for none — an ineligible block and empty space are the same thing to the well.
  ///
  /// Moving straight into another block switches at once: the hysteresis protects a trip
  /// *out of* a block, not a trip into the next one, and two hover wells at once would say
  /// two blocks are under one pointer.
  mutating func pointerMoved(over block: EscriboBlock.ID?, at now: TimeInterval) {
    advance(to: now)
    isHiddenByTyping = false
    if let block {
      hoverBlock = block
      hoverHidesAt = nil
    } else if hoverBlock != nil, hoverHidesAt == nil {
      hoverHidesAt = now + WellTiming.leaveHysteresis
    }
  }

  /// A key was typed. Hides the hover well until the pointer next moves.
  mutating func typed(at now: TimeInterval) {
    advance(to: now)
    isHiddenByTyping = true
  }

  /// A drag-selection began.
  mutating func dragBegan(at now: TimeInterval) {
    advance(to: now)
    isDragging = true
  }

  /// A drag-selection ended.
  mutating func dragEnded(at now: TimeInterval) {
    advance(to: now)
    isDragging = false
  }

  /// The caret moved. `block` is the eligible block holding an insertion point in a
  /// first-responder editor, or `nil`.
  mutating func caretMoved(to block: EscriboBlock.ID?, at now: TimeInterval) {
    advance(to: now)
    caretBlock = block
  }

  /// The host's active block changed.
  ///
  /// Active → none is the utterance ending, which is what Finished is. Active → another
  /// block is playback switching, which is not: the old block's well simply stops being
  /// pinned, and holding it would briefly show two accent wells.
  mutating func activeBlockChanged(to block: EscriboBlock.ID?, at now: TimeInterval) {
    advance(to: now)
    guard block != activeBlock else { return }
    if let previous = activeBlock, block == nil {
      finishedBlock = previous
      finishedEndsAt = now + WellTiming.finishedHold
    } else {
      finishedBlock = nil
      finishedEndsAt = nil
    }
    activeBlock = block
  }

  /// Retires every deadline that has passed by `now`.
  ///
  /// Called by each event before it applies, so an event arriving after a deadline sees the
  /// state that deadline produced — a pointer re-entering a block whose well has already
  /// hidden gets a fresh appearance rather than a cancelled hide.
  mutating func advance(to now: TimeInterval) {
    if let deadline = hoverHidesAt, now >= deadline {
      hoverBlock = nil
      hoverHidesAt = nil
    }
    if let deadline = finishedEndsAt, now >= deadline {
      finishedBlock = nil
      finishedEndsAt = nil
    }
  }

  // MARK: Output

  /// The next moment at which ``presentations(at:)`` changes with no further event, or
  /// `nil` when nothing is pending. The view schedules exactly one timer for it.
  var nextDeadline: TimeInterval? {
    [hoverHidesAt, finishedEndsAt].compactMap { $0 }.min()
  }

  /// The wells that should be on screen at `now`, at most one per block, in priority order:
  /// Playing, Finished, Hover, Caret.
  ///
  /// - The playing block is pinned regardless of the pointer, typing, or a drag (rule 3).
  ///   It is the host's state, not the pointer's, and hiding it would hide the stop button
  ///   for the thing that is making noise.
  /// - Typing and a drag-selection hide the hover well (rule 2).
  /// - The caret well is not hidden by typing. Touch has no pointer whose next move could
  ///   bring it back, which is what makes the rule sound for a mouse; applied to touch, one
  ///   keystroke would remove the well for good. A drag still hides it.
  /// - Caret yields to Hover: an iPad with a pointer shows the pointer's block, not both.
  func presentations(at now: TimeInterval) -> [Presentation] {
    var result: [Presentation] = []
    func add(_ block: EscriboBlock.ID, _ role: Role) {
      guard !result.contains(where: { $0.block == block }) else { return }
      result.append(Presentation(block: block, role: role))
    }

    if let activeBlock { add(activeBlock, .playing) }
    if let finishedBlock, let deadline = finishedEndsAt, now < deadline {
      add(finishedBlock, .finished)
    }

    var showsHover = false
    if !isHiddenByTyping, !isDragging, let hoverBlock {
      if hoverHidesAt.map({ now < $0 }) ?? true {
        add(hoverBlock, .hover)
        showsHover = true
      }
    }
    if !isDragging, !showsHover, let caretBlock {
      add(caretBlock, .caret)
    }
    return result
  }
}

// MARK: - Placement

/// How a span bar is drawn: its colour, how much of it is filled, and how long the fill
/// takes to get there. A value, so the Reduce Motion decision is testable without a view.
struct WellBarFill: Equatable, Sendable {
  /// Whether the bar is drawn in the accent colour rather than at rest.
  let isAccent: Bool
  /// The filled fraction of the bar, `0…1`, from the top.
  let fraction: CGFloat
  /// How long to animate to ``fraction``; `0` sets it at once.
  let duration: TimeInterval
}

/// Where the well's views go, as pure functions of rects (REQUIREMENTS-1.1.0 § 5.1).
///
/// Pure for the same reason ``WellTracker`` is: the rects come from TextKit in production
/// and from literals in a test, and the arithmetic cannot tell the difference. All rects are
/// in the text view's coordinate space, which is also the space the well's subviews live
/// in — that shared space is the point of making them subviews.
enum WellPlacement {

  /// The span bar's width.
  static let spanBarWidth: CGFloat = 2

  /// The gap between the span bar's right edge and the text edge.
  static let spanBarGap: CGFloat = 4

  /// The span bar's inset from the block's top and bottom.
  static let spanBarVerticalInset: CGFloat = 2

  /// The button's side: 20 pt on macOS, a 44 pt touch target on iOS.
  static func buttonSide(on platform: WellLane.Platform) -> CGFloat {
    switch platform {
    case .macOS: return 20
    case .iOS: return 44
    }
  }

  /// The button for slot `index`, centred in the lane horizontally and on the block's
  /// **first** line fragment vertically.
  ///
  /// The first line, not the block's centre: in a long paragraph the button belongs beside
  /// the words a reader starts from, and a centred button would drift down the lane as the
  /// paragraph grew. Later slots stack downward, one button-height apiece.
  ///
  /// - Parameters:
  ///   - index: The slot's position in the well, `0` for the first.
  ///   - firstLineFragment: The block's first line fragment.
  ///   - textEdge: The x of the text container's leading edge — the lane's trailing edge.
  ///   - laneWidth: The lane's width.
  ///   - platform: The platform whose button size applies.
  static func buttonFrame(
    slot index: Int,
    firstLineFragment: CGRect,
    textEdge: CGFloat,
    laneWidth: CGFloat,
    platform: WellLane.Platform
  ) -> CGRect {
    let side = buttonSide(on: platform)
    let centreX = textEdge - laneWidth / 2
    let centreY = firstLineFragment.midY + CGFloat(index) * side
    return CGRect(x: centreX - side / 2, y: centreY - side / 2, width: side, height: side)
  }

  /// The block's full extent: the union of its line fragments, or `nil` when it has none.
  static func blockRect(enclosing lineFragments: [CGRect]) -> CGRect? {
    guard var rect = lineFragments.first else { return nil }
    for fragment in lineFragments.dropFirst() {
      rect = rect.union(fragment)
    }
    return rect
  }

  /// The span bar: 2 pt wide, 4 pt from the text edge, inset 2 pt top and bottom, spanning
  /// the block's **full** height — the affordance that shows, before anyone clicks, that the
  /// whole block will be read and not merely the line under the pointer.
  static func spanBarFrame(blockRect: CGRect, textEdge: CGFloat) -> CGRect {
    CGRect(
      x: textEdge - spanBarGap - spanBarWidth,
      y: blockRect.minY + spanBarVerticalInset,
      width: spanBarWidth,
      height: max(0, blockRect.height - 2 * spanBarVerticalInset))
  }

  /// How the span bar is drawn for a well in `role` (REQUIREMENTS-1.1.0 § 5.2).
  ///
  /// - Hover and Caret: the at-rest track, no fill.
  /// - Playing: an accent bar that fills top to bottom with the clamped `progress`, eased
  ///   over ``WellTiming/progressStep``. A host that reports no progress gets a full accent
  ///   bar rather than an empty one — the bar still says which block is playing.
  /// - Playing under Reduce Motion: already filled, and not animated (rule 4). A fill that
  ///   creeps down the lane is exactly the motion the setting asks to remove, and a fill that
  ///   jumps once a word is worse.
  /// - Finished: full accent, not animated, while it holds.
  static func barFill(role: WellTracker.Role, progress: Double?, reduceMotion: Bool)
    -> WellBarFill
  {
    switch role {
    case .hover, .caret:
      return WellBarFill(isAccent: false, fraction: 0, duration: 0)
    case .finished:
      return WellBarFill(isAccent: true, fraction: 1, duration: 0)
    case .playing:
      guard !reduceMotion, let clamped = WellProgress.clamped(progress) else {
        return WellBarFill(isAccent: true, fraction: 1, duration: 0)
      }
      return WellBarFill(
        isAccent: true, fraction: CGFloat(clamped), duration: WellTiming.progressStep)
    }
  }

  /// The fill's frame inside a span bar with `barBounds`: anchored at the top and
  /// `fraction` of the bar's height, so progress reads top to bottom like the text.
  ///
  /// In top-left-origin coordinates — the span bar is flipped on macOS so that both
  /// platforms share this one answer.
  static func fillFrame(barBounds: CGRect, fraction: CGFloat) -> CGRect {
    let clamped = Swift.min(Swift.max(fraction, 0), 1)
    return CGRect(
      x: 0, y: 0, width: barBounds.width, height: barBounds.height * clamped)
  }

  /// The SF Symbol for `item`, or `nil` for an item this package does not know how to draw.
  ///
  /// An unknown item draws nothing rather than a placeholder: the well never shows a control
  /// it cannot give a meaning to.
  static func symbolName(for item: EscriboWellItem, isPlaying: Bool) -> String? {
    switch item {
    case .readAloud: return isPlaying ? "stop.fill" : "play.fill"
    default: return nil
    }
  }

  /// The accessibility identifier for `item`'s button: `editor.well.<rawValue>`, so
  /// `.readAloud` is `editor.well.readAloud`.
  static func accessibilityIdentifier(for item: EscriboWellItem) -> String {
    "editor.well.\(item.rawValue)"
  }
}
