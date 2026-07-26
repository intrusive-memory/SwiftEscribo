import Foundation
import Testing

@testable import EscriboCore

// MARK: - The corpus

/// One vendored Fountain document, loaded from the test bundle.
///
/// ## Why the text is loaded, and why it is loaded *this* way
///
/// Every fixture lives under `Tests/EscriboCoreTests/Fixtures/Fountain/` and is reached
/// through ``Bundle/module`` — never through an absolute path, and never by walking up
/// from a compiler source-location literal. A path under a developer's home directory
/// does not exist on a CI runner, and a test that can only pass on one laptop is
/// indistinguishable from a test that cannot fail. `Package.swift` declares
/// `.copy("Fixtures")` on `EscriboCoreTests` for exactly this. Sortie 17's exit criteria
/// enforce it with a grep over this whole directory, which is also why this comment does
/// not spell out any of the three forbidden spellings.
///
/// The bytes are decoded with `String(decoding:as: UTF8.self)` over raw `Data` rather
/// than with `String(contentsOf:encoding:)`, because the corpus deliberately contains
/// CRLF and lone-CR documents and the second form is entitled to normalize line endings.
/// A fixture whose terminators were laundered on the way in tests nothing the fixture was
/// authored to test.
struct FountainFixture: Sendable, CustomTestStringConvertible {
  /// The file's base name, without the `.fountain` extension.
  let name: String

  /// The document, exactly as committed.
  let text: String

  /// Whether loading succeeded at all. A missing resource must not degrade into an empty
  /// document that every assertion below passes vacuously.
  let loaded: Bool

  var testDescription: String { name }
}

/// Fixture loading, the golden-snapshot rendering, and the independently-measured facts
/// about each vendored screenplay.
enum FountainFixtures {

  /// The subdirectory the fixtures are copied into, inside the resource bundle.
  static let fountainSubdirectory = "Fixtures/Fountain"

  /// The subdirectory the golden snapshots are copied into.
  static let goldenSubdirectory = "Fixtures/Golden"

  /// Every fixture name, in the order the parameterized tests report them.
  ///
  /// The first three are **vendored real screenplays** (D-3), imported once from
  /// Produciesta and never referenced at their original path again. The rest are hostile
  /// documents authored for this corpus: each one is a shape that has broken a scanner
  /// somewhere, and each is small enough that its expected classification could be
  /// written out by hand — which `FountainHostileFixtureTests` below does.
  static let names: [String] = [
    "episode_01",
    "episode_10",
    "spanish",
    "astral_dialogue",
    "caps_at_eof",
    "crlf",
    "malformed_glosa",
    "mixed_terminators",
    "multiline_glosa",
    "unterminated_boneyard",
  ]

  /// Loads one fixture's bytes from the resource bundle.
  static func load(_ name: String) -> (text: String, loaded: Bool) {
    guard
      let url = Bundle.module.url(
        forResource: name, withExtension: "fountain", subdirectory: fountainSubdirectory),
      let data = try? Data(contentsOf: url)
    else {
      return ("", false)
    }
    return (String(decoding: data, as: UTF8.self), true)
  }

  /// Loads one committed golden snapshot, or `nil` when it has never been written.
  static func golden(_ name: String) -> String? {
    guard
      let url = Bundle.module.url(
        forResource: name, withExtension: "golden", subdirectory: goldenSubdirectory),
      let data = try? Data(contentsOf: url)
    else {
      return nil
    }
    return String(decoding: data, as: UTF8.self)
  }

  // MARK: Independently measured facts
  //
  // Counted from the committed bytes with a tool that is not this scanner — `python3`
  // over the file, at the time the fixture was vendored — and written out here by hand.
  // That is what makes them an oracle rather than a restatement: a scanner that loses a
  // line, mangles a terminator, or is handed a truncated resource disagrees with these,
  // and a scanner that classifies every line wrong still agrees. Both halves matter, and
  // the hand-written classifications below are the other half.

  /// `(utf16 code units, lines)` per fixture, measured off the committed file.
  ///
  /// The line count applies the terminator rule this package documents — `\r\n` is one
  /// terminator, a lone `\r` is a terminator, and a trailing terminator produces a final
  /// empty line — arrived at independently of `LineIndex`.
  static let measured: [String: (utf16: Int, lines: Int)] = [
    "astral_dialogue": (utf16: 131, lines: 12),
    "caps_at_eof": (utf16: 80, lines: 8),
    "crlf": (utf16: 91, lines: 10),
    "episode_01": (utf16: 27190, lines: 886),
    "episode_10": (utf16: 9308, lines: 562),
    "malformed_glosa": (utf16: 194, lines: 17),
    "mixed_terminators": (utf16: 91, lines: 10),
    "multiline_glosa": (utf16: 142, lines: 12),
    "spanish": (utf16: 6905, lines: 562),
    "unterminated_boneyard": (utf16: 108, lines: 10),
  ]

  // MARK: The golden rendering

  /// A 64-bit FNV-1a digest.
  ///
  /// Hand-written rather than `Hashable`: Swift's `hashValue` is seeded per process and
  /// is therefore **not** stable between runs, which makes it useless for a committed
  /// snapshot. `CryptoKit` would work and would also be a dependency this package's
  /// charter has no room for, even in a test target. FNV-1a is eight lines and is
  /// deterministic forever.
  static func digest(_ string: String) -> String {
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    for byte in string.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x0000_0100_0000_01B3
    }
    return String(format: "%016llx", hash)
  }

  /// Every span and record, at full fidelity, one line per document line.
  ///
  /// This is what the digest is taken over — so the digest moves when any offset, length,
  /// kind, style, role, element, or depth changes anywhere in the document. It is
  /// deliberately not committed for the large screenplays: 886 lines of span detail is a
  /// file nobody reviews, and an unreviewed snapshot is a rubber stamp.
  static func detail(of result: ScanResult) -> String {
    ScanInvariants.paintedLines(of: result).map(\.description).joined(separator: "\n")
  }

  /// The committed snapshot: sizes, a run-length-encoded record classification, a span-kind
  /// histogram, and a digest over the full detail above.
  ///
  /// ## What a golden snapshot is and is not evidence of
  ///
  /// It is a **regression detector**, not a correctness proof. Its expected value came
  /// from running the scanner, so it is green for any implementation that has not changed
  /// — including a wrong one. It catches "this changed and nobody meant it to" and
  /// nothing else. The hand-written expectations in `FountainHostileFixtureTests` are the
  /// half of this file that can fail on a scanner that was wrong from the start, and the
  /// two are not substitutes for each other.
  static func snapshot(name: String, text: String, result: ScanResult) -> String {
    var out = ""
    out += "fixture \(name)\n"
    out += "utf16 \(text.utf16.count)\n"
    out += "lines \(result.lineRecords.count)\n"
    out += "spans \(result.spans.count)\n"
    out += "digest \(digest(detail(of: result)))\n"

    out += "--- records (count element depth) ---\n"
    var run: (element: ElementKind, depth: Int, count: Int)?
    for record in result.lineRecords {
      if var current = run, current.element == record.element, current.depth == record.depth {
        current.count += 1
        run = current
      } else {
        if let current = run {
          out += "\(current.count) \(current.element.rawValue) \(current.depth)\n"
        }
        run = (record.element, record.depth, 1)
      }
    }
    if let current = run {
      out += "\(current.count) \(current.element.rawValue) \(current.depth)\n"
    }

    out += "--- span kinds (kind/role/style count) ---\n"
    var histogram: [String: Int] = [:]
    for span in result.spans {
      histogram["\(span.kind.rawValue)/\(span.role.rawValue)/\(span.style.rawValue)", default: 0] +=
        1
    }
    for key in histogram.keys.sorted() {
      out += "\(key) \(histogram[key] ?? 0)\n"
    }
    return out
  }

  /// Writes `snapshot` somewhere the operator can copy it from, and returns the path.
  ///
  /// Used only on a mismatch, and only to make regenerating a golden possible without
  /// hand-transcribing it out of a build log. `FileManager`'s temporary directory rather
  /// than any path spelled out in source: nothing under `Tests/` may name an absolute
  /// path, and nothing here does.
  static func writeActual(_ snapshot: String, name: String) -> String {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "swiftescribo-golden", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("\(name).golden")
    try? Data(snapshot.utf8).write(to: url)
    return url.path
  }

  // MARK: Scanning helpers

  /// Full-scans `text` as Fountain and asserts every ``ScanResult`` invariant on the way
  /// out — Sortie 6's harness, on every fixture, as this sortie's task 5 requires.
  static func fullScan(
    _ fixture: FountainFixture,
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> ScanResult {
    var scanner = IncrementalScanner(grammar: FountainGrammar())
    let result = scanner.fullScan(fixture.text)
    ScanInvariants.check(
      result, text: fixture.text, editedRange: nil, "fixture \(fixture.name) — full scan",
      sourceLocation: sourceLocation)
    return result
  }

  /// The elements of every line, in order.
  static func elements(_ result: ScanResult) -> [String] {
    result.lineRecords.map(\.element.rawValue)
  }
}

/// The corpus, loaded once.
let fountainCorpus: [FountainFixture] = FountainFixtures.names.map { name in
  let loaded = FountainFixtures.load(name)
  return FountainFixture(name: name, text: loaded.text, loaded: loaded.loaded)
}

/// The seeds the corpus is edited with. Two rather than the gate's thirty-two: the point
/// here is that a *real* 886-line screenplay survives the adversarial edit shapes, not to
/// re-run the gate's seed sweep on a bigger document.
let fixtureGateSeeds: [UInt64] = [0x0123_4567_89AB_CDEF, 0xDEAD_BEEF_CAFE_BABE]

// MARK: - The corpus, driven

@Suite("Fountain fixture corpus — vendored screenplays and hostile input")
struct FountainFixtureCorpusTests {

  // MARK: Loading

  /// Every fixture is present in the bundle and is the file that was committed.
  ///
  /// The size and line-count assertions are the reason this is not vacuous. A resource
  /// that failed to copy, a `String(contentsOf:)` that normalized `\r\n` to `\n`, or a
  /// fixture someone re-saved through an editor that trimmed a trailing terminator all
  /// change one of these two numbers, and all of them would otherwise present as a
  /// mysterious golden-snapshot failure much later.
  @Test("Every fixture loads from `Bundle.module` at exactly its committed size",
    arguments: fountainCorpus)
  func fixtureLoadsFromTheBundle(fixture: FountainFixture) {
    #expect(fixture.loaded, "\(fixture.name) was not found in Bundle.module")
    #expect(!fixture.text.isEmpty, "\(fixture.name) loaded empty")

    guard let measured = FountainFixtures.measured[fixture.name] else {
      Issue.record("\(fixture.name) has no independently measured size")
      return
    }
    #expect(
      fixture.text.utf16.count == measured.utf16,
      "\(fixture.name): \(fixture.text.utf16.count) UTF-16 units, expected \(measured.utf16)")
    #expect(
      ScanInvariants.lineCount(of: fixture.text) == measured.lines,
      "\(fixture.name): \(ScanInvariants.lineCount(of: fixture.text)) lines, expected \(measured.lines)"
    )
  }

  /// The corpus is at least the size the sortie called for, and the three real
  /// screenplays are in it.
  @Test("The corpus contains at least eight fixtures, three of them vendored screenplays")
  func corpusIsBigEnough() {
    #expect(fountainCorpus.count >= 8, "the corpus has \(fountainCorpus.count) fixtures")
    for vendored in ["episode_01", "episode_10", "spanish"] {
      #expect(
        fountainCorpus.contains { $0.name == vendored && $0.loaded },
        "the vendored screenplay \(vendored) is missing from the corpus")
    }
  }

  // MARK: Full scan

  /// Every fixture scans, produces one record per line, and satisfies every invariant.
  @Test("Every fixture full-scans and satisfies every `ScanResult` invariant",
    arguments: fountainCorpus)
  func fixtureFullScans(fixture: FountainFixture) {
    let result = FountainFixtures.fullScan(fixture)
    #expect(result.dirtyRange == 0..<fixture.text.utf16.count)
    #expect(result.lineRecords.count == ScanInvariants.lineCount(of: fixture.text))
    #expect(result.lines.lowerBound == 0)
    // No line is unclassified: `ElementKind` has no "unknown" member and every scan tiles,
    // so an empty raw value would mean a record was default-constructed.
    #expect(result.lineRecords.allSatisfy { !$0.element.rawValue.isEmpty })
  }

  // MARK: Incremental equals full

  /// Typing the whole document into an empty buffer produces exactly what scanning it in
  /// one pass produces.
  ///
  /// The cheapest possible statement of `incrementalScan == fullScan` over a real
  /// document, and the one that covers **every** fixture rather than the ones an edit
  /// generator happens to reach. The comparison is over `spans` and `lineRecords` as
  /// whole arrays, plus the scanner's own per-line start states, so a single wrong offset
  /// anywhere in an 886-line screenplay fails it.
  @Test("Inserting a fixture into an empty document equals scanning it in one pass",
    arguments: fountainCorpus)
  func insertingTheWholeDocumentEqualsAFullScan(fixture: FountainFixture) {
    var incremental = IncrementalScanner(grammar: FountainGrammar())
    let empty = incremental.fullScan("")
    ScanInvariants.check(empty, text: "", editedRange: nil, "\(fixture.name) — empty document")

    let edit = TextEdit(range: 0..<0, replacementLength: fixture.text.utf16.count)
    let typed = incremental.incrementalScan(edit, in: fixture.text)
    ScanInvariants.check(
      typed, text: fixture.text, editedRange: 0..<fixture.text.utf16.count,
      "\(fixture.name) — inserted in one edit")

    var fresh = IncrementalScanner(grammar: FountainGrammar())
    let full = fresh.fullScan(fixture.text)

    ScanInvariants.expectSameElements(
      typed.lineRecords, full.lineRecords, "lineRecords", "\(fixture.name) — inserted vs full")
    ScanInvariants.expectSameElements(
      typed.spans, full.spans, "spans", "\(fixture.name) — inserted vs full")
    ScanInvariants.expectSameElements(
      incremental.startStates, fresh.startStates, "startStates",
      "\(fixture.name) — inserted vs full")
  }

  /// The gate's adversarial edit sequence, replayed over the fixture corpus.
  ///
  /// `ScanGateTests.replay` asserts, at every step, both halves of the gate: the returned
  /// window against the matching slice of a full scan, and the whole accumulated painted
  /// document against a full scan of the same text. Read the warning on
  /// `ScanGateTests.incrementalScanEqualsFullScan` before citing a green run of this as
  /// evidence of anything about the Fountain grammar: both sides run the same grammar, so
  /// this is a convergence check over real documents and is structurally incapable of
  /// noticing that a line is classified wrong. What it adds over the gate's synthetic
  /// corpus is scale and real content — an 886-line screenplay with a title page, forced
  /// headings, sections, and 320 blank lines — not correctness.
  @Test("The adversarial edit sequence converges on every fixture",
    arguments: fountainCorpus, fixtureGateSeeds)
  func adversarialEditsConvergeOnEveryFixture(fixture: FountainFixture, seed: UInt64) {
    let steps = GateEditGenerator.sequence(seed: seed, from: fixture.text)
    #expect(steps.count == EditShape.allCases.count)
    ScanGateTests.replay(
      FountainGrammar(), steps: steps, from: fixture.text, seed: seed,
      documentName: "fixture \(fixture.name)")
  }

  // MARK: Golden snapshots

  /// The committed span/record snapshot for every fixture.
  ///
  /// On a mismatch the actual snapshot is written to the temporary directory and its path
  /// is reported, which is how a golden is regenerated after an intentional grammar
  /// change: read the diff, decide the change was meant, copy the file over the committed
  /// one.
  @Test("Every fixture matches its committed golden span/record snapshot",
    arguments: fountainCorpus)
  func fixtureMatchesItsGoldenSnapshot(fixture: FountainFixture) {
    let result = FountainFixtures.fullScan(fixture)
    let actual = FountainFixtures.snapshot(
      name: fixture.name, text: fixture.text, result: result)

    guard let expected = FountainFixtures.golden(fixture.name) else {
      let path = FountainFixtures.writeActual(actual, name: fixture.name)
      Issue.record(
        """
        no golden snapshot committed for \(fixture.name).
        The actual snapshot was written to: \(path)
        Copy it to Tests/EscriboCoreTests/Fixtures/Golden/\(fixture.name).golden
        """)
      return
    }

    if actual != expected {
      let path = FountainFixtures.writeActual(actual, name: fixture.name)
      let actualLines = actual.split(separator: "\n", omittingEmptySubsequences: false)
      let expectedLines = expected.split(separator: "\n", omittingEmptySubsequences: false)
      var index = 0
      while index < min(actualLines.count, expectedLines.count),
        actualLines[index] == expectedLines[index]
      {
        index += 1
      }
      let actualLine = index < actualLines.count ? String(actualLines[index]) : "<end>"
      let expectedLine = index < expectedLines.count ? String(expectedLines[index]) : "<end>"
      Issue.record(
        """
        golden snapshot for \(fixture.name) diverged at line \(index):
          actual:   \(actualLine)
          expected: \(expectedLine)
        Full actual snapshot written to: \(path)
        """)
    }
  }

  // MARK: Independently-derived facts about the vendored screenplays
  //
  // Counted off the committed bytes with `python3`, not with this scanner. Unlike the
  // golden snapshots above, these can fail against an implementation that was wrong from
  // the day it was written.

  /// `episode_10.fountain` and `spanish.fountain` each carry exactly fifty single-line
  /// GLOSA notes and two hundred and three blank lines.
  ///
  /// Both numbers were counted from the files directly: `grep -c '^\[\['` is fifty in each
  /// and `grep -c '^$'` is two hundred and three. Neither file contains a `/*`, so no
  /// blank line is inside a boneyard and none of the fifty notes spans a line — which is
  /// what makes the two counts comparable to the scanner's classification at all.
  @Test("The drill screenplays carry exactly fifty notes and 203 blank lines each",
    arguments: ["episode_10", "spanish"])
  func drillScreenplaysHaveTheNotesAndBlanksTheyWereCountedToHave(name: String) {
    guard let fixture = fountainCorpus.first(where: { $0.name == name }) else {
      Issue.record("\(name) missing from the corpus")
      return
    }
    let result = FountainFixtures.fullScan(fixture)
    let elements = FountainFixtures.elements(result)

    #expect(elements.filter { $0 == ElementKind.note.rawValue }.count == 50)
    #expect(elements.filter { $0 == ElementKind.blank.rawValue }.count == 203)
    #expect(
      elements.contains { $0 == ElementKind.boneyard.rawValue } == false,
      "\(name) contains no `/*` and must produce no boneyard line")

    // Every one of the fifty notes is a GLOSA directive — `[[<pause .../>]]` or
    // `[[<breath .../>]]` — so there are exactly fifty tag spans, no more and no fewer.
    let tags = result.spans.filter { $0.kind == .glosaTag }
    #expect(tags.count == 50, "\(name): \(tags.count) GLOSA tag spans, expected 50")
  }

  /// `episode_01.fountain` carries the two `#` section lines it was counted to have, and
  /// no note or boneyard at all.
  ///
  /// `grep -c '^#'` is two on the committed file and `grep -c '\[\[\|/\*'` is zero. The
  /// absence assertions are the strong half: a grammar that opened a region on some other
  /// character would light one up across an 886-line document and could not hide it.
  @Test("The vendored 886-line screenplay has two sections and no regions")
  func longScreenplayHasTheStructureItWasCountedToHave() {
    guard let fixture = fountainCorpus.first(where: { $0.name == "episode_01" }) else {
      Issue.record("episode_01 missing from the corpus")
      return
    }
    let result = FountainFixtures.fullScan(fixture)
    let elements = FountainFixtures.elements(result)

    #expect(elements.filter { $0 == ElementKind.section.rawValue }.count == 2)
    #expect(elements.filter { $0 == ElementKind.note.rawValue }.isEmpty)
    #expect(elements.filter { $0 == ElementKind.boneyard.rawValue }.isEmpty)

    // `# ACT ONE: …` is depth 1 and `## OPENING. …` is depth 2. Counted by reading the
    // file, not by running the scanner.
    let sections = result.lineRecords.filter { $0.element == .section }
    #expect(sections.map(\.depth) == [1, 2])
  }

  /// **A defect this corpus found, asserted as it actually behaves. Not fixed here.**
  ///
  /// `episode_01.fountain` is a real Highland 2 export, and Highland writes a title page
  /// as a key on one line with its value indented on the next — writing an **empty**
  /// value as a line containing a lone tab:
  ///
  /// ```
  /// TITLE:
  /// \tEVERYBODY WANTS THE SAME THING — EPISODE 1
  /// EPISODE:
  /// \t
  /// CREDIT:
  /// \tAct I — The Road
  /// ```
  ///
  /// `FountainGrammar` reads that whitespace-only line as **blank**, a blank line ends the
  /// title page, and the seven keys below it fall out of the region. `CREDIT:` is then an
  /// ALL-CAPS line with a non-blank line under it — a **character cue** — and the author,
  /// source, contact, draft date, and notes become its **dialogue**. Of nine title-page
  /// keys in the file, two are recognized.
  ///
  /// Whether a lone tab should terminate a title page is a real question — the Fountain
  /// spec says the page ends at a blank line and says nothing about whitespace-only lines
  /// — but the consequence is not ambiguous: the first embed of this parser is
  /// Produciesta, whose own fixtures are Highland exports in exactly this shape, and it
  /// would read a screenplay's author as a line of spoken dialogue.
  ///
  /// This test is deliberately **descriptive**, exactly like the DL-120 test in
  /// `FountainHostileFixtureTests`. Sortie 17 is a fixture sortie and touches no grammar.
  /// When this is fixed, this test goes red and should be rewritten to assert nine
  /// `titlePageKey` records — not deleted, and not weakened now to be true either way.
  @Test("Known defect: a whitespace-only title-page value ends the title page early")
  func highlandStyleEmptyTitlePageValueTruncatesTheTitlePage() {
    guard let fixture = fountainCorpus.first(where: { $0.name == "episode_01" }) else {
      Issue.record("episode_01 missing from the corpus")
      return
    }
    let result = FountainFixtures.fullScan(fixture)

    // Nine keys are written in the file — TITLE, EPISODE, CREDIT, AUTHOR, SOURCE,
    // CONTACT INFO, DRAFT DATE, NOTES, REVISION — counted by reading it.
    let keys = result.lineRecords.filter { $0.element == .titlePageKey }
    #expect(keys.count == 2, "\(keys.count) title-page keys recognized of the nine written")

    // The exact shape of the truncation, line by line, hand-derived from the bytes above.
    ScanInvariants.expectSameElements(
      Array(result.lineRecords.prefix(11).map(\.element)),
      [
        .titlePageKey,  // TITLE:
        .titlePageValue,  // \tEVERYBODY WANTS THE SAME THING — EPISODE 1
        .titlePageKey,  // EPISODE:
        .blank,  // \t  <- the lone tab that ends the region
        .character,  // CREDIT:      <- should be a title-page key
        .dialogue,  // \tAct I — The Road
        .dialogue,  // AUTHOR:      <- should be a title-page key
        .dialogue,  // \tSTOVAK
        .dialogue,  // SOURCE:      <- should be a title-page key
        .dialogue,  // \tadapted from Shakespeare's THE TEMPEST
        .dialogue,  // CONTACT INFO:  <- should be a title-page key
      ],
      "elements", "episode_01 title page")
  }
}
