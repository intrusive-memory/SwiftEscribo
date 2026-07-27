// Vendored verbatim from SwiftProyecto (`Sources/SwiftProyecto/Models/`) by
// OPERATION FOUNTAIN SURGEON Sortie 32, 2026-07-26, under D-5. Copied, not moved:
// SwiftProyecto still owns its original and is repointed at this target later.
// Below this block the file is byte-identical to its source. Change it here only
// for a defect that also exists there, and record the decision-log number.

//
//  VariantReference.swift
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

/// Status of a variant PROJECT.md file.
///
/// Indicates the production state of a language/season variant.
public enum VariantStatus: String, Codable, Sendable {
  /// Variant is published and complete
  case published

  /// Variant is currently being worked on
  case inProgress = "in_progress"

  /// Variant is in draft state
  case draft

  /// Variant is obsolete or superseded
  case obsolete
}

/// Reference to a language/season variant PROJECT.md file.
///
/// Used in multi-season/multi-language overview documents to index variant
/// PROJECT.md files and track their production status.
///
/// ## Example
///
/// ```yaml
/// variants:
///   - season: 1
///     language: en
///     path: "projects/s01_en/PROJECT.md"
///     status: published
///     introFile: "intro.m4a"
///     outroFile: "outro.m4a"
///   - season: 1
///     language: es
///     path: "projects/s01_es/PROJECT.md"
///     status: published
///   - season: 2
///     language: en
///     path: "projects/s02_en/PROJECT.md"
///     status: in_progress
/// ```
public struct VariantReference: Codable, Sendable, Equatable {
  /// Season number for this variant
  public let season: Int

  /// Language code for this variant (e.g., "en", "es", "fr")
  public let language: String

  /// Relative path to the variant's PROJECT.md file
  public let path: String

  /// Optional status indicator for the variant
  public let status: VariantStatus?

  /// Optional path to intro file (relative to episodesDir)
  public let introFile: String?

  /// Optional path to outro file (relative to episodesDir)
  public let outroFile: String?

  /// Create a new variant reference.
  public init(
    season: Int,
    language: String,
    path: String,
    status: VariantStatus? = nil,
    introFile: String? = nil,
    outroFile: String? = nil
  ) {
    self.season = season
    self.language = language
    self.path = path
    self.status = status
    self.introFile = introFile
    self.outroFile = outroFile
  }
}
