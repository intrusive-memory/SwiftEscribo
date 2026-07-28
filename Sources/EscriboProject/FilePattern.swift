// Vendored verbatim from SwiftProyecto (`Sources/SwiftProyecto/Models/`) by
// OPERATION FOUNTAIN SURGEON Sortie 32, 2026-07-26, under D-5. Copied, not moved:
// SwiftProyecto still owns its original and is repointed at this target later.
// Below this block the file is byte-identical to its source. Change it here only
// for a defect that also exists there, and record the decision-log number.

//
//  FilePattern.swift
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

/// Flexible file pattern that accepts either a single String or an array of Strings.
///
/// Used in PROJECT.md to specify which files to include for processing.
/// Supports both glob patterns (e.g., "*.fountain") and explicit file names.
///
/// ## YAML Formats
///
/// ```yaml
/// # Single glob pattern
/// filePattern: "*.fountain"
///
/// # Multiple glob patterns
/// filePattern: ["*.fountain", "*.fdx"]
///
/// # Explicit file list
/// filePattern:
///   - "intro.fountain"
///   - "chapter-01.fountain"
///   - "chapter-02.fountain"
///
/// # Mixed globs and explicit files
/// filePattern:
///   - "intro.fountain"
///   - "chapter-*.fountain"
///   - "outro.fountain"
/// ```
///
public enum FilePattern: Codable, Equatable, Sendable {
  /// A single pattern string (e.g., "*.fountain")
  case single(String)

  /// Multiple pattern strings (e.g., ["*.fountain", "*.fdx"])
  case multiple([String])

  /// Normalize to array for processing.
  ///
  /// Returns the pattern(s) as an array, regardless of whether this was
  /// created from a single string or an array.
  public var patterns: [String] {
    switch self {
    case .single(let pattern):
      return [pattern]
    case .multiple(let patterns):
      return patterns
    }
  }

  /// Returns true if this contains only a single pattern.
  public var isSingle: Bool {
    if case .single = self {
      return true
    }
    return false
  }

  // MARK: - Codable

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    // Try decoding as array first (more specific)
    if let array = try? container.decode([String].self) {
      self = .multiple(array)
    } else if let string = try? container.decode(String.self) {
      self = .single(string)
    } else {
      throw DecodingError.typeMismatch(
        FilePattern.self,
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "Expected String or [String] for filePattern"
        )
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .single(let pattern):
      try container.encode(pattern)
    case .multiple(let patterns):
      try container.encode(patterns)
    }
  }
}

// MARK: - Convenience Initializers

extension FilePattern {
  /// Create a FilePattern from a single string.
  public init(_ pattern: String) {
    self = .single(pattern)
  }

  /// Create a FilePattern from an array of strings.
  public init(_ patterns: [String]) {
    if patterns.count == 1 {
      self = .single(patterns[0])
    } else {
      self = .multiple(patterns)
    }
  }
}

// MARK: - ExpressibleByStringLiteral

extension FilePattern: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self = .single(value)
  }
}

// MARK: - ExpressibleByArrayLiteral

extension FilePattern: ExpressibleByArrayLiteral {
  public init(arrayLiteral elements: String...) {
    if elements.count == 1 {
      self = .single(elements[0])
    } else {
      self = .multiple(elements)
    }
  }
}

// MARK: - CustomStringConvertible

extension FilePattern: CustomStringConvertible {
  public var description: String {
    switch self {
    case .single(let pattern):
      return pattern
    case .multiple(let patterns):
      return "[\(patterns.joined(separator: ", "))]"
    }
  }
}
