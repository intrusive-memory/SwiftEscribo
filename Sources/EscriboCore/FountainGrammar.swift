/// `!`.
private let exclamationMark: UInt16 = 0x21

/// `#`.
private let numberSign: UInt16 = 0x23

/// `.`.
private let period: UInt16 = 0x2E

/// `:`.
private let colon: UInt16 = 0x3A

/// `<`.
private let lessThan: UInt16 = 0x3C

/// `=`.
private let equalsSign: UInt16 = 0x3D

/// `>`.
private let greaterThan: UInt16 = 0x3E

/// `~`.
private let tilde: UInt16 = 0x7E

/// A space.
private let space: UInt16 = 0x20

/// A horizontal tab.
private let tab: UInt16 = 0x09

/// `O`, and `T` — the two letters a natural transition's `TO:` is spelled with.
private let letterO: UInt16 = 0x4F
private let letterT: UInt16 = 0x54

/// Whether `unit` is a space or a tab. The only two characters this grammar treats as
/// whitespace: a Fountain document's structure is carried by blank lines and capital
/// letters, never by any other space character.
private func isSpaceOrTab(_ unit: UInt16) -> Bool { unit == space || unit == tab }

/// Whether `unit` is an ASCII capital.
private func isASCIIUpper(_ unit: UInt16) -> Bool { unit >= 0x41 && unit <= 0x5A }

/// Whether `unit` is an ASCII lowercase letter.
private func isASCIILower(_ unit: UInt16) -> Bool { unit >= 0x61 && unit <= 0x7A }

/// The scene-heading prefixes, **longest first**.
///
/// Longest-first is not a style choice: `INT./EXT.` starts with `INT.`, so a
/// shortest-first walk would match `INT.` and then reject the line because the unit
/// after it is `/`. Matching the longest prefix that fits removes the need for the
/// follow-character rule to know anything about the slash forms.
///
/// Built from string literals through `String.UTF16View`, which is standard library —
/// `EscriboCore` imports nothing, and nothing here needs it to.
private let scenePrefixes: [[UInt16]] = [
  Array("INT./EXT.".utf16),
  Array("EXT./INT.".utf16),
  Array("INT/EXT.".utf16),
  Array("EXT/INT.".utf16),
  Array("INT./EXT".utf16),
  Array("EXT./INT".utf16),
  Array("INT/EXT".utf16),
  Array("EXT/INT".utf16),
  Array("INT.".utf16),
  Array("EXT.".utf16),
  Array("EST.".utf16),
  Array("I/E.".utf16),
  Array("I/E".utf16),
  Array("INT".utf16),
  Array("EXT".utf16),
  Array("EST".utf16),
]

/// The Fountain grammar's **block** elements: scene headings, action, transitions,
/// centered text, sections, synopses, page breaks, and lyrics.
///
/// Dialogue — character cues, extensions, parentheticals, and the dual-dialogue caret —
/// is deliberately absent. A cue is the one Fountain construct recognized by the line
/// *after* it, so it is the only one that needs lookahead, and lookahead is the single
/// most likely source of "correct on full parse, wrong while typing" (REQUIREMENTS.md
/// § Fountain 4). It is built and tested on its own rather than smuggled in beside eight
/// constructs that do not need it. Until then an ALL-CAPS line is ``ElementKind/action``,
/// which is what it is in Fountain anyway when nothing follows it.
///
/// ## Hand-written, per the charter
///
/// Every decision below is a code-unit comparison against `line.units`. There is no
/// regex in this file and there never will be — the collection's existing Fountain
/// parser is regex-based, emits no source ranges, and replacing it is the reason this
/// package exists (AGENTS.md).
///
/// ## Lookahead: zero
///
/// Every construct here is decided by the line's own text plus the state it begins in.
/// The state carries exactly one bit — ``LineState/followsNonBlankLine`` — because the
/// two *natural* (unforced) constructs, scene headings and transitions, are recognized
/// only at the start of a block. That bit arrives from above, not below, so it costs no
/// lookahead. Sortie 14 raises `lookahead` to one when it adds cues; nothing in this
/// file may quietly start reading `window.line(ahead:)` in the meantime, and the
/// ``LineWindow`` it is handed physically prevents it.
///
/// ## Losslessness (REQUIREMENTS.md Architecture §9)
///
/// Every forced-element marker — `.` for a scene heading, `>` for a transition, `>`/`<`
/// for centered text, `!` for action, `#`, `=`, `~` — is emitted as a
/// ``SpanRole/marker`` span **and** excluded from the line record's `contentRange`. The
/// marker text is therefore recoverable as
/// `record.range.lowerBound..<record.contentRange.lowerBound` against the source, which
/// is what makes `.INT. HOUSE` and `INT. HOUSE` — the same ``ElementKind/sceneHeading``
/// — different records. Nothing is normalized away, so the writer can round-trip a
/// forced element as forced.
///
/// ## Deliberate deviations from Fountain 1.1, all of them stated
///
/// 1. **Markers must begin at the first code unit of the line.** Fountain's block
///    elements are line-initial and Action preserves leading whitespace, so tolerating
///    an indent before a marker would make the two rules contradict each other. An
///    indented `INT. HOUSE` is action.
/// 2. **A whitespace-only line is blank**, and therefore opens a block. Fountain's
///    "two trailing spaces preserve the line" convention is a *writing* affordance the
///    scanner does not need to honor to classify the line, and a writer's stray space
///    should not silently demote the scene heading below it to action.
/// 3. **A natural scene heading requires only a preceding blank line, not a following
///    one**, and a natural transition likewise. The spec's "…and has a blank line
///    following it" is a one-line lookahead this sortie does not own. The consequence is
///    permissive, never restrictive: a line the spec calls action can be classified as a
///    scene heading, and no line the spec calls a scene heading is missed.
/// 4. **Scene numbers (`#1#` at the end of a scene heading) are not extracted.** They
///    remain inside the content range, losslessly, for a later sortie to split out.
struct FountainGrammar: LineGrammar {

  var lookahead: Int { 0 }

  func scanLine(_ window: LineWindow, state: LineState) -> LineScan {
    let line = window.current

    // Order matters in exactly two places, and both are load-bearing:
    //
    //   * page break before synopsis — `===` also begins with `=`;
    //   * centered before transition — `>CENTERED<` also begins with `>`.
    //
    // Everything else is decided by a distinct first code unit and could be reordered
    // without changing a single classification.
    let scan =
      isBlank(line.units)
      ? blank(line)
      : pageBreak(line)
        ?? section(line)
        ?? synopsis(line)
        ?? lyrics(line)
        ?? forcedAction(line)
        ?? forcedSceneHeading(line)
        ?? centered(line)
        ?? forcedTransition(line)
        ?? naturalSceneHeading(line, state: state)
        ?? naturalTransition(line, state: state)
        ?? action(line)

    return withState(scan, after: line, state: state)
  }

  // MARK: - The one bit of state

  /// Rewrites `scan`'s end state so the next line knows whether this one was blank.
  ///
  /// This is the **only** place in the file that decides an end state, which is why the
  /// per-element methods all return a placeholder: a construct that forgot to carry the
  /// bit would converge one line early, and centralizing it means no construct can
  /// forget. The bit is carried by mutating the incoming state rather than by building a
  /// fresh one, so a field a later sortie adds — the boneyard flag, the in-dialogue-block
  /// flag — survives a line this grammar already knows how to scan. Dropping such a field
  /// is the one defect class the incremental design exists to prevent.
  private func withState(_ scan: LineScan, after line: GrammarLine, state: LineState) -> LineScan {
    var scan = scan
    var next = state
    next.followsNonBlankLine = !isBlank(line.units)
    scan.endState = next
    return scan
  }

  /// Whether the line is empty or contains nothing but spaces and tabs.
  private func isBlank(_ units: [UInt16]) -> Bool {
    for unit in units where !isSpaceOrTab(unit) { return false }
    return true
  }

  // MARK: - Blank

  private func blank(_ line: GrammarLine) -> LineScan {
    LineScan(
      // A whitespace-only line still has code units, and they still have to be tiled.
      spans: line.contentRange.isEmpty ? [] : [EscriboSpan(range: line.contentRange, kind: .text)],
      element: .blank,
      contentRange: line.contentRange.lowerBound..<line.contentRange.lowerBound,
      endState: LineState()
    )
  }

  // MARK: - Page break

  /// `===` or longer, with nothing after it but whitespace.
  ///
  /// Three is the floor and it is the entire difference between this and a synopsis:
  /// `==` falls through to ``synopsis(_:)`` and is a synopsis whose text is `=`. A page
  /// break is pure delimiter, so — like a closing code fence — its content range is the
  /// empty range where content would have begun.
  private func pageBreak(_ line: GrammarLine) -> LineScan? {
    let units = line.units
    guard units.first == equalsSign else { return nil }

    var runEnd = 0
    while runEnd < units.count, units[runEnd] == equalsSign {
      runEnd += 1
    }
    guard runEnd >= 3 else { return nil }
    for offset in runEnd..<units.count where !isSpaceOrTab(units[offset]) { return nil }

    let base = line.contentRange.lowerBound
    return LineScan(
      spans: [EscriboSpan(range: base..<(base + runEnd), kind: .pageBreak, role: .marker)],
      element: .pageBreak,
      contentRange: (base + runEnd)..<(base + runEnd),
      endState: LineState()
    )
  }

  // MARK: - Section

  /// `#`, `##`, … with the level in ``LineScan/depth``.
  ///
  /// The level goes in `depth` for the same reason a Markdown heading's does: paragraph
  /// geometry keyed by `(ElementKind, depth)` covers every level with one entry shape.
  /// Fountain places no ceiling on section depth, so neither does this — six is
  /// CommonMark's number, not Fountain's.
  private func section(_ line: GrammarLine) -> LineScan? {
    let units = line.units
    guard units.first == numberSign else { return nil }

    var runEnd = 0
    while runEnd < units.count, units[runEnd] == numberSign {
      runEnd += 1
    }
    return markedLine(line, markerEnd: runEnd, kind: .section, element: .section, depth: runEnd)
  }

  // MARK: - Synopsis

  /// `= text`. Only the *first* `=` is the marker, which is why `==` is a synopsis whose
  /// text is `=` rather than a two-character marker with nothing after it.
  private func synopsis(_ line: GrammarLine) -> LineScan? {
    guard line.units.first == equalsSign else { return nil }
    return markedLine(line, markerEnd: 1, kind: .synopsis, element: .synopsis)
  }

  // MARK: - Lyrics

  /// `~Willy Wonka`.
  private func lyrics(_ line: GrammarLine) -> LineScan? {
    guard line.units.first == tilde else { return nil }
    return markedLine(line, markerEnd: 1, kind: .lyrics, element: .lyrics)
  }

  // MARK: - Forced action

  /// `!Forced action`.
  ///
  /// The only marked element whose marker does **not** swallow the whitespace after it,
  /// and the only one whose content is not right-trimmed: action is the one Fountain
  /// element whose internal whitespace is meaningful, so `!  spaced   ` keeps every space
  /// it was written with inside its content range.
  private func forcedAction(_ line: GrammarLine) -> LineScan? {
    let units = line.units
    guard units.first == exclamationMark else { return nil }

    let base = line.contentRange.lowerBound
    var spans = [EscriboSpan(range: base..<(base + 1), kind: .action, role: .marker)]
    if units.count > 1 {
      spans.append(EscriboSpan(range: (base + 1)..<line.contentRange.upperBound, kind: .action))
    }
    return LineScan(
      spans: spans,
      element: .action,
      contentRange: (base + 1)..<line.contentRange.upperBound,
      endState: LineState()
    )
  }

  // MARK: - Scene headings

  /// `.INT. HOUSE` — a scene heading forced by a leading period.
  ///
  /// A single period followed by something that is neither another period nor
  /// whitespace. The period rule is the spec's, and its motivation is concrete: an
  /// action line may legitimately open with an ellipsis, and `...and then` must not
  /// become a scene heading. `. ` is likewise action, because a forced heading's period
  /// abuts its text.
  private func forcedSceneHeading(_ line: GrammarLine) -> LineScan? {
    let units = line.units
    guard units.first == period, units.count >= 2 else { return nil }
    guard units[1] != period, !isSpaceOrTab(units[1]) else { return nil }
    return markedLine(
      line, markerEnd: 1, kind: .sceneHeading, element: .sceneHeading, swallowWhitespace: false)
  }

  /// `INT. HOUSE - DAY` — a scene heading recognized by its prefix at the start of a
  /// block.
  ///
  /// Unmarked, so its record is distinguishable from the forced form by exactly one
  /// thing: its content range starts where its line starts, and the forced form's starts
  /// one code unit later. That difference *is* the preserved marker — REQUIREMENTS.md
  /// Architecture §9 asks that no lexical information the writer needs be discarded, and
  /// this is that information, kept where the writer can read it back off the source.
  private func naturalSceneHeading(_ line: GrammarLine, state: LineState) -> LineScan? {
    guard !state.followsNonBlankLine else { return nil }
    guard matchesScenePrefix(line.units) else { return nil }
    return markedLine(line, markerEnd: 0, kind: .sceneHeading, element: .sceneHeading)
  }

  /// Whether `units` opens with a scene-heading prefix that is properly terminated.
  ///
  /// The termination rule is what keeps `INTERIOR DECORATOR` out: `INT` matches, but the
  /// unit after it is `E`, and a prefix must be followed by end of line, a period, or
  /// whitespace. Case-sensitive on purpose — a Fountain scene heading is uppercase, and
  /// lowercasing the comparison would classify `interior thoughts` as a scene heading.
  private func matchesScenePrefix(_ units: [UInt16]) -> Bool {
    for prefix in scenePrefixes {
      guard units.count >= prefix.count else { continue }
      var matched = true
      for offset in 0..<prefix.count where units[offset] != prefix[offset] {
        matched = false
        break
      }
      guard matched else { continue }
      if units.count == prefix.count { return true }
      let following = units[prefix.count]
      if following == period || isSpaceOrTab(following) { return true }
    }
    return false
  }

  // MARK: - Centered text and transitions

  /// `>CENTERED<` — greater-than and less-than, both markers, content between them.
  ///
  /// Checked before ``forcedTransition(_:)`` because both open with `>`; the closing `<`
  /// is the whole difference, and it is why these are two element kinds rather than one
  /// with a flag.
  private func centered(_ line: GrammarLine) -> LineScan? {
    let units = line.units
    guard units.first == greaterThan else { return nil }

    var lastVisible = units.count
    while lastVisible > 0, isSpaceOrTab(units[lastVisible - 1]) {
      lastVisible -= 1
    }
    guard lastVisible >= 2, units[lastVisible - 1] == lessThan else { return nil }

    var contentStart = 1
    while contentStart < lastVisible - 1, isSpaceOrTab(units[contentStart]) {
      contentStart += 1
    }
    var contentEnd = lastVisible - 1
    while contentEnd > contentStart, isSpaceOrTab(units[contentEnd - 1]) {
      contentEnd -= 1
    }

    let base = line.contentRange.lowerBound
    var spans = [EscriboSpan(range: base..<(base + contentStart), kind: .centered, role: .marker)]
    if contentEnd > contentStart {
      spans.append(
        EscriboSpan(range: (base + contentStart)..<(base + contentEnd), kind: .centered))
    }
    // The trailing marker swallows the whitespace on both sides of the `<` and runs to
    // the end of the line's content, so the tail stays centered-colored rather than
    // falling through to `.text`.
    spans.append(
      EscriboSpan(
        range: (base + contentEnd)..<line.contentRange.upperBound, kind: .centered, role: .marker))

    return LineScan(
      spans: spans,
      element: .centered,
      contentRange: (base + contentStart)..<(base + contentEnd),
      endState: LineState()
    )
  }

  /// `> CUT TO:` — a transition forced by a leading greater-than.
  private func forcedTransition(_ line: GrammarLine) -> LineScan? {
    guard line.units.first == greaterThan else { return nil }
    return markedLine(line, markerEnd: 1, kind: .transition, element: .transition)
  }

  /// `CUT TO:` — an uppercase line ending in `TO:` at the start of a block.
  private func naturalTransition(_ line: GrammarLine, state: LineState) -> LineScan? {
    guard !state.followsNonBlankLine else { return nil }
    let units = line.units

    var end = units.count
    while end > 0, isSpaceOrTab(units[end - 1]) {
      end -= 1
    }
    guard end >= 3 else { return nil }
    guard units[end - 1] == colon, units[end - 2] == letterO, units[end - 3] == letterT else {
      return nil
    }
    guard isUppercase(units, upTo: end) else { return nil }

    return markedLine(line, markerEnd: 0, kind: .transition, element: .transition)
  }

  /// Whether `units[0..<end]` is uppercase: at least one ASCII capital and no ASCII
  /// lowercase letter.
  ///
  /// Only ASCII case is consulted. A case-folding table would be a Unicode dependency
  /// this module does not have and does not want, and a screenplay's transitions are
  /// ASCII in every document this parser was written for. A line with no cased ASCII at
  /// all is not uppercase — otherwise `>>> TO:` would be a transition.
  private func isUppercase(_ units: [UInt16], upTo end: Int) -> Bool {
    var sawUpper = false
    for offset in 0..<end {
      if isASCIILower(units[offset]) { return false }
      if isASCIIUpper(units[offset]) { sawUpper = true }
    }
    return sawUpper
  }

  // MARK: - Action

  /// Everything else.
  ///
  /// Its content range is the **whole** line minus the terminator, leading whitespace
  /// included: Fountain preserves indentation inside action, so trimming it here would
  /// make the writer lossy in the one element where whitespace is what the writer meant.
  private func action(_ line: GrammarLine) -> LineScan {
    LineScan(
      spans: line.contentRange.isEmpty
        ? [] : [EscriboSpan(range: line.contentRange, kind: .action)],
      element: .action,
      contentRange: line.contentRange,
      endState: LineState()
    )
  }

  // MARK: - Shared span layout

  /// The layout every marked block element shares: a marker span, then a content span,
  /// with the same ``SpanKind`` and ``StyleSet`` on both and only the ``SpanRole``
  /// differing.
  ///
  /// That sameness is the whole marker/content design (REQUIREMENTS.md Architecture §2):
  /// the styler resolves attributes once from kind and style, then multiplies the
  /// foreground alpha when the role is a marker. "The period shows, dimmed, while the
  /// slug line renders as a slug line" is then a property of the data rather than a case
  /// in the styler.
  ///
  /// - Parameters:
  ///   - markerEnd: How many code units of the line are marker. Zero for the natural
  ///     forms, which have no marker at all and therefore emit no marker span.
  ///   - swallowWhitespace: Whether the marker absorbs the whitespace between it and the
  ///     text, so the content span begins at the first character a reader sees.
  private func markedLine(
    _ line: GrammarLine,
    markerEnd: Int,
    kind: SpanKind,
    element: ElementKind,
    depth: Int = 0,
    swallowWhitespace: Bool = true
  ) -> LineScan {
    let units = line.units
    let base = line.contentRange.lowerBound

    var contentStart = markerEnd
    if swallowWhitespace {
      while contentStart < units.count, isSpaceOrTab(units[contentStart]) {
        contentStart += 1
      }
    }
    var contentEnd = units.count
    while contentEnd > contentStart, isSpaceOrTab(units[contentEnd - 1]) {
      contentEnd -= 1
    }

    var spans: [EscriboSpan] = []
    if contentStart > 0 {
      spans.append(EscriboSpan(range: base..<(base + contentStart), kind: kind, role: .marker))
    }
    if contentEnd > contentStart {
      spans.append(EscriboSpan(range: (base + contentStart)..<(base + contentEnd), kind: kind))
    }

    return LineScan(
      spans: spans,
      element: element,
      contentRange: (base + contentStart)..<(base + contentEnd),
      depth: depth,
      endState: LineState()
    )
  }
}
