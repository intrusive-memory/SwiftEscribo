/// `*` — italics once, bold twice, both three times.
private let asterisk: UInt16 = 0x2A

/// `_` — underline.
private let underscore: UInt16 = 0x5F

/// `\` — the escape that makes the next emphasis character literal.
private let backslash: UInt16 = 0x5C

/// A space.
private let space: UInt16 = 0x20

/// A horizontal tab.
private let tab: UInt16 = 0x09

/// Fountain's inline emphasis: `*italics*`, `**bold**`, `***bold italics***`,
/// `_underline_`, and `\*` / `\_` / `\\` for the characters themselves.
///
/// Applied to one line's content span at a time, because Fountain emphasis never crosses a
/// line break. The span comes back split into pieces that tile it exactly: the delimiters
/// as ``SpanRole/marker`` spans and the text between them as content spans carrying the
/// ``StyleSet`` bits — the same shape ``MarkdownInline`` produces, so a consumer that strips
/// markers and applies styles handles both languages with one rule. The kind is untouched:
/// emphasis inside dialogue is still `.dialogue`.
///
/// The matching follows CommonMark's delimiter-run algorithm in miniature, without the
/// rule of three: an opener spends from its right end and a closer from its left, two at
/// a time while both sides have two, so `***x***` is strong inside emphasis. A run can
/// open only when a non-space follows it and close only when a non-space precedes it,
/// which keeps `2 * 3 * 4` arithmetic. An underscore additionally may not open after, or
/// close before, a letter or digit, so `snake_case_name` stays text.
enum FountainEmphasis {

  /// The elements whose content can carry emphasis. The ones whose content is a name
  /// (cues), a structural marker (page breaks), or already non-printing (notes, boneyard,
  /// sections, synopses) are left alone, as are scene headings and transitions, which
  /// formatters print in capitals with no styling of their own.
  static let elements: Set<ElementKind> = [
    .action, .dialogue, .parenthetical, .lyrics, .centered,
  ]

  /// Splits every content-role span of `scan` into emphasis pieces, when `scan`'s element
  /// carries emphasis. Delimiters inside `covered` — notes and boneyards, which are text
  /// of their own — are never syntax.
  static func applied(
    to scan: LineScan, units: [UInt16], base: Int, covered: [Range<Int>]
  ) -> LineScan {
    guard elements.contains(scan.element) else { return scan }
    var scan = scan
    scan.spans = scan.spans.flatMap { span -> [EscriboSpan] in
      guard span.role == .content else { return [span] }
      return pieces(of: span, units: units, base: base, covered: covered)
    }
    return scan
  }

  /// One delimiter run: consecutive `*`s or consecutive `_`s.
  private struct Run {
    let character: UInt16
    let start: Int
    let length: Int
    var remaining: Int
    let canOpen: Bool
    let canClose: Bool
  }

  /// What one code unit came to: the style bits over it, and whether it is syntax.
  private struct Attribute: Equatable {
    var style: UInt16 = 0
    var isMarker = false
  }

  /// `span` split into emphasis pieces tiling it exactly, or `[span]` when it has none.
  static func pieces(
    of span: EscriboSpan, units: [UInt16], base: Int, covered: [Range<Int>]
  ) -> [EscriboSpan] {
    let range = span.range
    // The fast path, and the common one: most lines of a screenplay contain no emphasis
    // character at all, and they pay one scan of their units and no allocation.
    guard
      range.contains(where: {
        let unit = units[$0 - base]
        return unit == asterisk || unit == underscore || unit == backslash
      })
    else { return [span] }

    func unit(_ offset: Int) -> UInt16 { units[offset - base] }
    func isCovered(_ offset: Int) -> Bool { covered.contains { $0.contains(offset) } }
    func isWhitespace(_ unit: UInt16) -> Bool { unit == space || unit == tab }
    func isAlphanumeric(_ unit: UInt16) -> Bool {
      (unit >= 0x30 && unit <= 0x39) || (unit >= 0x41 && unit <= 0x5A)
        || (unit >= 0x61 && unit <= 0x7A) || unit >= 0x80
    }

    var attributes = [Attribute](repeating: Attribute(), count: range.count)
    var runs: [Run] = []

    var cursor = range.lowerBound
    while cursor < range.upperBound {
      if isCovered(cursor) {
        cursor += 1
        continue
      }
      let current = unit(cursor)
      if current == backslash {
        // The escape is a marker and the character after it is literal text, so the walk
        // steps over it before the run collector can see it.
        if cursor + 1 < range.upperBound, !isCovered(cursor + 1) {
          let next = unit(cursor + 1)
          if next == asterisk || next == underscore || next == backslash {
            attributes[cursor - range.lowerBound].isMarker = true
            cursor += 2
            continue
          }
        }
        cursor += 1
        continue
      }
      guard current == asterisk || current == underscore else {
        cursor += 1
        continue
      }
      var end = cursor
      while end < range.upperBound, unit(end) == current, !isCovered(end) {
        end += 1
      }
      // The edges of the span read as whitespace: emphasis cannot reach outside the line's
      // content, so a run at either end has nothing on that side to flank.
      let before = cursor > range.lowerBound ? unit(cursor - 1) : space
      let after = end < range.upperBound ? unit(end) : space
      var canOpen = !isWhitespace(after)
      var canClose = !isWhitespace(before)
      if current == underscore {
        canOpen = canOpen && !isAlphanumeric(before)
        canClose = canClose && !isAlphanumeric(after)
      }
      runs.append(
        Run(
          character: current, start: cursor, length: end - cursor, remaining: end - cursor,
          canOpen: canOpen, canClose: canClose))
      cursor = end
    }

    var openers: [Int] = []
    for closer in runs.indices {
      if runs[closer].canClose {
        while runs[closer].remaining > 0,
          let slot = openers.lastIndex(where: {
            runs[$0].character == runs[closer].character && runs[$0].remaining > 0
          })
        {
          let opener = openers[slot]
          let use =
            runs[opener].character == underscore
            ? 1 : ((runs[opener].remaining >= 2 && runs[closer].remaining >= 2) ? 2 : 1)
          let openerSpentEnd = runs[opener].start + runs[opener].remaining
          let openerSpentStart = openerSpentEnd - use
          let closerSpentStart = runs[closer].start + runs[closer].length - runs[closer].remaining
          let closerSpentEnd = closerSpentStart + use
          let bit =
            runs[opener].character == underscore
            ? StyleSet.underline.rawValue
            : (use == 2 ? StyleSet.strong.rawValue : StyleSet.emphasis.rawValue)
          for offset in openerSpentStart..<closerSpentEnd {
            attributes[offset - range.lowerBound].style |= bit
          }
          for offset in openerSpentStart..<openerSpentEnd {
            attributes[offset - range.lowerBound].isMarker = true
          }
          for offset in closerSpentStart..<closerSpentEnd {
            attributes[offset - range.lowerBound].isMarker = true
          }
          runs[opener].remaining -= use
          runs[closer].remaining -= use
          // Openers between the pair are inside it and never matched: they are text now.
          openers.removeSubrange((slot + 1)..<openers.count)
          if runs[opener].remaining == 0 { openers.remove(at: slot) }
        }
      }
      if runs[closer].canOpen, runs[closer].remaining > 0 {
        openers.append(closer)
      }
    }

    var spans: [EscriboSpan] = []
    var start = range.lowerBound
    while start < range.upperBound {
      let attribute = attributes[start - range.lowerBound]
      var end = start + 1
      while end < range.upperBound, attributes[end - range.lowerBound] == attribute {
        end += 1
      }
      spans.append(
        EscriboSpan(
          range: start..<end, kind: span.kind,
          style: span.style.union(StyleSet(rawValue: attribute.style)),
          role: attribute.isMarker ? .marker : span.role))
      start = end
    }
    return spans
  }
}
