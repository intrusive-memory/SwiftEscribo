import Testing

@testable import EscriboCore

/// Fountain's three multi-line constructs: notes `[[ ]]`, boneyard `/* */`, and the title
/// page.
///
/// Every expectation here — every `ElementKind`, every span range, every extracted string
/// — was **written out by hand**. None of it was produced by running the grammar and
/// pasting the answer back, and that is the only property that makes any of it able to
/// fail.
///
/// This suite exists because `ScanGateTests`'s `incrementalScan == fullScan` property
/// *cannot* check any of it. Both sides of that comparison run the same grammar, so a
/// boneyard flag that is computed and then not carried agrees with itself perfectly and
/// the gate stays green — measured three separate ways on this very package, most
/// starkly by setting `FountainGrammar.lookahead` to zero and watching the gate hold at
/// 288/288 while 62 hand-written tests went red. Boneyard state is *pure* multi-line
/// state, which is precisely the defect class the gate is blindest to. Do not delete an
/// expectation here on the grounds that the gate covers it.
@Suite("Fountain notes, boneyard, and the title page")
struct FountainRegionTests {

  // MARK: - Helpers

  /// The text `range` covers, in UTF-16 code units — how a writer would read a span back
  /// off the source.
  static func text(_ range: Range<Int>, of source: String) -> String {
    let units = Array(source.utf16)
    return String(decoding: units[range], as: UTF16.self)
  }

  /// Every span of `kind` and `role`, in document order, as the text it covers.
  static func texts(
    _ kind: SpanKind, role: SpanRole = .content, in result: ScanResult, of source: String
  ) -> [String] {
    result.spans
      .filter { $0.kind == kind && $0.role == role }
      .map { Self.text($0.range, of: source) }
  }

  // MARK: - Notes

  @Test("A line that is nothing but `[[a note]]` is a note, brackets excluded from content")
  func wholeLineNoteIsANote() {
    let source = "[[a note]]"
    let result = FountainGrammarTests.fullScan(source)
    let record = result.lineRecords[0]

    #expect(record.element == .note)
    // Written out: `[[` is 0..<2, `a note` is 2..<8, `]]` is 8..<10.
    #expect(record.range == 0..<10)
    #expect(record.contentRange == 2..<8)
    #expect(Self.text(record.contentRange, of: source) == "a note")

    #expect(result.spans.count == 3)
    #expect(result.spans[0].range == 0..<2)
    #expect(result.spans[0].kind == .note)
    #expect(result.spans[0].role == .marker)
    #expect(result.spans[1].range == 2..<8)
    #expect(result.spans[1].kind == .note)
    #expect(result.spans[1].role == .content)
    #expect(result.spans[2].range == 8..<10)
    #expect(result.spans[2].kind == .note)
    #expect(result.spans[2].role == .marker)
  }

  @Test("A note inside a line leaves the line's own classification alone")
  func inlineNoteDoesNotChangeTheLine() {
    // `Bob waits [[to Jane]] here.` — the words outside the note are what the line is,
    // and they are action.
    let source = "Bob waits [[to Jane]] here."
    let result = FountainGrammarTests.fullScan(source)

    #expect(result.lineRecords[0].element == .action)
    // Hand-counted: `[[` at 10..<12, `to Jane` at 12..<19, `]]` at 19..<21.
    #expect(Self.texts(.note, in: result, of: source) == ["to Jane"])
    #expect(Self.texts(.note, role: .marker, in: result, of: source) == ["[[", "]]"])

    // The action spans are cut around the note rather than swallowing it. This is the
    // assertion that fails if the grammar appends note spans instead of subtracting: the
    // tiler resolves an overlap in favour of the earlier span, so a whole-line action span
    // would eat the note entirely and this list would be `["Bob waits [[to Jane]] here."]`.
    #expect(Self.texts(.action, in: result, of: source) == ["Bob waits ", " here."])
  }

  @Test("A note spans lines, and the lines it fully covers are notes")
  func notesSpanLines() {
    let source = "Bob waits [[a note\nthat goes on\nand ends]] here."
    let result = FountainGrammarTests.fullScan(source)

    // Written out: line 0 opens the note and has action text before it; line 1 is entirely
    // inside it; line 2 closes it and has action text after it.
    #expect(result.lineRecords.map(\.element) == [.action, .note, .action])

    // The state is what carries the note across the line break, and this is the assertion
    // that goes red if it is computed and not carried.
    #expect(result.lineRecords[0].startState.openConstruct == 0)
    #expect(result.lineRecords[1].startState.openConstruct == FountainGrammar.noteTag)
    #expect(result.lineRecords[2].startState.openConstruct == FountainGrammar.noteTag)

    #expect(Self.texts(.note, in: result, of: source) == ["a note", "that goes on", "and ends"])
    #expect(Self.texts(.note, role: .marker, in: result, of: source) == ["[[", "]]"])
    #expect(Self.texts(.action, in: result, of: source) == ["Bob waits ", " here."])
  }

  @Test("An unterminated `[[` runs to the end of the document without failing")
  func unterminatedNoteRunsToEndOfDocument() {
    let source = "Bob waits.\n\n[[a note that never closes\nINT. HOUSE - DAY\nBOB"
    let result = FountainGrammarTests.fullScan(source)

    #expect(result.lineRecords.map(\.element) == [.action, .blank, .note, .note, .note])
    #expect(result.lineRecords[4].startState.openConstruct == FountainGrammar.noteTag)
    // Scanned to the last code unit: the spans tile the whole document.
    #expect(result.spans.last?.range.upperBound == source.utf16.count)
  }

  @Test("Notes do not nest — the first `]]` closes the note")
  func notesDoNotNest() {
    // Deviation 7. `[[a [[b]]` is the note; ` c]]` is ordinary text after it, which is why
    // this line is action rather than a note.
    let source = "[[a [[b]] c]]"
    let result = FountainGrammarTests.fullScan(source)

    #expect(result.lineRecords[0].element == .action)
    #expect(Self.texts(.note, in: result, of: source) == ["a [[b"])
    #expect(Self.texts(.note, role: .marker, in: result, of: source) == ["[[", "]]"])
  }

  @Test("A degenerate `[[]]` is an empty note, and `[[` alone opens one")
  func degenerateNotes() {
    let empty = FountainGrammarTests.fullScan("[[]]")
    #expect(empty.lineRecords[0].element == .note)
    #expect(empty.lineRecords[0].contentRange == 2..<2)

    let opener = FountainGrammarTests.fullScan("[[")
    #expect(opener.lineRecords[0].element == .note)
    #expect(opener.lineRecords[0].contentRange == 2..<2)
  }

  // MARK: - Notes and the dialogue block

  @Test("A `[[note]]` inside dialogue does not terminate the dialogue block")
  func wholeLineNoteInsideDialogueKeepsTheBlockOpen() {
    // The sortie's exit criterion, and it is capable of failing: a note has its own
    // `ElementKind`, so it reaches `withState`'s `switch` on its own and would fall into
    // the "everything else closes the block" branch unless it is named alongside
    // parenthetical, dialogue, and lyric. If it were, `Still speaking.` below would be
    // `.action`.
    let source = "BOB\nHello there.\n[[a note]]\nStill speaking."
    let result = FountainGrammarTests.fullScan(source)

    #expect(result.lineRecords.map(\.element) == [.character, .dialogue, .note, .dialogue])
    #expect(result.lineRecords[3].startState.inDialogueBlock)
  }

  @Test("An inline note inside a line of dialogue leaves it dialogue")
  func inlineNoteInsideDialogue() {
    let source = "BOB\nHello [[to Jane]] there.\nStill speaking."
    let result = FountainGrammarTests.fullScan(source)

    #expect(result.lineRecords.map(\.element) == [.character, .dialogue, .dialogue])
    #expect(Self.texts(.note, in: result, of: source) == ["to Jane"])
    #expect(
      Self.texts(.dialogue, in: result, of: source) == ["Hello ", " there.", "Still speaking."])
  }

  @Test("A multi-line note inside dialogue keeps every line of the block")
  func multiLineNoteInsideDialogue() {
    let source = "BOB\nHello.\n[[a note\nstill the note]]\nStill speaking."
    let result = FountainGrammarTests.fullScan(source)

    #expect(
      result.lineRecords.map(\.element) == [.character, .dialogue, .note, .note, .dialogue])
  }

  // MARK: - Boneyard

  @Test("A line that is nothing but `/* struck */` is boneyard")
  func wholeLineBoneyard() {
    let source = "/* struck */"
    let result = FountainGrammarTests.fullScan(source)

    #expect(result.lineRecords[0].element == .boneyard)
    // Written out: `/*` is 0..<2, ` struck ` is 2..<10, `*/` is 10..<12.
    #expect(result.lineRecords[0].contentRange == 2..<10)
    #expect(result.spans.map(\.range) == [0..<2, 2..<10, 10..<12])
    #expect(result.spans.map(\.kind) == [.boneyard, .boneyard, .boneyard])
    #expect(result.spans.map(\.role) == [.marker, .content, .marker])
  }

  @Test("A boneyard opening mid-line leaves that line's classification alone")
  func inlineBoneyardDoesNotChangeTheLine() {
    // Deviation 8: the text that decides what the line is sits outside the boneyard.
    let source = "Bob waits. /* cut this */ He leaves."
    let result = FountainGrammarTests.fullScan(source)

    #expect(result.lineRecords[0].element == .action)
    #expect(Self.texts(.boneyard, in: result, of: source) == [" cut this "])
    #expect(Self.texts(.action, in: result, of: source) == ["Bob waits. ", " He leaves."])
  }

  @Test("A boneyard carries across lines, blank lines included")
  func boneyardSpansLines() {
    // Every line between the delimiters is struck out — including a line that would be a
    // slug line anywhere else, and a blank line, which does **not** close the region
    // (deviation 9).
    let source = "/*\nINT. HOUSE - DAY\n\nBOB\nHello there.\n*/\nBob waits."
    let result = FountainGrammarTests.fullScan(source)

    #expect(
      result.lineRecords.map(\.element) == [
        .boneyard, .boneyard, .boneyard, .boneyard, .boneyard, .boneyard, .action,
      ])

    // Carried, not recomputed. Line 0 begins outside; lines 1 through 5 begin inside; the
    // line after `*/` begins outside again.
    #expect(
      result.lineRecords.map(\.startState.openConstruct) == [
        0, FountainGrammar.boneyardTag, FountainGrammar.boneyardTag, FountainGrammar.boneyardTag,
        FountainGrammar.boneyardTag, FountainGrammar.boneyardTag, 0,
      ])
  }

  @Test("An unterminated `/*` scans to the last code unit and returns normally")
  func unterminatedBoneyardScansToEndOfDocument() {
    // The sortie's exit criterion. REQUIREMENTS.md § Core API: the scan path has no error
    // path, so running to the end of the document is the specified behaviour rather than a
    // fallback. The document deliberately ends **without** a terminator.
    let source =
      "INT. HOUSE - DAY\n\nBob waits.\n\n/* everything below is struck\nINT. OTHER - DAY\nBOB\nHello"
    let result = FountainGrammarTests.fullScan(source)

    #expect(
      result.lineRecords.map(\.element) == [
        .sceneHeading, .blank, .action, .blank, .boneyard, .boneyard, .boneyard, .boneyard,
      ])
    #expect(result.lineRecords.last?.startState.openConstruct == FountainGrammar.boneyardTag)

    // "To the last code unit", stated as a range rather than as a feeling.
    #expect(result.spans.last?.range.upperBound == source.utf16.count)
    #expect(result.spans.reduce(0) { $0 + $1.range.count } == source.utf16.count)
    #expect(result.dirtyRange == 0..<source.utf16.count)
  }

  @Test("A boneyard does not terminate the dialogue block")
  func boneyardInsideDialogueKeepsTheBlockOpen() {
    let source = "BOB\nHello there.\n/* struck */\nStill speaking."
    let result = FountainGrammarTests.fullScan(source)

    #expect(result.lineRecords.map(\.element) == [.character, .dialogue, .boneyard, .dialogue])
    #expect(result.lineRecords[3].startState.inDialogueBlock)
  }

  // MARK: - One region at a time

  @Test("Inside a boneyard a `[[` is text, and inside a note a `/*` is text")
  func regionsDoNotNestInsideEachOther() {
    // Deviation 7, from both sides. Whichever opens first owns the line.
    let boneyardFirst = "/* a [[note]] inside */"
    let outerBoneyard = FountainGrammarTests.fullScan(boneyardFirst)
    #expect(outerBoneyard.lineRecords[0].element == .boneyard)
    #expect(Self.texts(.note, in: outerBoneyard, of: boneyardFirst).isEmpty)
    #expect(
      Self.texts(.boneyard, in: outerBoneyard, of: boneyardFirst) == [" a [[note]] inside "])

    let noteFirst = "[[a /* boneyard */ inside]]"
    let outerNote = FountainGrammarTests.fullScan(noteFirst)
    #expect(outerNote.lineRecords[0].element == .note)
    #expect(Self.texts(.boneyard, in: outerNote, of: noteFirst).isEmpty)
    #expect(Self.texts(.note, in: outerNote, of: noteFirst) == ["a /* boneyard */ inside"])
  }

  // MARK: - The title page

  @Test("Non-standard title-page keys survive a scan verbatim and in order")
  func nonStandardKeysArePreservedVerbatim() {
    // The sortie's exit criterion, and REQUIREMENTS.md § Fountain 2: `verbsCovered:` and
    // `Abstract:` are real keys in this org's documents. The assertion is byte-identical
    // key text — spelling and casing — in the document's own order.
    let source = """
      Title: The Thing
      Credit: Written by
      verbsCovered: run, jump, hide
      Abstract: A thing happens, and then another thing.
      Draft date: 26/07/2026

      INT. HOUSE - DAY
      """
    let result = FountainGrammarTests.fullScan(source)

    #expect(
      result.lineRecords.map(\.element) == [
        .titlePageKey, .titlePageKey, .titlePageKey, .titlePageKey, .titlePageKey, .blank,
        .sceneHeading,
      ])

    // Byte-identical, and in the order they were written. `verbsCovered` keeps its camel
    // case, `Abstract` keeps its capital, and `Draft date` keeps its space.
    #expect(
      Self.texts(.titlePageKey, in: result, of: source) == [
        "Title", "Credit", "verbsCovered", "Abstract", "Draft date",
      ])
    // No key is checked against a list, because there is no list — see the grammar.
    #expect(
      Self.texts(.titlePageValue, in: result, of: source) == [
        "The Thing", "Written by", "run, jump, hide",
        "A thing happens, and then another thing.", "26/07/2026",
      ])

    // And the record: the content range is the value, so a consumer reading metadata gets
    // the value without re-scanning, while the key stays exactly where the writer left it.
    #expect(Self.text(result.lineRecords[2].contentRange, of: source) == "run, jump, hide")
    // The key is recoverable from the record too: it runs from the line's start to the
    // colon, which is the difference between `range` and the key span.
    #expect(result.lineRecords[2].range.lowerBound == 36)
    #expect(Self.text(36..<48, of: source) == "verbsCovered")
  }

  @Test("A bare key takes its value from the indented lines under it")
  func bareKeyWithIndentedContinuations() {
    let source = """
      Title:
          _**BRICK & STEEL**_
          _**FULL RETALIATION**_
      Credit: Written by

      CUT TO:
      """
    let result = FountainGrammarTests.fullScan(source)

    #expect(
      result.lineRecords.map(\.element) == [
        .titlePageKey, .titlePageValue, .titlePageValue, .titlePageKey, .blank, .transition,
      ])
    #expect(Self.texts(.titlePageKey, in: result, of: source) == ["Title", "Credit"])
    #expect(
      Self.texts(.titlePageValue, in: result, of: source) == [
        "_**BRICK & STEEL**_", "_**FULL RETALIATION**_", "Written by",
      ])
    // A bare key's own content range is empty — the value is on the lines below it.
    #expect(result.lineRecords[0].contentRange.isEmpty)
    // The indent is the continuation line's one marker span, so it stays recoverable.
    #expect(
      result.spans.first { $0.kind == .titlePageValue && $0.role == .marker }?.range == 7..<11)
  }

  @Test("The title page ends at the first blank line, and the screenplay resumes")
  func titlePageEndsAtTheFirstBlankLine() {
    let source = "Title: A\n\nINT. HOUSE - DAY\n\nTitle: not a key any more\n"
    let result = FountainGrammarTests.fullScan(source)

    #expect(
      result.lineRecords.map(\.element) == [
        .titlePageKey, .blank, .sceneHeading, .blank, .action, .blank,
      ])
    #expect(Self.texts(.titlePageKey, in: result, of: source) == ["Title"])
  }

  @Test("A title page begins only on the first line of the document")
  func titlePageCannotBeginMidDocument() {
    // The state's third value is what holds this: `followsNonBlankLine` is false on line 0
    // *and* after every blank line, so a grammar keying off it would open a title page here.
    let source = "INT. HOUSE - DAY\n\nTitle: not a title page\n"
    let result = FountainGrammarTests.fullScan(source)

    #expect(result.lineRecords.map(\.element) == [.sceneHeading, .blank, .action, .blank])
    #expect(FountainRegionTests.texts(.titlePageKey, in: result, of: source).isEmpty)
  }

  @Test("A first line that merely ends in a colon is not a title page")
  func aTransitionOnLineOneIsNotATitlePage() {
    // Deviation 11. Without the corroboration rule, every one of these would be a title
    // page whose key is `CUT TO`.
    #expect(FountainGrammarTests.element("CUT TO:") == .transition)
    #expect(FountainGrammarTests.elements("CUT TO:\nBob waits.") == [.transition, .action])
    #expect(
      FountainGrammarTests.elements("CUT TO:\n\nINT. HOUSE - DAY") == [
        .transition, .blank, .sceneHeading,
      ])
  }

  @Test("A bare key is a title page when the line under it is another key")
  func bareKeyCorroboratedByASecondKey() {
    let source = "Title:\nCredit: Written by\n\nINT. HOUSE - DAY"
    let result = FountainGrammarTests.fullScan(source)
    #expect(
      result.lineRecords.map(\.element) == [
        .titlePageKey, .titlePageKey, .blank, .sceneHeading,
      ])
  }

  @Test("Inside the title page, no other Fountain element is recognized")
  func theTitlePageOwnsItsRegion() {
    // `INT. HOUSE - DAY` under a key is a continuation of that key's value, not a slug
    // line, and `BOB` is not a character cue. This is what makes the region "distinct".
    let source = "Title: A\nINT. HOUSE - DAY\nBOB\n\nINT. HOUSE - DAY"
    let result = FountainGrammarTests.fullScan(source)

    #expect(
      result.lineRecords.map(\.element) == [
        .titlePageKey, .titlePageValue, .titlePageValue, .blank, .sceneHeading,
      ])
  }

  // MARK: - The title page — empty values (DL-130)

  /// Grammar deviation 10a, stated as the two shapes Highland and a hand-editor produce.
  ///
  /// A lone tab and a lone space are both **empty values** for the key above them, and the
  /// keys below them are still title page. Every element here was written out by hand from
  /// the source string above it.
  @Test("A whitespace-only value line is an empty value, not the end of the title page")
  func whitespaceOnlyValueIsAnEmptyValue() {
    // Line 0 carries its value inline, so deviation 11's corroboration is satisfied without
    // depending on the whitespace-only lines below — this test is about the region's
    // interior, which is where the rule lives.
    let source = "Title: A\nEpisode:\n\t\nCredit:\n \nAuthor: STOVAK\n\nINT. HOUSE - DAY"
    let result = FountainGrammarTests.fullScan(source)

    #expect(
      result.lineRecords.map(\.element) == [
        .titlePageKey,  // Title: A
        .titlePageKey,  // Episode:
        .titlePageValue,  // \t   <- lone tab
        .titlePageKey,  // Credit:
        .titlePageValue,  // " "  <- lone space
        .titlePageKey,  // Author: STOVAK
        .blank,  // ""            <- genuinely empty: this is the terminator
        .sceneHeading,  // INT. HOUSE - DAY
      ])

    // The keys are all there, in order, and none was swallowed.
    #expect(
      Self.texts(.titlePageKey, in: result, of: source) == [
        "Title", "Episode", "Credit", "Author",
      ])
    // Only the two keys that were given values contribute value text. The tab and the
    // space contribute none — an empty value is empty.
    #expect(Self.texts(.titlePageValue, in: result, of: source) == ["A", "STOVAK"])

    // The empty values are still *records*, with empty content and the bytes they were
    // written with. Sortie 24's writer reads exactly this to tell an empty value from an
    // absent key.
    let tabLine = result.lineRecords[2]
    #expect(tabLine.element == .titlePageValue)
    #expect(tabLine.contentRange.isEmpty)
    #expect(Self.text(tabLine.range, of: source) == "\t\n")
    let spaceLine = result.lineRecords[4]
    #expect(spaceLine.element == .titlePageValue)
    #expect(spaceLine.contentRange.isEmpty)
    #expect(Self.text(spaceLine.range, of: source) == " \n")

    // And the whitespace is still spanned — the marker span every continuation line gets,
    // here covering the whole line because there is nothing else on it.
    #expect(
      Self.texts(.titlePageValue, role: .marker, in: result, of: source) == ["\t", " "])
  }

  /// The narrowness of the fix, asserted directly: only the *empty* line terminates.
  ///
  /// This is the assertion that would have to be deleted, not merely edited, to widen
  /// deviation 10a into "whitespace-only lines are never blank".
  @Test("A genuinely empty line still ends the title page, whitespace lines and all")
  func genuinelyEmptyLineStillTerminatesTheTitlePage() {
    // The document is deliberately built so that the *only* difference between the line
    // that terminates and the two that do not is whether it carries a space or a tab.
    let source = "Title: A\n\t\n \n\nBOB\nHello there.\n"
    let result = FountainGrammarTests.fullScan(source)

    #expect(
      result.lineRecords.map(\.element) == [
        .titlePageKey,  // Title: A
        .titlePageValue,  // \t
        .titlePageValue,  // " "
        .blank,  // ""      <- the terminator, and the only one
        .character,  // BOB — a cue, which it could only be outside the region
        .dialogue,  // Hello there.
        .blank,
      ])
    #expect(Self.texts(.titlePageKey, in: result, of: source) == ["Title"])
  }

  /// A whitespace-only line outside the title page is **still blank**, exactly as it was.
  ///
  /// The other half of the narrowness. A widened rule would change the dialogue-block
  /// boundary here — `BOB` under a whitespace-only line would stop being a cue — and would
  /// do the same to scene headings and every other rule that reads
  /// `followsNonBlankLine`. Nothing below the title page changed in Sortie 31, and this is
  /// what says so.
  @Test("Outside the title page a whitespace-only line is still blank")
  func whitespaceOnlyLineOutsideTheRegionIsStillBlank() {
    // No title page at all: line 0 is a slug line.
    let source = "INT. HOUSE - DAY\n\t \nBOB\nHello there.\n \nINT. YARD - DAY\n"
    let result = FountainGrammarTests.fullScan(source)

    #expect(
      result.lineRecords.map(\.element) == [
        .sceneHeading,  // INT. HOUSE - DAY
        .blank,  // "\t "        <- whitespace only, and blank
        .character,  // BOB      <- a cue, which needs a blank line above it
        .dialogue,  // Hello there.
        .blank,  // " "          <- whitespace only, and blank
        .sceneHeading,  // INT. YARD - DAY   <- needs a blank line above it too
        .blank,
      ])
  }

  /// An empty value is distinguishable from an absent key, in the line records alone.
  ///
  /// Three documents that a writer must be able to tell apart, and the property that tells
  /// them apart: whether a `titlePageValue` record exists under the key, and whether its
  /// content range is empty.
  @Test("An empty value, a present value, and an absent key are three different records")
  func emptyValueIsDistinguishableFromAnAbsentKey() {
    let withEmptyValue = FountainGrammarTests.fullScan("Title: A\nNotes:\n\t\n\nINT. HOUSE - DAY")
    let withNoValueLine = FountainGrammarTests.fullScan("Title: A\nNotes:\n\nINT. HOUSE - DAY")
    let withoutTheKey = FountainGrammarTests.fullScan("Title: A\n\nINT. HOUSE - DAY")

    // All three carry the `Notes` key or not, unambiguously.
    #expect(
      Self.texts(.titlePageKey, in: withEmptyValue, of: "Title: A\nNotes:\n\t\n\nINT. HOUSE - DAY")
        == ["Title", "Notes"])
    #expect(
      Self.texts(.titlePageKey, in: withoutTheKey, of: "Title: A\n\nINT. HOUSE - DAY") == ["Title"])

    // `Notes:` with a lone-tab value has a value record under it; `Notes:` with nothing
    // under it has none. That is the difference the writer round-trips on — one re-emits
    // the tab, the other re-emits a bare key.
    #expect(withEmptyValue.lineRecords.map(\.element) == [
      .titlePageKey, .titlePageKey, .titlePageValue, .blank, .sceneHeading,
    ])
    #expect(withNoValueLine.lineRecords.map(\.element) == [
      .titlePageKey, .titlePageKey, .blank, .sceneHeading,
    ])
    #expect(withoutTheKey.lineRecords.map(\.element) == [
      .titlePageKey, .blank, .sceneHeading,
    ])

    // Both `Notes` records have an empty content range — the key line always does, because
    // its value is below it — so emptiness of the *key* record is not the discriminator.
    // The presence of the value record is.
    #expect(withEmptyValue.lineRecords[1].contentRange.isEmpty)
    #expect(withNoValueLine.lineRecords[1].contentRange.isEmpty)
    #expect(withEmptyValue.lineRecords[2].contentRange.isEmpty)
  }

  /// **DL-149, found in Sortie 31 and deliberately not fixed there.**
  ///
  /// DL-150 — this test and its `@Test` display name said **DL-136** from Sortie 31 until
  /// Sortie 30 reconciled them. That number was already taken by an unrelated finding; the
  /// defect described here is DL-149, and `Tests/EscriboCoreTests/FountainWriterTitlePageTests.swift`
  /// pins the writer-side half of it under its other name, DL-170.
  ///
  /// Deviation 11's corroboration still reads a whitespace-only second line as no
  /// corroboration at all, so a document whose **first** key is the empty one opens no
  /// title page. `Title:` over a lone tab is indistinguishable, on one line of lookahead,
  /// from `CUT TO:` over a lone tab — there is genuinely no information to decide it — so
  /// widening the corroboration rule would turn an ordinary transition-led screenplay into
  /// a title page. Sortie 31's brief is the region's interior and this is its boundary.
  ///
  /// Descriptive, like the DL-130 test was: if a later sortie decides the ambiguity, this
  /// goes red and names itself.
  @Test("Known defect DL-149: a whitespace-only line does not corroborate a bare first key")
  func whitespaceOnlyLineDoesNotCorroborateABareFirstKey() {
    let source = "Title:\n\t\nCredit: Written by\n\nINT. HOUSE - DAY"
    let result = FountainGrammarTests.fullScan(source)

    // No title page at all — `Title:` is a transition, because it is uppercase-insensitive
    // only in the region it never opened.
    #expect(Self.texts(.titlePageKey, in: result, of: source).isEmpty)
    #expect(result.lineRecords[0].element != .titlePageKey)

    // The same document with any non-whitespace on the second line does open one, which is
    // what isolates the defect to the corroboration rule rather than to the region.
    let corroborated = FountainGrammarTests.fullScan("Title:\n\tA\n\nINT. HOUSE - DAY")
    #expect(corroborated.lineRecords[0].element == .titlePageKey)

    // **The hazard the obvious fix walks into, asserted rather than described (Sortie 30).**
    //
    // The supervisor measured that the one-word change — reading a whitespace-only second
    // line as corroboration — makes a transition-led document classify as a title page.
    // Nothing in this suite asserted the other side of the ambiguity, so the fix would have
    // looked free right up until it silently converted the top of a screenplay into
    // metadata. These two documents are that other side.
    //
    // `CUT TO:` is the sharp one: it is a *real* Fountain transition (Fountain 1.1 requires
    // a transition to end in `TO:`), it is a shape screenplays genuinely open on, and it is
    // indistinguishable from `Title:` over a lone tab on one line of lookahead. If it ever
    // starts scanning as a title page, a screenwriter's first line has been eaten.
    //
    // This is deliberately **not** an assertion that the current behaviour is right — like
    // the assertions above it, it is descriptive. It is here so that whichever way a later
    // sortie decides DL-149, it has to decide this at the same time, on purpose, in the
    // same commit, rather than discovering it from a bug report.
    let transitionSource = "CUT TO:\n\t\nThe end.\n"
    let transitionLed = FountainGrammarTests.fullScan(transitionSource)
    #expect(Self.texts(.titlePageKey, in: transitionLed, of: transitionSource).isEmpty)
    #expect(
      transitionLed.lineRecords.map(\.element) == [.transition, .blank, .action, .blank])

    // `FADE OUT:` is `action`, not `transition`, and that is correct rather than a second
    // defect: Fountain 1.1 recognizes a transition by the literal `TO:` ending, and
    // `FADE OUT.` / `FADE OUT:` are the spec's own examples of forms that need a leading
    // `>` to force. Included anyway because it is the document the hazard was measured on,
    // and because "it is not a title page" is the assertion that matters for both.
    let fadeSource = "FADE OUT:\n\t\nThe end.\n"
    let fadeLed = FountainGrammarTests.fullScan(fadeSource)
    #expect(Self.texts(.titlePageKey, in: fadeLed, of: fadeSource).isEmpty)
    #expect(fadeLed.lineRecords.map(\.element) == [.action, .blank, .action, .blank])
  }

  @Test("A title-page value may contain a colon without becoming two keys")
  func onlyTheFirstColonEndsAKey() {
    let source = "Notes: see 3:15 for the reprise\n\nINT. HOUSE - DAY"
    let result = FountainGrammarTests.fullScan(source)

    #expect(Self.texts(.titlePageKey, in: result, of: source) == ["Notes"])
    #expect(Self.texts(.titlePageValue, in: result, of: source) == ["see 3:15 for the reprise"])
  }

  // MARK: - Incremental behaviour
  //
  // Opening and closing a region is the state-invalidating edit: it changes every line
  // below it. These check the edited window against a fresh full scan by hand, which is
  // the same comparison the gate makes but with the *classifications* written out — so a
  // grammar that agreed with itself while being wrong would still be caught.

  @Test("Opening and closing a boneyard reclassifies the lines below it")
  func openingAndClosingABoneyardTracksAFullScan() {
    let base = "INT. HOUSE - DAY\n\nBob waits.\n\nBOB\nHello there.\n"
    var scanner = IncrementalScanner(grammar: FountainGrammar())
    let first = scanner.fullScan(base)
    ScanInvariants.check(first, text: base, editedRange: nil, "boneyard base")
    #expect(
      first.lineRecords.map(\.element) == [
        .sceneHeading, .blank, .action, .blank, .character, .dialogue, .blank,
      ])

    // Open a boneyard at the top. Everything below it is struck out.
    let opened = ScanInvariants.splice(base, 0..<0, "/*\n")
    let openResult = scanner.incrementalScan(
      TextEdit(range: 0..<0, replacementLength: 3), in: opened)
    ScanInvariants.check(openResult, text: opened, editedRange: 0..<3, "boneyard opened")

    var freshOpen = IncrementalScanner(grammar: FountainGrammar())
    let fullOpen = freshOpen.fullScan(opened)
    #expect(
      fullOpen.lineRecords.map(\.element) == [
        .boneyard, .boneyard, .boneyard, .boneyard, .boneyard, .boneyard, .boneyard, .boneyard,
      ])
    ScanInvariants.expectSameElements(
      scanner.startStates, freshOpen.startStates, "startStates", "boneyard opened")
    ScanInvariants.expectSameElements(
      openResult.lineRecords, fullOpen.lineRecords.filter { openResult.lines.contains($0.index) },
      "lineRecords", "boneyard opened")

    // Close it again at offset 32 — the start of the blank line above `BOB`. The lines
    // below the closer come back.
    let closed = ScanInvariants.splice(opened, 32..<32, "*/\n")
    let closeResult = scanner.incrementalScan(
      TextEdit(range: 32..<32, replacementLength: 3), in: closed)
    ScanInvariants.check(closeResult, text: closed, editedRange: 32..<35, "boneyard closed")

    var freshClose = IncrementalScanner(grammar: FountainGrammar())
    let fullClose = freshClose.fullScan(closed)
    // Written out: `/*`, the slug line, the blank line, `Bob waits.` and the `*/` are
    // struck; `BOB` and its speech are a dialogue block again.
    #expect(
      fullClose.lineRecords.map(\.element) == [
        .boneyard, .boneyard, .boneyard, .boneyard, .boneyard, .blank, .character, .dialogue,
        .blank,
      ])
    ScanInvariants.expectSameElements(
      scanner.startStates, freshClose.startStates, "startStates", "boneyard closed")
    ScanInvariants.expectSameElements(
      closeResult.lineRecords,
      fullClose.lineRecords.filter { closeResult.lines.contains($0.index) },
      "lineRecords", "boneyard closed")
  }

  @Test("Typing a title page onto line one reclassifies the region, and removing it undoes that")
  func titlePageAppearsAndDisappearsOnTheFirstLine() {
    let base = "INT. HOUSE - DAY\n"
    var scanner = IncrementalScanner(grammar: FountainGrammar())
    let first = scanner.fullScan(base)
    ScanInvariants.check(first, text: base, editedRange: nil, "title page base")
    #expect(first.lineRecords.map(\.element) == [.sceneHeading, .blank])

    // A key line above it. The slug line is now a continuation of the key's value, because
    // the title page owns its region.
    let added = ScanInvariants.splice(base, 0..<0, "Title: A\n")
    let addResult = scanner.incrementalScan(
      TextEdit(range: 0..<0, replacementLength: 9), in: added)
    ScanInvariants.check(addResult, text: added, editedRange: 0..<9, "title page added")

    var freshAdd = IncrementalScanner(grammar: FountainGrammar())
    let fullAdd = freshAdd.fullScan(added)
    #expect(fullAdd.lineRecords.map(\.element) == [.titlePageKey, .titlePageValue, .blank])
    ScanInvariants.expectSameElements(
      scanner.startStates, freshAdd.startStates, "startStates", "title page added")

    // And taking it away puts the slug line back.
    let removed = ScanInvariants.splice(added, 0..<9, "")
    let removeResult = scanner.incrementalScan(
      TextEdit(range: 0..<9, replacementLength: 0), in: removed)
    ScanInvariants.check(removeResult, text: removed, editedRange: 0..<0, "title page removed")

    var freshRemove = IncrementalScanner(grammar: FountainGrammar())
    let fullRemove = freshRemove.fullScan(removed)
    #expect(fullRemove.lineRecords.map(\.element) == [.sceneHeading, .blank])
    ScanInvariants.expectSameElements(
      scanner.startStates, freshRemove.startStates, "startStates", "title page removed")
  }

  // MARK: - Degenerate input

  @Test(
    "Degenerate region and title-page documents scan without failing",
    arguments: [
      "[[", "]]", "[[]]", "[", "[[[", "]]]]", "/*", "*/", "/*/", "/**/", "*/*", "/",
      "[[/*", "/*[[", ":", "::", "a:", ":a", " :a", "\t:\n", "Title:", "Title:\n",
      "[[\n]]", "/*\n*/", "/*\n\n\n", "[[\n\n\n", "Title:\n\n", "/*[[*/]]",
    ])
  func degenerateRegionDocuments(source: String) {
    let result = FountainGrammarTests.fullScan(source)
    #expect(result.spans.reduce(0) { $0 + $1.range.count } == source.utf16.count)
    IncrementalScannerTests.expectInvariants(
      result, text: source, editedRange: nil, "degenerate region")
  }
}
