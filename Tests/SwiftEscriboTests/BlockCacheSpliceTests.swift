import EscriboCore
import Foundation
import Testing

@testable import SwiftEscribo

/// The document-wide block cache stays current while the writer types in and around
/// multi-line blocks — spliced, never rebuilt by a full scan.
///
/// ## What used to happen
///
/// The splice in ``EditorCoordinator`` declines whenever a cached block straddles the
/// rescanned window, and the scanner's minimal window is not block-aligned: it starts a
/// line above the edit and stops a line past convergence. So a keystroke inside a
/// multi-line block — a hard-wrapped paragraph, a speech, a note — landed a window edge
/// inside that block and cleared ``EditorCoordinator/blocksSpanDocument``. On macOS it
/// happened one block *above* a note too, because AppKit reports a keystroke's edited
/// range one code unit longer than the insertion (its attribute-fixing pass extends it over
/// the line terminator), which moves convergence one line down. After that every block
/// query paid a full scan.
///
/// ## What these assert, keystroke by keystroke
///
/// 1. ``EditorCoordinator/blocksSpanDocument`` is still `true`.
/// 2. ``EditorCoordinator/documentBlocks`` equals the blocks a scanner that never saw the
///    earlier document produces for the current text — the real criterion, compared whole
///    rather than at one offset.
/// 3. ``EditorCoordinator/fullScanCount`` has not moved.
///
/// The view-driven suite types through the platform's own input path (`NSTextView` on
/// macOS, `UITextView` on iOS), so it covers the edit ranges each text system really
/// reports. The storage-driven suite is platform-neutral and adds the edits that change the
/// line count.
@MainActor
@Suite("Block cache — splice stays current around multi-line blocks")
struct BlockCacheSpliceTests {

  // MARK: - Fixtures

  /// A screenplay with every multi-line Fountain block the sortie names: an action
  /// paragraph, a speech, a standalone note, and a standalone JSON note.
  static let fountain = """
    INT. HOUSE - DAY

    Bob waits by the door.
    He checks his watch.
    He waits some more.
    Then he sits.

    BOB
    (quietly)
    I have been waiting
    for a very long time
    and I am tired.

    [[First line of the note
    second line
    third line
    fourth line
    fifth line]]

    [[{"kind": "beat",
    "title": "Arrival",
    "tags": ["a", "b"],
    "done": false}]]

    Jane enters.

    """

  /// Markdown's multi-line blocks: a plain paragraph (no inline syntax, so the scanner's
  /// joined-content widening does not apply), a paragraph whose emphasis crosses a line
  /// (so it does), and a list item with continuations.
  static let markdown = """
    # Title

    This is a paragraph
    that wraps over
    several lines of
    plain prose text
    without any syntax.

    Another paragraph with *emphasis
    that spans* two lines and
    a third line.

    - a list item
      that continues
      over three lines

    Last line.

    """

  /// One keystroke: type `x` at `offset` code units into the first occurrence of `anchor`
  /// in the document as it stands.
  struct Keystroke: CustomStringConvertible {
    let label: String
    let anchor: String
    let offset: Int

    var description: String { "\(label) (\(anchor.debugDescription) + \(offset))" }

    func location(in text: String) -> Int? {
      let found = (text as NSString).range(of: anchor)
      guard found.location != NSNotFound else { return nil }
      return found.location + offset
    }
  }

  /// Above, inside (first, middle and last line) and below each multi-line block.
  static let fountainKeystrokes: [Keystroke] = [
    // The action paragraph, lines 2–5.
    Keystroke(label: "above action", anchor: "INT. HOUSE - DAY", offset: 16),
    Keystroke(label: "action, first line", anchor: "Bob waits", offset: 3),
    Keystroke(label: "action, middle line", anchor: "He checks", offset: 2),
    Keystroke(label: "action, last line", anchor: "Then he sits.", offset: 12),
    // The speech, lines 7–11.
    Keystroke(label: "above speech", anchor: "Then he", offset: 4),
    Keystroke(label: "speech, cue", anchor: "BOB\n", offset: 1),
    Keystroke(label: "speech, parenthetical", anchor: "(quietly)", offset: 3),
    Keystroke(label: "speech, middle line", anchor: "for a very", offset: 3),
    Keystroke(label: "speech, last line", anchor: "and I am tired.", offset: 14),
    // The note, lines 13–17.
    Keystroke(label: "above note", anchor: "and I am", offset: 3),
    Keystroke(label: "note, first line", anchor: "[[First line", offset: 7),
    Keystroke(label: "note, middle line", anchor: "third line", offset: 5),
    Keystroke(label: "note, last line", anchor: "fifth line]]", offset: 10),
    // The JSON note, lines 19–22.
    Keystroke(label: "above JSON note", anchor: "fifth", offset: 5),
    Keystroke(label: "JSON note, first line", anchor: "\"beat\"", offset: 3),
    Keystroke(label: "JSON note, middle line", anchor: "\"Arrival\"", offset: 3),
    Keystroke(label: "JSON note, last line", anchor: "\"done\"", offset: 3),
    // And below the last of them.
    Keystroke(label: "below JSON note", anchor: "Jane enters.", offset: 4),
  ]

  static let markdownKeystrokes: [Keystroke] = [
    Keystroke(label: "above paragraph", anchor: "# Title", offset: 7),
    Keystroke(label: "paragraph, first line", anchor: "This is", offset: 4),
    Keystroke(label: "paragraph, middle line", anchor: "several lines", offset: 7),
    Keystroke(label: "paragraph, last line", anchor: "without any", offset: 7),
    Keystroke(label: "emphasis paragraph, first line", anchor: "Another", offset: 3),
    Keystroke(label: "emphasis paragraph, middle line", anchor: "that spans*", offset: 4),
    Keystroke(label: "emphasis paragraph, last line", anchor: "a third", offset: 5),
    Keystroke(label: "list item, marker line", anchor: "- a list", offset: 5),
    Keystroke(label: "list item, continuation", anchor: "that continues", offset: 4),
    Keystroke(label: "below list item", anchor: "Last line.", offset: 4),
  ]

  // MARK: - Assertions

  /// The three per-keystroke properties, against a scanner that never saw the earlier text.
  static func expectCacheIsCurrent(
    _ coordinator: EditorCoordinator, text: String, fullScans: Int, step: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    var fresh = EscriboScanner(language: coordinator.language)
    let expected = fresh.fullScan(text).blocks
    #expect(
      coordinator.blocksSpanDocument, "\(step): the splice declined",
      sourceLocation: sourceLocation)
    #expect(
      coordinator.documentBlocks == expected,
      """
      \(step): spliced blocks differ from a fresh scan
        spliced: \(coordinator.documentBlocks.map { "\($0.kind.rawValue)\($0.lines)" })
        fresh:   \(expected.map { "\($0.kind.rawValue)\($0.lines)" })
      """,
      sourceLocation: sourceLocation)
    #expect(
      coordinator.fullScanCount == fullScans, "\(step): a keystroke fell back to a full scan",
      sourceLocation: sourceLocation)
  }

  // MARK: - Through the platform's own input path

  /// Types each keystroke through the text view, in order, on one document.
  func typeThroughTheView(
    _ text: String, language: Language, theme: EscriboTheme, keystrokes: [Keystroke]
  ) throws {
    let editor = EscriboTextView(language: language, theme: theme)
    _ = editor.applyExternalText(text)
    let coordinator = editor.coordinator
    let fullScans = coordinator.fullScanCount
    Self.expectCacheIsCurrent(
      coordinator, text: editor.documentStorage.string, fullScans: fullScans, step: "setup")

    for keystroke in keystrokes {
      let location = try #require(
        keystroke.location(in: editor.documentStorage.string), "\(keystroke): anchor missing")
      placeCaret(editor, at: location)
      typeText(editor, "x")
      Self.expectCacheIsCurrent(
        coordinator, text: editor.documentStorage.string, fullScans: fullScans,
        step: keystroke.description)
    }
    #expect(
      coordinator.fullScanCount == fullScans,
      "zero full scans across \(keystrokes.count) keystrokes")
  }

  @Test("Fountain: typing above, inside and below each multi-line block, through the view")
  func fountainThroughTheView() throws {
    try typeThroughTheView(
      Self.fountain, language: .fountain, theme: .fountainLight,
      keystrokes: Self.fountainKeystrokes)
  }

  @Test("Markdown: typing above, inside and below each multi-line block, through the view")
  func markdownThroughTheView() throws {
    try typeThroughTheView(
      Self.markdown, language: .markdown, theme: .markdownLight,
      keystrokes: Self.markdownKeystrokes)
  }

  @Test("Twenty keystrokes above a three-line note keep the cache spliced (the spike's case)")
  func twentyKeystrokesAboveANote() throws {
    // The exact sequence that left the cache unspliced on macOS: the end of the action line
    // above a standalone three-line note, one keystroke at a time.
    let text =
      "INT. HOUSE - DAY\n\nBob waits by the door.\n\n"
      + "[[First line of the note\nsecond line\nthird line]]\n\nJane enters.\n"
    let editor = EscriboTextView(language: .fountain, theme: .fountainLight)
    _ = editor.applyExternalText(text)
    let coordinator = editor.coordinator
    let fullScans = coordinator.fullScanCount
    let lineEnd = (text as NSString).range(of: "door.").upperBound

    for index in 0..<20 {
      placeCaret(editor, at: lineEnd + index)
      typeText(editor, "x")
      if index == 0 {
        // The edit each text system reports for one typed character — the platform
        // difference behind the old macOS-only decline. Logged, not asserted: the fix makes
        // the splice independent of it, and the text systems are free to change it.
        print(
          "BLOCK-CACHE edit reported for one keystroke: \(String(describing: coordinator.lastEdit))"
        )
      }
      Self.expectCacheIsCurrent(
        coordinator, text: editor.documentStorage.string, fullScans: fullScans,
        step: "keystroke \(index + 1)")
    }
    let note = try #require(coordinator.documentBlocks.first { $0.kind == .note })
    #expect(note.lines == 4..<7, "the note is still one three-line block")
    #expect(note.range.lowerBound == (text as NSString).range(of: "[[").location + 20)
  }

  // MARK: - Platform-neutral, through the storage

  /// Edits applied straight to the storage, so the line count can change: Return inside a
  /// block, a newline deleted inside one, and a range replaced across a block edge.
  @Test("Line-count-changing edits inside multi-line blocks splice to a fresh scan's blocks")
  func lineCountChangingEditsSplice() throws {
    let editor = CoordinatorFixtures.makeEditor(Self.fountain, language: .fountain)
    let coordinator = editor.coordinator
    let fullScans = coordinator.fullScanCount

    /// Replace `length` code units at `offset` into `anchor` with `replacement`.
    struct Edit {
      let label: String
      let anchor: String
      let offset: Int
      let length: Int
      let replacement: String

      init(_ label: String, at anchor: String, _ offset: Int, _ length: Int, _ text: String) {
        self.label = label
        self.anchor = anchor
        self.offset = offset
        self.length = length
        self.replacement = text
      }
    }
    let edits = [
      Edit("Return in the action", at: "checks his", 6, 0, "\n"),
      Edit("join two action lines", at: "more.\nThen", 5, 1, " "),
      Edit("Return in the speech", at: "very long", 4, 0, "\n"),
      Edit("join two speech lines", at: "time\nand", 4, 1, " "),
      Edit("Return in the note", at: "third line", 5, 0, "\n"),
      Edit("join two note lines", at: "second line\n", 11, 1, " "),
      Edit("Return in the JSON note", at: "\"tags\": [", 9, 0, "\n"),
      Edit("delete across two blocks", at: "tired.\n\n[[First", 3, 9, ""),
    ]

    for edit in edits {
      let string = editor.storage.string
      let found = (string as NSString).range(of: edit.anchor)
      try #require(found.location != NSNotFound, "\(edit.label): anchor missing")
      editor.storage.replaceCharacters(
        in: NSRange(location: found.location + edit.offset, length: edit.length),
        with: edit.replacement)
      Self.expectCacheIsCurrent(
        coordinator, text: editor.storage.string, fullScans: fullScans, step: edit.label)
    }
  }

  @Test("Single keystrokes through the storage match a fresh scan on every platform")
  func keystrokesThroughTheStorage() throws {
    for (text, language, keystrokes) in [
      (Self.fountain, Language.fountain, Self.fountainKeystrokes),
      (Self.markdown, Language.markdown, Self.markdownKeystrokes),
    ] {
      let editor = CoordinatorFixtures.makeEditor(text, language: language)
      let fullScans = editor.coordinator.fullScanCount
      for keystroke in keystrokes {
        let location = try #require(
          keystroke.location(in: editor.storage.string), "\(keystroke): anchor missing")
        editor.storage.replaceCharacters(in: NSRange(location: location, length: 0), with: "x")
        Self.expectCacheIsCurrent(
          editor.coordinator, text: editor.storage.string, fullScans: fullScans,
          step: "\(language) \(keystroke)")
      }
    }
  }
}
