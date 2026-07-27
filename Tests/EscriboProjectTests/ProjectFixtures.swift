import Foundation
import Testing

@testable import EscriboProject

// MARK: - The corpus

/// One vendored `PROJECT.md`, paired with a mechanical JSON transcription of its
/// front matter.
///
/// ## Why there are two files per fixture
///
/// `ProjectFrontMatter` is `Codable`, not YAML-aware — the YAML reader lives in
/// `SwiftProyecto`, behind a third-party dependency this package is chartered never to
/// take. So the round-trip gate is run through `JSONEncoder`/`JSONDecoder`, over a JSON
/// document produced *mechanically* from the committed `.md`'s front matter rather than
/// typed out by hand.
///
/// The `.md` is vendored anyway, and it is not decoration. It is the provenance record,
/// and ``FrontMatterTranscriptionTests`` asserts that the JSON's top-level key set is
/// exactly the set of top-level keys in the committed YAML. Without that check the JSON
/// would be an unverifiable assertion by whoever generated it, and a fixture nobody can
/// audit is worth about as much as no fixture at all.
///
/// ## Provenance
///
/// All four are the user's own podcasts, copied once into this repository and never
/// referenced at their original location again — a fixture reached through an absolute
/// path under a home directory does not exist on a CI runner. `Package.swift` declares
/// `.copy("Fixtures")` on this target so the bytes reach the bundle unaltered, and both
/// files are reached through `Bundle/module`.
///
/// What was copied is the **front matter region** of each file — the opening `---`
/// through the closing `---`, byte for byte — and not the Markdown prose beneath it. Two
/// reasons: the prose is not data this model has any opinion about, and one of the four
/// bodies happens to quote a path under a developer's home directory, which the
/// repository-wide guard against locally-anchored fixtures forbids anywhere under
/// `Tests/`. The region that *is* committed is unmodified, and the JSON transcription is
/// bit-identical whether it is generated from the trimmed file or the original.
struct ProjectFixture: Sendable, CustomTestStringConvertible {

  /// The fixture's base name — the `.md` is `<name>-PROJECT.md`, the transcription is
  /// `<name>-frontmatter.json`.
  let name: String

  /// The unknown top-level keys this fixture is known to carry, written out by hand from
  /// reading the committed file.
  ///
  /// This is the oracle for `appSections`. Deriving it from the JSON instead would make
  /// the preservation tests agree with themselves: a decoder that silently dropped every
  /// unknown key would still satisfy "the keys it kept are the keys it kept". Naming them
  /// here means a decoder that keeps none fails, and a decoder that keeps them all passes.
  let expectedUnknownTopLevelKeys: Set<String>

  /// The number of cast members in the committed file, counted by hand.
  let expectedCastCount: Int

  var testDescription: String { name }
}

enum ProjectFixtures {

  /// The subdirectory the fixtures are copied into inside the resource bundle.
  static let subdirectory = "Fixtures"

  /// Every fixture, with the facts about it that were established by reading the file
  /// rather than by running this code over it.
  ///
  /// The four were chosen to cover the shapes that behave differently on decode:
  ///
  /// - `confessions` — carries an unknown top-level key (`episodes_index`, 69 entries)
  ///   *and* an unknown per-cast-member key (`bio`). This is the fixture the whole
  ///   `appSections` mechanism exists for.
  /// - `aunt-stanley` — a different unknown top-level key (`episodeList`) and a 42-member
  ///   cast, so the cast comparison is not exercised only on a three-element array.
  /// - `granville` — already declares `schemaVersion: 4`, so it is the one fixture that
  ///   round-trips with no version migration at all.
  /// - `daily-dao` — legacy v3 shape: `season` and `episodes` as top-level scalars, which
  ///   decode into a synthesized `seasons` array.
  static let all: [ProjectFixture] = [
    ProjectFixture(
      name: "confessions",
      expectedUnknownTopLevelKeys: ["episodes_index"],
      expectedCastCount: 3
    ),
    ProjectFixture(
      name: "aunt-stanley",
      expectedUnknownTopLevelKeys: ["episodeList"],
      expectedCastCount: 42
    ),
    ProjectFixture(
      name: "granville",
      expectedUnknownTopLevelKeys: [],
      expectedCastCount: 25
    ),
    ProjectFixture(
      name: "daily-dao",
      expectedUnknownTopLevelKeys: [],
      expectedCastCount: 2
    ),
  ]

  /// Raw bytes of the committed `PROJECT.md`.
  static func markdown(_ name: String) -> String? {
    load("\(name)-PROJECT", "md")
  }

  /// Raw bytes of the committed JSON transcription of that file's front matter.
  static func frontMatterJSON(_ name: String) -> Data? {
    guard
      let url = Bundle.module.url(
        forResource: "\(name)-frontmatter", withExtension: "json", subdirectory: subdirectory)
    else { return nil }
    return try? Data(contentsOf: url)
  }

  private static func load(_ resource: String, _ ext: String) -> String? {
    guard
      let url = Bundle.module.url(
        forResource: resource, withExtension: ext, subdirectory: subdirectory),
      let data = try? Data(contentsOf: url)
    else { return nil }
    return String(decoding: data, as: UTF8.self)
  }

  // MARK: Coders

  /// The decoder every test uses.
  ///
  /// `.iso8601` matches what the committed files carry (`2026-02-10T13:35:06Z`) and what
  /// `AnyCodable` uses internally. Nothing about this configuration is part of the model
  /// under test — it is the transport, and it is spelled out here once so that no test
  /// accidentally round-trips through a *different* date strategy than it decoded with,
  /// which would make `created` mismatch for reasons that have nothing to do with the
  /// model.
  static func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }

  static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }
}

// MARK: - YAML top-level key scan

/// The set of top-level keys in a `PROJECT.md`'s YAML front matter.
///
/// Deliberately *not* a YAML parser: it reads the region between the opening `---` and
/// the next line that is exactly `---`, and collects the text before the first `:` on
/// every line that starts in column zero. That is enough to answer the only question
/// asked of it — "does the JSON transcription have the same top-level keys as the file it
/// claims to transcribe?" — and it is small enough to be obviously right.
///
/// Hand-written line scanning, per this package's standing rule against regular
/// expressions.
enum FrontMatterKeyScan {

  static func topLevelKeys(in document: String) -> Set<String> {
    var keys: Set<String> = []
    var sawOpener = false
    var inRegion = false

    for line in splitLines(document) {
      if !sawOpener {
        // The opener must be the very first non-empty line.
        if line.isEmpty { continue }
        guard line == "---" else { return [] }
        sawOpener = true
        inRegion = true
        continue
      }
      if inRegion, line == "---" { break }
      guard inRegion else { break }

      // A top-level key starts in column zero. Anything indented belongs to a nested
      // mapping or sequence and is not a key of the document.
      guard let first = line.first, first != " ", first != "\t", first != "#", first != "-"
      else { continue }
      guard let colon = line.firstIndex(of: ":") else { continue }
      keys.insert(String(line[line.startIndex..<colon]))
    }
    return keys
  }

  /// Splits on `\n`, `\r\n`, and a lone `\r`, dropping the terminators.
  ///
  /// Works over **unicode scalars**, not `Character`s. `"\r\n"` is a single grapheme
  /// cluster in Swift, so a loop over `Character`s never sees a `\r` at all and silently
  /// treats a CRLF document as one enormous line. The first draft of this helper did
  /// exactly that; `scannerHandlesTerminators` caught it.
  private static func splitLines(_ text: String) -> [String] {
    let scalars = Array(text.unicodeScalars)
    var lines: [String] = []
    var current = String.UnicodeScalarView()
    var index = 0

    while index < scalars.count {
      let scalar = scalars[index]
      if scalar == "\r" {
        lines.append(String(current))
        current = String.UnicodeScalarView()
        index += (index + 1 < scalars.count && scalars[index + 1] == "\n") ? 2 : 1
      } else if scalar == "\n" {
        lines.append(String(current))
        current = String.UnicodeScalarView()
        index += 1
      } else {
        current.append(scalar)
        index += 1
      }
    }
    lines.append(String(current))
    return lines
  }
}

// MARK: - The known-key oracle

/// Every top-level key `ProjectFrontMatter` claims to understand, written out by hand.
///
/// The model's own `KnownCodingKeys` is `private`, so this cannot be — and should not be
/// — read off the type: an oracle derived from the thing it checks agrees with any
/// implementation. It is kept honest instead by ``KnownKeyOracleTests``, which encodes a
/// fully-populated value and compares the keys that actually come out.
enum KnownProjectKeys {
  static let all: Set<String> = [
    "type", "title", "author", "created", "updated", "description", "season",
    "episodes", "genre", "tags", "episodesDir", "audioDir",
    "filePattern", "exportFormat", "introFile", "outroFile", "cast",
    "preGenerateHook", "postGenerateHook", "tts",
    "schemaVersion", "projectType", "seasons", "languages", "variants", "episodePath",
  ]

  /// Keys the model reads but never writes: the v3 scalars, which decode into `seasons`
  /// and are not emitted again. See DL-151 in ``KnownDefectTests``.
  static let decodeOnly: Set<String> = ["season", "episodes"]
}

@Suite("The known-key oracle matches the model")
struct KnownKeyOracleTests {

  @Test("Encoding a fully-populated front matter emits exactly the known, writable keys")
  func encodedKeysMatchOracle() throws {
    let populated = ProjectFrontMatter(
      type: "project",
      title: "T",
      author: "A",
      created: Date(timeIntervalSince1970: 0),
      updated: Date(timeIntervalSince1970: 1),
      description: "d",
      genre: "g",
      tags: ["t"],
      episodesDir: "episodes",
      audioDir: "audio",
      filePattern: .single("*.fountain"),
      exportFormat: "m4a",
      introFile: "intro.m4a",
      outroFile: "outro.m4a",
      cast: [CastMember(character: "NARRATOR")],
      preGenerateHook: "pre",
      postGenerateHook: "post",
      tts: TTSConfig(model: "1.7b"),
      schemaVersion: 4,
      projectType: "project",
      seasons: [SeasonDefinition(number: 1, episodes: 2)],
      languages: [LanguageDefinition(code: "en", name: "English")],
      variants: [VariantReference(season: 1, language: "en", path: "p")],
      episodePath: "episodes/<episode>.fountain"
    )

    let data = try ProjectFixtures.makeEncoder().encode(populated)
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let emitted = Set(object.keys)

    let unlisted = emitted.subtracting(KnownProjectKeys.all).sorted()
    let unwritten = KnownProjectKeys.all.subtracting(emitted)
    #expect(
      unlisted.isEmpty,
      "the model emits keys the oracle does not list: \(unlisted)")
    #expect(
      unwritten == KnownProjectKeys.decodeOnly,
      """
      the oracle and the model disagree about which keys are written.
      never written: \(unwritten.sorted())
      expected never written: \(KnownProjectKeys.decodeOnly.sorted())
      """)
  }

  @Test("Every oracle key is actually accepted on decode, not swept into appSections")
  func oracleKeysAreNotUnknown() throws {
    // A decoder that had stopped recognizing, say, `tags` would still round-trip it
    // through `appSections` and pass every preservation test in this target. The only
    // way to tell the two apart is to assert the key landed in a typed field, which is
    // what an empty `appSections` here means.
    let json = """
      {
        "type": "project", "title": "T", "author": "A",
        "created": "1970-01-01T00:00:00Z", "updated": "1970-01-01T00:00:01Z",
        "description": "d", "season": 1, "episodes": 2, "genre": "g", "tags": ["t"],
        "episodesDir": "episodes", "audioDir": "audio", "filePattern": "*.fountain",
        "exportFormat": "m4a", "introFile": "i", "outroFile": "o",
        "cast": [{"character": "NARRATOR", "voices": {}}],
        "preGenerateHook": "pre", "postGenerateHook": "post",
        "tts": {"model": "1.7b"}, "schemaVersion": 4, "projectType": "project",
        "seasons": [{"number": 1, "episodes": 2}],
        "languages": [{"code": "en", "name": "English"}],
        "variants": [{"season": 1, "language": "en", "path": "p"}],
        "episodePath": "episodes/<episode>.fountain"
      }
      """
    let decoded = try ProjectFixtures.makeDecoder().decode(
      ProjectFrontMatter.self, from: Data(json.utf8))

    #expect(
      decoded.appSections.isEmpty,
      "keys the oracle calls known were captured as unknown: \(decoded.appSections.keys.sorted())"
    )

    // And the JSON above really does exercise every oracle key, so the assertion is not
    // passing because the sample is short.
    let object = try #require(
      try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    #expect(Set(object.keys) == KnownProjectKeys.all)
  }
}

// MARK: - Transcription guard

/// Proves the JSON transcription still describes the `PROJECT.md` next to it.
@Suite("PROJECT.md front matter transcription")
struct FrontMatterTranscriptionTests {

  @Test("Both files of every fixture load from the bundle", arguments: ProjectFixtures.all)
  func bothFilesLoad(_ fixture: ProjectFixture) throws {
    let markdown = try #require(
      ProjectFixtures.markdown(fixture.name),
      "\(fixture.name)-PROJECT.md was not found in the resource bundle")
    let json = try #require(
      ProjectFixtures.frontMatterJSON(fixture.name),
      "\(fixture.name)-frontmatter.json was not found in the resource bundle")

    // A resource that resolved to zero bytes would let every assertion below pass
    // vacuously, which is the failure mode this whole file is arranged to avoid.
    #expect(markdown.count > 200, "\(fixture.name)-PROJECT.md is implausibly short")
    #expect(json.count > 200, "\(fixture.name)-frontmatter.json is implausibly short")
  }

  @Test(
    "The JSON transcription carries exactly the committed file's top-level keys",
    arguments: ProjectFixtures.all)
  func transcriptionMatchesSource(_ fixture: ProjectFixture) throws {
    let markdown = try #require(ProjectFixtures.markdown(fixture.name))
    let data = try #require(ProjectFixtures.frontMatterJSON(fixture.name))

    let yamlKeys = FrontMatterKeyScan.topLevelKeys(in: markdown)
    #expect(!yamlKeys.isEmpty, "no front matter region found in \(fixture.name)-PROJECT.md")

    let object = try #require(
      try JSONSerialization.jsonObject(with: data) as? [String: Any],
      "\(fixture.name)-frontmatter.json is not a JSON object")
    let jsonKeys = Set(object.keys)

    #expect(
      jsonKeys == yamlKeys,
      """
      \(fixture.name): the JSON transcription has drifted from the committed PROJECT.md.
      only in JSON: \(jsonKeys.subtracting(yamlKeys).sorted())
      only in YAML: \(yamlKeys.subtracting(jsonKeys).sorted())
      """)
  }

  @Test(
    "Each fixture's hand-written unknown-key oracle matches the committed file",
    arguments: ProjectFixtures.all)
  func unknownKeyOracleIsHonest(_ fixture: ProjectFixture) throws {
    let markdown = try #require(ProjectFixtures.markdown(fixture.name))
    let unknown = FrontMatterKeyScan.topLevelKeys(in: markdown)
      .subtracting(KnownProjectKeys.all)

    #expect(
      unknown == fixture.expectedUnknownTopLevelKeys,
      """
      \(fixture.name): file carries unknown keys \(unknown.sorted()), \
      oracle says \(fixture.expectedUnknownTopLevelKeys.sorted())
      """)
  }

  @Test("The line scanner handles all three terminators")
  func scannerHandlesTerminators() {
    let lf = "---\na: 1\nb: 2\n---\nbody: no\n"
    let crlf = "---\r\na: 1\r\nb: 2\r\n---\r\nbody: no\r\n"
    let cr = "---\ra: 1\rb: 2\r---\rbody: no\r"

    #expect(FrontMatterKeyScan.topLevelKeys(in: lf) == ["a", "b"])
    #expect(FrontMatterKeyScan.topLevelKeys(in: crlf) == ["a", "b"])
    #expect(FrontMatterKeyScan.topLevelKeys(in: cr) == ["a", "b"])
  }

  @Test("The line scanner ignores nested keys and sequence entries")
  func scannerIgnoresNesting() {
    let document = """
      ---
      cast:
        - character: NARRATOR
          voices:
            voxalta: a.vox
      tts:
        model: "1.7b"
      ---
      """
    #expect(FrontMatterKeyScan.topLevelKeys(in: document) == ["cast", "tts"])
  }

  @Test("A document with no front matter yields no keys")
  func scannerRejectsBodyOnlyDocument() {
    #expect(FrontMatterKeyScan.topLevelKeys(in: "# Title\n\ntype: project\n").isEmpty)
  }
}
