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
}
