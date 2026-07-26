import Testing

@testable import EscriboCore

/// The first real grammar through the ``LineGrammar`` seam: ATX headings and fenced
/// code blocks.
///
/// The assertions here are deliberately **exact** — span by span, offset by offset —
/// rather than "contains a heading somewhere". A grammar test that only checks
/// classification passes on a scanner that puts the marker boundary one code unit wrong,
/// and that is the bug that shows up as a flickering `#` while typing.
///
/// Direct assertions throughout, with no shared invariant helper beyond the one
/// `IncrementalScannerTests` already wrote longhand. Sortie 6 owns the always-on harness
/// and the seeded gate property; retrofitting these onto it is cheaper than agreeing on
/// it now.
@Suite("Markdown grammar — ATX headings and fenced code")
struct MarkdownGrammarTests {

  // MARK: - Helpers

  static func fullScan(_ text: String) -> ScanResult {
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    return scanner.fullScan(text)
  }

  /// The UTF-16 offsets of `needle` in `haystack`, hand-computed. No regex, and no
  /// `String.range(of:)` — the offsets under test are UTF-16 offsets, and going through
  /// `String.Index` to produce the expectation would test the bridge instead.
  static func offset(of needle: String, in haystack: String) -> Int {
    let hay = Array(haystack.utf16)
    let pin = Array(needle.utf16)
    guard !pin.isEmpty, hay.count >= pin.count else { return -1 }
    for start in 0...(hay.count - pin.count) {
      var matched = true
      for cursor in 0..<pin.count where hay[start + cursor] != pin[cursor] {
        matched = false
        break
      }
      if matched { return start }
    }
    return -1
  }

  // MARK: - ATX headings

  @Test("`## Heading` is a marker span and a content span differing only in role")
  func headingMarkerAndContentDifferOnlyInRole() {
    // The design point the whole styler rests on: the hashes and the text carry the
    // SAME kind and the SAME style, and differ ONLY in role. Sortie 7's styler resolves
    // attributes from (kind, style) and then multiplies the foreground alpha when the
    // role is `.marker`. If these two spans ever disagree about kind or style, "the
    // hashes show, dimmed, while the text renders as a heading" stops being a
    // consequence of the data model and becomes a special case in the styler.
    let result = Self.fullScan("## Heading\n")

    #expect(result.spans.count == 3)
    let marker = result.spans[0]
    let content = result.spans[1]

    #expect(marker.range == 0..<3, "the marker must swallow the hashes AND the space")
    #expect(content.range == 3..<10)

    #expect(marker.kind == content.kind, "marker and content must carry the same kind")
    #expect(marker.style == content.style, "marker and content must carry the same style")
    #expect(marker.kind == .heading)
    #expect(marker.style == [])

    #expect(marker.role == .marker)
    #expect(content.role == .content)
    #expect(marker.role != content.role, "role is the ONLY axis they may differ on")

    // The terminator is engine-supplied filler, which is what keeps the tiling total.
    #expect(result.spans[2].range == 10..<11)
    #expect(result.spans[2].kind == .text)

    let record = result.lineRecords[0]
    #expect(record.element == .heading)
    #expect(record.depth == 2, "the level lives in `depth`, never in a `.heading2` kind")
    #expect(record.contentRange == 3..<10, "content excludes the markers and the terminator")
    #expect(record.range == 0..<11)
  }

  @Test("Every heading level 1 through 6 lands in `depth` under one `ElementKind`")
  func headingLevelsLiveInDepth() {
    for level in 1...6 {
      let hashes = String(repeating: "#", count: level)
      let result = Self.fullScan("\(hashes) Title")
      let record = result.lineRecords[0]
      #expect(record.element == .heading, "level \(level)")
      #expect(record.depth == level, "level \(level)")
      #expect(record.contentRange == (level + 1)..<(level + 6), "level \(level)")
      #expect(result.spans[0].role == .marker, "level \(level)")
      #expect(result.spans[0].range == 0..<(level + 1), "level \(level)")
    }
  }

  @Test("Seven hashes, a bare hashtag, and four spaces of indent are not headings")
  func nonHeadings() {
    // Each of these is a line a heading scanner gets wrong by being one condition
    // short, and each degrades to a paragraph rather than to an error.
    for text in ["####### Too deep", "#hashtag", "    # indented four", "\t# tabbed"] {
      let result = Self.fullScan(text)
      #expect(result.lineRecords[0].element == .paragraph, "\(text.debugDescription)")
      #expect(result.spans.allSatisfy { $0.kind == .text }, "\(text.debugDescription)")
      #expect(result.lineRecords[0].depth == 0, "\(text.debugDescription)")
    }

    // Up to three spaces is still a heading, and the indent is not content.
    let indented = Self.fullScan("   ### Three")
    #expect(indented.lineRecords[0].element == .heading)
    #expect(indented.lineRecords[0].depth == 3)
    #expect(indented.lineRecords[0].contentRange == 7..<12)
    #expect(indented.spans[0].kind == .text, "the indent is not part of the marker")
    #expect(indented.spans[0].range == 0..<3)
    #expect(indented.spans[1].role == .marker)
  }

  @Test("A closing hash sequence is a marker, and a trailing hash inside the text is not")
  func closingSequenceIsAMarker() {
    let closed = Self.fullScan("## Heading ##")
    #expect(closed.lineRecords[0].contentRange == 3..<10, "closing sequence is not content")
    #expect(closed.spans.count == 3)
    #expect(closed.spans[0].role == .marker)
    #expect(closed.spans[1].role == .content)
    #expect(closed.spans[1].range == 3..<10)
    #expect(closed.spans[2].role == .marker, "the closing run and its space are markers")
    #expect(closed.spans[2].range == 10..<13)
    #expect(closed.spans.allSatisfy { $0.kind == .heading })

    // No preceding whitespace, so it is text, not a closing sequence.
    let attached = Self.fullScan("## Heading##")
    #expect(attached.lineRecords[0].contentRange == 3..<12)

    // An empty heading is legal and has an empty content range.
    let empty = Self.fullScan("###")
    #expect(empty.lineRecords[0].element == .heading)
    #expect(empty.lineRecords[0].depth == 3)
    #expect(empty.lineRecords[0].contentRange == 3..<3)
    #expect(empty.spans.count == 1)
    #expect(empty.spans[0].range == 0..<3)
    #expect(empty.spans[0].role == .marker)
  }

  // MARK: - Fenced code blocks

  @Test("A three-line fenced block spans marker, info string, code, and marker")
  func fencedBlockSpanLayout() {
    let text = "```swift\ncode\n```\n"
    let result = Self.fullScan(text)

    // Line 0 — the opening fence. Delimiter is a marker; the info string is its own
    // kind, because Sortie 21 reads it to dispatch a `fountain` fence.
    #expect(result.spans[0].range == 0..<3)
    #expect(result.spans[0].kind == .codeBlock)
    #expect(result.spans[0].role == .marker)
    #expect(result.spans[1].range == 3..<8)
    #expect(result.spans[1].kind == .codeInfoString)
    #expect(result.spans[1].role == .content)
    #expect(result.lineRecords[0].element == .codeFence)
    #expect(result.lineRecords[0].contentRange == 3..<8, "the info string is the line's content")

    // Line 1 — the code itself.
    #expect(result.spans[3].range == 9..<13)
    #expect(result.spans[3].kind == .codeBlock)
    #expect(result.spans[3].role == .content)
    #expect(result.lineRecords[1].element == .codeBlock)
    #expect(result.lineRecords[1].contentRange == 9..<13)

    // Line 2 — the closing fence. Pure delimiter, so its content range is empty.
    #expect(result.spans[5].range == 14..<17)
    #expect(result.spans[5].kind == .codeBlock)
    #expect(result.spans[5].role == .marker)
    #expect(result.lineRecords[2].element == .codeFence)
    #expect(result.lineRecords[2].contentRange == 17..<17)

    // Line 3 — the empty final line after the last terminator.
    #expect(result.lineRecords[3].element == .blank)
    #expect(result.lineRecords[3].range == 18..<18)

    // And the fence closed: the state after it is the state a document starts in.
    #expect(result.lineRecords[3].startState == LineState.documentStart)
  }

  @Test("An info-string-free fence has an empty content range and no info span")
  func fenceWithoutInfoString() {
    let result = Self.fullScan("~~~\nx\n~~~")
    #expect(result.spans[0].range == 0..<3)
    #expect(result.spans[0].role == .marker)
    #expect(result.spans[1].kind == .text, "the terminator, not an empty info span")
    #expect(result.lineRecords[0].contentRange == 3..<3)
    #expect(result.lineRecords.map(\.element) == [.codeFence, .codeBlock, .codeFence])
  }

  @Test("Inside a fence nothing else is syntax")
  func fenceSuppressesOtherConstructs() {
    let result = Self.fullScan("```\n# not a heading\n```\n## yes a heading")
    #expect(result.lineRecords[1].element == .codeBlock)
    #expect(result.lineRecords[1].depth == 0)
    #expect(result.lineRecords[3].element == .heading)
    #expect(result.lineRecords[3].depth == 2)
    // Indentation inside a code block is significant, so it stays in the content
    // range — stripping it here would make the writer lossy. The terminator is still
    // excluded, which is the one thing `contentRange` always excludes.
    let indented = Self.fullScan("```\n    indented\n```")
    let code = indented.lineRecords[1]
    #expect(code.contentRange.lowerBound == code.range.lowerBound, "the indent is content here")
    #expect(code.contentRange.upperBound == code.range.upperBound - 1, "minus the terminator")
  }

  @Test("A fence closes only with its own character and only at its own length or longer")
  func fenceClosingRules() {
    // Tildes do not close a backtick fence.
    let mismatched = Self.fullScan("```\n~~~\nstill code")
    #expect(mismatched.lineRecords.map(\.element) == [.codeFence, .codeBlock, .codeBlock])

    // A shorter run does not close a longer fence; a longer one does close a shorter.
    let tooShort = Self.fullScan("````\n```\nstill code\n````")
    #expect(
      tooShort.lineRecords.map(\.element) == [.codeFence, .codeBlock, .codeBlock, .codeFence])

    let longer = Self.fullScan("```\n`````\nafter")
    #expect(longer.lineRecords.map(\.element) == [.codeFence, .codeFence, .paragraph])

    // A closing fence may carry nothing but whitespace after its run.
    let trailing = Self.fullScan("~~~\ncode\n~~~   \nafter")
    #expect(
      trailing.lineRecords.map(\.element) == [.codeFence, .codeBlock, .codeFence, .paragraph])

    let withText = Self.fullScan("~~~\ncode\n~~~ nope\nafter")
    #expect(
      withText.lineRecords.map(\.element) == [.codeFence, .codeBlock, .codeBlock, .codeBlock])

    // A backtick fence's info string may not contain a backtick — otherwise an inline
    // code span alone on a line would open a block.
    let inlineCode = Self.fullScan("``` `x` ```\ntext")
    #expect(inlineCode.lineRecords.map(\.element) == [.paragraph, .paragraph])
  }

  // MARK: - Total tiling

  @Test("Spans tile a heading-and-fence document exactly, with no hidden characters")
  func spansTileTheWholeDocument() {
    // The invariant that makes stale attributes structurally impossible: every UTF-16
    // code unit of the source belongs to exactly one span. Mixed terminators and an
    // astral-plane character are in the fixture because both are where a hand-written
    // scanner drops a code unit.
    let text = """
      # Title\r
      \r
      Some prose with a \u{1F600} in it.
      ```swift
      let x = 1
      ```
      ## Subtitle ##
      \ttabbed line
      ~~~
      still code
      """
    let result = Self.fullScan(text)

    let total = result.spans.reduce(0) { $0 + $1.range.count }
    #expect(total == text.utf16.count, "spans did not tile the document")
    #expect(result.dirtyRange == 0..<text.utf16.count)

    // Tiling means contiguous and ordered, not merely summing to the right number.
    var cursor = 0
    for span in result.spans {
      #expect(span.range.lowerBound == cursor, "gap or overlap at \(cursor)")
      #expect(!span.range.isEmpty, "empty span at \(cursor)")
      cursor = span.range.upperBound
    }
    #expect(cursor == text.utf16.count)

    // Line records tile it too, and every content range sits inside its line.
    #expect(result.lineRecords.map(\.index) == Array(result.lines))
    var lineCursor = 0
    for record in result.lineRecords {
      #expect(record.range.lowerBound == lineCursor)
      #expect(record.contentRange.lowerBound >= record.range.lowerBound)
      #expect(record.contentRange.upperBound <= record.range.upperBound)
      lineCursor = record.range.upperBound
    }
    #expect(lineCursor == text.utf16.count)

    IncrementalScannerTests.expectInvariants(result, text: text, editedRange: nil, "markdown full")
  }

  // MARK: - Unterminated fences

  @Test("An unterminated fence scans to the last code unit of the document and returns")
  func unterminatedFenceScansToEndOfDocument() {
    // Totality: no `throws`, no `fatalError`, no `precondition`. The state simply stays
    // open, and the last line of the document is the last line of the block.
    let text = "intro\n```swift\n" + (0..<40).map { "line \($0)" }.joined(separator: "\n")
    let result = Self.fullScan(text)

    #expect(result.dirtyRange == 0..<text.utf16.count)
    #expect(result.spans.last?.range.upperBound == text.utf16.count, "did not reach the last unit")
    #expect(result.spans.reduce(0) { $0 + $1.range.count } == text.utf16.count)
    #expect(result.lineRecords.count == 42)
    #expect(result.lineRecords.dropFirst(2).allSatisfy { $0.element == .codeBlock })
    #expect(result.lineRecords.last?.range.upperBound == text.utf16.count)
    // The very last span of an unterminated block is code, not text.
    #expect(result.spans.last?.kind == .codeBlock)

    IncrementalScannerTests.expectInvariants(result, text: text, editedRange: nil, "unterminated")
  }

  // MARK: - Convergence: the in-fence flag is real state

  @Test("Opening a fence on line 1 of a 500-line document dirties it to the end")
  func openingAFenceDirtiesTheRestOfTheDocument() {
    // This is the assertion the whole "carry the flag in `LineState`" design exists to
    // make true. Opening a fence changes the state entering every following line, so
    // convergence never finds a line whose recomputed state matches what was recorded —
    // and the rescan window runs to EOF. A grammar that classified lines by their own
    // text alone would converge after one line and repaint nothing below it.
    let body = (0..<500).map { "line \($0)" }.joined(separator: "\n")
    let text = "intro\n" + body
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    scanner.fullScan(text)

    var units = Array(text.utf16)
    units.replaceSubrange(6..<6, with: Array("```\n".utf16))
    let edited = String(decoding: units, as: UTF16.self)

    let result = scanner.incrementalScan(TextEdit(range: 6..<6, replacementLength: 4), in: edited)

    #expect(result.dirtyRange.upperBound == edited.utf16.count, "did not reach end of document")
    #expect(result.lines.upperBound == 502)
    #expect(result.lineRecords.last?.element == .codeBlock)
    #expect(result.spans.last?.kind == .codeBlock)

    // And it agrees with a full scan of the same text, which is what makes the claim
    // "dirtied to the end" mean "correctly dirtied to the end".
    var fresh = IncrementalScanner(grammar: MarkdownGrammar())
    fresh.fullScan(edited)
    #expect(scanner.startStates == fresh.startStates)

    IncrementalScannerTests.expectInvariants(
      result, text: edited, editedRange: 6..<10, "fence opened at line 1")
  }

  @Test("A one-character edit outside any fence rescans a handful of lines, not the document")
  func ordinaryEditsStayLocal() {
    // The other half of the contract. If every edit dirtied the document the fence test
    // above would pass for the wrong reason.
    let text = (0..<500).map { "line \($0)" }.joined(separator: "\n")
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    scanner.fullScan(text)

    let offset = text.utf16.count / 2
    var units = Array(text.utf16)
    units.replaceSubrange(offset..<offset, with: Array("z".utf16))
    let edited = String(decoding: units, as: UTF16.self)
    let result = scanner.incrementalScan(
      TextEdit(range: offset..<offset, replacementLength: 1), in: edited)

    #expect(result.lines.count <= 3, "rescanned \(result.lines.count) lines for one character")
    #expect(result.lines.upperBound < 500)
  }

  @Test("Editing an info string reclassifies the block below without breaking convergence")
  func editingTheInfoStringConverges() {
    let text = "```\ncode\n```\nafter"
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    scanner.fullScan(text)

    // Type `swift` after the opening fence.
    var units = Array(text.utf16)
    units.replaceSubrange(3..<3, with: Array("swift".utf16))
    let edited = String(decoding: units, as: UTF16.self)
    let result = scanner.incrementalScan(TextEdit(range: 3..<3, replacementLength: 5), in: edited)

    let infoStart = Self.offset(of: "swift", in: edited)
    #expect(infoStart == 3)
    #expect(result.spans.contains { $0.kind == .codeInfoString && $0.range == 3..<8 })

    var fresh = IncrementalScanner(grammar: MarkdownGrammar())
    let full = fresh.fullScan(edited)
    #expect(scanner.startStates == fresh.startStates)
    #expect(
      result.lineRecords == full.lineRecords.filter { result.lines.contains($0.index) })
  }

  @Test("A sequence of edits over headings and fences tracks a full scan throughout")
  func editSequenceTracksFullScan() {
    // Drift only shows up when one scanner is carried across many edits, which is how a
    // live editor uses one. Fixed script, no randomness — the seeded generator is
    // Sortie 6's, and an unseeded one is nobody's.
    let script: [(Range<Int>, String)] = [
      (0..<0, "# Title\n"),
      (8..<8, "prose\n"),
      (14..<14, "```swift\n"),
      (23..<23, "let x = 1\n"),
      (33..<33, "```\n"),
      (0..<2, "### "),  // `# ` becomes `### ` — the level changes under everything
      (16..<16, "\n"),  // split the prose line
      (0..<4, ""),  // delete the heading marker entirely
    ]

    var text = ""
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    scanner.fullScan(text)

    for (range, replacement) in script {
      var units = Array(text.utf16)
      units.replaceSubrange(range, with: Array(replacement.utf16))
      let next = String(decoding: units, as: UTF16.self)

      let result = scanner.incrementalScan(
        TextEdit(range: range, replacementLength: replacement.utf16.count), in: next)
      IncrementalScannerTests.expectInvariants(
        result, text: next,
        editedRange: range.lowerBound..<(range.lowerBound + replacement.utf16.count),
        "markdown sequence at \(next.debugDescription)")

      var fresh = IncrementalScanner(grammar: MarkdownGrammar())
      let full = fresh.fullScan(next)
      #expect(scanner.startStates == fresh.startStates, "diverged at \(next.debugDescription)")
      #expect(
        result.lineRecords == full.lineRecords.filter { result.lines.contains($0.index) },
        "records diverged at \(next.debugDescription)")
      text = next
    }
  }

  // MARK: - Degenerate input

  @Test(
    "Degenerate documents scan without failing",
    arguments: [
      "", "\n", "#", "# ", "```", "~", "~~", "~~~", "\r\n\r\n", "   ", "\t\t",
    ])
  func degenerateDocuments(text: String) {
    let result = Self.fullScan(text)
    #expect(result.spans.reduce(0) { $0 + $1.range.count } == text.utf16.count)
    IncrementalScannerTests.expectInvariants(result, text: text, editedRange: nil, "degenerate")
  }
}
