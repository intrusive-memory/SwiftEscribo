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
    markerOpacity: Double = 1
  ) {
    self.name = name
    self.baseFontSize = baseFontSize
    self.base = base
    self.kindStyles = kindStyles
    self.styleStyles = styleStyles
    self.elementSizeScales = elementSizeScales
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
      markerOpacity: 1
    )
  }
}
