// Vendored verbatim from SwiftProyecto (`Sources/SwiftProyecto/Models/`) by
// OPERATION FOUNTAIN SURGEON Sortie 32, 2026-07-26, under D-5. Copied, not moved:
// SwiftProyecto still owns its original and is repointed at this target later.
// Below this block the file is byte-identical to its source. Change it here only
// for a defect that also exists there, and record the decision-log number.

//
//  CastMember.swift
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

/// Gender specification for character roles.
///
/// Used to specify the expected or preferred gender for a character role,
/// or to indicate that gender is not a factor for the role.
public enum Gender: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
  /// Male
  case male = "M"

  /// Female
  case female = "F"

  /// Non-binary
  case nonBinary = "NB"

  /// Not specified - role doesn't depend on character's gender
  case notSpecified = "NS"

  /// Display name for UI presentation
  public var displayName: String {
    switch self {
    case .male: return "Male"
    case .female: return "Female"
    case .nonBinary: return "Non-Binary"
    case .notSpecified: return "Not Specified"
    }
  }
}

/// A character-to-voice mapping for audio generation.
///
/// Maps screenplay characters to human actors and TTS voice identifiers for
/// audio generation. Voices are specified as key/value pairs where the key is
/// the provider name and the value is an array of voice identifiers.
///
/// ## Voice Resolution
///
/// The appropriate voice is selected based on the enabled TTS provider.
/// If no voice is specified for the active provider, the default voice is used.
/// When multiple voice IDs exist for a provider, the first one is used unless
/// otherwise specified.
///
/// ## Example
///
/// ```swift
/// let narrator = CastMember(
///     character: "NARRATOR",
///     actor: "Tom Stovall",
///     gender: .male,
///     voices: [
///         "apple": ["com.apple.voice.compact.en-US.Aaron"],
///         "elevenlabs": ["21m00Tcm4TlvDq8ikWAM"],
///         "voxalta": ["narrative-1"]
///     ]
/// )
/// ```
///
/// ## Multiple Voices Per Provider
///
/// When a provider supports multiple voice IDs for a character (e.g., different
/// accents or emotional styles), all are preserved during merging to prevent
/// information loss.
///
/// ## YAML Representation
///
/// ```yaml
/// cast:
///   - character: NARRATOR
///     actor: Tom Stovall
///     gender: M
///     voices:
///       apple:
///         - com.apple.voice.compact.en-US.Aaron
///       elevenlabs:
///         - 21m00Tcm4TlvDq8ikWAM
/// ```
public struct CastMember: Codable, Sendable, Equatable, Hashable, Identifiable {

  /// Character name (as it appears in .fountain CHARACTER elements)
  /// Example: "NARRATOR", "LAO TZU", "COMMENTATOR"
  /// This is mutable to allow character renaming
  public var character: String

  /// Optional actor/voice artist name (for credits/reference)
  /// Example: "Tom Stovall", "Jason Manino"
  public var actor: String?

  /// Optional gender specification for the character role
  /// Defaults to .notSpecified if not provided
  public var gender: Gender?

  /// Optional description of the desired voice characteristics for this character.
  /// Used by CastMatcher to guide TTS voice selection.
  /// Example: "Deep, warm baritone with measured pacing and gravitas"
  public var voiceDescription: String?

  /// Dictionary of voice identifier arrays by provider.
  /// Keys are provider names (e.g., "apple", "elevenlabs"), values are arrays of voice identifiers.
  /// This structure supports multiple voice IDs per provider to enable lossless merging
  /// across master, season, and variant cast definitions.
  ///
  /// Examples:
  /// - "apple": ["com.apple.voice.compact.en-US.Aaron"]
  /// - "elevenlabs": ["21m00Tcm4TlvDq8ikWAM", "alternate-voice-id"]
  /// - "voxalta": ["narrative-1"]
  ///
  /// Invalid voice identifiers are permitted and will be handled at generation time.
  ///
  /// ## Zero Information Loss Guarantee
  ///
  /// All voice IDs are preserved during merge operations regardless of merge strategy.
  /// No voice information is lost when merging cast definitions from different levels
  /// (master, season, variant) or different providers.
  public var voices: [String: [String]]

  /// Optional spoken language for this character's lines, as a BCP 47 language
  /// tag (e.g. `"es"`, `"es-MX"`, `"en"`, `"fr-FR"`).
  ///
  /// Drives the TTS generation language so non-English dialogue is rendered with
  /// the correct language prefill rather than an anglicized default. When `nil`,
  /// the generator falls back to language inference (e.g. `"auto"`) — it must
  /// never silently force English.
  ///
  /// Example: `MAESTRA → "es-MX"`, `NARRATOR → "en"`.
  public var language: String?

  /// Storage for unknown, user-maintained per-member keys.
  ///
  /// Any key present under a cast member in PROJECT.md that is not one of the
  /// known fields above (e.g. a user-authored `bio:` note) is captured here on
  /// decode and re-emitted verbatim on encode. This mirrors
  /// ``ProjectFrontMatter/appSections`` and guarantees zero information loss on
  /// PROJECT.md round-trips — extra keys are preserved rather than silently
  /// destroyed on write-back.
  ///
  /// Internal access allows extensions to read and modify within the module.
  internal var extraKeys: [String: AnyCodable] = [:]

  /// Unique identifier based on character name
  public var id: String { character }

  /// Create a new cast member
  public init(
    character: String,
    actor: String? = nil,
    gender: Gender? = nil,
    voiceDescription: String? = nil,
    voices: [String: [String]] = [:],
    language: String? = nil,
    extraKeys: [String: AnyCodable] = [:]
  ) {
    self.character = character
    self.actor = actor
    self.gender = gender
    self.voiceDescription = voiceDescription
    self.voices = voices
    self.language = language
    self.extraKeys = extraKeys
  }

  // MARK: - Convenience

  /// Returns true if at least one voice is assigned
  public var hasVoices: Bool {
    !voices.isEmpty
  }

  /// Returns true if actor name is assigned
  public var hasActor: Bool {
    actor != nil && !(actor?.isEmpty ?? true)
  }

  /// Get first voice identifier for a specific provider (backward compatibility).
  ///
  /// Performs case-insensitive lookup of the provider name and returns the first
  /// voice ID in the array if multiple exist. This method provides backward
  /// compatibility with code expecting a single voice per provider.
  ///
  /// - Parameter provider: Provider name (e.g., "apple", "elevenlabs")
  /// - Returns: First voice identifier if found, nil otherwise
  ///
  /// ## Example
  ///
  /// ```swift
  /// let member = CastMember(
  ///     character: "NARRATOR",
  ///     voices: [
  ///         "apple": ["com.apple.voice.premium.en-US.Aaron"],
  ///         "elevenlabs": ["21m00Tcm4TlvDq8ikWAM"]
  ///     ]
  /// )
  /// if let appleVoice = member.voice(for: "apple") {
  ///     print(appleVoice) // "com.apple.voice.premium.en-US.Aaron"
  /// }
  /// ```
  public func voice(for provider: String) -> String? {
    voices[provider.lowercased()]?.first
  }

  /// Array of all provider names that have voices assigned.
  ///
  /// Returns provider names sorted alphabetically.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let member = CastMember(
  ///     character: "NARRATOR",
  ///     voices: [
  ///         "elevenlabs": ["21m00Tcm4TlvDq8ikWAM"],
  ///         "apple": ["com.apple.voice.premium.en-US.Aaron"]
  ///     ]
  /// )
  /// print(member.providers) // ["apple", "elevenlabs"]
  /// ```
  public var providers: [String] {
    Array(voices.keys).sorted()
  }

  // MARK: - Merge Strategy & Operations

  /// Merge strategies for combining cast members from different levels.
  ///
  /// Cast members can be defined at multiple levels (master, season, variant).
  /// This enum controls how they are combined while maintaining the
  /// **zero information loss guarantee**: all voice IDs are preserved
  /// regardless of strategy.
  public enum MergeStrategy: Sendable {
    /// Variant cast overrides master cast for specified fields, unspecified inherit from master.
    ///
    /// For fields like `actor`, `gender`, `voiceDescription`:
    /// - If the new/variant member has a value, use it
    /// - Otherwise, use the existing/master member's value
    ///
    /// For voices:
    /// - If the new/variant member has voices, use them
    /// - Otherwise, use the existing/master member's voices
    /// - All voice IDs are preserved (no information loss)
    case preserveExisting

    /// New cast completely overrides existing cast for populated fields.
    ///
    /// For fields like `actor`, `gender`, `voiceDescription`:
    /// - If the new member has a value, use it and discard existing
    /// - Otherwise, use the existing member's value
    ///
    /// For voices:
    /// - If the new member has voices, use them and discard existing
    /// - Otherwise, use the existing member's voices
    /// - All voice IDs are preserved (no information loss)
    case preferNew

    /// Merge voice arrays across providers, combining all voice IDs.
    ///
    /// For voices:
    /// - For each provider, combine voice arrays from both members
    /// - Remove duplicate voice IDs within each provider
    /// - All voice IDs are preserved (zero information loss guaranteed)
    ///
    /// For other fields (`actor`, `gender`, `voiceDescription`):
    /// - Use the existing member's value if present
    /// - Otherwise, use the new member's value
    case combine
  }

  /// Merge this cast member with another using the specified strategy.
  ///
  /// Returns a new merged CastMember. The merge strategy determines how
  /// voices and other attributes are combined.
  ///
  /// ## Zero Information Loss Guarantee
  ///
  /// All voice IDs are preserved regardless of merge strategy. No voice
  /// information is lost during merge operations. This is essential for
  /// multi-season, multi-language projects where cast is defined at
  /// master, season, and variant levels.
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
  /// let master = CastMember(
  ///   character: "NARRATOR",
  ///   actor: "Tom Stovall",
  ///   voices: ["apple": ["voice1"]]
  /// )
  /// let variant = CastMember(
  ///   character: "NARRATOR",
  ///   voices: ["elevenlabs": ["voice2"]]
  /// )
  ///
  /// let merged = master.merge(with: variant, strategy: .combine)
  /// // Result: voices = ["apple": ["voice1"], "elevenlabs": ["voice2"]]
  /// // Result: actor = "Tom Stovall" (from master, variant didn't override)
  /// ```
  ///
  /// - Parameters:
  ///   - other: The cast member to merge with
  ///   - strategy: The merge strategy to use
  /// - Returns: A new merged CastMember
  public func merge(with other: CastMember, strategy: MergeStrategy) -> CastMember {
    switch strategy {
    case .preserveExisting:
      return mergePreserveExisting(other)
    case .preferNew:
      return mergePreferNew(other)
    case .combine:
      return mergeCombine(other)
    }
  }

  /// Merge using preserveExisting strategy: variant overrides master.
  private func mergePreserveExisting(_ other: CastMember) -> CastMember {
    CastMember(
      character: character,  // Keep existing character
      actor: other.actor ?? actor,  // Other overrides if present
      gender: other.gender ?? gender,  // Other overrides if present
      voiceDescription: other.voiceDescription ?? voiceDescription,  // Other overrides if present
      voices: other.voices.isEmpty ? voices : other.voices,  // Other's voices override if present
      language: other.language ?? language,  // Other overrides if present
      extraKeys: extraKeys.merging(other.extraKeys) { _, new in new }  // Other overrides; all keys preserved
    )
  }

  /// Merge using preferNew strategy: new overrides existing.
  private func mergePreferNew(_ other: CastMember) -> CastMember {
    CastMember(
      character: character,  // Keep existing character
      actor: other.actor ?? actor,  // Other overrides if present
      gender: other.gender ?? gender,  // Other overrides if present
      voiceDescription: other.voiceDescription ?? voiceDescription,  // Other overrides if present
      voices: other.voices.isEmpty ? voices : other.voices,  // Other's voices override if present
      language: other.language ?? language,  // Other overrides if present
      extraKeys: extraKeys.merging(other.extraKeys) { _, new in new }  // Other overrides; all keys preserved
    )
  }

  /// Merge using combine strategy: merge voice arrays across providers.
  private func mergeCombine(_ other: CastMember) -> CastMember {
    // Start with all providers from both members
    var mergedVoices: [String: [String]] = [:]

    // Add all voices from self
    for (provider, voiceList) in voices {
      mergedVoices[provider] = voiceList
    }

    // Merge in voices from other, removing duplicates within each provider
    for (provider, otherVoiceList) in other.voices {
      let lowerProvider = provider.lowercased()
      if var existing = mergedVoices[lowerProvider] {
        // Combine arrays, preserving order and removing duplicates
        var seen = Set(existing)
        for voiceId in otherVoiceList {
          if !seen.contains(voiceId) {
            existing.append(voiceId)
            seen.insert(voiceId)
          }
        }
        mergedVoices[lowerProvider] = existing
      } else {
        // New provider: add all voices
        mergedVoices[lowerProvider] = otherVoiceList
      }
    }

    // For other fields, use self's value if present, else other's
    return CastMember(
      character: character,  // Keep existing character
      actor: actor ?? other.actor,  // Self's value preferred
      gender: gender ?? other.gender,  // Self's value preferred
      voiceDescription: voiceDescription ?? other.voiceDescription,  // Self's value preferred
      voices: mergedVoices,  // Combined voices
      language: language ?? other.language,  // Self's value preferred
      extraKeys: other.extraKeys.merging(extraKeys) { _, mine in mine }  // Self preferred; all keys preserved
    )
  }

  // MARK: - Equatable & Hashable

  /// Two cast members are equal if they have the same character name
  public static func == (lhs: CastMember, rhs: CastMember) -> Bool {
    lhs.character == rhs.character
  }

  /// Hash based on character name only
  public func hash(into hasher: inout Hasher) {
    hasher.combine(character)
  }

  // MARK: - Codable

  enum CodingKeys: String, CodingKey, CaseIterable {
    case character
    case actor
    case gender
    case voicePrompt
    case voiceDescription
    case voices
    case language
  }

  /// Dynamic key used to enumerate and re-emit unknown per-member keys.
  ///
  /// Mirrors the equivalent helper in ``ProjectFrontMatter`` so that unknown
  /// keys under a cast member survive a decode/encode round-trip.
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

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    character = try container.decode(String.self, forKey: .character)
    actor = try container.decodeIfPresent(String.self, forKey: .actor)
    gender = try container.decodeIfPresent(Gender.self, forKey: .gender)
    // Support both "voicePrompt" (preferred) and "voiceDescription" (legacy)
    voiceDescription =
      try container.decodeIfPresent(String.self, forKey: .voicePrompt)
      ?? container.decodeIfPresent(String.self, forKey: .voiceDescription)

    // Decode voices with backward compatibility:
    // - Old format: { provider: "voice-id" } → { provider: ["voice-id"] }
    // - New format: { provider: ["voice-id-1", "voice-id-2"] } → use as-is
    var decodedVoices: [String: [String]] = [:]
    if let voicesContainer = try container.decodeIfPresent(
      [String: AnyCodable].self, forKey: .voices)
    {
      for (provider, value) in voicesContainer {
        let lowercaseProvider = provider.lowercased()

        // Try to decode as array of strings first (new format)
        if let arrayValue = try? value.decode([String].self) {
          decodedVoices[lowercaseProvider] = arrayValue
        } else if let stringValue = try? value.decode(String.self) {
          // Old format: single string → wrap in array
          decodedVoices[lowercaseProvider] = [stringValue]
        }
      }
    }
    voices = decodedVoices

    language = try container.decodeIfPresent(String.self, forKey: .language)

    // Capture any remaining, unknown keys so user-maintained content (e.g. a
    // `bio:` note) is preserved rather than destroyed on the next write-back.
    let knownKeys = Set(CodingKeys.allCases.map { $0.stringValue })
    let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
    var capturedExtras: [String: AnyCodable] = [:]
    for key in dynamicContainer.allKeys where !knownKeys.contains(key.stringValue) {
      capturedExtras[key.stringValue] = try dynamicContainer.decode(AnyCodable.self, forKey: key)
    }
    extraKeys = capturedExtras
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(character, forKey: .character)
    try container.encodeIfPresent(actor, forKey: .actor)
    try container.encodeIfPresent(gender, forKey: .gender)
    try container.encodeIfPresent(voiceDescription, forKey: .voicePrompt)
    // Always encode voices as [String: [String]] (new format)
    try container.encode(voices, forKey: .voices)
    try container.encodeIfPresent(language, forKey: .language)

    // Re-emit any preserved unknown keys so round-trips are lossless.
    if !extraKeys.isEmpty {
      var dynamicContainer = encoder.container(keyedBy: DynamicCodingKey.self)
      for (key, value) in extraKeys {
        try dynamicContainer.encode(value, forKey: DynamicCodingKey(stringValue: key))
      }
    }
  }
}
