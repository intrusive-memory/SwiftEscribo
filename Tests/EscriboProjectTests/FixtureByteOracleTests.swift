import Foundation
import Testing

@testable import EscriboProject

// MARK: - Why this file exists

/// Assertions whose oracle never passes through `ProjectFrontMatter.init(from:)` or
/// `CastMember.init(from:)`.
///
/// ## The hole this closes
///
/// A round-trip gate compares `decode(x)` against `decode(encode(decode(x)))`. Both sides
/// run through the **same** decoder, so a field the decoder drops is missing from both and
/// the two compare **equal**. The gate is therefore blind, by construction, to every
/// decode-side loss — the single largest class of data loss this model can suffer.
///
/// This is not a hypothesis. Setting `voices = [:]` in `CastMember.init(from:)` — which
/// destroys every voice of every character in every file — left all four corpus-driven
/// round-trip tests in `ProjectFrontMatterRoundTripTests` **green** (measured 2026-07-26,
/// before this file existed: three issues fired, all three from tests whose expected value
/// was a literal typed into the source or a value constructed in code; zero from any test
/// driven by a fixture).
///
/// So every assertion in this file gets its expected value from one of two places, neither
/// of which is the model's decoder:
///
/// 1. **The committed fixture bytes, read with `JSONSerialization`.** Foundation's own JSON
///    parser produces `[String: Any]`; nothing in `EscriboProject` participates. If the
///    model's decoder throws a field away, the decoded value and the raw dictionary
///    disagree and the test fails. This is the general gate — it runs over the whole
///    corpus, so it scales to fields nobody thought to write a literal for.
/// 2. **Literals typed into this file by hand**, read out of the committed fixtures by a
///    human. Narrower, but immune even to a bug in the raw reader below.
///
/// A third leg lives in ``ConstructedValueRoundTripTests``: values built in code, encoded,
/// decoded, and compared against the value that was built. That one catches a decoder that
/// drops a field the corpus happens not to exercise.
///
/// **DL-159** was found by leg 1 on its first run. See ``KnownDefectTests``.

// MARK: - The raw reader

/// Reads a committed fixture's front matter with `JSONSerialization` and normalizes it
/// into the shape `CastMember` is *supposed* to decode into.
///
/// The normalization here duplicates rules the decoder also implements — provider names
/// are lowercased, a bare voice string becomes a one-element array, `voicePrompt` wins over
/// `voiceDescription`. That duplication is the point: it is a second, independent statement
/// of the rules, written from the documentation rather than from the code, and a decoder
/// that stops honouring one of them now disagrees with something.
enum RawFixture {

  /// The fixture's top-level object, straight from the bytes.
  static func topLevel(_ name: String) throws -> [String: Any] {
    let data = try #require(ProjectFixtures.frontMatterJSON(name))
    return try #require(
      try JSONSerialization.jsonObject(with: data) as? [String: Any],
      "\(name)-frontmatter.json is not a JSON object")
  }

  /// The same, for an arbitrary blob of encoded JSON.
  static func object(_ data: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  /// One cast member as the bytes describe it, with the field names and shapes the model
  /// promises to produce.
  struct Member: Equatable {
    var character: String
    var actor: String?
    var gender: String?
    var voiceDescription: String?
    var voices: [String: [String]]
    var language: String?
    var extraKeys: Set<String>
  }

  /// Every key `CastMember` claims to understand, written out by hand.
  ///
  /// Not read off `CastMember.CodingKeys`: an oracle derived from the type under test
  /// agrees with any implementation of it, including one that has quietly stopped
  /// recognizing a key. Kept honest by ``castMemberKeyOracleIsHonest`` below.
  static let knownMemberKeys: Set<String> = [
    "character", "actor", "gender", "voicePrompt", "voiceDescription", "voices", "language",
  ]

  static func cast(_ name: String) throws -> [Member] {
    let raw = try topLevel(name)
    guard let array = raw["cast"] as? [[String: Any]] else { return [] }
    return try array.map { try member($0) }
  }

  static func member(_ raw: [String: Any]) throws -> Member {
    var voices: [String: [String]] = [:]
    if let voicesRaw = raw["voices"] as? [String: Any] {
      for (provider, value) in voicesRaw {
        let key = provider.lowercased()
        if let list = value as? [String] {
          voices[key] = list
        } else if let single = value as? String {
          voices[key] = [single]
        }
      }
    }

    return Member(
      character: try #require(raw["character"] as? String, "a cast member has no character"),
      actor: raw["actor"] as? String,
      gender: raw["gender"] as? String,
      // The model prefers `voicePrompt` and falls back to the legacy `voiceDescription`.
      // When a file carries both, the legacy value is destroyed — DL-159.
      voiceDescription: (raw["voicePrompt"] as? String) ?? (raw["voiceDescription"] as? String),
      voices: voices,
      language: raw["language"] as? String,
      extraKeys: Set(raw.keys).subtracting(knownMemberKeys)
    )
  }

  /// Projects a decoded `CastMember` into the same shape, so the two can be compared.
  static func project(_ member: CastMember) -> Member {
    Member(
      character: member.character,
      actor: member.actor,
      gender: member.gender?.rawValue,
      voiceDescription: member.voiceDescription,
      voices: member.voices,
      language: member.language,
      extraKeys: Set(member.extraKeys.keys)
    )
  }

  /// Field-by-field difference report, so a failure names the field rather than dumping
  /// two structs.
  static func differences(_ expected: Member, _ actual: Member, at index: Int) -> [String] {
    var out: [String] = []
    let tag = "cast[\(index)] \(expected.character)"

    func compare<T: Equatable>(_ label: String, _ lhs: T, _ rhs: T) {
      if lhs != rhs {
        out.append(
          "\(tag).\(label): file says \(String(describing: lhs)), "
            + "model says \(String(describing: rhs))")
      }
    }

    compare("character", expected.character, actual.character)
    compare("actor", expected.actor, actual.actor)
    compare("gender", expected.gender, actual.gender)
    compare("voiceDescription", expected.voiceDescription, actual.voiceDescription)
    compare("voices", expected.voices, actual.voices)
    compare("language", expected.language, actual.language)
    compare("extraKeys", expected.extraKeys.sorted(), actual.extraKeys.sorted())
    return out
  }
}

// MARK: - Leg 1: the model checked against the committed bytes

@Suite("Cast content matched against the committed fixture bytes")
struct FixtureByteOracleTests {

  private func decode(_ name: String) throws -> ProjectFrontMatter {
    let data = try #require(ProjectFixtures.frontMatterJSON(name))
    return try ProjectFixtures.makeDecoder().decode(ProjectFrontMatter.self, from: data)
  }

  /// The oracle for "what keys may a cast member carry" is hand-written, so it has to be
  /// checked against the model the same way ``KnownKeyOracleTests`` checks the top-level
  /// one: encode a member with every field populated and see what actually comes out.
  @Test("The hand-written cast-member key oracle matches the model")
  func castMemberKeyOracleIsHonest() throws {
    let populated = CastMember(
      character: "C", actor: "A", gender: .male, voiceDescription: "v",
      voices: ["voxalta": ["a.vox"]], language: "en")
    let data = try ProjectFixtures.makeEncoder().encode(populated)
    let emitted = Set(try RawFixture.object(data).keys)

    let unlisted = emitted.subtracting(RawFixture.knownMemberKeys).sorted()
    #expect(unlisted.isEmpty, "the model emits member keys the oracle does not list: \(unlisted)")

    // `voiceDescription` is the one oracle key never written — it is read as a legacy
    // spelling and rewritten as `voicePrompt`.
    #expect(
      RawFixture.knownMemberKeys.subtracting(emitted) == ["voiceDescription"],
      "never written: \(RawFixture.knownMemberKeys.subtracting(emitted).sorted())")

    // And none of them is swept into `extraKeys` on the way back in, which is what would
    // happen if the decoder had stopped recognizing one.
    let decoded = try ProjectFixtures.makeDecoder().decode(CastMember.self, from: data)
    #expect(decoded.extraKeys.isEmpty, "known keys captured as unknown: \(decoded.extraKeys.keys)")
  }

  /// **The assertion this sortie exists for.**
  ///
  /// Not a round trip: the left-hand side is the committed file as `JSONSerialization`
  /// reads it, the right-hand side is what the model's decoder produced from those same
  /// bytes. Nothing cancels out. Every one of the seven fields a `CastMember` carries is
  /// compared for every member of every fixture.
  @Test(
    "Every cast member matches the committed file, field for field",
    arguments: ProjectFixtures.all)
  func decodedCastMatchesFixtureBytes(_ fixture: ProjectFixture) throws {
    let expected = try RawFixture.cast(fixture.name)
    let decoded = try #require(try decode(fixture.name).cast)

    #expect(
      expected.count == fixture.expectedCastCount,
      """
      \(fixture.name): the committed file has \(expected.count) members, \
      oracle says \(fixture.expectedCastCount)
      """)
    #expect(
      decoded.count == expected.count,
      "\(fixture.name): decoded \(decoded.count) members, the file has \(expected.count)")
    guard decoded.count == expected.count else { return }

    var diffs: [String] = []
    for (index, pair) in zip(expected, decoded).enumerated() {
      diffs.append(contentsOf: RawFixture.differences(pair.0, RawFixture.project(pair.1), at: index))
    }
    #expect(diffs.isEmpty, "\(fixture.name):\n\(diffs.joined(separator: "\n"))")
  }

  /// The fixture must actually contain voices, or the assertion above passes by having
  /// nothing to check. Guarding this separately means a fixture that loses its cast in a
  /// future re-vendoring is reported as an empty corpus rather than as a pass.
  @Test(
    "Every fixture carries voices for the comparison to have something to lose",
    arguments: ProjectFixtures.all)
  func fixturesCarryVoices(_ fixture: ProjectFixture) throws {
    let expected = try RawFixture.cast(fixture.name)
    let withVoices = expected.filter { !$0.voices.isEmpty }
    #expect(
      withVoices.count == fixture.expectedVoicedMemberCount,
      """
      \(fixture.name): \(withVoices.count) members carry voices in the file, \
      hand-counted oracle says \(fixture.expectedVoicedMemberCount)
      """)

    let ids = expected.flatMap { $0.voices.values.flatMap { $0 } }
    #expect(
      ids.count >= fixture.expectedVoicedMemberCount,
      "\(fixture.name) declares only \(ids.count) voice ids")
    #expect(Set(ids).count > 1, "\(fixture.name) declares the same voice id for everyone")
  }

  /// Encoding is checked against the bytes too: the file goes in, the model writes it back
  /// out, and the written bytes are compared with the original bytes — both sides read by
  /// `JSONSerialization`. A decoder that drops a field and an encoder that drops a field
  /// both show up here, which the `decode/encode/decode` formulation cannot say.
  @Test("Written-back cast bytes match the original bytes", arguments: ProjectFixtures.all)
  func encodedCastMatchesFixtureBytes(_ fixture: ProjectFixture) throws {
    let expected = try RawFixture.cast(fixture.name)
    let written = try ProjectFixtures.makeEncoder().encode(try decode(fixture.name))
    let object = try RawFixture.object(written)
    let rawCast = try #require(object["cast"] as? [[String: Any]], "\(fixture.name) wrote no cast")
    let actual = try rawCast.map { try RawFixture.member($0) }

    #expect(actual.count == expected.count, "\(fixture.name): wrote \(actual.count) members")
    guard actual.count == expected.count else { return }

    var diffs: [String] = []
    for (index, pair) in zip(expected, actual).enumerated() {
      diffs.append(contentsOf: RawFixture.differences(pair.0, pair.1, at: index))
    }
    #expect(diffs.isEmpty, "\(fixture.name) write-back:\n\(diffs.joined(separator: "\n"))")
  }

  /// The unknown-key twin of the test above, also byte to byte. `appSections` values are
  /// compared through `NSDictionary`/`NSArray` equality on the parsed objects, so a value
  /// that came back re-ordered but structurally identical still passes, and one that came
  /// back truncated does not.
  @Test("Written-back unknown top-level keys match the original bytes",
    arguments: ProjectFixtures.all)
  func encodedUnknownKeysMatchFixtureBytes(_ fixture: ProjectFixture) throws {
    let before = try RawFixture.topLevel(fixture.name)
    let written = try ProjectFixtures.makeEncoder().encode(try decode(fixture.name))
    let after = try RawFixture.object(written)

    let unknownInFile = Set(before.keys).subtracting(KnownProjectKeys.all)
    #expect(
      unknownInFile == fixture.expectedUnknownTopLevelKeys,
      "\(fixture.name): the bytes carry unknown keys \(unknownInFile.sorted())")

    for key in unknownInFile {
      let original = try #require(before[key], "\(key) vanished from the reader")
      let round = try #require(after[key], "\(fixture.name): \(key) was not written back")
      #expect(
        NSDictionary(dictionary: ["v": original]) == NSDictionary(dictionary: ["v": round]),
        "\(fixture.name): \(key) changed on write-back")
    }
  }
}

// MARK: - Leg 2: literals read out of the committed files by hand

@Suite("Cast values typed by hand from the committed files")
struct LiteralCastValueTests {

  private func decode(_ name: String) throws -> ProjectFrontMatter {
    let data = try #require(ProjectFixtures.frontMatterJSON(name))
    return try ProjectFixtures.makeDecoder().decode(ProjectFrontMatter.self, from: data)
  }

  private func roundTripped(_ name: String) throws -> ProjectFrontMatter {
    let data = try ProjectFixtures.makeEncoder().encode(try decode(name))
    return try ProjectFixtures.makeDecoder().decode(ProjectFrontMatter.self, from: data)
  }

  /// Every character name in `confessions`, in file order, and — for one member — the
  /// entire `voices` dictionary: every provider key and every voice id, written out rather
  /// than counted.
  @Test("confessions: names in order, and one member's every provider and voice id")
  func confessionsCastLiterals() throws {
    for value in [try decode("confessions"), try roundTripped("confessions")] {
      let cast = try #require(value.cast)
      #expect(cast.map(\.character) == ["NARRATOR", "ESPECTRO FAMILIAR", "THE PRACTITIONER"])

      #expect(cast[0].voices == ["voxalta": ["voices/NARRATOR.vox"]])
      #expect(cast[1].voices == ["voxalta": ["voices/ESPECTRO_FAMILIAR.vox"]])
      #expect(cast[2].voices == ["voxalta": ["voices/THE_PRACTITIONER.vox"]])

      #expect(cast[0].providers == ["voxalta"])
      #expect(cast[0].voice(for: "voxalta") == "voices/NARRATOR.vox")
      #expect(
        cast[0].voiceDescription
          == "Deep authoritative British baritone. Warm, commanding documentary narrator. "
            + "Rich resonance, measured pacing.")

      // Fields the file does not set must not be invented.
      #expect(cast.allSatisfy { $0.actor == nil })
      #expect(cast.allSatisfy { $0.gender == nil })
      #expect(cast.allSatisfy { $0.language == nil })
    }
  }

  /// `lazarillo`'s first member, in full: every provider key, every voice id, and both of
  /// its unknown per-member keys with their values.
  @Test("lazarillo: LAZARO's every provider, voice id, and unknown key")
  func lazarilloFirstMemberLiterals() throws {
    for value in [try decode("lazarillo"), try roundTripped("lazarillo")] {
      let cast = try #require(value.cast)
      #expect(cast.count == 29)
      #expect(cast.prefix(4).map(\.character) == ["LAZARO", "YOUNG LAZARO", "BLIND MAN", "ANTONA"])

      let lazaro = cast[0]
      #expect(lazaro.character == "LAZARO")
      #expect(lazaro.voices == ["voxalta": ["voices/lazaro.vox"]])
      #expect(lazaro.providers == ["voxalta"])
      #expect(lazaro.voiceDescription?.hasPrefix("A man in his early 40s") == true)

      #expect(lazaro.extraKeys.keys.sorted() == ["aliases", "episodes"])
      let aliases = try #require(lazaro.extraKeys["aliases"]).decode([String].self)
      let episodes = try #require(lazaro.extraKeys["episodes"]).decode([Int].self)
      #expect(aliases == ["LAZARO", "NARRATOR"])
      #expect(episodes == [0, 1, 2, 3, 4, 5, 6, 7])

      // The last member is reached too, so a decoder that truncated the array would fail
      // on something other than the count. It is one of five background crowds in this
      // file that carry no voice at all — the real-file version of the minimal member.
      #expect(cast[28].character == "SUPPLICANTS")
      #expect(cast[28].voices.isEmpty)
      #expect(cast[28].voiceDescription == "Background — no dialogue")
      #expect(cast[28].extraKeys.keys.sorted() == ["episodes"])
      #expect(cast.filter { $0.voices.isEmpty }.count == 5)
    }
  }

  /// `yntswyd` is the only fixture that declares `gender`, so it is the only one that can
  /// catch a decoder which dropped it. All 49 members carry one.
  @Test("yntswyd: gender is decoded, for every member")
  func yntswydGenderLiterals() throws {
    for value in [try decode("yntswyd"), try roundTripped("yntswyd")] {
      let cast = try #require(value.cast)
      #expect(cast.count == 49)
      #expect(cast.allSatisfy { $0.gender != nil }, "a member lost its gender")

      #expect(cast[0].character == "NARRATOR")
      #expect(cast[0].gender == .male)
      #expect(cast[1].character == "BERNARD")
      #expect(cast[1].gender == .male)
      #expect(cast[3].character == "SYLVIA")
      #expect(cast[3].gender == .female)

      #expect(cast.filter { $0.gender == .female }.count == 20)
      #expect(cast.filter { $0.gender == .male }.count == 29)

      // The legacy `voiceDescription` spelling, which this whole cast uses.
      #expect(
        cast[0].voiceDescription
          == "Warm, mid-range male voice. Steady pacing with an engaging storytelling tone. "
            + "Hint of dark humor and irony beneath a smooth, audiobook-quality delivery.")

      // Eight members carry an `arc:` note the model has never heard of.
      #expect(cast.filter { !$0.extraKeys.isEmpty }.count == 8)
      #expect(cast[1].extraKeys.keys.sorted() == ["arc"])
      let arc = try #require(cast[1].extraKeys["arc"]).decode(String.self)
      #expect(arc.hasPrefix("Begins the chapter as someone deeply broken by past trauma"))
    }
  }
}

// MARK: - Leg 3: expected values constructed in code, never decoded

@Suite("Round trips whose expected value was built in code")
struct ConstructedValueRoundTripTests {

  /// Stands in for the kind of unknown structure real files carry under a key the model
  /// has never heard of.
  struct IndexEntry: Codable, Equatable {
    let number: Int
    let title: String
  }

  /// The corpus uses one provider and one voice id per member, so nothing in it can catch
  /// a decoder that keeps only the first provider or only the first id. This value can.
  static let richMember = CastMember(
    character: "MAESTRA",
    actor: "Ana Ruiz",
    gender: .female,
    voiceDescription: "Warm mezzo, deliberate pacing",
    voices: [
      "voxalta": ["voices/MAESTRA.vox", "voices/MAESTRA-alt.vox"],
      "elevenlabs": ["21m00Tcm4TlvDq8ikWAM", "alternate-id"],
      "apple": ["com.apple.voice.premium.en-US.Ava"],
    ],
    language: "es-MX"
  )

  /// A whole front matter, cast and unknown keys included, built here rather than decoded,
  /// then written and read back. Nothing in the expected value came out of the decoder, so
  /// a decoder that drops a field cannot make this agree with itself.
  @Test("A front matter built in code survives encode and decode, field for field")
  func constructedFrontMatterSurvives() throws {
    let expected = ProjectFrontMatter(
      type: "project",
      title: "Constructed",
      author: "Nobody",
      created: Date(timeIntervalSince1970: 1_000_000),
      updated: Date(timeIntervalSince1970: 2_000_000),
      description: "built in code",
      genre: "Fiction",
      tags: ["a", "b"],
      episodesDir: "episodes",
      audioDir: "audio",
      filePattern: .multiple(["*.fountain", "*.highland"]),
      exportFormat: "m4a",
      introFile: "audio/intro.m4a",
      outroFile: "audio/outro.m4a",
      cast: [
        Self.richMember,
        CastMember(character: "NARRATOR"),
        CastMember(
          character: "CHORUS",
          voices: ["voxalta": ["voices/CHORUS.vox"]],
          extraKeys: ["bio": try AnyCodable("sings"), "arc": try AnyCodable([1, 2, 3])]),
      ],
      preGenerateHook: "pre",
      postGenerateHook: "post",
      tts: TTSConfig(model: "1.7b"),
      schemaVersion: 4,
      projectType: "project",
      seasons: [SeasonDefinition(number: 1, episodes: 9)],
      languages: [LanguageDefinition(code: "es", name: "Spanish")],
      variants: [VariantReference(season: 1, language: "es", path: "p")],
      episodePath: "episodes/<episode>.fountain",
      appSections: [
        "episodes_index": try AnyCodable([
          IndexEntry(number: 1, title: "ONE"), IndexEntry(number: 2, title: "TWO"),
        ])
      ]
    )

    let data = try ProjectFixtures.makeEncoder().encode(expected)
    let actual = try ProjectFixtures.makeDecoder().decode(ProjectFrontMatter.self, from: data)

    let diffs = FrontMatterComparison.differences(expected, actual)
    #expect(diffs.isEmpty, "\(diffs.joined(separator: "\n"))")

    // And the constructed cast really is a cast with something in it, so an empty-array
    // regression cannot pass the comparison by having nothing to compare.
    #expect(actual.cast?.count == 3)
    #expect(actual.cast?[0].voices.count == 3)
  }

  /// Every provider key and every voice id of a multi-provider member, named individually,
  /// on both sides of the round trip.
  @Test("A multi-provider member keeps every provider and every id")
  func multiProviderMemberSurvives() throws {
    let data = try ProjectFixtures.makeEncoder().encode(Self.richMember)
    let decoded = try ProjectFixtures.makeDecoder().decode(CastMember.self, from: data)

    #expect(decoded.providers == ["apple", "elevenlabs", "voxalta"])
    #expect(decoded.voices["voxalta"] == ["voices/MAESTRA.vox", "voices/MAESTRA-alt.vox"])
    #expect(decoded.voices["elevenlabs"] == ["21m00Tcm4TlvDq8ikWAM", "alternate-id"])
    #expect(decoded.voices["apple"] == ["com.apple.voice.premium.en-US.Ava"])
    #expect(decoded.actor == "Ana Ruiz")
    #expect(decoded.gender == .female)
    #expect(decoded.language == "es-MX")
    #expect(decoded.voiceDescription == "Warm mezzo, deliberate pacing")

    // The ids are in the written bytes, not merely in a value that came back out of the
    // decoder — the one statement about the encoder that no decoder bug can fake. Read
    // back with `JSONSerialization` rather than by searching the text, because
    // `JSONEncoder` escapes `/` as `\/` and two of these ids are paths.
    let written = try RawFixture.member(try RawFixture.object(data))
    #expect(written == RawFixture.project(Self.richMember))
    #expect(written.voices.values.flatMap { $0 }.count == 5)
  }

  /// The other end of the range: a member with nothing but a name must not acquire fields
  /// it never had, and must not lose the one it has.
  @Test("A member with only a character name gains nothing and loses nothing")
  func minimalMemberIsUnchanged() throws {
    let expected = CastMember(character: "NARRATOR")
    let data = try ProjectFixtures.makeEncoder().encode(expected)
    let actual = try ProjectFixtures.makeDecoder().decode(CastMember.self, from: data)

    #expect(RawFixture.project(actual) == RawFixture.project(expected))
    #expect(actual.voices.isEmpty)
    #expect(actual.extraKeys.isEmpty)
    #expect(actual.actor == nil)
    #expect(actual.gender == nil)
    #expect(actual.language == nil)
    #expect(actual.voiceDescription == nil)
  }
}

// MARK: - The self-test for the raw reader

/// Leg 1 is only as good as ``RawFixture``. A reader that returned an empty cast, or a
/// difference function that never reported anything, would make every assertion above pass
/// against any implementation of the model whatsoever. Each mutation below must be seen.
@Suite("The byte reader itself notices a change")
struct RawFixtureSelfTests {

  /// A function rather than a `static let`: `[String: Any]` is not `Sendable`, and a
  /// stored static of that type does not compile under strict concurrency.
  private static func sample() -> [String: Any] {
    [
      "character": "MAESTRA",
      "actor": "Ana Ruiz",
      "gender": "F",
      "voicePrompt": "Warm mezzo",
      "voices": ["Voxalta": "a.vox", "elevenlabs": ["b", "c"]],
      "language": "es-MX",
      "bio": "a bio",
    ]
  }

  @Test("The reader applies the normalizations the decoder is supposed to apply")
  func readerNormalizes() throws {
    let member = try RawFixture.member(Self.sample())
    #expect(member.character == "MAESTRA")
    #expect(member.actor == "Ana Ruiz")
    #expect(member.gender == "F")
    #expect(member.voiceDescription == "Warm mezzo")
    // Provider lowercased; a bare string became a one-element array; an array was kept.
    #expect(member.voices == ["voxalta": ["a.vox"], "elevenlabs": ["b", "c"]])
    #expect(member.language == "es-MX")
    #expect(member.extraKeys == ["bio"])
  }

  @Test("voicePrompt wins over voiceDescription, and either alone is read")
  func readerPrefersVoicePrompt() throws {
    var both = Self.sample()
    both["voiceDescription"] = "legacy text"
    let preferred = try RawFixture.member(both).voiceDescription
    #expect(preferred == "Warm mezzo")

    var legacyOnly = Self.sample()
    legacyOnly["voicePrompt"] = nil
    legacyOnly["voiceDescription"] = "legacy text"
    let fallback = try RawFixture.member(legacyOnly).voiceDescription
    #expect(fallback == "legacy text")
  }

  @Test("Every field the difference function claims to check is actually checked")
  func differencesSeeEveryField() throws {
    let base = try RawFixture.member(Self.sample())

    var mutations: [(String, RawFixture.Member)] = []
    var m = base
    m.character = "OTHER"
    mutations.append(("character", m))
    m = base
    m.actor = nil
    mutations.append(("actor", m))
    m = base
    m.gender = "M"
    mutations.append(("gender", m))
    m = base
    m.voiceDescription = nil
    mutations.append(("voiceDescription", m))
    m = base
    m.voices = [:]
    mutations.append(("voices", m))
    m = base
    m.voices["elevenlabs"] = ["b"]
    mutations.append(("voices", m))
    m = base
    m.language = "en"
    mutations.append(("language", m))
    m = base
    m.extraKeys = []
    mutations.append(("extraKeys", m))

    for (field, mutated) in mutations {
      let diffs = RawFixture.differences(base, mutated, at: 0)
      #expect(
        diffs.contains(where: { $0.contains(field) }),
        "the byte comparison did not notice a change to \(field)")
    }
    #expect(RawFixture.differences(base, base, at: 0).isEmpty)
  }

  /// The projection from `CastMember` has to agree with the reader, or leg 1 compares two
  /// things that were never comparable.
  @Test("Projecting a decoded member yields the same shape the reader produces")
  func projectionAgreesWithReader() throws {
    let data = try JSONSerialization.data(withJSONObject: Self.sample())
    let decoded = try ProjectFixtures.makeDecoder().decode(CastMember.self, from: data)
    let read = try RawFixture.member(Self.sample())
    #expect(RawFixture.project(decoded) == read)
  }

  @Test("The reader finds a non-empty cast in every fixture", arguments: ProjectFixtures.all)
  func readerFindsCast(_ fixture: ProjectFixture) throws {
    let count = try RawFixture.cast(fixture.name).count
    #expect(count == fixture.expectedCastCount)
  }
}
