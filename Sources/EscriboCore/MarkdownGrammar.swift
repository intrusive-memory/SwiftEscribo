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

/// `-`.
private let hyphen: UInt16 = 0x2D

/// `_`.
private let underscore: UInt16 = 0x5F

/// `*`.
private let asterisk: UInt16 = 0x2A

/// `+`.
private let plusSign: UInt16 = 0x2B

/// `=`.
private let equalsSign: UInt16 = 0x3D

/// `>`.
private let greaterThan: UInt16 = 0x3E

/// `.`.
private let fullStop: UInt16 = 0x2E

/// `)`.
private let rightParenthesis: UInt16 = 0x29

/// `0`.
private let digitZero: UInt16 = 0x30

/// `9`.
private let digitNine: UInt16 = 0x39

/// Whether `unit` is a space or a tab. The only two characters CommonMark counts as
/// indentation, and the only two this grammar ever skips.
private func isSpaceOrTab(_ unit: UInt16) -> Bool { unit == space || unit == tab }

/// Whether `unit` is an ASCII digit.
private func isDigit(_ unit: UInt16) -> Bool { unit >= digitZero && unit <= digitNine }

/// Whether `unit` is one of CommonMark's three bullet-list markers.
private func isBullet(_ unit: UInt16) -> Bool {
  unit == hyphen || unit == plusSign || unit == asterisk
}

// MARK: - Block-container state

/// The Markdown block-container context a line begins in: whether a paragraph is open,
/// and the list items enclosing it.
///
/// This is the Markdown half of ``LineState``, and it is a value of scalars for the same
/// reason ``LineState/openConstruct`` is a scalar: one `LineState` is stored **per line
/// for the whole document**, so a field that allocates would put one allocation per line
/// on the cheapest thing the scanner does. A list nesting stack is genuinely a stack, so
/// it is packed into a single `UInt64` rather than held in an array.
///
/// Everything here participates in ``LineState``'s equality, which is what makes it
/// convergence state rather than bookkeeping: opening a list item, or leaving a paragraph
/// open across a line, changes how every following line scans, and the incremental
/// scanner must not stop until it has proved that change has washed out.
struct MarkdownBlockState: Equatable, Sendable {

  /// How many levels of list nesting are tracked **exactly**.
  ///
  /// Eight, because the stack is eight bytes. A ninth level is not an error and is not
  /// misclassified: it takes the eighth level's slot, so its content column keeps
  /// advancing and everything inside it still scans as list content — only `depth`
  /// saturates, and only outdenting back through the levels past the eighth is
  /// approximate. Nine levels of Markdown list nesting is not a document anyone writes,
  /// and paying an allocation per line to describe one would be.
  static let maxTrackedDepth = 8

  /// The largest **visual column** a tracked list item's content may begin at.
  ///
  /// One byte per level, so 255. A list item whose content starts past column 255 is
  /// recorded as starting *at* column 255, which can only make a following line look like
  /// a sibling when it was a child — a depth that is too shallow by one, never a crash.
  static let maxTrackedColumn = 255

  /// Whether the previous line was a paragraph line whose paragraph is still open.
  ///
  /// Three separate CommonMark rules read this and no other state, which is why it is a
  /// field rather than something re-derived:
  ///
  /// 1. `---` under a paragraph is a **setext heading underline**, not a thematic break.
  /// 2. An indented code block **cannot interrupt** a paragraph — four spaces under a
  ///    paragraph line is continuation text, not code.
  /// 3. A list item can interrupt a paragraph only when it is non-empty, and an ordered
  ///    one only when it starts at 1.
  var paragraphOpen: Bool = false

  /// The **visual column** at which each open list item's content begins, packed one byte
  /// per nesting level with level 0 in the low byte. A zero byte terminates the stack.
  ///
  /// Zero is a safe terminator because a list item's content never begins at column 0 —
  /// the marker occupies at least column 0 — so no real entry can be mistaken for the end
  /// of the stack.
  ///
  /// The stack is strictly increasing by construction: a child item's marker sits at or
  /// past its parent's content column, and its own content sits past its marker.
  var contentColumns: UInt64 = 0

  /// How many list items are open.
  var listDepth: Int {
    var depth = 0
    while depth < Self.maxTrackedDepth, column(atLevel: depth) != 0 { depth += 1 }
    return depth
  }

  /// The **visual column** at which the innermost open list item's content begins, or `0`
  /// when no list is open. The base every other column measurement on the line is taken
  /// relative to.
  var innermostContentColumn: Int {
    let depth = listDepth
    return depth == 0 ? 0 : column(atLevel: depth - 1)
  }

  /// The content column recorded for `level`, or `0` if that level is not open.
  func column(atLevel level: Int) -> Int {
    guard level >= 0, level < Self.maxTrackedDepth else { return 0 }
    return Int((contentColumns >> (UInt64(level) * 8)) & 0xFF)
  }

  /// Closes every open list item whose content begins **past** `column`.
  ///
  /// This one rule decides list nesting, and it is worth stating why it is the only rule
  /// needed. A line at visual column *c* is inside an open item exactly when *c* is at or
  /// past that item's content column; otherwise it has outdented past it, and past every
  /// item nested inside it. Popping until that stops leaves the innermost item the line
  /// actually sits in on top, so the depth of a new marker is simply how many items are
  /// left — no separate sibling case, because a sibling is what a marker becomes once its
  /// predecessor has been popped.
  ///
  /// - Parameter column: A **visual column**, not a code-unit offset.
  mutating func popLists(deeperThan column: Int) {
    var depth = listDepth
    while depth > 0, self.column(atLevel: depth - 1) > column {
      setColumn(atLevel: depth - 1, to: 0)
      depth -= 1
    }
  }

  /// Opens a list item whose content begins at `contentColumn`.
  ///
  /// - Parameter contentColumn: A **visual column**. Clamped into `1...255`; see
  ///   ``maxTrackedColumn``. At ``maxTrackedDepth`` the new item **replaces** the deepest
  ///   tracked one rather than being dropped: dropping it would freeze the content column
  ///   the next line is measured against, and a tenth-level list item would come back as
  ///   an indented code block. Replacing keeps the classification right and costs only the
  ///   exact depth, which has already saturated.
  mutating func pushList(contentColumn: Int) {
    let level = min(listDepth, Self.maxTrackedDepth - 1)
    setColumn(atLevel: level, to: min(max(contentColumn, 1), Self.maxTrackedColumn))
  }

  private mutating func setColumn(atLevel level: Int, to value: Int) {
    let shift = UInt64(level) * 8
    contentColumns = (contentColumns & ~(UInt64(0xFF) << shift)) | (UInt64(value) << shift)
  }
}

// MARK: - The grammar

/// The Markdown grammar: CommonMark **block** structure.
///
/// ATX headings and fenced code arrived in Sortie 5, and indented code, lists,
/// blockquotes, thematic breaks, and setext heading underlines in Sortie 18. Inline
/// structure — emphasis, links, code spans — is Sortie 19's and is deliberately absent:
/// everything this grammar does not recognize degrades to ``ElementKind/paragraph`` and a
/// ``SpanKind/text`` span, which is what "malformed constructs degrade to text" means in
/// practice — the absence of a case, not a case.
///
/// ## Hand-written, per the charter
///
/// Every decision below is a code-unit comparison against `line.units`. There is no regex
/// anywhere in this file and there never will be — replacing a regex-based parser is the
/// reason this package exists (AGENTS.md).
///
/// ## Columns are code units, and tab stops are four columns
///
/// Every column in this file is a **visual column** in the CommonMark sense, computed by
/// ``visualColumn(of:upTo:)``: one column per **UTF-16 code unit**, except a tab, which
/// advances to the next multiple of four. Two consequences, both load-bearing:
///
/// - An astral-plane character is two code units and therefore two columns. A grammar
///   that counted `Character`s would be correct on every ASCII document and wrong on
///   every real one, which is precisely the defect that survives casual testing
///   (REQUIREMENTS.md § Unicode).
/// - A tab is four columns *from a tab stop*, not one column and not four columns from
///   wherever it happens to sit: a tab at column 0 lands at column 4, and so does a tab at
///   column 2 (REQUIREMENTS.md § Degenerate input).
///
/// ## Lookahead
///
/// Zero. Every construct here is decided by the line's own text plus the state it begins
/// in. That includes the setext underline, which reads ``MarkdownBlockState/paragraphOpen``
/// arriving from above rather than looking at the line below.
///
/// **Known gap, deliberate:** because lookahead is zero, a setext underline classifies
/// *itself* as ``ElementKind/heading`` and does **not** retro-classify the paragraph line
/// above it. Doing that requires `lookahead == 1` and the matching backward extent — the
/// same machinery Fountain's character cue needs — and it is not this sortie's. A
/// consumer that wants the heading *text* for a setext heading must read the line above a
/// `heading` record whose content range is empty.
///
/// ## What block structure this grammar does not model
///
/// It is a **line** grammar, so `element` and `depth` describe one line and there is no
/// container tree. Two consequences a later sortie must know:
///
/// - Blockquote content is not re-scanned as Markdown. `> # Title` is one
///   ``ElementKind/blockquote`` line, not a heading inside a quote. Expressing both at
///   once needs a container axis on ``LineRecord``, which is public API.
/// - A list item's own content is likewise not re-scanned: `- # Title` is a list item.
struct MarkdownGrammar: LineGrammar {

  /// The ``LineState/openConstruct`` tag meaning "a fenced code block is open".
  ///
  /// Its meaning belongs to this grammar; the scanner only ever compares it.
  static let fenceTag: UInt16 = 1

  /// The width of a CommonMark tab stop, in **visual columns**.
  ///
  /// Four, and stated once. A tab width of one is the classic way indented code stops
  /// being recognized in a tab-indented document while every space-indented fixture keeps
  /// passing.
  static let tabStopColumns = 4

  /// How many visual columns of indentation a block construct may carry before it becomes
  /// indented code instead. Measured **relative to the enclosing list item's content
  /// column**, not from the left margin.
  static let maxConstructIndentColumns = 3

  var lookahead: Int { 0 }

  func scanLine(_ window: LineWindow, state: LineState) -> LineScan {
    let line = window.current

    // Inside a fence, nothing else is syntax. A `#` is a hash and a `~~~` is three
    // tildes unless the open fence was opened with tildes and is no longer than this
    // run — which is exactly why the character and the length are carried in the state.
    if state.openConstruct == Self.fenceTag {
      return scanInsideFence(line, state: state)
    }

    let units = line.units
    let indent = leadingIndent(units)
    let incoming = state.markdownBlocks

    // A whitespace-only line is **blank** in Markdown — CommonMark's block separator is
    // "a line containing no characters, or only spaces and tabs" — which is a grammar's
    // decision to make and differs from Fountain's, and is why ``GrammarLine/isEmpty``
    // deliberately does not decide it.
    if indent.units == units.count {
      return scanBlank(line, blocks: incoming)
    }

    // Close every list item this line has outdented past, then measure the line against
    // whatever is left. Every construct below is recognized at its indentation *relative
    // to the enclosing item*, which is the whole of CommonMark's list-container rule that
    // a line grammar can express.
    var blocks = incoming
    blocks.popLists(deeperThan: indent.visualColumns)
    let base = blocks.innermostContentColumn
    let relativeColumns = max(0, indent.visualColumns - base)
    let containerDepth = max(0, blocks.listDepth - 1)

    if relativeColumns >= Self.maxConstructIndentColumns + 1 {
      // An indented code block cannot interrupt a paragraph: under an open paragraph,
      // four columns of indent is continuation text. This is the rule that keeps a
      // hanging-indented sentence from turning into a code block as it is typed.
      return incoming.paragraphOpen
        ? scanParagraph(line, blocks: incoming)
        : scanIndentedCode(line, blocks: blocks, depth: containerDepth)
    }

    // Past this point the line carries at most three relative columns of indent, which is
    // the precondition every construct below shares — so none of them re-checks it.
    if let scan = scanBlockquote(line, indent: indent, blocks: blocks) {
      return scan
    }
    // Setext before thematic break, because a run of dashes is both and CommonMark gives
    // the heading precedence. `***` and `___` are never setext underlines, so they reach
    // the thematic-break case regardless of what is above them.
    if incoming.paragraphOpen,
      let scan = scanSetextUnderline(line, indent: indent, blocks: blocks)
    {
      return scan
    }
    // Thematic break before lists, because `- - -` and `* * *` are both.
    if let scan = scanThematicBreak(line, indent: indent, blocks: blocks) {
      return scan
    }
    if let scan = scanFenceOpening(line, indent: indent, blocks: blocks) {
      return scan
    }
    if let scan = scanHeading(line, indent: indent, blocks: blocks) {
      return scan
    }
    if let scan = scanListItem(
      line, indent: indent, blocks: blocks, paragraphOpen: incoming.paragraphOpen)
    {
      return scan
    }

    // A paragraph line under an open paragraph is a lazy continuation: it stays inside
    // whatever container the paragraph was opened in even when its own indentation would
    // have left it, so the pop above does not apply to it.
    return incoming.paragraphOpen
      ? scanParagraph(line, blocks: incoming)
      : scanParagraph(line, blocks: blocks)
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
  private func scanHeading(
    _ line: GrammarLine, indent: Indent, blocks: MarkdownBlockState
  ) -> LineScan? {
    let units = line.units

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

    // A heading is a leaf block: it closes the paragraph above it, and `depth` carries the
    // heading level rather than the enclosing list depth. Geometry keyed by
    // `(ElementKind, depth)` reads a heading's depth as its level everywhere, so a
    // heading inside a list item is indented by its element, not by its nesting — a known
    // consequence of `depth` being one number.
    return LineScan(
      spans: spans,
      element: .heading,
      contentRange: (base + contentStart)..<(base + contentEnd),
      depth: level,
      endState: LineState(markdownBlocks: closingParagraph(blocks))
    )
  }

  // MARK: - Setext heading underlines

  /// Scans `===` or `---` sitting under an open paragraph, or returns `nil`.
  ///
  /// Only reachable with ``MarkdownBlockState/paragraphOpen`` set, and that is the whole
  /// rule: the same three dashes are a thematic break under a blank line and a level-two
  /// heading underline under a paragraph. CommonMark gives the heading precedence when
  /// both readings are available, which is why this is tried before
  /// ``scanThematicBreak(_:indent:blocks:)`` rather than after.
  ///
  /// `- - -` does **not** reach here: the run breaks at the first space, so the line is
  /// left to the thematic-break case, which is also what CommonMark does with it.
  private func scanSetextUnderline(
    _ line: GrammarLine, indent: Indent, blocks: MarkdownBlockState
  ) -> LineScan? {
    let units = line.units
    let character = units[indent.units]
    guard character == equalsSign || character == hyphen else { return nil }

    var runEnd = indent.units
    while runEnd < units.count, units[runEnd] == character {
      runEnd += 1
    }
    var cursor = runEnd
    while cursor < units.count, isSpaceOrTab(units[cursor]) {
      cursor += 1
    }
    guard cursor == units.count else { return nil }

    let base = line.contentRange.lowerBound
    return LineScan(
      spans: [
        EscriboSpan(
          range: (base + indent.units)..<(base + runEnd), kind: .heading, role: .marker)
      ],
      element: .heading,
      // Pure delimiter: the heading's text is the line above, which a zero-lookahead
      // grammar cannot reclassify. The empty content range says so honestly rather than
      // claiming the dashes are the heading.
      contentRange: (base + runEnd)..<(base + runEnd),
      depth: character == equalsSign ? 1 : 2,
      endState: LineState(markdownBlocks: closingParagraph(blocks))
    )
  }

  // MARK: - Thematic breaks

  /// Scans `---`, `***`, or `___`, or returns `nil` if the line is not one.
  ///
  /// Three or more of **one** character, with nothing but spaces and tabs between them and
  /// nothing else on the line. Tried before lists because `- - -` and `* * *` satisfy both
  /// readings and CommonMark gives the break precedence, and tried after the setext
  /// underline because `---` under a paragraph is a heading.
  private func scanThematicBreak(
    _ line: GrammarLine, indent: Indent, blocks: MarkdownBlockState
  ) -> LineScan? {
    let units = line.units
    let character = units[indent.units]
    guard character == hyphen || character == underscore || character == asterisk else {
      return nil
    }

    var count = 0
    var runEnd = indent.units
    var cursor = indent.units
    while cursor < units.count {
      if units[cursor] == character {
        count += 1
        cursor += 1
        runEnd = cursor
      } else if isSpaceOrTab(units[cursor]) {
        cursor += 1
      } else {
        return nil
      }
    }
    guard count >= 3 else { return nil }

    let base = line.contentRange.lowerBound
    return LineScan(
      spans: [
        EscriboSpan(
          range: (base + indent.units)..<(base + runEnd), kind: .thematicBreak, role: .marker)
      ],
      element: .thematicBreak,
      // Pure delimiter, like a closing fence: no content, so an empty content range where
      // content would have begun.
      contentRange: (base + runEnd)..<(base + runEnd),
      endState: LineState(markdownBlocks: closingParagraph(blocks))
    )
  }

  // MARK: - Blockquotes

  /// Scans `> quoted`, `>> nested`, or `> > nested`, or returns `nil`.
  ///
  /// Each `>` consumes itself plus **one** following space or tab, per CommonMark, and up
  /// to three further columns of whitespace may separate one marker from the next. The
  /// whole marker run is one span so the styler paints one dimmed gutter rather than a
  /// gutter with holes in it.
  ///
  /// ``LineScan/depth`` is the quote nesting minus one — `>` is depth 0, `> >` is depth 1 —
  /// matching lists, which are also zero-based. A blockquote inside a list therefore
  /// reports its quote depth and not its list depth; `depth` is one number and cannot
  /// carry both.
  ///
  /// The paragraph is closed on the way out. A blockquote's content is not re-scanned, so
  /// the grammar does not know whether a paragraph is open *inside* the quote, and
  /// claiming one is open would make the next unquoted `---` a setext underline for a
  /// paragraph that is not there.
  private func scanBlockquote(
    _ line: GrammarLine, indent: Indent, blocks: MarkdownBlockState
  ) -> LineScan? {
    let units = line.units
    guard units[indent.units] == greaterThan else { return nil }

    var cursor = indent.units
    var markers = 0
    while cursor < units.count {
      if units[cursor] == greaterThan {
        markers += 1
        cursor += 1
        // One space after the marker belongs to the marker; the rest is content.
        if cursor < units.count, isSpaceOrTab(units[cursor]) {
          cursor += 1
        }
        continue
      }
      // Up to three columns of whitespace may sit between one `>` and the next.
      var probe = cursor
      var skipped = 0
      while probe < units.count, isSpaceOrTab(units[probe]),
        skipped < Self.maxConstructIndentColumns
      {
        probe += 1
        skipped += 1
      }
      guard probe > cursor, probe < units.count, units[probe] == greaterThan else { break }
      cursor = probe
    }

    let base = line.contentRange.lowerBound
    var spans: [EscriboSpan] = [
      EscriboSpan(
        range: (base + indent.units)..<(base + cursor), kind: .blockquote, role: .marker)
    ]
    if cursor < units.count {
      spans.append(
        EscriboSpan(range: (base + cursor)..<line.contentRange.upperBound, kind: .blockquote))
    }

    return LineScan(
      spans: spans,
      element: .blockquote,
      contentRange: (base + cursor)..<line.contentRange.upperBound,
      depth: markers - 1,
      endState: LineState(markdownBlocks: closingParagraph(blocks))
    )
  }

  // MARK: - Lists

  /// Scans `- item`, `* item`, `+ item`, `1. item`, or `1) item`, or returns `nil`.
  ///
  /// ``LineScan/depth`` is the nesting level, zero-based, and it comes out of
  /// ``MarkdownBlockState/popLists(deeperThan:)`` having already run against this line's
  /// indentation: whatever items are still open are the items this one is nested inside,
  /// so its depth is simply how many there are. Three markers at columns 0, 2, and 4
  /// therefore yield depths 0, 1, and 2 without a special case for either nesting or
  /// un-nesting.
  ///
  /// The item's **content column** — where its text begins, in visual columns — is what
  /// goes on the stack, not its marker column, because that is the column a continuation
  /// line, a nested marker, or an indented code block inside the item is measured against.
  private func scanListItem(
    _ line: GrammarLine, indent: Indent, blocks: MarkdownBlockState, paragraphOpen: Bool
  ) -> LineScan? {
    let units = line.units
    var cursor = indent.units
    let ordered: Bool
    var startNumber = 0

    if isBullet(units[cursor]) {
      ordered = false
      cursor += 1
    } else if isDigit(units[cursor]) {
      var digits = 0
      while cursor < units.count, isDigit(units[cursor]) {
        // CommonMark caps an ordered marker at nine digits. Accumulating past that would
        // overflow for no gain — the number is only read to answer "is it 1?".
        if digits < 9 {
          startNumber = startNumber * 10 + Int(units[cursor] - digitZero)
        }
        digits += 1
        cursor += 1
      }
      guard digits <= 9 else { return nil }
      guard cursor < units.count, units[cursor] == fullStop || units[cursor] == rightParenthesis
      else { return nil }
      cursor += 1
      ordered = true
    } else {
      return nil
    }

    // The marker must be followed by whitespace or end the line: `-word` is a paragraph.
    guard cursor == units.count || isSpaceOrTab(units[cursor]) else { return nil }

    let markerEndColumn = Self.visualColumn(of: units, upTo: cursor)
    var contentUnits = cursor
    while contentUnits < units.count, isSpaceOrTab(units[contentUnits]) {
      contentUnits += 1
    }
    let isBlankItem = contentUnits == units.count

    let contentColumn: Int
    if isBlankItem {
      // An item that begins with a blank line takes exactly one column of marker padding.
      contentColumn = markerEndColumn + 1
      contentUnits = units.count
    } else {
      let afterWhitespace = Self.visualColumn(of: units, upTo: contentUnits)
      if afterWhitespace - markerEndColumn > Self.tabStopColumns {
        // Five or more columns of whitespace: one column belongs to the marker and the
        // rest begins an indented code block *inside* the item.
        contentColumn = markerEndColumn + 1
        contentUnits = cursor + 1
      } else {
        contentColumn = afterWhitespace
      }
    }

    // A list item may interrupt a paragraph only when it has content, and an ordered one
    // only when it starts at 1. Without both rules a wrapped sentence beginning "1968. "
    // turns the line above it into a list.
    if paragraphOpen {
      guard !isBlankItem else { return nil }
      guard !ordered || startNumber == 1 else { return nil }
    }

    var next = blocks
    let depth = next.listDepth
    next.pushList(contentColumn: contentColumn)
    next.paragraphOpen = !isBlankItem

    let base = line.contentRange.lowerBound
    var spans: [EscriboSpan] = [
      EscriboSpan(
        range: (base + indent.units)..<(base + contentUnits), kind: .listItem, role: .marker)
    ]
    if contentUnits < units.count {
      spans.append(
        EscriboSpan(range: (base + contentUnits)..<line.contentRange.upperBound, kind: .listItem))
    }

    return LineScan(
      spans: spans,
      element: ordered ? .orderedListItem : .unorderedListItem,
      contentRange: (base + contentUnits)..<line.contentRange.upperBound,
      depth: depth,
      endState: LineState(markdownBlocks: next)
    )
  }

  // MARK: - Indented code blocks

  /// A line indented four or more visual columns past its container, with no paragraph
  /// open above it.
  ///
  /// The whole line is content, indentation included, for the same reason a fenced code
  /// line's is: indentation is significant inside a code block, so stripping it here would
  /// make the writer lossy. It is classified as ``ElementKind/codeBlock``, the same as a
  /// fenced code line — the two differ in how they are delimited, not in what they are,
  /// and the source text distinguishes them for anyone who cares.
  private func scanIndentedCode(
    _ line: GrammarLine, blocks: MarkdownBlockState, depth: Int
  ) -> LineScan {
    LineScan(
      spans: line.contentRange.isEmpty
        ? [] : [EscriboSpan(range: line.contentRange, kind: .codeBlock)],
      element: .codeBlock,
      contentRange: line.contentRange,
      depth: depth,
      endState: LineState(markdownBlocks: closingParagraph(blocks))
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
  private func scanFenceOpening(
    _ line: GrammarLine, indent: Indent, blocks: MarkdownBlockState
  ) -> LineScan? {
    let units = line.units
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
      depth: max(0, blocks.listDepth - 1),
      endState: LineState(
        openConstruct: Self.fenceTag,
        fenceCharacter: character,
        fenceLength: UInt16(min(runLength, Int(UInt16.max))),
        // The block context is carried **through** the fence. Dropping it here would
        // close every open list item at the fence and reopen nothing at its end, which is
        // a state omission the gate test cannot see.
        markdownBlocks: closingParagraph(blocks)
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
    let blocks = state.markdownBlocks
    let depth = max(0, blocks.listDepth - 1)

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
        depth: depth,
        endState: LineState(markdownBlocks: closingParagraph(blocks))
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
      depth: depth,
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
    let base = state.markdownBlocks.innermostContentColumn
    guard indent.visualColumns - base <= Self.maxConstructIndentColumns else { return nil }
    guard indent.units < units.count else { return nil }
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

  /// A line that is empty apart from spaces, tabs, and its terminator.
  ///
  /// It closes the paragraph above it and leaves the list stack alone: a blank line
  /// separates blocks inside a list item without ending the item, and what ends the item
  /// is the *next* non-blank line outdenting past it.
  private func scanBlank(_ line: GrammarLine, blocks: MarkdownBlockState) -> LineScan {
    LineScan(
      spans: line.contentRange.isEmpty
        ? [] : [EscriboSpan(range: line.contentRange, kind: .text)],
      element: .blank,
      contentRange: line.contentRange.lowerBound..<line.contentRange.lowerBound,
      endState: LineState(markdownBlocks: closingParagraph(blocks))
    )
  }

  /// Anything this grammar does not recognize: a line of ordinary prose.
  ///
  /// - Parameter blocks: The container context this line belongs to. The caller passes the
  ///   **unpopped** stack for a lazy continuation — a line that continues a paragraph
  ///   opened above it stays inside the container that paragraph was opened in, even when
  ///   its own indentation would have left it — and the popped stack otherwise. Which of
  ///   the two applies is a decision about the line, so it is made where the line is
  ///   classified rather than here.
  private func scanParagraph(
    _ line: GrammarLine, blocks: MarkdownBlockState
  ) -> LineScan {
    var next = blocks
    next.paragraphOpen = true
    return LineScan(
      spans: line.contentRange.isEmpty
        ? [] : [EscriboSpan(range: line.contentRange, kind: .text)],
      element: .paragraph,
      contentRange: nil,
      depth: max(0, blocks.listDepth - 1),
      endState: LineState(markdownBlocks: next)
    )
  }

  /// `blocks` with its paragraph closed — the state after any leaf block that is not a
  /// paragraph.
  private func closingParagraph(_ blocks: MarkdownBlockState) -> MarkdownBlockState {
    var closed = blocks
    closed.paragraphOpen = false
    return closed
  }

  // MARK: - Shared line arithmetic

  /// A line's leading whitespace, in code units **and** in visual columns.
  struct Indent {
    /// How many **UTF-16 code units** of the line are leading whitespace. Where the
    /// syntax starts.
    let units: Int

    /// How many **visual columns** that whitespace occupies. What CommonMark's
    /// "up to three spaces of indentation" and "four spaces is code" are stated in, and
    /// not the same number as ``units`` whenever a tab is involved.
    let visualColumns: Int
  }

  /// The leading whitespace of `units`.
  private func leadingIndent(_ units: [UInt16]) -> Indent {
    var offset = 0
    while offset < units.count, isSpaceOrTab(units[offset]) {
      offset += 1
    }
    return Indent(units: offset, visualColumns: Self.visualColumn(of: units, upTo: offset))
  }

  /// The **visual column** at which `units[offset]` sits — that is, how many columns
  /// `units[0..<offset]` occupies.
  ///
  /// The one place in this grammar where columns are computed, and the reason every other
  /// method can talk about columns without restating the rules:
  ///
  /// - **One column per UTF-16 code unit.** Not per `Character`. An astral-plane
  ///   character — an emoji, a Deseret capital — is a surrogate pair and therefore *two*
  ///   columns. Counting characters instead is correct on every ASCII document, which is
  ///   exactly why it survives testing and fails on real input (REQUIREMENTS.md §
  ///   Unicode).
  /// - **A tab advances to the next multiple of ``tabStopColumns``**, which is four. Not
  ///   four columns from wherever it sits, and emphatically not one: a tab at column 0
  ///   lands at column 4, and a tab at column 2 also lands at column 4.
  ///
  /// Linear in `offset`, with no allocation — the whole of REQUIREMENTS.md § Degenerate
  /// input's "nothing worse than linear in line length" for this function.
  ///
  /// - Parameter offset: A code-unit offset into `units`. Clamped, so an out-of-range
  ///   offset measures the whole array rather than trapping.
  static func visualColumn(of units: [UInt16], upTo offset: Int) -> Int {
    let end = min(max(offset, 0), units.count)
    var columns = 0
    var cursor = 0
    while cursor < end {
      if units[cursor] == tab {
        columns += tabStopColumns - (columns % tabStopColumns)
      } else {
        columns += 1
      }
      cursor += 1
    }
    return columns
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
