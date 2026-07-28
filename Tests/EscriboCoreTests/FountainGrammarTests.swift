import Testing

@testable import EscriboCore

/// Fountain's block elements — scene headings, action, transitions, centered text,
/// sections, synopses, page breaks, and lyrics — and the whole dialogue block: character
/// cues with extensions, parentheticals, dialogue, and dual dialogue.
///
/// Every assertion here names an `ElementKind` — or a span's exact range, kind, and role
/// — **by hand**. None of it was produced by running the grammar and pasting the result
/// back, and that is the only property that makes any of it able to fail.
///
/// This matters more here than anywhere else in the suite, because the one property test
/// this package has cannot help. `ScanGateTests`'s `incrementalScan == fullScan` runs the
/// *same* grammar on both sides: a grammar that classifies every line wrong, or that
/// computes a state and forgets to carry it, agrees with itself perfectly and the gate
/// stays green. A prior sortie broke a fence flag, turned six classification tests red,
/// and the gate never noticed. Do not delete an expectation here on the grounds that the
/// gate covers it. It does not.
///
/// Every scan in this suite goes through ``fullScan(_:)``, which calls Sortie 6's
/// ``ScanInvariants/check(_:text:editedRange:_:sourceLocation:)`` on the way out — so the
/// invariant harness runs on every Fountain scan the suite performs, without any test
/// having to remember to ask for it.
@Suite("Fountain grammar — block elements and the dialogue block")
struct FountainGrammarTests {

  // MARK: - Helpers

  /// Full-scans `text` **and asserts every `ScanResult` invariant on the way out**.
  static func fullScan(
    _ text: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> ScanResult {
    var scanner = IncrementalScanner(grammar: FountainGrammar())
    let result = scanner.fullScan(text)
    ScanInvariants.check(
      result, text: text, editedRange: nil, "fountain full scan of \(text.debugDescription)",
      sourceLocation: sourceLocation)
    return result
  }

  /// The classification of every line of `text`, in order.
  static func elements(_ text: String, sourceLocation: SourceLocation = #_sourceLocation)
    -> [ElementKind]
  {
    fullScan(text, sourceLocation: sourceLocation).lineRecords.map(\.element)
  }

  /// The classification of a one-line document — the shape most of the negative cases
  /// below take.
  static func element(_ text: String, sourceLocation: SourceLocation = #_sourceLocation)
    -> ElementKind
  {
    fullScan(text, sourceLocation: sourceLocation).lineRecords[0].element
  }

  // MARK: - Scene headings: forced and natural

  @Test("`.INT. HOUSE` and `INT. HOUSE` are the same element with distinguishable records")
  func forcedAndNaturalSceneHeadingsShareAnElementAndDifferInRecord() {
    // REQUIREMENTS.md Architecture §9: no lexical information the writer needs may be
    // discarded. The forcing period is that information. It is NOT preserved by giving
    // the forced form its own `ElementKind` — the two lines lay out identically on the
    // page, so one kind is correct — but by keeping the period OUT of the content range,
    // where the writer reads it back as `range.lowerBound..<contentRange.lowerBound`.
    let forced = Self.fullScan(".INT. HOUSE")
    let natural = Self.fullScan("INT. HOUSE")

    let forcedRecord = forced.lineRecords[0]
    let naturalRecord = natural.lineRecords[0]

    // Same element: geometry does not care how the line was spelled.
    #expect(forcedRecord.element == .sceneHeading)
    #expect(naturalRecord.element == .sceneHeading)
    #expect(forcedRecord.element == naturalRecord.element)

    // Distinguishable records: the forced one's content starts one code unit later, and
    // that one code unit is exactly the marker.
    #expect(forcedRecord.range == 0..<11)
    #expect(forcedRecord.contentRange == 1..<11, "the forcing period is not content")
    #expect(naturalRecord.range == 0..<10)
    #expect(naturalRecord.contentRange == 0..<10, "an unforced heading has no marker to skip")
    #expect(forcedRecord.contentRange.lowerBound > forcedRecord.range.lowerBound)
    #expect(naturalRecord.contentRange.lowerBound == naturalRecord.range.lowerBound)

    // Stated as the writer would state it: the marker is recoverable from the record.
    let forcedMarker = forcedRecord.range.lowerBound..<forcedRecord.contentRange.lowerBound
    let naturalMarker = naturalRecord.range.lowerBound..<naturalRecord.contentRange.lowerBound
    #expect(forcedMarker == 0..<1)
    #expect(naturalMarker.isEmpty)

    // And the period is a `.marker` span carrying the SAME kind as the content it
    // delimits, differing only in role — the invariant the whole styler rests on.
    #expect(forced.spans[0].range == 0..<1)
    #expect(forced.spans[0].kind == .sceneHeading)
    #expect(forced.spans[0].role == .marker)
    #expect(forced.spans[1].range == 1..<11)
    #expect(forced.spans[1].kind == .sceneHeading)
    #expect(forced.spans[1].role == .content)
    #expect(forced.spans[0].kind == forced.spans[1].kind)
    #expect(forced.spans[0].style == forced.spans[1].style)

    // The natural form emits no marker span at all, which is the span-level statement of
    // the same fact.
    #expect(natural.spans.count == 1)
    #expect(natural.spans[0].role == .content)
  }

  @Test(
    "Every scene-heading prefix is recognized, and a word that merely starts with one is not",
    arguments: [
      ("INT. HOUSE - DAY", ElementKind.sceneHeading),
      ("EXT. STREET - NIGHT", ElementKind.sceneHeading),
      ("EST. THE CITY", ElementKind.sceneHeading),
      ("INT./EXT. CAR - DAY", ElementKind.sceneHeading),
      ("INT/EXT. CAR - DAY", ElementKind.sceneHeading),
      ("EXT./INT. CAR - DAY", ElementKind.sceneHeading),
      ("I/E. CAR - DAY", ElementKind.sceneHeading),
      ("I/E CAR - DAY", ElementKind.sceneHeading),
      ("INT HOUSE", ElementKind.sceneHeading),
      ("INT.", ElementKind.sceneHeading),
      // The follow-character rule. Each of these begins with a prefix and is not a
      // heading, and each is a line a prefix-only scanner classifies wrong.
      ("INTERIOR DECORATOR", ElementKind.action),
      ("ESTIMATED TIME", ElementKind.action),
      ("EXTRA! EXTRA!", ElementKind.action),
      // Case-sensitive: a Fountain slug line is uppercase.
      ("int. house - day", ElementKind.action),
      // Rule 1 of the grammar's stated deviations: markers and prefixes start at the
      // first code unit, because action preserves its leading whitespace.
      ("   INT. HOUSE", ElementKind.action),
    ])
  func scenePrefixes(text: String, expected: ElementKind) {
    #expect(Self.element(text) == expected, "\(text.debugDescription)")
  }

  @Test("A natural scene heading needs a blank line above it; a forced one does not")
  func naturalSceneHeadingsNeedABlockBoundary() {
    // The one bit of state this grammar carries, asserted directly. Line 2 is textually
    // identical to line 0 and classifies differently, which is only possible if the
    // classification consulted something that arrived from above.
    #expect(
      Self.elements("INT. HOUSE\n\nINT. HOUSE\n")
        == [.sceneHeading, .blank, .sceneHeading, .blank])
    #expect(
      Self.elements("Bob walks in.\nINT. HOUSE\n")
        == [.action, .action, .blank],
      "a slug line jammed under action is action")

    // Forcing it overrides the boundary rule entirely — that is what forcing is for.
    #expect(
      Self.elements("Bob walks in.\n.INT. HOUSE\n")
        == [.action, .sceneHeading, .blank])

    // A whitespace-only line opens a block: a stray space must not demote the heading
    // below it (deviation 2).
    #expect(
      Self.elements("Bob walks in.\n   \nINT. HOUSE\n")
        == [.action, .blank, .sceneHeading, .blank])
  }

  @Test("A leading period forces a heading only when it is single and followed by text")
  func forcedSceneHeadingPeriodRules() {
    // The spec's motivation for the rule is concrete: an action line may open with an
    // ellipsis, and `...and then` must not become a slug line.
    #expect(Self.element(".INT. HOUSE") == .sceneHeading)
    #expect(Self.element(".SNIPER SCOPE POV") == .sceneHeading)
    #expect(Self.element("...and then he ran") == .action)
    #expect(Self.element("..double") == .action)
    #expect(Self.element(". spaced") == .action)
    #expect(Self.element(".") == .action)

    // A doubled period never forces a heading, whatever else the line may turn out to
    // be — `..CUT TO:` is uppercase and ends in `TO:`, so it is a transition, and the
    // assertion that matters is that the period did not make it a slug line.
    #expect(Self.element("..CUT TO:") != .sceneHeading)
    #expect(Self.element("..CUT TO:") == .transition)
  }

  // MARK: - Page breaks and synopses

  @Test("`===` is a page break and `==` is not")
  func pageBreakNeedsThreeEquals() {
    // Three is the floor, and the floor is the entire difference between these two
    // elements. `==` is not "nearly a page break" and not an error — it is a synopsis
    // whose text happens to be a single `=`, because only the first `=` is the marker.
    let pageBreak = Self.fullScan("===")
    #expect(pageBreak.lineRecords[0].element == .pageBreak)
    #expect(pageBreak.lineRecords[0].contentRange == 3..<3, "a page break is pure delimiter")
    #expect(pageBreak.spans.count == 1)
    #expect(pageBreak.spans[0].range == 0..<3)
    #expect(pageBreak.spans[0].kind == .pageBreak)
    #expect(pageBreak.spans[0].role == .marker)

    let notAPageBreak = Self.fullScan("==")
    #expect(notAPageBreak.lineRecords[0].element != .pageBreak)
    #expect(notAPageBreak.lineRecords[0].element == .synopsis)
    #expect(notAPageBreak.lineRecords[0].contentRange == 1..<2)

    #expect(Self.element("=") == .synopsis)
    #expect(Self.element("====") == .pageBreak, "longer than three is still a page break")
    #expect(Self.element("===   ") == .pageBreak, "trailing whitespace is allowed")
    #expect(Self.element("=== END OF ACT ONE") == .synopsis, "a run with text after it is not")
  }

  @Test("A synopsis keeps only its first `=` as a marker")
  func synopsisSpanLayout() {
    let result = Self.fullScan("= Bob finally tells the truth.")
    #expect(result.lineRecords[0].element == .synopsis)
    #expect(result.lineRecords[0].contentRange == 2..<30)
    #expect(result.spans[0].range == 0..<2, "the marker swallows the space after it")
    #expect(result.spans[0].kind == .synopsis)
    #expect(result.spans[0].role == .marker)
    #expect(result.spans[1].range == 2..<30)
    #expect(result.spans[1].role == .content)
    #expect(result.spans[0].kind == result.spans[1].kind)
  }

  // MARK: - Centered text vs. transitions

  @Test("`>CENTERED<` and `> TRANSITION` produce different elements")
  func centeredAndTransitionAreDifferentElements() {
    // Both open with `>`. The closing `<` is the only difference in the source, and it
    // has to be the difference in the output too: centering is paragraph geometry and a
    // transition is flush right, so a scanner that collapsed them would make the styler
    // guess.
    let centered = Self.fullScan(">THE END<")
    let transition = Self.fullScan("> CUT TO:")

    #expect(centered.lineRecords[0].element == .centered)
    #expect(transition.lineRecords[0].element == .transition)
    #expect(centered.lineRecords[0].element != transition.lineRecords[0].element)

    // Centered: marker, content, marker. Both delimiters are preserved and both are out
    // of the content range.
    #expect(centered.lineRecords[0].contentRange == 1..<8)
    #expect(centered.spans.count == 3)
    #expect(centered.spans[0].range == 0..<1)
    #expect(centered.spans[0].role == .marker)
    #expect(centered.spans[1].range == 1..<8)
    #expect(centered.spans[1].role == .content)
    #expect(centered.spans[2].range == 8..<9)
    #expect(centered.spans[2].role == .marker)
    #expect(centered.spans.allSatisfy { $0.kind == .centered })

    // Transition: one marker that swallows the space, then content.
    #expect(transition.lineRecords[0].contentRange == 2..<9)
    #expect(transition.spans.count == 2)
    #expect(transition.spans[0].range == 0..<2)
    #expect(transition.spans[0].role == .marker)
    #expect(transition.spans[1].range == 2..<9)
    #expect(transition.spans.allSatisfy { $0.kind == .transition })

    // Whitespace inside the centering delimiters is marker, not content.
    let padded = Self.fullScan("> THE END <")
    #expect(padded.lineRecords[0].element == .centered)
    #expect(padded.lineRecords[0].contentRange == 2..<9)
  }

  @Test("A natural transition is uppercase, ends in `TO:`, and opens a block")
  func naturalTransitions() {
    #expect(Self.element("CUT TO:") == .transition)
    #expect(Self.element("SMASH CUT TO:") == .transition)
    #expect(Self.element("Cut to:") == .action, "an uppercase rule that ignores case is no rule")
    #expect(Self.element("CUT TO") == .action, "the colon is required")
    #expect(Self.element("FADE OUT.") == .action, "only `TO:` — `FADE OUT.` is not in the rule")

    // Same block-boundary rule as a natural scene heading, and the same override.
    #expect(Self.elements("Bob leaves.\nCUT TO:\n") == [.action, .action, .blank])
    #expect(Self.elements("Bob leaves.\n> CUT TO:\n") == [.action, .transition, .blank])
    #expect(Self.elements("Bob leaves.\n\nCUT TO:\n") == [.action, .blank, .transition, .blank])
  }

  @Test("A forced transition keeps its `>` out of the content range")
  func forcedTransitionPreservesItsMarker() {
    let forced = Self.fullScan(">BURN TO PINK.")
    #expect(forced.lineRecords[0].element == .transition)
    #expect(forced.lineRecords[0].contentRange == 1..<14)
    #expect(forced.spans[0].range == 0..<1)
    #expect(forced.spans[0].role == .marker)

    // The natural spelling of a transition has no marker, so its content starts at the
    // line start — the same forced/natural distinction scene headings make.
    let natural = Self.fullScan("CUT TO:")
    #expect(natural.lineRecords[0].element == .transition)
    #expect(natural.lineRecords[0].contentRange == 0..<7)
    #expect(natural.spans[0].role == .content)
  }

  // MARK: - Sections, lyrics, and forced action

  @Test("A section's level lives in `depth`, at any depth")
  func sectionDepth() {
    for level in 1...8 {
      let hashes = String(repeating: "#", count: level)
      let result = Self.fullScan("\(hashes) Act")
      let record = result.lineRecords[0]
      #expect(record.element == .section, "level \(level)")
      #expect(record.depth == level, "level \(level)")
      #expect(record.contentRange == (level + 1)..<(level + 4), "level \(level)")
      #expect(result.spans[0].range == 0..<(level + 1), "level \(level)")
      #expect(result.spans[0].kind == .section, "level \(level)")
      #expect(result.spans[0].role == .marker, "level \(level)")
    }

    // Fountain places no ceiling on section depth; six is CommonMark's number, and a
    // seven-hash line is a Markdown paragraph but a Fountain section.
    #expect(Self.element("####### Deep") == .section)
    // No space is required after the run — Fountain has no hashtags to protect.
    let tight = Self.fullScan("#Act One")
    #expect(tight.lineRecords[0].element == .section)
    #expect(tight.lineRecords[0].depth == 1)
    #expect(tight.lineRecords[0].contentRange == 1..<8)
  }

  @Test("Lyrics and forced action keep their markers")
  func lyricsAndForcedAction() {
    let lyric = Self.fullScan("~Willy Wonka")
    #expect(lyric.lineRecords[0].element == .lyrics)
    #expect(lyric.lineRecords[0].contentRange == 1..<12)
    #expect(lyric.spans[0].range == 0..<1)
    #expect(lyric.spans[0].kind == .lyrics)
    #expect(lyric.spans[0].role == .marker)
    #expect(lyric.spans[1].kind == .lyrics)
    #expect(lyric.spans[1].role == .content)

    // A forced action line keeps its `!` out of the content range and keeps everything
    // else in it — action is the one element whose internal whitespace is meaningful.
    let forced = Self.fullScan("!INT. HOUSE - DAY")
    #expect(forced.lineRecords[0].element == .action, "the bang beats the slug-line prefix")
    #expect(forced.lineRecords[0].contentRange == 1..<17)
    #expect(forced.spans[0].range == 0..<1)
    #expect(forced.spans[0].kind == .action)
    #expect(forced.spans[0].role == .marker)

    let spaced = Self.fullScan("!  spaced   ")
    #expect(spaced.lineRecords[0].contentRange == 1..<12, "action keeps its whitespace")
  }

  @Test("Plain action is action, and its content is the whole line including its indent")
  func actionKeepsItsIndent() {
    let result = Self.fullScan("    Bob steps back.")
    #expect(result.lineRecords[0].element == .action)
    #expect(result.lineRecords[0].contentRange == 0..<19, "the indent is content in action")
    #expect(result.spans[0].range == 0..<19)
    #expect(result.spans[0].kind == .action)
    #expect(result.spans[0].role == .content)
  }

  // MARK: - Character cues: the one rule that reads the line below it

  @Test("An ALL-CAPS line is a cue only when a non-blank line follows it")
  func aCueIsRecognizedByWhatFollowsIt() {
    // The whole sortie in four documents. `BOB` is textually identical in all of them and
    // classifies three different ways, which is only possible if the classification
    // consulted the line *after* it. Every expectation is written out by hand — the gate
    // property runs the same grammar on both sides and cannot fail on any of this.
    #expect(Self.elements("BOB\nHello there.\n") == [.character, .dialogue, .blank])
    #expect(Self.elements("BOB\n\nHello there.") == [.action, .blank, .action])
    #expect(Self.elements("BOB\n") == [.action, .blank])

    // A block boundary above is required too: an ALL-CAPS line jammed under action is a
    // shout, not a speaker.
    #expect(Self.elements("Bob shouts.\nBOB\nHello.") == [.action, .action, .action])
  }

  @Test("An ALL-CAPS line at the end of the document is action, not a cue")
  func allCapsAtEndOfFileIsAction() {
    // Nobody is speaking. `line(ahead:)` answers `nil` for "past the end of the document"
    // exactly as it does for "past the declared lookahead", and at a lookahead of one
    // those cannot be confused.
    #expect(Self.element("BOB") == .action, "a cue with nothing under it is not a cue")
    #expect(Self.elements("BOB\n") == [.action, .blank], "a trailing terminator is a blank line")
    #expect(Self.elements("BOB\r\n") == [.action, .blank])
    #expect(Self.elements("INT. HOUSE - DAY\n\nBOB") == [.sceneHeading, .blank, .action])

    // And the same line one document later, with something under it, is a cue. Stated as a
    // pair so the assertion above is about the lookahead rather than about capitals.
    #expect(
      Self.elements("INT. HOUSE - DAY\n\nBOB\nHi.") == [
        .sceneHeading, .blank, .character, .dialogue,
      ])
  }

  @Test("`@McAvoy` is a cue despite not being ALL-CAPS")
  func atSignForcesACueWhateverItsCase() {
    // The forcing marker exists precisely for the name the automatic rule declines, so it
    // overrides every context rule: no uppercase, no preceding blank line, no following
    // line. A marker that only worked where the automatic rule already fired would be
    // decoration.
    let forced = Self.fullScan("@McAvoy")
    #expect(forced.lineRecords[0].element == .character)
    #expect(forced.lineRecords[0].contentRange == 1..<7, "the `@` is not part of the name")
    #expect(forced.spans[0].range == 0..<1)
    #expect(forced.spans[0].kind == .character)
    #expect(forced.spans[0].role == .marker)
    #expect(forced.spans[1].range == 1..<7)
    #expect(forced.spans[1].kind == .character)
    #expect(forced.spans[1].role == .content)

    // Unforced, the same text is action — which is what makes the assertion above about
    // the marker rather than about the word.
    #expect(Self.elements("McAvoy\nHello.") == [.action, .action])

    // Forced works everywhere the natural form does not: under action, and at EOF.
    #expect(Self.elements("Bob walks in.\n@McAvoy\nHello.") == [.action, .character, .dialogue])
    #expect(Self.elements("@McAvoy\nHello.") == [.character, .dialogue])
    #expect(Self.element("@ McAvoy") == .character, "the `@` swallows the space after it")
    #expect(Self.element("@") == .action, "a cue needs a name")
  }

  @Test("A cue extension is spanned separately and left out of the character's name")
  func cueExtensions() {
    // `contentRange` is the NAME, not the whole line. That is the one place in this
    // vocabulary where content is narrower than "not a marker", and it is deliberate: a
    // consumer building a cast list wants `BOB`, and the extension is still on the line,
    // still spanned, and still in the source.
    let voiceOver = Self.fullScan("BOB (V.O.)\nHello.")
    #expect(voiceOver.lineRecords[0].element == .character)
    #expect(voiceOver.lineRecords[0].contentRange == 0..<3, "the extension is not the name")
    #expect(voiceOver.spans[0].range == 0..<3)
    #expect(voiceOver.spans[0].kind == .character)
    #expect(voiceOver.spans[1].range == 3..<10, "the space before `(` belongs to the extension")
    #expect(voiceOver.spans[1].kind == .characterExtension)
    #expect(voiceOver.spans[1].role == .content, "an extension prints; it is not a marker")

    let continued = Self.fullScan("BOB (CONT'D)\nHi.")
    #expect(continued.lineRecords[0].element == .character)
    #expect(continued.lineRecords[0].contentRange == 0..<3)
    #expect(continued.spans[1].range == 3..<12)
    #expect(continued.spans[1].kind == .characterExtension)

    // Two extensions are one region, because a Fountain name cannot contain a parenthesis
    // and the first one therefore opens the region by construction.
    let both = Self.fullScan("BOB (V.O.) (CONT'D)\nHi.")
    #expect(both.lineRecords[0].contentRange == 0..<3)
    #expect(both.spans[1].range == 3..<19)
    #expect(both.spans[1].kind == .characterExtension)

    // Deviation 5: the uppercase rule covers the extension too, and `@` is the escape.
    #expect(Self.elements("BOB (cont'd)\nHi.") == [.action, .action])
    #expect(Self.elements("@BOB (cont'd)\nHi.") == [.character, .dialogue])
    // An unclosed parenthesis is not an extension; the name is judged on its own merits.
    #expect(Self.elements("BOB (V.O.\nHi.") == [.character, .dialogue])
    #expect(Self.fullScan("BOB (V.O.\nHi.").lineRecords[0].contentRange == 0..<9)
  }

  @Test("The dual-dialogue caret is preserved in the record and never inside the name")
  func dualDialogueCaretIsPreserved() {
    // AGENTS.md: line records must be lossless for the writer, and the caret is named in
    // that list beside the forced-element markers. It is kept the same way they are — out
    // of the content range, and emitted as a marker span carrying the cue's own kind.
    let dual = Self.fullScan("JANE ^\nAnd hello.")
    let record = dual.lineRecords[0]
    #expect(record.element == .character)
    #expect(record.range == 0..<7, "the line, terminator included")
    #expect(record.contentRange == 0..<4, "the caret and the space before it are not the name")

    #expect(dual.spans[0].range == 0..<4)
    #expect(dual.spans[0].kind == .character)
    #expect(dual.spans[0].role == .content)
    #expect(dual.spans[1].range == 4..<6, "` ^` is one marker span")
    #expect(dual.spans[1].kind == .character)
    #expect(dual.spans[1].role == .marker)

    // Stated as the writer will state it: the caret is recoverable from the record against
    // the source, byte for byte.
    let text = "JANE ^\nAnd hello."
    let trailing = Array(text.utf16)[record.contentRange.upperBound..<(record.range.upperBound - 1)]
    #expect(String(decoding: trailing, as: UTF16.self) == " ^")

    // Tight, and with an extension, and forced.
    #expect(Self.fullScan("JANE^\nHi.").lineRecords[0].contentRange == 0..<4)
    let withExtension = Self.fullScan("BOB (V.O.) ^\nHi.")
    #expect(withExtension.lineRecords[0].contentRange == 0..<3)
    #expect(withExtension.spans[1].range == 3..<10)
    #expect(withExtension.spans[1].kind == .characterExtension)
    #expect(withExtension.spans[2].range == 10..<12)
    #expect(withExtension.spans[2].role == .marker)
    #expect(Self.elements("@Jane ^\nHi.") == [.character, .dialogue])
  }

  @Test("A cue needs a name, and a name needs a letter")
  func cuesNeedANameWithALetterInIt() {
    // The spec's "character names must include at least one alphabetical character".
    #expect(Self.elements("23\nHello.") == [.action, .action])
    #expect(Self.elements("R2D2\nHello.") == [.character, .dialogue], "R2D2 works, 23 does not")
    // A line that is nothing but a parenthetical has no name in front of the `(`, so it is
    // not a cue however uppercase it is.
    #expect(Self.elements("(BEAT)\nHello.") == [.action, .action])
    #expect(Self.elements("^\nHello.") == [.action, .action])
  }

  // MARK: - Parentheticals and dialogue

  @Test("A parenthetical is a parenthetical only inside a dialogue block")
  func parentheticalsNeedASpeaker() {
    let block = Self.fullScan("BOB\n(beat)\nHello there.\n")
    #expect(block.lineRecords.map(\.element) == [.character, .parenthetical, .dialogue, .blank])
    #expect(
      block.lineRecords[1].contentRange == 4..<10, "the parentheses print, so they are content")

    // Outside a block there is no speaker to modify, and Fountain does not invent one.
    #expect(Self.elements("(beat)\nHello there.") == [.action, .action])

    // Deviation 6: a parenthetical may be indented, because inside a dialogue block there
    // is no whitespace-preserving element for the indent rule to protect.
    let indented = Self.fullScan("BOB\n  (beat)\nHi.\n")
    #expect(indented.lineRecords.map(\.element) == [.character, .parenthetical, .dialogue, .blank])
    #expect(indented.lineRecords[1].contentRange == 6..<12, "the indent is not content")
    #expect(indented.spans[2].range == 4..<6)
    #expect(indented.spans[2].kind == .parenthetical)
    #expect(indented.spans[2].role == .marker)
    #expect(indented.spans[3].range == 6..<12)
    #expect(indented.spans[3].role == .content)
  }

  @Test("A dialogue block runs until a blank line, and blank lines end it")
  func dialogueBlockExtent() {
    let text = """
      INT. HOUSE - DAY
      Bob steps in.

      BOB
      (beat)
      Hello there.
      This is still me talking.

      Action again.
      """
    #expect(
      Self.elements(text) == [
        .sceneHeading, .action, .blank,
        .character, .parenthetical, .dialogue, .dialogue, .blank,
        .action,
      ])

    // A whitespace-only line is blank (deviation 2), so it closes the block too.
    #expect(
      Self.elements("BOB\nHello.\n   \nNot dialogue.")
        == [.character, .dialogue, .blank, .action])
  }

  @Test("A cue under a cue is dialogue, not a second speaker")
  func aCueUnderACueIsDialogue() {
    // The block-boundary condition, from the other side: `JANE` is ALL-CAPS with a
    // non-blank line under it and is still not a cue, because the line above it is not
    // blank. Fountain has no way to stack two speakers without a blank line, and a scanner
    // that allowed it would swallow the first speaker's first line.
    #expect(Self.elements("BOB\nJANE\nHello.") == [.character, .dialogue, .dialogue])
    #expect(
      Self.elements("BOB\nHi.\n\nJANE\nHello.")
        == [.character, .dialogue, .blank, .character, .dialogue])
    // Forcing overrides it, which is what forcing is for.
    #expect(Self.elements("BOB\n@JANE\nHello.") == [.character, .character, .dialogue])
  }

  @Test("Lyrics continue a dialogue block; a lyric on its own does not open one")
  func lyricsInsideAndOutsideADialogueBlock() {
    // Fountain's own lyrics example is a song sung inside a dialogue block, so a `~` line
    // under a cue is a lyric AND the block stays open under it.
    #expect(
      Self.elements("BOB\n~I've got a golden ticket\nStill me talking.")
        == [.character, .lyrics, .dialogue])
    // But a lyric at the top of a page must not make the line under it dialogue.
    #expect(Self.elements("~Willy Wonka\nBob steps back.") == [.lyrics, .action])
  }

  @Test("Any element that is not dialogue-shaped closes the block")
  func nonDialogueElementsCloseTheBlock() {
    // Forced elements beat the dialogue branch and end the block, so the line after them
    // is judged as if the cue had never happened. Written out per element, because the
    // switch in `withState` is exactly where a future construct gets forgotten.
    #expect(
      Self.elements("BOB\nHi.\n!Bob shrugs.\nStill action.") == [
        .character, .dialogue, .action, .action,
      ])
    #expect(
      Self.elements("BOB\nHi.\n# Act Two\nStill action.") == [
        .character, .dialogue, .section, .action,
      ])
    #expect(
      Self.elements("BOB\nHi.\n= a synopsis\nStill action.") == [
        .character, .dialogue, .synopsis, .action,
      ])
    #expect(
      Self.elements("BOB\nHi.\n===\nStill action.") == [.character, .dialogue, .pageBreak, .action])
    #expect(
      Self.elements("BOB\nHi.\n.INT. HOUSE\nStill action.") == [
        .character, .dialogue, .sceneHeading, .action,
      ])
    #expect(
      Self.elements("BOB\nHi.\n> CUT TO:\nStill action.") == [
        .character, .dialogue, .transition, .action,
      ])
    #expect(
      Self.elements("BOB\nHi.\n>THE END<\nStill action.") == [
        .character, .dialogue, .centered, .action,
      ])
  }

  // MARK: - Retroactive classification: the lookahead, incrementally

  /// Typing a word on the line **after** `BOB` promotes `BOB` from action to a character
  /// cue, and the incremental result equals a full scan of the same text.
  ///
  /// This is the sortie's headline assertion and it is written the only way that can catch
  /// anything: the expected `ElementKind`s are written out by hand. The gate property in
  /// `ScanGateTests` runs the same grammar on both sides of its comparison and stays green
  /// for a grammar that never recognizes a cue at all — so "the gate passes" is not
  /// evidence of any of this and must never be cited as such.
  @Test("Typing a word under `BOB` retroactively makes it a character cue")
  func typingUnderAnAllCapsLinePromotesIt() {
    let before = "BOB\n\n"
    var scanner = IncrementalScanner(grammar: FountainGrammar())
    let base = scanner.fullScan(before)
    ScanInvariants.check(base, text: before, editedRange: nil, "promotion base")
    #expect(
      base.lineRecords.map(\.element) == [.action, .blank, .blank],
      "with a blank line under it, `BOB` is action")

    // Type `Hello` on the line after `BOB`. Nothing about this edit points at the line
    // above it; the backward extent — `max(1, lookahead)` — is the only reason that line
    // is rescanned at all.
    let typed = ScanInvariants.splice(before, 4..<4, "Hello")
    #expect(typed == "BOB\nHello\n")
    let promoted = scanner.incrementalScan(
      TextEdit(range: 4..<4, replacementLength: 5), in: typed)
    ScanInvariants.check(promoted, text: typed, editedRange: 4..<9, "promotion edit")

    #expect(promoted.lines.contains(0), "the line above the edit was not even rescanned")
    let cue = promoted.lineRecords.first { $0.index == 0 }
    #expect(cue?.element == .character, "`BOB` was not repainted as a cue")
    #expect(cue?.contentRange == 0..<3)
    #expect(promoted.lineRecords.first { $0.index == 1 }?.element == .dialogue)

    // …and the incremental result equals the full-scan result for that edit.
    var fresh = IncrementalScanner(grammar: FountainGrammar())
    let full = fresh.fullScan(typed)
    ScanInvariants.check(full, text: typed, editedRange: nil, "promotion full scan")
    #expect(full.lineRecords.map(\.element) == [.character, .dialogue, .blank])
    ScanInvariants.expectSameElements(
      scanner.startStates, fresh.startStates, "startStates", "promotion")
    ScanInvariants.expectSameElements(
      promoted.lineRecords, full.lineRecords.filter { promoted.lines.contains($0.index) },
      "lineRecords", "promotion")

    // And the whole document as the editor would now have it painted. The window
    // comparison above cannot fail when the window is too *small* — the line wrongly left
    // unpainted is outside the window it compares — and this is the half that can.
    var painted = ScanInvariants.PaintedDocument(base)
    painted.apply(promoted, newLineCount: ScanInvariants.lineCount(of: typed))
    ScanInvariants.expectSameElements(
      painted.lines, ScanInvariants.paintedLines(of: full), "painted document", "promotion")
  }

  @Test("Deleting that word again demotes `BOB` back to action")
  func deletingUnderACueDemotesIt() {
    // The other direction, on the same scanner instance, because an engine that only ever
    // widens on insertion passes the promotion test and fails this one.
    let text = "BOB\nHello\n"
    var scanner = IncrementalScanner(grammar: FountainGrammar())
    let base = scanner.fullScan(text)
    ScanInvariants.check(base, text: text, editedRange: nil, "demotion base")
    #expect(base.lineRecords.map(\.element) == [.character, .dialogue, .blank])

    let deleted = ScanInvariants.splice(text, 4..<9, "")
    #expect(deleted == "BOB\n\n")
    let demoted = scanner.incrementalScan(
      TextEdit(range: 4..<9, replacementLength: 0), in: deleted)
    ScanInvariants.check(demoted, text: deleted, editedRange: 4..<4, "demotion edit")

    #expect(demoted.lines.contains(0))
    #expect(
      demoted.lineRecords.first { $0.index == 0 }?.element == .action,
      "`BOB` stayed painted as a cue after its speaker vanished")

    var fresh = IncrementalScanner(grammar: FountainGrammar())
    let full = fresh.fullScan(deleted)
    ScanInvariants.check(full, text: deleted, editedRange: nil, "demotion full scan")
    #expect(full.lineRecords.map(\.element) == [.action, .blank, .blank])
    ScanInvariants.expectSameElements(
      scanner.startStates, fresh.startStates, "startStates", "demotion")
    ScanInvariants.expectSameElements(
      demoted.lineRecords, full.lineRecords.filter { demoted.lines.contains($0.index) },
      "lineRecords", "demotion")

    var painted = ScanInvariants.PaintedDocument(base)
    painted.apply(demoted, newLineCount: ScanInvariants.lineCount(of: deleted))
    ScanInvariants.expectSameElements(
      painted.lines, ScanInvariants.paintedLines(of: full), "painted document", "demotion")
  }

  @Test("Promotion and demotion survive a round trip on one scanner")
  func promotionRoundTripsOnOneScanner() {
    // Drift only shows up when one scanner is carried across many edits. Four keystrokes,
    // each asserted by name against a hand-written expectation, plus a full-scan
    // comparison of the WHOLE document each time — the window comparison alone cannot fail
    // when the window is too small, because the lines wrongly left alone are outside it.
    let script: [(range: Range<Int>, replacement: String, expected: [ElementKind])] = [
      // Type a line of speech: `BOB` becomes a cue.
      (4..<4, "Hi.", [.character, .dialogue, .blank]),
      // Add a parenthetical under it.
      (7..<7, "\n(beat)", [.character, .dialogue, .parenthetical, .blank]),
      // Take the speech away again: the cue demotes, and `(beat)` — now outside any
      // dialogue block — stops being a parenthetical too.
      (4..<7, "", [.action, .blank, .action, .blank]),
      // Put it back.
      (4..<4, "Hi.", [.character, .dialogue, .parenthetical, .blank]),
    ]

    var text = "BOB\n\n"
    var scanner = IncrementalScanner(grammar: FountainGrammar())
    let base = scanner.fullScan(text)
    ScanInvariants.check(base, text: text, editedRange: nil, "round-trip base")
    #expect(base.lineRecords.map(\.element) == [.action, .blank, .blank])
    var painted = ScanInvariants.PaintedDocument(base)

    for (number, step) in script.enumerated() {
      let next = ScanInvariants.splice(text, step.range, step.replacement)
      let result = scanner.incrementalScan(
        TextEdit(range: step.range, replacementLength: step.replacement.utf16.count), in: next)
      let note = "round-trip step \(number) at \(next.debugDescription)"
      ScanInvariants.check(
        result, text: next,
        editedRange: step.range.lowerBound..<(step.range.lowerBound + step.replacement.utf16.count),
        note)

      var fresh = IncrementalScanner(grammar: FountainGrammar())
      let full = fresh.fullScan(next)
      ScanInvariants.check(full, text: next, editedRange: nil, "full scan — \(note)")
      #expect(full.lineRecords.map(\.element) == step.expected, "\(note)")
      ScanInvariants.expectSameElements(
        scanner.startStates, fresh.startStates, "startStates", note)
      ScanInvariants.expectSameElements(
        result.lineRecords, full.lineRecords.filter { result.lines.contains($0.index) },
        "lineRecords", note)

      painted.apply(result, newLineCount: ScanInvariants.lineCount(of: next))
      ScanInvariants.expectSameElements(
        painted.lines, ScanInvariants.paintedLines(of: full), "painted document", note)
      text = next
    }
  }

  @Test("The dialogue flag is carried across every line of a block, not recomputed")
  func dialogueStateMustBeCarriedAcrossLines() {
    // The counterweight to the gate property, in the shape `ScanGateTests` uses for the
    // fence flag: a grammar that computes `inDialogueBlock` and forgets to carry it agrees
    // with itself perfectly and the gate never notices. Every line below is inside the
    // block by virtue of a cue an arbitrary distance above it, and the last one is the
    // only one whose own text says anything at all.
    let text = "BOB\nOne.\nTwo.\nThree.\nFour.\nFive."
    var scanner = IncrementalScanner(grammar: FountainGrammar())
    let result = scanner.fullScan(text)
    ScanInvariants.check(result, text: text, editedRange: nil, "carried dialogue flag")
    #expect(
      result.lineRecords.map(\.element) == [
        .character, .dialogue, .dialogue, .dialogue, .dialogue, .dialogue,
      ])
    #expect(result.spans.contains { $0.kind == .character && $0.range == 0..<3 })

    // The states themselves: every line after the cue begins in a state that differs from
    // the state line 0 began in, and they are all equal to one another. A grammar that
    // dropped the flag would make all six equal.
    let states = result.lineRecords.map(\.startState)
    #expect(states[0] != states[1], "the cue's end state must differ from the document start")
    #expect(states[2] == states[1])
    #expect(states[5] == states[1])
  }

  @Test("The grammar declares a lookahead of one, in both directions")
  func lookaheadIsDeclared() {
    // Stated directly because it is the thing the engine reads, and because a value the
    // engine reads through a protocol requirement is a value a refactor can silently
    // change. `backwardExtent` is `max(1, lookahead)` by default, and it is what makes the
    // line ABOVE an edit get rescanned — the half of the contract nothing about the edit
    // points at.
    let grammar = FountainGrammar()
    #expect(grammar.lookahead == 1)
    #expect(grammar.backwardExtent == 1)
    #expect(IncrementalScanner(grammar: grammar).backwardWidening == 1)
  }

  // MARK: - A whole page

  @Test("A screenplay page classifies line by line and tiles exactly")
  func aWholePage() {
    let text = """
      # Act One

      = Bob finally tells the truth.

      INT. HOUSE - DAY\r
      Bob steps back. A \u{1F600} on the wall.

      ~Willy Wonka, Willy Wonka

      >THE END<

      CUT TO:

      ===

      .SNIPER SCOPE POV
      """
    let result = Self.fullScan(text)

    #expect(
      result.lineRecords.map(\.element) == [
        .section, .blank,
        .synopsis, .blank,
        .sceneHeading, .action, .blank,
        .lyrics, .blank,
        .centered, .blank,
        .transition, .blank,
        .pageBreak, .blank,
        .sceneHeading,
      ])
    #expect(result.lineRecords[0].depth == 1)

    // Total tiling: every UTF-16 code unit belongs to exactly one span. The CRLF and the
    // astral-plane character are in the fixture because both are where a hand-written
    // scanner drops a code unit.
    #expect(result.spans.reduce(0) { $0 + $1.range.count } == text.utf16.count)
    var cursor = 0
    for span in result.spans {
      #expect(span.range.lowerBound == cursor, "gap or overlap at \(cursor)")
      #expect(!span.range.isEmpty, "empty span at \(cursor)")
      cursor = span.range.upperBound
    }
    #expect(cursor == text.utf16.count)

    IncrementalScannerTests.expectInvariants(result, text: text, editedRange: nil, "fountain page")
  }

  // MARK: - Convergence: the block-boundary bit is real state

  @Test("Deleting a blank line reclassifies the scene heading below it, incrementally")
  func deletingABlankLineDemotesTheHeadingBelowIt() {
    // The assertion the `followsNonBlankLine` design exists to make true. The slug line's
    // text is untouched by this edit; only the line above it changes. A grammar that
    // classified a line from its own text alone would leave it painted as a heading, and
    // — because both sides of the gate test run the same grammar — the gate would agree
    // with it.
    let text = "Bob steps back.\n\nINT. HOUSE - DAY\nHe waits.\n"
    var scanner = IncrementalScanner(grammar: FountainGrammar())
    let before = scanner.fullScan(text)
    ScanInvariants.check(before, text: text, editedRange: nil, "boundary base")
    #expect(
      before.lineRecords.map(\.element) == [.action, .blank, .sceneHeading, .action, .blank])

    // Delete the blank line's terminator, joining nothing but removing the boundary.
    let edited = ScanInvariants.splice(text, 16..<17, "")
    #expect(edited == "Bob steps back.\nINT. HOUSE - DAY\nHe waits.\n")
    let result = scanner.incrementalScan(TextEdit(range: 16..<17, replacementLength: 0), in: edited)
    ScanInvariants.check(result, text: edited, editedRange: 16..<16, "blank line deleted")

    // The heading became action, and the incremental scan repainted it — not merely a
    // full scan of the same text.
    let heading = result.lineRecords.first { $0.range.lowerBound == 16 }
    #expect(heading?.element == .action, "the slug line was not repainted")

    var fresh = IncrementalScanner(grammar: FountainGrammar())
    let full = fresh.fullScan(edited)
    ScanInvariants.check(full, text: edited, editedRange: nil, "blank line deleted, full scan")
    #expect(full.lineRecords.map(\.element) == [.action, .action, .action, .blank])
    ScanInvariants.expectSameElements(
      scanner.startStates, fresh.startStates, "startStates", "blank line deleted")
    ScanInvariants.expectSameElements(
      result.lineRecords, full.lineRecords.filter { result.lines.contains($0.index) },
      "lineRecords", "blank line deleted")
  }

  @Test("Typing a blank line above a slug line promotes it, incrementally")
  func insertingABlankLinePromotesTheLineBelowIt() {
    let text = "Bob steps back.\nINT. HOUSE - DAY\n"
    var scanner = IncrementalScanner(grammar: FountainGrammar())
    let before = scanner.fullScan(text)
    ScanInvariants.check(before, text: text, editedRange: nil, "promote base")
    #expect(before.lineRecords.map(\.element) == [.action, .action, .blank])

    let edited = ScanInvariants.splice(text, 16..<16, "\n")
    let result = scanner.incrementalScan(TextEdit(range: 16..<16, replacementLength: 1), in: edited)
    ScanInvariants.check(result, text: edited, editedRange: 16..<17, "blank line inserted")

    var fresh = IncrementalScanner(grammar: FountainGrammar())
    let full = fresh.fullScan(edited)
    ScanInvariants.check(full, text: edited, editedRange: nil, "blank line inserted, full scan")
    #expect(full.lineRecords.map(\.element) == [.action, .blank, .sceneHeading, .blank])
    ScanInvariants.expectSameElements(
      scanner.startStates, fresh.startStates, "startStates", "blank line inserted")
    ScanInvariants.expectSameElements(
      result.lineRecords, full.lineRecords.filter { result.lines.contains($0.index) },
      "lineRecords", "blank line inserted")
  }

  @Test("A sequence of edits over a screenplay tracks a full scan throughout")
  func editSequenceTracksFullScan() {
    // Drift only shows up when one scanner is carried across many edits, which is how a
    // live editor uses one. Fixed script, no randomness — a seeded generator is the gate
    // suite's, and an unseeded one is nobody's.
    let script: [(Range<Int>, String)] = [
      (0..<0, "INT. HOUSE - DAY\n"),
      (17..<17, "Bob steps back.\n"),
      (33..<33, "\n"),
      (34..<34, "CUT TO:\n"),
      (0..<0, "# Act One\n\n"),
      (11..<11, "Bob waits.\n"),  // pushes the slug line under action
      (11..<22, ""),  // and takes it away again
      (0..<1, "."),  // `# Act One` becomes `. Act One` — a section becomes action
    ]

    var text = ""
    var scanner = IncrementalScanner(grammar: FountainGrammar())
    ScanInvariants.check(scanner.fullScan(text), text: text, editedRange: nil, "sequence base")

    for (range, replacement) in script {
      let next = ScanInvariants.splice(text, range, replacement)
      let result = scanner.incrementalScan(
        TextEdit(range: range, replacementLength: replacement.utf16.count), in: next)
      IncrementalScannerTests.expectInvariants(
        result, text: next,
        editedRange: range.lowerBound..<(range.lowerBound + replacement.utf16.count),
        "fountain sequence at \(next.debugDescription)")

      var fresh = IncrementalScanner(grammar: FountainGrammar())
      let full = fresh.fullScan(next)
      ScanInvariants.check(
        full, text: next, editedRange: nil,
        "fountain sequence full scan at \(next.debugDescription)")
      ScanInvariants.expectSameElements(
        scanner.startStates, fresh.startStates, "startStates",
        "fountain sequence at \(next.debugDescription)")
      ScanInvariants.expectSameElements(
        result.lineRecords, full.lineRecords.filter { result.lines.contains($0.index) },
        "lineRecords", "fountain sequence at \(next.debugDescription)")
      text = next
    }
  }

  // MARK: - Degenerate input

  @Test(
    "Degenerate documents scan without failing",
    arguments: [
      "", "\n", ".", "..", "...", ">", "<", "><", ">>", "=", "==", "===", "#", "~", "!",
      "\r\n\r\n", "   ", "\t\t", "I/E", "INT", "TO:", ">   <",
    ])
  func degenerateDocuments(text: String) {
    let result = Self.fullScan(text)
    #expect(result.spans.reduce(0) { $0 + $1.range.count } == text.utf16.count)
    IncrementalScannerTests.expectInvariants(result, text: text, editedRange: nil, "degenerate")
  }
}
