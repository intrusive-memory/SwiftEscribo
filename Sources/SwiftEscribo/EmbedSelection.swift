import Foundation

/// Pure selection, edit and deletion rules for embedded blocks, shared by both platforms.
///
/// An embedded block is drawn as one atomic row, so the editor never lets a caret or a
/// partial selection into it. Every function takes the embedded blocks as UTF-16 ranges
/// (the block-range convention: the block's final terminator is inside the range), sorted
/// or not. Nothing here touches a text view; the platform layers call these and apply the
/// answers.
enum EmbedSelection {

  /// What a Backspace or forward-delete key press should do.
  enum DeleteAction: Equatable {
    /// Select this embed whole; do not delete anything yet.
    case select(NSRange)
    /// Remove this range (an embed plus its adjacent blank line) as one edit.
    case delete(NSRange)
    /// Not an embed case: let the text view's default handling run.
    case passThrough
  }

  // MARK: - Selection

  /// Constrains a proposed selection so an embed is never entered.
  ///
  /// - A caret strictly inside an embed snaps to the edge in the direction of travel
  ///   (`proposed` after `previous` goes to the end, before goes to the start). With no
  ///   travel it snaps to the nearer edge.
  /// - A non-empty selection that overlaps an embed with positive length grows to cover
  ///   the whole block. A selection that only abuts an embed is left alone.
  /// - Carets at either edge of an embed are allowed.
  /// - `isFindMatch`: a selection set by Find passes through unchanged, so the host can
  ///   expand the embed that holds the match.
  static func constrain(
    proposed: NSRange,
    previous: NSRange,
    embeds: [NSRange],
    isFindMatch: Bool = false
  ) -> NSRange {
    guard !isFindMatch else { return proposed }
    return constrain(proposed, embeds: embeds) { loc, embed in
      let travel = loc - previous.location
      if travel > 0 { return NSMaxRange(embed) }
      if travel < 0 { return embed.location }
      return nearerEdge(of: embed, to: loc)
    }
  }

  /// The selection for a click or tap on an embed's row: the **whole block**, never an
  /// edge caret.
  ///
  /// A proposal whose caret (or selection) lands on an embed, start edge included and end
  /// edge excluded (the end edge is the next line), selects that block. A proposal that
  /// overlaps an embed grows to cover it. Anything else is returned unchanged, so a click
  /// outside every embed places the caret as usual. A second click on the same row selects
  /// the same block again; it never flips to an edge.
  static func constrainClick(proposed: NSRange, embeds: [NSRange]) -> NSRange {
    if proposed.length == 0 {
      let loc = proposed.location
      if let hit = embeds.first(where: { loc >= $0.location && loc < NSMaxRange($0) }) {
        return hit
      }
    }
    return constrain(proposed, embeds: embeds) { _, embed in embed.location }
  }

  /// Shared engine: snaps interior carets with `caretTarget`, grows overlapping
  /// selections, and repeats until stable so adjacent embeds are covered together.
  private static func constrain(
    _ proposed: NSRange,
    embeds: [NSRange],
    caretTarget: (_ location: Int, _ embed: NSRange) -> Int
  ) -> NSRange {
    let sorted = embeds.sorted { $0.location < $1.location }
    var result = proposed
    var changed = true
    var passes = 0
    while changed && passes <= sorted.count {
      changed = false
      passes += 1
      for embed in sorted {
        let start = embed.location
        let end = NSMaxRange(embed)
        let before = result
        if result.length == 0 {
          let loc = result.location
          guard loc > start && loc < end else { continue }
          result = NSRange(location: caretTarget(loc, embed), length: 0)
        } else {
          let lo = result.location
          let hi = NSMaxRange(result)
          guard lo < end && hi > start else { continue }
          let newLo = min(lo, start)
          result = NSRange(location: newLo, length: max(hi, end) - newLo)
        }
        if result != before { changed = true }
      }
    }
    return result
  }

  private static func nearerEdge(of embed: NSRange, to loc: Int) -> Int {
    (loc - embed.location) * 2 < embed.length ? embed.location : NSMaxRange(embed)
  }

  // MARK: - Deletion

  /// The range to remove when an embed is deleted: the block plus the following blank
  /// line; when no blank line follows, the preceding blank line; otherwise the block
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

  /// Backspace and forward-delete behave the same way at an embed's edges (they are
  /// symmetric, the way editors treat an atomic attachment):
  ///
  /// - Backspace with the caret just after an embed, or forward-delete with the caret just
  ///   before one, **selects** the embed first.
  /// - With exactly one embed selected, either key **deletes** `deletionRange` (the block
  ///   plus an adjacent blank line) as one edit.
  /// - Anything else (a caret elsewhere, a selection that is not exactly one embed) is
  ///   `.passThrough`; the edit rule in ``allowsEdit(range:replacementLength:embeds:)``
  ///   still vetoes anything that would cut an embed in part.
  static func deleteAction(
    selection: NSRange,
    forward: Bool,
    embeds: [NSRange],
    in text: NSString
  ) -> DeleteAction {
    if selection.length > 0 {
      guard embeds.contains(selection) else { return .passThrough }
      return .delete(deletionRange(for: selection, in: text))
    }
    let caret = selection.location
    let target = embeds.first { forward ? $0.location == caret : NSMaxRange($0) == caret }
    return target.map(DeleteAction.select) ?? .passThrough
  }

  // MARK: - Edits

  /// The edit rule: an edit that inserts into, or removes part of, an embed is vetoed.
  ///
  /// Allowed: an edit that does not touch any embed's interior, an insertion at an
  /// embed's edge (the caret may sit there), and an edit whose range fully contains whole
  /// embeds, which covers deleting exactly ``deletionRange(for:in:)``. Vetoed: a
  /// zero-length insertion strictly inside an embed, and a range that overlaps an embed
  /// without containing all of it.
  static func allowsEdit(range: NSRange, replacementLength: Int, embeds: [NSRange]) -> Bool {
    let lo = range.location
    let hi = NSMaxRange(range)
    for embed in embeds {
      let start = embed.location
      let end = NSMaxRange(embed)
      if range.length == 0 {
        if lo > start && lo < end { return false }
      } else if lo < end && hi > start {
        if !(lo <= start && hi >= end) { return false }
      }
    }
    return true
  }

  // MARK: - Blank lines

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
