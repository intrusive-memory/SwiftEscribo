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
}
