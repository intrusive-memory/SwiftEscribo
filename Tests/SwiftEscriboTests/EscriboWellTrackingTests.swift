import CoreGraphics
import EscriboCore
import Foundation
import Testing

@testable import SwiftEscribo

#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

// MARK: - The state machine

/// The paragraph well's state machine (REQUIREMENTS-1.1.0 § 5.2), stepped by hand.
///
/// No views, no timers, no sleeps: every event carries its own timestamp, so the 150 ms
/// hysteresis and the 400 ms Finished hold are asserted at the exact millisecond on either
/// side of the boundary rather than approximately after a wait.
///
/// Block IDs come from a real scan rather than being constructed, because `EscriboBlock.ID`'s
/// initializer is internal to `EscriboCore` — which is also the guarantee that an ID in these
/// tests is a shape the scanner actually produces.
@MainActor
@Suite("Paragraph well — state machine")
struct WellTrackerTests {

  /// Three paragraphs: `one`, `two`, `three`.
  private static func paragraphIDs() -> [EscriboBlock.ID] {
    CoordinatorFixtures.makeEditor("one\n\ntwo\n\nthree").coordinator.documentBlocks
      .filter { $0.kind == .paragraph }
      .map(\.id)
  }

  private let t0: TimeInterval = 1000

  private func shown(_ block: EscriboBlock.ID, _ role: WellTracker.Role) -> WellTracker.Presentation {
    WellTracker.Presentation(block: block, role: role)
  }

  @Test("Rest: a fresh tracker shows nothing and has nothing pending")
  func restShowsNothing() {
    let tracker = WellTracker()
    #expect(tracker.presentations(at: t0).isEmpty)
    #expect(tracker.nextDeadline == nil)
  }

  @Test("Hover shows the pointer's block at once, and fades in over 120 ms unless motion is reduced")
  func hoverShowsImmediately() throws {
    let ids = Self.paragraphIDs()
    let a = try #require(ids.first)
    var tracker = WellTracker()
    tracker.pointerMoved(over: a, at: t0)
    #expect(tracker.presentations(at: t0) == [shown(a, .hover)])

    #expect(WellTiming.fadeInDuration(reduceMotion: false) == 0.12)
    #expect(WellTiming.fadeInDuration(reduceMotion: true) == 0)
  }

  @Test("Hysteresis: leaving a block hides its well after 150 ms, not at once")
  func leavingHidesAfterHysteresis() throws {
    let a = try #require(Self.paragraphIDs().first)
    var tracker = WellTracker()
    tracker.pointerMoved(over: a, at: t0)
    tracker.pointerMoved(over: nil, at: t0 + 1)

    #expect(tracker.nextDeadline == t0 + 1 + WellTiming.leaveHysteresis)
    #expect(tracker.presentations(at: t0 + 1.149) == [shown(a, .hover)])
    #expect(tracker.presentations(at: t0 + 1 + 0.15).isEmpty)

    tracker.advance(to: t0 + 1.2)
    #expect(tracker.hoverBlock == nil)
    #expect(tracker.nextDeadline == nil)
  }

  @Test("Returning inside the hysteresis window cancels the hide")
  func returningCancelsTheHide() throws {
    let a = try #require(Self.paragraphIDs().first)
    var tracker = WellTracker()
    tracker.pointerMoved(over: a, at: t0)
    tracker.pointerMoved(over: nil, at: t0 + 0.01)
    tracker.pointerMoved(over: a, at: t0 + 0.1)
    #expect(tracker.nextDeadline == nil)
    #expect(tracker.presentations(at: t0 + 5) == [shown(a, .hover)])
  }

  @Test("Moving straight into another block switches the well at once")
  func movingToAnotherBlockSwitches() throws {
    let ids = Self.paragraphIDs()
    try #require(ids.count == 3)
    var tracker = WellTracker()
    tracker.pointerMoved(over: ids[0], at: t0)
    tracker.pointerMoved(over: ids[1], at: t0 + 0.01)
    #expect(tracker.presentations(at: t0 + 0.01) == [shown(ids[1], .hover)])
  }

  @Test("Typing hides the well; the next pointer move restores it; time alone does not")
  func typingHidesUntilThePointerMoves() throws {
    let a = try #require(Self.paragraphIDs().first)
    var tracker = WellTracker()
    tracker.pointerMoved(over: a, at: t0)
    tracker.typed(at: t0 + 1)
    #expect(tracker.presentations(at: t0 + 1).isEmpty)
    #expect(tracker.presentations(at: t0 + 60).isEmpty)

    tracker.pointerMoved(over: a, at: t0 + 61)
    #expect(tracker.presentations(at: t0 + 61) == [shown(a, .hover)])
  }

  @Test("No well during a drag-selection")
  func dragSelectionHidesTheWell() throws {
    let a = try #require(Self.paragraphIDs().first)
    var tracker = WellTracker()
    tracker.pointerMoved(over: a, at: t0)
    tracker.dragBegan(at: t0 + 1)
    tracker.pointerMoved(over: a, at: t0 + 1.1)
    #expect(tracker.presentations(at: t0 + 1.1).isEmpty)

    tracker.dragEnded(at: t0 + 2)
    #expect(tracker.presentations(at: t0 + 2) == [shown(a, .hover)])
  }

  @Test("Caret: the caret's eligible block shows a well, and the pointer's block wins over it")
  func caretShowsAndYieldsToHover() throws {
    let ids = Self.paragraphIDs()
    try #require(ids.count == 3)
    var tracker = WellTracker()
    tracker.caretMoved(to: ids[0], at: t0)
    #expect(tracker.presentations(at: t0) == [shown(ids[0], .caret)])

    // Touch has no pointer to bring a typed-away well back, so typing leaves Caret alone.
    tracker.typed(at: t0 + 1)
    #expect(tracker.presentations(at: t0 + 1) == [shown(ids[0], .caret)])

    tracker.pointerMoved(over: ids[1], at: t0 + 2)
    #expect(tracker.presentations(at: t0 + 2) == [shown(ids[1], .hover)])

    tracker.caretMoved(to: nil, at: t0 + 3)
    tracker.pointerMoved(over: nil, at: t0 + 3)
    #expect(tracker.presentations(at: t0 + 4).isEmpty)
  }

  @Test("Playing is pinned while the pointer hovers elsewhere, leaves, types, or drags")
  func playingBlockStaysPinned() throws {
    let ids = Self.paragraphIDs()
    try #require(ids.count == 3)
    var tracker = WellTracker()
    tracker.activeBlockChanged(to: ids[0], at: t0)
    tracker.pointerMoved(over: ids[1], at: t0 + 1)
    #expect(
      tracker.presentations(at: t0 + 1) == [
        shown(ids[0], .playing), shown(ids[1], .hover),
      ])

    tracker.pointerMoved(over: nil, at: t0 + 2)
    tracker.typed(at: t0 + 2.5)
    tracker.dragBegan(at: t0 + 2.6)
    #expect(tracker.presentations(at: t0 + 10) == [shown(ids[0], .playing)])
  }

  @Test("Hovering the playing block does not demote it to a hover well")
  func hoveringThePlayingBlockKeepsItPlaying() throws {
    let a = try #require(Self.paragraphIDs().first)
    var tracker = WellTracker()
    tracker.activeBlockChanged(to: a, at: t0)
    tracker.pointerMoved(over: a, at: t0 + 1)
    #expect(tracker.presentations(at: t0 + 1) == [shown(a, .playing)])
  }

  @Test("Finished holds 400 ms, then returns to Hover when the pointer is on the block")
  func finishedReturnsToHover() throws {
    let a = try #require(Self.paragraphIDs().first)
    var tracker = WellTracker()
    tracker.pointerMoved(over: a, at: t0)
    tracker.activeBlockChanged(to: a, at: t0)
    tracker.activeBlockChanged(to: nil, at: t0 + 3)

    #expect(tracker.nextDeadline == t0 + 3 + WellTiming.finishedHold)
    #expect(tracker.presentations(at: t0 + 3.399) == [shown(a, .finished)])
    #expect(tracker.presentations(at: t0 + 3 + 0.4) == [shown(a, .hover)])
  }

  @Test("Finished holds 400 ms, then returns to Rest when the pointer is elsewhere")
  func finishedReturnsToRest() throws {
    let a = try #require(Self.paragraphIDs().first)
    var tracker = WellTracker()
    tracker.activeBlockChanged(to: a, at: t0)
    tracker.activeBlockChanged(to: nil, at: t0 + 3)
    #expect(tracker.presentations(at: t0 + 3.2) == [shown(a, .finished)])
    #expect(tracker.presentations(at: t0 + 3.5).isEmpty)
  }

  @Test("Switching playback from one block to another is not Finished")
  func switchingPlaybackIsNotFinished() throws {
    let ids = Self.paragraphIDs()
    try #require(ids.count == 3)
    var tracker = WellTracker()
    tracker.activeBlockChanged(to: ids[0], at: t0)
    tracker.activeBlockChanged(to: ids[1], at: t0 + 1)
    #expect(tracker.presentations(at: t0 + 1) == [shown(ids[1], .playing)])
    #expect(tracker.nextDeadline == nil)
  }
}

// MARK: - Placement

/// The well's placement arithmetic (REQUIREMENTS-1.1.0 § 5.1), over literal rects.
@Suite("Paragraph well — placement")
struct WellPlacementTests {

  @Test("macOS button: 20 × 20, centred in the 28 pt lane and on the first line fragment")
  func macOSButtonFrame() {
    let frame = WellPlacement.buttonFrame(
      slot: 0, firstLineFragment: CGRect(x: 40, y: 100, width: 300, height: 18),
      textEdge: 40, laneWidth: 28, platform: .macOS)
    #expect(frame == CGRect(x: 16, y: 99, width: 20, height: 20))
    #expect(frame.midX == CGFloat(26))
    #expect(frame.midY == CGFloat(109))
  }

  @Test("iOS button: a 44 × 44 hit area, centred in the 44 pt lane and on the first line")
  func iOSButtonFrame() {
    let frame = WellPlacement.buttonFrame(
      slot: 0, firstLineFragment: CGRect(x: 40, y: 100, width: 300, height: 18),
      textEdge: 40, laneWidth: 44, platform: .iOS)
    #expect(frame == CGRect(x: -4, y: 87, width: 44, height: 44))
  }

  @Test("A later slot stacks one button-height below the first")
  func laterSlotsStack() {
    let first = WellPlacement.buttonFrame(
      slot: 0, firstLineFragment: CGRect(x: 40, y: 100, width: 300, height: 18),
      textEdge: 40, laneWidth: 28, platform: .macOS)
    let second = WellPlacement.buttonFrame(
      slot: 1, firstLineFragment: CGRect(x: 40, y: 100, width: 300, height: 18),
      textEdge: 40, laneWidth: 28, platform: .macOS)
    #expect(second == first.offsetBy(dx: 0, dy: 20))
  }

  @Test("The block rect is the union of every line fragment, soft-wrapped ones included")
  func blockRectIsTheUnion() {
    let fragments = [
      CGRect(x: 40, y: 100, width: 300, height: 18),
      CGRect(x: 40, y: 118, width: 200, height: 18),
      CGRect(x: 40, y: 136, width: 250, height: 18),
    ]
    #expect(
      WellPlacement.blockRect(enclosing: fragments) == CGRect(x: 40, y: 100, width: 300, height: 54))
    #expect(WellPlacement.blockRect(enclosing: []) == nil)
  }

  @Test("Span bar: 2 wide, 4 from the text edge, inset 2 top and bottom, the block's full height")
  func spanBarFrame() {
    let bar = WellPlacement.spanBarFrame(
      blockRect: CGRect(x: 40, y: 100, width: 300, height: 54), textEdge: 40)
    #expect(bar == CGRect(x: 34, y: 102, width: 2, height: 50))
    #expect(bar.maxX == CGFloat(36), "4 pt short of the text edge")
  }

  @Test("A block shorter than its insets gets a zero-height bar, never a negative one")
  func spanBarNeverInverts() {
    let bar = WellPlacement.spanBarFrame(
      blockRect: CGRect(x: 40, y: 100, width: 300, height: 3), textEdge: 40)
    #expect(bar.height == CGFloat(0))
  }

  @Test("Symbols and identifiers: play and stop for Read Aloud, nothing for an unknown item")
  func symbolsAndIdentifiers() {
    #expect(WellPlacement.symbolName(for: .readAloud, isPlaying: false) == "play.fill")
    #expect(WellPlacement.symbolName(for: .readAloud, isPlaying: true) == "stop.fill")
    #expect(WellPlacement.symbolName(for: EscriboWellItem(rawValue: "future"), isPlaying: false) == nil)
    #expect(WellPlacement.accessibilityIdentifier(for: .readAloud) == "editor.well.readAloud")
  }
}

// MARK: - Subviews

/// The reconciliation that turns the state machine into real subviews of the text view.
///
/// ## No layout, and no window
///
/// Laying out a text view in this process can deadlock against the font suites that run
/// concurrently off the main actor. So every test here replaces both geometry seams — the
/// coordinator's `utf16Offset` and the overlay's `WellGeometry` — with literal 20 pt lines
/// before anything could ask TextKit, and none of them hosts the view in a window. What is
/// under test is exactly what the seams leave: which subviews are added, where, and when
/// they go.
@MainActor
@Suite("Paragraph well — subviews")
struct WellOverlayTests {

  /// `one` (line 0), blank, `# Heading` (line 2), blank, `two` (line 4).
  static let document = "one\n\n# Heading\n\ntwo"
  static let textEdge: CGFloat = 40
  static let lineHeight: CGFloat = 20

  #if os(iOS)
    static let sizeClass: WellLane.HorizontalSizeClass? = .regular
  #else
    static let sizeClass: WellLane.HorizontalSizeClass? = nil
  #endif

  final class ManualClock {
    var now: TimeInterval = 1000
  }

  /// An editor over `document` whose geometry is literal: line `i` occupies
  /// `y ∈ [20i, 20i + 20)` and starts at the text edge.
  private func makeEditor() -> (editor: EscriboTextView, clock: ManualClock) {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    editor.applyExternalText(Self.document)
    editor.coordinator.restyleEverything()
    let textEdge = Self.textEdge
    let lineHeight = Self.lineHeight

    var starts = [0]
    for (index, unit) in Self.document.utf16.enumerated() where unit == 0x0A {
      starts.append(index + 1)
    }
    let lineStarts = starts

    editor.coordinator.utf16Offset = { point in
      let line = Int((point.y / lineHeight).rounded(.down))
      guard line >= 0, line < lineStarts.count else { return nil }
      return lineStarts[line]
    }

    let clock = ManualClock()
    let overlay = editor.wellOverlay
    overlay.schedulesTicks = false
    overlay.reduceMotion = { true }
    overlay.now = { clock.now }
    overlay.geometry = WellGeometry(
      textEdge: { textEdge },
      lineFragmentRects: { range in
        lineStarts.enumerated()
          .filter { range.contains($0.element) }
          .map {
            CGRect(
              x: textEdge, y: CGFloat($0.offset) * lineHeight, width: 300, height: lineHeight)
          }
      })
    return (editor, clock)
  }

  private func point(onLine line: Int) -> CGPoint {
    CGPoint(x: 120, y: CGFloat(line) * Self.lineHeight + Self.lineHeight / 2)
  }

  private func buttons(_ editor: EscriboTextView) -> [WellButton] {
    editor.textView.subviews.compactMap { $0 as? WellButton }
  }

  private func bars(_ editor: EscriboTextView) -> [WellSpanBar] {
    editor.textView.subviews.compactMap { $0 as? WellSpanBar }
  }

  private func block(_ editor: EscriboTextView, kind: BlockKind, last: Bool = false) throws
    -> EscriboBlock
  {
    let matching = editor.coordinator.documentBlocks.filter { $0.kind == kind }
    return try #require(last ? matching.last : matching.first)
  }

  private func identifier(of button: WellButton) -> String? {
    #if os(macOS)
      return button.accessibilityIdentifier()
    #else
      return button.accessibilityIdentifier
    #endif
  }

  // MARK: Exit criteria

  @Test("An ineligible block produces no button subview — not a disabled one")
  func ineligibleBlockProducesNoButtonSubview() throws {
    let (editor, _) = makeEditor()
    let heading = try block(editor, kind: .heading)
    editor.applyWell(EscriboWell(eligibleKinds: [.paragraph]), horizontalSizeClass: Self.sizeClass)

    editor.wellOverlay.pointerMoved(to: point(onLine: 2))
    #expect(buttons(editor).isEmpty, "a hovered heading outside eligibleKinds draws no button")
    #expect(bars(editor).isEmpty)

    // A blank run has no content, so it is ineligible whatever the kind set says.
    editor.wellOverlay.pointerMoved(to: point(onLine: 1))
    #expect(buttons(editor).isEmpty)

    // Nor may the host's active block smuggle an ineligible block past the check.
    editor.applyWell(
      EscriboWell(activeBlock: heading.id, eligibleKinds: [.paragraph]),
      horizontalSizeClass: Self.sizeClass)
    #expect(buttons(editor).isEmpty)

    // The control: the same mechanism draws exactly one enabled button for an eligible block.
    editor.wellOverlay.pointerMoved(to: point(onLine: 4))
    let drawn = buttons(editor)
    #expect(drawn.count == 1)
    #expect(drawn.allSatisfy { $0.isEnabled })
    #expect(drawn.first?.block?.kind == BlockKind.paragraph)
  }

  @Test("The active block's well stays pinned while the pointer moves to another block")
  func activeBlocksWellStaysPinnedWhilePointerIsElsewhere() throws {
    let (editor, clock) = makeEditor()
    let first = try block(editor, kind: .paragraph)
    let second = try block(editor, kind: .paragraph, last: true)
    try #require(first.id != second.id)

    editor.applyWell(EscriboWell(activeBlock: first.id), horizontalSizeClass: Self.sizeClass)
    #expect(buttons(editor).map { $0.block?.id } == [first.id])

    // Pointer to the other block: its play button joins, and the active one stays.
    editor.wellOverlay.pointerMoved(to: point(onLine: 4))
    #expect(Set(buttons(editor).compactMap { $0.block?.id }) == [first.id, second.id])

    // Pointer away entirely, past the hysteresis: the hover well goes, the pinned one does not.
    editor.wellOverlay.pointerMoved(to: nil)
    clock.now += 1
    editor.wellOverlay.reconcile()
    #expect(buttons(editor).map { $0.block?.id } == [first.id])
    #expect(bars(editor).count == 1)
  }

  // MARK: Drawing

  @Test("The button and span bar are placed by WellPlacement from the block's fragments")
  func subviewsArePlacedFromTheFragments() throws {
    let (editor, _) = makeEditor()
    editor.applyWell(EscriboWell(), horizontalSizeClass: Self.sizeClass)
    editor.wellOverlay.pointerMoved(to: point(onLine: 4))

    let button = try #require(buttons(editor).first)
    let firstLine = CGRect(x: Self.textEdge, y: 80, width: 300, height: Self.lineHeight)
    #expect(
      button.frame
        == WellPlacement.buttonFrame(
          slot: 0, firstLineFragment: firstLine, textEdge: Self.textEdge,
          laneWidth: editor.wellLaneWidth, platform: .current))
    let bar = try #require(bars(editor).first)
    #expect(bar.frame == WellPlacement.spanBarFrame(blockRect: firstLine, textEdge: Self.textEdge))
    #expect(identifier(of: button) == "editor.well.readAloud")
  }

  @Test("Rest: with a well applied and nothing hovered, playing, or focused, the lane is empty")
  func restDrawsNothing() {
    let (editor, _) = makeEditor()
    editor.applyWell(EscriboWell(), horizontalSizeClass: Self.sizeClass)
    #expect(buttons(editor).isEmpty)
    #expect(bars(editor).isEmpty)
  }

  @Test("Leaving hides the well after the hysteresis; typing hides it at once")
  func leavingAndTypingRemoveSubviews() {
    let (editor, clock) = makeEditor()
    editor.applyWell(EscriboWell(), horizontalSizeClass: Self.sizeClass)
    let overlay = editor.wellOverlay

    overlay.pointerMoved(to: point(onLine: 0))
    overlay.pointerMoved(to: nil)
    clock.now += 0.1
    overlay.reconcile()
    #expect(buttons(editor).count == 1, "still inside the 150 ms window")
    clock.now += 0.1
    overlay.reconcile()
    #expect(buttons(editor).isEmpty)

    overlay.pointerMoved(to: point(onLine: 0))
    #expect(buttons(editor).count == 1)
    overlay.typed()
    #expect(buttons(editor).isEmpty)
    overlay.pointerMoved(to: point(onLine: 0))
    #expect(buttons(editor).count == 1)
  }

  @Test("Reduce Motion: a new well appears fully opaque, with no fade")
  func reduceMotionSkipsTheFade() throws {
    let (editor, _) = makeEditor()
    editor.applyWell(EscriboWell(), horizontalSizeClass: Self.sizeClass)
    editor.wellOverlay.pointerMoved(to: point(onLine: 0))
    let button = try #require(buttons(editor).first)
    #if os(macOS)
      #expect(button.alphaValue == CGFloat(1))
    #else
      #expect(button.alpha == CGFloat(1))
    #endif
  }

  @Test("Activating a button calls onWellAction with its item and block")
  func buttonInvokesTheWellAction() throws {
    let (editor, _) = makeEditor()
    var received: [(EscriboWellItem, EscriboBlock.ID)] = []
    editor.onWellAction = { item, block in received.append((item, block.id)) }
    editor.applyWell(EscriboWell(), horizontalSizeClass: Self.sizeClass)
    editor.wellOverlay.pointerMoved(to: point(onLine: 4))

    let button = try #require(buttons(editor).first)
    editor.wellOverlay.wellButtonPressed(button)
    let second = try block(editor, kind: .paragraph, last: true)
    #expect(received.count == 1)
    #expect(received.first?.0 == EscriboWellItem.readAloud)
    #expect(received.first?.1 == second.id)
  }

  @Test("Removing the well removes every subview it drew")
  func removingTheWellClearsTheLane() throws {
    let (editor, _) = makeEditor()
    let first = try block(editor, kind: .paragraph)
    editor.applyWell(EscriboWell(activeBlock: first.id), horizontalSizeClass: Self.sizeClass)
    #expect(buttons(editor).count == 1)

    editor.applyWell(nil, horizontalSizeClass: Self.sizeClass)
    #expect(buttons(editor).isEmpty)
    #expect(bars(editor).isEmpty)
  }
}
