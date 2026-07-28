import Testing

@testable import EscriboCore

/// Fountain inside Markdown: a fence tagged `fountain`, scanned with the Fountain grammar,
/// in **outer-document** coordinates.
///
/// ## Every expectation here was written out by hand
///
/// None of the expected values below came from running the scanner and pasting the output.
/// That is the only property that makes a test able to catch a grammar that loses state, and
/// it is the property `ScanGateTests`'s seeded gate structurally cannot have — both sides of
/// that comparison run the same grammar, so a nested state that carries too little is wrong
/// identically on both sides and the gate smiles. A Fountain-in-Markdown document is in the
/// gate corpus because convergence *across the boundary* is worth checking; it is these
/// tests, not that one, that say the nesting is right.
///
/// ## The one defect class this file exists to catch
///
/// ``LineState/openConstruct`` is a single scalar shared by two grammars. Inside a
/// ```` ```fountain ```` fence two constructs are open **at once** — the Markdown fence and,
/// independently, a Fountain note or boneyard — and one scalar cannot say both. The state is
/// therefore two fields: ``LineState/openConstruct`` for the outer construct and
/// ``LineState/nestedFountain`` for the whole inner one. ``fenceAndBoneyardAreOpenAtOnce``
/// below is the assertion that a one-field encoding cannot satisfy: it demands two different
/// non-zero patterns over the same eleven lines.
@Suite("Fountain inside Markdown — the nested scan, its coordinates, and its state")
struct FountainInMarkdownTests {

  /// The tag meaning "a `fountain` fence is open", named once so the tables below read.
  static let fence = MarkdownGrammar.fountainFenceTag

  /// The tag meaning "a Fountain boneyard is open", likewise.
  static let boneyard = FountainGrammar.boneyardTag

  // MARK: - Coordinates

  /// Every span inside the fence indexes the **outer** document.
  ///
  /// The exit criterion this test is written against is not "the ranges look plausible" but
  /// "the offsets index correctly into the outer document string", so the assertion slices
  /// each span out of that string and compares the text. A nested scanner handed a substring
  /// — or one that laid its spans out from zero and expected the caller to shift them —
  /// produces ranges near the top of the document, none of which fall inside the fence at
  /// all, and the filtered list comes back empty.
  ///
  /// The document, with every offset written out:
  ///
  /// ```text
  ///  0  intro\n          0..<6     content 0..<5
  ///  6  ```fountain\n    6..<18    content 6..<17
  /// 18  BOB\n           18..<22    content 18..<21
  /// 22  Hi there.\n     22..<32    content 22..<31
  /// 32  ```\n           32..<36    content 32..<35
  /// 36  outro           36..<41    content 36..<41
  /// ```
  @Test("Every span inside a `fountain` fence indexes the outer document string")
  func nestedSpansAreInOuterDocumentCoordinates() {
    let text = "intro\n```fountain\nBOB\nHi there.\n```\noutro"
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    let result = scanner.fullScan(text)
    ScanInvariants.check(result, text: text, editedRange: nil, "fountain fence coordinates")

    // The whole document's classification, written out. The two lines between the fences
    // are a screenplay; everything else is Markdown.
    #expect(
      result.lineRecords.map(\.element) == [
        .paragraph, .codeFence, .character, .dialogue, .codeFence, .paragraph,
      ])

    // The fence's info string is its own span, because reading it is what dispatches the
    // block. Written out: `` ``` `` is 6..<9 and `fountain` is 9..<17.
    #expect(result.spans.contains(EscriboSpan(range: 6..<9, kind: .codeBlock, role: .marker)))
    #expect(result.spans.contains(EscriboSpan(range: 9..<17, kind: .codeInfoString)))

    // The body of the fence — lines 2 and 3 — is 18..<32. Every span the scan produced there,
    // with the text each one must cover when it is used to index `text`.
    let body = result.spans.filter {
      $0.range.lowerBound >= 18 && $0.range.upperBound <= 32
    }
    let expected: [(range: Range<Int>, kind: SpanKind, role: SpanRole, covers: String)] = [
      (18..<21, .character, .content, "BOB"),
      (21..<22, .text, .content, "\n"),
      (22..<31, .dialogue, .content, "Hi there."),
      (31..<32, .text, .content, "\n"),
    ]

    #expect(body.count == expected.count, "spans inside the fence body: \(body)")
    let units = Array(text.utf16)
    for (offset, want) in expected.enumerated() where offset < body.count {
      let got = body[offset]
      #expect(got.range == want.range, "span \(offset)")
      #expect(got.kind == want.kind, "span \(offset)")
      #expect(got.role == want.role, "span \(offset)")
      // The point of the whole test: the range, used against the **outer** document, names
      // the text it claims to name.
      #expect(
        String(decoding: units[got.range], as: UTF16.self) == want.covers,
        "span \(offset) at \(got.range) does not cover \(want.covers.debugDescription)")
    }
  }

  /// The fenced body scans exactly as the same text scans on its own.
  ///
  /// This is the offset property from the other side, and it is the one that would fail if
  /// the guest were handed a substring: shifting every span of a standalone scan by the
  /// fence's base offset must reproduce, span for span, what the nested scan emitted in
  /// place. It also pins the closing fence's treatment — the host's ```` ``` ```` is not part
  /// of the guest's document, so the last line of the block sees no following line, exactly
  /// as the last line of a standalone screenplay does.
  @Test("A fenced screenplay scans identically to the same text standalone, shifted")
  func nestedScanEqualsStandaloneScanShifted() {
    let body = "INT. HOUSE - DAY\n\nBOB\nHello there.\n"
    let opener = "```fountain\n"
    let base = opener.utf16.count
    let nested = opener + body + "```"

    var standaloneScanner = IncrementalScanner(grammar: FountainGrammar())
    let standalone = standaloneScanner.fullScan(body)
    ScanInvariants.check(standalone, text: body, editedRange: nil, "standalone screenplay")

    var nestedScanner = IncrementalScanner(grammar: MarkdownGrammar())
    let hosted = nestedScanner.fullScan(nested)
    ScanInvariants.check(hosted, text: nested, editedRange: nil, "hosted screenplay")

    let shifted = standalone.spans.map {
      EscriboSpan(
        range: ($0.range.lowerBound + base)..<($0.range.upperBound + base),
        kind: $0.kind, style: $0.style, role: $0.role)
    }
    let inFence = hosted.spans.filter {
      $0.range.lowerBound >= base && $0.range.upperBound <= base + body.utf16.count
    }
    ScanInvariants.expectSameElements(inFence, shifted, "nested spans", "shifted standalone scan")

    // And the classifications, written out rather than compared to each other, so this
    // cannot pass by both sides being wrong in the same way.
    #expect(
      hosted.lineRecords.map(\.element) == [
        .codeFence, .sceneHeading, .blank, .character, .dialogue, .codeFence,
      ])
  }

  // MARK: - Dispatch

  /// The info string decides the grammar, and nothing else does.
  ///
  /// The same six lines of body text are scanned twice: once under ```` ```fountain ````
  /// and once under ```` ```swift ````. If the two produce the same classification, the
  /// dispatch is not happening; if the `swift` one produces Fountain elements, the dispatch
  /// is happening to every fence. Both halves are needed and neither alone is a test.
  @Test("A `fountain` info string dispatches to Fountain; any other fence stays code")
  func infoStringDecidesTheGrammar() {
    let body = "INT. HOUSE - DAY\n\n# A section\n\nBOB\nHello.\n```\ntail"

    var fountainScanner = IncrementalScanner(grammar: MarkdownGrammar())
    let asFountain = fountainScanner.fullScan("```fountain\n" + body)
    ScanInvariants.check(
      asFountain, text: "```fountain\n" + body, editedRange: nil, "fountain fence")
    #expect(
      asFountain.lineRecords.map(\.element) == [
        .codeFence, .sceneHeading, .blank, .section, .blank, .character, .dialogue, .codeFence,
        .paragraph,
      ])
    // The Fountain section carries its level in `depth`, which a code block never would.
    #expect(asFountain.lineRecords[3].depth == 1)

    var swiftScanner = IncrementalScanner(grammar: MarkdownGrammar())
    let asCode = swiftScanner.fullScan("```swift\n" + body)
    ScanInvariants.check(asCode, text: "```swift\n" + body, editedRange: nil, "swift fence")
    #expect(
      asCode.lineRecords.map(\.element) == [
        .codeFence, .codeBlock, .codeBlock, .codeBlock, .codeBlock, .codeBlock, .codeBlock,
        .codeFence, .paragraph,
      ])
  }

  /// The info string is matched on its **first word**, ASCII-case-insensitively.
  ///
  /// `fountain` is how anyone writes it, `Fountain` is how a title-cased editor writes it,
  /// and `fountain title=cold-open` is CommonMark's own shape — a language followed by
  /// whatever the renderer wants. `fountainesque` is a different language and must not
  /// dispatch, which is what makes this a rule rather than a prefix check.
  @Test(
    "The info string's first word names the grammar, folded for ASCII case",
    arguments: [
      ("fountain", true),
      ("Fountain", true),
      ("FOUNTAIN", true),
      ("fountain title=cold-open", true),
      ("fountainesque", false),
      ("fount", false),
      ("swift", false),
      ("", false),
    ])
  func infoStringMatching(info: String, dispatches: Bool) {
    let text = "```\(info)\nINT. HOUSE - DAY\n```"
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    let result = scanner.fullScan(text)
    ScanInvariants.check(result, text: text, editedRange: nil, "info string \(info.debugDescription)")
    #expect(
      result.lineRecords[1].element == (dispatches ? .sceneHeading : .codeBlock),
      "info string \(info.debugDescription)")
  }

  // MARK: - Unterminated

  /// An unterminated `fountain` fence scans to the end of the document, as Fountain.
  ///
  /// Two failure modes are ruled out here and they are different failures. Falling back to
  /// Markdown would classify every line as ``ElementKind/codeBlock``; failing would mean an
  /// error path, and the scan path has none. What must happen is neither: the state stays
  /// open, the guest keeps scanning, and the last line of the document is the last line of
  /// the screenplay.
  @Test("An unterminated `fountain` fence produces Fountain spans to the end of the document")
  func unterminatedFountainFenceRunsToEndOfDocument() {
    let text = "```fountain\nINT. HOUSE - DAY\n\n# A section\n\nBOB\nHello.\n- not a list"
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    let result = scanner.fullScan(text)
    ScanInvariants.check(result, text: text, editedRange: nil, "unterminated fountain fence")

    // Written out. Note the last line: `- not a list` is a Markdown list item and a line of
    // speech, and inside an open dialogue block it is speech.
    #expect(
      result.lineRecords.map(\.element) == [
        .codeFence, .sceneHeading, .blank, .section, .blank, .character, .dialogue, .dialogue,
      ])
    #expect(
      result.lineRecords.dropFirst().allSatisfy { $0.element != .codeBlock },
      "an unterminated fountain fence must not fall back to Markdown")

    // The state never closes, and it stays the *fountain* fence tag rather than degrading to
    // the ordinary one — degrading is exactly how "falls back to Markdown" would look.
    #expect(
      result.lineRecords.dropFirst().allSatisfy { $0.startState.openConstruct == Self.fence })

    // And the spans are Fountain's, not `.codeBlock`. Written out for the last line.
    #expect(result.spans.contains { $0.kind == .sceneHeading })
    #expect(result.spans.contains { $0.kind == .section })
    #expect(result.spans.contains { $0.kind == .character })
    let last = result.lineRecords[7]
    #expect(
      result.spans.contains(EscriboSpan(range: last.range, kind: .dialogue)),
      "the final line of an unterminated fountain fence is dialogue, not code")
  }

  // MARK: - DL-112: two constructs open at once

  /// **The two-field assertion.** A Markdown fence and a Fountain boneyard are open on the
  /// same lines, and the state says so about both.
  ///
  /// This is the test a single-scalar state cannot pass, and the reason is arithmetic rather
  /// than stylistic: the two tables below are different non-zero patterns over the same
  /// eleven lines. ``LineState/openConstruct`` is the fence tag on lines 1 through 9;
  /// ``LineState/nestedFountain``'s is the boneyard tag on lines 4 and 5 and zero everywhere
  /// else. One scalar can hold one of those two answers per line, never both, so any
  /// implementation that collapses the fields fails one table or the other. Collapsing them
  /// and watching this go red is the falsification probe DL-112 asks for.
  ///
  /// The document, written out:
  ///
  /// ```text
  ///  0  ```fountain           outside the fence, opens it
  ///  1  Bob waits.            action
  ///  2  (blank)
  ///  3  /* struck out         opens the boneyard
  ///  4  INT. NOWHERE - NIGHT  inside the boneyard — a slug line that is not one
  ///  5  */                    closes it
  ///  6  (blank)
  ///  7  BOB                   a cue, because line 8 is non-blank
  ///  8  Hello.                speech
  ///  9  ```                   closes the fence
  /// 10  tail                  Markdown again
  /// ```
  @Test("A Markdown fence and a Fountain boneyard are open at the same time")
  func fenceAndBoneyardAreOpenAtOnce() {
    let text =
      "```fountain\nBob waits.\n\n/* struck out\nINT. NOWHERE - NIGHT\n*/\n\nBOB\nHello.\n```\ntail"
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    let result = scanner.fullScan(text)
    ScanInvariants.check(result, text: text, editedRange: nil, "fence hosting a boneyard")

    #expect(
      result.lineRecords.map(\.element) == [
        .codeFence, .action, .blank, .boneyard, .boneyard, .boneyard, .blank, .character,
        .dialogue, .codeFence, .paragraph,
      ])

    // The **outer** construct: a fence is open on lines 1 through 9.
    let f = Self.fence
    #expect(
      result.lineRecords.map(\.startState.openConstruct) == [0, f, f, f, f, f, f, f, f, f, 0],
      "the outer fence tag")

    // The **inner** construct: a boneyard is open on lines 4 and 5. A different pattern over
    // the same lines, which is why it cannot share a field with the one above.
    let b = Self.boneyard
    #expect(
      result.lineRecords.map(\.startState.nestedFountain.openConstruct)
        == [0, 0, 0, 0, b, b, 0, 0, 0, 0, 0],
      "the inner boneyard tag")

    // The rest of the nested state is carried too, and each of these is a field a nested
    // state could plausibly forget. A forgotten dialogue bit turns line 8 into action; a
    // forgotten block-boundary bit turns line 7 into action; a forgotten title-page region
    // reopens a title page in the middle of the screenplay.
    #expect(
      result.lineRecords.map(\.startState.nestedFountain.inDialogueBlock)
        == [false, false, false, false, false, false, false, false, true, true, false])
    #expect(
      result.lineRecords.map(\.startState.nestedFountain.followsNonBlankLine)
        == [false, false, true, false, true, true, true, false, true, true, false])
    #expect(
      result.lineRecords[1].startState.nestedFountain.titlePage == .documentStart,
      "the fence's first line is where a nested title page may begin")
    #expect(
      result.lineRecords.dropFirst(2).prefix(8).allSatisfy {
        $0.startState.nestedFountain.titlePage == .closed
      })

    // The nested state is gone once the fence is: it must not leak into the Markdown that
    // follows, where it would be a difference the convergence engine compares forever.
    #expect(result.lineRecords[10].startState.nestedFountain == NestedFountainState())
  }

  /// A nested title page opens on the fence's first line and nowhere else.
  ///
  /// The rule a standalone screenplay gets from "line zero" has to be got from "the first
  /// line of the block" here, and ``NestedFountainState/titlePage`` defaulting to
  /// ``TitlePageRegion/documentStart`` is what supplies it. The second half of the document
  /// is the half that matters: `Draft date:` after the title page has closed is a line of a
  /// screenplay, not a second title page.
  @Test("A title page inside a fence begins on the block's first line and only there")
  func nestedTitlePageOpensOnlyOnTheBlocksFirstLine() {
    let text =
      "para\n```fountain\nTitle: THE THING\nAuthor: Nobody\n\nINT. HOUSE - DAY\n\n"
      + "Draft date: tomorrow\n```"
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    let result = scanner.fullScan(text)
    ScanInvariants.check(result, text: text, editedRange: nil, "nested title page")

    #expect(
      result.lineRecords.map(\.element) == [
        .paragraph, .codeFence, .titlePageKey, .titlePageKey, .blank, .sceneHeading, .blank,
        .action, .codeFence,
      ])
  }

  // MARK: - Convergence across the boundary

  /// Editing a dialogue line inside a fenced Fountain block yields
  /// `incrementalScan == fullScan`.
  ///
  /// Four edits, each on its own scanner, and each compared two ways — the repainted window
  /// against the matching slice of a full scan ("is what you repainted right?") and the
  /// accumulated document against the whole full scan ("did you repaint everything that
  /// changed?"). The second is the one that fails when the nested state converges early: a
  /// state that says only "we are in a fence" is identical on every line of the block, so
  /// the engine stops one line into it and leaves the rest of the screenplay painted as it
  /// was.
  ///
  /// The document, with every line's extent written out:
  ///
  /// ```text
  ///  0  intro\n           0..<6
  ///  1  ```fountain\n     6..<18
  ///  2  \n               18..<19
  ///  3  BOB\n            19..<23
  ///  4  Hi there.\n      23..<33
  ///  5  More speech.\n   33..<46
  ///  6  ```\n            46..<50
  ///  7  tail             50..<54
  /// ```
  @Test(
    "Editing inside a fenced Fountain block converges",
    arguments: [
      // Typing into a line of speech — the case the exit criterion names.
      (30, 30, "there, "),
      // Deleting the cue's last letter. The cue survives as `BO`, and the edit is on the
      // line *above* the one whose classification it could change.
      (21, 22, ""),
      // Opening a boneyard inside the block: inner state that propagates to the fence's end.
      (23, 23, "/* "),
      // Blanking the line under the cue, which demotes the cue to action from below.
      (23, 32, ""),
      // Deleting the closing fence, which turns the tail of the document into screenplay.
      (46, 50, ""),
    ])
  func editingInsideAFencedBlockConverges(lower: Int, upper: Int, replacement: String) {
    let text = "intro\n```fountain\n\nBOB\nHi there.\nMore speech.\n```\ntail"
    let edited = ScanInvariants.splice(text, lower..<upper, replacement)
    let note = "edit \(lower..<upper) -> \(replacement.debugDescription) in \(text.debugDescription)"

    var incremental = IncrementalScanner(grammar: MarkdownGrammar())
    let first = incremental.fullScan(text)
    ScanInvariants.check(first, text: text, editedRange: nil, "base — \(note)")
    var painted = ScanInvariants.PaintedDocument(first)

    let result = incremental.incrementalScan(
      TextEdit(range: lower..<upper, replacementLength: replacement.utf16.count), in: edited)
    let editedRange = lower..<(lower + replacement.utf16.count)
    ScanInvariants.check(result, text: edited, editedRange: editedRange, note)

    var fresh = IncrementalScanner(grammar: MarkdownGrammar())
    let full = fresh.fullScan(edited)
    ScanInvariants.check(full, text: edited, editedRange: nil, "full — \(note)")

    ScanInvariants.expectSameElements(
      result.lineRecords, full.lineRecords.filter { result.lines.contains($0.index) },
      "lineRecords", note)
    ScanInvariants.expectSameElements(
      result.spans,
      full.spans.filter {
        $0.range.lowerBound >= result.dirtyRange.lowerBound
          && $0.range.upperBound <= result.dirtyRange.upperBound
      },
      "spans", note)
    ScanInvariants.expectSameElements(
      incremental.startStates, fresh.startStates, "startStates", note)

    painted.apply(result, newLineCount: ScanInvariants.lineCount(of: edited))
    ScanInvariants.expectSameElements(
      painted.lines, ScanInvariants.paintedLines(of: full), "painted document", note)
  }

  /// The host grammar declares the lookahead the **guest** needs.
  ///
  /// The engine sizes the ``LineWindow`` from the grammar it was instantiated with, so
  /// `MarkdownGrammar` declaring zero would hand a nested Fountain scan a window with
  /// nothing in it and no natural character cue would ever be recognized inside a fence —
  /// a wrong answer produced by a number in a different file from the rule it broke.
  @Test("Markdown declares the one line of lookahead its guest grammar needs")
  func markdownDeclaresTheGuestsLookahead() {
    #expect(MarkdownGrammar().lookahead == 1)
    #expect(MarkdownGrammar().backwardExtent == 1)
    #expect(FountainGrammar().lookahead == 1)
  }

  /// The closing fence is the host's, not the guest's — so the block's last line sees no
  /// line after it.
  ///
  /// `BOB` immediately above a closing fence is an ALL-CAPS line with nothing following it
  /// *in the screenplay*, and Fountain's rule makes that action rather than a cue: nobody is
  /// speaking. A nested scan that let the guest see the ```` ``` ```` would promote it, and
  /// the same three letters would mean different things depending on how the block ended.
  @Test("A cue candidate against the closing fence is action, as it is at end of document")
  func theClosingFenceIsNotVisibleToTheGuest() {
    let hosted = "```fountain\nBOB\n```\ntail"
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    let result = scanner.fullScan(hosted)
    ScanInvariants.check(result, text: hosted, editedRange: nil, "cue against a closing fence")
    #expect(
      result.lineRecords.map(\.element) == [.codeFence, .action, .codeFence, .paragraph])

    // The same three letters with a line of speech under them, inside the same fence.
    let speaking = "```fountain\nBOB\nHello.\n```\ntail"
    var second = IncrementalScanner(grammar: MarkdownGrammar())
    let spoken = second.fullScan(speaking)
    ScanInvariants.check(spoken, text: speaking, editedRange: nil, "cue with speech under it")
    #expect(
      spoken.lineRecords.map(\.element) == [
        .codeFence, .character, .dialogue, .codeFence, .paragraph,
      ])
  }

  // MARK: - One level, no recursion

  /// Fountain hosts nothing. A fence inside a `fountain` fence is screenplay text.
  ///
  /// Nesting stops at one level because Fountain has no fence syntax to nest with, and that
  /// is what lets ``LineState/nestedFountain`` be a fixed-size value rather than a boxed
  /// state. The inner ```` ```swift ```` below is therefore not a block opening: it is a run
  /// of backticks in a screenplay, and — because it matches the enclosing fence's character
  /// and length — the *host* reads it as the closing fence, which is CommonMark's own rule
  /// and the reason a nested screenplay wanting literal backticks uses a longer fence.
  @Test("Nesting is one level: a fence inside a fountain fence is not a second host")
  func nestingStopsAtOneLevel() {
    let text = "````fountain\nBob waits.\n```swift\nstill inside\n````\ntail"
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())
    let result = scanner.fullScan(text)
    ScanInvariants.check(result, text: text, editedRange: nil, "no second level of nesting")

    // The four-backtick fence is not closed by three, so `` ```swift `` is a line of the
    // screenplay — action — and the nested state never becomes a second fence.
    #expect(
      result.lineRecords.map(\.element) == [
        .codeFence, .action, .action, .action, .codeFence, .paragraph,
      ])
    #expect(
      result.lineRecords.dropFirst().prefix(4).allSatisfy {
        $0.startState.openConstruct == Self.fence
      })
  }
}
