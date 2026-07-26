/// What a *line* is — the semantic classification carried by a line record.
///
/// Where ``SpanKind`` drives character attributes, `ElementKind` drives paragraph
/// geometry: the editor looks up indents and spacing by `(ElementKind, depth)`. The
/// two outputs travel different application paths, which is why they are different
/// vocabularies rather than one shared enum.
///
/// A struct with static members, never an enum, for the same reason as ``SpanKind``:
/// adding a member must be a minor release, not a source break.
public struct ElementKind: Hashable, Sendable {
  /// The stable identifier for this element.
  public let rawValue: String

  /// Creates an element kind from a raw value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }
}

extension ElementKind {
  /// A line of ordinary prose. The default classification — a line the grammar
  /// recognized nothing special about is a paragraph line, not an error.
  public static let paragraph = ElementKind(rawValue: "paragraph")

  /// A line that is empty apart from its terminator.
  ///
  /// Distinct from an empty ``paragraph`` because blank lines are block separators in
  /// both grammars: they end paragraphs in Markdown and dialogue blocks in Fountain.
  public static let blank = ElementKind(rawValue: "blank")

  /// An ATX heading line. The heading level is carried in the line record's `depth`,
  /// not in a separate member per level, so geometry keyed by `(ElementKind, depth)`
  /// covers all six levels with one entry shape.
  public static let heading = ElementKind(rawValue: "heading")

  /// An opening or closing code-fence line. Not code itself — it delimits code — so
  /// it is classified apart from ``codeBlock``.
  public static let codeFence = ElementKind(rawValue: "codeFence")

  /// A line inside a fenced code block.
  public static let codeBlock = ElementKind(rawValue: "codeBlock")

  // MARK: - Fountain block elements

  /// A Fountain scene heading — a slug line.
  ///
  /// One kind for both spellings. `INT. HOUSE` and `.INT. HOUSE` are the same element and
  /// get the same geometry; the leading period that forced the second is preserved in the
  /// record's content range rather than in a second `ElementKind`, because a writer
  /// round-tripping the document needs the marker and a styler laying out the page does
  /// not need to know it was there.
  public static let sceneHeading = ElementKind(rawValue: "sceneHeading")

  /// A Fountain action line — the format's default, and what every line that is nothing
  /// else becomes. Distinct from ``paragraph`` because screenplay action has screenplay
  /// margins.
  public static let action = ElementKind(rawValue: "action")

  /// A Fountain transition — `CUT TO:`, or any line forced with a leading `>`. Rendered
  /// flush right.
  public static let transition = ElementKind(rawValue: "transition")

  /// Fountain centered text — `>THE END<`.
  ///
  /// Its own element rather than an alignment flag on ``action`` because alignment is
  /// paragraph geometry, and geometry is looked up by `(ElementKind, depth)`.
  public static let centered = ElementKind(rawValue: "centered")

  /// A Fountain section heading — `#`, `##`, and so on. The level lives in the record's
  /// `depth`, exactly as an ATX heading's does. Structural navigation only: sections do
  /// not appear on the printed page.
  public static let section = ElementKind(rawValue: "section")

  /// A Fountain synopsis — `= a line about what happens here`. Like a section, it is
  /// author-facing and does not print.
  public static let synopsis = ElementKind(rawValue: "synopsis")

  /// A Fountain page break — a line of three or more `=` and nothing else.
  public static let pageBreak = ElementKind(rawValue: "pageBreak")

  /// A Fountain lyric line — `~Willy Wonka`.
  public static let lyrics = ElementKind(rawValue: "lyrics")

  // MARK: - Fountain dialogue

  /// A Fountain character cue — `BOB`, `@McAvoy`, `BOB (V.O.)`, `JANE ^`.
  ///
  /// One kind for every spelling, for the reason ``sceneHeading`` is one kind for two: a
  /// cue lays out as a cue however it was written. What distinguishes the spellings is
  /// kept lexically instead — the forcing `@` and the dual-dialogue `^` are excluded from
  /// the record's content range and emitted as marker spans, so both are recoverable from
  /// the source against `range` and `contentRange`.
  ///
  /// **The content range of a cue is the character *name* alone**, exclusive of the `@`,
  /// of any `(V.O.)` extension, and of the `^`. That is a deliberate choice and it is the
  /// one place in this vocabulary where "content" is narrower than "everything that is not
  /// a marker": a consumer building a cast list — the reason this parser exists in an org
  /// that maps cues to synthesized voices — wants the name and nothing else, and the
  /// extension is still on the line, still spanned, and still recoverable.
  public static let character = ElementKind(rawValue: "character")

  /// A Fountain parenthetical — `(beat)`, `(to Jane)` — on its own line inside a dialogue
  /// block.
  ///
  /// Only inside a dialogue block. `(beat)` at the top of a page is ``action``, because
  /// outside a block there is no speaker for it to modify and Fountain does not invent
  /// one. Its parentheses are **content, not markers**: they print, where a forcing `.`
  /// or a centering `>` does not.
  public static let parenthetical = ElementKind(rawValue: "parenthetical")

  /// A line of spoken Fountain dialogue.
  ///
  /// Every non-blank line inside a dialogue block that is not a cue, a parenthetical, or a
  /// forced element of some other kind. Its own element rather than ``action`` because
  /// dialogue has its own screenplay margins, which is exactly what an `ElementKind` is
  /// for.
  public static let dialogue = ElementKind(rawValue: "dialogue")

  // MARK: - CommonMark block structure

  /// A bullet-list item line — `- item`, `* item`, `+ item`.
  ///
  /// The **nesting level** lives in the record's `depth`, zero-based, exactly as a
  /// heading's level does: geometry keyed by `(ElementKind, depth)` then covers every
  /// nesting level with one entry shape, and a five-deep list needs no vocabulary at all.
  ///
  /// Only the line carrying the marker is a list item. A continuation line inside the same
  /// item is a ``paragraph`` carrying the item's depth, because that is what geometry
  /// needs to indent it and what a writer needs to reproduce it.
  public static let unorderedListItem = ElementKind(rawValue: "unorderedListItem")

  /// A numbered-list item line — `1. item`, `1) item`.
  ///
  /// Distinct from ``unorderedListItem`` because the two are different constructs that a
  /// writer must round-trip and a theme may well indent differently; the number itself is
  /// in the source, recoverable from the record's range and content range.
  public static let orderedListItem = ElementKind(rawValue: "orderedListItem")

  /// A blockquote line — `> quoted`, `>> nested`.
  ///
  /// The **quote nesting** lives in `depth`, zero-based: `>` is depth 0 and `> >` is
  /// depth 1.
  ///
  /// Blockquote content is not re-scanned as Markdown, so `> # Title` is one blockquote
  /// line rather than a heading inside a quote. Saying both at once needs a container axis
  /// on ``LineRecord``, which is public API and not a scanner detail.
  public static let blockquote = ElementKind(rawValue: "blockquote")

  /// A thematic break — `---`, `***`, `___`.
  ///
  /// Pure delimiter, like a closing code fence: the record's content range is empty, and
  /// the whole run is a `SpanRole/marker` span.
  public static let thematicBreak = ElementKind(rawValue: "thematicBreak")

  // MARK: - YAML frontmatter

  /// The `---` opening or closing a document's leading YAML frontmatter region.
  ///
  /// Distinct from ``thematicBreak`` and that distinction is the point: the same three
  /// characters are a horizontal rule everywhere else in the document. Only the
  /// document's **first line** may open a region, so `---` on line five is a
  /// ``thematicBreak`` and `---` on line one is this.
  ///
  /// Pure delimiter — the record's content range is empty.
  public static let frontmatterDelimiter = ElementKind(rawValue: "frontmatterDelimiter")

  /// A line **inside** a YAML frontmatter region.
  ///
  /// One kind for every line in the region, whether it parsed as `key: value` or not,
  /// because geometry is what an `ElementKind` drives and the whole region gets the same
  /// geometry. What a line turned out to be is on the span axis: a recognized entry emits
  /// ``SpanKind/frontmatterKey`` and ``SpanKind/frontmatterValue``, and an unrecognized one
  /// degrades to ``SpanKind/text``.
  public static let frontmatter = ElementKind(rawValue: "frontmatter")

  // MARK: - GitHub-flavored Markdown

  /// A GFM table's **delimiter row** — `|:---|---:|`.
  ///
  /// The row that makes a table a table, and the only line whose record carries
  /// ``LineRecord/tableAlignments``. Pure delimiter: its content range is empty.
  public static let tableDelimiterRow = ElementKind(rawValue: "tableDelimiterRow")

  /// A GFM table **body row** — a line after a delimiter row, up to the blank line or the
  /// pipe-less line that ends the table.
  ///
  /// The **header** row is not this. A header row is recognized in GFM only by the
  /// delimiter row that follows it, which is one line of lookahead this grammar does not
  /// have, so a header row stays a ``paragraph`` — the same deliberate gap a setext
  /// heading's text line has. A consumer that wants the header reads the line above a
  /// `tableDelimiterRow` record.
  public static let tableRow = ElementKind(rawValue: "tableRow")

  // MARK: - Fountain notes, boneyard, and the title page

  /// A line that is **nothing but** one or more Fountain notes — `[[a note]]` on its own
  /// line — or a line inside a note that spans several.
  ///
  /// A note *within* a line does not produce this: `Hello [[to Jane]] there.` inside a
  /// dialogue block is one ``dialogue`` line carrying ``SpanKind/note`` spans, because a
  /// line has one geometry and that line's geometry is dialogue's. This kind is for the
  /// case where there is nothing else on the line for the geometry to belong to.
  ///
  /// **A note does not end a dialogue block.** A note is commentary layered over a
  /// screenplay rather than an element of one, so a `[[note]]` between two lines of speech
  /// leaves the speech contiguous — the same rule ``lyrics`` gets, and for the same reason.
  public static let note = ElementKind(rawValue: "note")

  /// A line inside a Fountain boneyard — the `/* … */` region whose contents are struck
  /// out of the screenplay.
  ///
  /// Produced only when the boneyard was **already open** at the start of the line, or
  /// when the line holds nothing but boneyard. A `/*` that opens mid-line leaves that
  /// line's classification alone: `Bob waits. /* cut this */` is ``action`` carrying
  /// ``SpanKind/boneyard`` spans, because the text that decides what the line is sits
  /// outside the boneyard.
  ///
  /// **A boneyard does not end a dialogue block**, for the reason a ``note`` does not: the
  /// region is removed from the screenplay, so the speech on either side of it is
  /// contiguous in the document that gets printed.
  public static let boneyard = ElementKind(rawValue: "boneyard")

  /// A Fountain title-page **key line** — `Title: Big Fish`, `verbsCovered: run, jump`.
  ///
  /// The record's content range is the **value**; the key is the ``SpanKind/titlePageKey``
  /// span on the line, which covers the key text exactly and is what a writer reads a
  /// non-standard key's spelling and casing back off the source with (REQUIREMENTS.md
  /// § Fountain 2, Architecture §9). Order is line order, which the record's `index`
  /// already carries.
  public static let titlePageKey = ElementKind(rawValue: "titlePageKey")

  /// A Fountain title-page **value line** — an indented continuation under a key, or a
  /// line inside the title page that carries no key of its own.
  ///
  /// Its own element rather than a second ``titlePageKey`` because the two lay out
  /// differently: a key line begins at the margin and a continuation is indented under the
  /// key it belongs to.
  public static let titlePageValue = ElementKind(rawValue: "titlePageValue")
}
