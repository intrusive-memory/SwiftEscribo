import Testing

@testable import EscriboCore

/// Hand-written classifications for every hostile fixture in the corpus.
///
/// ## Why this file exists next to the golden snapshots
///
/// `FountainFixtureCorpusTests` proves two things and neither is correctness. Its
/// `incrementalScan == fullScan` replay runs the *same* grammar on both sides, so it is
/// structurally incapable of noticing a line classified wrong — the gate has been
/// falsified against its own interest five separate times on this package while staying
/// green. Its golden snapshots took their expected values from running the scanner, so
/// they are green for any implementation that has not *changed*, correct or not.
///
/// Everything below was instead written out by hand from the fixture bytes, before the
/// scanner was run on them. That is the only property that makes an expectation able to
/// fail against a scanner that was wrong from the day it was written, and it is why the
/// hostile fixtures were authored small enough to enumerate line by line.
@Suite("Fountain hostile fixtures — hand-written classifications")
struct FountainHostileFixtureTests {

  // MARK: - Helpers

  /// The named fixture, or a recorded failure.
  static func fixture(_ name: String, sourceLocation: SourceLocation = #_sourceLocation)
    -> FountainFixture?
  {
    guard let found = fountainCorpus.first(where: { $0.name == name }), found.loaded else {
      Issue.record("fixture \(name) is missing from the corpus", sourceLocation: sourceLocation)
      return nil
    }
    return found
  }

  /// Every ``SpanKind/text`` span that is not a line terminator, as the text it covers.
  ///
  /// The filter is necessary and is itself a fact worth writing down: a line's terminator
  /// is emitted as a `.text` span, because spans **exactly tile** the scanned range and a
  /// terminator is part of that range. So `texts(.text, …)` on any multi-line document
  /// returns one `"\n"` (or `"\r\n"`, or `"\r"`) per line before it returns anything a
  /// malformed-markup assertion is about. Filtering them out here rather than asserting
  /// around them keeps the malformed-GLOSA expectations legible.
  static func malformedMarkupTexts(in result: ScanResult, of source: String) -> [String] {
    FountainRegionTests.texts(.text, in: result, of: source)
      .filter { $0.contains { $0 != "\n" && $0 != "\r" && $0 != "\r\n" } }
  }

  /// Asserts the exact, ordered element classification of every line of `name`.
  static func expectElements(
    _ name: String,
    _ expected: [ElementKind],
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    guard let fixture = Self.fixture(name, sourceLocation: sourceLocation) else { return }
    let result = FountainFixtures.fullScan(fixture, sourceLocation: sourceLocation)
    ScanInvariants.expectSameElements(
      result.lineRecords.map(\.element), expected, "elements", "fixture \(name)",
      sourceLocation: sourceLocation)
  }

  // MARK: - An ALL-CAPS line at end of file

  /// `SHOUTING AT THE VOID` is the last line of the document and has no terminator.
  ///
  /// It is **action**, not a character cue, and the distinction is the whole Fountain
  /// lookahead trap: a cue is an ALL-CAPS line recognized only by what *follows* it, and
  /// nothing follows this one. `BOB` four lines above it is a cue for exactly the opposite
  /// reason. A grammar that keys on capitalization alone gets one of the two wrong and
  /// this test names which.
  @Test("An ALL-CAPS line at EOF is action; an ALL-CAPS line with dialogue under it is a cue")
  func allCapsAtEndOfFileIsNotACue() {
    Self.expectElements(
      "caps_at_eof",
      [
        .sceneHeading,  // INT. HOUSE - DAY
        .blank,
        .action,  // Bob waits by the door.
        .blank,
        .character,  // BOB — a following non-blank line makes it a cue
        .dialogue,  // Hello there.
        .blank,
        .action,  // SHOUTING AT THE VOID — nothing follows, so not a cue
      ])
  }

  // MARK: - CRLF throughout

  /// Every line ends `\r\n`, the document ends without a terminator, and the
  /// classification is identical to what the same document with LF terminators produces.
  ///
  /// `\r\n` is one terminator and two code units, never normalized (AGENTS.md § Things
  /// that look like details and are not). A grammar that reads the trailing `\r` as
  /// content sees `CUT TO:\r` — which does not end in a colon — and misclassifies the
  /// transition. That is the assertion this fixture is here for.
  @Test("A CRLF document classifies exactly as its LF twin, transitions included")
  func crlfDocumentClassifiesIdentically() {
    Self.expectElements(
      "crlf",
      [
        .sceneHeading,  // INT. OFFICE - NIGHT
        .blank,
        .action,  // Bob types.
        .blank,
        .character,  // BOB
        .dialogue,  // This file uses CRLF.
        .blank,
        .transition,  // CUT TO:  — only if the trailing \r is not content
        .blank,
        .action,  // ENDING IN CAPS — at EOF, so not a cue
      ])
  }

  /// The `\r` of every `\r\n` is outside the line's content range.
  ///
  /// Stated separately from the classification above because it is the fact the
  /// classification silently depends on, and because a writer reads content ranges back
  /// to reconstruct the document: a content range that swallowed the `\r` would round-trip
  /// a document with a doubled terminator.
  @Test("`\\r\\n` is one terminator: neither code unit is inside a content range")
  func crlfTerminatorIsExcludedFromContent() {
    guard let fixture = Self.fixture("crlf") else { return }
    let units = Array(fixture.text.utf16)
    let result = FountainFixtures.fullScan(fixture)

    for record in result.lineRecords {
      for offset in record.contentRange {
        #expect(
          units[offset] != 0x0D && units[offset] != 0x0A,
          "line \(record.index) content range covers a terminator at \(offset)")
      }
    }
    // And the terminators really are there — otherwise the loop above is vacuous.
    #expect(units.filter { $0 == 0x0D }.count == 9, "the fixture must carry nine CRs")
    #expect(units.filter { $0 == 0x0A }.count == 9, "the fixture must carry nine LFs")
  }

  // MARK: - Mixed terminators

  /// LF, CRLF, and a **lone CR** in one document.
  ///
  /// The lone CR is the one that gets forgotten: `Bob orders a drink.\rBob drinks it.` is
  /// two lines, and a scanner that only splits on `\n` reads it as one. Two consecutive
  /// action lines rather than one is exactly what distinguishes the two readings, which is
  /// why the fixture has that shape.
  @Test("A lone CR terminates a line, and LF, CRLF, and CR coexist in one document")
  func mixedTerminatorsAllTerminate() {
    Self.expectElements(
      "mixed_terminators",
      [
        .sceneHeading,  // INT. BAR - DAY        \n
        .blank,  //                        \n
        .action,  // Bob orders a drink.   \r   <- lone CR
        .action,  // Bob drinks it.        \n
        .blank,  //                        \r\n
        .character,  // BOB                    \r   <- lone CR
        .dialogue,  // Mixed terminators here.\n
        .blank,  //                        \n
        .transition,  // CUT TO:                \r\n
        .blank,  // the final empty line a trailing terminator produces
      ])
  }

  // MARK: - Astral-plane characters in dialogue

  /// Emoji and a Deseret capital — both surrogate pairs in UTF-16 — inside dialogue,
  /// action, and a dual-dialogue block.
  ///
  /// The classification half is ordinary. The half that matters is that no span boundary
  /// and no dirty-range bound falls between a high and a low surrogate: a boundary through
  /// a pair is a range `setAttributes(_:range:)` rounds outward, so the attributes applied
  /// would not be the attributes computed. `ScanInvariants.check` asserts it on every scan
  /// this suite performs; this fixture is what gives it something to assert on.
  @Test("Astral-plane dialogue classifies normally and splits no surrogate pair")
  func astralPlaneDialogueIsSafe() {
    Self.expectElements(
      "astral_dialogue",
      [
        .sceneHeading,  // INT. SPACE STATION - NIGHT
        .blank,
        .action,  // Bob 😀 waves at 𐐷 the console.
        .blank,
        .character,  // BOB
        .dialogue,  // 😀😀 Hello there 𐐷.
        .blank,
        .character,  // JANE ^ — dual dialogue
        .dialogue,  // 𐐷𐐷𐐷 And hello to you 😀.
        .blank,
        .transition,  // CUT TO:
        .blank,
      ])

    guard let fixture = Self.fixture("astral_dialogue") else { return }
    let units = Array(fixture.text.utf16)
    // The fixture must actually contain surrogate pairs, or every assertion above about
    // them is vacuous. Five emoji and four Deseret capitals, counted off the file.
    let highSurrogates = units.filter { (0xD800...0xDBFF).contains($0) }.count
    #expect(highSurrogates == 9, "\(highSurrogates) surrogate pairs, expected 9")

    let result = FountainFixtures.fullScan(fixture)
    for span in result.spans {
      #expect(!ScanInvariants.splitsSurrogatePair(at: span.range.lowerBound, in: units))
      #expect(!ScanInvariants.splitsSurrogatePair(at: span.range.upperBound, in: units))
    }
  }

  // MARK: - An unterminated boneyard

  /// `/*` with no `*/` anywhere below it strikes out the rest of the document, including
  /// a scene heading and a whole dialogue block that would otherwise classify.
  ///
  /// "An unterminated construct scans to the end of the document" is `EscriboScanner`'s
  /// documented totality rule, and this is the Fountain construct where getting it wrong
  /// is most visible: a grammar that lets a blank line close a boneyard produces a live
  /// scene heading in the middle of struck-out text.
  @Test("An unterminated boneyard strikes out every line below it, blank lines included")
  func unterminatedBoneyardRunsToEndOfDocument() {
    Self.expectElements(
      "unterminated_boneyard",
      [
        .sceneHeading,  // INT. HOUSE - DAY
        .blank,
        .action,  // Bob waits.
        .blank,
        .boneyard,  // /* struck out from here
        .boneyard,  // INT. NOWHERE - NIGHT   — struck, not a scene heading
        .boneyard,  // (blank, but inside the region)
        .boneyard,  // BOB                    — struck, not a cue
        .boneyard,  // This line never comes back.
        .boneyard,  // the final empty line, still inside the region
      ])
  }

  // MARK: - Malformed GLOSA

  /// Six malformed or non-directive notes and one well-formed pair, in one document.
  ///
  /// Every expectation is stated as the **text** each span covers, read off the fixture by
  /// hand, because that is how a consumer reads a span back and because an offset written
  /// out by hand for a seventeen-line file is an offset transcribed wrong. The rule being
  /// asserted is the one Sortie 16 settled: malformed markup degrades to
  /// ``SpanKind/text``, never to a gap, never to a crash, and never to a whitelist
  /// decision about whether `breath` is a real tag.
  @Test("Malformed GLOSA degrades to text, and only well-formed directives yield structure")
  func malformedGlosaDegradesToText() {
    Self.expectElements(
      "malformed_glosa",
      [
        .sceneHeading,  // INT. STUDIO - NIGHT
        .blank,
        .note,  // [[<breath length=>]]              — no value
        .blank,
        .note,  // [[<breath length="4s"]]           — no tag closer
        .blank,
        .note,  // [[< not a tag at all]]            — `<` then a space
        .blank,
        .note,  // [[<breath length='4s'/> and <shot/>]]
        .blank,
        .note,  // [[</SceneContext>]]               — a bare closing tag
        .blank,
        .note,  // [[<9lives/>]]                     — `<` then a digit
        .blank,
        .character,  // NARRADOR
        .dialogue,  // Something spoken.
        .blank,
      ])

    guard let fixture = Self.fixture("malformed_glosa") else { return }
    let result = FountainFixtures.fullScan(fixture)
    let source = fixture.text

    // Only two lines contain a structurally complete directive, and between them they
    // carry three tag names.
    #expect(
      FountainRegionTests.texts(.glosaTag, in: result, of: source) == [
        "breath", "shot", "SceneContext",
      ])
    #expect(
      FountainRegionTests.texts(.glosaAttributeName, in: result, of: source) == ["length"])
    #expect(
      FountainRegionTests.texts(.glosaAttributeValue, in: result, of: source) == ["4s"])

    // The two malformed directives, each collapsed to one `.text` span running to the
    // recovery point — the next `>` if there is one, the end of the note's content if not.
    #expect(
      Self.malformedMarkupTexts(in: result, of: source) == [
        "<breath length=>", "<breath length=\"4s\"",
      ])

    // What was never markup at all stays note prose, including the `<` that opened it.
    #expect(
      FountainRegionTests.texts(.note, in: result, of: source) == [
        "< not a tag at all", " and ", "<9lives/>",
      ])

    // The structural punctuation of the two well-formed lines, in order. A single quote is
    // as good as a double one, and the whitespace that separates a tag from its attribute
    // is punctuation rather than part of either.
    #expect(
      FountainRegionTests.texts(.glosaPunctuation, role: .marker, in: result, of: source) == [
        "<", " ", "='", "'", "/>", "<", "/>", "</", ">",
      ])
  }

  // MARK: - Multi-line GLOSA — DL-120

  /// **DL-120, asserted as it actually behaves rather than as it ought to.**
  ///
  /// Sortie 15 shipped notes that span lines; Sortie 16 scanned GLOSA **per line**, with
  /// no cross-line state at all (`GlosaScanner` § Scope: one content chunk, no cross-line
  /// state). Those two facts have not been reconciled, and this fixture is where the gap
  /// shows. Two distinct consequences, both asserted below:
  ///
  /// 1. **A tag pair spanning lines is not a pair.** `<SceneContext>` on one line and
  ///    `</SceneContext>` two lines below produce two independent tag spans and nothing
  ///    that relates them. The prose between them carries no mark of being inside the
  ///    element. Nothing is *wrong* on any single line — but a consumer that wants the
  ///    region has to reconstruct it, and no line record or span says where it is.
  /// 2. **A directive split across lines is destroyed.** `<breath` on one line with
  ///    `length="4s"/>` on the next degrades the opening to ``SpanKind/text`` — correct
  ///    behavior for a chunk scanner, and a silent loss of a directive a screenwriter
  ///    plainly wrote. The continuation line is ordinary note prose: `length` is not an
  ///    attribute name and `4s` is not an attribute value.
  ///
  /// This test is deliberately **descriptive**. Sortie 17 is a fixture sortie and does not
  /// touch grammar. If Sortie 30 decides multi-line directives should be recognized, this
  /// is the test that will go red and it should be rewritten then — not deleted, and not
  /// weakened now to be true either way.
  @Test("DL-120: GLOSA is scanned per line, so a directive spanning lines is not recognized")
  func multiLineGlosaIsNotRecognizedAsAPair() {
    Self.expectElements(
      "multiline_glosa",
      [
        .sceneHeading,  // INT. HOUSE - DAY
        .blank,
        .note,  // [[<SceneContext>
        .note,  // Bob is nervous about the meeting.
        .note,  // </SceneContext>]]
        .blank,
        .note,  // [[<breath
        .note,  // length="4s"/>]]
        .blank,
        .character,  // NARRADOR
        .dialogue,  // Something spoken.
        .blank,
      ])

    guard let fixture = Self.fixture("multiline_glosa") else { return }
    let result = FountainFixtures.fullScan(fixture)
    let source = fixture.text

    // Consequence 1: both halves of the pair are scanned, independently. Two tag spans
    // with the same name and no relation between them.
    #expect(
      FountainRegionTests.texts(.glosaTag, in: result, of: source) == [
        "SceneContext", "SceneContext",
      ])
    // The line between them is plain note prose — nothing marks it as inside the element.
    #expect(
      FountainRegionTests.texts(.note, in: result, of: source).contains(
        "Bob is nervous about the meeting."))

    // Consequence 2: the split directive. The opening is `.text`, and the continuation is
    // prose rather than an attribute.
    #expect(Self.malformedMarkupTexts(in: result, of: source) == ["<breath"])
    #expect(
      FountainRegionTests.texts(.note, in: result, of: source).contains("length=\"4s\"/>"))
    // Stated as an absence, because the absence is the whole finding: no attribute
    // structure survives the line break.
    #expect(FountainRegionTests.texts(.glosaAttributeName, in: result, of: source).isEmpty)
    #expect(FountainRegionTests.texts(.glosaAttributeValue, in: result, of: source).isEmpty)
  }
}
