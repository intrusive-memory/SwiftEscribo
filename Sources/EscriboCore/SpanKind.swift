/// What a run of text *is* — the first of the two orthogonal axes a span carries.
///
/// The second axis is ``StyleSet`` (how the text is emphasized). Keeping them
/// separate is what stops `***bold italic***` inside dialogue from needing a
/// `.boldItalicDialogue` case: it is `kind: .dialogue, style: [.strong, .emphasis]`.
///
/// This is a struct with static members rather than an enum, deliberately. A public
/// enum is source-breaking to extend — every consumer's exhaustive `switch` stops
/// compiling the day a Fountain construct is added, which would make routine grammar
/// work a major release. Static members on a struct still pattern-match in a `switch`
/// and still require a `default:`, which is exactly the forward compatibility wanted.
/// Adding a member here is a *minor* release; changing what an existing member is
/// emitted for is *major*.
///
/// Raw values are stable API. Never renumber or respell one.
public struct SpanKind: Hashable, Sendable {
  /// The stable identifier for this kind.
  public let rawValue: String

  /// Creates a kind from a raw value.
  ///
  /// Unrecognized kinds are legal by design: the styler resolves an unknown kind to
  /// its base style rather than trapping, so a consumer scanning with a newer core
  /// against an older theme degrades in appearance, never in correctness.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }
}

extension SpanKind {
  /// Plain text carrying no grammatical meaning of its own.
  ///
  /// Spans exactly tile the scanned range, so unstyled text is emitted as a `.text`
  /// span rather than left as a gap. A gap would require a clear-then-restyle pass
  /// and reintroduce the whole class of stale-attribute bugs that total tiling makes
  /// structurally impossible.
  public static let text = SpanKind(rawValue: "text")

  /// An ATX heading — both the `#` run (as `SpanRole/marker`) and the heading text
  /// (as `SpanRole/content`).
  ///
  /// A marker span carries the *same* kind and style as the content it delimits and
  /// differs only in its role, which is how "the hashes show, dimmed, while the
  /// heading renders large" falls out of the data model instead of a special case.
  public static let heading = SpanKind(rawValue: "heading")

  /// A fenced code block — both the fence delimiter runs (as `SpanRole/marker`) and
  /// the code inside them (as `SpanRole/content`).
  public static let codeBlock = SpanKind(rawValue: "codeBlock")

  /// The info string trailing an opening code fence — the `swift` in ```` ```swift ````.
  ///
  /// Distinct from ``codeBlock`` because it is prose about the block rather than code
  /// in it, and because language dispatch reads it.
  public static let codeInfoString = SpanKind(rawValue: "codeInfoString")

  // MARK: - Fountain block elements

  /// A Fountain scene heading — the slug text, and the leading `.` of a forced one as
  /// `SpanRole/marker`.
  ///
  /// One kind for the marker and the content, differing only in role, which is what makes
  /// "the forcing period shows, dimmed, while the slug line renders as a slug line" a
  /// consequence of the data rather than a case in the styler.
  public static let sceneHeading = SpanKind(rawValue: "sceneHeading")

  /// Fountain action text, and the leading `!` of a forced action line as
  /// `SpanRole/marker`.
  ///
  /// Distinct from ``text`` because action is a *classification* — a screenplay's default
  /// element — where `text` is the absence of one. Emitting it lets a theme give action
  /// its own color without the styler having to consult the line record.
  public static let action = SpanKind(rawValue: "action")

  /// A Fountain transition, and the leading `>` of a forced one as `SpanRole/marker`.
  public static let transition = SpanKind(rawValue: "transition")

  /// Fountain centered text, and its enclosing `>` and `<` as `SpanRole/marker`.
  public static let centered = SpanKind(rawValue: "centered")

  /// A Fountain section heading — the `#` run as `SpanRole/marker` and the title text as
  /// content.
  public static let section = SpanKind(rawValue: "section")

  /// A Fountain synopsis — the leading `=` as `SpanRole/marker` and the text as content.
  public static let synopsis = SpanKind(rawValue: "synopsis")

  /// A Fountain page break. Pure delimiter: the whole `===` run is a `SpanRole/marker`
  /// and there is no content span at all.
  public static let pageBreak = SpanKind(rawValue: "pageBreak")

  /// A Fountain lyric line — the leading `~` as `SpanRole/marker` and the lyric as
  /// content.
  public static let lyrics = SpanKind(rawValue: "lyrics")

  // MARK: - Fountain dialogue

  /// A Fountain character cue — the name as content, and **both** of a cue's markers as
  /// `SpanRole/marker`: the leading `@` that forces it and the trailing `^` that makes the
  /// block dual dialogue.
  ///
  /// Both markers carry this kind rather than a kind of their own, which is the rule
  /// everywhere else in this vocabulary and is what lets the styler dim them without
  /// knowing they exist. They are told apart by position — a leading marker span is the
  /// `@`, a trailing one is the `^` and the whitespace around it — which is enough for a
  /// writer, and the source is authoritative either way.
  public static let character = SpanKind(rawValue: "character")

  /// A character cue's extension — the `(V.O.)` in `BOB (V.O.)`, including any further
  /// `(CONT'D)` after it and the whitespace separating them from the name.
  ///
  /// Distinct from ``character`` for the reason ``codeInfoString`` is distinct from
  /// ``codeBlock``: it is *about* the cue rather than part of the name, a theme will want
  /// to mute it, and a consumer reading a cast list has to be able to drop it. It is
  /// `SpanRole/content`, not a marker — an extension prints.
  public static let characterExtension = SpanKind(rawValue: "characterExtension")

  /// A Fountain parenthetical — `(beat)` on its own line inside a dialogue block.
  ///
  /// The parentheses are part of the content span, not markers, because they print. Any
  /// leading indent is the one marker-role span such a line has.
  public static let parenthetical = SpanKind(rawValue: "parenthetical")

  /// Spoken Fountain dialogue.
  public static let dialogue = SpanKind(rawValue: "dialogue")

  // MARK: - CommonMark block structure

  /// A Markdown list item — the bullet or number **and the whitespace after it** as
  /// `SpanRole/marker`, and the item's text as content.
  ///
  /// One kind for ordered and unordered alike: what a theme wants to do to a bullet it
  /// wants to do to a number, and the line record already says which one it is. As
  /// everywhere else, marker and content differ only in role, so dimming the bullet is the
  /// styler's one marker rule rather than a case.
  public static let listItem = SpanKind(rawValue: "listItem")

  /// A blockquote — the whole `>` marker run as `SpanRole/marker`, and the quoted text as
  /// content.
  ///
  /// The marker run is **one** span rather than one per `>`, so a theme that dims markers
  /// paints one continuous gutter instead of a gutter with holes between the arrows.
  public static let blockquote = SpanKind(rawValue: "blockquote")

  /// A thematic break — `---`, `***`, `___`.
  ///
  /// Marker only. There is no content span because a thematic break has no content, which
  /// is also why a theme styles it by drawing rather than by coloring text.
  public static let thematicBreak = SpanKind(rawValue: "thematicBreak")

  // MARK: - CommonMark inline structure

  /// The **text** of a link — `[text]` — and its enclosing brackets as
  /// `SpanRole/marker`.
  ///
  /// Distinct from ``linkURL`` so a theme can paint the words a reader clicks differently
  /// from the destination they point at, which is the whole reason the two are separate
  /// kinds rather than one `.link` with a role.
  ///
  /// A link **overrides** the enclosing block's kind: `[x](y)` inside a heading is a link,
  /// not heading-sized text. That is a deliberate trade. There is no ``StyleSet`` flag
  /// meaning "this is a destination", so the only axis that can express it is `kind`, and
  /// `kind` is one value. Emphasis and code spans do *not* make this trade — they live on
  /// the style axis and leave the block's kind alone.
  public static let link = SpanKind(rawValue: "link")

  /// A link or image **destination** — the `(url)` of `[text](url)`, with the parentheses,
  /// any `<`…`>`, and the whitespace inside them as `SpanRole/marker`.
  ///
  /// The kind the sortie brief names by hand, and the reason it does: a URL is the one run
  /// in a Markdown document a reader most wants de-emphasized, and nothing on the style
  /// axis can say so.
  public static let linkURL = SpanKind(rawValue: "linkURL")

  /// The optional **title** of a link or image — the `"…"`, `'…'`, or `(…)` after the
  /// destination — with its quotes as `SpanRole/marker`.
  public static let linkTitle = SpanKind(rawValue: "linkTitle")

  /// The **alt text** of an image — `![alt]` — and its `![` and `]` as
  /// `SpanRole/marker`. The destination that follows is ``linkURL``, the same as a link's:
  /// what a theme wants to do to one URL it wants to do to both.
  public static let image = SpanKind(rawValue: "image")

  /// A hard line break — two or more trailing spaces, or a trailing backslash.
  ///
  /// Marker only, like ``thematicBreak``: the break *is* the syntax, and there is no
  /// content to wrap. Emitting it as a span rather than dropping it is what keeps the
  /// tiling total over trailing whitespace a reader cannot otherwise see.
  public static let hardBreak = SpanKind(rawValue: "hardBreak")
}
