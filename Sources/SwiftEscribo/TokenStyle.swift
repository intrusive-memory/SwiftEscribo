/// One theme table entry: what a composition stage contributes, and nothing more.
///
/// The same type serves all three of the stages that can contribute anything — base,
/// kind, and style (REQUIREMENTS.md § Composition order) — because the *rule* for
/// combining them is uniform: **traits union, everything else overrides**. A `nil` field
/// contributes nothing and leaves whatever an earlier stage put there.
///
/// ## What is deliberately absent
///
/// **There is no point size and no size scale on this type.** Paragraph size is looked up
/// by the line's `ElementKind` and `depth` (``EscriboTheme/sizeScale(for:depth:)``),
/// never by a span's `SpanKind`. Two reasons, and the second is the load-bearing one:
///
/// 1. Architecture §3 requires size to vary per line and never within a line — resizing
///    a marker makes text jitter while typing.
/// 2. The Markdown grammar emits a heading's *leading indent* as a `SpanKind/text` span,
///    not as part of the heading's marker. A size scale hung off `SpanKind` would
///    therefore render an indented heading's indent at body size and the rest of the line
///    at heading size: within-line uniformity broken by the very construct it was meant
///    to serve. Since the type has no size field, that cannot be written.
///
/// **There is no marker entry and no marker `TokenStyle`.** Marker appearance is the
/// single scalar ``EscriboTheme/markerOpacity``, so "markers in a different font" and
/// "markers a size smaller" are not expressible. See that property's documentation.
public struct TokenStyle: Equatable, Sendable {

  /// The foreground color. Overrides.
  public var foreground: EscriboColor?

  /// The background color. Overrides. `nil` at every stage means no background attribute
  /// is emitted at all, which is not the same as an explicit clear background.
  public var background: EscriboColor?

  /// The family. Overrides — a fenced code block swaps to monospaced, and `.inlineCode`
  /// does the same for a run inside a paragraph.
  public var family: FontFamilyRole?

  /// Font traits. **Unions** with whatever earlier stages contributed. This is the one
  /// field that does not override, and it is the difference between a code span inside a
  /// bold heading rendering bold-mono and rendering mono-only.
  public var traits: FontTraits

  /// Whether the run is underlined. Overrides, so a later stage can turn it back off.
  public var underline: Bool?

  /// Whether the run is struck through. Overrides.
  public var strikethrough: Bool?

  /// Creates a token style. Every field defaults to "contributes nothing".
  public init(
    foreground: EscriboColor? = nil,
    background: EscriboColor? = nil,
    family: FontFamilyRole? = nil,
    traits: FontTraits = [],
    underline: Bool? = nil,
    strikethrough: Bool? = nil
  ) {
    self.foreground = foreground
    self.background = background
    self.family = family
    self.traits = traits
    self.underline = underline
    self.strikethrough = strikethrough
  }

  /// A style that contributes nothing. What an unrecognized `SpanKind` resolves against.
  public static let none = TokenStyle()
}
