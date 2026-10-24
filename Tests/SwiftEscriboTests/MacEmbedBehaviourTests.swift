#if os(macOS)
  import AppKit
  import EscriboCore
  import Foundation
  import Testing

  @testable import SwiftEscribo

  /// An embed-drawing editor with an observable undo manager and recorded host callbacks.
  ///
  /// A class because `NSTextView.delegate` is weak: the undo provider must be owned by
  /// something that outlives every assertion (see ``UndoableEditor``).
  @MainActor
  final class MacEmbedHarness {
    let layout: EmbedLayoutHarness
    let undoProvider = TestUndoManagerProvider()
    var activations: [EscriboBlock] = []
    var actions: [(block: EscriboBlock, id: String)] = []
    var findMatches: [EscriboBlock] = []
    /// Runs inside `onFindMatchInEmbed`, as a host's handler would.
    var onFindMatch: ((EscriboBlock) -> Void)?

    var editor: EscriboTextView { layout.editor }
    var textView: EscriboNativeTextView { layout.editor.textView }
    var undo: CountingUndoManager { undoProvider.manager }

    /// The note block as an `NSRange`, in the original document.
    let note: NSRange
    let original: String

    init(text: String = EmbedLayoutFixture.text) throws {
      let layout = try EmbedLayoutHarness(text: text)
      self.layout = layout
      note = NSRange(location: layout.note.lowerBound, length: layout.note.count)
      original = layout.editor.textView.string
      textView.delegate = undoProvider
      editor.coordinator.setEmbedCallbacks(
        onActivate: { [unowned self] in self.activations.append($0) },
        onAction: { [unowned self] in self.actions.append((block: $0, id: $1)) },
        onFindMatch: { [unowned self] in
          self.findMatches.append($0)
          self.onFindMatch?($0)
        })
      layout.embed()
      _ = layout.layout()
      settleEventGroup()
      undo.removeAllActions()
      undo.resetCount()
    }

    var string: String { textView.string }
    var selection: NSRange { textView.selectedRange() }

    func select(_ range: NSRange) { textView.setSelectedRange(range) }
    func caret(_ location: Int) { textView.setSelectedRange(NSRange(location: location, length: 0)) }
    func type(_ text: String) {
      textView.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    /// The embedded blocks' starts, as the coordinator's cache holds them.
    var embeddedStarts: [Int] { editor.coordinator.embeddedBlocks.map(\.block.range.lowerBound) }

    static func strictlyInside(_ location: Int, _ range: NSRange) -> Bool {
      location > range.location && location < NSMaxRange(range)
    }
  }

  /// REQUIREMENTS.md § 1.3 on macOS: one test per behaviour of an embed row.
  @MainActor
  @Suite("macOS embed behaviour", .serialized)
  struct MacEmbedBehaviourTests {

    // MARK: Step-over

    @Test("Arrows step over the embed and the caret never lands inside it")
    func arrowsStepOver() throws {
      let h = try MacEmbedHarness()
      let tv = h.textView

      h.caret(h.note.location)
      tv.moveRight(nil)
      #expect(h.selection == NSRange(location: NSMaxRange(h.note), length: 0))
      tv.moveLeft(nil)
      #expect(h.selection == NSRange(location: h.note.location, length: 0))

      let length = (h.string as NSString).length
      var visited: [Int] = []
      h.caret(0)
      for _ in 0..<(length + 2) {
        tv.moveRight(nil)
        visited.append(h.selection.location)
      }
      for _ in 0..<(length + 2) {
        tv.moveLeft(nil)
        visited.append(h.selection.location)
      }
      h.caret(0)
      for _ in 0..<10 {
        tv.moveDown(nil)
        visited.append(h.selection.location)
      }
      for _ in 0..<10 {
        tv.moveUp(nil)
        visited.append(h.selection.location)
      }
      #expect(!visited.contains { MacEmbedHarness.strictlyInside($0, h.note) }, "\(visited)")
      #expect(visited.contains(h.note.location) && visited.contains(NSMaxRange(h.note)))
      #expect(visited.contains { $0 > NSMaxRange(h.note) }, "never got past: \(visited)")

      // A programmatic caret inside snaps to an edge too.
      h.caret(h.note.location + 3)
      #expect(!MacEmbedHarness.strictlyInside(h.selection.location, h.note))
    }

    // MARK: Extend

    @Test("Shift-arrows and drags that touch the embed extend over the whole block")
    func selectionExtendsToWholeBlock() throws {
      let h = try MacEmbedHarness()
      let tv = h.textView

      h.caret(h.note.location)
      tv.moveRightAndModifySelection(nil)
      #expect(h.selection == h.note)

      h.caret(NSMaxRange(h.note))
      tv.moveLeftAndModifySelection(nil)
      #expect(h.selection == h.note)

      let above = h.note.location - 5
      h.caret(above)
      tv.setSelectedRange(
        NSRange(location: above, length: 8), affinity: .downstream, stillSelecting: true)
      #expect(h.selection == NSRange(location: above, length: NSMaxRange(h.note) - above))
      tv.setSelectedRange(
        NSRange(location: above, length: 8), affinity: .downstream, stillSelecting: false)
      #expect(h.selection == NSRange(location: above, length: NSMaxRange(h.note) - above))

      // A selection that only abuts the block is left alone.
      h.select(NSRange(location: above, length: 5))
      #expect(h.selection == NSRange(location: above, length: 5))
    }

    // MARK: Delete

    @Test("Backspace / forward-delete select the embed first, then remove it as one undo step")
    func deleteSelectsThenDeletes() throws {
      for forward in [false, true] {
        let h = try MacEmbedHarness()
        let tv = h.textView
        let removal = EmbedSelection.deletionRange(for: h.note, in: h.original as NSString)
        #expect(removal == NSRange(location: h.note.location, length: h.note.length + 1))
        let expected = (h.original as NSString).replacingCharacters(in: removal, with: "")

        // First press, at the edge the key points into: selects, deletes nothing.
        h.caret(forward ? h.note.location : NSMaxRange(h.note))
        if forward { tv.deleteForward(nil) } else { tv.deleteBackward(nil) }
        #expect(h.string == h.original, "forward: \(forward)")
        #expect(h.selection == h.note, "forward: \(forward)")
        #expect(h.undo.registrations == 0, "forward: \(forward)")
        settleEventGroup()

        // Second press: removes the block plus the blank line after it.
        if forward { tv.deleteForward(nil) } else { tv.deleteBackward(nil) }
        settleEventGroup()
        #expect(h.string == expected, "forward: \(forward)")
        #expect(h.selection == NSRange(location: removal.location, length: 0))
        #expect(h.embeddedStarts.isEmpty)

        // One undo step brings everything back.
        #expect(h.undo.canUndo)
        h.undo.undo()
        #expect(h.string == h.original, "forward: \(forward)")
        #expect(!h.undo.canUndo, "forward: \(forward): more than one undo step")
        withExtendedLifetime(h) {}
      }
    }

    // MARK: Copy

    @Test("Copy with the embed selected writes the block's source")
    func copyWritesSource() throws {
      let h = try MacEmbedHarness()
      let tv = h.textView
      let pasteboard = NSPasteboard(name: NSPasteboard.Name("escribo.embed.copy.\(UUID())"))
      defer { pasteboard.releaseGlobally() }

      h.select(h.note)
      #expect(tv.writeSelection(to: pasteboard, types: tv.writablePasteboardTypes))
      #expect(pasteboard.string(forType: .string) == EmbedLayoutFixture.noteLines)

      // A selection extended onto the block copies the whole block's source.
      h.select(NSRange(location: h.note.location - 1, length: 3))
      pasteboard.clearContents()
      #expect(tv.writeSelection(to: pasteboard, types: tv.writablePasteboardTypes))
      #expect(pasteboard.string(forType: .string) == "\n" + EmbedLayoutFixture.noteLines)
    }

    // MARK: Typing veto

    @Test("Typing, Return, Tab and paste with the embed selected change nothing")
    func typingOverEmbedIsIgnored() throws {
      let h = try MacEmbedHarness()
      let tv = h.textView
      let pasteboard = NSPasteboard(name: NSPasteboard.Name("escribo.embed.paste.\(UUID())"))
      defer { pasteboard.releaseGlobally() }
      pasteboard.clearContents()
      pasteboard.setString("pasted\n", forType: .string)

      for selection in [h.note, NSRange(location: h.note.location - 1, length: h.note.length + 2)] {
        h.select(selection)
        h.type("x")
        #expect(h.string == h.original)
        tv.insertText("x", replacementRange: h.note)
        #expect(h.string == h.original)
        tv.insertNewline(nil)
        #expect(h.string == h.original)
        tv.insertTab(nil)
        #expect(h.string == h.original)
        _ = tv.readSelection(from: pasteboard, type: .string)
        #expect(h.string == h.original)
      }
      #expect(h.embeddedStarts == [h.note.location])

      // Non-vacuous: the same paste after the block edits.
      h.caret(NSMaxRange(h.note))
      #expect(tv.readSelection(from: pasteboard, type: .string))
      #expect(h.string != h.original)
    }

    // MARK: Start edge

    @Test("At the embed's start edge only line-terminated input inserts; nothing joins its first line")
    func startEdgeRule() throws {
      let h = try MacEmbedHarness()
      let tv = h.textView

      // However the caret got there: set directly, or arrived by an arrow key.
      h.caret(h.note.location)
      h.type("x")
      #expect(h.string == h.original)
      h.caret(NSMaxRange(h.note))
      tv.moveLeft(nil)
      #expect(h.selection == NSRange(location: h.note.location, length: 0))
      h.type("x")
      tv.insertTab(nil)
      #expect(h.string == h.original)

      // A selection ending at the start edge, replaced by text, would join too.
      h.select(NSRange(location: h.note.location - 3, length: 3))
      h.type("x")
      #expect(h.string == h.original)

      // Paste there is ignored, even text ending in a newline (the iOS rule).
      let pasteboard = NSPasteboard(name: NSPasteboard.Name("escribo.embed.edge.\(UUID())"))
      defer { pasteboard.releaseGlobally() }
      pasteboard.clearContents()
      pasteboard.setString("pasted\n", forType: .string)
      h.caret(h.note.location)
      _ = tv.readSelection(from: pasteboard, type: .string)
      #expect(h.string == h.original)

      // Typed text ending in a line break is inserted above the block, which stays whole.
      h.caret(h.note.location)
      h.type("above\n")
      let typedAbove = (h.original as NSString).replacingCharacters(
        in: NSRange(location: h.note.location, length: 0), with: "above\n")
      #expect(h.string == typedAbove)
      #expect(h.embeddedStarts.count == 1)
      tv.undoManager?.undo()
      settleEventGroup()
      #expect(h.string == h.original)

      // Backspace at the start edge is allowed when it only removes a blank line above...
      h.caret(h.note.location)
      tv.deleteBackward(nil)
      let blankRemoved = (h.original as NSString).replacingCharacters(
        in: NSRange(location: h.note.location - 1, length: 1), with: "")
      #expect(h.string == blankRemoved)
      #expect(h.embeddedStarts == [h.note.location - 1])
      // ...and ignored when it would pull the block's first line onto a non-empty line.
      tv.deleteBackward(nil)
      #expect(h.string == blankRemoved)
      tv.undoManager?.undo()
      settleEventGroup()
      #expect(h.string == h.original)

      // Return pushes the block down a line and keeps it whole and embedded.
      h.caret(h.note.location)
      tv.insertNewline(nil)
      let pushed = (h.original as NSString).replacingCharacters(
        in: NSRange(location: h.note.location, length: 0), with: "\n")
      #expect(h.string == pushed)
      #expect(h.embeddedStarts == [h.note.location + 1])

      // Non-vacuous: typing at the end edge (the next line's start) edits.
      h.caret(NSMaxRange(h.note) + 1)
      h.type("y")
      #expect(h.string != pushed)
      #expect(h.embeddedStarts == [h.note.location + 1])
    }

    // MARK: Click

    /// Puts the editor in a window and returns the note row's centre in window coordinates.
    private func windowed(_ h: MacEmbedHarness) throws -> (NSWindow, CGRect) {
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 600, height: 800), styleMask: [.titled],
        backing: .buffered, defer: true)
      window.isReleasedWhenClosed = false
      window.contentView = h.editor.scrollView
      _ = h.layout.layout()
      let controller = try #require(h.editor.embedLayout)
      let block = try #require(h.editor.coordinator.embeddedBlocks.first)
      let row = try #require(controller.rowRect(for: block))
      return (window, row)
    }

    private func click(_ h: MacEmbedHarness, _ window: NSWindow, at point: CGPoint) {
      let location = h.textView.convert(point, to: nil)
      guard
        let event = NSEvent.mouseEvent(
          with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0,
          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
          pressure: 1)
      else {
        Issue.record("could not make a mouse event")
        return
      }
      h.textView.mouseDown(with: event)
    }

    @Test("A click anywhere on the row selects the whole block and activates it once")
    func clickSelectsAndActivatesOnce() throws {
      let h = try MacEmbedHarness()
      let (window, row) = try windowed(h)
      defer { window.close() }

      let points = [
        CGPoint(x: row.midX, y: row.midY),
        CGPoint(x: row.minX + 2, y: row.minY + 2),
        CGPoint(x: row.maxX - 2, y: row.maxY - 2),
      ]
      for (i, point) in points.enumerated() {
        h.caret(0)
        click(h, window, at: point)
        #expect(h.selection == h.note, "click \(i) at \(point)")
        #expect(h.activations.count == i + 1, "click \(i): activations \(h.activations.count)")
        #expect(h.activations.last?.range == h.layout.note)
      }

      // A point beside the row is not a row click: AppKit handles it.
      #expect(!h.editor.handleEmbedClick(at: CGPoint(x: row.midX, y: row.minY - 20)))
      #expect(h.activations.count == points.count)
    }

    /// A one-paragraph note long enough to wrap to several lines under its two-line row —
    /// the shape of a storyboard shot note — followed by a blank run.
    nonisolated static let longWrappingNote =
      "INT. HOUSE - DAY\n\nBob waits by the door.\n\n"
      + "[["
      + String(repeating: "A long one-line note that wraps across many visual lines. ", count: 8)
      + "]]\n\n\nJane enters.\n"

    @Test("A click anywhere on a long note's row selects it and activates it once")
    func clickOnLongNoteRow() throws {
      let h = try MacEmbedHarness(text: Self.longWrappingNote)
      let (window, row) = try windowed(h)
      defer { window.close() }

      var clicks = 0
      for fy in stride(from: 0.05, through: 0.95, by: 0.15) {
        for fx in [0.1, 0.5, 0.9] {
          let point = CGPoint(x: row.minX + row.width * fx, y: row.minY + row.height * fy)
          h.caret(0)
          click(h, window, at: point)
          clicks += 1
          #expect(h.selection == h.note, "click at \(point) in \(row)")
          #expect(h.activations.count == clicks, "click at \(point): not activated")
        }
      }
      #expect(h.activations.allSatisfy { $0.range == h.layout.note })
    }

    /// The selection highlight's rectangles for `range`, in text-container coordinates.
    private func selectionRects(_ h: MacEmbedHarness, _ range: NSRange) throws -> [CGRect] {
      let manager = try #require(h.textView.textLayoutManager)
      let content = try #require(manager.textContentManager)
      let start = try #require(
        content.location(content.documentRange.location, offsetBy: range.location))
      let end = try #require(content.location(start, offsetBy: range.length))
      var rects: [CGRect] = []
      manager.enumerateTextSegments(
        in: try #require(NSTextRange(location: start, end: end)), type: .selection, options: []
      ) { _, rect, _, _ in
        rects.append(rect)
        return true
      }
      return rects
    }

    /// The hidden text under a row is laid out at its natural size; a long note's wrap used
    /// to give the selection a highlight that reached over the paragraphs below the row.
    @Test(
      "A selected row's highlight stays inside the row",
      arguments: [EmbedLayoutFixture.text, MacEmbedBehaviourTests.longWrappingNote])
    func selectionHighlightStaysInRow(text: String) throws {
      let h = try MacEmbedHarness(text: text)
      let (window, row) = try windowed(h)
      defer { window.close() }
      let origin = EmbedLayoutController.containerOrigin(of: h.textView)

      let rects = try selectionRects(h, h.note).map { $0.offsetBy(dx: origin.x, dy: origin.y) }
      #expect(!rects.isEmpty)
      for rect in rects where !rect.isEmpty {
        #expect(
          rect.minY >= row.minY - 0.5 && rect.maxY <= row.maxY + 0.5, "\(rect) vs row \(row)")
      }
    }

    @Test("Programmatic selection never activates an embed")
    func programmaticSelectionDoesNotActivate() throws {
      let h = try MacEmbedHarness()
      h.select(h.note)
      h.caret(h.note.location + 2)
      h.select(NSRange(location: h.note.location - 1, length: 3))
      h.textView.moveDown(nil)
      h.textView.selectAll(nil)
      #expect(h.activations.isEmpty)
      #expect(h.actions.isEmpty)
    }

    // MARK: Option-Return

    @Test("Option-Return with the embed selected sends Edit as Text to the host")
    func optionReturnSendsEditAsText() throws {
      let h = try MacEmbedHarness()
      let tv = h.textView
      #expect(EscriboEmbed.Action.editAsTextID == "escribo.editAsText")

      h.select(h.note)
      tv.insertNewlineIgnoringFieldEditor(nil)
      #expect(h.actions.count == 1)
      #expect(h.actions.first?.block.range == h.layout.note)
      #expect(h.actions.first?.id == EscriboEmbed.Action.editAsTextID)
      #expect(h.string == h.original)

      // Through the key binding, as the keyboard delivers it.
      let event = try #require(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [.option], timestamp: 0,
          windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
          isARepeat: false, keyCode: 36))
      tv.interpretKeyEvents([event])
      #expect(h.actions.count == 2)
      #expect(h.string == h.original)

      // Nothing selected: no action.
      h.caret(0)
      tv.insertNewlineIgnoringFieldEditor(nil)
      #expect(h.actions.count == 2)
      #expect(h.activations.isEmpty)
    }

    // MARK: Undo / redo

    @Test("Undo restores the deleted embed's text and embed, selected; redo removes it again")
    func undoRestoresEmbedSelected() throws {
      let h = try MacEmbedHarness()
      let tv = h.textView
      h.select(h.note)
      tv.deleteBackward(nil)
      settleEventGroup()
      let deleted = h.string
      #expect(deleted != h.original)
      #expect(h.embeddedStarts.isEmpty)

      for round in 0..<2 {
        h.undo.undo()
        #expect(h.string == h.original, "round \(round)")
        #expect(h.embeddedStarts == [h.note.location], "round \(round)")
        #expect(h.selection == h.note, "round \(round)")
        let controller = try #require(h.editor.embedLayout)
        let block = try #require(h.editor.coordinator.embeddedBlocks.first)
        #expect(controller.rowRect(for: block) != nil, "round \(round): not drawn as a row")

        #expect(h.undo.canRedo)
        h.undo.redo()
        #expect(h.string == deleted, "round \(round)")
        #expect(h.embeddedStarts.isEmpty, "round \(round)")
      }
    }

    // MARK: Typing above

    @Test("Typing above a multi-line embed keeps it drawn and never falls back to a full scan")
    func typingAboveKeepsEmbedWithoutFullScan() throws {
      let h = try MacEmbedHarness()
      let coordinator = h.editor.coordinator
      let controller = try #require(h.editor.embedLayout)
      let fullScans = coordinator.fullScanCount
      let lineEnd = (h.original as NSString).range(of: "door.").upperBound

      for i in 0..<20 {
        h.caret(lineEnd + i)
        h.type("x")
        #expect(coordinator.fullScanCount == fullScans, "keystroke \(i + 1) fell back to a full scan")
        #expect(h.embeddedStarts == [h.note.location + i + 1], "keystroke \(i + 1)")
      }
      #expect((h.string as NSString).length == (h.original as NSString).length + 20)

      _ = h.layout.layout()
      let block = try #require(coordinator.embeddedBlocks.first)
      let row = try #require(controller.rowRect(for: block))
      #expect(abs(row.height - controller.rowHeight) < 0.5)
    }

    // MARK: Find hook

    @Test("A find-originated selection passes through unsnapped")
    func findSelectionPassesThrough() throws {
      let h = try MacEmbedHarness()
      let inside = NSRange(location: h.note.location + 2, length: 4)
      h.textView.isApplyingFindSelection = true
      h.select(inside)
      h.textView.isApplyingFindSelection = false
      #expect(h.selection == inside)
      h.select(inside)
      #expect(h.selection == h.note)
    }
  }
#endif
