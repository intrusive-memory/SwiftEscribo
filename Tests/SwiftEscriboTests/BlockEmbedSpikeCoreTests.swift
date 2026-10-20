import EscriboCore
import Foundation
import Testing

@testable import SwiftEscribo

// SPIKE — throwaway tests for the atomic block-embed experiment.

/// Shared fixture: a standalone three-line note that bridges nothing.
enum BlockEmbedSpikeFixture {
  static let noteLines = "[[First line of the note\nsecond line\nthird line]]\n"
  static let text =
    "INT. HOUSE - DAY\n\nBob waits by the door.\n\n" + noteLines + "\nJane enters.\n"
}

@Suite("Block embed spike — core logic")
struct BlockEmbedSpikeCoreTests {

  // MARK: - Row 10 prerequisite

  @Test("row 10: a three-line standalone note is exactly one .note block covering all lines")
  func multiLineNoteIsOneBlock() throws {
    var scanner = EscriboScanner(language: .fountain)
    let result = scanner.fullScan(BlockEmbedSpikeFixture.text)
    let notes = result.blocks.filter { $0.kind == .note }
    #expect(notes.count == 1)
    let note = try #require(notes.first)
    let ns = BlockEmbedSpikeFixture.text as NSString
    let expected = ns.range(of: BlockEmbedSpikeFixture.noteLines)
    #expect(note.range == expected.location..<NSMaxRange(expected))
    #expect(note.lines.count == 3)
  }

  @Test("registry reports only embedded, collapsed blocks")
  func registryRanges() throws {
    var scanner = EscriboScanner(language: .fountain)
    let result = scanner.fullScan(BlockEmbedSpikeFixture.text)
    let note = try #require(result.blocks.first { $0.kind == .note })
    var registry = SpikeEmbedRegistry()
    #expect(registry.embeddedRanges(in: result.blocks).isEmpty)
    registry.embeds[note.range.lowerBound] = SpikeEmbedContent(
      symbolName: "note.text", title: "t", subtitle: "s", badge: "b",
      accessibilityLabel: "l", accessibilityValue: "v")
    #expect(
      registry.embeddedRanges(in: result.blocks)
        == [NSRange(location: note.range.lowerBound, length: note.range.count)])
    registry.expanded.insert(note.range.lowerBound)
    #expect(registry.embeddedRanges(in: result.blocks).isEmpty)
  }

  // MARK: - constrain: embed is [10, 30)

  private let embed = NSRange(location: 10, length: 20)

  private func constrain(_ proposed: NSRange, from previous: NSRange) -> NSRange {
    SpikeEmbedSelection.constrain(proposed: proposed, previous: previous, embeds: [embed])
  }

  @Test("caret moving forward into the embed snaps to its end")
  func caretForward() {
    #expect(constrain(NSRange(location: 11, length: 0), from: NSRange(location: 10, length: 0))
      == NSRange(location: 30, length: 0))
  }

  @Test("caret moving backward into the embed snaps to its start")
  func caretBackward() {
    #expect(constrain(NSRange(location: 29, length: 0), from: NSRange(location: 30, length: 0))
      == NSRange(location: 10, length: 0))
  }

  @Test("caret at either edge stays")
  func caretAtEdges() {
    #expect(constrain(NSRange(location: 10, length: 0), from: NSRange(location: 5, length: 0))
      == NSRange(location: 10, length: 0))
    #expect(constrain(NSRange(location: 30, length: 0), from: NSRange(location: 35, length: 0))
      == NSRange(location: 30, length: 0))
  }

  @Test("a click inside the embed snaps to the nearer edge")
  func clickInside() {
    #expect(constrain(NSRange(location: 12, length: 0), from: NSRange(location: 12, length: 0))
      == NSRange(location: 10, length: 0))
    #expect(constrain(NSRange(location: 28, length: 0), from: NSRange(location: 28, length: 0))
      == NSRange(location: 30, length: 0))
  }

  @Test("extending a selection rightward into the embed covers it whole")
  func extendRight() {
    #expect(constrain(NSRange(location: 5, length: 10), from: NSRange(location: 5, length: 3))
      == NSRange(location: 5, length: 25))
  }

  @Test("extending a selection leftward into the embed covers it whole")
  func extendLeft() {
    #expect(constrain(NSRange(location: 20, length: 20), from: NSRange(location: 30, length: 10))
      == NSRange(location: 10, length: 30))
  }

  @Test("a selection inside the embed grows to the whole embed")
  func selectionInside() {
    #expect(constrain(NSRange(location: 15, length: 5), from: NSRange(location: 15, length: 0))
      == embed)
  }

  @Test("selections fully outside or merely abutting the embed are untouched")
  func outsideUntouched() {
    let before = NSRange(location: 0, length: 10)
    let after = NSRange(location: 30, length: 5)
    #expect(constrain(before, from: NSRange(location: 0, length: 5)) == before)
    #expect(constrain(after, from: NSRange(location: 30, length: 2)) == after)
    #expect(constrain(embed, from: NSRange(location: 0, length: 0)) == embed)
  }

  // MARK: - deletionRange

  @Test("a middle block takes its following blank line")
  func deleteMiddle() {
    let text = "A\n\nBBB\nBBB\n\nC\n" as NSString
    let block = NSRange(location: 3, length: 8)  // "BBB\nBBB\n"
    #expect(SpikeEmbedSelection.deletionRange(for: block, in: text)
      == NSRange(location: 3, length: 9))
  }

  @Test("the last block takes its preceding blank line")
  func deleteLast() {
    let text = "A\n\nBBB\n" as NSString
    let block = NSRange(location: 3, length: 4)
    #expect(SpikeEmbedSelection.deletionRange(for: block, in: text)
      == NSRange(location: 2, length: 5))
  }

  @Test("a block with no blank neighbour takes only itself")
  func deleteNoBlank() {
    let text = "A\nBBB\nC\n" as NSString
    let block = NSRange(location: 2, length: 4)
    #expect(SpikeEmbedSelection.deletionRange(for: block, in: text) == block)
  }

  @Test("the fixture note deletes with its following blank line")
  func deleteFixtureNote() {
    let text = BlockEmbedSpikeFixture.text as NSString
    let block = text.range(of: BlockEmbedSpikeFixture.noteLines)
    let del = SpikeEmbedSelection.deletionRange(for: block, in: text)
    #expect(del.length == block.length + 1)
    let remaining = text.replacingCharacters(in: del, with: "")
    #expect(remaining == "INT. HOUSE - DAY\n\nBob waits by the door.\n\nJane enters.\n")
  }
}
