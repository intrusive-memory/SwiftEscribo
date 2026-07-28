import Foundation
import Testing

@testable import EscriboProject

// MARK: - Field-by-field comparison

/// Compares two `ProjectFrontMatter` values field by field and reports what differs.
///
/// ## Why `==` is not enough
///
/// `ProjectFrontMatter` synthesizes `Equatable`, and `cast` is one of its stored
/// properties — but `CastMember` overrides `==` to compare **character names only**. So
/// `a == b` is true for two front matters whose casts have lost every voice, every actor,
/// every language and every unknown key, as long as the names still line up. Asserting
/// `a == b` on a round trip therefore proves close to nothing about the part of the model
/// most likely to lose data.
///
/// This comparator exists to close that hole. Everything the model stores is compared
/// explicitly, and cast members are compared on all seven of their fields.
enum FrontMatterComparison {

  /// Returns a human-readable description of each difference. Empty means equal.
  ///
  /// - Parameter ignoringSchemaVersion: `schemaVersion` is asymmetric by design — it
  ///   decodes as `nil` for a legacy file and is always written as `4` — so a legacy
  ///   fixture can never satisfy `decode(x) == decode(encode(decode(x)))` on that one
  ///   field. See DL-152.
  static func differences(
    _ a: ProjectFrontMatter,
    _ b: ProjectFrontMatter,
    ignoringSchemaVersion: Bool = false
  ) -> [String] {
    var out: [String] = []

    func compare<T: Equatable>(_ label: String, _ lhs: T, _ rhs: T) {
      if lhs != rhs {
        out.append("\(label): \(String(describing: lhs)) != \(String(describing: rhs))")
      }
    }

    compare("type", a.type, b.type)
    compare("title", a.title, b.title)
    compare("author", a.author, b.author)
    compare("created", a.created, b.created)
    compare("updated", a.updated, b.updated)
    compare("description", a.description, b.description)
    compare("genre", a.genre, b.genre)
    compare("tags", a.tags, b.tags)
    compare("episodesDir", a.episodesDir, b.episodesDir)
    compare("audioDir", a.audioDir, b.audioDir)
    compare("filePattern", a.filePattern, b.filePattern)
    compare("exportFormat", a.exportFormat, b.exportFormat)
    compare("introFile", a.introFile, b.introFile)
    compare("outroFile", a.outroFile, b.outroFile)
    compare("preGenerateHook", a.preGenerateHook, b.preGenerateHook)
    compare("postGenerateHook", a.postGenerateHook, b.postGenerateHook)
    compare("tts", a.tts, b.tts)
    compare("projectType", a.projectType, b.projectType)
    compare("seasons", a.seasons, b.seasons)
    compare("languages", a.languages, b.languages)
    compare("variants", a.variants, b.variants)
    compare("episodePath", a.episodePath, b.episodePath)

    // Reported by key rather than by value: an `appSections` value can be tens of
    // kilobytes, and a failure message that dumps two of them is unreadable.
    let leftKeys = Set(a.appSections.keys)
    let rightKeys = Set(b.appSections.keys)
    if leftKeys != rightKeys {
      out.append(
        "appSections keys: only-left \(leftKeys.subtracting(rightKeys).sorted()), "
          + "only-right \(rightKeys.subtracting(leftKeys).sorted())")
    }
    for key in leftKeys.intersection(rightKeys) where a.appSections[key] != b.appSections[key] {
      out.append("appSections[\(key)]: value changed")
    }

    if !ignoringSchemaVersion {
      compare("schemaVersion", a.schemaVersion, b.schemaVersion)
    }

    out.append(contentsOf: castDifferences(a.cast, b.cast))
    return out
  }

  /// Compares two cast lists on every field, in order.
  static func castDifferences(_ a: [CastMember]?, _ b: [CastMember]?) -> [String] {
    switch (a, b) {
    case (nil, nil):
      return []
    case (nil, .some(let rhs)):
      return ["cast: nil != \(rhs.count) members"]
    case (.some(let lhs), nil):
      return ["cast: \(lhs.count) members != nil"]
    case (.some(let lhs), .some(let rhs)):
      guard lhs.count == rhs.count else {
        return ["cast: \(lhs.count) members != \(rhs.count) members"]
      }
      var out: [String] = []
      for (index, pair) in zip(lhs, rhs).enumerated() {
        out.append(contentsOf: memberDifferences(pair.0, pair.1, at: index))
      }
      return out
    }
  }

  static func memberDifferences(_ a: CastMember, _ b: CastMember, at index: Int) -> [String] {
    var out: [String] = []
    let tag = "cast[\(index)]"

    func compare<T: Equatable>(_ label: String, _ lhs: T, _ rhs: T) {
      if lhs != rhs {
        out.append("\(tag).\(label): \(String(describing: lhs)) != \(String(describing: rhs))")
      }
    }

    compare("character", a.character, b.character)
    compare("actor", a.actor, b.actor)
    compare("gender", a.gender, b.gender)
    compare("voiceDescription", a.voiceDescription, b.voiceDescription)
    compare("voices", a.voices, b.voices)
    compare("language", a.language, b.language)
    compare("extraKeys", a.extraKeys, b.extraKeys)
    return out
  }
}

@Suite("The field comparator itself notices a change")
struct ComparatorSelfTests {

  /// A comparator that reported "no differences" for everything would make every test in
  /// this file green forever. Each field gets one mutation and must be seen.
  @Test("Every cast field the comparator claims to check is actually checked")
  func comparatorSeesEveryCastField() throws {
    let base = CastMember(
      character: "NARRATOR",
      actor: "Tom Stovall",
      gender: .male,
      voiceDescription: "deep",
      voices: ["voxalta": ["a.vox"]],
      language: "en",
      extraKeys: ["bio": try AnyCodable("a bio")]
    )

    var mutations: [(String, CastMember)] = []
    var m = base
    m.character = "OTHER"
    mutations.append(("character", m))
    m = base
    m.actor = "Someone Else"
    mutations.append(("actor", m))
    m = base
    m.gender = .female
    mutations.append(("gender", m))
    m = base
    m.voiceDescription = "shallow"
    mutations.append(("voiceDescription", m))
    m = base
    m.voices = ["voxalta": ["b.vox"]]
    mutations.append(("voices", m))
    m = base
    m.language = "es"
    mutations.append(("language", m))
    m = base
    m.extraKeys = ["bio": try AnyCodable("a different bio")]
    mutations.append(("extraKeys", m))

    for (field, mutated) in mutations {
      let diffs = FrontMatterComparison.memberDifferences(base, mutated, at: 0)
      #expect(
        diffs.contains(where: { $0.contains(field) }),
        "the comparator did not notice a change to \(field)")
    }

    #expect(FrontMatterComparison.memberDifferences(base, base, at: 0).isEmpty)
  }

  @Test("The comparator notices a dropped appSections key")
  func comparatorSeesAppSections() throws {
    let a = ProjectFrontMatter(
      title: "T", author: "A", created: Date(timeIntervalSince1970: 0),
      appSections: ["extra": try AnyCodable(["k": "v"])])
    let b = ProjectFrontMatter(
      title: "T", author: "A", created: Date(timeIntervalSince1970: 0))

    let diffs = FrontMatterComparison.differences(a, b)
    #expect(diffs.contains(where: { $0.hasPrefix("appSections") }))
    #expect(FrontMatterComparison.differences(a, a).isEmpty)
  }
}

// MARK: - The round-trip gate

@Suite("PROJECT.md front matter survives a decode/encode round trip")
struct ProjectFrontMatterRoundTripTests {

  /// Decodes the fixture, re-encodes it, and decodes again — twice, so the second and
  /// third values are both past the one-time v3 → v4 normalization.
  private func roundTrip(_ fixture: ProjectFixture) throws -> (
    first: ProjectFrontMatter, second: ProjectFrontMatter, third: ProjectFrontMatter
  ) {
    let data = try #require(ProjectFixtures.frontMatterJSON(fixture.name))
    let decoder = ProjectFixtures.makeDecoder()
    let encoder = ProjectFixtures.makeEncoder()

    let first = try decoder.decode(ProjectFrontMatter.self, from: data)
    let second = try decoder.decode(ProjectFrontMatter.self, from: encoder.encode(first))
    let third = try decoder.decode(ProjectFrontMatter.self, from: encoder.encode(second))
    return (first, second, third)
  }

  @Test(
    "Every field survives the round trip, including every unknown key",
    arguments: ProjectFixtures.all)
  func everyFieldSurvives(_ fixture: ProjectFixture) throws {
    let (first, second, _) = try roundTrip(fixture)

    // The fixture must actually contain something to lose.
    #expect(first.title.isEmpty == false)
    #expect(
      first.cast?.count == fixture.expectedCastCount,
      """
      \(fixture.name): decoded \(first.cast?.count ?? -1) cast members, \
      expected \(fixture.expectedCastCount)
      """)

    let diffs = FrontMatterComparison.differences(first, second, ignoringSchemaVersion: true)
    #expect(diffs.isEmpty, "\(fixture.name) lost or changed:\n\(diffs.joined(separator: "\n"))")
  }

  @Test(
    "Unknown top-level keys land in appSections and come back out",
    arguments: ProjectFixtures.all)
  func unknownKeysSurvive(_ fixture: ProjectFixture) throws {
    let (first, second, third) = try roundTrip(fixture)

    #expect(
      Set(first.appSections.keys) == fixture.expectedUnknownTopLevelKeys,
      """
      \(fixture.name): decoded unknown keys \(first.appSections.keys.sorted()), \
      expected \(fixture.expectedUnknownTopLevelKeys.sorted())
      """)
    #expect(Set(second.appSections.keys) == fixture.expectedUnknownTopLevelKeys)
    #expect(Set(third.appSections.keys) == fixture.expectedUnknownTopLevelKeys)

    // Not just the key names — the values, byte for byte. `AnyCodable` compares its
    // canonical encoded form, so this catches a value that survived as a truncated or
    // re-ordered shadow of itself.
    for key in fixture.expectedUnknownTopLevelKeys {
      #expect(first.appSections[key] == second.appSections[key], "\(fixture.name): \(key) changed")
      #expect(second.appSections[key] == third.appSections[key], "\(fixture.name): \(key) drifted")
    }
  }

  @Test("The round trip is stable once past the v4 normalization", arguments: ProjectFixtures.all)
  func stableAfterFirstEncode(_ fixture: ProjectFixture) throws {
    let (_, second, third) = try roundTrip(fixture)
    let diffs = FrontMatterComparison.differences(second, third)
    #expect(diffs.isEmpty, "\(fixture.name) is not stable:\n\(diffs.joined(separator: "\n"))")
    #expect(second == third)
  }

  @Test("A file that already declares schemaVersion 4 round-trips with no change at all")
  func alreadyV4RoundTripsExactly() throws {
    let fixture = try #require(ProjectFixtures.all.first { $0.name == "granville" })
    let (first, second, _) = try roundTrip(fixture)

    #expect(first.schemaVersion == 4, "the granville fixture is supposed to be the v4 case")
    let diffs = FrontMatterComparison.differences(first, second)
    #expect(diffs.isEmpty, "granville changed:\n\(diffs.joined(separator: "\n"))")
  }
}

// MARK: - The keys this model exists to protect

@Suite("Named unknown keys from real files")
struct NamedUnknownKeyTests {

  private func decode(_ name: String) throws -> ProjectFrontMatter {
    let data = try #require(ProjectFixtures.frontMatterJSON(name))
    return try ProjectFixtures.makeDecoder().decode(ProjectFrontMatter.self, from: data)
  }

  private func roundTripped(_ name: String) throws -> ProjectFrontMatter {
    let value = try decode(name)
    let data = try ProjectFixtures.makeEncoder().encode(value)
    return try ProjectFixtures.makeDecoder().decode(ProjectFrontMatter.self, from: data)
  }

  /// The shape of one entry in `confessions`' `episodes_index`, which the model has never
  /// heard of. Decoding `appSections` back into a concrete type is the strongest available
  /// statement that the value survived: a mechanism that kept the key but flattened the
  /// value to a string, an empty object, or a null would fail here and pass a key-name
  /// check.
  private struct EpisodeIndexEntry: Codable {
    let number: Int
    let title: String
    let summary: String
    let keywords: [String]
  }

  @Test("A 69-entry unknown array survives with its structure intact")
  func episodesIndexSurvives() throws {
    let after = try roundTripped("confessions")
    let raw = try #require(after.appSections["episodes_index"])
    let entries = try raw.decode([EpisodeIndexEntry].self)

    #expect(entries.count == 69)
    #expect(entries.first?.number == 1)
    #expect(entries.first?.title == "CODE REVIEW")
    #expect(entries.first?.keywords == ["ADHD", "shame", "code-review", "AI-tools", "workplace"])
    #expect(entries.last?.number == 69)
    #expect(entries.last?.title == "WITHOUT A NET")
    #expect(entries.first?.summary.hasPrefix("The Practitioner brings shame") == true)
  }

  private struct EpisodeListEntry: Codable {
    let file: String
    let title: String
  }

  @Test("A differently-named unknown array in a different file also survives")
  func episodeListSurvives() throws {
    let after = try roundTripped("aunt-stanley")
    let raw = try #require(after.appSections["episodeList"])
    let entries = try raw.decode([EpisodeListEntry].self)

    #expect(entries.count == 9)
    #expect(entries.first?.file == "episodes/chapter-1.fountain")
    #expect(entries.first?.title == "Chapter 1: Ladies of the Morning")
  }

  @Test("An unknown key on a single cast member survives")
  func castMemberExtraKeySurvives() throws {
    let before = try decode("confessions")
    let after = try roundTripped("confessions")

    let index = try #require(before.cast?.firstIndex { $0.character == "THE PRACTITIONER" })
    let beforeMember = try #require(before.cast?[index])
    let afterMember = try #require(after.cast?[index])

    #expect(beforeMember.extraKeys.keys.sorted() == ["bio"])
    #expect(afterMember.extraKeys.keys.sorted() == ["bio"])

    let bio = try #require(afterMember.extraKeys["bio"]).decode(String.self)
    #expect(bio.hasPrefix("Neurodivergent (ADHD), gay Gen X developer"))
    #expect(bio.hasSuffix("Brings the wound; asks the questions."))
    #expect(bio.contains("The bridge generation"))

    // And the members that had no extra keys did not acquire any.
    for member in try #require(after.cast) where member.character != "THE PRACTITIONER" {
      #expect(member.extraKeys.isEmpty, "\(member.character) grew keys it never had")
    }
  }

  @Test("A cast member with every field populated round-trips field for field")
  func fullyPopulatedMemberSurvives() throws {
    let member = CastMember(
      character: "MAESTRA",
      actor: "Ana Ruiz",
      gender: .female,
      voiceDescription: "Warm mezzo, deliberate pacing",
      voices: [
        "voxalta": ["voices/MAESTRA.vox"],
        "elevenlabs": ["21m00Tcm4TlvDq8ikWAM", "alternate-id"],
      ],
      language: "es-MX",
      extraKeys: ["bio": try AnyCodable("Teacher"), "notes": try AnyCodable([1, 2, 3])]
    )

    let data = try ProjectFixtures.makeEncoder().encode(member)
    let decoded = try ProjectFixtures.makeDecoder().decode(CastMember.self, from: data)

    let diffs = FrontMatterComparison.memberDifferences(member, decoded, at: 0)
    #expect(diffs.isEmpty, "\(diffs.joined(separator: "\n"))")
  }

  @Test("A cast member with only a character name round-trips")
  func minimalMemberSurvives() throws {
    let member = CastMember(character: "NARRATOR")
    let data = try ProjectFixtures.makeEncoder().encode(member)
    let decoded = try ProjectFixtures.makeDecoder().decode(CastMember.self, from: data)

    #expect(FrontMatterComparison.memberDifferences(member, decoded, at: 0).isEmpty)
    #expect(decoded.voices.isEmpty)
    #expect(decoded.extraKeys.isEmpty)
  }
}

// MARK: - Behaviour carried over from SwiftProyecto, recorded rather than changed

/// Sortie 32 moved this model without redesigning it. These tests pin down the parts of
/// its behaviour that are surprising or lossy, so that the move is auditable and so that a
/// later change to any of them is a deliberate act rather than an accident.
///
/// Each one asserts what the code does **today**. None of them is an endorsement.
@Suite("Documented behaviour of the vendored model")
struct KnownDefectTests {

  private func decode(_ name: String) throws -> ProjectFrontMatter {
    let data = try #require(ProjectFixtures.frontMatterJSON(name))
    return try ProjectFixtures.makeDecoder().decode(ProjectFrontMatter.self, from: data)
  }

  /// **DL-151** — a top-level `episodes:` with no accompanying `season:` is discarded.
  ///
  /// `init(from:)` reads both v3 scalars, but only synthesizes a `SeasonDefinition` when
  /// `season` is present; with `season` absent the episode count has nowhere to go and is
  /// dropped. It is a *known* key, so it is not rescued by `appSections` either. Three of
  /// the four vendored files are in exactly this shape, and `confessions` loses the number
  /// 69 on any write-back.
  @Test("DL-151: `episodes` without `season` is silently dropped")
  func episodesWithoutSeasonIsLost() throws {
    let confessions = try decode("confessions")
    #expect(confessions.seasons == nil)
    #expect(confessions.episodes == nil, "if this is now 69, DL-151 has been fixed — update this test")

    // The committed file really does carry it, so the loss is real and not a fixture that
    // never had the key.
    let markdown = try #require(ProjectFixtures.markdown("confessions"))
    #expect(FrontMatterKeyScan.topLevelKeys(in: markdown).contains("episodes"))
  }

  /// The same defect, stated the way Sortie 33's byte oracle states things — and the proof
  /// that the technique in ``FixtureByteOracleTests`` is what finds this class of bug.
  ///
  /// The expected value here is read out of the committed bytes by `JSONSerialization`,
  /// which never touches `ProjectFrontMatter.init(from:)`. It disagrees with the model.
  /// Had DL-151 not already been documented, an oracle of this shape extended from `cast`
  /// to the top-level scalars would have reported it on its first run — which is the whole
  /// argument for building the gate this way rather than as a second decode.
  ///
  /// Not extended to the top-level scalars in the shipped gate, because doing so would
  /// turn it red for a defect this sortie is explicitly not authorized to fix.
  @Test("DL-151 stated against the committed bytes rather than against a second decode")
  func episodesLossIsVisibleInTheBytes() throws {
    let raw = try RawFixture.topLevel("confessions")
    #expect(raw["episodes"] as? Int == 69, "the committed bytes are supposed to carry 69")
    #expect(raw["season"] == nil, "and no season, which is what triggers the loss")

    let decoded = try decode("confessions")
    #expect(
      decoded.episodes == nil,
      """
      if this is now 69, DL-151 has been fixed — update this test and extend the byte \
      oracle to the top-level scalars
      """)

    // Three of the six fixtures are in this shape. `yntswyd` loses 9 the same way.
    let yntswyd = try RawFixture.topLevel("yntswyd")
    let decodedYntswyd = try decode("yntswyd")
    #expect(yntswyd["episodes"] as? Int == 9)
    #expect(decodedYntswyd.episodes == nil)

    // `lazarillo` carries the pair, so it does not lose anything — the contrast that makes
    // this a gap rather than a policy.
    let lazarillo = try RawFixture.topLevel("lazarillo")
    let decodedLazarillo = try decode("lazarillo")
    #expect(lazarillo["season"] as? Int == 1)
    #expect(lazarillo["episodes"] as? Int == 8)
    #expect(decodedLazarillo.episodes == 8)
  }

  /// **DL-159** — a cast member that carries **both** `voicePrompt` and the legacy
  /// `voiceDescription` loses the `voiceDescription` text outright on decode.
  ///
  /// `init(from:)` reads `voicePrompt` and falls back to `voiceDescription`, storing one
  /// string in one property. `voiceDescription` is a declared `CodingKey`, so it is *not*
  /// swept into `extraKeys` either: the text is simply gone, and the next write-back
  /// deletes it from the file. This is a second live instance of Fact 0 — a decode-side
  /// loss that no decode/encode/decode round trip can see — and it was found by the byte
  /// oracle in ``FixtureByteOracleTests`` on its first run against the `lazarillo` fixture,
  /// where 24 of 29 members are in this shape.
  ///
  /// Recorded, not repaired: fixing it changes decode behaviour and the shape of the
  /// model, which is a user decision this sortie has no authority to make.
  @Test("DL-159: a member carrying both voice spellings loses the legacy one")
  func bothVoiceSpellingsLosesTheLegacyOne() throws {
    let json = """
      {"character":"LAZARO","voicePrompt":"the prompt","voiceDescription":"the legacy text",
       "voices":{"voxalta":"voices/lazaro.vox"}}
      """
    let decoded = try ProjectFixtures.makeDecoder().decode(CastMember.self, from: Data(json.utf8))

    #expect(decoded.voiceDescription == "the prompt")
    #expect(
      decoded.extraKeys.isEmpty,
      "if `voiceDescription` is now in extraKeys, DL-159 has been fixed — update this test")

    let written = String(decoding: try ProjectFixtures.makeEncoder().encode(decoded), as: UTF8.self)
    #expect(!written.contains("the legacy text"), "if this now round-trips, DL-159 is fixed")

    // And it is not a synthetic shape: the committed `lazarillo` fixture is full of it.
    let raw = try RawFixture.cast("lazarillo")
    let topLevel = try RawFixture.topLevel("lazarillo")
    let rawObjects = try #require(topLevel["cast"] as? [[String: Any]])
    let carryingBoth = rawObjects.filter { $0["voicePrompt"] != nil && $0["voiceDescription"] != nil }
    #expect(carryingBoth.count == 24, "the fixture no longer exercises DL-159")
    #expect(raw.count == 29)

    let first = try #require(carryingBoth.first)
    #expect(
      first["voiceDescription"] as? String
        == "Adult Lazaro — narrator and protagonist across all episodes")
    let lazarilloCast = try decode("lazarillo").cast
    let decodedFirst = try #require(lazarilloCast?.first)
    #expect(decodedFirst.character == "LAZARO")
    #expect(decodedFirst.voiceDescription?.hasPrefix("A man in his early 40s") == true)
    #expect(
      decodedFirst.voiceDescription != (first["voiceDescription"] as? String),
      "if these now agree, DL-159 has been fixed")
  }

  /// The v3 pair *together* does migrate, which is what makes DL-151 a gap rather than a
  /// deliberate policy of ignoring the legacy keys.
  @Test("`season` and `episodes` together migrate into a seasons array")
  func v3PairMigrates() throws {
    let dailyDao = try decode("daily-dao")
    #expect(dailyDao.seasons?.count == 1)
    #expect(dailyDao.seasons?.first?.number == 1)
    #expect(dailyDao.seasons?.first?.episodes == 81)
    #expect(dailyDao.season == 1)
    #expect(dailyDao.episodes == 81)
  }

  /// **DL-152** — `encode(to:)` writes `schemaVersion: 4` unconditionally, so a legacy
  /// file is stamped as v4 by the first write-back and `isLegacyV3Format` — documented as
  /// tracking the origin — reports `false` from then on.
  ///
  /// This matters beyond tidiness: it means `decode(encode(decode(x))) == decode(x)`, the
  /// formulation a round-trip gate reaches for first, is **false** for every legacy file
  /// in the corpus. A gate written that way fails for a reason that has nothing to do with
  /// data loss.
  @Test("DL-152: a legacy file is stamped schemaVersion 4 on the first write-back")
  func schemaVersionIsForced() throws {
    let before = try decode("confessions")
    #expect(before.schemaVersion == nil)
    #expect(before.isLegacyV3Format)

    let data = try ProjectFixtures.makeEncoder().encode(before)
    let after = try ProjectFixtures.makeDecoder().decode(ProjectFrontMatter.self, from: data)
    #expect(after.schemaVersion == 4)
    #expect(after.isLegacyV3Format == false)

    // Which is exactly why the gate above compares field by field with schemaVersion
    // excluded rather than using `==`.
    #expect(before != after)
    #expect(FrontMatterComparison.differences(before, after, ignoringSchemaVersion: true).isEmpty)
  }

  /// **DL-153** — `withCast(_:)` rebuilds the value through the memberwise initializer but
  /// never passes `updated`, so calling it erases the last-updated date.
  @Test("DL-153: withCast(_:) drops `updated`")
  func withCastDropsUpdated() throws {
    let original = ProjectFrontMatter(
      title: "T",
      author: "A",
      created: Date(timeIntervalSince1970: 0),
      updated: Date(timeIntervalSince1970: 86_400),
      cast: [CastMember(character: "NARRATOR")]
    )
    #expect(original.updated != nil)

    let replaced = original.withCast([CastMember(character: "OTHER")])
    #expect(
      replaced.updated == nil,
      "if `updated` survived, DL-153 has been fixed — update this test")

    // `normalizingPaths(relativeTo:)`, the other rebuild-through-init helper, does pass it.
    let normalized = original.normalizingPaths(relativeTo: URL(fileURLWithPath: "/tmp"))
    #expect(normalized.updated == original.updated)
  }

  /// **DL-154** — `CastMember.MergeStrategy.preserveExisting` and `.preferNew` are
  /// documented as opposites but their implementations are line-for-line identical, so the
  /// two strategies cannot produce different results for any input.
  @Test("DL-154: preserveExisting and preferNew are indistinguishable")
  func mergeStrategiesAreIdentical() {
    let existing = CastMember(
      character: "NARRATOR", actor: "Tom", gender: .male,
      voiceDescription: "deep", voices: ["voxalta": ["a.vox"]], language: "en")
    let incoming = CastMember(
      character: "NARRATOR", actor: "Ana", gender: .female,
      voiceDescription: "warm", voices: ["elevenlabs": ["b"]], language: "es")

    let preserved = existing.merge(with: incoming, strategy: .preserveExisting)
    let preferred = existing.merge(with: incoming, strategy: .preferNew)

    #expect(
      FrontMatterComparison.memberDifferences(preserved, preferred, at: 0).isEmpty,
      "if these now differ, DL-154 has been fixed — update this test")

    // `.combine` really is a third behaviour, so the two above are the anomaly.
    let combined = existing.merge(with: incoming, strategy: .combine)
    #expect(combined.voices == ["voxalta": ["a.vox"], "elevenlabs": ["b"]])
    #expect(combined.actor == "Tom")
  }

  /// A single voice string is accepted on decode and rewritten as a one-element array.
  /// Every vendored file uses the string form, so this is the normalization that actually
  /// runs in practice.
  @Test("A legacy single-string voice becomes a one-element array")
  func singleVoiceStringIsNormalized() throws {
    let json = #"{"character":"NARRATOR","voices":{"voxalta":"voices/NARRATOR.vox"}}"#
    let decoded = try ProjectFixtures.makeDecoder().decode(
      CastMember.self, from: Data(json.utf8))
    #expect(decoded.voices == ["voxalta": ["voices/NARRATOR.vox"]])

    let reencoded = try ProjectFixtures.makeEncoder().encode(decoded)
    #expect(String(decoding: reencoded, as: UTF8.self).contains(#""voices":{"voxalta":["#))
  }

  /// `voiceDescription` is read from either `voicePrompt` or the legacy
  /// `voiceDescription`, and always written back as `voicePrompt`.
  @Test("voiceDescription is read from two spellings and written as one")
  func voicePromptSpellingIsNormalized() throws {
    let decoder = ProjectFixtures.makeDecoder()
    let legacy = try decoder.decode(
      CastMember.self,
      from: Data(#"{"character":"N","voices":{},"voiceDescription":"deep"}"#.utf8))
    let current = try decoder.decode(
      CastMember.self,
      from: Data(#"{"character":"N","voices":{},"voicePrompt":"deep"}"#.utf8))

    #expect(legacy.voiceDescription == "deep")
    #expect(current.voiceDescription == "deep")

    let written = String(
      decoding: try ProjectFixtures.makeEncoder().encode(legacy), as: UTF8.self)
    #expect(written.contains("voicePrompt"))
    #expect(!written.contains("voiceDescription"))
  }
}
