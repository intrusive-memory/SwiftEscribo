import Testing

@testable import EscriboCore

// MARK: - Harness

/// Scan-then-write, through the **public** entry points on both sides.
///
/// The writer's whole contract is stated in bytes, so almost every assertion in this file
/// compares the written document — or one line of it — against a string written out by
/// hand. That is deliberate and it is the lesson of this mission: a writer test that feeds
/// the output back into the parser and compares parse trees is blind to anything the
/// parser drops, and would be green for a writer that deleted a construct the scanner
/// happens to ignore. Re-parsing appears exactly twice below, both times as a *second*
/// assertion alongside a byte comparison, never as the only one.
enum FountainWriterHarness {

  /// Full-scans `source` as Fountain and writes it back out.
  static func roundTrip(_ source: String) -> String {
    var scanner = EscriboScanner(language: .fountain)
    let result = scanner.fullScan(source)
    return FountainWriter().write(result.lineRecords, from: source)
  }

  /// Every line's `(element, depth)`, in order.
  static func shape(of source: String) -> [String] {
    var scanner = EscriboScanner(language: .fountain)
    let result = scanner.fullScan(source)
    return result.lineRecords.map { "\($0.element.rawValue):\($0.depth)" }
  }

  /// The document's lines, terminators excluded, for a per-line assertion.
  ///
  /// Code units are accumulated and decoded a line at a time rather than a unit at a time:
  /// decoding one half of a surrogate pair yields a replacement character, and the corpus
  /// contains astral-plane dialogue.
  static func lines(_ document: String) -> [String] {
    var out: [String] = []
    var current: [UInt16] = []
    var units = Array(document.utf16)[...]
    while let unit = units.first {
      units = units.dropFirst()
      if unit == 0x0D {
        if units.first == 0x0A { units = units.dropFirst() }
        out.append(String(decoding: current, as: UTF16.self))
        current = []
      } else if unit == 0x0A {
        out.append(String(decoding: current, as: UTF16.self))
        current = []
      } else {
        current.append(unit)
      }
    }
    out.append(String(decoding: current, as: UTF16.self))
    return out
  }

  /// Every `\n` in `document` that is **not** preceded by a `\r`.
  ///
  /// Counted rather than asserted directly so a failure reports how many there were. A
  /// document written from a CRLF source must have none: `\r\n` is one terminator of two
  /// code units and is never normalized (REQUIREMENTS.md § Line termination).
  static func bareLineFeeds(in document: String) -> Int {
    let units = Array(document.utf16)
    var count = 0
    for offset in units.indices where units[offset] == 0x0A {
      if offset == 0 || units[offset - 1] != 0x0D { count += 1 }
    }
    return count
  }
}

// MARK: - Terminators

@Suite("Fountain writer — terminators")
struct FountainWriterTerminatorTests {

  /// **Exit criterion.** A CRLF document written from its records still contains `\r\n`
  /// and no bare `\n`.
  ///
  /// The document is chosen so that the writer **cannot** satisfy this by copying the
  /// source: `#   ACT ONE` must come back as `# ACT ONE`, `=====` as `===`, and
  /// `BOB   ^` as `BOB ^`. A writer that returned its input unchanged — the degenerate
  /// implementation this exit criterion is otherwise blind to — fails the first
  /// assertion. A writer that normalized correctly but emitted `\n` fails the last two.
  @Test("A CRLF document keeps every `\\r\\n` and gains no bare `\\n`, while still normalizing")
  func crlfSurvivesTheWriteAndNormalizationStillHappens() {
    let source =
      "INT. HOUSE - DAY\r\n"
      + "\r\n"
      + "#   ACT ONE\r\n"
      + "\r\n"
      + "=====\r\n"
      + "\r\n"
      + "BOB   ^\r\n"
      + "Hello.\r\n"

    let written = FountainWriterHarness.roundTrip(source)

    #expect(
      written == "INT. HOUSE - DAY\r\n\r\n# ACT ONE\r\n\r\n===\r\n\r\nBOB ^\r\nHello.\r\n")
    #expect(written.contains("\r\n"))
    #expect(
      FountainWriterHarness.bareLineFeeds(in: written) == 0,
      "\(FountainWriterHarness.bareLineFeeds(in: written)) bare line feeds in the written document")
  }

  /// `\n`, `\r\n`, and a lone `\r` in one document, each written back as itself — with a
  /// page break normalized on the way through so this cannot pass by copying.
  ///
  /// The final line has no terminator and must not acquire one: a trailing terminator
  /// produces a final empty line, so inventing one would add a line to the document.
  @Test("Mixed terminators are each preserved, and a missing final terminator is not invented")
  func mixedTerminatorsSurvive() {
    let source = "=====\r\n===\rrun on\n"
    let written = FountainWriterHarness.roundTrip(source)

    #expect(written == "===\r\n===\rrun on\n")
    #expect(FountainWriterHarness.bareLineFeeds(in: written) == 1)

    let noTerminator = FountainWriterHarness.roundTrip("=====")
    #expect(noTerminator == "===")
  }

  /// The empty document writes as the empty document — one empty line, no bytes.
  @Test("The empty document round-trips to nothing")
  func emptyDocument() {
    #expect(FountainWriterHarness.roundTrip("") == "")
  }
}

// MARK: - Forced markers

@Suite("Fountain writer — forced-element markers")
struct FountainWriterMarkerTests {

  /// **Exit criterion.** `.HOUSE` writes back with its leading period.
  ///
  /// Both halves are asserted, and the second is what makes the first mean anything: the
  /// forced heading keeps its `.` **and** the natural heading does not acquire one. A
  /// writer that emitted a period unconditionally passes the exit criterion as literally
  /// worded and fails here. The trailing spaces on the forced line are there so a
  /// copy-the-source writer fails too.
  @Test("A forced scene heading keeps its period; a natural one does not grow one")
  func forcedSceneHeadingKeepsItsPeriod() {
    #expect(FountainWriterHarness.roundTrip(".HOUSE   \n") == ".HOUSE\n")
    #expect(FountainWriterHarness.roundTrip("INT. HOUSE - DAY   \n") == "INT. HOUSE - DAY\n")

    // The distinction is not merely textual: the forced line is still a scene heading
    // after the write, and `.HOUSE` is not a scene heading by any natural rule — its
    // period is the only reason it is one.
    #expect(FountainWriterHarness.shape(of: ".HOUSE   \n").first == "sceneHeading:0")
    #expect(FountainWriterHarness.shape(of: ".HOUSE\n").first == "sceneHeading:0")
  }

  /// A forced action's `!`, and the whitespace action is entitled to keep.
  ///
  /// Action is the one Fountain element whose internal and trailing whitespace is what the
  /// writer meant, so this line must come back byte for byte — including the two spaces
  /// after the `!` and the three at the end. A writer that trimmed every element uniformly
  /// fails here, and a writer that dropped the `!` demotes forced action to whatever the
  /// text would otherwise have been.
  @Test("Forced action keeps its `!` and every space around it")
  func forcedActionIsVerbatim() {
    #expect(FountainWriterHarness.roundTrip("!  spaced   \n") == "!  spaced   \n")
    #expect(FountainWriterHarness.roundTrip("!INT. HOUSE\n") == "!INT. HOUSE\n")
    #expect(FountainWriterHarness.shape(of: "!INT. HOUSE\n").first == "action:0")
  }

  /// A forced transition keeps its `>`; a natural one is not given one.
  @Test("A forced transition keeps its `>` and a natural transition stays unmarked")
  func transitionMarkers() {
    #expect(FountainWriterHarness.roundTrip(">CUT TO:\n") == "> CUT TO:\n")
    #expect(FountainWriterHarness.roundTrip("CUT TO:\n") == "CUT TO:\n")
    #expect(FountainWriterHarness.roundTrip(">   burn to white   \n") == "> burn to white\n")
  }
}

// MARK: - The dialogue block

@Suite("Fountain writer — the dialogue block")
struct FountainWriterDialogueTests {

  /// **Exit criterion.** A dual-dialogue caret survives the write.
  ///
  /// Asserted on the emitted bytes, with the caret's spacing normalized from four spaces
  /// to one so a copy-the-source writer cannot pass it, and with the *first* cue asserted
  /// to have no caret so a writer that emitted one unconditionally cannot either. The
  /// caret is not in the cue's content range — a cue's content is the character name alone
  /// — so a writer that emitted only content ranges loses it silently, which is exactly
  /// the loss this criterion exists to catch.
  @Test("A dual-dialogue caret survives, normalized, and is not invented on the first cue")
  func dualDialogueCaretSurvives() {
    let source = "BOB\nHi.\n\nJANE    ^\nHello.\n"
    let written = FountainWriterHarness.roundTrip(source)

    #expect(written == "BOB\nHi.\n\nJANE ^\nHello.\n")

    let lines = FountainWriterHarness.lines(written)
    #expect(lines.count > 3)
    #expect(lines[3] == "JANE ^")
    #expect(lines[0] == "BOB", "the first cue has no caret and must not be given one")
  }

  /// A forced cue keeps its `@`, its extension, and its caret, each separated by exactly
  /// one space.
  @Test("`@McAvoy (V.O.) ^` keeps its at-sign, its extension, and its caret")
  func forcedCueKeepsEverything() {
    #expect(
      FountainWriterHarness.roundTrip("@McAvoy   (V.O.)   ^\nHello.\n")
        == "@McAvoy (V.O.) ^\nHello.\n")

    // The `@` is load-bearing: `McAvoy` is not uppercase, so without the marker the line
    // is action and the line under it is not speech at all.
    #expect(
      Array(FountainWriterHarness.shape(of: "@McAvoy (V.O.) ^\nHello.\n").prefix(2))
        == ["character:0", "dialogue:0"])

    // A natural cue is not given a marker it never had.
    #expect(FountainWriterHarness.roundTrip("BOB (V.O.)\nHello.\n") == "BOB (V.O.)\nHello.\n")
    #expect(FountainWriterHarness.roundTrip("BOB(V.O.)\nHello.\n") == "BOB (V.O.)\nHello.\n")
  }

  /// Parentheticals lose their indent; speech loses its indent and its trailing spaces.
  @Test("A parenthetical and a line of speech are written flush left")
  func dialogueIsDeIndented() {
    let source = "BOB\n    (beat)\n    Hello there.   \n"
    #expect(FountainWriterHarness.roundTrip(source) == "BOB\n(beat)\nHello there.\n")
  }

  /// **DL-163.** De-indenting speech is not unconditionally safe, and this is the case
  /// that proves it.
  ///
  /// `~` is a lyric marker only at the **first** code unit of a line, so `  ~la la la`
  /// inside a dialogue block is dialogue. A writer that de-indented every line of speech
  /// would emit `~la la la`, which the next parse reads as a lyric — the writer would have
  /// changed what the document says, not how it is spelled. The guard in
  /// ``FountainWriter/emitDialogue(units:content:into:)`` keeps the indent on exactly these
  /// lines and nowhere else, which is why the ordinary line below it still loses its own.
  ///
  /// The re-parse here is a second assertion, not the only one: the byte comparison above
  /// it fails on its own if the guard is removed.
  @Test("Speech that begins with a block marker keeps its indent and stays speech")
  func deIndentingNeverPromotesSpeechToAnotherElement() {
    let source = "BOB\n  ~la la la\n  Ordinary speech.\n"
    let written = FountainWriterHarness.roundTrip(source)

    // The lyric-shaped line keeps its indent; the ordinary line beside it loses its own,
    // which is what makes the guard targeted rather than a blanket refusal to normalize.
    #expect(written == "BOB\n  ~la la la\nOrdinary speech.\n")
    #expect(FountainWriterHarness.lines(written)[1] == "  ~la la la")
    #expect(FountainWriterHarness.shape(of: written) == FountainWriterHarness.shape(of: source))

    // Without the guard the line would be written flush left and re-read as a lyric. That
    // is the failure this test exists to catch, stated as the classification it produces.
    #expect(FountainWriterHarness.shape(of: "BOB\n~la la la\n")[1] == "lyrics:0")
  }
}

// MARK: - Body elements

@Suite("Fountain writer — body elements")
struct FountainWriterBodyElementTests {

  /// One canonical spelling per body element, each written out by hand.
  ///
  /// Every pair whose two sides differ is a normalization the writer performs, and is
  /// therefore a case a copy-the-source writer fails. Every pair whose two sides are equal
  /// is a case where the canonical form is the input, and is there to pin the spelling
  /// down — a writer that "canonicalized" `~Willy Wonka` to `~ Willy Wonka` fails it.
  @Test(
    "Every body element writes back in its canonical spelling",
    arguments: [
      // Scene headings.
      (".HOUSE\n", ".HOUSE\n"),
      ("INT. HOUSE - DAY\n", "INT. HOUSE - DAY\n"),
      // Action keeps everything.
      ("   indented action\n", "   indented action\n"),
      ("Bob waits.\n", "Bob waits.\n"),
      // Transitions.
      (">CUT TO:\n", "> CUT TO:\n"),
      ("SMASH CUT TO:\n", "SMASH CUT TO:\n"),
      // Centered text.
      (">THE END<\n", ">THE END<\n"),
      (">   THE END   <\n", ">THE END<\n"),
      // Sections, at their recorded depth.
      ("#   ACT ONE\n", "# ACT ONE\n"),
      ("##Scene one\n", "## Scene one\n"),
      ("####### seven deep\n", "####### seven deep\n"),
      ("#\n", "#\n"),
      // Synopses.
      ("=a synopsis\n", "= a synopsis\n"),
      ("=   a synopsis   \n", "= a synopsis\n"),
      // Page breaks.
      ("===\n", "===\n"),
      ("==========\n", "===\n"),
      ("===   \n", "===\n"),
      // Lyrics.
      ("~Willy Wonka\n", "~Willy Wonka\n"),
      ("~   Willy Wonka   \n", "~Willy Wonka\n"),
      // Blank lines carry no whitespace forward.
      ("Bob waits.\n   \nBob leaves.\n", "Bob waits.\n\nBob leaves.\n"),
    ])
  func bodyElementsWriteCanonically(source: String, expected: String) {
    #expect(FountainWriterHarness.roundTrip(source) == expected)
  }

  /// Normalizing a body element never changes what it is.
  ///
  /// The companion to the table above: that one pins the bytes, this one pins the
  /// classification, and neither implies the other. `=====` shortening to `===` is only
  /// correct because `===` is still a page break; `#   ACT` losing two spaces is only
  /// correct because `# ACT` is still a depth-one section.
  @Test(
    "A normalized element classifies as it did before",
    arguments: [
      "==========\n", "#   ACT ONE\n", "##Scene one\n", "=   a synopsis   \n",
      "~   Willy Wonka   \n", ">   THE END   <\n", ">CUT TO:\n", ".HOUSE   \n",
      "BOB   (V.O.)   ^\nHello.\n", "Bob waits.\n   \nBob leaves.\n",
    ])
  func normalizationPreservesClassification(source: String) {
    let written = FountainWriterHarness.roundTrip(source)
    #expect(
      FountainWriterHarness.shape(of: written) == FountainWriterHarness.shape(of: source),
      "\(source.debugDescription) wrote as \(written.debugDescription) and changed shape")
  }
}

// MARK: - Notes, boneyard, and the title page

@Suite("Fountain writer — verbatim regions")
struct FountainWriterVerbatimTests {

  /// A note is written byte for byte, GLOSA directive and irregular spacing included.
  ///
  /// The spacing inside the note is deliberately non-canonical. Nothing inside a note has
  /// a canonical form — it is commentary layered over the screenplay, and a directive
  /// inside it is a payload another tool parses — so the writer must not touch a single
  /// code unit of it.
  @Test("A note, its GLOSA directive, and its spacing survive untouched")
  func notesAreVerbatim() {
    let source = "[[<pause   dur=\"2s\"   />]]\n"
    #expect(FountainWriterHarness.roundTrip(source) == source)

    let inline = "Bob waits. [[<breath/>]] Then he leaves.   \n"
    #expect(FountainWriterHarness.roundTrip(inline) == inline)
  }

  /// A boneyard, including one that opens on one line and closes on another, and one that
  /// is never closed at all.
  @Test("A boneyard is written verbatim, open or closed, single-line or spanning")
  func boneyardIsVerbatim() {
    let spanning = "/*  struck   out\nstill   struck\nand   out  */\n"
    #expect(FountainWriterHarness.roundTrip(spanning) == spanning)

    let unterminated = "/*  never   closed\nstill   inside\n"
    #expect(FountainWriterHarness.roundTrip(unterminated) == unterminated)
  }

  /// **The Sortie 24 seam.** A title-page key whose value is empty keeps its line.
  ///
  /// Highland 2 writes an empty title-page value as a line containing a lone tab, and since
  /// Sortie 31 that line is a real ``ElementKind/titlePageValue`` record with an **empty
  /// content range** and its bytes intact (DL-130). It is deliberately distinguishable from
  /// a key that was never written at all, and the distinction only survives a round trip if
  /// the writer emits a record whose content is empty rather than skipping it.
  ///
  /// This is not title-page *writing* — the title page is written verbatim here, and giving
  /// it a canonical spelling is Sortie 24's task. What this test pins down is the seam:
  /// whatever Sortie 24 does with these records, the empty-valued key must still be on the
  /// page afterwards, and the line count must not drop by one per empty value.
  @Test("A title-page key with an empty value keeps its line and its bytes")
  func emptyTitlePageValueSurvives() {
    let source =
      "Title: Big Fish\n"
      + "EPISODE:\n"
      + "\t\n"
      + "CREDIT:\n"
      + "\tAct I\n"
      + "\n"
      + "Bob waits.\n"

    let written = FountainWriterHarness.roundTrip(source)

    #expect(written == source)
    #expect(written.contains("EPISODE:\n\t\n"), "the empty value's line is gone")
    #expect(
      FountainWriterHarness.lines(written).count == FountainWriterHarness.lines(source).count,
      "a line was added or lost")
    #expect(FountainWriterHarness.shape(of: written) == FountainWriterHarness.shape(of: source))
  }
}

// MARK: - The corpus

@Suite("Fountain writer — the fixture corpus")
struct FountainWriterCorpusTests {

  /// Writing a real screenplay changes how it is spelled and never what it is.
  ///
  /// One assertion, over ten documents including three vendored screenplays and every
  /// hostile fixture: the written document classifies **line for line** exactly as the
  /// original did, element and depth.
  ///
  /// ## What this is, and what it deliberately is not
  ///
  /// It is **not** the idempotence gate — that is `parse(write(parse(x))) == parse(x)`,
  /// it compares whole records rather than classifications, it has to survive canonical
  /// title-page writing, and it belongs to Sortie 24. This is the weaker property that a
  /// body-element writer can be held to on its own: a transformation that renames an
  /// element is a writer changing the document's meaning, and no amount of "it re-parses
  /// fine" makes that acceptable.
  ///
  /// It is also **not** "write a document's parse back out and get the original bytes",
  /// which is the wrong formulation and is asserted nowhere in this package — not even
  /// spelled out here, because Sortie 24's exit criteria grep this directory for it. These
  /// fixtures are full of non-canonical spellings and the writer normalizes every one.
  ///
  /// The line count is asserted separately from the shape so a writer that dropped a line
  /// says so plainly rather than as a thousand-element array mismatch.
  @Test("Every fixture writes back with its line count and every classification intact",
    arguments: fountainCorpus)
  func writingAFixturePreservesEveryClassification(fixture: FountainFixture) {
    guard fixture.loaded else {
      Issue.record("\(fixture.name) did not load")
      return
    }
    let written = FountainWriterHarness.roundTrip(fixture.text)

    let before = FountainWriterHarness.shape(of: fixture.text)
    let after = FountainWriterHarness.shape(of: written)
    #expect(
      after.count == before.count,
      "\(fixture.name): \(before.count) lines in, \(after.count) out")

    if after != before {
      var index = 0
      while index < min(after.count, before.count), after[index] == before[index] {
        index += 1
      }
      Issue.record(
        """
        \(fixture.name) changed classification at line \(index):
          before: \(index < before.count ? before[index] : "<end>")
          after:  \(index < after.count ? after[index] : "<end>")
        """)
    }
  }

  /// A CRLF fixture, written, still has no bare `\n` anywhere in it.
  ///
  /// The hand-built document in `FountainWriterTerminatorTests` is eight lines; this is the
  /// same property over a whole vendored file, which is where a single mishandled record
  /// would hide.
  @Test("The CRLF fixture is written with no bare line feed anywhere")
  func crlfFixtureHasNoBareLineFeeds() {
    guard let fixture = fountainCorpus.first(where: { $0.name == "crlf" }) else {
      Issue.record("the crlf fixture is missing from the corpus")
      return
    }
    #expect(
      FountainWriterHarness.bareLineFeeds(in: fixture.text) == 0,
      "the fixture itself is not pure CRLF; this test would prove nothing")

    let written = FountainWriterHarness.roundTrip(fixture.text)
    #expect(written.contains("\r\n"))
    #expect(FountainWriterHarness.bareLineFeeds(in: written) == 0)
  }
}
