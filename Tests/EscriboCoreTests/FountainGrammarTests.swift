import Testing

@testable import EscriboCore

/// Fountain's **block** elements: scene headings, action, transitions, centered text,
/// sections, synopses, page breaks, and lyrics.
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
@Suite("Fountain grammar — block elements")
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
