import EscriboCore
import Foundation
import SwiftUI
import Testing

@testable import SwiftEscribo

/// Records every block it is asked about; answers for the start offsets in `noticed`.
final class CountingNotice {
  private(set) var asked: [EscriboBlock] = []
  var noticed: Set<Int> = []
  var symbol = "exclamationmark.triangle"

  func answer(_ block: EscriboBlock) -> (symbolName: String, help: String)? {
    asked.append(block)
    guard noticed.contains(block.range.lowerBound) else { return nil }
    return (symbol, "help \(block.range.lowerBound)")
  }

  func reset() { asked = [] }
}

/// Sortie 16: the notice model and tracker rules (REQUIREMENTS.md § 2).
@MainActor
@Suite("Well notice — model, tracker rules, and re-ask points")
struct WellNoticeTests {

  static let largeDocument = EmbedAPITests.largeDocument

  /// The document's blocks, scanned once; `EscriboBlock`'s initializer is internal to
  /// `EscriboCore`, so tests take real ones.
  private static let blocks = CoordinatorFixtures.makeEditor(largeDocument).coordinator
    .documentBlocks

  /// The block starting at `offset`.
  private func block(_ offset: Int) -> EscriboBlock {
    Self.blocks.first { $0.range.lowerBound == offset }!
  }

  /// A block with no content (a blank run).
  private func emptyBlock() -> EscriboBlock {
    Self.blocks.first { $0.contentRanges.isEmpty }!
  }

  // MARK: - Model

  @Test("EscriboWellItem.notice is a stable, distinct static member")
  func noticeItem() {
    #expect(EscriboWellItem.notice.rawValue == "notice")
    #expect(EscriboWellItem.notice != .readAloud)
  }

  @Test("EscriboWell stays Equatable and old init shapes compile")
  func wellEquatableAndInit() {
    #expect(EscriboWell() == EscriboWell())
    #expect(EscriboWell(items: [.readAloud, .notice]) != EscriboWell())
    _ = EscriboEditor(text: .constant(""), language: .markdown)
    _ = EscriboEditor(
      text: .constant(""), language: .markdown, well: EscriboWell(), onWellAction: { _, _ in },
      embedProvider: nil, onEmbedActivate: { _ in }, onEmbedAction: { _, _ in },
      onFindMatchInEmbed: { _ in })
    let view: any View = EscriboEditor(
      text: .constant(""), language: .markdown, well: EscriboWell(),
      wellNotice: { _ in ("bell", "help") })
    #expect(view is EscriboEditor)
  }

  // MARK: - Tracker rules

  @Test("A noticed block always presents the notice, with no hover or caret")
  func noticeAlwaysPresents() {
    var tracker = WellTracker()
    let b = block(0)
    tracker.noticesChanged(to: [b.id])
    #expect(tracker.presentations(at: 0) == [.init(block: b.id, role: .notice)])
    #expect(tracker.presentations(at: 1000) == [.init(block: b.id, role: .notice)])
  }

  @Test("The notice wins the one slot over hover, caret, playing and finished")
  func noticeSharesTheSlot() {
    var tracker = WellTracker()
    let b = block(0)
    tracker.noticesChanged(to: [b.id])
    tracker.pointerMoved(over: b.id, at: 0)
    tracker.caretMoved(to: b.id, at: 0)
    tracker.activeBlockChanged(to: b.id, at: 0)
    #expect(tracker.presentations(at: 0) == [.init(block: b.id, role: .notice)])
    tracker.activeBlockChanged(to: nil, at: 1)
    #expect(tracker.presentations(at: 1.1) == [.init(block: b.id, role: .notice)])
  }

  @Test("Read-aloud keeps hover/caret behaviour on blocks without a notice")
  func readAloudUnchanged() {
    var tracker = WellTracker()
    let noticed = block(0)
    let plain = block(21)
    tracker.noticesChanged(to: [noticed.id])
    #expect(tracker.presentations(at: 0).map(\.block) == [noticed.id])
    tracker.pointerMoved(over: plain.id, at: 0)
    #expect(
      tracker.presentations(at: 0)
        == [.init(block: noticed.id, role: .notice), .init(block: plain.id, role: .hover)])
    tracker.pointerMoved(over: nil, at: 1)
    #expect(tracker.presentations(at: 2) == [.init(block: noticed.id, role: .notice)])
    tracker.caretMoved(to: plain.id, at: 2)
    #expect(tracker.presentations(at: 2).last == .init(block: plain.id, role: .caret))
  }

  @Test("Typing and dragging do not hide a notice")
  func noticeSurvivesTypingAndDrag() {
    var tracker = WellTracker()
    let b = block(0)
    tracker.noticesChanged(to: [b.id])
    tracker.typed(at: 0)
    tracker.dragBegan(at: 0)
    #expect(tracker.presentations(at: 0).count == 1)
  }

  @Test("A notice draws a glyph only: no span bar, and an at-rest fill if asked")
  func noticeHasNoSpanBar() {
    #expect(!WellTracker.Presentation(block: block(0).id, role: .notice).showsSpanBar)
    #expect(WellTracker.Presentation(block: block(0).id, role: .hover).showsSpanBar)
    #expect(WellTracker.Presentation(block: block(0).id, role: .playing).showsSpanBar)
    #expect(
      WellPlacement.barFill(role: .notice, progress: 0.5, reduceMotion: false)
        == WellBarFill(isAccent: false, fraction: 0, duration: 0))
  }

  @Test("The notice glyph comes from the callback, not the built-in table")
  func glyphFromCallback() {
    #expect(WellPlacement.symbolName(for: .notice, isPlaying: false) == nil)
    #expect(WellPlacement.symbolName(for: .notice, isPlaying: false, notice: "bell") == "bell")
    #expect(WellPlacement.symbolName(for: .readAloud, isPlaying: false) == "play.fill")
    #expect(WellPlacement.symbolName(for: .readAloud, isPlaying: true, notice: nil) == "stop.fill")
    #expect(WellPlacement.symbolName(for: .readAloud, isPlaying: false, notice: "bell") == nil)
  }

  @Test("A notice is exempt from eligibleKinds and from the has-content rule")
  func noticeExemptFromEligibility() {
    let well = EscriboWell(eligibleKinds: [.heading])
    let paragraph = block(0)
    let empty = emptyBlock()
    #expect(!well.isEligible(paragraph))
    #expect(!well.isEligible(empty))
    #expect(well.presents(paragraph, hasNotice: true))
    #expect(well.presents(empty, hasNotice: true))
    #expect(!well.presents(paragraph, hasNotice: false))
    #expect(EscriboWell().presents(paragraph, hasNotice: false))
  }

  // MARK: - Re-ask points

  @Test("Installing asks every block once, in both modes; the answers are cached")
  func installAsksEveryBlock() {
    let editor = CoordinatorFixtures.makeEditor(Self.largeDocument)
    let counter = CountingNotice()
    counter.noticed = [0, 21 * 5]
    editor.coordinator.setWellNotice(counter.answer)
    #expect(counter.asked == editor.coordinator.documentBlocks)
    #expect(editor.coordinator.noticedBlocks.map(\.block.range.lowerBound) == [0, 105])
    let first = editor.coordinator.noticedBlocks[0].block
    #expect(editor.coordinator.notice(for: first)?.help == "help 0")
    #expect(editor.coordinator.notice(for: block(21 * 7)) == nil)

    // Re-installing a closure on an update pass is not a re-ask.
    counter.reset()
    editor.coordinator.setWellNotice(counter.answer)
    #expect(counter.asked.isEmpty)

    // Source mode: asked too.
    let storage = NSTextStorage(string: Self.largeDocument)
    let styler = EscriboStyler(
      environment: EditorStyleEnvironment(theme: .markdownLight, mode: .source, appearance: .light))
    let coordinator = EditorCoordinator(attachingTo: storage, language: .markdown, styler: styler)
    coordinator.restyleEverything()
    let sourceCounter = CountingNotice()
    coordinator.setWellNotice(sourceCounter.answer)
    #expect(sourceCounter.asked == coordinator.documentBlocks)
  }

  @Test("The bridge asks every block once on load and not on update passes")
  func bridgeLoadAsksOnce() {
    let counter = CountingNotice()
    let config = EmbedConfiguration(provider: nil, wellNotice: counter.answer)
    let bridge = EscriboEditorBridge(text: .constant(Self.largeDocument))
    let editor = bridge.makeEditor(
      language: .markdown, mode: .live, theme: .markdownLight, appearance: .light,
      embeds: config)
    #expect(counter.asked == editor.coordinator.documentBlocks)
    counter.reset()
    for _ in 0..<3 {
      bridge.update(
        language: .markdown, mode: .live, theme: .markdownLight, appearance: .light,
        text: Self.largeDocument, embeds: config)
    }
    #expect(counter.asked.isEmpty)
    bridge.update(
      language: .markdown, mode: .live, theme: .markdownLight, appearance: .light,
      text: "one\n\ntwo\n", embeds: config)
    #expect(counter.asked == editor.coordinator.documentBlocks)
  }

  @Test("An edit asks only the rescanned blocks and carries other answers across")
  func editAsksOnlyRescanned() throws {
    let editor = CoordinatorFixtures.makeEditor(Self.largeDocument)
    let counter = CountingNotice()
    counter.noticed = [0, 21 * 60]
    editor.coordinator.setWellNotice(counter.answer)
    counter.reset()

    editor.storage.replaceCharacters(in: NSRange(location: 21 * 40 + 5, length: 0), with: "X")
    try #require(editor.coordinator.blocksSpanDocument)
    let window = editor.coordinator.lastBlocks
    #expect(counter.asked == window)
    #expect(window.count < editor.coordinator.documentBlocks.count)
    // The later notice shifted by one character.
    #expect(editor.coordinator.noticedBlocks.map(\.block.range.lowerBound) == [0, 21 * 60 + 1])
  }

  @Test("invalidateEmbeds() asks every block and reports only changed blocks")
  func invalidateAsksEveryBlock() {
    let editor = CoordinatorFixtures.makeEditor(Self.largeDocument)
    let counter = CountingNotice()
    counter.noticed = [0]
    editor.coordinator.setWellNotice(counter.answer)
    var reports: [[Range<Int>]] = []
    editor.coordinator.onNoticesChange = { reports.append($0) }
    counter.reset()

    let handle = EscriboEditorHandle()
    handle.attach(to: editor.coordinator)
    handle.invalidateEmbeds()
    #expect(counter.asked == editor.coordinator.documentBlocks)
    #expect(reports.isEmpty)

    counter.noticed = [0, 42]
    handle.invalidateEmbeds()
    #expect(reports == [[42..<62]])
    #expect(editor.coordinator.noticedBlockIDs.count == 2)
  }

  @Test("Removing the callback empties the cache")
  func removingEmptiesCache() {
    let editor = CoordinatorFixtures.makeEditor(Self.largeDocument)
    let counter = CountingNotice()
    counter.noticed = [0]
    editor.coordinator.setWellNotice(counter.answer)
    #expect(editor.coordinator.noticedBlocks.count == 1)
    editor.coordinator.setWellNotice(nil)
    #expect(editor.coordinator.noticedBlocks.isEmpty)
  }
}
