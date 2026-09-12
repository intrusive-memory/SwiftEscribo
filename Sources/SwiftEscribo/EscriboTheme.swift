import EscriboCore

/// How a document looks: a **value type holding a lookup table**.
///
/// ## Why a table and not a protocol
///
/// REQUIREMENTS.md § Theme is explicit that a theme is not a protocol with an
/// `attributes(for:)` method. A protocol call per span allocates an attribute dictionary
/// per span — tolerable for a three-span keystroke, wasteful across the ~10⁴ spans of a
/// cold 120 KB document, and awkward to make `Sendable`. A table, by contrast, lets
/// ``EscriboStyler`` cache by `(SpanKind, StyleSet, SpanRole)` and turn the hot path into
/// a dictionary read. It also makes theme equality real, which is what lets the styler
/// decide whether its cache survived a change.
///
/// ## The tables, in composition order
///
/// 1. ``base`` — family, size, foreground, background.
/// 2. ``kindStyles`` — per-`SpanKind` overrides. **Absence is legal**: an unrecognized
///    kind resolves to ``base`` rather than trapping, which is what lets a theme written
///    against 1.0 keep working when 1.1 adds a Fountain construct.
/// 3. ``styleStyles`` — per-`StyleSet`-*flag* contributions, applied additively in
///    ascending bit order.
/// 4. ``markerOpacity`` — the role stage, and the whole of it.
///
/// ``elementSizeScales`` sits outside that sequence on purpose: it is keyed by the
/// *line's* `ElementKind` and `depth`, not by a span's kind, because point size must vary
/// per line and never within a line. See ``TokenStyle`` for why that is not merely a
/// convention here.
public struct EscriboTheme: Equatable, Sendable {

  /// A human-readable name. Not an identifier — nothing dispatches on it.
  public var name: String

  /// The point size every other size is derived from, before font metrics and the line's
  /// element scale are applied.
  public var baseFontSize: Double

  /// Stage 1. Family, foreground, and background for every span the document contains.
  ///
  /// Every field of this one should be non-`nil`: it is the floor the other stages build
  /// on and the answer for a kind no table mentions. A missing foreground resolves to
  /// ``EscriboColor/black`` and a missing family to ``FontFamilyRole/monospaced`` rather
  /// than failing — a per-keystroke attribute lookup has no useful error to report.
  public var base: TokenStyle

  /// Stage 2. Per-`SpanKind` overrides, sparse by design.
  public var kindStyles: [SpanKind: TokenStyle]

  /// Stage 3. Per-flag contributions, keyed by a **single-bit** `StyleSet`.
  ///
  /// Keyed by individual flags rather than by whole sets so that `[.strong, .inlineCode]`
  /// needs no entry of its own: the styler walks the set bits in ascending order and
  /// applies each. A multi-bit key here is simply never looked up.
  public var styleStyles: [StyleSet: TokenStyle]

  /// Point-size scale by line, keyed by `ElementKind` and then by `depth`.
  ///
  /// Two levels rather than a compound key because `depth` is a fallback dimension: a
  /// heading looks up its level, and anything with no entry for its depth falls back to
  /// the element's depth-`0` entry and then to `1`. `ElementKind/heading` carries its
  /// level in `depth` (there is no `.heading1`…`.heading6`), so all six levels are one
  /// entry shape.
  public var elementSizeScales: [ElementKind: [Int: Double]]

  /// Paragraph geometry by line, keyed by `ElementKind` and then by `depth` — the same
  /// two-level shape, with the same fallback, as ``elementSizeScales``.
  ///
  /// Values are in **characters and multiples of line height, never points**
  /// (``ParagraphMetrics``). The key is `(ElementKind, depth)` because Markdown list
  /// indentation is a function of nesting depth, which is exactly why `LineRecord` carries
  /// `depth` — and because heading level lives in `depth` too, so all six levels are one
  /// entry shape.
  ///
  /// Empty in every built-in theme as of this sortie. The Fountain and Markdown rule sets
  /// are populated later; what exists now is the layer they populate.
  public var elementParagraphMetrics: [ElementKind: [Int: ParagraphMetrics]]

  /// Whether paragraph geometry applies at all.
  ///
  /// REQUIREMENTS.md § Editor 6 requires geometry to be theme-controlled and switchable
  /// off, because changing line height while typing near the top of a long document moves
  /// the scroll position. Switching it off does not disable a code path: it makes
  /// ``paragraphMetrics(for:depth:)`` answer ``ParagraphMetrics/default`` for every
  /// element, which converts through the same arithmetic every other value converts
  /// through and lands on the text system's own default paragraph style.
  public var isGeometryEnabled: Bool

  /// The factor a marker span's foreground alpha is multiplied by. Stage 4, entire.
  ///
  /// **A single scalar, not a `TokenStyle` and not a per-kind value.** There is therefore
  /// no way to express "markers in a different font" or "markers a size smaller" — the
  /// type system refuses. Combined with a marker span carrying the same `SpanKind` and
  /// `StyleSet` as the content it delimits, Architecture §3 stops being a rule someone
  /// has to remember and becomes a property that cannot be violated without changing this
  /// type.
  public var markerOpacity: Double

  /// Creates a theme.
  public init(
    name: String,
    baseFontSize: Double,
    base: TokenStyle,
    kindStyles: [SpanKind: TokenStyle] = [:],
    styleStyles: [StyleSet: TokenStyle] = [:],
    elementSizeScales: [ElementKind: [Int: Double]] = [:],
    elementParagraphMetrics: [ElementKind: [Int: ParagraphMetrics]] = [:],
    isGeometryEnabled: Bool = true,
    markerOpacity: Double = 1
  ) {
    self.name = name
    self.baseFontSize = baseFontSize
    self.base = base
    self.kindStyles = kindStyles
    self.styleStyles = styleStyles
    self.elementSizeScales = elementSizeScales
    self.elementParagraphMetrics = elementParagraphMetrics
    self.isGeometryEnabled = isGeometryEnabled
    self.markerOpacity = markerOpacity
  }

  /// The point-size scale for a line classified `element` at `depth`.
  ///
  /// Total: an element with no table entry, and a depth with no entry under an element
  /// that has one, both resolve to `1`. Geometry is never a reason to fail.
  public func sizeScale(for element: ElementKind, depth: Int) -> Double {
    guard let byDepth = elementSizeScales[element] else { return 1 }
    return byDepth[depth] ?? byDepth[0] ?? 1
  }

  /// The paragraph geometry for a line classified `element` at `depth`.
  ///
  /// Total, on the same terms as ``sizeScale(for:depth:)``: an element with no table
  /// entry, and a depth with no entry under an element that has one, both resolve to
  /// ``ParagraphMetrics/default``. Geometry is never a reason to fail, and an element a
  /// later release adds renders with default geometry until a theme opts into styling it.
  ///
  /// This is the **only** reader of ``elementParagraphMetrics``, which is what makes
  /// ``isGeometryEnabled`` a single guard rather than a condition every call site has to
  /// remember.
  public func paragraphMetrics(for element: ElementKind, depth: Int) -> ParagraphMetrics {
    guard isGeometryEnabled, let byDepth = elementParagraphMetrics[element] else {
      return .default
    }
    return byDepth[depth] ?? byDepth[0] ?? .default
  }

  /// This theme with every table emptied and marker dimming switched off.
  ///
  /// The mechanism behind ``EditorMode/source``. The base survives, so switching modes
  /// keeps the reader's family and size and changes only whether anything is *added* to
  /// them. Because every kind, every style combination, and both roles then resolve
  /// through the same untouched base, "every span in a document resolves to identical
  /// attributes" becomes a testable property — and it is the cheapest available proof
  /// that mode switching has not grown a code path it was not supposed to have.
  public func strippedToSource() -> EscriboTheme {
    EscriboTheme(
      name: "\(name) (source)",
      baseFontSize: baseFontSize,
      base: base,
      kindStyles: [:],
      styleStyles: [:],
      elementSizeScales: [:],
      // Emptied like every other table: raw mode indents nothing. The flag is carried
      // through rather than forced, so stripping and unstripping a theme whose host had
      // geometry switched off round-trips to the same value.
      elementParagraphMetrics: [:],
      isGeometryEnabled: isGeometryEnabled,
      markerOpacity: 1
    )
  }

  // MARK: - Font measurement (0.4.0)

  /// The advance width of **one character**, in points, for `spec`'s resolved face.
  ///
  /// The unit a monospaced measure is counted in: a sixty-character column is sixty of
  /// these. Published in 0.4.0 so that a host laying out a screenplay page — or a Markdown
  /// measure — asks the package that already owns the font chain instead of transcribing
  /// it. Escribir has exactly such a transcription today, and deleting it is the point.
  ///
  /// ## Why this is a measurement and not a constant
  ///
  /// The value is the output of whichever face the D-4 chain resolves to on *this* machine:
  /// Courier Prime if it is installed, then Courier New, then Courier, then the system's
  /// own monospaced face. A test that asserted a point number would be asserting which
  /// font the machine happened to have. Assert the relationships instead — that it is
  /// positive, that it scales linearly with ``FontSpec/pointSize``, and that it is very
  /// nearly `0.6` of the point size for a monospaced spec, which is Courier's ratio and
  /// the same `0.6` the unmeasurable-glyph fallback uses.
  ///
  /// Resolved through ``FontResolver`` — the one chain — rather than measured here, so the
  /// published number is the same number the styler lays out with.
  ///
  /// Total: every branch of the chain ends at a real face, and a face with no glyph for
  /// the probe falls back to a fraction of the point size rather than to zero, because a
  /// zero advance collapses every margin on the page and does so silently.
  public func columnAdvance(for spec: FontSpec) -> Double {
    FontResolver.geometry(of: FontResolver.font(for: spec)).advanceWidth
  }

  /// The width of one **em**, in points, for `spec`'s resolved face.
  ///
  /// An em is historically the width of the letter `m`, and that is literally how this is
  /// measured. The distinction from ``columnAdvance(for:)`` is the whole reason both
  /// exist:
  ///
  /// - For a **monospaced** spec the two agree, because every glyph in a monospaced face
  ///   has the same advance. A caller measuring a screenplay page may use either.
  /// - For a **proportional** spec they differ, and `columnAdvance` becomes meaningless
  ///   while this stays useful: an em is the unit proportional type is spaced in, so a
  ///   Markdown measure expressed in ems survives a change of body face and one expressed
  ///   in character advances does not.
  ///
  /// Same chain, same totality guarantees, same reason not to assert a point constant.
  public func emWidth(for spec: FontSpec) -> Double {
    FontResolver.advanceWidth(of: FontResolver.font(for: spec), for: FontResolver.emProbe)
  }
}
