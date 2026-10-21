import Foundation

extension EmbedSelection {

  // MARK: - The input rule (typing, Return, Tab, paste)

  /// The rule for edits that come from the writer's input — typing, Return, Tab, paste,
  /// a key-bound deletion — on top of ``allowsEdit(range:replacementLength:embeds:)``.
  ///
  /// `allowsEdit` keeps an edit from cutting into an embed. This also keeps one from
  /// **changing an embed's block from outside it**, which the scanner would otherwise
  /// accept quietly:
  ///
  /// 1. **Typing over a selected embed is ignored.** An edit whose range contains a whole
  ///    embed and whose replacement is non-empty is vetoed, so typing, Return, Tab and
  ///    paste with the block selected (alone or inside a wider selection) change nothing.
  ///    Removing it — Delete, forward-delete, Cut — has an empty replacement and is
  ///    allowed.
  /// 2. **Nothing joins the embed's first line.** The start edge is the start of the
  ///    block's first line, so text inserted there, by any route, would become part of
  ///    that line and change the block on the next scan. An edit that ends at an embed's
  ///    start is allowed only if the embed still starts a line afterwards: a replacement
  ///    ending in a line terminator (Return at the start edge pushes the block down a
  ///    line), or a deletion that leaves a terminator (or the document's start) before it.
  ///    Everything else — a typed character, a Tab, a paste that does not end in a
  ///    newline, Backspace across the newline above — is vetoed, **however the caret got
  ///    there** (arrow keys included). To write above an embed, put the caret on the line
  ///    above or press Return first.
  /// 3. **Nothing joins the embed's last line** when the block is the document's last and
  ///    has no final terminator: an insertion at its end edge must begin with one.
  ///
  /// Package edits that are not the writer's input (an external reset, undo and redo) do
  /// not go through this rule; the platform layer exempts them.
  ///
  /// - Parameters:
  ///   - range: The range being replaced, in UTF-16 code units of `text`.
  ///   - replacement: Its replacement.
  ///   - embeds: The embedded blocks' ranges (block-range convention).
  ///   - text: The document **before** the edit.
  static func allowsInput(
    range: NSRange, replacement: String, embeds: [NSRange], in text: NSString
  ) -> Bool {
    let replacementUnits = replacement.utf16
    guard
      allowsEdit(range: range, replacementLength: replacementUnits.count, embeds: embeds)
    else { return false }
    let lo = range.location
    let hi = NSMaxRange(range)
    for embed in embeds {
      let start = embed.location
      let end = NSMaxRange(embed)

      // 1. Typing over a selected embed.
      if !replacementUnits.isEmpty, range.length > 0, lo <= start, hi >= end { return false }

      // 2. The start edge.
      if hi == start {
        let stillStartsLine: Bool
        if let last = replacementUnits.last {
          stillStartsLine = isLineTerminator(last)
        } else if range.length == 0 {
          stillStartsLine = true  // an empty edit changes nothing
        } else {
          stillStartsLine = lo == 0 || isLineTerminator(text.character(at: lo - 1))
        }
        if !stillStartsLine { return false }
      }

      // 3. The end edge of an unterminated last block.
      if lo == end, end > start, end <= text.length, !isLineTerminator(text.character(at: end - 1)),
        let first = replacementUnits.first, !isLineTerminator(first)
      {
        return false
      }
    }
    return true
  }

  private static func isLineTerminator(_ unit: unichar) -> Bool {
    unit == 0x0A || unit == 0x0D
  }
}
