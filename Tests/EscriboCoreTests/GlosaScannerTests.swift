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

  @Test(
    "An opening and closing tag pair both yield their tag name; prose between them stays note text")
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

  @Test(
    "A `<` in ordinary note prose, not followed by a letter or `/`, is not mistaken for a directive"
  )
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
    #expect(
      FountainRegionTests.texts(.glosaAttributeName, in: fullResult, of: edited) == ["length"])
    #expect(FountainRegionTests.texts(.glosaAttributeValue, in: fullResult, of: edited) == ["2s"])
  }

  // MARK: - JSON notes (single line)

  /// Scans `content` as a note's content directly through ``GlosaScanner`` and returns
  /// `(kind, text)` pairs, asserting the spans tile the whole chunk.
  private static func jsonSpans(_ content: String) -> [(SpanKind, String)] {
    let units = Array(content.utf16)
    let spans = GlosaScanner.scan(units, in: 0..<units.count, base: 0)
    var cursor = 0
    for span in spans {
      #expect(span.range.lowerBound == cursor, "gap or overlap scanning \(content)")
      cursor = span.range.upperBound
    }
    #expect(cursor == units.count, "spans do not tile \(content)")
    return spans.map { span in
      (span.kind, String(decoding: units[span.range], as: UTF16.self))
    }
  }

  private static func texts(_ kind: SpanKind, in content: String) -> [String] {
    jsonSpans(content).filter { $0.0 == kind }.map(\.1)
  }

  @Test("A JSON note with every value type is subdivided into key, value and punctuation spans")
  func validJSONObjectEveryValueType() {
    let content =
      "{\"s\": \"x\", \"n\": -1.5e+3, \"t\": true, \"f\": false, \"z\": null, \"o\": {\"k\": 0}, \"a\": [1, \"y\", [null]]}"
    #expect(
      Self.texts(.glosaJSONKey, in: content) == [
        "\"s\"", "\"n\"", "\"t\"", "\"f\"", "\"z\"", "\"o\"", "\"k\"", "\"a\"",
      ])
    #expect(Self.texts(.glosaJSONString, in: content) == ["\"x\"", "\"y\""])
    #expect(Self.texts(.glosaJSONNumber, in: content) == ["-1.5e+3", "0", "1"])
    #expect(Self.texts(.glosaJSONLiteral, in: content) == ["true", "false", "null", "null"])
    // Whitespace between tokens stays `note`; nothing degraded to `text`.
    #expect(Self.jsonSpans(content).allSatisfy { $0.0 != .text })
    // Counted from the source: 4 braces + 4 brackets, 8 colons (one per key), and 8
    // commas (6 between the 7 top-level entries, 2 inside the array).
    let punctuation = Self.texts(.glosaPunctuation, in: content)
    #expect(punctuation.filter { $0 == ":" }.count == 8)
    #expect(punctuation.filter { $0 == "," }.count == 8)
    #expect(punctuation.filter { "{}[]".contains($0) }.count == 8)
  }

  @Test("Exponent and negative numbers, and a number directly before a closer")
  func numberForms() {
    #expect(Self.texts(.glosaJSONNumber, in: "{\"a\":-0.5}") == ["-0.5"])
    #expect(Self.texts(.glosaJSONNumber, in: "{\"a\":2E10,\"b\":1e-2}") == ["2E10", "1e-2"])
  }

  @Test("A literal `]]` inside a JSON string, handed to the scanner directly, is one string span")
  func literalDoubleBracketInsideAStringScannedDirectly() {
    let content = "{\"a\":\"]]\"}"
    #expect(Self.texts(.glosaJSONString, in: content) == ["\"]]\""])
    #expect(Self.texts(.glosaPunctuation, in: content) == ["{", ":", "}"])
    // Escaped quote and backslash stay inside the string.
    let escaped = "{\"a\":\"q\\\"]\\\\\"}"
    #expect(Self.texts(.glosaJSONString, in: escaped) == ["\"q\\\"]\\\\\""])
  }

  @Test("A literal `]]` in the document closes the note even inside a JSON string")
  func literalDoubleBracketClosesTheNoteEvenInsideAString() {
    let source = "Bob waits.\n\n[[{\"a\":\"]]\"}]]"
    let result = FountainGrammarTests.fullScan(source)
    // The note content is `{"a":"` — an unterminated string — so nothing is subdivided.
    #expect(FountainRegionTests.texts(.glosaJSONKey, in: result, of: source) == ["\"a\""])
    #expect(FountainRegionTests.texts(.glosaJSONString, in: result, of: source).isEmpty)
    #expect(result.spans.reduce(0) { $0 + $1.range.count } == source.utf16.count)
  }

  @Test(
    "The JSON unicode escape for `]` lets a directive string hold `]]` without closing the note")
  func unicodeEscapedBracketKeepsTheNoteOpen() {
    // Document text: [[{"a":"]\u005d"}]]  (one backslash; no literal `]]` inside the string).
    let source = "Bob waits.\n\n[[{\"a\":\"]\\u005d\"}]]"
    let result = FountainGrammarTests.fullScan(source)
    #expect(result.lineRecords[2].element == .note)
    #expect(FountainRegionTests.texts(.glosaJSONKey, in: result, of: source) == ["\"a\""])
    #expect(
      FountainRegionTests.texts(.glosaJSONString, in: result, of: source) == ["\"]\\u005d\""])
    #expect(
      FountainRegionTests.texts(.glosaPunctuation, role: .marker, in: result, of: source)
        == ["{", ":", "}"])
    // The note closes at the final `]]`: the last two code units are the closing marker.
    let closer = result.spans.last!
    #expect(closer.kind == .note && closer.role == .marker)
    #expect(FountainRegionTests.text(closer.range, of: source) == "]]")
    #expect(result.spans.reduce(0) { $0 + $1.range.count } == source.utf16.count)
  }

  @Test(
    "Malformed JSON stops subdividing at the first error and the rest stays `note`",
    arguments: [
      // (content, JSON-token texts that survive before the error)
      ("{\"a\" 1}", ["{", "\"a\""]),
      ("{\"a\": }", ["{", "\"a\"", ":"]),
      ("{\"a\": 1,, \"b\": 2}", ["{", "\"a\"", ":", "1", ","]),
      ("{\"a\": 01}", ["{", "\"a\"", ":"]),
      ("{\"a\": tru}", ["{", "\"a\"", ":"]),
      ("{\"a\": \"open}", ["{", "\"a\"", ":"]),
      ("{\"a\": [1}", ["{", "\"a\"", ":", "[", "1"]),
      ("{\"a\": 1} trailing", ["{", "\"a\"", ":", "1", "}"]),
      ("{\"a\": 1.}", ["{", "\"a\"", ":"]),
    ]
  )
  func malformedStopsAtFirstError(content: String, surviving: [String]) {
    let spans = Self.jsonSpans(content)  // also asserts tiling
    let tokens = spans.filter { $0.0 != .note }.map(\.1)
    #expect(tokens == surviving)
    // The trailing span is `note` and covers the unscanned tail.
    #expect(spans.last?.0 == .note)
    #expect(spans.allSatisfy { $0.0 != .text })
  }

  @Test("Nesting past the depth cap is malformed and the rest stays `note`")
  func depthCap() {
    let content =
      "{\"a\":" + String(repeating: "[", count: 70) + String(repeating: "]", count: 70) + "}"
    let spans = Self.jsonSpans(content)
    #expect(spans.last?.0 == .note)
    #expect(spans.filter { $0.1 == "[" }.count == JSONNoteState.maxDepth - 1)
  }

  @Test(
    "`{` then optional whitespace then `\"` triggers JSON; anything else is an ordinary note",
    arguments: [
      ("{\"a\":1}", true),
      ("{ \"a\":1}", true),
      ("  {\t\"a\":1}", true),
      ("{sic}", false),
      ("{}", false),
      ("{ 1 }", false),
      ("{", false),
      ("{ ", false),
      ("a {\"a\":1}", false),
    ]
  )
  func jsonTrigger(content: String, isJSON: Bool) {
    let spans = Self.jsonSpans(content)
    let sawJSON = spans.contains { $0.0 == .glosaJSONKey }
    #expect(sawJSON == isJSON)
    if !isJSON {
      #expect(spans.allSatisfy { $0.0 == .note })
    }
  }

  @Test("Through the grammar, `[[{sic}]]` stays a plain note and `[[{ \"a\": 1 }]]` is JSON")
  func triggerThroughTheGrammar() {
    let plain = "[[{sic}]]"
    let plainResult = FountainGrammarTests.fullScan(plain)
    #expect(FountainRegionTests.texts(.note, in: plainResult, of: plain) == ["{sic}"])
    #expect(FountainRegionTests.texts(.glosaPunctuation, in: plainResult, of: plain).isEmpty)

    // A leading action line: a first line containing `:` would open a title page.
    let json = "Bob waits.\n\n[[{ \"a\": 1 }]]"
    let jsonResult = FountainGrammarTests.fullScan(json)
    #expect(jsonResult.lineRecords[2].element == .note)
    #expect(FountainRegionTests.texts(.glosaJSONKey, in: jsonResult, of: json) == ["\"a\""])
    #expect(FountainRegionTests.texts(.glosaJSONNumber, in: jsonResult, of: json) == ["1"])
    #expect(jsonResult.spans.reduce(0) { $0 + $1.range.count } == json.utf16.count)
  }

  @Test("A tag-directive note is unchanged by the JSON trigger")
  func tagDirectiveNoteUnchanged() {
    let source = "[[<breath length=\"4s\"/>]]"
    let result = FountainGrammarTests.fullScan(source)
    #expect(FountainRegionTests.texts(.glosaTag, in: result, of: source) == ["breath"])
    #expect(FountainRegionTests.texts(.glosaJSONKey, in: result, of: source).isEmpty)
  }
}
