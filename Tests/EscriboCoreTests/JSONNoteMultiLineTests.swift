import Testing

@testable import EscriboCore

/// JSON notes that span lines: the context carried in ``LineState/jsonNote``.
///
/// Expectations are written by hand against the source, as in ``GlosaScannerTests``. Test
/// documents open with an action line because a first line containing `:` opens a title
/// page.
@Suite("JSON notes across lines")
struct JSONNoteMultiLineTests {

  // MARK: - Helpers

  private static func texts(
    _ kind: SpanKind, role: SpanRole = .content, in result: ScanResult, of source: String
  ) -> [String] {
    FountainRegionTests.texts(kind, role: role, in: result, of: source)
  }

  private static func punctuation(_ result: ScanResult, _ source: String) -> [String] {
    texts(.glosaPunctuation, role: .marker, in: result, of: source)
  }

  /// The JSON phase each line **begins** in.
  private static func phases(_ result: ScanResult) -> [JSONNoteContext.Phase] {
    result.lineRecords.map(\.startState.jsonNote.phase)
  }

  // MARK: - Valid multi-line notes

  @Test("A pretty-printed JSON note is scanned across its lines")
  func multiLineValidNote() {
    let source = """
      Bob waits.

      [[{
        "shot": "wide",
        "n": [1, 2,
          true],
        "o": {"k": null}
      }]]
      Jane enters.
      """
    let result = FountainGrammarTests.fullScan(source)
    #expect(
      result.lineRecords.map(\.element) == [
        .action, .blank, .note, .note, .note, .note, .note, .note, .action,
      ])
    #expect(
      Self.texts(.glosaJSONKey, in: result, of: source) == ["\"shot\"", "\"n\"", "\"o\"", "\"k\""])
    #expect(Self.texts(.glosaJSONString, in: result, of: source) == ["\"wide\""])
    #expect(Self.texts(.glosaJSONNumber, in: result, of: source) == ["1", "2"])
    #expect(Self.texts(.glosaJSONLiteral, in: result, of: source) == ["true", "null"])
    #expect(
      Self.punctuation(result, source) == [
        "{", ":", ",", ":", "[", ",", ",", "]", ",", ":", "{", ":", "}", "}",
      ])
    // Only line terminators are `.text`; nothing in the note degraded to it.
    #expect(Self.texts(.text, in: result, of: source).allSatisfy { $0 == "\n" })
    // Inside the note the context is live; after it closes, it is the default again.
    #expect(Self.phases(result)[3] == .awaitingQuote)
    #expect(Self.phases(result)[4...7].allSatisfy { $0 == .json })
    #expect(result.lineRecords[8].startState.jsonNote == JSONNoteContext())
  }

  @Test("`[[` alone on its line: the trigger is decided on a later line")
  func openerAloneOnItsLine() {
    let source = "Bob waits.\n\n[[\n\n{\n  \"a\": 1\n}\n]]\nJane enters."
    let result = FountainGrammarTests.fullScan(source)
    #expect(Self.phases(result)[3] == .awaitingContent)
    #expect(Self.phases(result)[4] == .awaitingContent)
    #expect(Self.phases(result)[5] == .awaitingQuote)
    #expect(Self.texts(.glosaJSONKey, in: result, of: source) == ["\"a\""])
    #expect(Self.texts(.glosaJSONNumber, in: result, of: source) == ["1"])
    #expect(Self.punctuation(result, source) == ["{", ":", "}"])
    #expect(result.lineRecords[8].element == .action)
  }

  @Test("`[[` alone, then a tag directive: still a tag-directive note")
  func openerAloneThenTagDirective() {
    let source = "Bob waits.\n\n[[\n<breath length=\"4s\"/>\n]]"
    let result = FountainGrammarTests.fullScan(source)
    #expect(Self.texts(.glosaTag, in: result, of: source) == ["breath"])
    #expect(Self.texts(.glosaJSONKey, in: result, of: source).isEmpty)
  }

  @Test("`[[{` then a line break then `\"` is JSON")
  func braceThenLineBreakThenQuote() {
    let source = "Bob waits.\n\n[[{\n\"a\": true}]]"
    let result = FountainGrammarTests.fullScan(source)
    #expect(Self.phases(result)[3] == .awaitingQuote)
    #expect(Self.texts(.glosaJSONKey, in: result, of: source) == ["\"a\""])
    #expect(Self.texts(.glosaJSONLiteral, in: result, of: source) == ["true"])
    #expect(Self.punctuation(result, source) == ["{", ":", "}"])
  }

  @Test("`[[{` then a line break then not `\"`: only the speculative `{` is coloured")
  func braceThenLineBreakThenNotAQuote() {
    // A span may depend only on what precedes it, so the `{` alone on its line is coloured
    // before the next line can decide the trigger. Everything after it is a plain note.
    let source = "Bob waits.\n\n[[{\nsic}]]"
    let result = FountainGrammarTests.fullScan(source)
    #expect(Self.punctuation(result, source) == ["{"])
    #expect(Self.texts(.note, in: result, of: source) == ["sic}"])
    #expect(Self.phases(result)[3] == .awaitingQuote)
  }

  // MARK: - Malformed

  @Test("A string that runs past the end of its line is malformed (JSON forbids raw line breaks)")
  func stringSpanningLinesIsMalformed() {
    let source = "Bob waits.\n\n[[{\"a\": \"open\nstill\", \"b\": 1}]]\nJane enters."
    let result = FountainGrammarTests.fullScan(source)
    #expect(Self.texts(.glosaJSONKey, in: result, of: source) == ["\"a\""])
    #expect(Self.texts(.glosaJSONString, in: result, of: source).isEmpty)
    #expect(Self.punctuation(result, source) == ["{", ":"])
    #expect(Self.phases(result)[3] == .malformed)
    // The rest of the note is plain `note`, and the note still closes on line 3.
    #expect(Self.texts(.note, in: result, of: source).last == "still\", \"b\": 1}")
    #expect(result.lineRecords[4].element == .action)
    #expect(result.lineRecords[4].startState.jsonNote == JSONNoteContext())
  }

  @Test("Notes that fail in different places carry one identical malformed state")
  func malformedStateIsUniform() {
    let first = FountainGrammarTests.fullScan("Bob waits.\n\n[[{\"a\" 1,\nmore")
    let second = FountainGrammarTests.fullScan("Bob waits.\n\n[[{\"a\": [1, {\"b\": tru\nmore")
    #expect(first.lineRecords[3].startState == second.lineRecords[3].startState)
    #expect(first.lineRecords[3].startState.jsonNote.phase == .malformed)
  }

  @Test("Nesting past the depth cap across lines is malformed and the rest stays `note`")
  func depthCapAcrossLines() {
    let source =
      "Bob waits.\n\n[[{\"a\":\n" + String(repeating: "[\n", count: 70) + "1\n}]]\nJane enters."
    let result = FountainGrammarTests.fullScan(source)
    // The object is level 1, so 63 arrays fit under the cap of 64 and the 64th fails.
    #expect(
      Self.punctuation(result, source).filter { $0 == "[" }.count == JSONNoteState.maxDepth - 1)
    #expect(Self.texts(.glosaJSONNumber, in: result, of: source).isEmpty)
    let firstFailedLine = 3 + JSONNoteState.maxDepth  // the line after the 64th `[`
    #expect(Self.phases(result)[firstFailedLine] == .malformed)
    #expect(Self.phases(result)[firstFailedLine - 1] == .json)
    #expect(result.lineRecords.last?.element == .action)
  }

  // MARK: - Fountain in Markdown

  @Test("A fenced screenplay's JSON note scans identically to the same text standalone")
  func fencedJSONNoteMatchesStandalone() {
    let body = """
      Bob waits.

      [[
      {
        "a": [1, "x"],
        "b": {"c": false}
      }
      ]]
      [[{"open":
      "y" "z"}]]
      After.

      """
    let opener = "```fountain\n"
    let base = opener.utf16.count
    let nested = opener + body + "```\ntail"

    let standalone = FountainGrammarTests.fullScan(body)
    var nestedScanner = IncrementalScanner(grammar: MarkdownGrammar())
    let hosted = nestedScanner.fullScan(nested)
    ScanInvariants.check(hosted, text: nested, editedRange: nil, "hosted JSON note")

    let shifted = standalone.spans.map {
      EscriboSpan(
        range: ($0.range.lowerBound + base)..<($0.range.upperBound + base),
        kind: $0.kind, style: $0.style, role: $0.role)
    }
    let inFence = hosted.spans.filter {
      $0.range.lowerBound >= base && $0.range.upperBound <= base + body.utf16.count
    }
    ScanInvariants.expectSameElements(inFence, shifted, "nested spans", "standalone JSON note")
    // Written out, so the comparison cannot pass by both sides being wrong together.
    #expect(
      Self.texts(.glosaJSONKey, in: hosted, of: nested) == ["\"a\"", "\"b\"", "\"c\"", "\"open\""])
    #expect(Self.texts(.glosaJSONString, in: hosted, of: nested) == ["\"x\"", "\"y\""])
  }

  // MARK: - Incremental

  static let incrementalBase =
    "Bob waits.\n\n[[{\n  \"a\": [1,\n    2],\n  \"b\": \"s\"\n}]]\nJane."

  @Test(
    "An edit anywhere in a multi-line JSON note equals a full rescan",
    arguments: ["", "\"", "{", "[", "]]", "\n", "x"])
  func incrementalEditInsideJSONNote(replacement: String) {
    let base = Self.incrementalBase
    let count = base.utf16.count
    for offset in 0...count {
      IncrementalScannerTests.expectIncrementalMatchesFull(
        FountainGrammar(), from: base, replacing: offset..<offset, with: replacement)
      if offset < count {
        IncrementalScannerTests.expectIncrementalMatchesFull(
          FountainGrammar(), from: base, replacing: offset..<(offset + 1), with: replacement)
      }
    }
  }

  @Test("The same edits inside a fenced screenplay equal a full rescan")
  func incrementalEditInsideFencedJSONNote() {
    let base = "intro\n```fountain\n" + Self.incrementalBase + "\n```\ntail"
    let count = base.utf16.count
    for replacement in ["", "\"", "{", "]]"] {
      for offset in 0..<count {
        IncrementalScannerTests.expectIncrementalMatchesFull(
          MarkdownGrammar(), from: base, replacing: offset..<(offset + 1), with: replacement)
      }
    }
  }

  // MARK: - Block grouping

  @Test("A standalone multi-line JSON note is one `.note` block")
  func standaloneNoteIsOneBlock() {
    let shape = FountainBlockGroupingTests.shape(
      "Bob waits.\n\n[[{\n  \"a\": 1,\n  \"b\": 2\n}]]\n\nJane enters.")
    #expect(
      shape == [
        .init(.action, 0, 1), .init(.blank, 1, 2), .init(.note, 2, 6), .init(.blank, 6, 7),
        .init(.action, 7, 8),
      ])
  }

  @Test("A multi-line JSON note between lines of one block is absorbed into it")
  func noteBetweenLinesIsAbsorbed() {
    #expect(
      FountainBlockGroupingTests.shape("Bob waits.\n[[{\n  \"a\": 1\n}]]\nJane enters.")
        == [.init(.action, 0, 5)])
    #expect(
      FountainBlockGroupingTests.shape("BOB\nHello.\n[[{\n  \"a\": 1\n}]]\nStill speaking.")
        == [.init(.speech, 0, 6)])
  }
}
