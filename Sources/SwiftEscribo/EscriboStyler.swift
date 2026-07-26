import EscriboCore

#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

/// The cache key REQUIREMENTS.md § Theme specifies: `(SpanKind, StyleSet, SpanRole)`.
///
/// A named struct rather than a tuple because Swift tuples are not `Hashable`. `SpanRole`
/// is `Hashable, Sendable` in the core precisely so this composes with no adapter.
struct StyleKey: Hashable, Sendable {

  /// What the run is.
  var kind: SpanKind

  /// The union of emphasis covering the run.
  var style: StyleSet

  /// Content or marker.
  var role: SpanRole
}

/// The key of the *line* a span sits on: `(ElementKind, depth)`.
///
/// Point size is a property of the line, never of the span (see ``EscriboStyler``), so
/// the style cache is partitioned by this and keyed by ``StyleKey`` within each
/// partition. Documents contain a handful of distinct line keys and a few dozen style
/// keys, so both levels stay in the tens.
struct LineStyleKey: Hashable, Sendable {

  /// The line's classification.
  var element: ElementKind

  /// The line's nesting or heading level.
  var depth: Int
}

/// Resolves spans to attributes, and caches the answer.
///
/// ## Point size comes from the line, not the span
///
/// This is the single most easily broken rule in the styling layer, so it is the shape of
/// the API rather than a comment inside it: every entry point takes the span's
/// **`ElementKind` and `depth`** alongside the span, and there is no entry point that
/// does not.
///
/// The reason is concrete. Architecture §3 requires point size to vary per line and never
/// within a line — resizing a marker makes text jitter while typing. But the Markdown
/// grammar emits a heading's *leading indent* as a `SpanKind.text` span, not as part of
/// the heading's marker span. A styler that scaled size off `SpanKind` would therefore
/// render the indent of `  ## Heading` at body size and the rest of the line at heading
/// size — within-line uniformity broken by the very construct the scale exists for.
/// Taking size from `LineRecord.element` and `LineRecord.depth` makes every span on a
/// line the same size no matter what kind the grammar gave it.
///
/// ## Four triggers, one invalidation path
///
/// ``environment`` holds all four things that can change an answer: theme, mode,
/// appearance, and font metrics. Assigning any of them replaces the whole value, the
/// whole value is compared, and one `invalidate()` runs. There is no per-trigger
/// invalidation to forget to call, and adding a fifth field to the environment wires it
/// up automatically.
///
/// ## Unknown kinds
///
/// A kind with no table entry contributes nothing and resolves to the base style. There
/// is no `default:` that traps, because a theme written against 1.0 must keep working
/// when 1.1 adds a Fountain construct — it renders the new kind as plain text until the
/// theme opts in.
///
/// A reference type: it is a cache, shared by the coordinator across every span of a
/// scan, and copying it per lookup would defeat it. Synchronous and single-threaded,
/// like the scanner it consumes.
final class EscriboStyler {

  /// Everything outside the document that decides how a span looks.
  ///
  /// Assigning a *different* value empties the cache. Assigning an equal one does not,
  /// which is what lets a host push its full configuration on every layout pass without
  /// throwing away work.
  var environment: EditorStyleEnvironment {
    didSet {
      guard environment != oldValue else { return }
      invalidate()
    }
  }

  /// The theme composition actually reads: ``environment``'s theme with its mode folded
  /// in. Recomputed once per invalidation rather than once per span.
  private var activeTheme: EscriboTheme

  /// Resolved styles, partitioned by line key and keyed by `(SpanKind, StyleSet, SpanRole)`.
  private var styles: [LineStyleKey: [StyleKey: ResolvedStyle]] = [:]

  /// Paragraph styles, keyed by the same `(ElementKind, depth)` line key the style cache is
  /// partitioned by — because that is the whole of what geometry depends on.
  ///
  /// Emptied by ``invalidate()`` and by nothing else. A geometry cache with its own
  /// clearing rule would be a second invalidation path, and the point of the environment
  /// being one `Equatable` value is that there is exactly one.
  private var paragraphStyles: [LineStyleKey: NSParagraphStyle] = [:]

  /// The shared font cache. `internal` so ``ResolvedStyle/attributes(resolver:)`` can be
  /// called directly by the coordinator with the same resolver every span used.
  private(set) var fontResolver = FontResolver()

  /// How many lookups were answered from the cache. Test instrumentation, and the only
  /// way to assert "a repeated lookup with no trigger is a hit" without timing it.
  private(set) var cacheHits = 0

  /// How many lookups had to compose.
  private(set) var cacheMisses = 0

  /// Creates a styler over `environment`.
  init(environment: EditorStyleEnvironment) {
    self.environment = environment
    self.activeTheme = environment.resolvedTheme
  }

  /// Creates a styler over `theme` with default mode, appearance, and metrics.
  convenience init(theme: EscriboTheme) {
    self.init(environment: EditorStyleEnvironment(theme: theme))
  }

  // MARK: - Cache

  /// How many resolved styles are currently cached, across every line partition.
  var cachedStyleCount: Int {
    styles.values.reduce(0) { $0 + $1.count }
  }

  /// How many paragraph styles are currently cached.
  var cachedParagraphStyleCount: Int { paragraphStyles.count }

  /// Whether nothing is cached.
  var isCacheEmpty: Bool {
    styles.isEmpty
      && paragraphStyles.isEmpty
      && fontResolver.cachedFontCount == 0
      && fontResolver.cachedGeometryCount == 0
  }

  /// Empties every cache. **The only invalidation path.**
  ///
  /// Fonts go too, not only styles: a font-metric change moves the point size, which is
  /// part of a ``FontSpec``, and a font cache that outlived a size change would be a
  /// second store to reason about for no gain. Paragraph styles go for the same reason —
  /// they are point values converted against a face at a size, so every trigger that can
  /// move the size can move a margin.
  func invalidate() {
    activeTheme = environment.resolvedTheme
    styles.removeAll(keepingCapacity: true)
    paragraphStyles.removeAll(keepingCapacity: true)
    fontResolver.invalidate()
  }

  /// Resets the hit and miss counters without touching the cache.
  func resetStatistics() {
    cacheHits = 0
    cacheMisses = 0
  }

  // MARK: - Resolution

  /// The resolved style for `span`, sitting on a line classified `element` at `depth`.
  ///
  /// - Parameters:
  ///   - span: The span to style. Only its `kind`, `style`, and `role` are read; its
  ///     range is the caller's business.
  ///   - element: The **line's** classification — the source of point size.
  ///   - depth: The line's heading level or nesting depth.
  func style(for span: EscriboSpan, element: ElementKind, depth: Int) -> ResolvedStyle {
    style(
      kind: span.kind, style: span.style, role: span.role,
      element: element, depth: depth)
  }

  /// The resolved style for `span`, whose line is described by `line`.
  ///
  /// The entry point the coordinator uses: `LineRecord` carries both halves of the line
  /// key, so a caller holding a scan result cannot get the size wrong.
  func style(for span: EscriboSpan, on line: LineRecord) -> ResolvedStyle {
    style(for: span, element: line.element, depth: line.depth)
  }

  /// The resolved style for an explicit `(kind, style, role)` on a given line.
  func style(
    kind: SpanKind, style spanStyle: StyleSet, role: SpanRole,
    element: ElementKind, depth: Int
  ) -> ResolvedStyle {
    let lineKey = LineStyleKey(element: element, depth: depth)
    let styleKey = StyleKey(kind: kind, style: spanStyle, role: role)
    if let cached = styles[lineKey]?[styleKey] {
      cacheHits += 1
      return cached
    }
    cacheMisses += 1
    let composed = compose(styleKey, on: lineKey)
    styles[lineKey, default: [:]][styleKey] = composed
    return composed
  }

  /// The base style for a line — what an unrecognized kind with no emphasis resolves to.
  ///
  /// Not cached and not counted: it exists so a caller (and a test) can name the fallback
  /// without inventing a kind that happens to be absent from the theme.
  func baseStyle(element: ElementKind, depth: Int) -> ResolvedStyle {
    compose(
      StyleKey(kind: .text, style: [], role: .content),
      on: LineStyleKey(element: element, depth: depth),
      skippingKindStage: true)
  }

  /// Text-storage attributes for `span` on `line`.
  func attributes(for span: EscriboSpan, on line: LineRecord) -> [NSAttributedString.Key: Any] {
    let resolved = style(for: span, on: line)
    return resolved.attributes(resolver: &fontResolver)
  }

  /// Text-storage attributes for an already-resolved style.
  func attributes(for resolved: ResolvedStyle) -> [NSAttributedString.Key: Any] {
    resolved.attributes(resolver: &fontResolver)
  }

  // MARK: - Paragraph geometry

  /// The paragraph style for a line classified `element` at `depth`.
  ///
  /// Where the character counts a theme declares become points. The conversion measures
  /// the **line's own base font** — the family the theme's base asks for, at the size this
  /// line resolves to after font metrics and the element's size scale. Measuring anything
  /// else would decouple a margin from the text it indents: a heading set 1.8× larger with
  /// margins measured at body size would sit at the wrong column, and the error would grow
  /// with the scale.
  ///
  /// It is the line's **base** style specifically — the kind and emphasis stages are not
  /// run. Bold and italic can change advance width even within a monospaced family, and a
  /// paragraph's left margin cannot depend on whether some word inside it happened to be
  /// emphasised; a theme that sets a trait on its *base* has set it for every line, so
  /// that one is legitimately part of the measurement.
  func paragraphStyle(element: ElementKind, depth: Int) -> NSParagraphStyle {
    let key = LineStyleKey(element: element, depth: depth)
    if let cached = paragraphStyles[key] { return cached }
    let metrics = activeTheme.paragraphMetrics(for: element, depth: depth)
    let geometry = fontResolver.geometry(for: baseStyle(element: element, depth: depth).font)
    let style = metrics.paragraphStyle(in: geometry)
    paragraphStyles[key] = style
    return style
  }

  /// The paragraph style for `line`.
  ///
  /// The entry point the coordinator uses: a `LineRecord` carries both halves of the key,
  /// so a caller holding a scan result cannot look up the geometry of a line it is not
  /// applying it to.
  func paragraphStyle(for line: LineRecord) -> NSParagraphStyle {
    paragraphStyle(element: line.element, depth: line.depth)
  }

  /// A paragraph style for every line record, over that record's full range.
  ///
  /// One run per line rather than per coalesced group of identical lines: runs are consumed
  /// by a rescan of a handful of lines, and merging them would mean comparing paragraph
  /// styles for equality on a path where cached identical lines already share one object.
  ///
  /// **Apply these additively.** Paragraph styles are per-line and span attributes are
  /// per-span, so a pass that replaces attributes over span ranges will drop a paragraph
  /// style that was set first. Add the paragraph attribute over these ranges *after* the
  /// span pass, or set it as part of the span attributes — do not set it before and assume
  /// it survives.
  func paragraphStyleRuns(for lines: [LineRecord]) -> [ParagraphStyleRun] {
    lines.map { ParagraphStyleRun(range: $0.range, style: paragraphStyle(for: $0)) }
  }

  // MARK: - Composition

  /// The normative composition: base → kind → style → role.
  ///
  /// Within a stage, **traits union and everything else overrides**. That asymmetry is
  /// the difference between a code span inside a bold heading rendering bold-mono and
  /// rendering mono-only, and it is not something two implementers guess the same way.
  ///
  /// The role stage multiplies the foreground alpha and does nothing else — not the
  /// background, not the traits, and above all not the size.
  private func compose(
    _ key: StyleKey, on line: LineStyleKey, skippingKindStage: Bool = false
  ) -> ResolvedStyle {
    let theme = activeTheme

    // Stage 1 — base. Size is a function of the LINE, never of the span's kind.
    let pointSize =
      theme.baseFontSize
      * environment.metrics.pointSizeScale
      * theme.sizeScale(for: line.element, depth: line.depth)

    var family = theme.base.family ?? .monospaced
    var traits = theme.base.traits
    var foreground = theme.base.foreground ?? .black
    var background = theme.base.background
    var underline = theme.base.underline ?? false
    var strikethrough = theme.base.strikethrough ?? false

    func apply(_ token: TokenStyle) {
      traits.formUnion(token.traits)
      if let value = token.family { family = value }
      if let value = token.foreground { foreground = value }
      if let value = token.background { background = value }
      if let value = token.underline { underline = value }
      if let value = token.strikethrough { strikethrough = value }
    }

    // Stage 2 — kind. An absent entry contributes nothing: unknown kinds fall back to
    // base rather than trapping.
    if !skippingKindStage, let kindStyle = theme.kindStyles[key.kind] {
      apply(kindStyle)
    }

    // Stage 3 — style flags, additively, in ascending bit order so composition is
    // deterministic regardless of how the set was built. A flag with no table entry
    // contributes nothing, which is how a `StyleSet` member added in a later release
    // degrades rather than breaks.
    if !key.style.isEmpty {
      for bit in 0..<StyleSet.RawValue.bitWidth {
        let flag = StyleSet(rawValue: 1 << UInt16(bit))
        guard key.style.contains(flag), let flagStyle = theme.styleStyles[flag] else { continue }
        apply(flagStyle)
      }
    }

    // Stage 4 — role. Alpha on the foreground, and nothing else.
    if key.role == .marker {
      foreground = foreground.withAlphaMultiplied(by: theme.markerOpacity)
    }

    return ResolvedStyle(
      font: FontSpec(family: family, traits: traits, pointSize: pointSize),
      foreground: foreground,
      background: background,
      underline: underline,
      strikethrough: strikethrough
    )
  }
}
