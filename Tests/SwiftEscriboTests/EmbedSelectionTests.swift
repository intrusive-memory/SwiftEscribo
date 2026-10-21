import Foundation
import Testing

@testable import SwiftEscribo

@Suite("EmbedSelection")
struct EmbedSelectionTests {

  // One embed at [10, 30).
  private let embed = NSRange(location: 10, length: 20)

  private func caret(_ loc: Int) -> NSRange { NSRange(location: loc, length: 0) }

  private func constrain(
    _ proposed: NSRange, from previous: NSRange, embeds: [NSRange]? = nil, find: Bool = false
  ) -> NSRange {
    EmbedSelection.constrain(
      proposed: proposed, previous: previous, embeds: embeds ?? [embed], isFindMatch: find)
  }

  // MARK: - constrain

  @Test("caret moving forward into the embed steps over it")
  func caretForward() {
    #expect(constrain(caret(11), from: caret(10)) == caret(30))
  }

  @Test("caret moving backward into the embed steps over it")
  func caretBackward() {
    #expect(constrain(caret(29), from: caret(30)) == caret(10))
  }

  @Test("caret at either edge stays")
  func caretAtEdges() {
    #expect(constrain(caret(10), from: caret(5)) == caret(10))
    #expect(constrain(caret(30), from: caret(35)) == caret(30))
  }

  @Test("a caret with no travel inside snaps to the nearer edge")
  func noTravel() {
    #expect(constrain(caret(12), from: caret(12)) == caret(10))
    #expect(constrain(caret(28), from: caret(28)) == caret(30))
  }

  @Test("extending a selection into the embed covers it whole")
  func extend() {
    #expect(constrain(NSRange(location: 5, length: 10), from: NSRange(location: 5, length: 3))
      == NSRange(location: 5, length: 25))
    #expect(constrain(NSRange(location: 20, length: 20), from: NSRange(location: 30, length: 10))
      == NSRange(location: 10, length: 30))
    #expect(constrain(NSRange(location: 15, length: 5), from: caret(15)) == embed)
  }

  @Test("selections outside or merely abutting the embed are untouched")
  func outsideUntouched() {
    let before = NSRange(location: 0, length: 10)
    let after = NSRange(location: 30, length: 5)
    #expect(constrain(before, from: NSRange(location: 0, length: 5)) == before)
    #expect(constrain(after, from: NSRange(location: 30, length: 2)) == after)
    #expect(constrain(embed, from: caret(0)) == embed)
  }

  @Test("a find-originated selection passes through unchanged")
  func findPassThrough() {
    let inside = NSRange(location: 14, length: 4)
    #expect(constrain(inside, from: caret(0), find: true) == inside)
    #expect(constrain(caret(14), from: caret(0), find: true) == caret(14))
    #expect(constrain(inside, from: caret(0), find: false) == embed)
  }

  @Test("adjacent embeds: a caret between them is allowed, a selection spanning both covers both")
  func adjacent() {
    let a = NSRange(location: 10, length: 10)
    let b = NSRange(location: 20, length: 10)
    #expect(constrain(caret(20), from: caret(5), embeds: [a, b]) == caret(20))
    #expect(constrain(NSRange(location: 15, length: 10), from: caret(0), embeds: [b, a])
      == NSRange(location: 10, length: 20))
    // Stepping over the first lands on the shared edge, which is allowed.
    #expect(constrain(caret(12), from: caret(10), embeds: [a, b]) == caret(20))
  }

  @Test("embed at document start and at document end")
  func documentEnds() {
    let first = NSRange(location: 0, length: 8)
    let last = NSRange(location: 40, length: 10)
    let all = [first, last]
    #expect(constrain(caret(3), from: caret(8), embeds: all) == caret(0))
    #expect(constrain(caret(45), from: caret(40), embeds: all) == caret(50))
    #expect(constrain(NSRange(location: 0, length: 3), from: caret(0), embeds: all) == first)
    #expect(constrain(NSRange(location: 45, length: 5), from: caret(50), embeds: all) == last)
  }

  // MARK: - click

  @Test("a click anywhere on the row selects the whole block")
  func clickSelectsWhole() {
    for loc in [10, 11, 20, 29] {
      #expect(EmbedSelection.constrainClick(proposed: caret(loc), embeds: [embed]) == embed)
    }
  }

  @Test("a second click on the same row selects the same block, never an edge")
  func secondClick() {
    let once = EmbedSelection.constrainClick(proposed: caret(66 - 40), embeds: [embed])
    let twice = EmbedSelection.constrainClick(proposed: caret(12), embeds: [embed])
    #expect(once == embed)
    #expect(twice == embed)
  }

  @Test("a click outside every embed places the caret as usual")
  func clickOutside() {
    #expect(EmbedSelection.constrainClick(proposed: caret(5), embeds: [embed]) == caret(5))
    #expect(EmbedSelection.constrainClick(proposed: caret(30), embeds: [embed]) == caret(30))
    #expect(EmbedSelection.constrainClick(proposed: caret(5), embeds: []) == caret(5))
  }

  @Test("a click on an adjacent embed's row selects that one only")
  func clickAdjacent() {
    let a = NSRange(location: 10, length: 10)
    let b = NSRange(location: 20, length: 10)
    #expect(EmbedSelection.constrainClick(proposed: caret(20), embeds: [a, b]) == b)
    #expect(EmbedSelection.constrainClick(proposed: caret(19), embeds: [a, b]) == a)
  }

  // MARK: - deletionRange

  @Test("a middle block takes its following blank line")
  func deleteMiddle() {
    let text = "A\n\nBBB\nBBB\n\nC\n" as NSString
    let block = NSRange(location: 3, length: 8)
    #expect(EmbedSelection.deletionRange(for: block, in: text) == NSRange(location: 3, length: 9))
  }

  @Test("the last block takes its preceding blank line")
  func deleteLast() {
    let text = "A\n\nBBB\n" as NSString
    let block = NSRange(location: 3, length: 4)
    #expect(EmbedSelection.deletionRange(for: block, in: text) == NSRange(location: 2, length: 5))
  }

  @Test("a block with no blank neighbour takes only itself")
  func deleteNoBlank() {
    let text = "A\nBBB\nC\n" as NSString
    let block = NSRange(location: 2, length: 4)
    #expect(EmbedSelection.deletionRange(for: block, in: text) == block)
  }

  @Test("a block at document start takes its following blank line")
  func deleteFirst() {
    let text = "BBB\n\nC\n" as NSString
    let block = NSRange(location: 0, length: 4)
    #expect(EmbedSelection.deletionRange(for: block, in: text) == NSRange(location: 0, length: 5))
  }

  @Test("the following blank line wins over the preceding one")
  func followingWins() {
    let text = "A\n\nBBB\n\nC\n" as NSString
    let block = NSRange(location: 3, length: 4)
    let del = EmbedSelection.deletionRange(for: block, in: text)
    #expect(del == NSRange(location: 3, length: 5))
    #expect(text.replacingCharacters(in: del, with: "") == "A\n\nC\n")
  }

  @Test("a whitespace-only line counts as blank")
  func whitespaceBlank() {
    let text = "BBB\n  \nC\n" as NSString
    let block = NSRange(location: 0, length: 4)
    #expect(EmbedSelection.deletionRange(for: block, in: text) == NSRange(location: 0, length: 7))
  }

  // MARK: - delete key symmetry

  @Test("backspace just after an embed selects it; a second press deletes it")
  func backspaceSelectsThenDeletes() {
    let text = "A\n\nBBB\n\nC\n" as NSString
    let block = NSRange(location: 3, length: 4)
    let first = EmbedSelection.deleteAction(
      selection: caret(7), forward: false, embeds: [block], in: text)
    #expect(first == .select(block))
    let second = EmbedSelection.deleteAction(
      selection: block, forward: false, embeds: [block], in: text)
    #expect(second == .delete(NSRange(location: 3, length: 5)))
  }

  @Test("forward-delete just before an embed behaves the same way")
  func forwardDeleteSymmetric() {
    let text = "A\n\nBBB\n\nC\n" as NSString
    let block = NSRange(location: 3, length: 4)
    #expect(
      EmbedSelection.deleteAction(selection: caret(3), forward: true, embeds: [block], in: text)
        == .select(block))
    #expect(
      EmbedSelection.deleteAction(selection: block, forward: true, embeds: [block], in: text)
        == EmbedSelection.deleteAction(selection: block, forward: false, embeds: [block], in: text))
  }

  @Test("the wrong-direction key at an edge, or a caret elsewhere, passes through")
  func deletePassThrough() {
    let text = "A\n\nBBB\n\nC\n" as NSString
    let block = NSRange(location: 3, length: 4)
    #expect(
      EmbedSelection.deleteAction(selection: caret(3), forward: false, embeds: [block], in: text)
        == .passThrough)
    #expect(
      EmbedSelection.deleteAction(selection: caret(7), forward: true, embeds: [block], in: text)
        == .passThrough)
    #expect(
      EmbedSelection.deleteAction(selection: caret(0), forward: false, embeds: [block], in: text)
        == .passThrough)
    #expect(
      EmbedSelection.deleteAction(
        selection: NSRange(location: 0, length: 3), forward: false, embeds: [block], in: text)
        == .passThrough)
  }

  @Test("between adjacent embeds backspace selects the first and forward-delete the second")
  func deleteBetweenAdjacent() {
    let text = "AAA\nBBB\nC\n" as NSString
    let a = NSRange(location: 0, length: 4)
    let b = NSRange(location: 4, length: 4)
    #expect(
      EmbedSelection.deleteAction(selection: caret(4), forward: false, embeds: [a, b], in: text)
        == .select(a))
    #expect(
      EmbedSelection.deleteAction(selection: caret(4), forward: true, embeds: [a, b], in: text)
        == .select(b))
  }

  // MARK: - edit rule

  @Test("an insertion strictly inside an embed is vetoed; at its edges it is allowed")
  func insertion() {
    #expect(!EmbedSelection.allowsEdit(range: caret(15), replacementLength: 1, embeds: [embed]))
    #expect(EmbedSelection.allowsEdit(range: caret(10), replacementLength: 1, embeds: [embed]))
    #expect(EmbedSelection.allowsEdit(range: caret(30), replacementLength: 1, embeds: [embed]))
    #expect(EmbedSelection.allowsEdit(range: caret(3), replacementLength: 1, embeds: [embed]))
  }

  @Test("removing part of an embed is vetoed")
  func partialRemoval() {
    #expect(!EmbedSelection.allowsEdit(
      range: NSRange(location: 12, length: 3), replacementLength: 0, embeds: [embed]))
    #expect(!EmbedSelection.allowsEdit(
      range: NSRange(location: 5, length: 10), replacementLength: 0, embeds: [embed]))
    #expect(!EmbedSelection.allowsEdit(
      range: NSRange(location: 25, length: 10), replacementLength: 0, embeds: [embed]))
    #expect(!EmbedSelection.allowsEdit(
      range: NSRange(location: 29, length: 1), replacementLength: 0, embeds: [embed]))
  }

  @Test("deleting exactly the deletion range, or ranges containing whole embeds, is allowed")
  func wholeRemoval() {
    let text = "A\n\nBBB\n\nC\n" as NSString
    let block = NSRange(location: 3, length: 4)
    let del = EmbedSelection.deletionRange(for: block, in: text)
    #expect(EmbedSelection.allowsEdit(range: del, replacementLength: 0, embeds: [block]))
    #expect(EmbedSelection.allowsEdit(range: block, replacementLength: 0, embeds: [block]))
    #expect(EmbedSelection.allowsEdit(
      range: NSRange(location: 0, length: text.length), replacementLength: 0, embeds: [block]))
    #expect(EmbedSelection.allowsEdit(
      range: NSRange(location: 0, length: 3), replacementLength: 0, embeds: [block]))
  }

  @Test("a range that swallows one embed whole but clips its neighbour is vetoed")
  func clippingNeighbour() {
    let a = NSRange(location: 10, length: 10)
    let b = NSRange(location: 20, length: 10)
    #expect(!EmbedSelection.allowsEdit(
      range: NSRange(location: 5, length: 20), replacementLength: 0, embeds: [a, b]))
    #expect(EmbedSelection.allowsEdit(
      range: NSRange(location: 5, length: 25), replacementLength: 0, embeds: [a, b]))
  }
}
