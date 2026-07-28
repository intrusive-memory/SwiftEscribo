// Vendored verbatim from SwiftProyecto (`Sources/SwiftProyecto/Models/`) by
// OPERATION FOUNTAIN SURGEON Sortie 32, 2026-07-26, under D-5. Copied, not moved:
// SwiftProyecto still owns its original and is repointed at this target later.
// Below this block the file is byte-identical to its source. Change it here only
// for a defect that also exists there, and record the decision-log number.

//
//  TTSConfig.swift
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

/// TTS generation configuration stored in PROJECT.md front matter.
///
/// Captures the voice provider, voice identifier, language, and a portable
/// `hablare://` URI that can be resolved by SwiftHablare at runtime.
public struct TTSConfig: Codable, Sendable, Equatable {
  /// Provider identifier (e.g. "apple", "elevenlabs", "qwen")
  public let providerId: String?

  /// Provider-specific voice identifier
  public let voiceId: String?

  /// BCP-47 language code (e.g. "en", "es", "fr")
  public let languageCode: String?

  /// Portable hablare:// URI referencing the voice
  public let voiceURI: String?

  /// Model size/variant for providers that support multiple models (e.g. VoxAlta: "0.6b", "1.7b", "8bit", "4bit")
  public let model: String?

  /// Optional voice URI for action lines (dialogue parentheticals, stage directions)
  public let actionLineVoice: String?

  public init(
    providerId: String? = nil,
    voiceId: String? = nil,
    languageCode: String? = nil,
    voiceURI: String? = nil,
    model: String? = nil,
    actionLineVoice: String? = nil
  ) {
    self.providerId = providerId
    self.voiceId = voiceId
    self.languageCode = languageCode
    self.voiceURI = voiceURI
    self.model = model
    self.actionLineVoice = actionLineVoice
  }
}
