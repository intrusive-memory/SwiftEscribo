/// `#`.
private let numberSign: UInt16 = 0x23

/// `` ` ``.
private let backtick: UInt16 = 0x60

/// `~`.
private let tilde: UInt16 = 0x7E

/// A space.
private let space: UInt16 = 0x20

/// A horizontal tab.
private let tab: UInt16 = 0x09

/// Whether `unit` is a space or a tab. The only two characters CommonMark counts as
/// indentation, and the only two this grammar ever skips.
private func isSpaceOrTab(_ unit: UInt16) -> Bool { unit == space || unit == tab }

/// The Markdown grammar: ATX headings and fenced code blocks, and nothing else yet.
///
/// This is the first real grammar through the ``LineGrammar`` seam, and it is
/// deliberately tiny. Its job is to prove the substrate — a stateful multi-line
/// construct that convergence can observe, a marker/content span pair that the styler
/// can dim without a special case, a `contentRange` that excludes syntax — before
/// Sorties 18 through 20 build lists, blockquotes, emphasis, links, tables, and
/// frontmatter on top of it. Everything it does not recognize degrades to
/// ``ElementKind/paragraph`` and a ``SpanKind/text`` span, which is what "malformed
/// constructs degrade to text" means in practice: the absence of a case, not a case.
///
/// ## Hand-written, per the charter
///
/// Every decision below is a code-unit comparison against `line.units`. There is no
/// regex anywhere in this file and there never will be — replacing a regex-based parser
/// is the reason this package exists (AGENTS.md).
///
/// ## Lookahead
///
/// Zero. Both constructs are decided by the line's own text plus the state it begins
/// in: a heading is a heading on sight, and a fence line's meaning depends on whether a
/// fence is *already* open, which arrives from above rather than below. Fountain's
/// character cue — the construct that genuinely needs lookahead — is Sortie 14's.
struct MarkdownGrammar: LineGrammar {

  /// The ``LineState/openConstruct`` tag meaning "a fenced code block is open".
  ///
  /// Its meaning belongs to this grammar; the scanner only ever compares it.
  static let fenceTag: UInt16 = 1

  var lookahead: Int { 0 }

  func scanLine(_ window: LineWindow, state: LineState) -> LineScan {
    let line = window.current

    // Inside a fence, nothing else is syntax. A `#` is a hash and a `~~~` is three
    // tildes unless the open fence was opened with tildes and is no longer than this
    // run — which is exactly why the character and the length are carried in the state.
    if state.openConstruct == Self.fenceTag {
      return scanInsideFence(line, state: state)
    }
    if let scan = scanFenceOpening(line) {
      return scan
    }
    if let scan = scanHeading(line, state: state) {
      return scan
    }
    return scanPlain(line, state: state)
  }

  // MARK: - ATX headings

  /// Scans `# Heading` … `###### Heading`, or returns `nil` if the line is not one.
  ///
  /// The span layout is the point of this method, and it is the layout the whole
  /// marker/content design rests on: the `#` run **and the whitespace after it** are one
  /// span, the heading text is another, and both carry ``SpanKind/heading`` with the
  /// same ``StyleSet``. They differ only in ``SpanRole``. Sortie 7's styler therefore
  /// resolves attributes from kind and style once and multiplies the foreground alpha
  /// when the role is ``SpanRole/marker`` — "the hashes show, dimmed, while the text
  /// renders as a heading" falls out of the data, with no case for it anywhere.
  ///
  /// The level goes in ``LineScan/depth``, never into a `.heading1`…`.heading6`
  /// vocabulary, so paragraph geometry keyed by `(ElementKind, depth)` covers all six
  /// levels with one entry shape.
  private func scanHeading(_ line: GrammarLine, state: LineState) -> LineScan? {
    let units = line.units
    let indent = leadingIndent(units)
    // Four columns of indent is an indented code block in CommonMark, not a heading.
    // Indented code is Sortie 18's; until then such a line is a paragraph, which is a
    // degradation to text rather than a misclassification.
    guard indent.columns <= 3 else { return nil }

    var cursor = indent.units
    var level = 0
    while cursor < units.count, units[cursor] == numberSign {
      level += 1
      cursor += 1
    }
    guard level >= 1, level <= 6 else { return nil }
    // `#hashtag` is not a heading: the run must be followed by whitespace or end there.
    guard cursor == units.count || isSpaceOrTab(units[cursor]) else { return nil }

    // The marker swallows the whitespace between the hashes and the text, so the
    // content span begins at the first character a reader sees.
    var contentStart = cursor
    while contentStart < units.count, isSpaceOrTab(units[contentStart]) {
      contentStart += 1
    }

    // A trailing run of hashes is a closing sequence only when the run is preceded by
    // whitespace or is the entire remainder — `# a#` keeps its hash, `# a #` does not.
    var trailingStart = units.count
    while trailingStart > contentStart, isSpaceOrTab(units[trailingStart - 1]) {
      trailingStart -= 1
    }
    var closingStart = trailingStart
    while closingStart > contentStart, units[closingStart - 1] == numberSign {
      closingStart -= 1
    }
    let hasClosingSequence =
      closingStart < trailingStart
      && (closingStart == contentStart || isSpaceOrTab(units[closingStart - 1]))

    var contentEnd = hasClosingSequence ? closingStart : trailingStart
    while contentEnd > contentStart, isSpaceOrTab(units[contentEnd - 1]) {
      contentEnd -= 1
    }

    let base = line.contentRange.lowerBound
    var spans: [EscriboSpan] = [
      EscriboSpan(
        range: (base + indent.units)..<(base + contentStart), kind: .heading, role: .marker)
    ]
    if contentEnd > contentStart {
      spans.append(
        EscriboSpan(range: (base + contentStart)..<(base + contentEnd), kind: .heading))
    }
    if hasClosingSequence {
      // The closing run, plus the whitespace on either side of it, so the tail of the
      // line stays heading-colored instead of falling through to `.text`.
      spans.append(
        EscriboSpan(
          range: (base + contentEnd)..<line.contentRange.upperBound, kind: .heading, role: .marker))
    }

    return LineScan(
      spans: spans,
      element: .heading,
      contentRange: (base + contentStart)..<(base + contentEnd),
      depth: level,
      endState: state
    )
  }

  // MARK: - Fenced code blocks

  /// Scans an opening ```` ``` ```` or `~~~` line, or returns `nil` if the line is not
  /// one.
  ///
  /// The fence's character and run length go into the returned ``LineState``, which is
  /// the entire reason "opening a fence on line 1 dirties the rest of the document" is
  /// true rather than aspirational: the state entering every following line changes, so
  /// the convergence engine cannot stop until it finds a line whose recomputed state
  /// matches what was there before — and inside an unterminated fence it never does.
  private func scanFenceOpening(_ line: GrammarLine) -> LineScan? {
    let units = line.units
    let indent = leadingIndent(units)
    guard indent.columns <= 3, indent.units < units.count else { return nil }

    let character = units[indent.units]
    guard character == backtick || character == tilde else { return nil }

    var runEnd = indent.units
    while runEnd < units.count, units[runEnd] == character {
      runEnd += 1
    }
    let runLength = runEnd - indent.units
    guard runLength >= 3 else { return nil }

    let info = trimmedRange(of: units, from: runEnd)
    // A backtick-fenced block may not carry a backtick in its info string; otherwise
    // `` `` `x` `` `` on its own line would open a block instead of being a code span.
    if character == backtick {
      for offset in info where units[offset] == backtick { return nil }
    }

    let base = line.contentRange.lowerBound
    var spans: [EscriboSpan] = [
      EscriboSpan(
        range: (base + indent.units)..<(base + runEnd), kind: .codeBlock, role: .marker)
    ]
    if !info.isEmpty {
      // Sortie 21 reads this span's text to dispatch a `fountain` fence to the Fountain
      // scanner, which is why the info string is its own kind rather than part of the
      // marker.
      spans.append(
        EscriboSpan(
          range: (base + info.lowerBound)..<(base + info.upperBound), kind: .codeInfoString))
    }

    return LineScan(
      spans: spans,
      element: .codeFence,
      contentRange: (base + info.lowerBound)..<(base + info.upperBound),
      endState: LineState(
        openConstruct: Self.fenceTag,
        fenceCharacter: character,
        fenceLength: UInt16(min(runLength, Int(UInt16.max)))
      )
    )
  }

  /// Scans a line that begins inside an open fenced code block.
  ///
  /// Two outcomes and no third: the line closes the fence, or it is code. There is no
  /// failure case, which is what makes an unterminated fence scan to the end of the
  /// document and return normally — the state simply stays open, and the last line of
  /// the document is the last line of the block.
  private func scanInsideFence(_ line: GrammarLine, state: LineState) -> LineScan {
    let units = line.units
    let base = line.contentRange.lowerBound

    if let runEnd = closingFenceEnd(units, state: state) {
      return LineScan(
        spans: [
          EscriboSpan(
            range: (base + leadingIndent(units).units)..<(base + runEnd), kind: .codeBlock,
            role: .marker)
        ],
        element: .codeFence,
        // A closing fence is pure delimiter: it has no content, so its content range is
        // the empty range where content would have started.
        contentRange: (base + runEnd)..<(base + runEnd),
        endState: LineState()
      )
    }

    return LineScan(
      spans: line.contentRange.isEmpty
        ? [] : [EscriboSpan(range: line.contentRange, kind: .codeBlock)],
      element: .codeBlock,
      // Everything on the line is code, including its leading whitespace: indentation is
      // significant inside a code block, so stripping it here would make the writer
      // lossy.
      contentRange: line.contentRange,
      endState: state
    )
  }

  /// The end offset, in `units`, of a closing fence run — or `nil` if this line does not
  /// close the open fence.
  ///
  /// A fence closes only with the character it opened with, only with a run at least as
  /// long as the opening one, and only when nothing but whitespace follows it. All three
  /// are CommonMark, and all three are why the state carries more than a boolean.
  private func closingFenceEnd(_ units: [UInt16], state: LineState) -> Int? {
    let indent = leadingIndent(units)
    guard indent.columns <= 3, indent.units < units.count else { return nil }
    guard units[indent.units] == state.fenceCharacter else { return nil }

    var runEnd = indent.units
    while runEnd < units.count, units[runEnd] == state.fenceCharacter {
      runEnd += 1
    }
    guard runEnd - indent.units >= Int(state.fenceLength) else { return nil }

    var trailing = runEnd
    while trailing < units.count, isSpaceOrTab(units[trailing]) {
      trailing += 1
    }
    guard trailing == units.count else { return nil }
    return runEnd
  }

  // MARK: - Everything else

  /// Anything this grammar does not recognize: a blank line, or a paragraph line.
  ///
  /// A whitespace-only line is **blank** in Markdown — CommonMark's block separator is
  /// "a line containing no characters, or only spaces and tabs" — which is a grammar's
  /// decision to make and differs from Fountain's, and is why ``GrammarLine/isEmpty``
  /// deliberately does not decide it.
  private func scanPlain(_ line: GrammarLine, state: LineState) -> LineScan {
    let isBlank = leadingIndent(line.units).units == line.units.count
    return LineScan(
      spans: line.contentRange.isEmpty
        ? [] : [EscriboSpan(range: line.contentRange, kind: .text)],
      element: isBlank ? .blank : .paragraph,
      contentRange: isBlank ? line.contentRange.lowerBound..<line.contentRange.lowerBound : nil,
      endState: state
    )
  }

  // MARK: - Shared line arithmetic

  /// The leading whitespace of `units`, in code units **and** in columns.
  ///
  /// Both numbers are needed and they are not the same number: the code-unit count is
  /// where the syntax starts, and the column count is what CommonMark's "up to three
  /// spaces of indentation" is stated in. A tab advances to the next multiple of four
  /// columns, which is the only place tab width is ever assumed in this grammar.
  private func leadingIndent(_ units: [UInt16]) -> (units: Int, columns: Int) {
    var offset = 0
    var columns = 0
    while offset < units.count {
      if units[offset] == space {
        columns += 1
      } else if units[offset] == tab {
        columns += 4 - (columns % 4)
      } else {
        break
      }
      offset += 1
    }
    return (offset, columns)
  }

  /// The range of `units` from `start` to the end, with whitespace trimmed off both
  /// ends. Empty — and positioned at the trimmed start — when there is nothing left.
  private func trimmedRange(of units: [UInt16], from start: Int) -> Range<Int> {
    var lower = start
    while lower < units.count, isSpaceOrTab(units[lower]) {
      lower += 1
    }
    var upper = units.count
    while upper > lower, isSpaceOrTab(units[upper - 1]) {
      upper -= 1
    }
    return lower..<upper
  }
}
