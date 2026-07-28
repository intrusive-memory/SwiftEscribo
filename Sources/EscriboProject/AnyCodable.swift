// Vendored verbatim from SwiftProyecto (`Sources/SwiftProyecto/Models/`) by
// OPERATION FOUNTAIN SURGEON Sortie 32, 2026-07-26, under D-5. Copied, not moved:
// SwiftProyecto still owns its original and is repointed at this target later.
// Below this block the file is byte-identical to its source. Change it here only
// for a defect that also exists there, and record the decision-log number.

import Foundation

/// A type-erased wrapper for storing arbitrary Codable values.
///
/// `AnyCodable` allows you to store any `Codable` value while preserving its
/// type information through encoding and decoding cycles. This is useful when
/// you need to store heterogeneous Codable values in a collection or when
/// the specific type is not known at compile time.
///
/// ## Supported Types
///
/// - Primitives: `Bool`, `Int`, `Double`, `Float`, `String`
/// - Collections: `[T]` where T is `Codable`, `[String: T]` where T is `Codable`
/// - Nested: Custom `Codable` structs
/// - Optionals: `Optional<T>` where T is `Codable`
///
/// ## Example
///
/// ```swift
/// let stringValue = AnyCodable("hello")
/// let intValue = AnyCodable(42)
/// let arrayValue = AnyCodable(["a", "b", "c"])
///
/// let data = try JSONEncoder().encode(stringValue)
/// let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
/// ```
///
/// ## Type Preservation
///
/// The wrapped value's type is preserved through encoding and decoding using
/// internal JSON representation. When you decode an `AnyCodable`, you get back
/// an equivalent value that can be compared for equality.
public struct AnyCodable: Codable, Sendable, Equatable {

  /// The type-erased value stored as encoded data.
  ///
  /// This ensures thread-safety (Sendable) while preserving type information.
  private let encodedData: Data

  /// Creates a type-erased wrapper for the given Codable value.
  ///
  /// - Parameter value: The value to wrap. Must conform to `Codable`.
  /// - Throws: `EncodingError` if the value cannot be encoded.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let wrapped = try AnyCodable(42)
  /// let wrapped2 = try AnyCodable(["key": "value"])
  /// ```
  public init<T: Codable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = .sortedKeys
    self.encodedData = try encoder.encode(value)
  }

  /// Decodes the wrapped value as the specified type.
  ///
  /// - Parameter type: The type to decode the wrapped value as.
  /// - Returns: The decoded value of type `T`.
  /// - Throws: `DecodingError` if the wrapped value cannot be decoded as `T`.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let wrapped = try AnyCodable(42)
  /// let value = try wrapped.decode(Int.self)  // 42
  /// ```
  public func decode<T: Codable>(_ type: T.Type) throws -> T {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(T.self, from: encodedData)
  }

  // MARK: - Codable

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    // Try to decode as various types and store the encoded representation
    if let bool = try? container.decode(Bool.self) {
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = .sortedKeys
      self.encodedData = try encoder.encode(bool)
    } else if let int = try? container.decode(Int.self) {
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = .sortedKeys
      self.encodedData = try encoder.encode(int)
    } else if let double = try? container.decode(Double.self) {
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = .sortedKeys
      self.encodedData = try encoder.encode(double)
    } else if let string = try? container.decode(String.self) {
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = .sortedKeys
      self.encodedData = try encoder.encode(string)
    } else if let array = try? container.decode([AnyCodable].self) {
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = .sortedKeys
      self.encodedData = try encoder.encode(array)
    } else if let dict = try? container.decode([String: AnyCodable].self) {
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = .sortedKeys
      self.encodedData = try encoder.encode(dict)
    } else {
      // Try to decode as raw JSON data
      if let data = try? container.decode(Data.self) {
        self.encodedData = data
      } else {
        throw DecodingError.dataCorruptedError(
          in: container,
          debugDescription: "AnyCodable value cannot be decoded"
        )
      }
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()

    // Try to decode and re-encode to preserve the original structure
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    if let bool = try? decoder.decode(Bool.self, from: encodedData) {
      try container.encode(bool)
    } else if let int = try? decoder.decode(Int.self, from: encodedData) {
      try container.encode(int)
    } else if let double = try? decoder.decode(Double.self, from: encodedData) {
      try container.encode(double)
    } else if let string = try? decoder.decode(String.self, from: encodedData) {
      try container.encode(string)
    } else if let array = try? decoder.decode([AnyCodable].self, from: encodedData) {
      try container.encode(array)
    } else if let dict = try? decoder.decode([String: AnyCodable].self, from: encodedData) {
      try container.encode(dict)
    } else {
      // Fallback: encode as raw data
      try container.encode(encodedData)
    }
  }

  // MARK: - Equatable

  public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
    // Two AnyCodable values are equal if their encoded representations match
    return lhs.encodedData == rhs.encodedData
  }
}
