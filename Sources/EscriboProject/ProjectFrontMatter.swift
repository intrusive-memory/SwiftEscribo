// Vendored verbatim from SwiftProyecto (`Sources/SwiftProyecto/Models/`) by
// OPERATION FOUNTAIN SURGEON Sortie 32, 2026-07-26, under D-5. Copied, not moved:
// SwiftProyecto still owns its original and is repointed at this target later.
// Below this block the file is byte-identical to its source. Change it here only
// for a defect that also exists there, and record the decision-log number.

//
//  ProjectFrontMatter.swift
//  SwiftProyecto
//
//  Copyright (c) 2025 Intrusive Memory
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
//  IN THE SOFTWARE.
//

import Foundation

/// Project type classification for PROJECT.md files.
///
/// Distinguishes between individual season projects and multi-season
/// overview/master documents.
public enum ProjectType: String, Codable, Sendable {
  /// Single season project
  case project

  /// Multi-season overview or master document
  case overview
}

/// Metadata extracted from PROJECT.md front matter.
///
/// PROJECT.md files use YAML front matter to store project metadata. This struct
/// provides a strongly-typed representation of that metadata.
///
/// ## Example PROJECT.md
///
/// ```markdown
/// ---
/// type: project
/// title: My Series
/// author: Jane Showrunner
/// created: 2025-11-17T10:30:00Z
/// description: A multi-episode series
/// season: 1
/// episodes: 12
/// genre: Science Fiction
/// tags: [sci-fi, drama]
/// ---
///
/// # Project Notes
///
/// Additional production notes go here...
/// ```
///
public struct ProjectFrontMatter: Codable, Sendable, Equatable {
  /// Type identifier - must be "project"
  public let type: String

  /// Project title (required)
  public let title: String

  /// Project author (required)
  public let author: String

  /// Creation date (required)
  public let created: Date

  /// Last update date (optional, defaults to today on generation)
  public let updated: Date?

  /// Optional project description
  public let description: String?

  /// Backward-compat accessor for v3-style season number (computed from seasons[0]).
  public var season: Int? {
    seasons?.first?.number
  }

  /// Backward-compat accessor for v3-style episode count (computed from seasons[0]).
  public var episodes: Int? {
    seasons?.first?.episodes
  }

  /// Optional genre
  public let genre: String?

  /// Optional tags
  public let tags: [String]?

  // MARK: - Generation Configuration Fields

  /// Relative path to episode/screenplay files (default: "episodes")
  public let episodesDir: String?

  /// Relative path for audio output (default: "audio")
  public let audioDir: String?

  /// Glob pattern(s) or explicit file list for file discovery
  public let filePattern: FilePattern?

  /// Audio export format (default: "m4a")
  public let exportFormat: String?

  /// Optional path to intro file (project-resolved: relative to the project root)
  public let introFile: String?

  /// Optional path to outro file (project-resolved: relative to the project root)
  public let outroFile: String?

  // MARK: - Cast List

  /// Character-to-voice mappings for audio generation
  /// Maps screenplay characters to actors and TTS voice URIs
  public var cast: [CastMember]?

  // MARK: - Hook Fields

  /// Shell command to run BEFORE generation
  public let preGenerateHook: String?

  /// Shell command to run AFTER generation
  public let postGenerateHook: String?

  // MARK: - TTS Configuration

  /// Optional text-to-speech generation configuration
  public let tts: TTSConfig?

  // MARK: - v4.0.0 Multi-Season / Multi-Language Fields

  /// Schema version identifier (4 for v4.0.0, nil for v3.x and earlier)
  public let schemaVersion: Int?

  /// Project type: "project" for single season, "overview" for multi-season master
  public let projectType: String?

  /// Array of season definitions (for overview documents)
  public let seasons: [SeasonDefinition]?

  /// Array of language definitions (for overview documents)
  public let languages: [LanguageDefinition]?

  /// Array of variant references (for overview documents)
  public let variants: [VariantReference]?

  /// Template string for episode path resolution
  /// Example: "episodes/<language>/<season>/<episode>.<ext>"
  public let episodePath: String?

  // MARK: - App-Specific Settings Storage

  /// Storage for app-specific settings sections.
  /// Keys are app section identifiers, values are type-erased settings.
  /// Internal access allows extensions to read and modify within the module.
  internal var appSections: [String: AnyCodable] = [:]

  /// Create a new ProjectFrontMatter instance.
  ///
  /// - Parameters:
  ///   - type: Type identifier (should always be "project")
  ///   - title: Project title
  ///   - author: Project author
  ///   - created: Creation date
  ///   - description: Optional project description
  ///   - season: Deprecated; use seasons array instead
  ///   - episodes: Deprecated; use seasons array instead
  ///   - genre: Optional genre
  ///   - tags: Optional tags
  ///   - episodesDir: Relative path to episode files (default: "episodes")
  ///   - audioDir: Relative path for audio output (default: "audio")
  ///   - filePattern: Glob pattern(s) for file discovery
  ///   - exportFormat: Audio export format (default: "m4a")
  ///   - introFile: Path to intro file (project-resolved: relative to the project root)
  ///   - outroFile: Path to outro file (project-resolved: relative to the project root)
  ///   - cast: Character-to-voice mappings for audio generation
  ///   - preGenerateHook: Shell command to run before generation
  ///   - postGenerateHook: Shell command to run after generation
  ///   - tts: Optional TTS generation configuration
  ///   - schemaVersion: Schema version identifier (4 for v4.0.0, nil for v3.x)
  ///   - projectType: Project type ("project" or "overview")
  ///   - seasons: Array of season definitions
  ///   - languages: Array of language definitions
  ///   - variants: Array of variant references
  ///   - episodePath: Template string for episode paths
  ///   - appSections: App-specific settings sections (default: empty)
  public init(
    type: String = "project",
    title: String,
    author: String,
    created: Date = Date(),
    updated: Date? = nil,
    description: String? = nil,
    season: Int? = nil,
    episodes: Int? = nil,
    genre: String? = nil,
    tags: [String]? = nil,
    episodesDir: String? = nil,
    audioDir: String? = nil,
    filePattern: FilePattern? = nil,
    exportFormat: String? = nil,
    introFile: String? = nil,
    outroFile: String? = nil,
    cast: [CastMember]? = nil,
    preGenerateHook: String? = nil,
    postGenerateHook: String? = nil,
    tts: TTSConfig? = nil,
    schemaVersion: Int? = nil,
    projectType: String? = nil,
    seasons: [SeasonDefinition]? = nil,
    languages: [LanguageDefinition]? = nil,
    variants: [VariantReference]? = nil,
    episodePath: String? = nil,
    appSections: [String: AnyCodable] = [:]
  ) {
    self.type = type
    self.title = title
    self.author = author
    self.created = created
    self.updated = updated
    self.description = description
    self.genre = genre
    self.tags = tags
    self.episodesDir = episodesDir
    self.audioDir = audioDir
    self.filePattern = filePattern
    self.exportFormat = exportFormat
    self.introFile = introFile
    self.outroFile = outroFile
    self.cast = cast
    self.preGenerateHook = preGenerateHook
    self.postGenerateHook = postGenerateHook
    self.tts = tts
    self.schemaVersion = schemaVersion
    self.projectType = projectType

    var finalSeasons = seasons
    if finalSeasons == nil && (season != nil || episodes != nil) {
      var migratedSeasons: [SeasonDefinition] = []
      if let seasonNum = season {
        let episodeCount = episodes ?? 0
        let seasonDef = SeasonDefinition(number: seasonNum, episodes: episodeCount)
        migratedSeasons.append(seasonDef)
      }
      finalSeasons = migratedSeasons.isEmpty ? nil : migratedSeasons
    }
    self.seasons = finalSeasons

    self.languages = languages
    self.variants = variants
    self.episodePath = episodePath
    self.appSections = appSections
  }

  // MARK: - Custom Codable Implementation

  private enum KnownCodingKeys: String, CodingKey, CaseIterable {
    case type, title, author, created, updated, description, season
    case episodes, genre, tags, episodesDir, audioDir
    case filePattern, exportFormat, introFile, outroFile, cast
    case preGenerateHook, postGenerateHook, tts
    case schemaVersion, projectType, seasons, languages, variants, episodePath
  }

  private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
      self.stringValue = stringValue
      self.intValue = nil
    }

    init?(intValue: Int) {
      self.stringValue = "\(intValue)"
      self.intValue = intValue
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: KnownCodingKeys.self)
    try container.encode(type, forKey: .type)
    try container.encode(title, forKey: .title)
    try container.encode(author, forKey: .author)
    try container.encode(created, forKey: .created)
    try container.encodeIfPresent(updated, forKey: .updated)
    try container.encodeIfPresent(description, forKey: .description)
    try container.encodeIfPresent(genre, forKey: .genre)
    try container.encodeIfPresent(tags, forKey: .tags)
    try container.encodeIfPresent(episodesDir, forKey: .episodesDir)
    try container.encodeIfPresent(audioDir, forKey: .audioDir)
    try container.encodeIfPresent(filePattern, forKey: .filePattern)
    try container.encodeIfPresent(exportFormat, forKey: .exportFormat)
    try container.encodeIfPresent(introFile, forKey: .introFile)
    try container.encodeIfPresent(outroFile, forKey: .outroFile)
    try container.encodeIfPresent(cast, forKey: .cast)
    try container.encodeIfPresent(preGenerateHook, forKey: .preGenerateHook)
    try container.encodeIfPresent(postGenerateHook, forKey: .postGenerateHook)
    try container.encodeIfPresent(tts, forKey: .tts)

    try container.encode(4, forKey: .schemaVersion)
    try container.encodeIfPresent(projectType, forKey: .projectType)
    try container.encodeIfPresent(seasons, forKey: .seasons)

    try container.encodeIfPresent(languages, forKey: .languages)
    try container.encodeIfPresent(variants, forKey: .variants)
    try container.encodeIfPresent(episodePath, forKey: .episodePath)

    if !appSections.isEmpty {
      var rootContainer = encoder.container(keyedBy: DynamicCodingKey.self)
      for (key, value) in appSections {
        try rootContainer.encode(value, forKey: DynamicCodingKey(stringValue: key))
      }
    }
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: KnownCodingKeys.self)

    type = try container.decode(String.self, forKey: .type)
    title = try container.decode(String.self, forKey: .title)
    author = try container.decode(String.self, forKey: .author)
    created = try container.decode(Date.self, forKey: .created)
    updated = try container.decodeIfPresent(Date.self, forKey: .updated)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    genre = try container.decodeIfPresent(String.self, forKey: .genre)
    tags = try container.decodeIfPresent([String].self, forKey: .tags)
    episodesDir = try container.decodeIfPresent(String.self, forKey: .episodesDir)
    audioDir = try container.decodeIfPresent(String.self, forKey: .audioDir)
    filePattern = try container.decodeIfPresent(FilePattern.self, forKey: .filePattern)
    exportFormat = try container.decodeIfPresent(String.self, forKey: .exportFormat)
    introFile = try container.decodeIfPresent(String.self, forKey: .introFile)
    outroFile = try container.decodeIfPresent(String.self, forKey: .outroFile)
    cast = try container.decodeIfPresent([CastMember].self, forKey: .cast)
    preGenerateHook = try container.decodeIfPresent(String.self, forKey: .preGenerateHook)
    postGenerateHook = try container.decodeIfPresent(String.self, forKey: .postGenerateHook)
    tts = try container.decodeIfPresent(TTSConfig.self, forKey: .tts)

    let decodedSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
    schemaVersion = decodedSchemaVersion

    projectType = try container.decodeIfPresent(String.self, forKey: .projectType)
    languages = try container.decodeIfPresent([LanguageDefinition].self, forKey: .languages)
    variants = try container.decodeIfPresent([VariantReference].self, forKey: .variants)
    episodePath = try container.decodeIfPresent(String.self, forKey: .episodePath)

    let v3Season = try container.decodeIfPresent(Int.self, forKey: .season)
    let v3Episodes = try container.decodeIfPresent(Int.self, forKey: .episodes)
    let decodedSeasons = try container.decodeIfPresent([SeasonDefinition].self, forKey: .seasons)

    if decodedSeasons == nil {
      var migratedSeasons: [SeasonDefinition] = []
      if let seasonNum = v3Season {
        let episodeCount = v3Episodes ?? 0
        let seasonDef = SeasonDefinition(number: seasonNum, episodes: episodeCount)
        migratedSeasons.append(seasonDef)
      }
      seasons = migratedSeasons.isEmpty ? nil : migratedSeasons
    } else {
      seasons = decodedSeasons
    }

    let rootContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
    var sections: [String: AnyCodable] = [:]
    for key in rootContainer.allKeys {
      if !KnownCodingKeys.allCases.contains(where: { $0.stringValue == key.stringValue }) {
        sections[key.stringValue] = try rootContainer.decode(AnyCodable.self, forKey: key)
      }
    }
    self.appSections = sections
  }
}

// MARK: - Validation

extension ProjectFrontMatter {
  /// Validate that this front matter represents a valid project.
  ///
  /// Checks that type is "project" and required fields are present.
  /// Season information is optional.
  ///
  /// - Returns: `true` if type is "project" and title/author are non-empty
  public var isValid: Bool {
    return type.lowercased() == "project"
      && !title.isEmpty
      && !author.isEmpty
  }
}

// MARK: - Version Detection & Backward Compatibility

extension ProjectFrontMatter {

  /// Detect the schema version of this ProjectFrontMatter.
  /// - Returns: 4 if schemaVersion is set to 4, otherwise 3 (default)
  public func detectedSchemaVersion() -> Int {
    schemaVersion ?? 3
  }

  /// Returns true if this was originally a v3.x format file.
  /// Note: Internally normalized to v4.0.0, but this tracks the origin.
  public var isLegacyV3Format: Bool {
    schemaVersion == nil
  }
}

// MARK: - Convenience Accessors with Defaults

extension ProjectFrontMatter {
  /// Resolved episodes directory, defaulting to "episodes" if not specified.
  public var resolvedEpisodesDir: String {
    episodesDir ?? "episodes"
  }

  /// Resolved audio directory, defaulting to "audio" if not specified.
  public var resolvedAudioDir: String {
    audioDir ?? "audio"
  }

  /// Resolved file patterns, defaulting to ["*.fountain"] if not specified.
  public var resolvedFilePatterns: [String] {
    filePattern?.patterns ?? ["*.fountain"]
  }

  /// Resolved export format, defaulting to "m4a" if not specified.
  public var resolvedExportFormat: String {
    exportFormat ?? "m4a"
  }

  /// Returns true if a TTS configuration is present.
  public var hasTTSConfig: Bool {
    tts != nil
  }

  /// Returns true if any generation configuration fields are set.
  public var hasGenerationConfig: Bool {
    episodesDir != nil || audioDir != nil || filePattern != nil || exportFormat != nil
      || preGenerateHook != nil || postGenerateHook != nil
  }
}

// MARK: - Path Normalization

extension ProjectFrontMatter {

  /// Returns a copy with path-valued fields (`episodesDir`, `audioDir`) made
  /// relative to `baseDirectory` — the directory that contains (or will contain)
  /// PROJECT.md.
  ///
  /// PROJECT.md is intended to be portable: all paths it references must be
  /// interpreted relative to the file itself. This helper enforces that at the
  /// write boundary. It:
  /// - Leaves already-relative paths (no leading `/` or `~`) unchanged.
  /// - Expands leading `~` to the user's home directory, then makes it relative.
  /// - Strips the `baseDirectory` prefix from absolute paths that live inside it.
  /// - Falls back to a `../`-style traversal for absolute paths outside the base.
  ///
  /// `filePattern` (glob), `preGenerateHook`, and `postGenerateHook` (shell
  /// commands) are intentionally not touched — they are not file paths.
  ///
  /// - Parameter baseDirectory: The directory containing PROJECT.md.
  /// - Returns: A new `ProjectFrontMatter` with path fields normalized.
  public func normalizingPaths(relativeTo baseDirectory: URL) -> ProjectFrontMatter {
    ProjectFrontMatter(
      type: type,
      title: title,
      author: author,
      created: created,
      updated: updated,
      description: description,
      genre: genre,
      tags: tags,
      episodesDir: episodesDir.map { Self.makeRelative($0, to: baseDirectory) },
      audioDir: audioDir.map { Self.makeRelative($0, to: baseDirectory) },
      filePattern: filePattern,
      exportFormat: exportFormat,
      introFile: introFile.map { Self.makeRelative($0, to: baseDirectory) },
      outroFile: outroFile.map { Self.makeRelative($0, to: baseDirectory) },
      cast: cast,
      preGenerateHook: preGenerateHook,
      postGenerateHook: postGenerateHook,
      tts: tts,
      schemaVersion: schemaVersion,
      projectType: projectType,
      seasons: seasons,
      languages: languages,
      variants: variants,
      episodePath: episodePath,
      appSections: appSections
    )
  }

  /// Convert a single path string to a path relative to `baseDirectory`.
  /// Relative inputs pass through unchanged.
  static func makeRelative(_ path: String, to baseDirectory: URL) -> String {
    if path.isEmpty { return path }

    // Expand leading ~ to absolute before deciding how to relativize.
    let expanded: String
    if path.hasPrefix("~") {
      expanded = NSString(string: path).expandingTildeInPath
    } else {
      expanded = path
    }

    // Non-absolute paths are already relative to PROJECT.md — leave alone.
    guard expanded.hasPrefix("/") else { return path }

    let baseStandardized = baseDirectory.standardizedFileURL.path
    let targetStandardized = URL(fileURLWithPath: expanded).standardizedFileURL.path

    if targetStandardized == baseStandardized {
      return "."
    }
    let prefix = baseStandardized.hasSuffix("/") ? baseStandardized : baseStandardized + "/"
    if targetStandardized.hasPrefix(prefix) {
      return String(targetStandardized.dropFirst(prefix.count))
    }

    // Path lies outside baseDirectory — build a ../-style traversal.
    let baseComponents = baseStandardized.split(separator: "/").map(String.init)
    let targetComponents = targetStandardized.split(separator: "/").map(String.init)
    var commonCount = 0
    while commonCount < baseComponents.count,
      commonCount < targetComponents.count,
      baseComponents[commonCount] == targetComponents[commonCount]
    {
      commonCount += 1
    }
    let ups = Array(repeating: "..", count: baseComponents.count - commonCount)
    let downs = Array(targetComponents[commonCount...])
    let joined = (ups + downs).joined(separator: "/")
    return joined.isEmpty ? "." : joined
  }
}

// MARK: - Cast Mutation Helpers

extension ProjectFrontMatter {

  /// Create a copy of this front matter with the cast list replaced.
  ///
  /// Returns a new `ProjectFrontMatter` instance with all fields preserved
  /// except the cast, which is replaced with the provided value.
  ///
  /// **Warning**: This replaces the entire cast list. If you need to update
  /// voices for a single provider while preserving other providers' voices,
  /// use ``mergingCast(_:forProvider:)`` instead.
  ///
  /// ## Usage
  ///
  /// ```swift
  /// let newCast = [CastMember(character: "NARRATOR", voices: ["apple": "voice-id"])]
  /// let updated = frontMatter.withCast(newCast)
  /// ```
  ///
  /// - Parameter cast: The new cast list, or `nil` to remove the cast section entirely.
  /// - Returns: A new `ProjectFrontMatter` with the updated cast.
  public func withCast(_ cast: [CastMember]?) -> ProjectFrontMatter {
    ProjectFrontMatter(
      type: type,
      title: title,
      author: author,
      created: created,
      description: description,
      genre: genre,
      tags: tags,
      episodesDir: episodesDir,
      audioDir: audioDir,
      filePattern: filePattern,
      exportFormat: exportFormat,
      introFile: introFile,
      outroFile: outroFile,
      cast: cast,
      preGenerateHook: preGenerateHook,
      postGenerateHook: postGenerateHook,
      tts: tts,
      schemaVersion: schemaVersion,
      projectType: projectType,
      seasons: seasons,
      languages: languages,
      variants: variants,
      episodePath: episodePath,
      appSections: appSections
    )
  }

  /// Merge cast member voices for a specific provider, preserving all other provider voices.
  ///
  /// This is the **safe** way to update cast voices. For each character in `newCast`:
  /// - If the character already exists in the current cast, the voice(s) for `providerID`
  ///   are updated (or added), while all other provider voices are preserved.
  /// - If the character does not exist in the current cast, it is added as-is.
  ///
  /// Characters in the existing cast that are not present in `newCast` are preserved unchanged.
  ///
  /// ## Zero Information Loss
  ///
  /// All voice IDs are preserved. When updating voices for a specific provider,
  /// voices for all other providers remain unchanged.
  ///
  /// ## Usage
  ///
  /// ```swift
  /// // Existing cast has ElevenLabs voice for NARRATOR
  /// // newCast has Apple voice for NARRATOR
  /// let updated = frontMatter.mergingCast(newCast, forProvider: "apple")
  /// // Result: NARRATOR has both ElevenLabs and Apple voices
  /// ```
  ///
  /// ## Example
  ///
  /// ```yaml
  /// # Before: Has ElevenLabs voice
  /// cast:
  ///   - character: NARRATOR
  ///     voices:
  ///       elevenlabs:
  ///         - 21m00Tcm4TlvDq8ikWAM
  ///
  /// # After mergingCast with Apple provider:
  /// cast:
  ///   - character: NARRATOR
  ///     voices:
  ///       apple:
  ///         - com.apple.voice.premium.en-US.Aaron
  ///       elevenlabs:
  ///         - 21m00Tcm4TlvDq8ikWAM
  /// ```
  ///
  /// - Parameters:
  ///   - newCast: The cast members with voices to merge in. Only the voice(s) for `providerID`
  ///     are extracted from each member.
  ///   - providerID: The provider whose voices are being updated (e.g., "apple", "elevenlabs").
  /// - Returns: A new `ProjectFrontMatter` with the merged cast.
  public func mergingCast(_ newCast: [CastMember], forProvider providerID: String)
    -> ProjectFrontMatter
  {
    let existingCast = cast ?? []
    let lowerProviderID = providerID.lowercased()

    // Build a lookup of existing cast by character name
    var mergedByCharacter: [String: CastMember] = [:]
    for member in existingCast {
      mergedByCharacter[member.character] = member
    }

    // Merge in new cast voices for the specified provider
    for newMember in newCast {
      if var existing = mergedByCharacter[newMember.character] {
        // Character exists: update only the specified provider's voices
        if let newVoices = newMember.voices[lowerProviderID], !newVoices.isEmpty {
          existing.voices[lowerProviderID] = newVoices
        }
        mergedByCharacter[newMember.character] = existing
      } else {
        // New character: add it as-is
        mergedByCharacter[newMember.character] = newMember
      }
    }

    // Preserve original ordering: existing characters first, then new ones
    var result: [CastMember] = []
    var seen: Set<String> = []

    // Add existing characters in their original order (with merged voices)
    for member in existingCast {
      if let merged = mergedByCharacter[member.character] {
        result.append(merged)
        seen.insert(member.character)
      }
    }

    // Add new characters that were not in the existing cast
    for newMember in newCast where !seen.contains(newMember.character) {
      if let merged = mergedByCharacter[newMember.character] {
        result.append(merged)
        seen.insert(newMember.character)
      }
    }

    return withCast(result)
  }

  /// Merge two cast lists using the specified strategy.
  ///
  /// Returns a unified cast dictionary keyed by character name. This is the
  /// primary method for merging cast definitions from different levels
  /// (master, season, variant) while maintaining the zero information loss guarantee.
  ///
  /// ## Zero Information Loss Guarantee
  ///
  /// All voice IDs are preserved regardless of merge strategy. When merging
  /// cast from master, season, and variant levels, no voice information is
  /// lost. This is essential for multi-season, multi-language projects.
  ///
  /// ## Merge Strategies
  ///
  /// - **preserveExisting**: Variant overrides master; unspecified fields inherit
  /// - **preferNew**: New overrides existing; unspecified fields inherit
  /// - **combine**: Merge voice arrays across providers, removing duplicates
  ///
  /// ## Example
  ///
  /// ```swift
  /// // Master cast has NARRATOR and MAESTRA
  /// let masterCast = [
  ///   CastMember(character: "NARRATOR", actor: "Tom", voices: ["apple": ["voice1"]]),
  ///   CastMember(character: "MAESTRA", voices: ["apple": ["voice2"]])
  /// ]
  /// // Variant cast overrides NARRATOR and adds GUIDE
  /// let variantCast = [
  ///   CastMember(character: "NARRATOR", voices: ["elevenlabs": ["voice3"]])
  /// ]
  ///
  /// let merged = ProjectFrontMatter.mergeCast(
  ///   masterCast,
  ///   variantCast,
  ///   strategy: .combine
  /// )
  /// // Result keys: ["NARRATOR", "MAESTRA"]
  /// // NARRATOR.voices = ["apple": ["voice1"], "elevenlabs": ["voice3"]]
  /// // MAESTRA.voices = ["apple": ["voice2"]]
  /// ```
  ///
  /// ## Processing Order
  ///
  /// 1. Start with master cast, keyed by character name
  /// 2. For each character in variant cast:
  ///    - If character exists in master: merge using strategy
  ///    - If character not in master: add variant's cast member
  /// 3. Return combined dictionary with all characters
  ///
  /// - Parameters:
  ///   - masterCast: Base cast list (typically from master/overview level)
  ///   - variantCast: Variant cast list to merge in (season, language, or variant level)
  ///   - strategy: The merge strategy to use
  /// - Returns: Dictionary mapping character name to merged CastMember
  public static func mergeCast(
    _ masterCast: [CastMember]?,
    _ variantCast: [CastMember]?,
    strategy: CastMember.MergeStrategy
  ) -> [String: CastMember] {
    // Start with master cast keyed by character
    var result: [String: CastMember] = [:]

    if let master = masterCast {
      for member in master {
        result[member.character] = member
      }
    }

    // Merge in variant cast
    if let variant = variantCast {
      for variantMember in variant {
        if let masterMember = result[variantMember.character] {
          // Character exists in master: merge using strategy
          result[variantMember.character] = masterMember.merge(
            with: variantMember,
            strategy: strategy
          )
        } else {
          // Character not in master: add variant's member as-is
          result[variantMember.character] = variantMember
        }
      }
    }

    return result
  }
}

// MARK: - Intro/Outro Asset Information

/// Information about intro and outro assets for a project or variant.
///
/// Tracks both the resolved file paths and whether files exist on disk.
/// Missing files generate warnings but don't block generation (non-blocking).
///
/// ## Usage
///
/// ```swift
/// let assets = frontMatter.resolvedIntroOutroAssets(
///   forSeason: 1,
///   withMaster: masterFrontMatter,
///   episodesDir: "episodes",
///   baseDirectory: projectURL
/// )
///
/// if let intro = assets.introPath {
///   print("Intro file: \(intro)")
/// }
/// if assets.isIntroMissing {
///   print("Warning: Intro file specified but not found")
/// }
/// ```
public struct IntroOutroAssets: Sendable, Equatable {
  /// Resolved path to intro file, relative to episodesDir
  /// nil if not specified at any level
  public let introPath: String?

  /// Resolved path to outro file, relative to episodesDir
  /// nil if not specified at any level
  public let outroPath: String?

  /// True if intro file is specified in PROJECT but doesn't exist on disk
  /// Used for warnings (non-blocking)
  public let isIntroMissing: Bool

  /// True if outro file is specified in PROJECT but doesn't exist on disk
  /// Used for warnings (non-blocking)
  public let isOutroMissing: Bool

  /// Create a new IntroOutroAssets instance
  public init(
    introPath: String? = nil,
    outroPath: String? = nil,
    isIntroMissing: Bool = false,
    isOutroMissing: Bool = false
  ) {
    self.introPath = introPath
    self.outroPath = outroPath
    self.isIntroMissing = isIntroMissing
    self.isOutroMissing = isOutroMissing
  }
}

// MARK: - Intro/Outro Resolution

extension ProjectFrontMatter {

  /// Resolve the intro file using the property hierarchy.
  ///
  /// Resolves the path using: variant > season > master > none
  ///
  /// - Parameters:
  ///   - forSeason: Season number (for looking up season-level override)
  ///   - withMaster: Master ProjectFrontMatter (for inheritance)
  ///
  /// - Returns: Resolved intro file path (relative to episodesDir), or nil if unspecified
  public func resolvedIntroFile(
    forSeason season: Int,
    withMaster master: ProjectFrontMatter
  ) -> String? {
    // Resolve hierarchy: self > season > master > nil
    if let introFile = introFile {
      return introFile
    }

    if let seasonDef = master.seasons?.first(where: { $0.number == season }) {
      if let introFile = seasonDef.introFile {
        return introFile
      }
    }

    return master.introFile
  }

  /// Resolve the outro file using the property hierarchy.
  ///
  /// Resolves the path using: variant > season > master > none
  ///
  /// - Parameters:
  ///   - forSeason: Season number (for looking up season-level override)
  ///   - withMaster: Master ProjectFrontMatter (for inheritance)
  ///
  /// - Returns: Resolved outro file path (relative to episodesDir), or nil if unspecified
  public func resolvedOutroFile(
    forSeason season: Int,
    withMaster master: ProjectFrontMatter
  ) -> String? {
    // Resolve hierarchy: self > season > master > nil
    if let outroFile = outroFile {
      return outroFile
    }

    if let seasonDef = master.seasons?.first(where: { $0.number == season }) {
      if let outroFile = seasonDef.outroFile {
        return outroFile
      }
    }

    return master.outroFile
  }

  /// Combined resolution of both intro and outro files.
  ///
  /// - Parameters:
  ///   - forSeason: Season number
  ///   - withMaster: Master ProjectFrontMatter
  ///   - episodesDir: Directory containing episodes (for relative path interpretation)
  ///   - baseDirectory: Base directory for file existence checks
  ///
  /// - Returns: IntroOutroAssets with resolved paths and missing file flags
  public func resolvedIntroOutroAssets(
    forSeason season: Int,
    withMaster master: ProjectFrontMatter,
    episodesDir: String,
    baseDirectory: URL
  ) -> IntroOutroAssets {
    // Resolve intro and outro paths using hierarchy
    let introPath = resolvedIntroFile(forSeason: season, withMaster: master)
    let outroPath = resolvedOutroFile(forSeason: season, withMaster: master)

    // Check if files exist on disk
    let isIntroMissing: Bool
    if let intro = introPath {
      let introURL = baseDirectory.appendingPathComponent(episodesDir).appendingPathComponent(intro)
      isIntroMissing = !FileManager.default.fileExists(atPath: introURL.path)
    } else {
      isIntroMissing = false
    }

    let isOutroMissing: Bool
    if let outro = outroPath {
      let outroURL = baseDirectory.appendingPathComponent(episodesDir).appendingPathComponent(outro)
      isOutroMissing = !FileManager.default.fileExists(atPath: outroURL.path)
    } else {
      isOutroMissing = false
    }

    return IntroOutroAssets(
      introPath: introPath,
      outroPath: outroPath,
      isIntroMissing: isIntroMissing,
      isOutroMissing: isOutroMissing
    )
  }
}
