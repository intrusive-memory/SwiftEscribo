#if os(iOS)
  import EscriboCore
  import Foundation
  import Testing
  import UIKit

  @testable import SwiftEscribo

  // SPIKE — throwaway tests for the atomic block-embed experiment (iOS column).

  /// One laid-out paragraph: its UTF-16 offset, frame, and fragment class.
  struct SpikeIOSLaidOutParagraph {
    var offset: Int
    var frame: CGRect
    var fragment: NSTextLayoutFragment
  }

  @MainActor
  struct SpikeIOSHarness {
    let editor: EscriboTextView
    let note: NSRange

    static let content = SpikeEmbedContent(
      symbolName: "note.text", title: "Note", subtitle: "First line of the note",
      badge: "3 lines", accessibilityLabel: "Note", accessibilityValue: "First line of the note")

    init(mechanism: SpikeCollapseMechanism = .fragmentFrameOverride, scale: Double = 1) throws {
      let editor = EscriboTextView(language: .fountain, theme: .fountainLight)
      editor.textView.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
      if scale != 1 {
        editor.coordinator.styler.environment.metrics = FontMetrics(pointSizeScale: scale)
      }
      editor.applyExternalText(BlockEmbedSpikeFixture.text)
      editor.coordinator.restyleEverything()
      editor.spikeEmbeds.mechanism = mechanism
      let block = try #require(editor.coordinator.documentBlocks.first { $0.kind == .note })
      self.editor = editor
      self.note = NSRange(location: block.range.lowerBound, length: block.range.count)
    }

    func embed() {
      editor.spikeSetEmbed(Self.content, forBlockStartingAt: note.location)
    }

    /// Every paragraph's layout fragment, with layout ensured over the whole document.
    func layout() -> [SpikeIOSLaidOutParagraph] {
      guard let tlm = editor.textView.textLayoutManager,
        let content = tlm.textContentManager
      else { return [] }
      tlm.ensureLayout(for: tlm.documentRange)
      var result: [SpikeIOSLaidOutParagraph] = []
      tlm.enumerateTextLayoutFragments(from: tlm.documentRange.location, options: [.ensuresLayout]) {
        fragment in
        let offset = content.offset(
          from: content.documentRange.location, to: fragment.rangeInElement.location)
        result.append(
          SpikeIOSLaidOutParagraph(offset: offset, frame: fragment.layoutFragmentFrame, fragment: fragment))
        return true
      }
      return result
    }

    func noteParagraphs(_ laid: [SpikeIOSLaidOutParagraph]) -> [SpikeIOSLaidOutParagraph] {
      laid.filter { $0.offset >= note.location && $0.offset < NSMaxRange(note) }
    }

    /// Total vertical extent the note's paragraphs occupy (top of first to bottom of last).
    func noteExtent(_ laid: [SpikeIOSLaidOutParagraph]) -> CGFloat {
      let paras = noteParagraphs(laid)
      guard let first = paras.first, let last = paras.last else { return 0 }
      return last.frame.maxY - first.frame.minY
    }
  }

  @MainActor
  @Suite("Block embed spike — iOS draw", .serialized, .timeLimit(.minutes(2)))
  struct BlockEmbedSpikeIOSTests {

    // MARK: - Row 1: draw

    @Test("row 1: the embed draws as one fixed-height custom row; the rest lays out normally")
    func row1FixedHeightRow() throws {
      let h = try SpikeIOSHarness()
      // Unlike NSTextView, UITextView already holds the layout-manager delegate slot (its own
      // `_UITextKit2LayoutController`); the spike chains to it rather than replacing it.
      let displaced = h.editor.spikeEmbeds.displacedDelegates
      print("SPIKE iOS displaced delegates: \(displaced)")
      #expect(displaced.allSatisfy { $0.hasPrefix("layoutManager:") })
      #expect(h.editor.spikeEmbeds.forwardedLayoutDelegate != nil || displaced.isEmpty)
      let before = h.layout()
      h.embed()
      let after = h.layout()
      let rowHeight = h.editor.spikeEmbeds.rowHeight

      #expect(before.count == after.count)
      let paras = h.noteParagraphs(after)
      let first = try #require(paras.first)
      let row = try #require(first.fragment as? SpikeEmbedRowFragment)
      #expect(abs(first.frame.height - rowHeight) <= 0.5)
      #expect(row.content == SpikeIOSHarness.content)
      // At the paragraph's leading indent, read from the real storage.
      let style = h.editor.textView.textStorage.attribute(
        .paragraphStyle, at: h.note.location, effectiveRange: nil) as? NSParagraphStyle
      #expect(row.indent == (style?.firstLineHeadIndent ?? 0))

      // Before the block: untouched. After: own heights kept.
      for (b, a) in zip(before, after) where a.offset < h.note.location {
        #expect(a.frame == b.frame)
        // Whatever UIKit's own delegate vends, unchanged.
        #expect(type(of: a.fragment) == type(of: b.fragment))
        #expect(!(a.fragment is SpikeEmbedFragment))
      }
      for (b, a) in zip(before, after) where a.offset >= NSMaxRange(h.note) {
        #expect(abs(a.frame.height - b.frame.height) <= 0.5)
        #expect(type(of: a.fragment) == type(of: b.fragment))
        #expect(!(a.fragment is SpikeEmbedFragment))
      }
      // Contiguous: every fragment starts where the previous one ends.
      for (prev, next) in zip(after, after.dropFirst()) {
        #expect(abs(next.frame.minY - prev.frame.maxY) <= 0.5, "gap before offset \(next.offset)")
      }

      // The row actually draws (symbol, two lines, badge) and puts pixels down.
      let side = CGSize(width: row.rowWidth, height: rowHeight)
      let image = UIGraphicsImageRenderer(size: side).image { ctx in
        row.draw(at: .zero, in: ctx.cgContext)
      }
      #expect(row.drawCount >= 1)
      #expect(Self.hasInk(image))

      // And through UITextView's own rendering, hosted in a window.
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
      window.addSubview(h.editor.textView)
      window.isHidden = false
      defer { window.isHidden = true }
      let drawsBefore = row.drawCount
      h.editor.textView.layoutIfNeeded()
      _ = UIGraphicsImageRenderer(bounds: h.editor.textView.bounds).image { ctx in
        h.editor.textView.layer.render(in: ctx.cgContext)
      }
      let live = try #require(h.noteParagraphs(h.layout()).first?.fragment as? SpikeEmbedRowFragment)
      print("SPIKE iOS plain fragment class: \(type(of: after[0].fragment))")
      print("SPIKE iOS row 1: view-render draw calls: \(live === row ? row.drawCount - drawsBefore : live.drawCount)")
    }

    @Test("row 1: zoom (pointSizeScale 2) scales the row, and it survives the coordinator's restyle")
    func row1ZoomScalesRow() throws {
      let h = try SpikeIOSHarness()
      h.embed()
      let baseline = try #require(h.noteParagraphs(h.layout()).first)
      #expect(baseline.fragment is SpikeEmbedRowFragment)

      // Zoom the way the package does: new metrics, then the coordinator rewrites every
      // attribute (paragraph styles included) into storage.
      h.editor.coordinator.styler.environment.metrics = FontMetrics(pointSizeScale: 2)
      h.editor.coordinator.restyleEverything()

      let zoomed = h.layout()
      let first = try #require(h.noteParagraphs(zoomed).first)
      #expect(first.fragment is SpikeEmbedRowFragment)
      #expect(first.frame.height > 1.5 * baseline.frame.height)
      #expect(abs(h.noteExtent(zoomed) - first.frame.height) <= 0.5)

      // A harness built at 2× from the start agrees.
      let h2 = try SpikeIOSHarness(scale: 2)
      h2.embed()
      let fresh = try #require(h2.noteParagraphs(h2.layout()).first)
      #expect(abs(fresh.frame.height - first.frame.height) <= 0.5)
    }

    // MARK: - Row 2: storage untouched

    @Test("row 2: textStorage is byte-identical with the embed; find, copy-all and word count see the source")
    func row2StorageUntouched() throws {
      let h = try SpikeIOSHarness()
      let storage = h.editor.textView.textStorage
      let original = storage.string
      let originalData = Data(original.utf8)
      let originalAttrs = NSAttributedString(attributedString: storage)
      let restyles = h.editor.coordinator.restyleCount

      h.embed()
      _ = h.layout()

      #expect(Data(storage.string.utf8) == originalData)
      #expect(storage.string == BlockEmbedSpikeFixture.text)
      #expect(h.editor.textView.text == BlockEmbedSpikeFixture.text)
      // Not even attributes moved, and the coordinator was never asked to restyle.
      #expect(storage.isEqual(to: originalAttrs))
      #expect(h.editor.coordinator.restyleCount == restyles)

      // Find a note word through the storage string.
      let found = (storage.string as NSString).range(of: "second line")
      #expect(found.location != NSNotFound)
      #expect(NSLocationInRange(found.location, h.note))

      // Word count over the source.
      func words(_ s: String) -> Int {
        var n = 0
        s.enumerateSubstrings(in: s.startIndex..., options: .byWords) { _, _, _, _ in n += 1 }
        return n
      }
      #expect(words(storage.string) == words(BlockEmbedSpikeFixture.text))
      #expect(words(storage.string) > 0)

      // Copy-all: what UITextView's `copy(_:)` writes is the text it vends for the selected
      // range. `copy(_:)` always targets the system general pasteboard (it cannot be
      // redirected to a named one), and reading `UIPasteboard.general` from the simulator test
      // host blocks indefinitely on pasteboard services, so the test asserts the copy path's
      // source — the selected range's plain and attributed text — instead of the pasteboard.
      let tv = h.editor.textView
      tv.selectAll(nil)
      let all = try #require(tv.selectedTextRange)
      #expect(tv.text(in: all) == BlockEmbedSpikeFixture.text)
      #expect(tv.attributedText.attributedSubstring(from: tv.selectedRange).string == BlockEmbedSpikeFixture.text)

      // And after a full restyle (the coordinator writes paragraph attributes), still so.
      h.editor.coordinator.restyleEverything()
      #expect(storage.string == BlockEmbedSpikeFixture.text)
      #expect(h.noteParagraphs(h.layout()).first?.fragment is SpikeEmbedRowFragment)
    }

    // MARK: - Row 10: multi-line block

    @Test("row 10: the three note paragraphs (three layout fragments) together occupy exactly one row")
    func row10MultiLineCollapse() throws {
      let h = try SpikeIOSHarness()
      let unembedded = h.noteExtent(h.layout())
      h.editor.textView.layoutIfNeeded()
      let usedBefore = h.editor.textView.textLayoutManager?.usageBoundsForTextContainer.height ?? 0
      h.embed()
      let laid = h.layout()
      let paras = h.noteParagraphs(laid)
      let rowHeight = h.editor.spikeEmbeds.rowHeight

      #expect(paras.count == 3)
      #expect(paras.first?.fragment is SpikeEmbedRowFragment)
      for p in paras.dropFirst() {
        #expect(p.fragment is SpikeEmbedCollapsedFragment)
        #expect(p.frame.height == 0)
      }
      #expect(abs(h.noteExtent(laid) - rowHeight) <= 0.5)
      // Non-vacuous: un-embedded, the note is three lines tall, not one row.
      #expect(abs(unembedded - rowHeight) > 0.5)

      // The paragraph after the block starts right below the row.
      let next = try #require(laid.first { $0.offset == NSMaxRange(h.note) })
      let first = try #require(paras.first)
      #expect(abs(next.frame.minY - (first.frame.minY + rowHeight)) <= 0.5)

      // The layout manager's used height (what UITextView sizes its content from) shrinks by
      // what the block gave up.
      h.editor.textView.layoutIfNeeded()
      let usedAfter = h.editor.textView.textLayoutManager?.usageBoundsForTextContainer.height ?? 0
      #expect(abs((usedBefore - usedAfter) - (unembedded - rowHeight)) <= 0.5)
    }

    @Test("row 10: mechanism comparison — only the frame override collapses N fragments without a storage edit")
    func row10MechanismComparison() throws {
      var extents: [SpikeCollapseMechanism: CGFloat] = [:]
      var rowHeight: CGFloat = 0
      for mechanism in SpikeCollapseMechanism.allCases {
        let h = try SpikeIOSHarness(mechanism: mechanism)
        // The realistic case: the document is already laid out when the host embeds.
        _ = h.layout()
        h.embed()
        extents[mechanism] = h.noteExtent(h.layout())
        rowHeight = h.editor.spikeEmbeds.rowHeight
      }
      print("SPIKE iOS row 10 extents: \(extents), rowHeight \(rowHeight)")
      // Draw-only keeps three line heights.
      #expect(abs((extents[.fragmentDrawOnly] ?? 0) - rowHeight) > 0.5)
      // The frame override collapses to one row.
      #expect(abs((extents[.fragmentFrameOverride] ?? 0) - rowHeight) <= 0.5)
      // The content-storage paragraph is never re-vended without a storage edit.
      #expect(abs((extents[.contentStorageParagraph] ?? 0) - rowHeight) > 0.5)
    }

    // MARK: - Rows 3–7: atomic behaviour

    /// True when `location` is strictly inside `range` (an edge is not inside).
    static func strictlyInside(_ location: Int, _ range: NSRange) -> Bool {
      location > range.location && location < NSMaxRange(range)
    }

    /// One arrow press the way UIKit's text-input navigation computes it: the next position
    /// in `direction` from the caret (`UITextInput.position(from:in:offset:)`, which for
    /// Up/Down is geometry-based), committed through the `selectedTextRange` setter.
    /// Returns the proposed (pre-filter) offset too, so tests can show UIKit did propose a
    /// position inside the block.
    @discardableResult
    static func arrow(_ tv: UITextView, _ direction: UITextLayoutDirection) -> (proposed: Int?, landed: Int) {
      guard let caret = tv.selectedTextRange?.end,
        let next = tv.position(from: caret, in: direction, offset: 1)
      else { return (nil, tv.selectedRange.location) }
      let proposed = tv.offset(from: tv.beginningOfDocument, to: next)
      tv.selectedTextRange = tv.textRange(from: next, to: next)
      return (proposed, tv.selectedRange.location)
    }

    /// Shift-arrow: extends the selection's moving end by one position in `direction`.
    static func extend(_ tv: UITextView, anchor: Int, head: Int, _ direction: UITextLayoutDirection) -> NSRange {
      let begin = tv.beginningOfDocument
      guard let headPos = tv.position(from: begin, offset: head),
        let next = tv.position(from: headPos, in: direction, offset: 1),
        let anchorPos = tv.position(from: begin, offset: anchor)
      else { return tv.selectedRange }
      let n = tv.offset(from: begin, to: next)
      tv.selectedTextRange =
        n >= anchor ? tv.textRange(from: anchorPos, to: next) : tv.textRange(from: next, to: anchorPos)
      return tv.selectedRange
    }

    @Test("row 3: left/right (position(from:in:offset:) + selectedTextRange) step over the block; never inside")
    func row3LeftRightStepOver() throws {
      let h = try SpikeIOSHarness()
      h.embed()
      _ = h.layout()
      let tv = h.editor.textView
      let note = h.note
      let length = (tv.text as NSString).length

      tv.selectedRange = NSRange(location: note.location, length: 0)
      let right = Self.arrow(tv, .right)
      #expect(right.proposed == note.location + 1)  // UIKit proposes a position inside
      #expect(tv.selectedRange == NSRange(location: NSMaxRange(note), length: 0))
      Self.arrow(tv, .left)
      #expect(tv.selectedRange == NSRange(location: note.location, length: 0))

      tv.selectedRange = NSRange(location: 0, length: 0)
      var visited: [Int] = []
      for _ in 0..<(length + 2) { visited.append(Self.arrow(tv, .right).landed) }
      for _ in 0..<(length + 2) { visited.append(Self.arrow(tv, .left).landed) }
      #expect(!visited.contains { Self.strictlyInside($0, note) })
      #expect(visited.contains(note.location) && visited.contains(NSMaxRange(note)))
      #expect(visited.contains(length) && visited.contains(0))
    }

    @Test("row 3: up/down from the adjacent lines land before/after the block; never inside")
    func row3UpDownStepOver() throws {
      let h = try SpikeIOSHarness()
      h.embed()
      _ = h.layout()
      let tv = h.editor.textView
      let note = h.note
      let length = (tv.text as NSString).length

      // Down from the blank line just above the block.
      tv.selectedRange = NSRange(location: note.location - 1, length: 0)
      let down = Self.arrow(tv, .down)
      print("SPIKE iOS row 3: down from \(note.location - 1) proposed \(String(describing: down.proposed)) → \(down.landed); note \(note)")
      #expect(down.landed == note.location || down.landed == NSMaxRange(note))
      if down.landed == note.location {
        let again = Self.arrow(tv, .down)
        print("SPIKE iOS row 3: second down proposed \(String(describing: again.proposed)) → \(again.landed)")
        #expect(again.landed == NSMaxRange(note) || again.landed > NSMaxRange(note))
      }
      // Up from the blank line just below the block.
      tv.selectedRange = NSRange(location: NSMaxRange(note), length: 0)
      let up = Self.arrow(tv, .up)
      print("SPIKE iOS row 3: up from \(NSMaxRange(note)) proposed \(String(describing: up.proposed)) → \(up.landed)")
      #expect(up.landed == note.location || up.landed < note.location)
      #expect(!Self.strictlyInside(up.landed, note))

      // Walk down from the top and up from the bottom: never inside, and the walk crosses.
      tv.selectedRange = NSRange(location: 0, length: 0)
      var downs: [Int] = []
      for _ in 0..<12 { downs.append(Self.arrow(tv, .down).landed) }
      #expect(!downs.contains { Self.strictlyInside($0, note) }, "down: \(downs)")
      #expect(downs.contains { $0 > NSMaxRange(note) }, "down never got past: \(downs)")

      tv.selectedRange = NSRange(location: length, length: 0)
      var ups: [Int] = []
      for _ in 0..<12 { ups.append(Self.arrow(tv, .up).landed) }
      #expect(!ups.contains { Self.strictlyInside($0, note) }, "up: \(ups)")
      #expect(ups.contains { $0 < note.location }, "up never got past: \(ups)")
      print("SPIKE iOS row 3 walks: down \(downs) up \(ups)")
    }

    @Test("row 3: a tap inside the row (closestPosition(to:)) lands the caret on one of the block's edges")
    func row3TapLandsOnEdge() throws {
      let h = try SpikeIOSHarness()
      h.embed()
      let laid = h.layout()
      let tv = h.editor.textView
      let note = h.note
      let row = try #require(h.noteParagraphs(laid).first)
      let inset = tv.textContainerInset

      let points = [
        CGPoint(x: row.frame.midX, y: row.frame.midY),
        CGPoint(x: row.frame.minX + 4, y: row.frame.minY + 2),
        CGPoint(x: row.frame.maxX - 4, y: row.frame.maxY - 2),
      ]
      var rawInside = 0
      for point in points {
        let viewPoint = CGPoint(x: point.x + inset.left, y: point.y + inset.top)
        let position = try #require(tv.closestPosition(to: viewPoint))
        let index = tv.offset(from: tv.beginningOfDocument, to: position)
        if Self.strictlyInside(index, note) { rawInside += 1 }
        for start in [0, (tv.text as NSString).length] {
          tv.selectedRange = NSRange(location: start, length: 0)
          tv.selectedTextRange = tv.textRange(from: position, to: position)
          let loc = tv.selectedRange.location
          #expect(tv.selectedRange.length == 0)
          #expect(!Self.strictlyInside(loc, note), "tap index \(index) → \(loc)")
          #expect(loc == note.location || loc == NSMaxRange(note) || !NSLocationInRange(index, note))
        }
      }
      print("SPIKE iOS row 3 tap: \(rawInside)/\(points.count) raw hits inside")
      // Non-vacuous: UIKit's own hit-testing does find positions inside the row.
      #expect(rawInside > 0)
    }

    @Test("row 3/row 4: hardware-keyboard arrows (UIKit's private _move*:withHistory:) reach the selection filter")
    func row3HardwareArrowRoute() throws {
      let h = try SpikeIOSHarness()
      h.embed()
      _ = h.layout()
      let tv = h.editor.textView
      let note = h.note
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
      window.addSubview(tv)
      window.isHidden = false
      defer { window.isHidden = true }
      _ = tv.becomeFirstResponder()

      // UIKit's arrow-key commands: what the text view itself declares.
      let commands = (tv.keyCommands ?? []).compactMap { $0.input }
      print("SPIKE iOS row 3: UITextView.keyCommands inputs: \(commands)")

      // The private UITextInput movement UIKit's keyboard layer calls for hardware arrows.
      typealias Move = @convention(c) (AnyObject, Selector, Bool, AnyObject?) -> AnyObject?
      var routed: [String: (sets: Int, landed: Int)] = [:]
      for (name, start) in [
        ("_moveRight:withHistory:", note.location), ("_moveLeft:withHistory:", NSMaxRange(note)),
        ("_moveDown:withHistory:", note.location - 1), ("_moveUp:withHistory:", NSMaxRange(note)),
      ] {
        let sel = NSSelectorFromString(name)
        guard tv.responds(to: sel) else {
          print("SPIKE iOS row 3: \(name) not implemented")
          continue
        }
        tv.selectedRange = NSRange(location: start, length: 0)
        let before = tv.spikeSelectedTextRangeSets
        let fn = unsafeBitCast(tv.method(for: sel), to: Move.self)
        _ = fn(tv, sel, false, nil)
        routed[name] = (tv.spikeSelectedTextRangeSets - before, tv.selectedRange.location)
      }
      print("SPIKE iOS row 3: private arrow routes (setter calls, landed): \(routed); note \(note)")
      // Observed on iOS 26.5: all four exist and each commits through the public
      // `selectedTextRange` setter exactly once, so the filter sees hardware arrows too.
      #expect(routed.count == 4)
      for (name, result) in routed {
        #expect(result.sets >= 1, "\(name) bypassed the selectedTextRange setter")
        #expect(!Self.strictlyInside(result.landed, note), "\(name) landed inside at \(result.landed)")
      }
      #expect(routed["_moveRight:withHistory:"]?.landed == NSMaxRange(note))
      #expect(routed["_moveLeft:withHistory:"]?.landed == note.location)

      // Shift-arrow through the same private route (extending = true) selects the block whole.
      let sel = NSSelectorFromString("_moveRight:withHistory:")
      if tv.responds(to: sel) {
        tv.selectedRange = NSRange(location: note.location, length: 0)
        let fn = unsafeBitCast(tv.method(for: sel), to: Move.self)
        _ = fn(tv, sel, true, nil)
        print("SPIKE iOS row 4: _moveRight extending from \(note.location) → \(tv.selectedRange)")
        #expect(tv.selectedRange == note)
      }
    }

    @Test("row 4: extending selections that touch the block grow to cover all of it")
    func row4ExtendSelectsWhole() throws {
      let h = try SpikeIOSHarness()
      h.embed()
      _ = h.layout()
      let tv = h.editor.textView
      let note = h.note

      // Shift-right from the start edge, shift-left from the end edge.
      #expect(Self.extend(tv, anchor: note.location, head: note.location, .right) == note)
      #expect(Self.extend(tv, anchor: NSMaxRange(note), head: NSMaxRange(note), .left) == note)

      // From the blank line above: the second shift-right touches the block.
      let a = note.location - 1
      #expect(Self.extend(tv, anchor: a, head: a, .right) == NSRange(location: a, length: 1))
      let sel = Self.extend(tv, anchor: a, head: a + 1, .right)
      #expect(sel == NSRange(location: a, length: NSMaxRange(note) - a))

      // Shift-down from above the block, shift-up from below it.
      tv.selectedRange = NSRange(location: a, length: 0)
      let downSel = Self.extend(tv, anchor: a, head: a, .down)
      print("SPIKE iOS row 4: shift-down from \(a) → \(downSel); note \(note)")
      #expect(!Self.strictlyInside(downSel.location, note) && !Self.strictlyInside(NSMaxRange(downSel), note))
      let b = NSMaxRange(note)
      let upSel = Self.extend(tv, anchor: b, head: b, .up)
      print("SPIKE iOS row 4: shift-up from \(b) → \(upSel)")
      #expect(!Self.strictlyInside(upSel.location, note) && !Self.strictlyInside(NSMaxRange(upSel), note))

      // A drag (a range whose end moves into the block) — through both setters.
      tv.selectedRange = NSRange(location: note.location - 5, length: 8)
      #expect(tv.selectedRange == NSRange(location: note.location - 5, length: NSMaxRange(note) - (note.location - 5)))
      let below = NSMaxRange(note) + 3
      let begin = tv.beginningOfDocument
      let from = try #require(tv.position(from: begin, offset: NSMaxRange(note) - 2))
      let to = try #require(tv.position(from: begin, offset: below))
      tv.selectedTextRange = tv.textRange(from: from, to: to)
      #expect(tv.selectedRange == NSRange(location: note.location, length: below - note.location))
    }

    @Test("row 5: Backspace with the block selected removes exactly deletionRange as one undo step")
    func row5DeleteWhole() throws {
      let h = try SpikeIOSHarness()
      h.embed()
      _ = h.layout()
      let tv = h.editor.textView
      // UITextView's undo manager comes from the responder chain: host it in a window.
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
      window.addSubview(tv)
      window.isHidden = false
      defer { window.isHidden = true }
      let undo = try #require(tv.undoManager)
      Self.settle()
      undo.removeAllActions()

      let original = tv.text ?? ""
      let removal = SpikeEmbedSelection.deletionRange(for: h.note, in: original as NSString)
      #expect(removal.length == h.note.length + 1)  // block plus the following blank line
      let expected = (original as NSString).replacingCharacters(in: removal, with: "")

      tv.selectedRange = h.note
      #expect(tv.selectedRange == h.note)
      tv.deleteBackward()
      Self.settle()

      #expect(tv.text == expected)
      #expect(h.editor.documentStorage.string == expected)
      #expect(h.editor.spikeEmbeds.registry.embeds.isEmpty)
      #expect(tv.selectedRange == NSRange(location: removal.location, length: 0))

      // One undo step restores the source exactly, and there is nothing further to undo.
      #expect(undo.canUndo)
      undo.undo()
      Self.settle()
      #expect(Array((tv.text ?? "").utf8) == Array(original.utf8))
      #expect(!undo.canUndo)

      // Non-vacuous: a Backspace with a partial selection of the block is vetoed.
      let h2 = try SpikeIOSHarness()
      h2.embed()
      _ = h2.layout()
      let tv2 = h2.editor.textView
      let before = tv2.text
      // The filter grows a partial selection to the whole block, so put the caret at the
      // block's end edge: plain Backspace would remove its last terminator — vetoed.
      tv2.selectedRange = NSRange(location: NSMaxRange(h2.note), length: 0)
      tv2.deleteBackward()
      #expect(tv2.text == before)
    }

    @Test("row 6: copy with the block selected — the copy source is the original characters")
    func row6CopySource() throws {
      let h = try SpikeIOSHarness()
      h.embed()
      _ = h.layout()
      let tv = h.editor.textView

      // `UITextView.copy(_:)` writes only to `UIPasteboard.general` (no named-pasteboard
      // route) and reading the general pasteboard from the simulator test host blocks on
      // pasteboard services, so this asserts what the copy path reads — the text vended for
      // the selected range — not the pasteboard itself.
      tv.selectedRange = h.note
      #expect(tv.selectedRange == h.note)
      #expect(tv.canPerformAction(#selector(UIResponderStandardEditActions.copy(_:)), withSender: nil))
      let range = try #require(tv.selectedTextRange)
      #expect(tv.text(in: range) == BlockEmbedSpikeFixture.noteLines)
      #expect(tv.attributedText.attributedSubstring(from: tv.selectedRange).string == BlockEmbedSpikeFixture.noteLines)

      // A selection that was extended onto the block copies the whole block's source.
      tv.selectedRange = NSRange(location: h.note.location - 1, length: 3)
      let wider = try #require(tv.selectedTextRange)
      #expect(tv.text(in: wider) == "\n" + BlockEmbedSpikeFixture.noteLines)
    }

    @Test("row 7: typing with the block selected changes nothing")
    func row7TypingIgnored() throws {
      let h = try SpikeIOSHarness()
      h.embed()
      _ = h.layout()
      let tv = h.editor.textView
      let original = tv.text

      tv.selectedRange = h.note
      tv.insertText("x")
      #expect(tv.text == original)
      tv.insertText("\n")  // Return goes through the package's own handler
      #expect(tv.text == original)
      tv.insertText("\t")
      #expect(tv.text == original)
      tv.setMarkedText("x", selectedRange: NSRange(location: 1, length: 0))
      #expect(tv.text == original)
      let sel = try #require(tv.selectedTextRange)
      tv.replace(sel, withText: "x")
      #expect(tv.text == original)

      // A wider selection containing the block, too.
      tv.selectedRange = NSRange(location: h.note.location - 1, length: h.note.length + 2)
      tv.insertText("x")
      #expect(tv.text == original)

      // Non-vacuous: typing at the block's start edge (outside it) still edits.
      tv.selectedRange = NSRange(location: h.note.location, length: 0)
      tv.insertText("x")
      #expect(tv.text != original)
    }

    // MARK: - Row 8: expand / collapse

    @Test("row 8: expand draws the block as text and lets the caret in; collapse restores the row and the snap")
    func row8ExpandCollapse() throws {
      let h = try SpikeIOSHarness()
      h.embed()
      let tv = h.editor.textView
      let note = h.note
      let inside = note.location + 5
      #expect(h.noteParagraphs(h.layout()).first?.fragment is SpikeEmbedRowFragment)

      // Expanded: UIKit's own fragments, ordinary heights, caret may enter.
      h.editor.spikeSetExpanded(true, forBlockStartingAt: note.location)
      let expanded = h.noteParagraphs(h.layout())
      #expect(expanded.count == 3)
      for p in expanded {
        #expect(!(p.fragment is SpikeEmbedFragment), "\(type(of: p.fragment))")
        #expect(p.frame.height > 0)
      }
      #expect(abs(h.noteExtent(h.layout()) - h.editor.spikeEmbeds.rowHeight) > 0.5)
      tv.selectedRange = NSRange(location: inside, length: 0)
      #expect(tv.selectedRange == NSRange(location: inside, length: 0))
      let step = Self.arrow(tv, .right)
      #expect(step.landed == inside + 1)
      #expect(h.editor.spikeEmbeds.accessibilityElements().isEmpty)

      // Collapsed again with the caret inside: the row returns and the caret is pushed out.
      h.editor.spikeSetExpanded(false, forBlockStartingAt: note.location)
      let collapsed = h.layout()
      #expect(h.noteParagraphs(collapsed).first?.fragment is SpikeEmbedRowFragment)
      #expect(abs(h.noteExtent(collapsed) - h.editor.spikeEmbeds.rowHeight) <= 0.5)
      #expect(!Self.strictlyInside(tv.selectedRange.location, note), "\(tv.selectedRange)")
      tv.selectedRange = NSRange(location: inside, length: 0)
      let loc = tv.selectedRange.location
      #expect(loc == note.location || loc == NSMaxRange(note))
      // The storage never moved through either toggle.
      #expect(tv.textStorage.string == BlockEmbedSpikeFixture.text)
    }

    // MARK: - Row 9: accessibility

    @Test("row 9: one accessibility element per embed, label/value from the host, activate fires the callback once")
    func row9Accessibility() throws {
      let h = try SpikeIOSHarness()
      let tv = h.editor.textView
      let before = tv.accessibilityElements ?? []
      #expect(!before.contains { $0 is SpikeEmbedAccessibilityElement })

      h.embed()
      _ = h.layout()
      var activations: [Int] = []
      h.editor.spikeEmbeds.onSpikeEmbedActivate = { activations.append($0) }

      let children = tv.accessibilityElements ?? []
      let elements = children.compactMap { $0 as? SpikeEmbedAccessibilityElement }
      #expect(elements.count == 1)
      let element = try #require(elements.first)
      #expect(element.accessibilityTraits.contains(.button))
      #expect(element.accessibilityLabel == SpikeIOSHarness.content.title)
      #expect(
        element.accessibilityValue
          == "\(SpikeIOSHarness.content.subtitle), \(SpikeIOSHarness.content.badge)")
      #expect((element.accessibilityContainer as AnyObject?) === tv)
      // Stable identity across queries, and visible through UIAccessibilityContainer's
      // count/index API (what VoiceOver walks), not only the array property.
      #expect((tv.accessibilityElements ?? []).contains { ($0 as AnyObject) === element })
      let count = tv.accessibilityElementCount()
      let indexed = (0..<max(0, count)).compactMap { tv.accessibilityElement(at: $0) as AnyObject? }
      print("SPIKE iOS row 9: textView.isAccessibilityElement = \(tv.isAccessibilityElement); container count \(count); indexed contains element: \(indexed.contains { $0 === element })")
      #expect(indexed.contains { $0 === element })

      // The element's frame is the row, in the text view's (content) coordinates.
      let row = try #require(h.noteParagraphs(h.layout()).first)
      let frame = element.accessibilityFrameInContainerSpace
      let inset = tv.textContainerInset
      #expect(abs(frame.minY - (row.frame.minY + inset.top)) <= 0.5)
      #expect(abs(frame.height - h.editor.spikeEmbeds.rowHeight) <= 0.5)
      #expect(frame.width > 0)

      // Hosted in a window, UIKit reports it in screen coordinates.
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
      window.addSubview(tv)
      window.isHidden = false
      defer { window.isHidden = true }
      tv.layoutIfNeeded()
      let screenFrame = element.accessibilityFrame
      let expected = tv.convert(frame, to: window.screen.coordinateSpace)
      #expect(
        abs(screenFrame.minX - expected.minX) <= 1 && abs(screenFrame.minY - expected.minY) <= 1,
        "screen \(screenFrame) vs \(expected)")
      #expect(abs(screenFrame.height - expected.height) <= 1)

      #expect(element.accessibilityActivate())
      #expect(activations == [h.note.location])

      // Expanded: no element.
      h.editor.spikeSetExpanded(true, forBlockStartingAt: h.note.location)
      #expect(!(tv.accessibilityElements ?? []).contains { $0 is SpikeEmbedAccessibilityElement })
    }

    // MARK: - Row 11: scroll and edit elsewhere

    @Test("row 11: typing above the block and scrolling keep the row drawn; ≤ 2 row-fragment creations per step")
    func row11ScrollAndEditStability() throws {
      let h = try SpikeIOSHarness()
      let tv = h.editor.textView
      // A short viewport, hosted in a window, so the document actually scrolls.
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
      tv.frame = window.bounds
      window.addSubview(tv)
      window.isHidden = false
      defer { window.isHidden = true }
      h.embed()
      _ = h.layout()
      tv.layoutIfNeeded()
      let controller = h.editor.spikeEmbeds
      let rowHeight = controller.rowHeight
      let original = tv.text ?? ""

      func checkRow(_ step: String, noteStart: Int) throws {
        tv.layoutIfNeeded()
        tv.textLayoutManager?.textViewportLayoutController.layoutViewport()
        let laid = h.layout()
        let paras = laid.filter { $0.offset >= noteStart && $0.offset < noteStart + h.note.length }
        let first = try #require(paras.first, "\(step): no note paragraphs")
        #expect(first.offset == noteStart, "\(step)")
        #expect(first.fragment is SpikeEmbedRowFragment, "\(step): \(type(of: first.fragment))")
        #expect(abs(first.frame.height - rowHeight) <= 0.5, "\(step): height \(first.frame.height)")
        let extent = (paras.last?.frame.maxY ?? 0) - first.frame.minY
        #expect(abs(extent - rowHeight) <= 0.5, "\(step): extent \(extent)")
      }

      // Insert 20 characters, one keystroke at a time, at the end of the action line above.
      let lineEnd = (original as NSString).range(of: "door.").upperBound
      var perEdit: [Int] = []
      for i in 0..<20 {
        let before = controller.rowFragmentCreations
        tv.selectedRange = NSRange(location: lineEnd + i, length: 0)
        tv.insertText("x")
        try checkRow("edit \(i + 1)", noteStart: h.note.location + i + 1)
        perEdit.append(controller.rowFragmentCreations - before)
      }
      #expect((tv.text as NSString).length == (original as NSString).length + 20)
      #expect(controller.registry.embeds.keys.sorted() == [h.note.location + 20])
      #expect(perEdit.allSatisfy { $0 <= 2 }, "row fragment creations per edit: \(perEdit)")
      let noteStart = h.note.location + 20

      // Scroll to the bottom and back, several times.
      tv.layoutIfNeeded()
      let maxY = tv.contentSize.height + tv.adjustedContentInset.bottom - tv.bounds.height
      #expect(maxY > 0, "content \(tv.contentSize) bounds \(tv.bounds)")
      var perScroll: [Int] = []
      for (i, y) in [maxY, 0, maxY / 2, maxY, 0].enumerated() {
        let before = controller.rowFragmentCreations
        tv.setContentOffset(CGPoint(x: 0, y: max(0, y)), animated: false)
        try checkRow("scroll \(i)", noteStart: noteStart)
        perScroll.append(controller.rowFragmentCreations - before)
      }
      #expect(perScroll.allSatisfy { $0 <= 2 }, "row fragment creations per scroll: \(perScroll)")
      print("SPIKE iOS row 11 creations per edit: \(perEdit); per scroll: \(perScroll); fallback scans: \(controller.fallbackScans); blocksSpanDocument: \(h.editor.coordinator.blocksSpanDocument)")
    }

    // MARK: - Screenshot evidence

    @Test("evidence: renders collapsed / expanded / zoom2x PNGs when ESCRIBO_SPIKE_EVIDENCE_DIR is set")
    func screenshotEvidence() throws {
      guard let dir = ProcessInfo.processInfo.environment["ESCRIBO_SPIKE_EVIDENCE_DIR"],
        !dir.isEmpty
      else { return }  // CI: no-op
      let url = URL(fileURLWithPath: dir, isDirectory: true)
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

      func render(_ h: SpikeIOSHarness, height: CGFloat, to name: String) throws {
        let tv = h.editor.textView
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: height))
        window.overrideUserInterfaceStyle = .light
        tv.overrideUserInterfaceStyle = .light
        tv.frame = window.bounds
        window.addSubview(tv)
        window.isHidden = false
        defer { window.isHidden = true }
        _ = h.layout()
        tv.layoutIfNeeded()
        tv.textLayoutManager?.textViewportLayoutController.layoutViewport()
        tv.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let size = tv.bounds.size
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
          UIColor.white.setFill()
          ctx.fill(CGRect(origin: .zero, size: size))
          // `drawHierarchy(in:afterScreenUpdates:)` renders nothing in the test host (no
          // scene); the layer tree does, and it is what UITextView's fragment views draw into.
          tv.layer.render(in: ctx.cgContext)
        }
        let png = try #require(image.pngData())
        try png.write(to: url.appendingPathComponent(name))
      }

      let collapsed = try SpikeIOSHarness()
      collapsed.embed()
      try render(collapsed, height: 300, to: "ios-embed-collapsed.png")

      let expanded = try SpikeIOSHarness()
      expanded.embed()
      expanded.editor.spikeSetExpanded(true, forBlockStartingAt: expanded.note.location)
      try render(expanded, height: 300, to: "ios-embed-expanded.png")

      let zoomed = try SpikeIOSHarness(scale: 2)
      zoomed.embed()
      try render(zoomed, height: 520, to: "ios-embed-zoom2x.png")
    }

    // MARK: - Helpers

    /// Lets the run loop close the current undo event group.
    static func settle() {
      _ = CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.02, false)
    }

    /// Whether any pixel in `image` is not fully transparent.
    static func hasInk(_ image: UIImage) -> Bool {
      guard let cg = image.cgImage else { return false }
      let width = cg.width
      let height = cg.height
      var pixels = [UInt8](repeating: 0, count: width * height * 4)
      guard
        let ctx = CGContext(
          data: &pixels, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
      return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] != 0 }
    }
  }
#endif
