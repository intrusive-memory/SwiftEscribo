/// What a *block* is — a run of consecutive ``LineRecord`` values that a writer thinks
/// of as one unit.
///
/// Where ``EscriboSpan`` drives character attributes and ``LineRecord`` drives paragraph
/// geometry, a block drives everything that acts on a writer's *unit of thought*: the
/// paragraph well's hover lane, read-aloud's selection granularity, and the script
/// preview's speech grouping. Those three consumers previously each rediscovered "where
/// does this paragraph end" from line records and could — and did — disagree. A block is
/// the one answer they share (REQUIREMENTS-1.1.0 § 4).
///
/// ## Coordinates
///
/// - ``lines`` is a half-open range of **document line indices**, matching
///   ``LineRecord/index``. It is not an index into any array.
/// - ``range`` and ``contentRanges`` are **UTF-16 code-unit** offsets into the document,
///   the same coordinate space as ``LineRecord/range``.
///
/// ## There is no public initializer
///
/// Blocks are scanner output, for the reason ``LineRecord`` and ``ScanResult`` are: a
/// consumer receives them and never fabricates one. Grouping is a property of the
/// grammar, and a caller who could assemble a block could assemble one the grammar
/// would never produce.
public struct EscriboBlock: Sendable, Equatable, Identifiable {

  /// A block's identity **within one scan of one document revision**.
  ///
  /// Composite rather than a bare `Int` so that it cannot be mistaken for either
  /// coordinate on its own, and so that a consumer diffing two scans of the same
  /// unedited text gets stable identities for free. It is deliberately *not* stable
  /// across an edit that moves a block: nothing in the scanner carries identity across
  /// edits, and pretending otherwise would be a lie a `ForEach` would eventually pay
  /// for.
  public struct ID: Hashable, Sendable {
    /// The block's first line index.
    public let line: Int

    /// The block's first UTF-16 offset.
    public let offset: Int
  }

  /// What this block is.
  public let kind: BlockKind

  /// The half-open range of **document line indices** this block covers. Never empty.
  public let lines: Range<Int>

  /// The block's full extent in **UTF-16 code units**: the first line's start to the
  /// last line's end.
  ///
  /// "The last line's end" is ``LineRecord/range``'s upper bound, so the final
  /// terminator is **inside** this range. That is the same convention `LineRecord` uses,
  /// and a block whose range stopped short of the terminator could not be used to
  /// replace the block's text without leaving a stray newline behind.
  public let range: Range<Int>

  /// The block's content, **markers excluded**, one range per contributing line, in
  /// order.
  ///
  /// This is the concatenation of the non-empty ``LineRecord/contentRange`` values of the
  /// block's lines, so the `## ` of a heading, the `- ` of a list item, and the `> ` of a
  /// blockquote are not in it — that exclusion is `LineRecord`'s, inherited rather than
  /// re-derived. Lines that are pure delimiter contribute nothing: a closing code fence, a
  /// setext underline, a blank line, and a table delimiter row are all absent, which is
  /// why this is an *array* of ranges rather than one range: a block's content is not
  /// contiguous in the document even though the block is.
  ///
  /// `Range<Int>` rather than `NSRange`, deliberately and for the same reason as
  /// ``LineRecord/range`` and ``ScanResult/dirtyRange``: `EscriboCore` imports no
  /// Foundation, and one `NSRange` here would be both the module's only Foundation
  /// dependency and the API's only inconsistent coordinate type. A consumer that needs
  /// `NSRange` converts at the module boundary it already crosses.
  ///
  /// Read aloud reads exactly these ranges, joined. A block with no content — a blank run,
  /// a thematic break — has an empty array, and that is the signal that there is nothing to
  /// speak.
  public let contentRanges: [Range<Int>]

  /// The document line indices whose content is in ``contentRanges``, **index-aligned
  /// with it**: `contentLines[i]` is the line that `contentRanges[i]` lies on.
  ///
  /// The two arrays always have equal count, and that is guaranteed *by construction* —
  /// both are derived from one filtered pass over the block's records, not assembled
  /// separately and hoped to agree.
  ///
  /// ## Why this exists
  ///
  /// ``contentRanges`` is filtered twice: lines with no content at all are dropped, and
  /// so is the content of a line the block absorbed but must not speak — a `[[note]]` or
  /// a `/* boneyard */` sitting between a cue and its dialogue. After that filtering
  /// `contentRanges[i]` no longer corresponds to `lines.lowerBound + i`, so the pairing
  /// from range back to line is gone. This restores it.
  ///
  /// **An absorbed line's index is absent from this array, and that absence is the
  /// point.** It is how a consumer that needs per-line units — the script preview, which
  /// paginates one unit per line — learns which lines a block contains but does not
  /// speak, without hardcoding the annotation vocabulary or inferring the filter's
  /// behaviour from set membership. `Set(contentLines)` is that answer directly; the
  /// lines in ``lines`` and not in this array are exactly the ones the block carries for
  /// tiling and nothing else.
  ///
  /// Strictly increasing, and every element is inside ``lines``. Empty when the block has
  /// no content at all — a blank run, a thematic break — in which case ``contentRanges``
  /// is empty too.
  ///
  /// A **standalone** annotation block is not affected by any of this: a note that *is*
  /// the block is the block's content, so its line index is present. Only a line absorbed
  /// into a block of some other kind is omitted. Whether such a block should be read
  /// aloud at all is a separate question, answered by ``kind``.
  public let contentLines: [Int]

  public var id: ID { ID(line: lines.lowerBound, offset: range.lowerBound) }

  /// Creates a block.
  ///
  /// `internal` on purpose — see the type's discussion.
  init(
    kind: BlockKind,
    lines: Range<Int>,
    range: Range<Int>,
    contentRanges: [Range<Int>],
    contentLines: [Int]
  ) {
    self.kind = kind
    self.lines = lines
    self.range = range
    self.contentRanges = contentRanges
    self.contentLines = contentLines
  }
}

/// What one ``EscriboBlock`` is — the block-level vocabulary of **both** dialects.
///
/// One vocabulary for Markdown and Fountain together, rather than one per dialect,
/// because every consumer of blocks is dialect-agnostic by design: the well lane,
/// read-aloud, and the preview switch on what a block *is*, not on which grammar
/// produced it. Two vocabularies would push that switch into every call site and make
/// "a paragraph and an action line both get the read-aloud button" a statement made in
/// three places.
///
/// A struct with static members rather than an enum, for the same reason as ``SpanKind``,
/// ``ElementKind``, ``Language``, and ``SpanRole``, and the reason is worth restating
/// because an enum is the obvious-looking shape and this file will be read by someone who
/// wants to "fix" it back. **A public enum is source-breaking to extend.** Every
/// consumer's exhaustive `switch` stops compiling the day a block kind is added, which
/// would make routine grammar work a major release — and there are eleven downstream
/// consumers of this type. Static members on a struct still pattern-match in a `switch`
/// and still require a `default:`, which is exactly the forward compatibility wanted.
/// Adding a member here is a *minor* release; changing what an existing member is emitted
/// for is *major*.
///
/// Raw values are stable API. Never renumber or respell one.
///
/// The Markdown members are produced by ``EscriboBlockGrouper/markdownBlocks(from:)``; the
/// Fountain members are declared here and produced by the Fountain grouping that follows
/// (REQUIREMENTS-1.1.0 § 4.2).
public struct BlockKind: Hashable, Sendable {
  /// The stable identifier for this kind.
  public let rawValue: String

  /// Creates a block kind from a raw value.
  ///
  /// Unrecognized kinds are legal by design, as they are for every other vocabulary in
  /// this package: a consumer reading blocks produced by a newer core resolves an unknown
  /// kind to its default treatment rather than trapping.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }
}

extension BlockKind {

  // MARK: - Markdown (§ 4.1)

  /// A run of consecutive `.paragraph` lines, ended by a blank line or any other
  /// element. The hard-wrapped prose paragraph — the case the paragraph well exists for.
  public static let paragraph = BlockKind(rawValue: "paragraph")

  /// One ATX heading line, or a setext pair: the text line plus its `===`/`---`
  /// underline, as **one** block.
  public static let heading = BlockKind(rawValue: "heading")

  /// One list item: the marker line plus its continuation lines. **Each item is its own
  /// block** — a five-item list is five blocks, never one.
  public static let listItem = BlockKind(rawValue: "listItem")

  /// A run of consecutive `.blockquote` lines **at the same depth**. A change of depth
  /// starts a new block, because a nested quote is a different unit to a writer.
  public static let blockquote = BlockKind(rawValue: "blockquote")

  /// A code block: a whole fence, opener through closer, or a run of indented code lines.
  public static let codeBlock = BlockKind(rawValue: "codeBlock")

  /// A GFM table: its header line, its delimiter row, and its body rows.
  public static let table = BlockKind(rawValue: "table")

  /// A document's leading YAML frontmatter region, delimiters included.
  public static let frontmatter = BlockKind(rawValue: "frontmatter")

  /// A thematic break — one line, `---`, `***`, `___`.
  public static let thematicBreak = BlockKind(rawValue: "thematicBreak")

  /// A run of consecutive blank lines. Present so that blocks tile a scan's lines with no
  /// gaps, which is what lets an offset-to-block lookup be a search rather than a search
  /// plus a fallback.
  public static let blank = BlockKind(rawValue: "blank")

  // MARK: - Fountain (§ 4.2)

  /// A Fountain scene heading — one line.
  public static let sceneHeading = BlockKind(rawValue: "sceneHeading")

  /// A run of consecutive `.action` lines.
  public static let action = BlockKind(rawValue: "action")

  /// A character cue plus the contiguous parentheticals and dialogue lines that follow
  /// it. The one block whose boundary rule is not "a run of one element", and the reason
  /// the rule belongs in the package rather than in the preview.
  public static let speech = BlockKind(rawValue: "speech")

  /// A run of transition lines.
  public static let transition = BlockKind(rawValue: "transition")

  /// A run of centered lines.
  public static let centered = BlockKind(rawValue: "centered")

  /// A run of lyric lines.
  public static let lyrics = BlockKind(rawValue: "lyrics")

  /// A run of note lines.
  public static let note = BlockKind(rawValue: "note")

  /// A run of boneyard lines.
  public static let boneyard = BlockKind(rawValue: "boneyard")

  /// A Fountain section heading.
  public static let section = BlockKind(rawValue: "section")

  /// A Fountain synopsis line.
  public static let synopsis = BlockKind(rawValue: "synopsis")

  /// A Fountain page break.
  public static let pageBreak = BlockKind(rawValue: "pageBreak")

  /// The Fountain title page — its key lines and their continuations.
  public static let titlePage = BlockKind(rawValue: "titlePage")
}
