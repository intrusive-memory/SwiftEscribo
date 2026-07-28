// Vendored verbatim from SwiftProyecto (`Sources/SwiftProyecto/Models/`) by
// OPERATION FOUNTAIN SURGEON Sortie 32, 2026-07-26, under D-5. Copied, not moved:
// SwiftProyecto still owns its original and is repointed at this target later.
// Below this block the file is byte-identical to its source. Change it here only
// for a defect that also exists there, and record the decision-log number.

//
//  LanguageDefinition.swift
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

/// Definition of a language supported by a multi-language project.
///
/// Used in PROJECT.md to specify which languages are available and supported
/// by the project, typically for a multi-language overview document.
///
/// ## Example
///
/// ```yaml
/// languages:
///   - code: en
///     name: English
///     locale: en-US
///   - code: es
///     name: Spanish
///     locale: es-MX
///   - code: fr
///     name: French
///     locale: fr-FR
/// ```
public struct LanguageDefinition: Codable, Sendable, Equatable {
  /// Language code (required, e.g., "en", "es", "fr")
  /// Typically a BCP 47 language subtag
  public let code: String

  /// Language name (required, e.g., "English", "Spanish", "French")
  public let name: String

  /// Optional locale or variant (e.g., "es-MX", "pt-BR", "en-GB")
  /// Can be a full BCP 47 language tag for regional specificity
  public let locale: String?

  /// Create a new language definition.
  public init(
    code: String,
    name: String,
    locale: String? = nil
  ) {
    self.code = code
    self.name = name
    self.locale = locale
  }
}
