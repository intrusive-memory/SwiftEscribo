#if os(iOS)
  import EscriboCore
  import Foundation
  import Testing
  import UIKit

  @testable import SwiftEscribo

  /// What the host's embed callbacks were called with.
  @MainActor
  final class EmbedCallbackRecorder {
    var activations: [EscriboBlock] = []
    var actions: [(block: EscriboBlock, id: String)] = []

    func install(on editor: EscriboTextView) {
      editor.coordinator.setEmbedCallbacks(
        onActivate: { [weak self] in self?.activations.append($0) },
        onAction: { [weak self] in self?.actions.append((block: $0, id: $1)) },
        onFindMatch: { _ in })
    }
  }

  /// REQUIREMENTS.md § 1.3 on iOS: selection, edits, paste, delete keys, tap, `⌥↩` and undo
  /// over a drawn embed. Real gestures and hardware keys cannot be delivered to a unit-test
  /// host, so each test drives the public UIKit entry point a gesture lands on
  /// (IOS_LIVE_CHECK.md, "Selection funnels") or the seam the gesture's recognizer calls.
  /// `UIPasteboard.general` is never read: it blocks the simulator test host.
  @MainActor
  @Suite("iOS embed input: selection, edits, paste, delete, tap, ⌥↩, undo", .serialized)
  struct IOSEmbedInputTests {

    // MARK: - Fixtures

    @MainActor
    struct Fixture {
      let harness: EmbedLayoutHarness
      let recorder = EmbedCallbackRecorder()
      var editor: EscriboTextView { harness.editor }
      var textView: EscriboNativeTextView { harness.editor.textView }
      var note: NSRange { NSRange(location: harness.note.lowerBound, length: harness.note.count) }
      var input: IOSEmbedInput {
        get throws { try #require(harness.editor.textView.embedInput) }
      }
      var text: String { harness.editor.documentStorage.string }

      init(embedded: Bool = true) throws {
        harness = try EmbedLayoutHarness()
        if embedded { harness.embed() }
        _ = harness.layout()
        recorder.install(on: harness.editor)
      }
    }

    /// Hosts the text view in a window: UIKit's undo manager comes from the responder chain.
    static func host(_ textView: UITextView) -> UIWindow {
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
      window.addSubview(textView)
      window.isHidden = false
      return window
    }

    /// Lets UIKit's run-loop work (undo grouping, deferred clears) finish.
    static func settle() {
      _ = CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.05, false)
    }

    static func strictlyInside(_ location: Int, _ range: NSRange) -> Bool {
      location > range.location && location < NSMaxRange(range)
    }

    static func caret(_ textView: UITextView, at offset: Int) throws -> UITextRange {
      let position = try #require(
        textView.position(from: textView.beginningOfDocument, offset: offset))
      return try #require(textView.textRange(from: position, to: position))
    }

    // MARK: - Selection setters

    @Test(
      "selectedTextRange / selectedRange setters step a caret over the embed and grow selections to it"
    )
    func setterStepOverAndExtend() throws {
      let f = try Fixture()
      let tv = f.textView
      let note = f.note

      // Right from the start edge: UIKit proposes start + 1, the caret lands on the end edge.
      tv.selectedRange = NSRange(location: note.location, length: 0)
      tv.selectedTextRange = try Self.caret(tv, at: note.location + 1)
      #expect(tv.selectedRange == NSRange(location: NSMaxRange(note), length: 0))
      // Left from the end edge lands on the start edge.
      tv.selectedTextRange = try Self.caret(tv, at: NSMaxRange(note) - 1)
      #expect(tv.selectedRange == NSRange(location: note.location, length: 0))

      // The NSRange setter too, travelling down and up.
      tv.selectedRange = NSRange(location: 0, length: 0)
      tv.selectedRange = NSRange(location: note.location + 20, length: 0)
      #expect(tv.selectedRange == NSRange(location: NSMaxRange(note), length: 0))
      tv.selectedRange = NSRange(location: note.location + 20, length: 0)
      #expect(tv.selectedRange == NSRange(location: note.location, length: 0))

      // A selection reaching into the embed grows over all of it, through both setters.
      tv.selectedRange = NSRange(location: note.location - 5, length: 8)
      #expect(tv.selectedRange == NSRange(location: note.location - 5, length: note.length + 5))
      let from = try #require(
        tv.position(from: tv.beginningOfDocument, offset: NSMaxRange(note) - 2))
      let to = try #require(tv.position(from: tv.beginningOfDocument, offset: NSMaxRange(note) + 3))
      tv.selectedTextRange = tv.textRange(from: from, to: to)
      #expect(tv.selectedRange == NSRange(location: note.location, length: note.length + 3))

      // Non-vacuous: without a provider the same caret stays inside.
      let plain = try Fixture(embedded: false)
      plain.textView.selectedRange = NSRange(location: plain.note.location + 20, length: 0)
      #expect(
        plain.textView.selectedRange == NSRange(location: plain.note.location + 20, length: 0))
    }

    // MARK: - Tap

    @Test("a tap on the row selects the whole block (no edge caret) and activates once per tap")
    func tapSelectsWholeAndActivatesOnce() throws {
      let f = try Fixture()
      let tv = f.textView
      let input = try f.input
      let note = f.note
      let layout = try #require(f.editor.embedLayout)
      let hit = try #require(layout.embeddedBlock(containingUTF16Offset: note.location))
      let row = try #require(layout.rowRect(for: hit))

      // The recognizer that detects tap origin is on the text view and never steals touches.
      let recognizer = try #require(input.tapRecognizer)
      #expect(tv.gestureRecognizers?.contains { $0 === recognizer } == true)
      #expect(!recognizer.cancelsTouchesInView && !recognizer.delaysTouchesEnded)
      #expect(recognizer.delegate === input)

      for point in [
        CGPoint(x: row.midX, y: row.midY), CGPoint(x: row.minX + 4, y: row.minY + 2),
        CGPoint(x: row.maxX - 4, y: row.maxY - 2),
      ] {
        #expect(input.embeddedBlock(atRowPoint: point) == hit)
        // UIKit's own tap proposes `closestPosition(to:)` — inside the block.
        let raw = try #require(tv.closestPosition(to: point))
        let proposed = tv.offset(from: tv.beginningOfDocument, to: raw)
        #expect(NSLocationInRange(proposed, note))

        // Order 1: UIKit commits its proposal first, then the tap is recognised.
        for start in [0, (f.text as NSString).length] {
          tv.selectedRange = NSRange(location: start, length: 0)
          let before = f.recorder.activations.count
          input.touchBegan(at: point)
          tv.selectedTextRange = tv.textRange(from: raw, to: raw)
          #expect(tv.selectedRange == note, "UIKit's tap proposal \(proposed) from \(start)")
          input.tapRecognized(at: point)
          input.touchFinished()
          Self.settle()
          #expect(tv.selectedRange == note)
          #expect(f.recorder.activations.count == before + 1)
          #expect(f.recorder.activations.last == hit.block)
          #expect(input.touchedBlock == nil)
        }

        // Order 2: the tap is recognised first, then UIKit's commit arrives — and a second
        // tap on the same row selects the same block again, never flipping to an edge.
        let before = f.recorder.activations.count
        input.touchBegan(at: point)
        input.tapRecognized(at: point)
        tv.selectedTextRange = tv.textRange(from: raw, to: raw)
        input.touchFinished()
        Self.settle()
        #expect(tv.selectedRange == note)
        #expect(f.recorder.activations.count == before + 1)
      }

      // A touch off the row is not a row tap: it places the caret as usual.
      let firstLine = CGPoint(x: row.midX, y: tv.textContainerInset.top + 4)
      #expect(input.embeddedBlock(atRowPoint: firstLine) == nil)
      let before = f.recorder.activations.count
      input.touchBegan(at: firstLine)
      #expect(input.touchedBlock == nil)
      input.tapRecognized(at: firstLine)
      input.touchFinished()
      #expect(f.recorder.activations.count == before)
    }

    @Test(
      "a programmatic selection on the embed never activates it, and snaps rather than selecting it"
    )
    func programmaticSelectionDoesNotActivate() throws {
      let f = try Fixture()
      let tv = f.textView
      let note = f.note

      tv.selectedRange = NSRange(location: 0, length: 0)
      tv.selectedRange = NSRange(location: note.location + 3, length: 0)
      #expect(tv.selectedRange == NSRange(location: NSMaxRange(note), length: 0))
      tv.selectedTextRange = try Self.caret(tv, at: note.location + 3)
      #expect(!Self.strictlyInside(tv.selectedRange.location, note))
      #expect(tv.selectedRange.length == 0)
      tv.selectedRange = note
      #expect(tv.selectedRange == note)
      tv.selectAll(nil)
      Self.settle()
      #expect(f.recorder.activations.isEmpty)
    }

    // MARK: - Edits

    @Test("insertText, marked text and replace(_:withText:) over the embed change nothing")
    func editsVetoed() throws {
      let f = try Fixture()
      let tv = f.textView
      let original = f.text

      for selection in [f.note, NSRange(location: f.note.location - 1, length: f.note.length + 2)] {
        tv.selectedRange = selection
        #expect(tv.selectedRange == selection)
        tv.insertText("x")
        tv.insertText("\n")  // Return, and its affordance, too
        tv.insertText("\t")
        tv.setMarkedText("x", selectedRange: NSRange(location: 1, length: 0))
        #expect(tv.markedTextRange == nil)
        let range = try #require(tv.selectedTextRange)
        tv.replace(range, withText: "x")
        #expect(f.text == original, "selection \(selection)")
      }
      // A replacement cutting the embed in part, wherever it comes from.
      let from = try #require(
        tv.position(from: tv.beginningOfDocument, offset: f.note.location + 2))
      let to = try #require(tv.position(from: from, offset: 4))
      tv.replace(try #require(tv.textRange(from: from, to: to)), withText: "y")
      #expect(f.text == original)
      #expect(f.editor.coordinator.embeddedBlocks.count == 1)

      // Non-vacuous: typing at the end edge (the next line's start) edits.
      tv.selectedRange = NSRange(location: NSMaxRange(f.note), length: 0)
      tv.insertText("x")
      #expect(f.text != original)
      #expect(f.editor.coordinator.embeddedBlocks.count == 1)
    }

    @Test(
      "typing at the embed's start edge is ignored unless it is a line break, which keeps the block whole"
    )
    func startEdgeTyping() throws {
      let f = try Fixture()
      let tv = f.textView
      let original = f.text
      let start = f.note.location

      tv.selectedRange = NSRange(location: start, length: 0)
      #expect(try f.input.typingVerdict(range: tv.selectedRange, text: "x") == .veto)
      tv.insertText("x")
      tv.setMarkedText("k", selectedRange: NSRange(location: 1, length: 0))
      #expect(f.text == original)
      #expect(try !f.input.allowsInput(range: tv.selectedRange, text: "\u{FFFC}"))  // paste
      #expect(!tv.pasteAllowed())

      // Backspace at the start edge deletes the blank line above: allowed (the line break
      // before the block stays), and the block stays an embed.
      tv.deleteBackward()
      #expect((f.text as NSString).length == (original as NSString).length - 1)
      let moved = start - 1
      #expect(
        f.editor.coordinator.embeddedBlock(containingUTF16Offset: moved)?.block.range.lowerBound
          == moved)
      // Again: that would pull the block's first line up onto "door." — ignored.
      #expect(tv.selectedRange == NSRange(location: moved, length: 0))
      let joined = f.text
      tv.deleteBackward()
      #expect(f.text == joined)

      // Return there inserts a plain newline: the block moves down, intact, still an embed.
      tv.insertText("\n")
      #expect(f.text == original)
      let block = try #require(f.editor.coordinator.embeddedBlock(containingUTF16Offset: start))
      #expect(block.block.range == f.harness.note)
    }

    // MARK: - Paste

    @Test(
      "paste with the block selected is hidden from the menu and changes nothing; the pasteboard is never read"
    )
    func pasteVetoed() throws {
      let f = try Fixture()
      let tv = f.textView
      let original = f.text

      for selection in [f.note, NSRange(location: f.note.location - 1, length: f.note.length + 2)] {
        tv.selectedRange = selection
        #expect(!tv.pasteAllowed())
        // `canPerformAction` answers before `super`, which could consult the pasteboard.
        for action in EscriboNativeTextView.pasteActions {
          #expect(!tv.canPerformAction(action, withSender: nil), "\(action)")
        }
        // Each entry point returns before UIKit reads the pasteboard.
        tv.paste(nil)
        tv.pasteAndMatchStyle(nil)
        tv.paste(itemProviders: [NSItemProvider(object: "x" as NSString)])
        #expect(f.text == original)
      }

      // Outside the embed the verdict allows paste (UIKit's own paste is not exercised: it
      // reads the general pasteboard).
      tv.selectedRange = NSRange(location: 0, length: 0)
      #expect(tv.pasteAllowed())
      tv.selectedRange = NSRange(location: NSMaxRange(f.note), length: 0)
      #expect(tv.pasteAllowed())
    }

    // MARK: - Delete keys and undo

    @Test(
      "Backspace selects the embed first, then removes it plus a blank line as one undo step; undo/redo restore"
    )
    func backspaceSelectThenDeleteAndUndo() throws {
      let f = try Fixture()
      let tv = f.textView
      let window = Self.host(tv)
      defer { window.isHidden = true }
      let undo = try #require(tv.undoManager)
      Self.settle()
      undo.removeAllActions()

      let original = f.text
      let removal = EmbedSelection.deletionRange(for: f.note, in: original as NSString)
      #expect(removal.length == f.note.length + 1)
      let expected = (original as NSString).replacingCharacters(in: removal, with: "")

      // First press, caret just after the embed: selects it, deletes nothing.
      tv.selectedRange = NSRange(location: NSMaxRange(f.note), length: 0)
      tv.deleteBackward()
      #expect(tv.selectedRange == f.note)
      #expect(f.text == original)
      #expect(!undo.canUndo)

      // Second press: block plus the following blank line.
      tv.deleteBackward()
      Self.settle()
      #expect(f.text == expected)
      #expect(tv.selectedRange == NSRange(location: removal.location, length: 0))
      #expect(f.editor.coordinator.embeddedBlocks.isEmpty)

      // One undo step: text and embed back, with the block selected; nothing further.
      #expect(undo.canUndo)
      undo.undo()
      Self.settle()
      #expect(Array(f.text.utf16) == Array(original.utf16))
      #expect(f.editor.coordinator.embeddedBlocks.map(\.block.range) == [f.harness.note])
      #expect(tv.selectedRange == f.note)
      #expect(!undo.canUndo)

      // Redo removes it again; a second undo restores it selected again.
      #expect(undo.canRedo)
      undo.redo()
      Self.settle()
      #expect(f.text == expected)
      #expect(f.editor.coordinator.embeddedBlocks.isEmpty)
      undo.undo()
      Self.settle()
      #expect(f.text == original)
      #expect(f.editor.coordinator.embeddedBlocks.count == 1)
      #expect(tv.selectedRange == f.note)
    }

    @Test("hardware forward-delete selects the embed first, then removes it as one undo step")
    func forwardDeleteSelectThenDelete() throws {
      let f = try Fixture()
      let tv = f.textView
      let window = Self.host(tv)
      defer { window.isHidden = true }
      let undo = try #require(tv.undoManager)
      Self.settle()
      undo.removeAllActions()
      let original = f.text
      let removal = EmbedSelection.deletionRange(for: f.note, in: original as NSString)
      let expected = (original as NSString).replacingCharacters(in: removal, with: "")

      // The key is taken on key-down (`pressesBegan`) only where it acts on an embed;
      // elsewhere it is left to UIKit. Real key presses cannot be synthesised here, so the
      // test calls what `pressesBegan` calls.
      tv.selectedRange = NSRange(location: 0, length: 0)
      #expect(!tv.forwardDeleteAtEmbed())
      #expect(f.text == original)

      tv.selectedRange = NSRange(location: f.note.location, length: 0)
      #expect(tv.forwardDeleteAtEmbed())
      #expect(tv.selectedRange == f.note)
      #expect(f.text == original)
      #expect(tv.forwardDeleteAtEmbed())
      Self.settle()
      #expect(f.text == expected)

      undo.undo()
      Self.settle()
      #expect(f.text == original)
      #expect(tv.selectedRange == f.note)
      #expect(f.editor.coordinator.embeddedBlocks.count == 1)
      #expect(!undo.canUndo)
    }

    // MARK: - Copy

    @Test("copy with the block selected copies the block's source")
    func copySource() throws {
      let f = try Fixture()
      let tv = f.textView
      // `copy(_:)` writes only to the general pasteboard, which the test host cannot read;
      // this asserts what the copy reads — the text vended for the selection.
      tv.selectedRange = f.note
      #expect(
        tv.canPerformAction(#selector(UIResponderStandardEditActions.copy(_:)), withSender: nil))
      let range = try #require(tv.selectedTextRange)
      #expect(tv.text(in: range) == EmbedLayoutFixture.noteLines)
      #expect(
        tv.attributedText.attributedSubstring(from: tv.selectedRange).string
          == EmbedLayoutFixture.noteLines)
    }

    // MARK: - ⌥↩

    @Test(
      "⌥↩ is a priority key command that calls onEmbedAction with editAsTextID while an embed is selected"
    )
    func optionReturnEditsAsText() throws {
      let f = try Fixture()
      let tv = f.textView
      let command = try #require(
        tv.keyCommands?.first { $0.input == "\r" && $0.modifierFlags == .alternate })
      #expect(command.wantsPriorityOverSystemBehavior)
      let action = try #require(command.action)
      #expect(action == #selector(EscriboNativeTextView.editEmbedAsText(_:)))
      #expect(EscriboEmbed.Action.editAsTextID == "escribo.editAsText")

      // Without an embed selected the command is disabled, so ⌥↩ types as usual.
      tv.selectedRange = NSRange(location: NSMaxRange(f.note), length: 0)
      #expect(!tv.canPerformAction(action, withSender: command))

      tv.selectedRange = f.note
      #expect(tv.canPerformAction(action, withSender: command))
      let original = f.text
      tv.editEmbedAsText(command)
      #expect(f.recorder.actions.count == 1)
      #expect(f.recorder.actions.first?.id == EscriboEmbed.Action.editAsTextID)
      #expect(f.recorder.actions.first?.block.range == f.harness.note)
      #expect(f.text == original)
      #expect(tv.selectedRange == f.note)
      #expect(f.recorder.activations.isEmpty)
    }

    // MARK: - Off by default

    @Test("with no provider every rule passes through")
    func offByDefault() throws {
      let f = try Fixture(embedded: false)
      let tv = f.textView
      let input = try f.input
      #expect(input.embeds.isEmpty)
      let inside = NSRange(location: f.note.location + 5, length: 0)
      tv.selectedRange = inside
      #expect(tv.selectedRange == inside)
      #expect(input.typingVerdict(range: inside, text: "x") == .normal)
      #expect(!input.handleDeleteKey(forward: false))
      #expect(!input.forwardDeleteActs())
      #expect(tv.pasteAllowed())
      let original = f.text
      tv.insertText("x")
      #expect(f.text == (original as NSString).replacingCharacters(in: inside, with: "x"))
    }
  }
#endif
