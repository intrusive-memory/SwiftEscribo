import Testing

@testable import EscriboCore

/// GLOSA directives inside Fountain notes — Sortie 16.
///
/// Every expectation here, like ``FountainRegionTests``, was written out **by hand**
/// against the source string, never produced by running the scanner and pasting the
/// answer back. The gate test (`ScanGateTests`'s `incrementalScan == fullScan`) runs the
/// same grammar on both sides of its comparison and cannot catch a structural span in
/// the wrong place, the wrong kind, or missing outright — a mutation on this very
/// package once dropped `FountainGrammar.lookahead` to zero and the gate held at
/// 288/288 while 62 hand-written tests went red. Do not delete an expectation here on
/// the grounds that the gate covers it.
@Suite("GLOSA directives inside Fountain notes")
struct GlosaScannerTests {

  // MARK: - The sortie's exit criteria, verbatim

  @Test(
    "`[[<breath length=\"4s\" strength=\"strong\"/>]]` yields distinct spans for the tag, each attribute name, each attribute value, and the punctuation"
  )
  func wellFormedDirectiveIsScannedStructurally() {
    let source = "[[<breath length=\"4s\" strength=\"strong\"/>]]"
    let result = FountainGrammarTests.fullScan(source)

    #expect(result.lineRecords[0].element == .note)

    // Hand-counted against the source: `<` at 2, `breath` at 3..<9, the space at
    // 9..<10, `length` at 10..<16, `="` at 16..<18, `4s` at 18..<20, the closing `"`
    // at 20..<21, the space at 21..<22, `strength` at 22..<30, `="` at 30..<32,
    // `strong` at 32..<38, the closing `"` at 38..<39, `/>` at 39..<41.
    #expect(FountainRegionTests.texts(.glosaTag, in: result, of: source) == ["breath"])
    #expect(
      FountainRegionTests.texts(.glosaAttributeName, in: result, of: source) == [
        "length", "strength",
      ])
    #expect(
      FountainRegionTests.texts(.glosaAttributeValue, in: result, of: source) == [
        "4s", "strong",
      ])
    #expect(
      FountainRegionTests.texts(.glosaPunctuation, role: .marker, in: result, of: source) == [
        "<", " ", "=\"", "\"", " ", "=\"", "\"", "/>",
      ])

    // No content is unaccounted for and none is duplicated: the note's own `[[`/`]]`
    // markers plus every GLOSA span sum to exactly the source length.
    #expect(result.spans.reduce(0) { $0 + $1.range.count } == source.utf16.count)

    // Nothing here degraded to plain text — this directive is entirely well-formed.
    #expect(FountainRegionTests.texts(.text, in: result, of: source).isEmpty)
  }

  @Test("`[[<breath length=>]]` — malformed GLOSA — tiles the range completely and never crashes")
  func malformedDirectiveDegradesToText() {
    let source = "[[<breath length=>]]"
    let result = FountainGrammarTests.fullScan(source)

    // `fullScan` already ran `ScanInvariants.check`, which is the "still tiles the
    // range" half of this criterion — ordered, non-overlapping, contiguous, and total
    // over the document. Restated here as an explicit sum so a reader does not have to
    // trust that invariant call silently:
    #expect(result.spans.reduce(0) { $0 + $1.range.count } == source.utf16.count)

    #expect(result.lineRecords[0].element == .note)

    // The whole malformed directive — from the opening `<` through the `>` that was
    // supposed to open a quoted value — degrades to one `.text` span, per task 4.
    // Hand-counted: the note's content is `<breath length=>`, positions 2..<18.
    #expect(FountainRegionTests.texts(.text, in: result, of: source) == ["<breath length=>"])

    // And nothing structural leaked through: a malformed directive contributes no
    // partial tag or attribute spans, because `scanDirective` discards everything it
    // had accumulated the moment it recognizes the directive cannot be completed.
    #expect(FountainRegionTests.texts(.glosaTag, in: result, of: source).isEmpty)
    #expect(FountainRegionTests.texts(.glosaAttributeName, in: result, of: source).isEmpty)
    #expect(FountainRegionTests.texts(.glosaAttributeValue, in: result, of: source).isEmpty)
    #expect(FountainRegionTests.texts(.glosaPunctuation, in: result, of: source).isEmpty)
  }

  // MARK: - The seven tag forms the sortie brief names

  @Test(
    "Every tag form the brief names scans to a `glosaTag` span carrying its own name, no whitelist consulted",
    arguments: [
      ("[[<breath>]]", "breath"),
      ("[[<pause>]]", "pause"),
      ("[[<shot/>]]", "shot"),
      ("[[<include/>]]", "include"),
      ("[[<SceneContext>]]", "SceneContext"),
      ("[[<Intent>]]", "Intent"),
      ("[[<Constraint>]]", "Constraint"),
    ]
  )
  func namedTagFormsScanStructurally(source: String, tagName: String) {
    let result = FountainGrammarTests.fullScan(source)
    #expect(result.lineRecords[0].element == .note)
    #expect(FountainRegionTests.texts(.glosaTag, in: result, of: source) == [tagName])
    // Every code unit still tiles — self-closing and plain-opening forms alike.
    #expect(result.spans.reduce(0) { $0 + $1.range.count } == source.utf16.count)
  }

  // MARK: - A tag pair with prose inside it

  @Test("An opening and closing tag pair both yield their tag name; prose between them stays note text")
  func openingAndClosingTagPairSurroundProse() {
    let source = "[[<SceneContext>a hallway, dim light</SceneContext>]]"
    let result = FountainGrammarTests.fullScan(source)

    #expect(result.lineRecords[0].element == .note)
    #expect(
      FountainRegionTests.texts(.glosaTag, in: result, of: source) == [
        "SceneContext", "SceneContext",
      ])
    #expect(FountainRegionTests.texts(.note, in: result, of: source) == ["a hallway, dim light"])
    #expect(result.spans.reduce(0) { $0 + $1.range.count } == source.utf16.count)
  }

  // MARK: - No false positives on ordinary note prose

  @Test("A `<` in ordinary note prose, not followed by a letter or `/`, is not mistaken for a directive")
  func lessThanInProseIsNotADirective() {
    let source = "[[5 < 3 is false]]"
    let result = FountainGrammarTests.fullScan(source)

    #expect(result.lineRecords[0].element == .note)
    #expect(FountainRegionTests.texts(.note, in: result, of: source) == ["5 < 3 is false"])
    #expect(FountainRegionTests.texts(.glosaTag, in: result, of: source).isEmpty)
    #expect(FountainRegionTests.texts(.text, in: result, of: source).isEmpty)
  }

  @Test("A note with no `<` at all is completely unaffected — GLOSA scanning changes nothing")
  func ordinaryNoteIsUnaffected() {
    let source = "[[just a plain note]]"
    let result = FountainGrammarTests.fullScan(source)

    #expect(result.lineRecords[0].element == .note)
    #expect(result.spans.count == 3)
    #expect(result.spans[1].kind == .note)
    #expect(result.spans[1].role == .content)
    #expect(FountainRegionTests.text(result.spans[1].range, of: source) == "just a plain note")
  }

  // MARK: - Degenerate and hostile GLOSA input

  @Test(
    "Degenerate GLOSA-shaped note content scans without failing and tiles completely",
    arguments: [
      "[[<]]", "[[</]]", "[[<a]]", "[[<a ]]", "[[<a/]]", "[[<a b]]", "[[<a b=]]",
      "[[<a b=\"]]", "[[<a b=\"\">]]", "[[<a b=\"v\" c=\"w\"]]", "[[<a><b></a></b>]]",
      "[[<<a>>]]", "[[<a//>]]", "[[<a b=\"v\"/]]", "[[< a>]]", "[[<1a>]]",
      "[[<a b=\"v\">extra</a>]]",
    ]
  )
  func degenerateGlosaDocuments(source: String) {
    let result = FountainGrammarTests.fullScan(source)
    // The totality half of the criterion, restated explicitly rather than only via the
    // invariant helper `fullScan` already ran on the way out.
    #expect(result.spans.reduce(0) { $0 + $1.range.count } == source.utf16.count)
    #expect(result.lineRecords[0].element == .note)
  }

  // MARK: - Incremental behaviour survives a directive edit

  @Test("Typing a GLOSA directive into an existing note keeps the incremental scan honest")
  func typingADirectiveMatchesAFullScan() {
    let base = "Bob waits.\n\n[[a note]]\n"
    var scanner = IncrementalScanner(grammar: FountainGrammar())
    let first = scanner.fullScan(base)
    ScanInvariants.check(first, text: base, editedRange: nil, "glosa base")

    // Replace `a note` (offsets 14..<20, six code units) with a self-closing directive
    // (`<pause length="2s"/>`, twenty code units).
    let edited = ScanInvariants.splice(base, 14..<20, "<pause length=\"2s\"/>")
    let editResult = scanner.incrementalScan(
      TextEdit(range: 14..<20, replacementLength: 20), in: edited)
    ScanInvariants.check(editResult, text: edited, editedRange: 14..<34, "glosa directive typed")

    var fresh = IncrementalScanner(grammar: FountainGrammar())
    let fullResult = fresh.fullScan(edited)
    ScanInvariants.expectSameElements(
      scanner.startStates, fresh.startStates, "startStates", "glosa directive typed")
    ScanInvariants.expectSameElements(
      editResult.lineRecords,
      fullResult.lineRecords.filter { editResult.lines.contains($0.index) },
      "lineRecords", "glosa directive typed")

    #expect(FountainRegionTests.texts(.glosaTag, in: fullResult, of: edited) == ["pause"])
    #expect(FountainRegionTests.texts(.glosaAttributeName, in: fullResult, of: edited) == ["length"])
    #expect(FountainRegionTests.texts(.glosaAttributeValue, in: fullResult, of: edited) == ["2s"])
  }
}
