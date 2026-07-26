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
    ],
    styleStyles: markdownStyleFlags,
    elementSizeScales: [.heading: headingSizeScale],
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
    ],
    styleStyles: markdownStyleFlags,
    elementSizeScales: [.heading: headingSizeScale],
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
      )
    ],
    styleStyles: screenplayStyleFlags,
    // Deliberately empty. A screenplay page is uniform 12-point: nothing on it is set
    // larger than anything else, so there is no scale to declare.
    elementSizeScales: [:],
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
      )
    ],
    styleStyles: screenplayStyleFlags,
    elementSizeScales: [:],
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
}
