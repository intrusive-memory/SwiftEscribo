import Testing

@testable import EscriboCore

/// YAML frontmatter in a **screenplay** — `FountainGrammar` deviations 12, 12a, and 12b.
///
/// ## Why every expectation here is written out by hand
///
/// `ScanGateTests`'s `incrementalScan == fullScan` property cannot catch a single bug in
/// this file, and a leading region is its worst case: both sides of that comparison run the
/// same grammar, so a rule that opens a region on the wrong line is wrong identically on
/// both sides and the gate stays green. Every offset, element, and span kind below is a
/// value computed by hand from the fixture's UTF-16 code units and written down.
///
/// ## The three boundaries this suite exists to pin
///
/// 1. **Position.** `---` is action everywhere in a screenplay except the leading region,
///    and the negative assertion — no frontmatter span *anywhere* in a document whose `---`
///    sits on line 3 — is what fails if the opening criterion is state-blind.
/// 2. **Corroboration** (deviation 12a). Fountain's opening `---` requires the line below to
///    look like a YAML entry, which Markdown's does not. Without it a scene separator typed
///    at the top of a screenplay would swallow the screenplay, since an unterminated region
///    runs to the end of the document.
/// 3. **Coexistence** (deviation 12b). A closed frontmatter region leaves a title page
///    openable beneath it, across blank lines. This is the assertion that fails if the
///    leading region collapses to `.closed` the moment the YAML ends.
@Suite("Fountain grammar — YAML frontmatter as a leading region")
struct FountainFrontmatterTests {

  // MARK: - Helpers

  /// The text `range` covers, in UTF-16 code units.
  static func text(_ range: Range<Int>, of source: String) -> String {
    String(decoding: Array(source.utf16)[range], as: UTF16.self)
  }

  /// Every span of `kind` and `role`, in document order, as the text it covers.
  static func texts(
    _ kind: SpanKind, role: SpanRole = .content, in result: ScanResult, of source: String
  ) -> [String] {
    result.spans
      .filter { $0.kind == kind && $0.role == role }
      .map { Self.text($0.range, of: source) }
  }

  /// Whether any span or record anywhere in `result` belongs to a frontmatter region.
  ///
  /// The negative assertions below are stated through this rather than through one kind at a
  /// time, because a rule that opens a region wrongly leaks *some* frontmatter vocabulary and
  /// which one is not the point.
  static func carriesFrontmatter(_ result: ScanResult) -> Bool {
    result.spans.contains {
      $0.kind == .frontmatterDelimiter || $0.kind == .frontmatterKey
        || $0.kind == .frontmatterValue
    }
      || result.lineRecords.contains {
        $0.element == .frontmatterDelimiter || $0.element == .frontmatter
      }
  }

  // MARK: - The criterion

  @Test("A screenplay opening with `---` is frontmatter, with key and value spans")
  func aLeadingDelimiterOpensFrontmatter() {
    // `---\ntitle: ep\n---\n`, code unit by code unit:
    //
    //   line 0   0..<4    `-` `-` `-` `\n`
    //                      0   1   2    3
    //   line 1   4..<14   t  i  t  l  e  :  ' ' e   p   `\n`
    //                     4  5  6  7  8  9  10  11  12   13
    //   line 2  14..<18   `-` `-` `-` `\n`
    //                     14  15  16   17
    //   line 3  18..<18   the empty final line a trailing terminator produces
    let source = "---\ntitle: ep\n---\n"
    let result = FountainGrammarTests.fullScan(source)

    #expect(
      result.lineRecords.map(\.element) == [
        .frontmatterDelimiter, .frontmatter, .frontmatterDelimiter, .blank,
      ])

    // The delimiters are markers and carry no content: an empty range where content would
    // have begun, exactly as a closing code fence does.
    #expect(result.lineRecords[0].contentRange == 3..<3)
    #expect(result.lineRecords[2].contentRange == 17..<17)
    // The entry's content is its **value**, not the whole line.
    #expect(result.lineRecords[1].contentRange == 11..<13)

    #expect(
      Self.texts(.frontmatterDelimiter, role: .marker, in: result, of: source) == ["---", "---"])
    #expect(Self.texts(.frontmatterKey, in: result, of: source) == ["title"])
    #expect(Self.texts(.frontmatterKey, role: .marker, in: result, of: source) == [": "])
    #expect(Self.texts(.frontmatterValue, in: result, of: source) == ["ep"])

    // The state is what carries the region across the line break, and this is the assertion
    // that goes red if it is computed and not carried.
    #expect(result.lineRecords[0].startState.openConstruct == 0)
    #expect(result.lineRecords[1].startState.openConstruct == FountainGrammar.frontmatterTag)
    #expect(result.lineRecords[2].startState.openConstruct == FountainGrammar.frontmatterTag)
    #expect(result.lineRecords[3].startState.openConstruct == 0)
  }

  @Test("Inside a region nothing is Fountain: a cue, a slug line, and a `#` are all YAML")
  func insideARegionNoFountainElementIsRecognized() {
    // Every line between the fences is shaped like a Fountain element and must not be one:
    // `# season` is a section marker, `BOB` an ALL-CAPS cue candidate, `INT. HOUSE` a slug
    // line, `=== ` a page break, `~lyric` a lyric.
    let source = """
      ---
      show: The Show
      # season
      BOB
      INT. HOUSE
      ===
      ~lyric
      ---
      """
    let result = FountainGrammarTests.fullScan(source)

    #expect(
      result.lineRecords.map(\.element) == [
        .frontmatterDelimiter, .frontmatter, .frontmatter, .frontmatter, .frontmatter,
        .frontmatter, .frontmatter, .frontmatterDelimiter,
      ])

    // Stated negatively too, because the list above would still pass if the grammar emitted
    // a section span *and* classified the line as frontmatter.
    for kind in [SpanKind.section, .sceneHeading, .character, .pageBreak, .lyrics] {
      #expect(
        !result.spans.contains { $0.kind == kind },
        "no \(kind.rawValue) span may appear inside a frontmatter region")
    }
  }

  @Test("A key with no value, a `#` comment, and a sequence entry all stay inside the region")
  func degradingLinesStayInTheRegion() {
    let source = """
      ---
      cast:
        - BOB
      # a comment
      url: https://example.com
      ---
      """
    let result = FountainGrammarTests.fullScan(source)

    #expect(
      result.lineRecords.map(\.element) == [
        .frontmatterDelimiter, .frontmatter, .frontmatter, .frontmatter, .frontmatter,
        .frontmatterDelimiter,
      ])

    // `cast:` is a key with no value — a marker and no `.frontmatterValue` span. The `- BOB`
    // sequence entry and the `#` comment carry no key at all and degrade to `.text`, which is
    // the shared rule refusing to invent structure.
    #expect(Self.texts(.frontmatterKey, in: result, of: source) == ["cast", "url"])
    // YAML's colon rule: `url: https://example.com` splits at the first colon **followed by
    // whitespace**, so the value keeps its scheme rather than the key becoming `url: https`.
    #expect(Self.texts(.frontmatterValue, in: result, of: source) == ["https://example.com"])
  }

  // MARK: - The boundary: position

  @Test("`---` below the leading region is action, and opens no frontmatter anywhere")
  func aDelimiterBelowTheLeadingRegionIsAction() {
    // The body below the first blank line is byte-for-byte the fixture above, so the *only*
    // difference between the two documents is where the `---` sits.
    let source = "INT. HOUSE - DAY\n\n---\ntitle: ep\n---\n"
    let result = FountainGrammarTests.fullScan(source)

    #expect(result.lineRecords[0].element == .sceneHeading)
    #expect(result.lineRecords[2].element == .action, "`---` on line 3 is action")

    // **This is the assertion with teeth.** "Line 3 is action" was already true before this
    // rule existed and would stay green with every line of it deleted. What can only be true
    // because the position rule is right is that *no* frontmatter is anywhere in this
    // document — not on the `---`, and not on the `title: ep` beneath it, which is the line
    // an over-broad rule would key off.
    #expect(
      !Self.carriesFrontmatter(result),
      "a `---` below the leading region opens no frontmatter region")
  }

  // MARK: - The boundary: corroboration (deviation 12a)

  @Test("A leading `---` with no YAML under it is action, not the top of a region")
  func anUncorroboratedDelimiterIsAction() {
    // A scene separator typed at the top of a screenplay. Without deviation 12a's
    // corroboration the unterminated region would run to the end of the document and every
    // line of this screenplay would be YAML.
    let source = "---\nINT. HOUSE - DAY\n\nBOB\nHello there.\n"
    let result = FountainGrammarTests.fullScan(source)

    #expect(result.lineRecords[0].element == .action)
    #expect(!Self.carriesFrontmatter(result), "an uncorroborated `---` opens no region")
    // And the screenplay under it is still a screenplay — the point of declining the region.
    #expect(result.lineRecords[3].element == .character)
    #expect(result.lineRecords[4].element == .dialogue)
  }

  @Test("A `---` on the last line of a document corroborates nothing and stays action")
  func aTrailingDelimiterAloneIsAction() {
    let source = "---"
    let result = FountainGrammarTests.fullScan(source)

    #expect(result.lineRecords[0].element == .action)
    #expect(!Self.carriesFrontmatter(result))
  }

  @Test("A `#` comment corroborates the opening delimiter, exactly as a key does")
  func aCommentCorroboratesTheOpeningDelimiter() {
    let source = "---\n# generated, do not edit\ntitle: ep\n---\n"
    let result = FountainGrammarTests.fullScan(source)

    #expect(result.lineRecords[0].element == .frontmatterDelimiter)
    #expect(result.lineRecords[1].element == .frontmatter)
  }

  // MARK: - The boundary: coexistence with the title page (deviation 12b)

  @Test("A title page still opens under a closed frontmatter region, across a blank line")
  func aTitlePageOpensBelowAClosedRegion() {
    let source = """
      ---
      type: episode
      ---

      Title: The One
      Author: Nobody

      INT. HOUSE - DAY
      """
    let result = FountainGrammarTests.fullScan(source)

    #expect(
      result.lineRecords.map(\.element) == [
        .frontmatterDelimiter, .frontmatter, .frontmatterDelimiter, .blank,
        .titlePageKey, .titlePageKey, .blank, .sceneHeading,
      ])

    // The keys are the title page's, not the region's: two vocabularies, one document.
    #expect(Self.texts(.titlePageKey, in: result, of: source) == ["Title", "Author"])
    #expect(Self.texts(.frontmatterKey, in: result, of: source) == ["type"])
  }

  @Test("A screenplay body under a closed region is a body, and the title page stays shut")
  func aBodyBelowAClosedRegionIsABody() {
    // The same document as above with the title page removed. `.afterFrontmatter` must not
    // make a title page out of the first line that happens to carry a colon — here the
    // transition `CUT TO:`, which is deviation 11's canonical trap.
    let source = "---\ntype: episode\n---\n\nCUT TO:\n\nINT. HOUSE - DAY\n"
    let result = FountainGrammarTests.fullScan(source)

    #expect(
      result.lineRecords.map(\.element) == [
        .frontmatterDelimiter, .frontmatter, .frontmatterDelimiter, .blank,
        .transition, .blank, .sceneHeading, .blank,
      ])
    #expect(Self.texts(.titlePageKey, in: result, of: source).isEmpty)
  }

  @Test("The leading region is one-shot: a second `---` block lower down is action")
  func aSecondRegionDoesNotOpen() {
    let source = "---\ntitle: ep\n---\n\n---\ntitle: again\n---\n"
    let result = FountainGrammarTests.fullScan(source)

    #expect(
      result.lineRecords.map(\.element) == [
        .frontmatterDelimiter, .frontmatter, .frontmatterDelimiter, .blank,
        .action, .action, .action, .blank,
      ])
    #expect(Self.texts(.frontmatterKey, in: result, of: source) == ["title"])
  }

  // MARK: - Unterminated

  @Test("An unterminated region runs to the end of the document and returns normally")
  func anUnterminatedRegionRunsToTheEnd() {
    let source = "---\ntitle: ep\nBOB\nHello there.\n"
    let result = FountainGrammarTests.fullScan(source)

    #expect(
      result.lineRecords.map(\.element) == [
        .frontmatterDelimiter, .frontmatter, .frontmatter, .frontmatter, .frontmatter,
      ])
    #expect(
      result.lineRecords.last?.startState.openConstruct == FountainGrammar.frontmatterTag,
      "the region is still open at the last line")
  }

  // MARK: - Inside a `fountain` fence

  @Test("A frontmatter region opens on the first line of a `fountain` fence")
  func aRegionOpensInsideANestedFence() {
    // The opening criterion is the title-page region rather than the line index, which is
    // what makes this work: the first line of a fence is `documentStart` for the nested scan
    // exactly as line 0 is for a standalone screenplay. A rule keyed to `line.index == 0`
    // would classify none of this.
    let source = "intro\n```fountain\n---\ntitle: ep\n---\nBOB\n```\noutro"
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    let result = scanner.fullScan(source)

    #expect(result.lineRecords[2].element == .frontmatterDelimiter)
    #expect(result.lineRecords[3].element == .frontmatter)
    #expect(result.lineRecords[4].element == .frontmatterDelimiter)
    #expect(Self.texts(.frontmatterKey, in: result, of: source) == ["title"])
    // The outer fence is still the open construct at every line inside it; the Fountain
    // region rides in the nested half of the state, which is the separation DL-112 exists
    // for.
    #expect(
      result.lineRecords[3].startState.openConstruct == MarkdownGrammar.fountainFenceTag)
    #expect(
      result.lineRecords[3].startState.nestedFountain.openConstruct
        == FountainGrammar.frontmatterTag)
  }

  // MARK: - Round trip

  @Test("The writer re-emits a frontmatter region byte for byte")
  func theWriterPreservesTheRegionVerbatim() {
    // Indentation is significant in YAML, `- ` is a sequence entry rather than anything to
    // canonicalize, and this writer knows no YAML — so the only correct output is the input.
    let source = """
      ---
      title: Episode One
      cast:
        - BOB
        -   JANE
      note:    padded value
      ---

      Title: Episode One

      INT. HOUSE - DAY
      """
    #expect(FountainWriterHarness.roundTrip(source) == source)
  }
}
