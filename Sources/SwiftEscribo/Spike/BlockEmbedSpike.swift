// SPIKE — throwaway code for the atomic block-embed experiment. Never merged.
import EscriboCore
import Foundation

/// What a host supplies to draw one embedded block as a single row.
struct SpikeEmbedContent: Equatable {
  var symbolName: String
  var title: String
  var subtitle: String
  var badge: String
  var accessibilityLabel: String
  var accessibilityValue: String
}

/// Embeds keyed by the UTF-16 offset of the block's first character, plus the set of
/// those that are currently expanded (drawn as ordinary text).
struct SpikeEmbedRegistry {
  var embeds: [Int: SpikeEmbedContent] = [:]
  var expanded: Set<Int> = []

  /// The ranges of blocks that are embedded and not expanded, in document order.
  func embeddedRanges(in blocks: [EscriboBlock]) -> [NSRange] {
    blocks
      .filter { embeds[$0.range.lowerBound] != nil && !expanded.contains($0.range.lowerBound) }
      .map { NSRange(location: $0.range.lowerBound, length: $0.range.count) }
      .sorted { $0.location < $1.location }
  }
}

/// Pure selection and deletion rules shared by both platforms.
enum SpikeEmbedSelection {

  /// Constrains a proposed selection so an embed is never entered.
  ///
  /// - A caret strictly inside an embed snaps to the edge in the direction of travel
  ///   (`proposed` after `previous` goes to the end; before goes to the start; a click that
  ///   does not move snaps to the nearer edge).
  /// - A non-empty selection that overlaps an embed grows to cover it whole.
  static func constrain(proposed: NSRange, previous: NSRange, embeds: [NSRange]) -> NSRange {
    var result = proposed
    for embed in embeds.sorted(by: { $0.location < $1.location }) {
      let start = embed.location
      let end = NSMaxRange(embed)
      if result.length == 0 {
        let loc = result.location
        guard loc > start && loc < end else { continue }
        let travel = loc - previous.location
        if travel > 0 {
          result = NSRange(location: end, length: 0)
        } else if travel < 0 {
          result = NSRange(location: start, length: 0)
        } else {
          result = NSRange(location: (loc - start) * 2 < embed.length ? start : end, length: 0)
        }
      } else {
        let lo = result.location
        let hi = NSMaxRange(result)
        // Overlap of positive length with the embed.
        guard lo < end && hi > start else { continue }
        let newLo = min(lo, start)
        let newHi = max(hi, end)
        result = NSRange(location: newLo, length: newHi - newLo)
      }
    }
    return result
  }

  /// The range to remove when an embed is deleted: the block, plus the following blank
  /// line; or, when no blank line follows, the preceding blank line; otherwise the block
  /// alone. `embed` follows the block-range convention (its final terminator is inside).
  static func deletionRange(for embed: NSRange, in text: NSString) -> NSRange {
    let end = NSMaxRange(embed)
    if let blank = blankLine(startingAt: end, in: text) {
      return NSRange(location: embed.location, length: NSMaxRange(blank) - embed.location)
    }
    if let blank = blankLine(endingAt: embed.location, in: text) {
      return NSRange(location: blank.location, length: end - blank.location)
    }
    return embed
  }

  /// The blank line (terminator included) that begins at `start`, if there is one.
  private static func blankLine(startingAt start: Int, in text: NSString) -> NSRange? {
    guard start < text.length else { return nil }
    var i = start
    while i < text.length {
      let c = text.character(at: i)
      if c == 0x0A { return NSRange(location: start, length: i + 1 - start) }
      if c != 0x20 && c != 0x09 && c != 0x0D { return nil }
      i += 1
    }
    return NSRange(location: start, length: text.length - start)
  }

  /// The blank line (terminator included) that ends exactly at `end`, if there is one.
  private static func blankLine(endingAt end: Int, in text: NSString) -> NSRange? {
    guard end >= 1, end <= text.length, text.character(at: end - 1) == 0x0A else { return nil }
    var i = end - 1
    while i > 0 {
      let c = text.character(at: i - 1)
      if c == 0x0A { break }
      if c != 0x20 && c != 0x09 && c != 0x0D { return nil }
      i -= 1
    }
    return NSRange(location: i, length: end - i)
  }
}
