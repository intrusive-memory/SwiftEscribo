import EscriboCore

/// The built-in themes: light and dark for both languages, plus the source theme.
///
/// ## Why light and dark are two values rather than one adaptive theme
///
/// ``EscriboColor`` stores components, not a dynamic platform color, so a theme cannot
/// silently change what it renders when the system appearance flips. Appearance is
/// instead one of the styler's four declared invalidation triggers, and the host swaps
/// the theme. That is more typing and one less way to end up with dark-mode text on a
/// light background.
///
/// ## Why the Fountain themes look thin
///
/// They style what the scanner emits *today*. `EscriboCore`'s Fountain vocabulary —
/// scene headings, character cues, dialogue, parentheticals, transitions — arrives in
/// Sortie 13, and a theme entry for a `SpanKind` nothing produces is decoration. What
/// these themes fix now is the part that is genuinely a Fountain decision and not a
/// Sortie 13 decision: a monospaced base at screenplay size, no per-element size scaling
/// (a screenplay page is uniform), and marker dimming.
///
/// ## Why the leading regions declare a family the base already gives them
///
/// The title-page and frontmatter entries in the Fountain themes set
/// ``FontFamilyRole/monospaced`` even though ``base`` is already monospaced. That is not
/// redundancy for its own sake: a screenplay's metadata must be monospaced *because it is
/// metadata* — it is `Key: Value` text whose columns are the whole reason it is readable —
/// and not because the body around it happens to be. A host that swaps the base family for
/// a proportional reading face keeps the guarantee, and the two Markdown themes, whose base
/// is proportional, reach the same rendering through the same entries.
extension EscriboTheme {

  // MARK: - Markdown

  /// Markdown on a light background.
  public static let markdownLight = EscriboTheme(
    name: "Markdown Light",
    baseFontSize: 14,
    base: TokenStyle(
      foreground: EscriboColor(red: 0.11, green: 0.11, blue: 0.12),
      family: .body
    ),
    kindStyles: [
      .heading: TokenStyle(
        foreground: EscriboColor(red: 0.05, green: 0.28, blue: 0.63),
        traits: .bold
      ),
      .codeBlock: TokenStyle(
        foreground: EscriboColor(red: 0.31, green: 0.16, blue: 0.42),
        family: .monospaced
      ),
      .codeInfoString: TokenStyle(
        foreground: EscriboColor(red: 0.42, green: 0.42, blue: 0.45),
        family: .monospaced,
        traits: .italic
      ),
      .frontmatterDelimiter: TokenStyle(
        foreground: EscriboColor(red: 0.42, green: 0.42, blue: 0.45),
        family: .monospaced
      ),
      .frontmatterKey: TokenStyle(
        foreground: EscriboColor(red: 0.31, green: 0.16, blue: 0.42),
        family: .monospaced
      ),
      .frontmatterValue: TokenStyle(
        foreground: EscriboColor(red: 0.24, green: 0.30, blue: 0.36),
        family: .monospaced
      ),
    ],
    styleStyles: markdownStyleFlags,
    elementSizeScales: [.heading: headingSizeScale],
    elementParagraphMetrics: markdownParagraphMetrics,
    markerOpacity: 0.4
  )

  /// Markdown on a dark background.
  public static let markdownDark = EscriboTheme(
    name: "Markdown Dark",
    baseFontSize: 14,
    base: TokenStyle(
      foreground: EscriboColor(red: 0.90, green: 0.90, blue: 0.92),
      family: .body
    ),
    kindStyles: [
      .heading: TokenStyle(
        foreground: EscriboColor(red: 0.48, green: 0.71, blue: 1.0),
        traits: .bold
      ),
      .codeBlock: TokenStyle(
        foreground: EscriboColor(red: 0.78, green: 0.62, blue: 0.92),
        family: .monospaced
      ),
      .codeInfoString: TokenStyle(
        foreground: EscriboColor(red: 0.62, green: 0.62, blue: 0.66),
        family: .monospaced,
        traits: .italic
      ),
      .frontmatterDelimiter: TokenStyle(
        foreground: EscriboColor(red: 0.62, green: 0.62, blue: 0.66),
        family: .monospaced
      ),
      .frontmatterKey: TokenStyle(
        foreground: EscriboColor(red: 0.78, green: 0.62, blue: 0.92),
        family: .monospaced
      ),
      .frontmatterValue: TokenStyle(
        foreground: EscriboColor(red: 0.72, green: 0.79, blue: 0.86),
        family: .monospaced
      ),
    ],
    styleStyles: markdownStyleFlags,
    elementSizeScales: [.heading: headingSizeScale],
    elementParagraphMetrics: markdownParagraphMetrics,
    markerOpacity: 0.5
  )

  // MARK: - Fountain

  /// Fountain on a light background.
  public static let fountainLight = EscriboTheme(
    name: "Fountain Light",
    baseFontSize: 12,
    base: TokenStyle(
      foreground: EscriboColor(red: 0.10, green: 0.10, blue: 0.10),
      family: .monospaced
    ),
    kindStyles: [
      .heading: TokenStyle(
        foreground: EscriboColor(red: 0.16, green: 0.24, blue: 0.44),
        traits: .bold
      ),
      .titlePageKey: TokenStyle(
        foreground: EscriboColor(red: 0.35, green: 0.30, blue: 0.20),
        family: .monospaced
      ),
      .titlePageValue: TokenStyle(
        foreground: EscriboColor(red: 0.10, green: 0.10, blue: 0.10),
        family: .monospaced
      ),
      .frontmatterDelimiter: TokenStyle(
        foreground: EscriboColor(red: 0.42, green: 0.42, blue: 0.45),
        family: .monospaced
      ),
      .frontmatterKey: TokenStyle(
        foreground: EscriboColor(red: 0.31, green: 0.16, blue: 0.42),
        family: .monospaced
      ),
      .frontmatterValue: TokenStyle(
        foreground: EscriboColor(red: 0.24, green: 0.30, blue: 0.36),
        family: .monospaced
      ),
    ],
    styleStyles: screenplayStyleFlags,
    // Deliberately empty. A screenplay page is uniform 12-point: nothing on it is set
    // larger than anything else, so there is no scale to declare.
    elementSizeScales: [:],
    elementParagraphMetrics: fountainParagraphMetrics,
    markerOpacity: 0.4
  )

  /// Fountain on a dark background.
  public static let fountainDark = EscriboTheme(
    name: "Fountain Dark",
    baseFontSize: 12,
    base: TokenStyle(
      foreground: EscriboColor(red: 0.91, green: 0.90, blue: 0.87),
      family: .monospaced
    ),
    kindStyles: [
      .heading: TokenStyle(
        foreground: EscriboColor(red: 0.62, green: 0.75, blue: 1.0),
        traits: .bold
      ),
      .titlePageKey: TokenStyle(
        foreground: EscriboColor(red: 0.80, green: 0.74, blue: 0.58),
        family: .monospaced
      ),
      .titlePageValue: TokenStyle(
        foreground: EscriboColor(red: 0.91, green: 0.90, blue: 0.87),
        family: .monospaced
      ),
      .frontmatterDelimiter: TokenStyle(
        foreground: EscriboColor(red: 0.62, green: 0.62, blue: 0.66),
        family: .monospaced
      ),
      .frontmatterKey: TokenStyle(
        foreground: EscriboColor(red: 0.78, green: 0.62, blue: 0.92),
        family: .monospaced
      ),
      .frontmatterValue: TokenStyle(
        foreground: EscriboColor(red: 0.72, green: 0.79, blue: 0.86),
        family: .monospaced
      ),
    ],
    styleStyles: screenplayStyleFlags,
    elementSizeScales: [:],
    elementParagraphMetrics: fountainParagraphMetrics,
    markerOpacity: 0.5
  )

  // MARK: - Source

  /// The built-in source theme: every kind, every style combination, and both roles
  /// resolve to the base attributes.
  ///
  /// This is what ``EditorMode/source`` looks like when the host has expressed no
  /// preference. When a host *has* a theme, prefer `theme.strippedToSource()`, which
  /// keeps that theme's base — an appearance-correct source mode falls out of that, with
  /// no appearance branch here.
  public static let source = EscriboTheme(
    name: "Source",
    baseFontSize: 13,
    base: TokenStyle(
      foreground: EscriboColor(red: 0.12, green: 0.12, blue: 0.13),
      family: .monospaced
    ),
    markerOpacity: 1
  )

  // MARK: - Selection

  /// The built-in theme for `language` under `appearance`.
  ///
  /// Total for a `Language` this version has never heard of — it gets the Markdown
  /// theme, matching `EscriboCore`'s own treatment of an unknown language as plain text.
  static func builtIn(language: Language, appearance: EscriboAppearance) -> EscriboTheme {
    switch (language, appearance) {
    case (.fountain, .dark): fountainDark
    case (.fountain, _): fountainLight
    case (_, .dark): markdownDark
    default: markdownLight
    }
  }

  // MARK: - Shared tables

  /// ATX heading levels 1…6. Level lives in `LineRecord.depth`, so this is keyed by it.
  private static let headingSizeScale: [Int: Double] = [
    0: 1.0, 1: 1.8, 2: 1.5, 3: 1.3, 4: 1.15, 5: 1.05, 6: 1.0,
  ]

  /// The stage-3 table shared by both Markdown themes.
  ///
  /// Only `traits` and the two decoration flags appear here. Emphasis must not recolor
  /// text — a bold run inside a heading stays heading-colored, because the kind stage ran
  /// first and this stage contributes no foreground to override it.
  private static let markdownStyleFlags: [StyleSet: TokenStyle] = [
    .strong: TokenStyle(traits: .bold),
    .emphasis: TokenStyle(traits: .italic),
    .strikethrough: TokenStyle(strikethrough: true),
    .inlineCode: TokenStyle(family: .monospaced),
    .underline: TokenStyle(underline: true),
  ]

  /// The stage-3 table shared by both Fountain themes.
  ///
  /// `.inlineCode` is absent: Fountain has no code spans, and a family swap for a flag no
  /// Fountain grammar emits is a table entry that can only ever be wrong.
  private static let screenplayStyleFlags: [StyleSet: TokenStyle] = [
    .strong: TokenStyle(traits: .bold),
    .emphasis: TokenStyle(traits: .italic),
    .underline: TokenStyle(underline: true),
    .strikethrough: TokenStyle(strikethrough: true),
  ]

  // MARK: - Paragraph geometry (Sortie 27)

  /// Screenplay margins, in **characters at 10 CPI** (REQUIREMENTS.md § Editor 3),
  /// expressed as offsets from the action column's own left and right edges.
  ///
  /// Sourced from the standard screenplay page (1.5" action margin, 1" right margin,
  /// on 8.5"-wide paper) and converted at 10 characters per inch:
  ///
  /// | Element        | Left edge | Offset from action | Right edge | Offset from action |
  /// |----------------|-----------|---------------------|------------|---------------------|
  /// | Action         | 1.5"      | 0"                  | 7.5"       | 0"                  |
  /// | Character cue  | 3.7"      | 2.2" → 22 ch         | 7.5"       | 0"                  |
  /// | Parenthetical  | 3.1"      | 1.6" → 16 ch         | 5.1"       | 2.4" → 24 ch         |
  /// | Dialogue       | 2.5"      | 1.0" → 10 ch         | 6.0"       | 1.5" → 15 ch         |
  ///
  /// Named rather than inlined into the tables below for two reasons: a reviewer can
  /// see the whole margin scheme in one place, and DL-46's grep — which forbids a
  /// hardcoded point constant in a theme table — reads a named character constant at
  /// every `leftIndentChars:` call site, never a bare number.
  private enum FountainMargins {
    /// Character cue: 22 characters right of the action margin.
    static let characterIndentChars: Double = 22
    /// Parenthetical: 16 characters right of the action margin.
    static let parentheticalIndentChars: Double = 16
    /// Parenthetical's right margin, inward from the action column's own right edge.
    static let parentheticalRightMarginChars: Double = 24
    /// Dialogue: 10 characters right of the action margin.
    static let dialogueIndentChars: Double = 10
    /// Dialogue's right margin, inward from the action column's own right edge.
    static let dialogueRightMarginChars: Double = 15
  }

  /// The Fountain paragraph-geometry rule set, shared by both Fountain themes.
  ///
  /// One layer, two rule sets (REQUIREMENTS.md § Editor 6): this table and
  /// ``markdownParagraphMetrics`` are both consumed by the same
  /// `ParagraphMetrics.paragraphStyle(in:)` conversion in `ParagraphGeometry.swift` —
  /// nothing here builds a second `NSParagraphStyle` code path.
  ///
  /// Every entry sets `alignment` explicitly to something other than ``ParagraphAlignment/natural``
  /// — `.left`, `.right`, or `.center`. Fountain paragraph geometry is **LTR-only**
  /// (REQUIREMENTS.md § Editor 3 fixes physical margins in characters at 10 CPI); that is a
  /// scope statement, not an oversight, and `.natural` would silently reopen the RTL question
  /// this rule set does not answer.
  private static let fountainParagraphMetrics: [ElementKind: [Int: ParagraphMetrics]] = [
    // Action and scene headings sit at the action column's own margin — no extra
    // indent — but still declare `.left` explicitly rather than leaving alignment
    // at its `.natural` default, for the reason above.
    .sceneHeading: [0: ParagraphMetrics(alignment: .left)],
    .action: [0: ParagraphMetrics(alignment: .left)],
    .character: [
      0: ParagraphMetrics(
        leftIndentChars: FountainMargins.characterIndentChars, alignment: .left)
    ],
    .parenthetical: [
      0: ParagraphMetrics(
        leftIndentChars: FountainMargins.parentheticalIndentChars,
        rightIndentChars: FountainMargins.parentheticalRightMarginChars,
        alignment: .left)
    ],
    .dialogue: [
      0: ParagraphMetrics(
        leftIndentChars: FountainMargins.dialogueIndentChars,
        rightIndentChars: FountainMargins.dialogueRightMarginChars,
        alignment: .left)
    ],
    // Flush right within the action column — CUT TO:, and any line forced with `>`.
    .transition: [0: ParagraphMetrics(alignment: .right)],
    // Centered within the action column — `>THE END<`.
    .centered: [0: ParagraphMetrics(alignment: .center)],
  ]

  /// Markdown indent unit, in characters, per level of nesting (REQUIREMENTS.md § Editor 6:
  /// list and blockquote indents via `firstLineHeadIndent` / `headIndent`).
  ///
  /// Named for the same DL-46 reason ``FountainMargins`` is: every `leftIndentChars:`
  /// argument below is a named constant or an arithmetic expression over one, never a bare
  /// number.
  private enum MarkdownMargins {
    /// Characters of indent contributed by *each* level of list nesting. A depth-0
    /// (unnested) item carries no geometry of its own beyond its marker text — nesting is
    /// what this constant charges for — so `leftIndentChars` at depth *n* is this constant
    /// times *n*, and depth 2 is therefore always exactly twice depth 1.
    static let listIndentUnitChars: Double = 4
    /// Characters of indent contributed by *each* level of blockquote nesting, including
    /// the outermost: unlike a list marker, `>` earns a margin at every depth, so
    /// `leftIndentChars` at depth *n* is this constant times *n + 1*.
    static let blockquoteIndentUnitChars: Double = 4
  }

  /// `leftIndentChars` scaled linearly by nesting depth — the shape both the list and
  /// blockquote tables below share, differing only in whether depth 0 is bare.
  private static func linearIndentTable(
    unit: Double, throughDepth: Int, startingAt firstDepth: Int = 0
  ) -> [Int: ParagraphMetrics] {
    var table: [Int: ParagraphMetrics] = [:]
    for depth in 0...throughDepth {
      table[depth] = ParagraphMetrics(
        leftIndentChars: unit * Double(depth + firstDepth), alignment: .natural)
    }
    return table
  }

  /// The Markdown paragraph-geometry rule set, shared by both Markdown themes.
  ///
  /// `.paragraph` and every list/blockquote entry declare ``ParagraphAlignment/natural``
  /// explicitly: unlike the Fountain rule set, Markdown geometry works in RTL, because
  /// nothing here fixes a physical left or right edge.
  private static let markdownParagraphMetrics: [ElementKind: [Int: ParagraphMetrics]] = [
    // A small paragraph-to-paragraph gap. Non-default (so this is a real table entry, not
    // the absent-element fallback) while still `.natural`.
    .paragraph: [0: ParagraphMetrics(spaceBeforeLines: 0.5, alignment: .natural)],
    // Heading level lives in `depth`, exactly as `elementSizeScales` above reads it — more
    // space before a bigger heading, tapering as the level number grows.
    .heading: [
      0: ParagraphMetrics(spaceBeforeLines: 0.6, alignment: .natural),
      1: ParagraphMetrics(spaceBeforeLines: 1.2, alignment: .natural),
      2: ParagraphMetrics(spaceBeforeLines: 1.0, alignment: .natural),
      3: ParagraphMetrics(spaceBeforeLines: 0.9, alignment: .natural),
      4: ParagraphMetrics(spaceBeforeLines: 0.8, alignment: .natural),
      5: ParagraphMetrics(spaceBeforeLines: 0.7, alignment: .natural),
      6: ParagraphMetrics(spaceBeforeLines: 0.6, alignment: .natural),
    ],
    // List nesting saturates at `MarkdownBlockState.maxTrackedDepth - 1` (7); every depth
    // up to and including it gets its own entry so a deeply nested list never falls back to
    // depth 0's bare geometry.
    .unorderedListItem: linearIndentTable(
      unit: MarkdownMargins.listIndentUnitChars, throughDepth: 7),
    .orderedListItem: linearIndentTable(
      unit: MarkdownMargins.listIndentUnitChars, throughDepth: 7),
    // Blockquote nesting has no scanner-enforced ceiling; seven levels covers any quote a
    // human would actually write, and depth 0 already carries one unit of margin.
    .blockquote: linearIndentTable(
      unit: MarkdownMargins.blockquoteIndentUnitChars, throughDepth: 7, startingAt: 1),
  ]
}
