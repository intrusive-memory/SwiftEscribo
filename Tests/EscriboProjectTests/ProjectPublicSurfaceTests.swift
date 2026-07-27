import Foundation
import Testing

// Deliberately NOT `@testable`. Every other file in this target uses `@testable import
// EscriboProject`, which means every assertion any of them makes about `appSections` and
// `extraKeys` would keep passing with both properties `internal` — which is exactly the
// state Sortie 30 found them in (DL-157). This file is the one that sees the module the
// way a host app does.
import EscriboProject

/// The unknown-key accessors, reached from outside the module.
///
/// ## What DL-157 actually was
///
/// `ProjectFrontMatter.appSections` and `CastMember.extraKeys` are the mechanism that makes
/// a `PROJECT.md` round-trip lossless for keys this model has never heard of. Both were
/// `internal` with no public accessor of any kind, while the public memberwise initializers
/// already took them as parameters — so an outside caller could *write* unknown keys and
/// could not *read* them back. The preservation guarantee existed and was unobservable.
///
/// Sortie 30 made both `public internal(set)`. This suite is the check that the change is
/// real, and it is written against a synthesized document rather than a fixture on purpose:
/// no `Bundle.module` lookup, no committed bytes, nothing that could make it pass by
/// accident of what a vendored file happens to contain.
@Suite("EscriboProject public surface (no @testable import)")
struct ProjectPublicSurfaceTests {

  /// A minimal v4 project carrying one unknown top-level key and one cast member with one
  /// unknown per-member key. Both unknown values are *structured* rather than scalar, which
  /// is the case a naive "keep the strings" implementation gets wrong.
  static let json = """
    {
      "type": "project",
      "title": "A Test Project",
      "author": "Nobody",
      "created": 0,
      "cast": [
        {
          "character": "MARGARET",
          "voices": {"qwen": ["margaret.vox"]},
          "arc": {"season": 2, "note": "she leaves"}
        }
      ],
      "verbsCovered": ["ser", "estar"]
    }
    """

  static func decoded() throws -> ProjectFrontMatter {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    return try decoder.decode(ProjectFrontMatter.self, from: Data(json.utf8))
  }

  @Test("A consumer outside the module can read the unknown top-level keys it round-trips")
  func appSectionsAreReadable() throws {
    let project = try Self.decoded()

    // Present, named, and *only* the unknown one — a decoder that swept a known key in here
    // would preserve it too and would also be wrong.
    #expect(project.appSections.keys.sorted() == ["verbsCovered"])
    let verbs = try #require(project.appSections["verbsCovered"]).decode([String].self)
    #expect(verbs == ["ser", "estar"])

    // The known keys really did decode into their own members, so `appSections` is the
    // remainder rather than a copy of the document.
    #expect(project.title == "A Test Project")
    #expect(project.cast?.count == 1)
  }

  @Test("A consumer outside the module can read a cast member's unknown keys")
  func extraKeysAreReadable() throws {
    let member = try #require(try Self.decoded().cast?.first)

    #expect(member.character == "MARGARET")
    #expect(member.voices["qwen"] == ["margaret.vox"])
    #expect(member.extraKeys.keys.sorted() == ["arc"])

    // Structured, not stringified. `AnyCodable.decode(_:)` is public, and this is the only
    // thing a consumer can usefully do with a value out of either dictionary — so reading
    // the key set without being able to decode a value would have closed half the gap.
    struct Arc: Codable, Equatable {
      let season: Int
      let note: String
    }
    let arc = try #require(member.extraKeys["arc"]).decode(Arc.self)
    #expect(arc == Arc(season: 2, note: "she leaves"))
  }

  @Test("Unknown keys written from outside the module survive an encode/decode round trip")
  func unknownKeysRoundTripFromOutside() throws {
    // The write side was already public through the memberwise initializers; this pins it
    // together with the new read side, which is the pair a host app needs. A host that can
    // write its own settings section and read it back is the entire point of the feature.
    let member = CastMember(
      character: "BOB",
      voices: [:],
      extraKeys: ["bio": try AnyCodable("a man")])
    let project = ProjectFrontMatter(
      title: "Round Trip",
      author: "Nobody",
      created: Date(timeIntervalSince1970: 0),
      cast: [member],
      appSections: ["myApp": try AnyCodable(["theme": "dark"])])

    #expect(project.appSections.keys.sorted() == ["myApp"])
    #expect(project.cast?.first?.extraKeys.keys.sorted() == ["bio"])

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let reDecoded = try decoder.decode(
      ProjectFrontMatter.self, from: try encoder.encode(project))

    #expect(reDecoded.appSections.keys.sorted() == ["myApp"])
    #expect(try #require(reDecoded.appSections["myApp"]).decode([String: String].self)
      == ["theme": "dark"])
    #expect(reDecoded.cast?.first?.extraKeys.keys.sorted() == ["bio"])
    #expect(try #require(reDecoded.cast?.first?.extraKeys["bio"]).decode(String.self) == "a man")
  }

  /// **DL-151, documented rather than fixed.** A top-level `episodes:` with no `season:`
  /// beside it is discarded on decode: the v3→v4 migration builds a `SeasonDefinition` only
  /// when `season` is present, and `episodes` is a known coding key, so it is not swept into
  /// ``ProjectFrontMatter/appSections`` either. It is read, dropped, and re-emitted as
  /// nothing.
  ///
  /// This is live data loss and it is **pre-existing**, not something this mission
  /// introduced. It is not fixed here because there is no fix that is only a bug fix:
  /// inventing `season: 1` changes what a document means, and sweeping the orphan into
  /// `appSections` changes the encoded output of every v3 file that has one. Both are
  /// behaviour changes that need a user's decision about the org's real files.
  ///
  /// Asserted so the loss is a *known* quantity with a test naming it, and so that whoever
  /// decides it finds this test going red and knows why.
  @Test("DL-151: a bare top-level `episodes:` is discarded on decode, and is not preserved")
  func orphanedEpisodesCountIsLost() throws {
    let orphan = """
      {"type": "project", "title": "T", "author": "A", "created": 0, "episodes": 12}
      """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let project = try decoder.decode(ProjectFrontMatter.self, from: Data(orphan.utf8))

    // Gone from every reachable surface.
    #expect(project.episodes == nil)
    #expect(project.seasons == nil)
    #expect(project.appSections.isEmpty, "not preserved as an unknown key either")

    // And gone from the bytes: a re-encode of this document does not contain the 12.
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    let written = try #require(String(bytes: try encoder.encode(project), encoding: .utf8))
    #expect(!written.contains("episodes"))

    // The same document *with* a season keeps both numbers, which is what isolates the loss
    // to the orphan case rather than to `episodes` generally.
    let paired = """
      {"type": "project", "title": "T", "author": "A", "created": 0, "season": 1, "episodes": 12}
      """
    let withSeason = try decoder.decode(ProjectFrontMatter.self, from: Data(paired.utf8))
    #expect(withSeason.season == 1)
    #expect(withSeason.episodes == 12)
  }
}
