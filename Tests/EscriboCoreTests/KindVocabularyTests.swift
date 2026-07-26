import Testing

@testable import EscriboCore

/// Accepts anything `Sendable`. Passing a value here is a compile-time proof of
/// conformance — under Swift 6 language mode a non-`Sendable` argument is an error,
/// not a warning, so the assertion is the call itself.
private func requireSendable<T: Sendable>(_ value: T) -> T { value }

/// Accepts anything `Hashable`, and exercises the conformance so it is not merely
/// declared.
private func requireHashable<T: Hashable>(_ value: T) -> Int { value.hashValue }

/// Accepts anything `Equatable`.
private func requireEquatable<T: Equatable>(_ lhs: T, _ rhs: T) -> Bool { lhs == rhs }

@Suite("Kind vocabulary")
struct KindVocabularyTests {

  // MARK: - Conformance

  @Test("Every vocabulary type is Sendable")
  func vocabularyIsSendable() {
    #expect(requireSendable(SpanKind.text) == .text)
    #expect(requireSendable(ElementKind.paragraph) == .paragraph)
    #expect(requireSendable(Language.markdown) == .markdown)
    #expect(requireSendable(StyleSet.strong) == .strong)
    #expect(requireSendable(SpanRole.content) == .content)
  }

  @Test("Every vocabulary type is Hashable, and so usable as a styler cache key")
  func vocabularyIsHashable() {
    _ = requireHashable(SpanKind.heading)
    _ = requireHashable(ElementKind.heading)
    _ = requireHashable(Language.fountain)
    _ = requireHashable(StyleSet([.strong, .emphasis]))
    _ = requireHashable(SpanRole.marker)

    // The styler's cache is keyed by the whole triple; if any leg lost its
    // conformance this would stop compiling.
    var cache: [SpanKind: [StyleSet: [SpanRole: Int]]] = [:]
    cache[.heading, default: [:]][StyleSet.strong, default: [:]][.marker] = 1
    #expect(cache[.heading]?[StyleSet.strong]?[.marker] == 1)

    let keys: Set<SpanKind> = [.text, .heading, .codeBlock, .codeInfoString, .text]
    #expect(keys.count == 4)
  }

  @Test("Every vocabulary type is Equatable")
  func vocabularyIsEquatable() {
    #expect(requireEquatable(SpanKind.text, SpanKind(rawValue: "text")))
    #expect(requireEquatable(ElementKind.blank, ElementKind(rawValue: "blank")))
    #expect(requireEquatable(Language.markdown, Language(rawValue: "markdown")))
    #expect(requireEquatable(StyleSet.underline, StyleSet(rawValue: 1 << 4)))
    #expect(requireEquatable(SpanRole.marker, SpanRole(rawValue: "marker")))

    #expect(SpanKind.text != SpanKind.heading)
    #expect(ElementKind.codeFence != ElementKind.codeBlock)
    #expect(Language.markdown != Language.fountain)
    #expect(SpanRole.content != SpanRole.marker)
  }

  // MARK: - Construction and extensibility

  @Test("An unrecognized kind is constructible, not an error")
  func unknownKindsAreConstructible() {
    // The whole reason these are structs: a consumer scanning with a newer core
    // against an older theme must degrade in appearance, never fail to compile and
    // never trap. The styler resolving this to a base style is Sortie 7's job; that
    // it can exist at all is this sortie's.
    let unknown = SpanKind(rawValue: "someKindFromAFutureRelease")
    #expect(unknown.rawValue == "someKindFromAFutureRelease")
    #expect(unknown != .text)

    let unknownElement = ElementKind(rawValue: "someElementFromAFutureRelease")
    #expect(unknownElement != .paragraph)

    let unknownLanguage = Language(rawValue: "org-mode")
    #expect(unknownLanguage != .markdown)
    #expect(unknownLanguage != .fountain)
  }

  // MARK: - Raw values

  @Test(
    "SpanKind raw values are stable",
    arguments: [
      (SpanKind.text, "text"),
      (SpanKind.heading, "heading"),
      (SpanKind.codeBlock, "codeBlock"),
      (SpanKind.codeInfoString, "codeInfoString"),
      (SpanKind.sceneHeading, "sceneHeading"),
      (SpanKind.action, "action"),
      (SpanKind.transition, "transition"),
      (SpanKind.centered, "centered"),
      (SpanKind.section, "section"),
      (SpanKind.synopsis, "synopsis"),
      (SpanKind.pageBreak, "pageBreak"),
      (SpanKind.lyrics, "lyrics"),
    ]
  )
  func spanKindRawValues(kind: SpanKind, expected: String) {
    #expect(kind.rawValue == expected)
  }

  @Test(
    "ElementKind raw values are stable",
    arguments: [
      (ElementKind.paragraph, "paragraph"),
      (ElementKind.blank, "blank"),
      (ElementKind.heading, "heading"),
      (ElementKind.codeFence, "codeFence"),
      (ElementKind.codeBlock, "codeBlock"),
      (ElementKind.sceneHeading, "sceneHeading"),
      (ElementKind.action, "action"),
      (ElementKind.transition, "transition"),
      (ElementKind.centered, "centered"),
      (ElementKind.section, "section"),
      (ElementKind.synopsis, "synopsis"),
      (ElementKind.pageBreak, "pageBreak"),
      (ElementKind.lyrics, "lyrics"),
    ]
  )
  func elementKindRawValues(element: ElementKind, expected: String) {
    #expect(element.rawValue == expected)
  }

  @Test(
    "Language raw values are stable",
    arguments: [
      (Language.markdown, "markdown"),
      (Language.fountain, "fountain"),
    ]
  )
  func languageRawValues(language: Language, expected: String) {
    #expect(language.rawValue == expected)
  }

  @Test(
    "SpanRole raw values are stable",
    arguments: [
      (SpanRole.content, "content"),
      (SpanRole.marker, "marker"),
    ]
  )
  func spanRoleRawValues(role: SpanRole, expected: String) {
    #expect(role.rawValue == expected)
  }
}
