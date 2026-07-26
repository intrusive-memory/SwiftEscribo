/// `!`.
private let exclamationMark: UInt16 = 0x21

/// `#`.
private let numberSign: UInt16 = 0x23

/// `(` and `)` — a cue extension's and a parenthetical's delimiters.
private let leftParenthesis: UInt16 = 0x28
private let rightParenthesis: UInt16 = 0x29

/// `@` — the character-cue forcing marker.
private let atSign: UInt16 = 0x40

/// `^` — the dual-dialogue marker.
private let caret: UInt16 = 0x5E

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

/// `[` and `]` — a note's delimiters, doubled: `[[` and `]]`.
private let leftBracket: UInt16 = 0x5B
private let rightBracket: UInt16 = 0x5D

/// `/` and `*` — the boneyard's delimiters, paired: `/*` and `*/`.
private let solidus: UInt16 = 0x2F
private let asterisk: UInt16 = 0x2A

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

/// The Fountain grammar: scene headings, action, transitions, centered text, sections,
/// synopses, page breaks, lyrics, and the whole dialogue block — character cues with
/// extensions, parentheticals, dialogue, and dual dialogue.
///
/// ## Hand-written, per the charter
///
/// Every decision below is a code-unit comparison against `line.units`. There is no
/// regex in this file and there never will be — the collection's existing Fountain
/// parser is regex-based, emits no source ranges, and replacing it is the reason this
/// package exists (AGENTS.md).
///
/// ## Lookahead: one, and exactly one
///
/// One construct in Fountain is recognized by the line *after* it: a natural character
/// cue is an ALL-CAPS line at a block boundary **whose following line is non-blank**
/// (REQUIREMENTS.md § Fountain 4). Nothing else here reads ``LineWindow/line(ahead:)``,
/// and nothing else may: the declared number sizes the window the engine hands over, so a
/// grammar that wanted two lines of lookahead would silently get `nil` for the second
/// rather than a wrong answer, and would have to raise the declaration to get it.
///
/// The declaration is load-bearing in both directions and the backward one is the one
/// that gets forgotten. ``LineGrammar/backwardExtent`` defaults to `max(1, lookahead)`, so
/// raising `lookahead` to one is also what makes an edit rescan from the line *above* it —
/// which is the only reason typing a word under `BOB` can promote `BOB` from action to a
/// cue. Nothing about that edit points at the line above it.
///
/// The rest of the multi-line story is state, not lookahead:
/// ``LineState/followsNonBlankLine`` says a block boundary is above this line, and
/// ``LineState/inDialogueBlock`` says a cue is. Both arrive from above, where they cost
/// nothing.
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
///    following it" is a one-line lookahead, and this grammar now has one — so this is a
///    *retained* deviation rather than an unavailable feature, and the reason it is
///    retained is stated so the next reader does not "fix" it by accident:
///
///    - It would make a one-line document `INT. HOUSE` action, because a line with no
///      following line has no following *blank* line either. Sixteen slug-line spellings
///      are asserted in the suite as one-line documents, and a rule that reclassifies all
///      of them buys nothing a screenwriter can see.
///    - It collides with the cue rule at exactly the wrong place. `INT. HOUSE` followed by
///      a non-blank line would stop being a scene heading and become a *cue candidate*,
///      since it is ALL-CAPS at a block boundary with a non-blank line under it. Trading a
///      slug line for a character named `INT. HOUSE` is a worse answer than the one the
///      deviation gives.
///
///    The consequence stays what it was: permissive, never restrictive. A line the spec
///    calls action can be classified as a scene heading, and no line the spec calls a
///    scene heading is missed.
/// 4. **Scene numbers (`#1#` at the end of a scene heading) are not extracted.** They
///    remain inside the content range, losslessly, for a later sortie to split out.
/// 5. **A natural character cue must be uppercase over its whole line**, extension
///    included — `BOB (V.O.)` is a cue and `BOB (cont'd)` is action. That is the spec's
///    rule ("a line entirely in uppercase") rather than the looser one some parsers use,
///    and it is kept strict because the loose form promotes `THE MAN (who is not a man)`
///    to a cue. `@` forces anything the strict rule declines.
/// 6. **A parenthetical may be indented.** Deviation 1 keeps markers at the first code
///    unit because action preserves its leading whitespace — but no whitespace-preserving
///    element can occur inside a dialogue block, where every non-blank line is dialogue,
///    so the reason does not apply and real screenplays indent parentheticals.
/// 7. **Notes and boneyard do not nest, in themselves or in each other.** The first `]]`
///    closes a note and the first `*/` closes a boneyard, whichever came first opens the
///    region, and inside a region nothing is syntax — a `/*` inside a note is two
///    characters of note text and a `[[` inside a boneyard is two characters of struck-out
///    text. Fountain has no nesting rule for either construct, and a bracket-matching walk
///    would make `[[ the array is a[[i]] ]]` behave differently from every other Fountain
///    parser in the org.
/// 8. **A region affects a line's classification only when it was open at the start of
///    the line, or when it is all the line has on it.** `Bob waits. /* cut */` is action
///    with boneyard spans on it; a line inside an open boneyard is
///    ``ElementKind/boneyard``; and `[[a note]]` alone on a line is ``ElementKind/note``.
///    A line grammar gives one line one classification, and splitting a line that closes a
///    boneyard and then carries a slug line into two would need a second element axis on
///    ``LineRecord``, which is public API and not a scanner detail. Nothing is lost either
///    way: every code unit is spanned and the source stays authoritative.
/// 9. **An unterminated note or boneyard runs to the end of the document**, and that is
///    the specified behavior rather than a fallback — the scan path has no error path
///    (REQUIREMENTS.md § Core API, totality). A blank line does **not** close either
///    region: Fountain gives neither construct a blank-line rule, and inventing one would
///    make `/*` mean something different from `*/` being absent.
/// 10. **The title page is a leading region and may begin only on line 0.** It runs to the
///    first blank line. Keys are **arbitrary** — `verbsCovered:` and `Abstract:` are real
///    keys in this org's documents (REQUIREMENTS.md § Fountain 2) — and are preserved
///    verbatim, as a ``SpanKind/titlePageKey`` span covering the key text exactly, with
///    nothing trimmed, folded, or normalized.
/// 11. **A line that could be a title-page key needs corroboration to open one.** `Key:`
///    with nothing after it is a title page only if the line below it is an indented
///    continuation or another key; otherwise a document opening on the transition `CUT TO:`
///    would be a title page whose key is `CUT TO`. That corroboration is the *same* one
///    line of lookahead the cue rule already declared (see above), not a second one.
struct FountainGrammar: LineGrammar {

  var lookahead: Int { 1 }

  /// The ``LineState/openConstruct`` tag meaning "a `[[` note is open".
  ///
  /// Its meaning belongs to this grammar; the scanner only ever compares it. The value is
  /// deliberately **not** `1`, which is ``MarkdownGrammar/fenceTag`` — the two grammars own
  /// disjoint documents today, but a `fountain` fence inside a Markdown document puts one
  /// grammar's state inside the other's (REQUIREMENTS.md § Fountain-in-Markdown), and a
  /// tag that means two things is exactly the ambiguity that would be discovered late.
  static let noteTag: UInt16 = 0x10

  /// The ``LineState/openConstruct`` tag meaning "a `/*` boneyard is open".
  static let boneyardTag: UInt16 = 0x11

  func scanLine(_ window: LineWindow, state: LineState) -> LineScan {
    let line = window.current

    // The title page comes first and answers for the whole line, because inside it no
    // other Fountain element exists: `INT. HOUSE` under `Title:` is a continuation of a
    // title-page value, not a slug line. It can only be open — or opened — here, so this
    // costs one comparison on every other line of every screenplay.
    if state.titlePage == .open || (state.titlePage == .documentStart && opensTitlePage(window)) {
      if isBlank(line.units) {
        // The blank line ends the region and is not part of it.
        return withState(blank(line), after: line, state: state, region: 0, titlePage: .closed)
      }
      return withState(titlePageLine(line), after: line, state: state, region: 0, titlePage: .open)
    }

    // Notes and boneyard next, and before any block rule, because they are the only
    // constructs here that can be open *across* lines: what a line means depends on
    // whether it began inside one. The walk is a single left-to-right pass that carries
    // the region open at the start of the line and reports the one open at the end of it
    // — the state a later line will be scanned against.
    let regions = scanRegions(line, incoming: state.openConstruct)

    // A line with nothing on it but region text is that region. Everything else keeps its
    // ordinary classification, with the region spans laid over the top (deviation 8).
    if regions.coversWholeLine {
      return withState(
        regionLine(line, regions), after: line, state: state, region: regions.endRegion,
        titlePage: .closed)
    }

    // Order matters in exactly four places, and all four are load-bearing:
    //
    //   * page break before synopsis — `===` also begins with `=`;
    //   * centered before transition — `>CENTERED<` also begins with `>`;
    //   * scene headings and transitions before cues — `INT. HOUSE` and `CUT TO:` with a
    //     line of action under them are ALL-CAPS at a block boundary, which is a cue's
    //     shape too, and the more specific rule has to be asked first;
    //   * everything before `dialogue` — a dialogue block is ended by any element that is
    //     not dialogue-shaped, so a `~lyric`, a `!forced action`, or a `# section` inside
    //     one is that element and not a line of speech. Fountain's own lyrics example sits
    //     inside a dialogue block, so this is the spec's order, not a convenience.
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
        ?? forcedCharacter(line)
        ?? naturalSceneHeading(line, state: state)
        ?? naturalTransition(line, state: state)
        ?? naturalCharacter(window, state: state)
        ?? dialogue(line, state: state)
        ?? action(line)

    return withState(
      overlaid(scan, with: regions), after: line, state: state, region: regions.endRegion,
      titlePage: .closed)
  }

  // MARK: - State

  /// Rewrites `scan`'s end state: whether this line was blank, and whether a dialogue
  /// block is open below it.
  ///
  /// This is the **only** place in the file that decides an end state, which is why the
  /// per-element methods all return a placeholder: a construct that forgot to carry a bit
  /// would converge one line early, and centralizing it means no construct can forget. The
  /// bits are carried by mutating the incoming state rather than by building a fresh one,
  /// so a field a later sortie adds — the boneyard flag, the title-page flag — survives a
  /// line this grammar already knows how to scan. Dropping such a field is the one defect
  /// class the incremental design exists to prevent.
  ///
  /// The dialogue rule reads the *classification* rather than the text, because that is
  /// what the block boundary actually is:
  ///
  /// - a cue **opens** a block, whichever way it was spelled;
  /// - a parenthetical or a line of dialogue **continues** the one that is open, which it
  ///   could only have been produced inside of;
  /// - a lyric continues an open block without opening one — Fountain's own lyrics example
  ///   is a song sung inside a dialogue block, and `~Willy Wonka` at the top of a page must
  ///   not make the line under it dialogue;
  /// - **a note and a boneyard line likewise continue** an open block without opening one.
  ///   This is a deliberate addition rather than a consequence, and it is the one case in
  ///   this `switch` that is easy to get wrong by omission: a whole-line `[[note]]` between
  ///   two lines of speech would otherwise fall into the "everything else" branch, close
  ///   the block, and turn the speech under it into action. Neither construct is an element
  ///   of a screenplay — a note is commentary layered over one and a boneyard is text
  ///   struck out of one — so the speech on either side of either is contiguous in the
  ///   document that gets printed, and a scanner that says otherwise is describing a
  ///   document nobody wrote;
  /// - everything else, blank lines included, **closes** it.
  ///
  /// - Parameters:
  ///   - region: The ``LineState/openConstruct`` tag open at the **end** of this line —
  ///     ``noteTag``, ``boneyardTag``, or zero. Passed in and always assigned rather than
  ///     inherited, because inheriting it is how a closed boneyard stays open forever.
  ///   - titlePage: Where the **next** line sits with respect to the title page.
  private func withState(
    _ scan: LineScan,
    after line: GrammarLine,
    state: LineState,
    region: UInt16,
    titlePage: TitlePageRegion
  ) -> LineScan {
    var scan = scan
    var next = state
    next.followsNonBlankLine = !isBlank(line.units)
    next.openConstruct = region
    next.titlePage = titlePage
    switch scan.element {
    case .character:
      next.inDialogueBlock = true
    case .parenthetical, .dialogue, .lyrics, .note, .boneyard:
      break
    default:
      next.inDialogueBlock = false
    }
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

  // MARK: - The dialogue block

  /// Where the pieces of a character-cue line sit, as offsets into the line's content
  /// units.
  ///
  /// Four numbers rather than four ranges because the layout is computed against
  /// `line.units`, whose offsets are line-relative, and turned into document offsets
  /// exactly once — at the single call site that builds the spans. A layout carrying
  /// document ranges would have to be recomputed to be reused, and the natural-cue rule
  /// needs it twice: once to find where the name ends, and once to ask whether everything
  /// up to `textEnd` is uppercase.
  private struct CueLayout {
    /// One past the forcing `@` and any whitespace it swallowed. Zero for a natural cue,
    /// which has no marker at all.
    let markerEnd: Int

    /// One past the last code unit of the character *name* — before any extension, before
    /// the dual-dialogue caret, and with trailing whitespace trimmed.
    let nameEnd: Int

    /// One past the last code unit of the cue's text: the end of the extension when there
    /// is one, and equal to ``nameEnd`` when there is not. Everything from here to the end
    /// of the line is the caret and the whitespace around it.
    let textEnd: Int

    /// Whether the line carries a `(V.O.)`-style extension.
    var hasExtension: Bool { textEnd > nameEnd }
  }

  /// Decomposes a cue line into marker, name, extension, and trailing caret — or returns
  /// `nil` if it cannot be one at all.
  ///
  /// The only structural requirement is a **non-empty name**: `@` alone is not a cue, and
  /// neither is a line that is nothing but `(V.O.)`, which is a parenthetical's shape and
  /// belongs to whatever rule claims it next.
  ///
  /// Extension detection is "the first `(` on the line, when the line ends with `)`".
  /// That is deliberately not a bracket-matching walk: a Fountain character name cannot
  /// contain a parenthesis, so the first one opens the extension region by construction,
  /// and taking the whole region as one span makes `BOB (V.O.) (CONT'D)` fall out with no
  /// loop. Malformed input degrades rather than fails — `BOB (V.O.` has no closing
  /// parenthesis, so there is no extension and `(V.O.` is part of the name, which the
  /// uppercase rule then judges on its own merits.
  private func cueLayout(_ units: [UInt16], forced: Bool) -> CueLayout? {
    var markerEnd = 0
    if forced {
      guard units.first == atSign else { return nil }
      markerEnd = 1
      while markerEnd < units.count, isSpaceOrTab(units[markerEnd]) {
        markerEnd += 1
      }
    }

    // Right-trim, then peel one dual-dialogue caret and the whitespace on either side of
    // it. One caret: `^^` is not a Fountain construct, and the second one is text.
    var textEnd = units.count
    while textEnd > markerEnd, isSpaceOrTab(units[textEnd - 1]) {
      textEnd -= 1
    }
    if textEnd > markerEnd, units[textEnd - 1] == caret {
      textEnd -= 1
      while textEnd > markerEnd, isSpaceOrTab(units[textEnd - 1]) {
        textEnd -= 1
      }
    }
    guard textEnd > markerEnd else { return nil }

    var nameEnd = textEnd
    if units[textEnd - 1] == rightParenthesis {
      var open = markerEnd
      while open < textEnd, units[open] != leftParenthesis {
        open += 1
      }
      if open < textEnd {
        var trimmed = open
        while trimmed > markerEnd, isSpaceOrTab(units[trimmed - 1]) {
          trimmed -= 1
        }
        guard trimmed > markerEnd else { return nil }
        nameEnd = trimmed
      }
    }

    return CueLayout(markerEnd: markerEnd, nameEnd: nameEnd, textEnd: textEnd)
  }

  /// `@McAvoy`, `@BOB (V.O.) ^` — a character cue forced by a leading `@`.
  ///
  /// Forcing overrides **every** context rule, exactly as it does for a scene heading or a
  /// transition: no preceding blank line is required, no following line is required, and
  /// no uppercase rule is applied. `@McAvoy` on the last line of a document is a cue, and
  /// that is the entire point of the marker — it is how a writer names a character the
  /// automatic rule would not recognize, and a marker that only worked when the automatic
  /// rule would have fired anyway would be decoration.
  ///
  /// The `@` swallows the whitespace after it, so `@ McAvoy` names `McAvoy`. There is no
  /// ambiguity to protect against here the way a forced scene heading's `.` has to protect
  /// against an ellipsis: no other Fountain construct begins with `@`.
  private func forcedCharacter(_ line: GrammarLine) -> LineScan? {
    guard let layout = cueLayout(line.units, forced: true) else { return nil }
    return character(line, layout: layout)
  }

  /// `BOB`, `BOB (V.O.)`, `JANE ^` — a cue recognized by its shape and its neighbours.
  ///
  /// **This is the one rule in the package that reads the line below it**, and all three
  /// of its conditions are necessary:
  ///
  /// 1. A block boundary above — otherwise every shouted line of action becomes a cue.
  /// 2. A non-blank line below. This is the lookahead, and it is why an ALL-CAPS line at
  ///    the end of a document is action: nobody is speaking. `line(ahead:)` answers `nil`
  ///    both for "past the end of the document" and for "past the declared lookahead", and
  ///    those two cases are deliberately indistinguishable — at a lookahead of one they
  ///    can only mean the first.
  /// 3. Uppercase, over the whole line minus the caret (deviation 5), with at least one
  ///    ASCII capital in it. The capital is the spec's "character names must include at
  ///    least one alphabetical character", which is what keeps `23` from being a speaker.
  private func naturalCharacter(_ window: LineWindow, state: LineState) -> LineScan? {
    guard !state.followsNonBlankLine else { return nil }
    guard let ahead = window.line(ahead: 1), !isBlank(ahead.units) else { return nil }
    let line = window.current
    guard let layout = cueLayout(line.units, forced: false) else { return nil }
    guard isUppercase(line.units, upTo: layout.textEnd) else { return nil }
    return character(line, layout: layout)
  }

  /// Lays out a cue: `@` marker, name, extension, trailing caret marker.
  ///
  /// The spans tile the line with no `.text` filler anywhere in it, which is why the
  /// extension span begins at `nameEnd` rather than at the `(` — the space between a name
  /// and its extension belongs to the extension, not to a gap. The trailing marker runs
  /// from the end of the text to the end of the line's content for the same reason the
  /// centered element's closing marker does: the caret and the whitespace around it stay
  /// cue-coloured instead of falling through to plain text.
  private func character(_ line: GrammarLine, layout: CueLayout) -> LineScan {
    let base = line.contentRange.lowerBound
    var spans: [EscriboSpan] = []
    if layout.markerEnd > 0 {
      spans.append(
        EscriboSpan(range: base..<(base + layout.markerEnd), kind: .character, role: .marker))
    }
    spans.append(
      EscriboSpan(range: (base + layout.markerEnd)..<(base + layout.nameEnd), kind: .character))
    if layout.hasExtension {
      spans.append(
        EscriboSpan(
          range: (base + layout.nameEnd)..<(base + layout.textEnd), kind: .characterExtension))
    }
    if base + layout.textEnd < line.contentRange.upperBound {
      spans.append(
        EscriboSpan(
          range: (base + layout.textEnd)..<line.contentRange.upperBound, kind: .character,
          role: .marker))
    }

    return LineScan(
      spans: spans,
      element: .character,
      // The name alone — see ``ElementKind/character``. The `@`, the extension, and the
      // `^` are all still on the line and all still recoverable against the source.
      contentRange: (base + layout.markerEnd)..<(base + layout.nameEnd),
      endState: LineState()
    )
  }

  /// A line inside an open dialogue block: a parenthetical, or speech.
  ///
  /// `nil` outside a block, which is the whole reason `(beat)` at the top of a page is
  /// action. Both forms trim their whitespace into the record's content range, unlike
  /// action: indentation inside a dialogue block is screenplay formatting rather than
  /// something the writer meant, and the source still has it.
  private func dialogue(_ line: GrammarLine, state: LineState) -> LineScan? {
    guard state.inDialogueBlock else { return nil }
    return parenthetical(line)
      ?? markedLine(line, markerEnd: 0, kind: .dialogue, element: .dialogue)
  }

  /// `(beat)` — a parenthetical, possibly indented (deviation 6).
  ///
  /// Only ever reached from inside a dialogue block. The parentheses stay inside the
  /// content range because they print; the indent, which does not, becomes the line's one
  /// marker-role span.
  private func parenthetical(_ line: GrammarLine) -> LineScan? {
    let units = line.units
    var start = 0
    while start < units.count, isSpaceOrTab(units[start]) {
      start += 1
    }
    var end = units.count
    while end > start, isSpaceOrTab(units[end - 1]) {
      end -= 1
    }
    guard end - start >= 2 else { return nil }
    guard units[start] == leftParenthesis, units[end - 1] == rightParenthesis else { return nil }
    return markedLine(line, markerEnd: 0, kind: .parenthetical, element: .parenthetical)
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

  // MARK: - Notes and boneyard

  /// What one line's notes and boneyard came to.
  ///
  /// Offsets here are **document** offsets, not line-relative ones: unlike ``CueLayout``,
  /// nothing recomputes this against a second coordinate system, so converting once inside
  /// the walk is cheaper than converting at every use.
  private struct RegionScan {

    /// The note and boneyard spans, in document coordinates, in ascending order and
    /// non-overlapping.
    var spans: [EscriboSpan] = []

    /// The extents those spans cover, one per region the line touched, ascending.
    ///
    /// Kept apart from ``spans`` because a region is *three* spans — opening marker,
    /// content, closing marker — and what the overlay has to subtract is the whole region,
    /// not each of its pieces.
    var covered: [Range<Int>] = []

    /// The tag of the region open at the **end** of the line: ``noteTag``,
    /// ``boneyardTag``, or zero when the line ends outside one.
    var endRegion: UInt16 = 0

    /// The tag of the **first** region on the line, which is the one that names the line
    /// when the line is nothing but region.
    var firstRegion: UInt16 = 0

    /// Whether every code unit on the line that is not a space or a tab sits inside a
    /// region.
    var contentIsAllRegion = true

    /// Where the first region's text begins and the last region's text ends, markers
    /// excluded — the content range of a line that is nothing but region.
    var innerStart = 0
    var innerEnd = 0

    /// Whether the line has region on it and nothing else a classification could belong
    /// to.
    ///
    /// Vacuously true for a whitespace-only line **inside** an open region, which is the
    /// answer that keeps a blank line in the middle of a boneyard from ending the
    /// boneyard's block.
    var coversWholeLine: Bool { !covered.isEmpty && contentIsAllRegion }
  }

  /// Walks one line left to right, opening and closing notes and boneyards.
  ///
  /// One pass for both constructs rather than one pass each, because they are mutually
  /// exclusive rather than independent: inside a note a `/*` is text, and inside a
  /// boneyard a `[[` is text (deviation 7). Two passes would have to agree with each other
  /// about which opened first, and agreeing is what one pass does for free.
  ///
  /// - Parameter incoming: The ``LineState/openConstruct`` tag this line begins with. A tag
  ///   this grammar does not own — a Markdown fence tag arriving through a nested scan —
  ///   is read as "nothing open", which is the only reading a grammar is entitled to make
  ///   of another grammar's private encoding.
  private func scanRegions(_ line: GrammarLine, incoming: UInt16) -> RegionScan {
    let units = line.units
    let base = line.contentRange.lowerBound
    var out = RegionScan()

    var region = (incoming == Self.noteTag || incoming == Self.boneyardTag) ? incoming : 0
    // Where the open region's extent begins on *this* line, and where its text does. Equal
    // when the region opened on an earlier line, which is exactly what "no opening marker
    // on this line" means.
    var regionStart = 0
    var textStart = 0
    var sawFirstText = false
    if region != 0 { out.firstRegion = region }

    /// Records the region running from `regionStart` as ending at `end`.
    func closeRegion(at end: Int, withMarker hasCloser: Bool) {
      let kind: SpanKind = region == Self.noteTag ? .note : .boneyard
      let textEnd = hasCloser ? end - 2 : end
      if textStart > regionStart {
        out.spans.append(
          EscriboSpan(range: (base + regionStart)..<(base + textStart), kind: kind, role: .marker))
      }
      if textEnd > textStart {
        out.spans.append(EscriboSpan(range: (base + textStart)..<(base + textEnd), kind: kind))
      }
      if hasCloser {
        out.spans.append(
          EscriboSpan(range: (base + textEnd)..<(base + end), kind: kind, role: .marker))
      }
      out.covered.append((base + regionStart)..<(base + end))
      if !sawFirstText {
        out.innerStart = base + textStart
        sawFirstText = true
      }
      out.innerEnd = base + max(textStart, textEnd)
    }

    var offset = 0
    while offset < units.count {
      if region == 0 {
        let opensNote =
          units[offset] == leftBracket && offset + 1 < units.count
          && units[offset + 1] == leftBracket
        let opensBoneyard =
          units[offset] == solidus && offset + 1 < units.count && units[offset + 1] == asterisk
        if opensNote || opensBoneyard {
          region = opensNote ? Self.noteTag : Self.boneyardTag
          if out.firstRegion == 0 { out.firstRegion = region }
          regionStart = offset
          textStart = offset + 2
          offset += 2
          continue
        }
        // The one place a line earns its own classification: a visible code unit that no
        // region covers.
        if !isSpaceOrTab(units[offset]) { out.contentIsAllRegion = false }
        offset += 1
        continue
      }

      let first: UInt16 = region == Self.noteTag ? rightBracket : asterisk
      let second: UInt16 = region == Self.noteTag ? rightBracket : solidus
      if units[offset] == first, offset + 1 < units.count, units[offset + 1] == second {
        closeRegion(at: offset + 2, withMarker: true)
        region = 0
        offset += 2
        continue
      }
      offset += 1
    }

    if region != 0 {
      // Unterminated on this line. It runs to the end of the line and, through the state,
      // to the end of the document unless a later line closes it (deviation 9).
      closeRegion(at: units.count, withMarker: false)
      out.endRegion = region
    }
    return out
  }

  /// A line that is nothing but note or boneyard.
  ///
  /// The content range is the region text with the markers taken off, which is the same
  /// bargain every marked element here makes: `[[a note]]` reports `a note`, and the
  /// brackets stay recoverable against the source as the difference between `range` and
  /// `contentRange`.
  private func regionLine(_ line: GrammarLine, _ regions: RegionScan) -> LineScan {
    LineScan(
      spans: regions.spans,
      element: regions.firstRegion == Self.noteTag ? .note : .boneyard,
      contentRange: regions.innerStart..<max(regions.innerStart, regions.innerEnd),
      endState: LineState()
    )
  }

  /// Lays `regions`' spans over `scan`'s, cutting the block element's spans around them.
  ///
  /// Cutting rather than appending, and this is not a detail: ``SpanTiling`` resolves an
  /// overlap in favour of whichever span **starts earlier**, so a `.dialogue` span covering
  /// a whole line would swallow a note in the middle of it and the note would never be
  /// seen. Subtracting first means nothing overlaps by the time the tiler runs, and the
  /// tiler's repairs stay repairs rather than the mechanism.
  ///
  /// The content range is deliberately left alone: a note inside a line of dialogue is
  /// inside that line's content, and a writer round-tripping the line writes the source
  /// back out unchanged either way.
  private func overlaid(_ scan: LineScan, with regions: RegionScan) -> LineScan {
    guard !regions.covered.isEmpty else { return scan }
    var scan = scan
    var spans = regions.spans
    for span in scan.spans {
      var pieces = [span.range]
      for cut in regions.covered {
        pieces = pieces.flatMap { Self.subtracting(cut, from: $0) }
      }
      for piece in pieces where !piece.isEmpty {
        spans.append(
          EscriboSpan(range: piece, kind: span.kind, style: span.style, role: span.role))
      }
    }
    scan.spans = spans
    return scan
  }

  /// `range` with `cut` removed: itself, one piece, two pieces, or none.
  private static func subtracting(_ cut: Range<Int>, from range: Range<Int>) -> [Range<Int>] {
    guard cut.lowerBound < range.upperBound, cut.upperBound > range.lowerBound else {
      return [range]
    }
    var pieces: [Range<Int>] = []
    if range.lowerBound < cut.lowerBound { pieces.append(range.lowerBound..<cut.lowerBound) }
    if cut.upperBound < range.upperBound { pieces.append(cut.upperBound..<range.upperBound) }
    return pieces
  }

  // MARK: - The title page

  /// Whether the document's first line opens a title page.
  ///
  /// Asked **only** on line 0 — ``TitlePageRegion/documentStart`` is reachable nowhere else
  /// in a Fountain scan — which is what keeps a `Draft date:` in the middle of a line of
  /// action from reopening a title page two hundred lines down.
  ///
  /// Two ways to qualify, and the second one is deviation 11's whole point. A key with a
  /// value on the same line settles it by itself. A key with nothing after the colon needs
  /// the line below it to corroborate: Fountain's canonical form puts a long value on
  /// indented continuation lines under a bare `Title:`, and without corroboration the
  /// transition `CUT TO:` — an entirely ordinary first line — would be a title page whose
  /// key is `CUT TO`.
  private func opensTitlePage(_ window: LineWindow) -> Bool {
    let units = window.current.units
    guard let colonAt = titlePageKeyEnd(units) else { return false }
    for offset in (colonAt + 1)..<units.count where !isSpaceOrTab(units[offset]) { return true }
    guard let ahead = window.line(ahead: 1), !isBlank(ahead.units) else { return false }
    // An indented continuation, or a second key. Anything else is a document that merely
    // begins with a colon.
    return isSpaceOrTab(ahead.units[0]) || titlePageKeyEnd(ahead.units) != nil
  }

  /// The offset of the colon ending a title-page key, or `nil` if the line carries none.
  ///
  /// A key starts at the first code unit — an indented line is a continuation value, not a
  /// key, even when it contains a colon — and must be non-empty, so `: value` is not a key
  /// of nothing. The **first** colon ends it: a key may contain spaces (`Draft date`) but
  /// not a colon, so no scanning past the first one is meaningful.
  private func titlePageKeyEnd(_ units: [UInt16]) -> Int? {
    guard let first = units.first, !isSpaceOrTab(first) else { return nil }
    var offset = 0
    while offset < units.count, units[offset] != colon {
      offset += 1
    }
    guard offset >= 1, offset < units.count else { return nil }
    return offset
  }

  /// One non-blank line inside the title page: a key with its value, or a continuation.
  private func titlePageLine(_ line: GrammarLine) -> LineScan {
    guard let colonAt = titlePageKeyEnd(line.units) else {
      // Indented, or carrying no colon at all: a continuation of whatever key is above it.
      // The leading indent becomes the line's one marker span, exactly as a parenthetical's
      // does, and the value is what is left.
      return markedLine(line, markerEnd: 0, kind: .titlePageValue, element: .titlePageValue)
    }

    let units = line.units
    let base = line.contentRange.lowerBound
    var valueStart = colonAt + 1
    while valueStart < units.count, isSpaceOrTab(units[valueStart]) {
      valueStart += 1
    }
    var valueEnd = units.count
    while valueEnd > valueStart, isSpaceOrTab(units[valueEnd - 1]) {
      valueEnd -= 1
    }

    // The key span covers the key text and **nothing else** — this is REQUIREMENTS.md
    // § Fountain 2 as a range. Nothing is trimmed off either end, nothing is case-folded,
    // and no key is checked against a list, because there is no list: `verbsCovered` and
    // `Abstract` are as much keys here as `Title` is.
    var spans = [
      EscriboSpan(range: base..<(base + colonAt), kind: .titlePageKey),
      EscriboSpan(
        range: (base + colonAt)..<(base + valueStart), kind: .titlePageKey, role: .marker),
    ]
    if valueEnd > valueStart {
      spans.append(
        EscriboSpan(range: (base + valueStart)..<(base + valueEnd), kind: .titlePageValue))
    }

    return LineScan(
      spans: spans,
      element: .titlePageKey,
      // The **value**. The key is the first span, where a writer reads it back verbatim.
      contentRange: (base + valueStart)..<(base + valueEnd),
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
