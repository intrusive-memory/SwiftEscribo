// Vendored verbatim from SwiftProyecto (`Sources/SwiftProyecto/Models/`) by
// OPERATION FOUNTAIN SURGEON Sortie 32, 2026-07-26, under D-5. Copied, not moved:
// SwiftProyecto still owns its original and is repointed at this target later.
// Below this block the file is byte-identical to its source. Change it here only
// for a defect that also exists there, and record the decision-log number.

//
//  SeasonDefinition.swift
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

/// Definition of a season within a multi-season project.
///
/// Used in PROJECT.md to define season-specific metadata including episode count,
/// release date, file organization, cast, and TTS configuration.
///
/// ## Example
///
/// ```yaml
/// seasons:
///   - number: 1
///     title: "Season One: The Beginning"
///     description: "First season of the series"
///     episodes: 12
///     releaseDate: 2025-01-15T00:00:00Z
///     episodesDir: "episodes/season-01"
///     cast:
///       - character: NARRATOR
///         voices:
///           apple: com.apple.voice.premium.en-US.Aaron
/// ```
public struct SeasonDefinition: Codable, Sendable, Equatable {
  /// Season number (required, must be unique within project)
  public let number: Int

  /// Optional season title (e.g., "Season One: The Beginning")
  public let title: String?

  /// Optional season description
  public let description: String?

  /// Episode count for this season (required)
  public let episodes: Int

  /// Optional release date for the season
  public let releaseDate: Date?

  /// Optional relative path to season's episode files
  /// (e.g., "episodes/season-01", defaults to project episodesDir)
  public let episodesDir: String?

  /// Optional file pattern(s) for this season's episodes
  public let filePattern: FilePattern?

  /// Optional path to season intro file (project-resolved: relative to the project root)
  public let introFile: String?

  /// Optional path to season outro file (project-resolved: relative to the project root)
  public let outroFile: String?

  /// Optional cast list for this season (overrides project-level cast)
  public let cast: [CastMember]?

  /// Optional TTS configuration specific to this season
  public let tts: TTSConfig?

  /// Create a new season definition.
  public init(
    number: Int,
    title: String? = nil,
    description: String? = nil,
    episodes: Int,
    releaseDate: Date? = nil,
    episodesDir: String? = nil,
    filePattern: FilePattern? = nil,
    introFile: String? = nil,
    outroFile: String? = nil,
    cast: [CastMember]? = nil,
    tts: TTSConfig? = nil
  ) {
    self.number = number
    self.title = title
    self.description = description
    self.episodes = episodes
    self.releaseDate = releaseDate
    self.episodesDir = episodesDir
    self.filePattern = filePattern
    self.introFile = introFile
    self.outroFile = outroFile
    self.cast = cast
    self.tts = tts
  }
}
