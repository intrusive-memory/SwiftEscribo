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
    #expect(requireSendable(BlockKind.paragraph) == .paragraph)
  }

  @Test("Every vocabulary type is Hashable, and so usable as a styler cache key")
  func vocabularyIsHashable() {
    _ = requireHashable(SpanKind.heading)
    _ = requireHashable(ElementKind.heading)
    _ = requireHashable(Language.fountain)
    _ = requireHashable(StyleSet([.strong, .emphasis]))
    _ = requireHashable(SpanRole.marker)
    _ = requireHashable(BlockKind.paragraph)

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
    #expect(requireEquatable(BlockKind.speech, BlockKind(rawValue: "speech")))

    #expect(SpanKind.text != SpanKind.heading)
    #expect(ElementKind.codeFence != ElementKind.codeBlock)
    #expect(Language.markdown != Language.fountain)
    #expect(SpanRole.content != SpanRole.marker)
    #expect(BlockKind.paragraph != BlockKind.action)
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

  // MARK: - BlockKind (SwiftEscribo 0.4.0)

  /// Every member of ``BlockKind``, paired with its raw value.
  ///
  /// This table is the **only** guard the block vocabulary has. `BlockKind` is a struct
  /// with static members, not an enum, so there is no exhaustive `switch` anywhere for the
  /// compiler to break when a member is added or respelled — the trade that buys source
  /// compatibility costs exactly this, and paying it here is the point. A member added to
  /// `EscriboBlock.swift` and not added below is caught by the count assertion; a member
  /// *respelled* is caught by its own row.
  static let blockKindRawValueTable: [(BlockKind, String)] = [
    // Markdown (§ 4.1)
    (BlockKind.paragraph, "paragraph"),
    (BlockKind.heading, "heading"),
    (BlockKind.listItem, "listItem"),
    (BlockKind.blockquote, "blockquote"),
    (BlockKind.codeBlock, "codeBlock"),
    (BlockKind.table, "table"),
    (BlockKind.frontmatter, "frontmatter"),
    (BlockKind.thematicBreak, "thematicBreak"),
    (BlockKind.blank, "blank"),
    // Fountain (§ 4.2)
    (BlockKind.sceneHeading, "sceneHeading"),
    (BlockKind.action, "action"),
    (BlockKind.speech, "speech"),
    (BlockKind.transition, "transition"),
    (BlockKind.centered, "centered"),
    (BlockKind.lyrics, "lyrics"),
    (BlockKind.note, "note"),
    (BlockKind.boneyard, "boneyard"),
    (BlockKind.section, "section"),
    (BlockKind.synopsis, "synopsis"),
    (BlockKind.pageBreak, "pageBreak"),
    (BlockKind.titlePage, "titlePage"),
  ]

  @Test("The block vocabulary is exactly the twenty-one members both dialects declare")
  func blockKindTableIsExhaustive() {
    // Nine Markdown members and twelve Fountain ones, counted by hand from
    // `Sources/EscriboCore/EscriboBlock.swift`. There is no compiler check behind this
    // number, which is why it is asserted rather than assumed.
    #expect(Self.blockKindRawValueTable.count == 21)
    #expect(Set(Self.blockKindRawValueTable.map(\.0)).count == 21, "no member listed twice")
    #expect(Set(Self.blockKindRawValueTable.map(\.1)).count == 21, "no raw value listed twice")
  }

  @Test("BlockKind raw values are stable", arguments: blockKindRawValueTable)
  func blockKindRawValues(kind: BlockKind, expected: String) {
    #expect(kind.rawValue == expected)
  }

  @Test("An unrecognized block kind is constructible and equal only to itself")
  func unrecognizedBlockKindsAreLegal() {
    // The forward-compatibility property the struct shape exists for: a consumer reading
    // blocks from a newer core meets a kind this version has never heard of, and must be
    // able to hold and compare it rather than trap.
    let future = BlockKind(rawValue: "figure")
    #expect(future.rawValue == "figure")
    #expect(future == BlockKind(rawValue: "figure"))
    #expect(!Self.blockKindRawValueTable.map(\.0).contains(future))
  }
}
