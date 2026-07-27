import Testing

@testable import EscriboCore

// MARK: - An oracle for the title page

/// Reads a document's title page **without** the scanner and **without** the writer.
///
/// Every assertion below that says "the keys survived" needs a second opinion about what
/// the keys were, and taking that opinion from the scanner would make the test a
/// restatement: a scanner that dropped `verbsCovered` would report that `verbsCovered` was
/// never there, and the comparison would be green. So the region rules are re-implemented
/// here, by hand, from ``FountainGrammar``'s documented deviations 10, 10a, and 11 — the
/// title page begins only on line 0, needs corroboration when its first key has no inline
/// value, runs to the first **genuinely empty** line, and takes a key to be everything
/// before the first colon of a line that does not begin with whitespace.
///
/// This is a deliberate duplication and it is the point. Two independent readings that
/// agree on every title-page line of ten committed documents is evidence; one reading
/// compared against itself is not.
enum TitlePageOracle {

  private static let space: UInt16 = 0x20
  private static let tab: UInt16 = 0x09
  private static let colon: UInt16 = 0x3A

  private static func isSpaceOrTab(_ unit: UInt16) -> Bool { unit == space || unit == tab }

  /// Whitespace-only, empty included — ``FountainGrammar``'s body test.
  static func isBlank(_ line: String) -> Bool { line.utf16.allSatisfy(isSpaceOrTab) }

  /// The offset of the colon ending this line's key, or `nil` when the line carries none.
  static func firstColon(_ line: String) -> Int? {
    let units = Array(line.utf16)
    guard let first = units.first, !isSpaceOrTab(first) else { return nil }
    var offset = 0
    while offset < units.count, units[offset] != colon {
      offset += 1
    }
    guard offset >= 1, offset < units.count else { return nil }
    return offset
  }

  /// Deviation 11: whether line 0 opens a title page at all.
  static func opensTitlePage(_ lines: [String]) -> Bool {
    guard let first = lines.first, let colonAt = firstColon(first) else { return false }
    let units = Array(first.utf16)
    for offset in (colonAt + 1)..<units.count where !isSpaceOrTab(units[offset]) { return true }
    guard lines.count > 1, !isBlank(lines[1]) else { return false }
    let ahead = Array(lines[1].utf16)
    return isSpaceOrTab(ahead[0]) || firstColon(lines[1]) != nil
  }

  /// The lines of the title-page region, terminators excluded. Empty when there is none.
  static func region(of document: String) -> [String] {
    let lines = FountainWriterHarness.lines(document)
    guard opensTitlePage(lines) else { return [] }
    var out: [String] = []
    for line in lines {
      // Deviation 10a: the terminator is a *genuinely* empty line. A lone tab is an empty
      // value and the region continues past it.
      if line.isEmpty { break }
      out.append(line)
    }
    return out
  }

  /// Every key, in document order, exactly as spelled.
  static func keys(of document: String) -> [String] {
    region(of: document).compactMap { line in
      guard let colonAt = firstColon(line) else { return nil }
      return String(decoding: Array(line.utf16)[0..<colonAt], as: UTF16.self)
    }
  }

  /// Every **non-empty** value, in document order, trimmed of the whitespace that
  /// surrounds it — the same set of strings the scanner emits a value span for.
  static func values(of document: String) -> [String] {
    region(of: document).compactMap { line in
      let units = Array(line.utf16)
      let start = firstColon(line).map { $0 + 1 } ?? 0
      var lower = start
      while lower < units.count, isSpaceOrTab(units[lower]) { lower += 1 }
      var upper = units.count
      while upper > lower, isSpaceOrTab(units[upper - 1]) { upper -= 1 }
      guard upper > lower else { return nil }
      return String(decoding: units[lower..<upper], as: UTF16.self)
    }
  }

  /// Every key as the **span route** reports it: the text under each non-marker
  /// ``SpanKind/titlePageKey`` span.
  ///
  /// This is the route DL-111 is about. Sortie 15 shipped title-page key and value ranges
  /// as spans rather than as ``LineRecord`` fields, and the obligation to prove that route
  /// lossless came here with the writer.
  static func spanKeys(of document: String) -> [String] {
    spanText(of: document, kind: .titlePageKey)
  }

  /// Every value as the span route reports it.
  static func spanValues(of document: String) -> [String] {
    spanText(of: document, kind: .titlePageValue)
  }

  private static func spanText(of document: String, kind: SpanKind) -> [String] {
    var scanner = EscriboScanner(language: .fountain)
    let result = scanner.fullScan(document)
    let units = Array(document.utf16)
    return result.spans
      .filter { $0.kind == kind && $0.role == .content }
      .map { String(decoding: units[$0.range], as: UTF16.self) }
  }
}

// MARK: - The title page

@Suite("Fountain writer — the title page")
struct FountainWriterTitlePageTests {

  /// **Exit criterion.** `verbsCovered:` writes back with that exact casing, in its
  /// original position relative to the other keys.
  ///
  /// Asserted three ways, because "the key survived" is easy to satisfy accidentally:
  /// against the whole written document byte for byte, against the ordered key list read
  /// by an oracle that is not the scanner, and against the two mis-spellings a writer that
  /// case-folded or title-cased its keys would produce.
  ///
  /// The input is deliberately non-canonical — over-spaced after three of the four colons —
  /// so a writer that returned its input fails the first assertion.
  @Test("`verbsCovered:` keeps its casing and its position among the other keys")
  func arbitraryKeysKeepTheirSpellingAndOrder() {
    let source =
      "Title:   Episode 10 — Full Mixed Review\n"
      + "Credit: Spanish School\n"
      + "verbsCovered:\thaber, llegar, pasar\n"
      + "Abstract:  Fifty phrases.\n"
      + "\n"
      + "Bob waits.\n"

    let written = FountainWriterHarness.roundTrip(source)

    #expect(
      written == "Title: Episode 10 — Full Mixed Review\n"
        + "Credit: Spanish School\n"
        + "verbsCovered: haber, llegar, pasar\n"
        + "Abstract: Fifty phrases.\n"
        + "\n"
        + "Bob waits.\n")

    #expect(TitlePageOracle.keys(of: written) == ["Title", "Credit", "verbsCovered", "Abstract"])
    #expect(TitlePageOracle.keys(of: written) == TitlePageOracle.keys(of: source))

    // The two spellings a key-folding writer produces. Named rather than implied, so a
    // failure says which transformation happened.
    #expect(!written.contains("VerbsCovered"), "the key was title-cased")
    #expect(!written.contains("verbscovered"), "the key was lowercased")
  }

  /// The same criterion against a real vendored screenplay rather than a hand-built one.
  ///
  /// `spanish.fountain` carries `verbsCovered` fourth of five, between `Author` and
  /// `Abstract`, and the expected list below was read off the committed bytes with `awk`,
  /// not produced by this scanner. A writer that reordered the page, dropped an
  /// unrecognized key, or normalized its casing changes this list.
  @Test("The vendored screenplays' arbitrary keys survive in order",
    arguments: ["spanish", "episode_10"])
  func vendoredScreenplayKeysSurvive(name: String) {
    guard let fixture = fountainCorpus.first(where: { $0.name == name }), fixture.loaded else {
      Issue.record("\(name) is missing from the corpus")
      return
    }
    let written = FountainWriterHarness.roundTrip(fixture.text)
    #expect(
      TitlePageOracle.keys(of: written)
        == ["Title", "Credit", "Author", "verbsCovered", "Abstract"])
    #expect(TitlePageOracle.values(of: written) == TitlePageOracle.values(of: fixture.text))
  }

  /// `episode_01.fountain`'s nine ALL-CAPS Highland keys, in order, including the two whose
  /// value is an empty line and the one that has no value line at all.
  @Test("The Highland export's nine keys survive, empty values and all")
  func highlandExportKeysSurvive() {
    guard let fixture = fountainCorpus.first(where: { $0.name == "episode_01" }),
      fixture.loaded
    else {
      Issue.record("episode_01 is missing from the corpus")
      return
    }
    let written = FountainWriterHarness.roundTrip(fixture.text)
    #expect(
      TitlePageOracle.keys(of: written) == [
        "TITLE", "EPISODE", "CREDIT", "AUTHOR", "SOURCE", "CONTACT INFO", "DRAFT DATE",
        "NOTES", "REVISION",
      ])
    // `EPISODE`, `CONTACT INFO`, and `NOTES` each have a lone-tab value line — a key whose
    // value is empty — and `REVISION` has no value line at all. So nine keys, eight value
    // lines, five non-empty values. Counted off the committed bytes, and stated here as
    // numbers because a writer that collapsed an empty value into an absent key would keep
    // all nine keys and change the second number.
    #expect(TitlePageOracle.values(of: written).count == 5)
    #expect(
      FountainWriterHarness.shape(of: written).filter { $0 == "titlePageValue:0" }.count == 8)
    #expect(
      FountainWriterHarness.shape(of: written).filter { $0 == "titlePageKey:0" }.count == 9)
    #expect(TitlePageOracle.values(of: written) == TitlePageOracle.values(of: fixture.text))
  }

  /// **Exit criterion.** A key with an empty value keeps **both** lines.
  ///
  /// The input spells its two empty values differently — a lone tab, and three spaces — so
  /// a copy-the-source writer fails the byte comparison, and the canonical form of both is
  /// a tab.
  ///
  /// The classification assertion is the one that matters and it is not decoration: an
  /// empty value line written as an *empty line* would terminate the title page
  /// (``FountainGrammar`` deviation 10a), and every key below it would come back as
  /// something else entirely. That is what the shape comparison catches, and it is why the
  /// value line cannot simply be dropped.
  @Test("An empty title-page value keeps its own line and does not close the page")
  func emptyValuesKeepTheirLines() {
    let source =
      "TITLE:\tBig Fish\n"
      + "EPISODE:\n"
      + "\t\n"
      + "CONTACT INFO:\n"
      + "   \n"
      + "CREDIT:\n"
      + "\tAct I\n"
      + "REVISION:\n"
      + "\n"
      + "Bob waits.\n"

    let written = FountainWriterHarness.roundTrip(source)

    #expect(
      written == "TITLE: Big Fish\n"
        + "EPISODE:\n"
        + "\t\n"
        + "CONTACT INFO:\n"
        + "\t\n"
        + "CREDIT:\n"
        + "\tAct I\n"
        + "REVISION:\n"
        + "\n"
        + "Bob waits.\n")

    // Neither empty-valued key collapsed into an absent key, and the page did not end early.
    #expect(
      TitlePageOracle.keys(of: written)
        == ["TITLE", "EPISODE", "CONTACT INFO", "CREDIT", "REVISION"])
    #expect(TitlePageOracle.keys(of: written) == TitlePageOracle.keys(of: source))
    #expect(
      FountainWriterHarness.lines(written).count == FountainWriterHarness.lines(source).count,
      "a line was added or lost")
    #expect(FountainWriterHarness.shape(of: written) == FountainWriterHarness.shape(of: source))

    // Stated as the count that would drop by two if empty values were skipped.
    let valueLines = FountainWriterHarness.shape(of: written).filter { $0 == "titlePageValue:0" }
    #expect(valueLines.count == 3, "\(valueLines.count) value lines, expected 3")
  }

  /// A title page whose keys repeat. Both occurrences survive, in order, and a second
  /// write changes nothing.
  ///
  /// **Exit criterion** (the idempotence half). Duplicate keys are the shape a
  /// dictionary-backed writer loses: read the page into `[String: String]`, write it back,
  /// and one of each pair is gone and the order is whatever the hash table felt like. The
  /// key list below fails immediately for such a writer, and the fixed-point assertion
  /// would then be green on a document that had already lost half its metadata — which is
  /// why the two are asserted together rather than the second one alone.
  @Test("A duplicate title-page key survives twice, in order, and is a fixed point")
  func duplicateKeysSurviveAndAreIdempotent() {
    let source =
      "Title:   One\n"
      + "Title: Two\n"
      + "Author:\n"
      + "   First\n"
      + "Author:\n"
      + "\tSecond\n"
      + "\n"
      + "Bob waits.\n"

    let once = FountainWriterHarness.roundTrip(source)
    let twice = FountainWriterHarness.roundTrip(once)

    #expect(
      once == "Title: One\n"
        + "Title: Two\n"
        + "Author:\n"
        + "\tFirst\n"
        + "Author:\n"
        + "\tSecond\n"
        + "\n"
        + "Bob waits.\n")
    #expect(twice == once, "the writer is not a fixed point on a duplicated key")

    #expect(TitlePageOracle.keys(of: once) == ["Title", "Title", "Author", "Author"])
    #expect(TitlePageOracle.values(of: once) == ["One", "Two", "First", "Second"])
    #expect(once != source, "the input was canonical, so this proves nothing about identity")
  }

  /// Keys that no `if key == "Title"` would ever recognize, each written back byte for
  /// byte.
  ///
  /// Spaces, mixed case, a digit, an underscore, a period, a single letter, and a key with
  /// a diacritic that is one code unit and one with a combining mark that is two. There is
  /// no key list in this package and this is what that means in practice.
  @Test("Arbitrary keys are copied out of the source byte for byte")
  func arbitraryKeysAreVerbatim() {
    let source =
      "Draft date:   June 3, 2026\n"
      + "CONTACT INFO:  a@b.example\n"
      + "verbsCovered:\thablar\n"
      + "weird.key_1:   v\n"
      + "A: b\n"
      + "Título:  x\n"
      + "\n"
      + "Bob waits.\n"

    let written = FountainWriterHarness.roundTrip(source)

    #expect(
      written == "Draft date: June 3, 2026\n"
        + "CONTACT INFO: a@b.example\n"
        + "verbsCovered: hablar\n"
        + "weird.key_1: v\n"
        + "A: b\n"
        + "Título: x\n"
        + "\n"
        + "Bob waits.\n")
    #expect(
      TitlePageOracle.keys(of: written) == [
        "Draft date", "CONTACT INFO", "verbsCovered", "weird.key_1", "A", "Título",
      ])
    #expect(written != source)
  }

  /// A value containing a colon is a value, not a second key.
  ///
  /// `spanish.fountain`'s real first line is `Title: Episode 1 — Present Tense, Level 1:
  /// Simple Sentences (Regular Verbs)`. A writer that split on the *last* colon, or that
  /// re-split the line it had just written, turns the key into `Title: Episode 1 — Present
  /// Tense, Level 1` on the second pass — which the fixed-point assertion catches and the
  /// key list names.
  @Test("A colon inside a value does not become a key boundary on any pass")
  func aColonInTheValueIsNotAKeyBoundary() {
    let source = "Title:   Level 1: Simple Sentences\n\nBob waits.\n"
    let once = FountainWriterHarness.roundTrip(source)
    let twice = FountainWriterHarness.roundTrip(once)

    #expect(once == "Title: Level 1: Simple Sentences\n\nBob waits.\n")
    #expect(twice == once)
    #expect(TitlePageOracle.keys(of: twice) == ["Title"])
    #expect(TitlePageOracle.values(of: twice) == ["Level 1: Simple Sentences"])
  }

  /// A CRLF title page is written with CRLF, and the tab that canonicalizes a continuation
  /// does not bring a bare `\n` with it.
  @Test("A CRLF title page keeps every `\\r\\n`")
  func crlfTitlePage() {
    let source = "Title:   Big Fish\r\n   continued\r\nverbsCovered:  a, b\r\n\r\nBob waits.\r\n"
    let written = FountainWriterHarness.roundTrip(source)

    #expect(written == "Title: Big Fish\r\n\tcontinued\r\nverbsCovered: a, b\r\n\r\nBob waits.\r\n")
    #expect(FountainWriterHarness.bareLineFeeds(in: written) == 0)
    #expect(written != source)
  }

  /// **DL-170 — a scanner defect, pinned here because the writer is where it shows.**
  ///
  /// A title page whose **first** key has an empty value, spelled the way Highland 2 spells
  /// one (a line containing a lone tab), is not recognized as a title page at all. Every
  /// key in it comes back as action, a character cue, or dialogue.
  ///
  /// The cause is a mismatch between two of ``FountainGrammar``'s own deviations. Deviation
  /// 10a says a whitespace-only line inside the region is an empty value, and its terminator
  /// test is `GrammarLine.isEmpty` — Sortie 31 fixed exactly that. But deviation 11's
  /// corroboration test, which decides whether line 0 opens a region in the first place,
  /// still asks `isBlank(_:)`, which answers *true* to a lone tab. So the line that proves
  /// the document has a title page is the one line the opener refuses to accept as
  /// corroboration, and the region never opens.
  ///
  /// `episode_01.fountain` is unaffected because its first key, `TITLE`, has a real value —
  /// which is exactly why Sortie 31 did not find this. A Highland export whose first field
  /// happens to be blank loses its entire title page, silently.
  ///
  /// The fix is one word in `opensTitlePage(_:)` and it is **not** made here: this sortie
  /// owns the writer, and changing the opener moves the committed golden snapshots of three
  /// fixtures. This test pins the current behavior so the change cannot be made by accident,
  /// and **it is meant to go red when DL-170 is fixed** — at which point the expectations
  /// below invert and the document becomes a five-key title page.
  @Test("DL-170: a first key whose value is empty loses the whole title page")
  func firstKeyWithAnEmptyValueLosesTheWholeTitlePage() {
    let source = "TITLE:\n\t\nEPISODE:\n\tX\n\nBob waits.\n"

    // Today: not a title page. `TITLE:` is action, the lone tab is blank, `EPISODE:` is a
    // cue and `\tX` is its dialogue.
    #expect(
      FountainWriterHarness.shape(of: source) == [
        "action:0", "blank:0", "character:0", "dialogue:0", "blank:0", "action:0", "blank:0",
      ])
    #expect(TitlePageOracle.keys(of: source) == [])

    // And the consequence the writer makes visible: the tab is written as an empty line,
    // because a blank line is blank (Sortie 23). That is correct *given* the
    // classification, and the classification is what DL-170 is about.
    #expect(FountainWriterHarness.roundTrip(source) == "TITLE:\n\nEPISODE:\nX\n\nBob waits.\n")

    // The same document with a value on the first key is a title page, which is what makes
    // this a defect in the opener rather than a general limitation.
    let corroborated = "TITLE:\n\tBig Fish\nEPISODE:\n\t\n\nBob waits.\n"
    #expect(TitlePageOracle.keys(of: corroborated) == ["TITLE", "EPISODE"])
    #expect(FountainWriterHarness.shape(of: corroborated).first == "titlePageKey:0")
  }
}

// MARK: - DL-111

@Suite("Fountain writer — DL-111, the span route for title-page keys")
struct FountainWriterKeySpanTests {

  /// **DL-111.** Title-page keys and values ship as spans rather than as ``LineRecord``
  /// fields, and this is the test that route is byte-lossless.
  ///
  /// Sortie 15 shipped ``SpanKind/titlePageKey`` and ``SpanKind/titlePageValue`` spans and
  /// deferred proving they carry every byte. The alternative discharge was to add a
  /// `keyRange` to ``LineRecord`` — a field that would be empty on every line of every
  /// document that is not a title page — and it was not taken, so the obligation is
  /// discharged here instead, with an assertion rather than an argument.
  ///
  /// Three routes to the same strings, over every title-page line in the corpus:
  ///
  /// 1. The **span route** — the text under each non-marker key and value span.
  /// 2. The **oracle** — ``TitlePageOracle``, which re-reads the region by hand and never
  ///    consults the scanner.
  /// 3. The **writer** — the same oracle applied to the written document, which is what the
  ///    writer's own re-lexing of the colon produces.
  ///
  /// All three must agree. A span that trimmed the key, folded its case, swallowed the
  /// colon, or started one code unit late fails (1); a writer that lost a key or reordered
  /// the page fails (3). The comparison is `==` over `[String]`, so a dropped key, an
  /// added one, and a reordered pair are all distinguishable in the failure message.
  @Test("Key and value spans, the oracle, and the writer agree on every fixture",
    arguments: fountainCorpus)
  func theSpanRouteCarriesEveryByte(fixture: FountainFixture) {
    guard fixture.loaded else {
      Issue.record("\(fixture.name) did not load")
      return
    }
    let oracleKeys = TitlePageOracle.keys(of: fixture.text)
    let oracleValues = TitlePageOracle.values(of: fixture.text)

    #expect(
      TitlePageOracle.spanKeys(of: fixture.text) == oracleKeys,
      "\(fixture.name): the key spans and the oracle disagree")
    #expect(
      TitlePageOracle.spanValues(of: fixture.text) == oracleValues,
      "\(fixture.name): the value spans and the oracle disagree")

    let written = FountainWriterHarness.roundTrip(fixture.text)
    #expect(
      TitlePageOracle.keys(of: written) == oracleKeys,
      "\(fixture.name): the writer changed the keys")
    #expect(
      TitlePageOracle.values(of: written) == oracleValues,
      "\(fixture.name): the writer changed the values")
    #expect(
      TitlePageOracle.spanKeys(of: written) == oracleKeys,
      "\(fixture.name): the written document's key spans changed")
  }

  /// The corpus is not vacuously title-page-free.
  ///
  /// Seven of the ten fixtures are body-only documents, so the assertion above is trivially
  /// true for them. This names the three that are not, and the number of keys each carries,
  /// so that a change which stopped the scanner recognizing title pages at all cannot make
  /// the DL-111 test green by making it empty.
  @Test("Three fixtures carry a title page, and they carry the keys they were counted to")
  func theCorpusActuallyHasTitlePages() {
    var withPages: [String: Int] = [:]
    for fixture in fountainCorpus where fixture.loaded {
      let count = TitlePageOracle.keys(of: fixture.text).count
      if count > 0 { withPages[fixture.name] = count }
    }
    #expect(withPages == ["episode_01": 9, "spanish": 5, "episode_10": 5], "\(withPages)")
  }
}

// MARK: - The idempotence gate

/// One document the fixed-point gate runs over, named so a failure identifies itself.
struct WriterDocument: Sendable, CustomTestStringConvertible {
  let name: String
  let text: String
  var testDescription: String { name }
}

/// Documents that are **deliberately non-canonical**, every one of them.
///
/// This list exists because of a finding this mission has now made thirteen times: an exit
/// criterion that the identity function satisfies is decoration. `write(parse(x)) == x` is
/// exactly what a writer that returns its input does, so a fixed-point gate run only over
/// documents that are already canonical proves nothing at all. Every entry below is
/// spelled wrongly on purpose, and `identityCannotPassTheGate` asserts, per document, that
/// the first write **changes** it.
let nonCanonicalWriterDocuments: [WriterDocument] = [
  WriterDocument(
    name: "over-spaced title page",
    text: "Title:   Big Fish\nCredit:\tWritten by\nverbsCovered:   a, b\n\nBob waits.\n"),
  WriterDocument(
    name: "space-indented continuations",
    text: "Title:\n   Big Fish\n      still the title\nAuthor:\n  Someone\n\nBob waits.\n"),
  WriterDocument(
    name: "empty values, spelled three ways",
    text: "TITLE:\n\tBig Fish\nEPISODE:\n\t\nCREDIT:\n   \nAUTHOR:\n \t \nREVISION:\n\nBob waits.\n"
  ),
  // DL-170. This document looks like the one above and is **not** a title page at all —
  // see `firstKeyWithAnEmptyValueLosesTheWholeTitlePage` below for why. It stays in the
  // gate because the fixed point has to hold for it whatever it classifies as, and because
  // if DL-170 is ever fixed this entry starts exercising the title-page path instead and
  // the gate must still be green.
  WriterDocument(
    name: "DL-170: the first key's value is empty",
    text: "TITLE:\n\t\nEPISODE:\n\tX\n\nBob waits.\n"),
  WriterDocument(
    name: "duplicate keys",
    text: "Title:  One\nTitle:   Two\nTitle:\n\tThree\n\nBob waits.\n"),
  WriterDocument(
    name: "over-spelled body",
    text: "=====\n\n#   ACT ONE\n\n##Scene one\n\n=   a synopsis   \n\n~   Willy Wonka   \n"),
  WriterDocument(
    name: "over-spaced dialogue block",
    text: "BOB   (V.O.)   ^\n    (beat)\n    Hello there.   \n\n>   CUT TO:   \n"),
  WriterDocument(
    name: "title page then hostile body",
    text: "Title:   Big Fish\nCONTACT INFO:\n\t\n\n=====\n\n.OVER BLACK   \n\n"
      + "@McAvoy   (V.O.)   ^\n  ~la la la\n   Ordinary speech.   \n\n>   THE END   <\n"),
  WriterDocument(
    name: "CRLF title page and body",
    text: "Title:   Big Fish\r\n   continued\r\n\r\n#   ACT ONE\r\n\r\n=====\r\n\r\n"
      + "BOB   ^\r\nHello.   \r\n"),
  WriterDocument(
    name: "notes and boneyard around a title page",
    text: "Title:   Big Fish\n\n[[<pause   dur=\"2s\"   />]]\n\n/*  struck   out\n"
      + "still   struck  */\n\n=====\n"),
  WriterDocument(
    name: "a colon inside every value",
    text: "Title:   Level 1: Simple Sentences\nAbstract:   see: nothing\n\n#   ACT ONE\n"),
  WriterDocument(
    name: "no final terminator",
    text: "Title:   Big Fish\n\n=====   "),
]

@Suite("Fountain writer — the idempotence gate")
struct FountainWriterIdempotenceTests {

  /// The first differing line of two documents, for a failure message that names a line
  /// rather than dumping two screenplays.
  static func firstDifference(_ lhs: String, _ rhs: String) -> String {
    let left = FountainWriterHarness.lines(lhs)
    let right = FountainWriterHarness.lines(rhs)
    var index = 0
    while index < min(left.count, right.count), left[index] == right[index] {
      index += 1
    }
    let leftLine = index < left.count ? left[index].debugDescription : "<end>"
    let rightLine = index < right.count ? right[index].debugDescription : "<end>"
    return """
      line \(index):
        first write:  \(leftLine)
        second write: \(rightLine)
      """
  }

  /// **Exit criterion.** `write(parse(write(parse(x)))) == write(parse(x))`, over every
  /// fixture in the Sortie 17 corpus — three vendored screenplays and seven hostile
  /// documents.
  ///
  /// The comparison is over **text**, which is the only formulation of this property that
  /// is both true and meaningful. `write(parse(x)) == x` is false for a normalizing writer
  /// and always was. `parse(write(parse(x))) == parse(x)` compared as records is *also*
  /// false, for a reason that took this mission two sorties to state: normalization
  /// shortens lines, every ``LineRecord/range`` after the first shortened one shifts, and
  /// the records then differ for a reason that has nothing to do with data loss.
  ///
  /// What makes this one able to fail is `identityCannotPassTheGate` below, which pins that
  /// at least one document here — including one real fixture — is changed by the first
  /// write.
  @Test("The writer is a fixed point on every fixture in the corpus", arguments: fountainCorpus)
  func fixedPointOnEveryFixture(fixture: FountainFixture) {
    guard fixture.loaded else {
      Issue.record("\(fixture.name) did not load")
      return
    }
    let once = FountainWriterHarness.roundTrip(fixture.text)
    let twice = FountainWriterHarness.roundTrip(once)
    if twice != once {
      let difference = FountainWriterIdempotenceTests.firstDifference(once, twice)
      Issue.record("\(fixture.name) is not a fixed point:\n\(difference)")
    }
  }

  /// The same property over documents authored to be spelled wrongly.
  ///
  /// The corpus is mostly canonical already — real screenplays exported by real tools
  /// usually are — so it exercises the *preservation* half of the fixed point and barely
  /// touches the *normalization* half. These do the opposite: every one of them is changed
  /// by the first write, and the second write must then leave it exactly alone.
  @Test("The writer is a fixed point on every deliberately non-canonical document",
    arguments: nonCanonicalWriterDocuments)
  func fixedPointOnNonCanonicalDocuments(document: WriterDocument) {
    let once = FountainWriterHarness.roundTrip(document.text)
    let twice = FountainWriterHarness.roundTrip(once)
    if twice != once {
      let difference = FountainWriterIdempotenceTests.firstDifference(once, twice)
      Issue.record("\(document.name) is not a fixed point:\n\(difference)")
    }
  }

  /// **Exit criterion.** The identity function fails this gate.
  ///
  /// Stated as an assertion rather than as a claim in a comment, per document, so that a
  /// document which quietly became canonical — because someone rewrote it, or because the
  /// writer stopped normalizing something — turns the gate red instead of hollowing it out.
  @Test("Every gate document is actually changed by the first write",
    arguments: nonCanonicalWriterDocuments)
  func identityCannotPassTheGate(document: WriterDocument) {
    let once = FountainWriterHarness.roundTrip(document.text)
    #expect(
      once != document.text,
      "\(document.name) is already canonical, so the fixed point holds for the identity writer")
  }

  /// And the same, for a **real** fixture rather than a hand-built one.
  ///
  /// `episode_01.fountain` is an 886-line Highland 2 export and it is not canonical: it
  /// carries lines of speech with trailing spaces, which this writer trims. So the corpus
  /// arm of the gate is not identity-satisfiable either, and that is asserted here rather
  /// than assumed.
  @Test("A real vendored screenplay is non-canonical, so the corpus arm can fail too")
  func aRealFixtureIsNonCanonical() {
    guard let fixture = fountainCorpus.first(where: { $0.name == "episode_01" }),
      fixture.loaded
    else {
      Issue.record("episode_01 is missing from the corpus")
      return
    }
    let once = FountainWriterHarness.roundTrip(fixture.text)
    #expect(once != fixture.text, "episode_01 is already canonical")
    // And the normalization is the one claimed: a trimmed line of speech, not a lost one.
    #expect(
      FountainWriterHarness.lines(once).count == FountainWriterHarness.lines(fixture.text).count,
      "the write changed episode_01's line count")
    #expect(once.utf16.count < fixture.text.utf16.count, "the write did not shorten anything")
  }

  /// The fixed point holds line for line as a classification too, on every gate document.
  ///
  /// The text comparison above is the gate. This is the parse-level companion the plan's
  /// amendment 3a permits — **classifications**, never records — and it catches the one
  /// failure mode a byte comparison cannot describe: a writer that is a stable fixed point
  /// on some document it has already turned into a different screenplay.
  @Test("A non-canonical document classifies the same after being written",
    arguments: nonCanonicalWriterDocuments)
  func writingPreservesClassificationOnEveryGateDocument(document: WriterDocument) {
    let written = FountainWriterHarness.roundTrip(document.text)
    let before = FountainWriterHarness.shape(of: document.text)
    let after = FountainWriterHarness.shape(of: written)
    #expect(
      after.count == before.count,
      "\(document.name): \(before.count) lines in, \(after.count) out")
    if after != before {
      var index = 0
      while index < min(after.count, before.count), after[index] == before[index] {
        index += 1
      }
      Issue.record(
        """
        \(document.name) changed classification at line \(index):
          before: \(index < before.count ? before[index] : "<end>")
          after:  \(index < after.count ? after[index] : "<end>")
        """)
    }
  }
}

