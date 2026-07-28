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

/// `|`.
private let verticalBar: UInt16 = 0x7C

/// `:`.
private let colon: UInt16 = 0x3A

/// `[`.
private let leftBracket: UInt16 = 0x5B

/// `]`.
private let rightBracket: UInt16 = 0x5D

/// `\`.
private let backslash: UInt16 = 0x5C

/// `x`.
private let lowercaseX: UInt16 = 0x78

/// `fountain`, lowercased, as the info string that dispatches a fence to the Fountain
/// grammar.
///
/// Built through `String.UTF16View`, which is standard library — `EscriboCore` imports
/// nothing, and nothing here needs it to. Compared against a case-folded copy of the info
/// string's first word, so ```` ```Fountain ```` and ```` ```FOUNTAIN ```` dispatch too.
private let fountainInfoWord: [UInt16] = Array("fountain".utf16)

/// `X`.
private let uppercaseX: UInt16 = 0x58

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
/// blockquotes, thematic breaks, and setext heading underlines in Sortie 18. Everything
/// this grammar does not recognize degrades to ``ElementKind/paragraph`` and a
/// ``SpanKind/text`` span, which is what "malformed constructs degrade to text" means in
/// practice — the absence of a case, not a case.
///
/// ## Inline structure lives in ``MarkdownInline``
///
/// Sortie 19 added emphasis, code spans, links, images, and hard breaks, and it added them
/// in their own file rather than here. The split is along a real seam: this file decides
/// **which block a line is and where its content begins**, and that decision needs the
/// state arriving from above; ``MarkdownInline`` paints **inside one content range** and
/// needs no state at all. Four methods below hand it a range — ``scanHeading(_:indent:blocks:)``,
/// ``scanListItem(_:indent:blocks:paragraphOpen:)``, ``scanBlockquote(_:indent:blocks:)``,
/// and ``scanParagraph(_:blocks:)`` — and the code paths that must *not* be inline-scanned
/// are exactly the ones that do not: fenced and indented code, closing fences, setext
/// underlines, thematic breaks, and blank lines.
///
/// The block kind is passed in and inherited by every inline span that is not a link,
/// image, or hard break, which is what keeps `# **Bold** heading` one heading rather than
/// a heading with a hole in it.
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
/// **Declared one; consumed by no Markdown construct.** DL-139 — until Sortie 21 this
/// section said "Zero", and the number stopped being true when ``lookahead`` was raised to
/// `1` so that a nested `fountain` fence could hand its guest grammar a window with a line
/// in it (see the property's own documentation for why the *host* grammar's declaration is
/// what sizes that window). The behaviour the old prose described did not change, only its
/// stated cause, and the corrected statement is the narrower one:
///
/// Every Markdown decision in this file is still made from the line's own text plus the
/// state it begins in. Nothing here calls `line(ahead:)`. That includes the setext
/// underline and the table delimiter row, both of which read
/// ``MarkdownBlockState/paragraphOpen`` arriving from above rather than looking at the line
/// below.
///
/// **Known gap, deliberate (DL-88):** because no rule here reads the line below, a setext
/// underline classifies *itself* as ``ElementKind/heading`` and does **not** retro-classify
/// the paragraph line above it. Closing it needs the matching *backward* extent as well —
/// the machinery Fountain's character cue has — and raising `lookahead` alone did not
/// supply it. A consumer that wants the heading *text* for a setext heading must read the
/// line above a `heading` record whose content range is empty.
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
///
/// ## GFM and YAML frontmatter, added in Sortie 20
///
/// Tables, task-list checkboxes, and YAML frontmatter are block structure and live here;
/// strikethrough and autolinks are inline and live in ``MarkdownInline``. Three decisions
/// in this half are worth stating where a later sortie will find them.
///
/// **Frontmatter is decided by line *position*, not by state.** A region opens only when
/// ``GrammarLine/index`` is zero, because the state entering line 0 —
/// ``LineState/documentStart`` — is a state many later lines legitimately begin in too, so
/// state alone cannot say "this is the top of the document". Reading the index is sound
/// for the incremental engine for one reason, and it is worth writing down: line 0 begins
/// at offset 0, so **any** edit that could change which line is line 0 must touch offset 0,
/// and an edit touching offset 0 always rescans from line 0. There is no edit that renumbers
/// line 0 without rescanning it.
///
/// **A table's header row is not classified as one.** GFM recognizes a header only by the
/// delimiter row beneath it, which would mean reading the line below plus retro-classifying
/// the line above — neither of which any rule in this file does, whatever ``lookahead``
/// happens to be declared as. The same gap the setext underline has, waiting on the same
/// later sortie. The
/// delimiter row is recognized instead, from its own text plus
/// ``MarkdownBlockState/paragraphOpen`` arriving from above, and the header stays a
/// ``ElementKind/paragraph``. For the same reason the delimiter row's **cell count is never
/// checked against the header's**, which GFM requires; a delimiter row under any paragraph
/// opens a table.
///
/// **A table ends at a blank line or at a line with no `|` in it.** GFM ends it at a blank
/// line or at the start of another block-level construct, which would mean re-running the
/// whole construct chain speculatively for every row. Requiring a pipe gets every real
/// document right — headings, fences, quotes, and lists have no pipe — and gets `# a | b`
/// directly after a table wrong, which is the trade.
struct MarkdownGrammar: LineGrammar {

  /// The ``LineState/openConstruct`` tag meaning "a fenced code block is open".
  ///
  /// Its meaning belongs to this grammar; the scanner only ever compares it.
  static let fenceTag: UInt16 = 1

  /// The ``LineState/openConstruct`` tag meaning "a YAML frontmatter region is open".
  ///
  /// A tag rather than a new field on ``LineState`` because the three multi-line
  /// constructs this grammar has — a fence, a frontmatter region, a table — are mutually
  /// exclusive: a document inside one is inside no other. One scalar therefore says which,
  /// and convergence across a frontmatter region falls out of the same comparison that
  /// makes convergence across a fence work.
  static let frontmatterTag: UInt16 = 2

  /// The ``LineState/openConstruct`` tag meaning "a GFM table's body is open".
  static let tableTag: UInt16 = 3

  /// The ``LineState/openConstruct`` tag meaning "a fenced code block tagged `fountain` is
  /// open".
  ///
  /// A tag of its own rather than ``fenceTag`` plus a flag, because it answers a question
  /// asked before anything else on the line is looked at: *which grammar scans this line?*
  /// Folding it into `fenceTag` would mean every line inside every fence in every document
  /// re-derived the answer from an info string that is no longer on the line.
  ///
  /// **It is not where the nested Fountain state lives.** That is
  /// ``LineState/nestedFountain``, and the separation is the whole of DL-112: this tag says
  /// the *outer* construct is open, and the nested state says which *inner* construct is —
  /// a boneyard inside a fence is both at once, and one scalar cannot say so.
  static let fountainFenceTag: UInt16 = 4

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

  /// One, and only because of the nested `fountain` fence.
  ///
  /// **No construct in this file reads the line below it.** Every Markdown decision here is
  /// still made from the line's own text plus the state arriving from above — the setext
  /// underline and the table delimiter row both key off
  /// ``MarkdownBlockState/paragraphOpen`` rather than looking ahead, and the known gaps that
  /// causes are documented on the type. What needs the line below is the *guest*:
  /// ``FountainGrammar`` declares a lookahead of one for its character-cue rule, and the
  /// engine sizes the ``LineWindow`` from the **host** grammar's declaration. Declaring zero
  /// here would hand the nested scan a window with nothing in it, `line(ahead:)` would
  /// answer `nil` for every line of every fenced screenplay, and no natural cue would ever
  /// be recognized inside one — a wrong answer produced by a number a hundred lines away
  /// from the rule it broke.
  ///
  /// Raising it is safe for everything else and not free: ``LineGrammar/backwardExtent``
  /// defaults to `max(1, lookahead)`, which was already one, so no edit rescans further
  /// back; the rescan window extends one line further forward past convergence, which is
  /// conservative padding and cannot change a painted line.
  var lookahead: Int { 1 }

  func scanLine(_ window: LineWindow, state: LineState) -> LineScan {
    let line = window.current

    // A `fountain` fence, before the ordinary fence check, because the two tags are
    // mutually exclusive and this one answers a different question: not "is this line
    // code?" but "which grammar reads this line?". Everything inside is a screenplay
    // until the fence closes — or, if it never closes, until the end of the document.
    if state.openConstruct == Self.fountainFenceTag {
      return scanInsideFountainFence(window, state: state)
    }

    // Inside a fence, nothing else is syntax. A `#` is a hash and a `~~~` is three
    // tildes unless the open fence was opened with tildes and is no longer than this
    // run — which is exactly why the character and the length are carried in the state.
    if state.openConstruct == Self.fenceTag {
      return scanInsideFence(line, state: state)
    }

    // Inside frontmatter, nothing else is syntax either — a `#` is a YAML comment and a
    // `- ` is a YAML sequence entry, not a heading and not a list. Two outcomes and no
    // third, exactly as inside a fence: the line closes the region, or it is an entry. That
    // is what makes an **unterminated** region scan to the end of the document and return
    // normally rather than needing an error path that does not exist.
    if state.openConstruct == Self.frontmatterTag {
      return scanInsideFrontmatter(line)
    }

    let units = line.units
    let indent = leadingIndent(units)
    let incoming = state.markdownBlocks

    // A table body row, before the blank check would classify nothing and before the
    // construct chain would reclassify it. A blank line falls through and closes the table;
    // so does a line with no `|`, which is then scanned as whatever it actually is.
    if state.openConstruct == Self.tableTag, indent.units != units.count,
      containsUnescapedPipe(units)
    {
      return scanTableRow(line, blocks: incoming)
    }

    // A whitespace-only line is **blank** in Markdown — CommonMark's block separator is
    // "a line containing no characters, or only spaces and tabs" — which is a grammar's
    // decision to make and differs from Fountain's, and is why ``GrammarLine/isEmpty``
    // deliberately does not decide it.
    if indent.units == units.count {
      return scanBlank(line, blocks: incoming)
    }

    // Frontmatter, and **only** on the document's first line. This is the one construct in
    // this grammar decided by where the line is rather than by what it says, and it is the
    // reason `---` on line 1 and `---` on line 5 are different elements. See the type's
    // documentation for why reading the line index does not break incremental convergence.
    if line.index == 0, let scan = scanFrontmatterOpening(line) {
      return scan
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
    // A table delimiter row before the thematic break, because `---|---` reaches neither
    // the setext case nor the break case — both stop at the first `|` — but reads as one of
    // them to anyone skimming the chain. Placed here so the ordering is written down.
    if incoming.paragraphOpen,
      let scan = scanTableDelimiterRow(line, indent: indent, blocks: blocks)
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
    // The heading's text is inline-scanned, so `# **Bold** heading` is a heading whose
    // first word is also strong. `allowsHardBreak` is false because CommonMark has no hard
    // break inside an ATX heading, and emitting one would paint the trailing spaces a
    // closing-sequence scan has already accounted for.
    spans.append(
      contentsOf: MarkdownInline.spans(
        in: units, range: contentStart..<contentEnd, base: base, kind: .heading,
        allowsHardBreak: false))
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
      // Pure delimiter: the heading's text is the line above, which a grammar with no
      // backward extent cannot reclassify. The empty content range says so honestly rather than
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
    spans.append(
      contentsOf: MarkdownInline.spans(
        in: units, range: cursor..<units.count, base: base, kind: .blockquote,
        allowsHardBreak: true))

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

    // A GFM task-list checkbox, if the item opens with one. It does **not** move the
    // content column pushed above: GFM measures an item's content from just past its list
    // marker, and a checkbox is content that happens to be syntax. Moving it would make a
    // continuation line under `- [ ] a` need four more columns of indent than one under
    // `- a`, which no writer expects and no renderer does.
    let checkbox = taskListCheckbox(units, from: contentUnits)
    let textUnits = checkbox?.end ?? contentUnits

    let base = line.contentRange.lowerBound
    var spans: [EscriboSpan] = [
      EscriboSpan(
        range: (base + indent.units)..<(base + contentUnits), kind: .listItem, role: .marker)
    ]
    if let checkbox {
      spans.append(
        EscriboSpan(
          range: (base + contentUnits)..<(base + checkbox.end),
          kind: checkbox.checked ? .taskListChecked : .taskListUnchecked,
          role: .marker))
    }
    spans.append(
      contentsOf: MarkdownInline.spans(
        in: units, range: textUnits..<units.count, base: base, kind: .listItem,
        allowsHardBreak: true))

    return LineScan(
      spans: spans,
      element: ordered ? .orderedListItem : .unorderedListItem,
      contentRange: (base + textUnits)..<line.contentRange.upperBound,
      depth: depth,
      endState: LineState(markdownBlocks: next)
    )
  }

  /// A GFM task-list checkbox at `start`, plus the whitespace after it — or `nil`.
  ///
  /// `[ ]`, `[x]`, or `[X]`, and it must be followed by whitespace or end the line, so
  /// `- [x]y` is an ordinary item whose text begins with a bracket. The returned `end` is
  /// past the trailing whitespace, so the item's text begins at the first character a
  /// reader sees — the same rule the ATX heading marker follows.
  ///
  /// The two states are distinguished by ``SpanKind``, not by ``StyleSet`` and not by
  /// ``SpanRole``: a theme draws an empty box or a tick, which is a difference in what the
  /// run *is*, and the style axis is a set of emphasis flags with nowhere to say it.
  private func taskListCheckbox(_ units: [UInt16], from start: Int)
    -> (end: Int, checked: Bool)?
  {
    guard start + 2 < units.count else { return nil }
    guard units[start] == leftBracket, units[start + 2] == rightBracket else { return nil }

    let mark = units[start + 1]
    let checked: Bool
    if mark == lowercaseX || mark == uppercaseX {
      checked = true
    } else if isSpaceOrTab(mark) {
      checked = false
    } else {
      return nil
    }

    var end = start + 3
    guard end == units.count || isSpaceOrTab(units[end]) else { return nil }
    while end < units.count, isSpaceOrTab(units[end]) {
      end += 1
    }
    return (end, checked)
  }

  // MARK: - YAML frontmatter

  /// Scans the `---` that opens a document's YAML frontmatter region, or returns `nil`.
  ///
  /// Only ever called with ``GrammarLine/index`` zero. Everything about this construct is
  /// that restriction: `---` is a ``ElementKind/thematicBreak`` on every other line of
  /// every document, and turning the same three characters into a region delimiter one line
  /// higher is the whole of what this method adds. `---` on line five stays a thematic
  /// break because this method is never reached there, not because it declines the line.
  ///
  /// **Exactly three hyphens**, no leading whitespace, nothing but whitespace after them.
  /// Three and not "three or more", so that `----` on line one is still a thematic break:
  /// Jekyll, Hugo, and every other tool that reads this region spell the fence `---`, and
  /// widening the rule would silently swallow the top of a document that opens with a rule.
  private func scanFrontmatterOpening(_ line: GrammarLine) -> LineScan? {
    guard let runEnd = frontmatterDelimiterEnd(line.units) else { return nil }
    return frontmatterDelimiterScan(line, runEnd: runEnd, opening: true)
  }

  /// Scans a line that begins **inside** an open frontmatter region.
  ///
  /// Two outcomes and no third, exactly as inside a fence: the line closes the region, or
  /// it is an entry. There is no failure case, which is what makes an unterminated region
  /// scan to the end of the document and return normally — the state simply stays open, and
  /// the last line of the document is the last line of the region.
  ///
  /// **What "unterminated frontmatter degrades to `.text`" means here, stated exactly.**
  /// No rule in this grammar reads the line below, so at the opening `---` it cannot know
  /// whether a closing one exists; retro-classifying the opener is not available to it and
  /// will not be until the sortie that owns the backward extent. What it can do, and does, is refuse
  /// to invent structure: a line inside the region that is not `key:`-shaped comes back as a
  /// single ``SpanKind/text`` span. A region that was never YAML — the unterminated case in
  /// practice — is therefore `.text` from its second line to the end of the document, which
  /// is the outcome the requirement asks for by the route a line grammar can actually take.
  private func scanInsideFrontmatter(_ line: GrammarLine) -> LineScan {
    if let runEnd = frontmatterDelimiterEnd(line.units) {
      return frontmatterDelimiterScan(line, runEnd: runEnd, opening: false)
    }
    return scanFrontmatterEntry(line)
  }

  /// The shared shape of an opening and a closing frontmatter fence: one marker span, an
  /// empty content range, and the state the region is or is not open in.
  private func frontmatterDelimiterScan(
    _ line: GrammarLine, runEnd: Int, opening: Bool
  ) -> LineScan {
    let base = line.contentRange.lowerBound
    return LineScan(
      spans: [
        EscriboSpan(range: base..<(base + runEnd), kind: .frontmatterDelimiter, role: .marker)
      ],
      element: .frontmatterDelimiter,
      // Pure delimiter, like a closing code fence: no content, so an empty range where
      // content would have begun.
      contentRange: (base + runEnd)..<(base + runEnd),
      endState: opening ? LineState(openConstruct: Self.frontmatterTag) : LineState()
    )
  }

  /// The end offset of a frontmatter fence run, or `nil` if this line is not one.
  ///
  /// No leading whitespace — a fence sits flush left — exactly three hyphens, and nothing
  /// but spaces and tabs after them.
  private func frontmatterDelimiterEnd(_ units: [UInt16]) -> Int? {
    var runEnd = 0
    while runEnd < units.count, units[runEnd] == hyphen {
      runEnd += 1
    }
    guard runEnd == 3 else { return nil }
    var cursor = runEnd
    while cursor < units.count, isSpaceOrTab(units[cursor]) {
      cursor += 1
    }
    guard cursor == units.count else { return nil }
    return runEnd
  }

  /// Scans one line inside a frontmatter region into key and value **spans**.
  ///
  /// Spans, never values. `EscriboCore` imports nothing at all, so there is no YAML parser
  /// here and deliberately no date, number, or boolean anywhere in this package's output:
  /// the scanner says where the value is and the source says what it is. A consumer that
  /// wants `type: docs` as a dictionary reads the ranges and does its own parsing, with its
  /// own dependencies, outside this package.
  ///
  /// The key is everything from the first non-whitespace character to the first `:` that is
  /// followed by whitespace or ends the line — YAML's own rule, and the reason
  /// `url: https://example.com` does not split at the scheme's colon. A leading `- ` is
  /// consumed as part of the leading marker so a sequence of mappings still finds its keys.
  private func scanFrontmatterEntry(_ line: GrammarLine) -> LineScan {
    let units = line.units
    let base = line.contentRange.lowerBound
    let openState = LineState(openConstruct: Self.frontmatterTag)

    var keyStart = 0
    while keyStart < units.count, isSpaceOrTab(units[keyStart]) {
      keyStart += 1
    }
    // A YAML sequence entry — `- name: bob`. The dash and its space are marker, and the
    // key search resumes after them.
    if keyStart < units.count, units[keyStart] == hyphen,
      keyStart + 1 < units.count, isSpaceOrTab(units[keyStart + 1])
    {
      keyStart += 2
      while keyStart < units.count, isSpaceOrTab(units[keyStart]) {
        keyStart += 1
      }
    }

    // A `#` comment and a blank line are not entries, and neither is a line with no key.
    // All three take the degrade path below rather than pretending to a structure they do
    // not have.
    if keyStart < units.count, units[keyStart] != numberSign,
      let colonOffset = frontmatterKeySeparator(units, from: keyStart), colonOffset > keyStart
    {
      var valueStart = colonOffset + 1
      while valueStart < units.count, isSpaceOrTab(units[valueStart]) {
        valueStart += 1
      }
      var spans: [EscriboSpan] = [
        EscriboSpan(
          range: (base + keyStart)..<(base + colonOffset), kind: .frontmatterKey),
        // The `:` and the whitespace after it, as a marker carrying the key's own kind —
        // the rule every marker in this package obeys.
        EscriboSpan(
          range: (base + colonOffset)..<(base + valueStart), kind: .frontmatterKey,
          role: .marker),
      ]
      if valueStart < units.count {
        spans.append(
          EscriboSpan(
            range: (base + valueStart)..<line.contentRange.upperBound, kind: .frontmatterValue))
      }
      return LineScan(
        spans: spans,
        element: .frontmatter,
        contentRange: (base + valueStart)..<line.contentRange.upperBound,
        endState: openState
      )
    }

    // Degrade: one `.text` span over whatever is there, and the region stays open.
    return LineScan(
      spans: line.contentRange.isEmpty
        ? [] : [EscriboSpan(range: line.contentRange, kind: .text)],
      element: .frontmatter,
      contentRange: line.contentRange,
      endState: openState
    )
  }

  /// The offset of the `:` separating a frontmatter key from its value, or `nil`.
  ///
  /// YAML's rule: the colon must be followed by whitespace or end the line. Without it
  /// `url: https://example.com` would split at `https:` and the key would be `url: https`.
  private func frontmatterKeySeparator(_ units: [UInt16], from start: Int) -> Int? {
    var cursor = start
    while cursor < units.count {
      if units[cursor] == colon, cursor + 1 == units.count || isSpaceOrTab(units[cursor + 1]) {
        return cursor
      }
      cursor += 1
    }
    return nil
  }

  // MARK: - GFM tables

  /// Scans `|:---|---:|` — a table's delimiter row — or returns `nil`.
  ///
  /// Only reachable with ``MarkdownBlockState/paragraphOpen`` set, because in GFM a
  /// delimiter row is only a delimiter row under a header, and a header is a paragraph line
  /// as far as this grammar is concerned. Two consequences of reading no line but this one, both
  /// deliberate and both stated in the type's documentation: the header line above stays a
  /// ``ElementKind/paragraph``, and the delimiter row's cell count is never checked against
  /// the header's.
  ///
  /// **At least one `|` is required**, which is what keeps this method from competing with
  /// the setext underline and the thematic break: `---` under a paragraph reaches neither
  /// this method's success path nor its ambiguity, because it has no pipe at all.
  ///
  /// The alignments go on the **line record** rather than into a span, because alignment is
  /// per *column* and a span has no column axis — see ``LineRecord/tableAlignments``.
  private func scanTableDelimiterRow(
    _ line: GrammarLine, indent: Indent, blocks: MarkdownBlockState
  ) -> LineScan? {
    let units = line.units
    var cursor = indent.units
    var sawPipe = false
    var alignments: [TableAlignment] = []

    if units[cursor] == verticalBar {
      sawPipe = true
      cursor += 1
    }
    while cursor < units.count {
      while cursor < units.count, isSpaceOrTab(units[cursor]) {
        cursor += 1
      }
      // Trailing whitespace after the last `|`. The row is complete.
      if cursor == units.count { break }

      let leftColon = units[cursor] == colon
      if leftColon { cursor += 1 }
      var dashes = 0
      while cursor < units.count, units[cursor] == hyphen {
        dashes += 1
        cursor += 1
      }
      guard dashes >= 1 else { return nil }
      let rightColon = cursor < units.count && units[cursor] == colon
      if rightColon { cursor += 1 }
      while cursor < units.count, isSpaceOrTab(units[cursor]) {
        cursor += 1
      }

      alignments.append(Self.alignment(left: leftColon, right: rightColon))
      if cursor == units.count { break }
      guard units[cursor] == verticalBar else { return nil }
      sawPipe = true
      cursor += 1
    }
    guard sawPipe, !alignments.isEmpty else { return nil }

    let base = line.contentRange.lowerBound
    return LineScan(
      spans: [
        EscriboSpan(
          range: (base + indent.units)..<line.contentRange.upperBound, kind: .tableDelimiter,
          role: .marker)
      ],
      element: .tableDelimiterRow,
      // Pure delimiter, like a thematic break: the row prints as a rule and has no content.
      contentRange: line.contentRange.upperBound..<line.contentRange.upperBound,
      depth: max(0, blocks.listDepth - 1),
      endState: LineState(
        openConstruct: Self.tableTag,
        // The block context is carried **through** the table for the reason it is carried
        // through a fence: dropping it would close every open list item at the table and
        // reopen nothing after it, which is a state omission the gate test cannot see.
        markdownBlocks: closingParagraph(blocks)
      ),
      tableAlignments: alignments
    )
  }

  /// Which alignment a delimiter cell's colons declare.
  private static func alignment(left: Bool, right: Bool) -> TableAlignment {
    switch (left, right) {
    case (true, true): return .center
    case (true, false): return .left
    case (false, true): return .right
    case (false, false): return .unspecified
    }
  }

  /// Scans a table body row: cell text as content, each separating `|` as a marker.
  ///
  /// Cells are inline-scanned, so `| **bold** | [link](x) |` is a row whose first cell is
  /// strong and whose second is a link. `allowsHardBreak` is false: a trailing double space
  /// inside a table is not a line break in GFM, and emitting one would paint the row's last
  /// cell short of its own end.
  ///
  /// A `\|` is a literal pipe and does **not** end a cell, which is the one escape GFM
  /// gives tables and the only way to put a pipe in a cell at all.
  ///
  /// The record carries **no** alignments; a consumer aligning a cell reads them off the
  /// delimiter row above. See ``LineRecord/tableAlignments`` for the allocation argument
  /// behind that.
  private func scanTableRow(_ line: GrammarLine, blocks: MarkdownBlockState) -> LineScan {
    let units = line.units
    let base = line.contentRange.lowerBound
    var spans: [EscriboSpan] = []
    var cellStart = 0
    var cursor = 0

    func appendCell(_ end: Int) {
      guard end > cellStart else { return }
      spans.append(
        contentsOf: MarkdownInline.spans(
          in: units, range: cellStart..<end, base: base, kind: .tableCell,
          allowsHardBreak: false))
    }

    while cursor < units.count {
      if units[cursor] == backslash, cursor + 1 < units.count {
        cursor += 2
        continue
      }
      if units[cursor] == verticalBar {
        appendCell(cursor)
        spans.append(
          EscriboSpan(
            range: (base + cursor)..<(base + cursor + 1), kind: .tableCell, role: .marker))
        cursor += 1
        cellStart = cursor
        continue
      }
      cursor += 1
    }
    appendCell(units.count)

    return LineScan(
      spans: spans,
      element: .tableRow,
      contentRange: line.contentRange,
      depth: max(0, blocks.listDepth - 1),
      endState: LineState(
        openConstruct: Self.tableTag, markdownBlocks: closingParagraph(blocks))
    )
  }

  /// Whether `units` holds a `|` that is not backslash-escaped.
  ///
  /// The one question that decides whether an open table continues across this line. Linear
  /// and allocation-free, like everything else on this path.
  private func containsUnescapedPipe(_ units: [UInt16]) -> Bool {
    var cursor = 0
    while cursor < units.count {
      if units[cursor] == backslash {
        cursor += 2
        continue
      }
      if units[cursor] == verticalBar { return true }
      cursor += 1
    }
    return false
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
      // The info string's text is what dispatches a `fountain` fence to the Fountain
      // scanner, which is why it is its own kind rather than part of the marker.
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
        // The info string is read **once**, here, and its answer is carried as a tag. Every
        // line inside the block then knows which grammar reads it without re-deriving it
        // from a line that is no longer in the window.
        openConstruct: namesFountain(units, info) ? Self.fountainFenceTag : Self.fenceTag,
        fenceCharacter: character,
        fenceLength: UInt16(min(runLength, Int(UInt16.max))),
        // The block context is carried **through** the fence. Dropping it here would
        // close every open list item at the fence and reopen nothing at its end, which is
        // a state omission the gate test cannot see.
        markdownBlocks: closingParagraph(blocks)
        // `nestedFountain` stays at its default, and that default is the point: its
        // `titlePage` is `.documentStart`, so the fence's first content line is the one
        // line a nested title page may open on — the same rule a standalone screenplay
        // gets from line zero, reached by the same route rather than by a special case.
      )
    )
  }

  /// Whether a fence's info string names Fountain: its **first word**, compared
  /// ASCII-case-insensitively against `fountain`.
  ///
  /// The first word only, because CommonMark's info string is "a language, then whatever
  /// the renderer wants" — ```` ```fountain title=scene ```` is a Fountain block. ASCII case
  /// folding only, because a case-folding table would be a Unicode dependency this module
  /// does not have and every spelling anyone writes this in is ASCII. No regex, per the
  /// charter: this is a length check and a loop of code-unit comparisons.
  private func namesFountain(_ units: [UInt16], _ info: Range<Int>) -> Bool {
    var end = info.lowerBound
    while end < info.upperBound, !isSpaceOrTab(units[end]) {
      end += 1
    }
    guard end - info.lowerBound == fountainInfoWord.count else { return false }
    for offset in 0..<fountainInfoWord.count {
      var unit = units[info.lowerBound + offset]
      // `A`...`Z` folded to lowercase. Nothing else is touched.
      if unit >= 0x41, unit <= 0x5A { unit += 0x20 }
      if unit != fountainInfoWord[offset] { return false }
    }
    return true
  }

  // MARK: - The nested Fountain scan

  /// Scans a line that begins inside an open ```` ```fountain ```` fence.
  ///
  /// Three properties hold here and each is a task this sortie was given.
  ///
  /// **The inner scan is offset, not separate.** ``FountainGrammar`` is handed the same
  /// ``GrammarLine`` this grammar was handed — the same `units` array, the same
  /// `contentRange`, whose `lowerBound` is an offset into the **outer** document — and it
  /// lays every span out against `line.contentRange.lowerBound` exactly as it does in a
  /// standalone screenplay. So outer-document coordinates are not translated back from
  /// inner ones; they are the only coordinates that ever existed. Nothing is substringed,
  /// nothing is re-based, and the per-keystroke allocation a substring would cost is not
  /// paid because there is no substring.
  ///
  /// **The inner state is part of the outer state.** It rides in
  /// ``LineState/nestedFountain`` — a second field, never a second meaning for
  /// ``LineState/openConstruct`` — so a boneyard open *inside* a fence is two facts held at
  /// once. A state that recorded only "we are in a fence" would be identical on every line
  /// of the block, the incremental scanner would converge on the block's second line, and
  /// an edit inside a fenced screenplay would repaint one line of it (DL-112).
  ///
  /// **One level, no recursion.** Fountain hosts nothing — it has no fence syntax — so this
  /// method is never reached from inside itself, and the nested state can be a fixed-size
  /// value rather than a boxed `LineState`.
  ///
  /// The closing fence is checked **first** and belongs to Markdown, not to the guest: it is
  /// the host's delimiter, and handing it to the Fountain grammar would classify ```` ``` ````
  /// as action and leave the fence open forever.
  private func scanInsideFountainFence(_ window: LineWindow, state: LineState) -> LineScan {
    let line = window.current
    let units = line.units
    let base = line.contentRange.lowerBound
    let blocks = state.markdownBlocks

    if let runEnd = closingFenceEnd(units, state: state) {
      return LineScan(
        spans: [
          EscriboSpan(
            range: (base + leadingIndent(units).units)..<(base + runEnd), kind: .codeBlock,
            role: .marker)
        ],
        element: .codeFence,
        contentRange: (base + runEnd)..<(base + runEnd),
        depth: max(0, blocks.listDepth - 1),
        // The fence is closed: the nested state goes with it, back to its default, where it
        // compares equal to itself for the rest of the document.
        endState: LineState(markdownBlocks: closingParagraph(blocks))
      )
    }

    let scan = FountainGrammar().scanLine(
      LineWindow(nestedWindow(window, state: state)), state: .nested(state.nestedFountain))

    return LineScan(
      spans: scan.spans,
      element: scan.element,
      contentRange: scan.contentRange,
      depth: scan.depth,
      endState: LineState(
        openConstruct: Self.fountainFenceTag,
        // The fence's own character and length still have to be carried, or the *next*
        // line could not tell a closing fence from a line of action that starts with
        // backticks.
        fenceCharacter: state.fenceCharacter,
        fenceLength: state.fenceLength,
        markdownBlocks: blocks,
        // The whole Fountain half, not the region tag alone. See ``NestedFountainState``.
        nestedFountain: scan.endState.fountainHalf
      )
    )
  }

  /// The window the nested scan sees: this line, plus the next one **only when the next
  /// line is still inside the fence**.
  ///
  /// The host's closing fence is not part of the guest's document, and hiding it is what
  /// makes a fenced screenplay scan identically to the same text scanned standalone. The
  /// case it decides is Fountain's cue rule: an ALL-CAPS line is a character cue only when a
  /// non-blank line follows it, so with the closing ```` ``` ```` visible, the last line of
  /// every fenced block would be a cue for a speaker who never speaks. `line(ahead:)`
  /// answers `nil` both for "past the end of the document" and for "past the declared
  /// lookahead", and the guest is entitled to no finer distinction — so "the fence ends
  /// here" is delivered as the same `nil` that the end of a document is.
  ///
  /// Reading the next line's text is within this grammar's declared ``lookahead`` of one, so
  /// the convergence engine already rescans one line past the point where state converges.
  private func nestedWindow(_ window: LineWindow, state: LineState) -> [GrammarLine] {
    guard let ahead = window.line(ahead: 1) else { return [window.current] }
    guard closingFenceEnd(ahead.units, state: state) == nil else { return [window.current] }
    return [window.current, ahead]
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
      spans: MarkdownInline.spans(
        in: line.units, range: 0..<line.units.count, base: line.contentRange.lowerBound,
        kind: .text, allowsHardBreak: true),
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
