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

  /// **DL-113.** These two tables were exhaustive when they were written at Sortie 1 and
  /// stopped being so at Sortie 13; by 1.0 they covered 12 of 39 `SpanKind`s and 13 of 28
  /// `ElementKind`s. Nothing asserted completeness, so this was drift rather than a defect
  /// — but a spot-check of a *vocabulary* is close to worthless, and Sortie 30 owned the
  /// decision. Made exhaustive, because at 1.0 these raw values stop being an
  /// implementation detail:
  ///
  /// REQUIREMENTS.md § Semver commitments makes reordering or renumbering anything with a
  /// raw value a **major** release, and a `SpanKind`'s raw value is the key a persisted
  /// theme is written against. A rename is therefore not a refactor, it is a silent
  /// breaking change to every theme on disk — invisible to the compiler, invisible to the
  /// styler (which resolves an unrecognized kind to the base style by design), and visible
  /// only as "the highlighting went grey". These two tables are the only thing in the
  /// package that turns it red.
  ///
  /// **The honest limit.** Both directions are not equally checked. Renaming or renumbering
  /// an existing member fails here. *Adding* a member and forgetting to list it does not:
  /// `SpanKind` and `ElementKind` are structs precisely so a consumer can name a kind this
  /// version has never heard of, which is the same property that makes their static members
  /// unenumerable at runtime — there is no `CaseIterable` to conform and no reflection that
  /// reaches them. The count assertions below are the compromise: they fail if a row is
  /// deleted, and the number in them has to be updated by hand when a kind is added, which
  /// is the moment a reader is looking at this file anyway. Verify with
  /// `grep -c 'public static let' Sources/EscriboCore/SpanKind.swift`.
  static let spanKindRawValueTable: [(SpanKind, String)] = [
    // Universal
    (SpanKind.text, "text"),
    // Markdown blocks
    (SpanKind.heading, "heading"),
    (SpanKind.codeBlock, "codeBlock"),
    (SpanKind.codeInfoString, "codeInfoString"),
    (SpanKind.listItem, "listItem"),
    (SpanKind.blockquote, "blockquote"),
    (SpanKind.thematicBreak, "thematicBreak"),
    // Markdown inline
    (SpanKind.link, "link"),
    (SpanKind.linkURL, "linkURL"),
    (SpanKind.linkTitle, "linkTitle"),
    (SpanKind.image, "image"),
    (SpanKind.hardBreak, "hardBreak"),
    // YAML frontmatter
    (SpanKind.frontmatterDelimiter, "frontmatterDelimiter"),
    (SpanKind.frontmatterKey, "frontmatterKey"),
    (SpanKind.frontmatterValue, "frontmatterValue"),
    // GFM
    (SpanKind.tableCell, "tableCell"),
    (SpanKind.tableDelimiter, "tableDelimiter"),
    (SpanKind.taskListUnchecked, "taskListUnchecked"),
    (SpanKind.taskListChecked, "taskListChecked"),
    // Fountain structure
    (SpanKind.sceneHeading, "sceneHeading"),
    (SpanKind.action, "action"),
    (SpanKind.transition, "transition"),
    (SpanKind.centered, "centered"),
    (SpanKind.section, "section"),
    (SpanKind.synopsis, "synopsis"),
    (SpanKind.pageBreak, "pageBreak"),
    (SpanKind.lyrics, "lyrics"),
    // Fountain dialogue
    (SpanKind.character, "character"),
    (SpanKind.characterExtension, "characterExtension"),
    (SpanKind.parenthetical, "parenthetical"),
    (SpanKind.dialogue, "dialogue"),
    // Fountain annotations
    (SpanKind.note, "note"),
    (SpanKind.boneyard, "boneyard"),
    (SpanKind.titlePageKey, "titlePageKey"),
    (SpanKind.titlePageValue, "titlePageValue"),
    // GLOSA, scanned structurally only
    (SpanKind.glosaTag, "glosaTag"),
    (SpanKind.glosaAttributeName, "glosaAttributeName"),
    (SpanKind.glosaAttributeValue, "glosaAttributeValue"),
    (SpanKind.glosaPunctuation, "glosaPunctuation"),
  ]

  static let elementKindRawValueTable: [(ElementKind, String)] = [
    // Universal
    (ElementKind.paragraph, "paragraph"),
    (ElementKind.blank, "blank"),
    // Markdown blocks
    (ElementKind.heading, "heading"),
    (ElementKind.codeFence, "codeFence"),
    (ElementKind.codeBlock, "codeBlock"),
    (ElementKind.unorderedListItem, "unorderedListItem"),
    (ElementKind.orderedListItem, "orderedListItem"),
    (ElementKind.blockquote, "blockquote"),
    (ElementKind.thematicBreak, "thematicBreak"),
    // YAML frontmatter
    (ElementKind.frontmatterDelimiter, "frontmatterDelimiter"),
    (ElementKind.frontmatter, "frontmatter"),
    // GFM
    (ElementKind.tableDelimiterRow, "tableDelimiterRow"),
    (ElementKind.tableRow, "tableRow"),
    // Fountain structure
    (ElementKind.sceneHeading, "sceneHeading"),
    (ElementKind.action, "action"),
    (ElementKind.transition, "transition"),
    (ElementKind.centered, "centered"),
    (ElementKind.section, "section"),
    (ElementKind.synopsis, "synopsis"),
    (ElementKind.pageBreak, "pageBreak"),
    (ElementKind.lyrics, "lyrics"),
    // Fountain dialogue
    (ElementKind.character, "character"),
    (ElementKind.parenthetical, "parenthetical"),
    (ElementKind.dialogue, "dialogue"),
    // Fountain annotations
    (ElementKind.note, "note"),
    (ElementKind.boneyard, "boneyard"),
    (ElementKind.titlePageKey, "titlePageKey"),
    (ElementKind.titlePageValue, "titlePageValue"),
  ]

  @Test("The raw-value tables cover every declared member of both vocabularies")
  func rawValueTablesAreExhaustive() {
    // The counts in `Sources/EscriboCore/{SpanKind,ElementKind}.swift` at 1.0. See the
    // comment above on which direction of drift this catches and which it does not.
    #expect(Self.spanKindRawValueTable.count == 39)
    #expect(Self.elementKindRawValueTable.count == 28)

    // No kind listed twice, in either column — a duplicated row would inflate the count
    // and hide a missing one.
    #expect(Set(Self.spanKindRawValueTable.map(\.0)).count == 39)
    #expect(Set(Self.spanKindRawValueTable.map(\.1)).count == 39)
    #expect(Set(Self.elementKindRawValueTable.map(\.0)).count == 28)
    #expect(Set(Self.elementKindRawValueTable.map(\.1)).count == 28)
  }

  @Test("SpanKind raw values are stable", arguments: spanKindRawValueTable)
  func spanKindRawValues(kind: SpanKind, expected: String) {
    #expect(kind.rawValue == expected)
  }

  @Test("ElementKind raw values are stable", arguments: elementKindRawValueTable)
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
