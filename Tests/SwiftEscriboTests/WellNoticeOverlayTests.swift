import EscriboCore
import Foundation
import Testing

@testable import SwiftEscribo

#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

/// Sortie 17: the notice glyph is drawn and clickable (REQUIREMENTS.md § 2).
///
/// Same seams as `WellOverlayTests`: literal 20 pt lines, no layout, no window.
@MainActor
@Suite("Well notice — overlay drawing and click")
struct WellNoticeOverlayTests {

  /// `one` (line 0), blank (1), `# Heading` (2), blank (3), `two` (4).
  static let document = "one\n\n# Heading\n\ntwo"
  static let textEdge: CGFloat = 40
  static let lineHeight: CGFloat = 20

  #if os(iOS)
    static let sizeClass: WellLane.HorizontalSizeClass? = .regular
  #else
    static let sizeClass: WellLane.HorizontalSizeClass? = nil
  #endif

  private func makeEditor() -> EscriboTextView {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    editor.applyExternalText(Self.document)
    editor.coordinator.restyleEverything()
    let textEdge = Self.textEdge
    let lineHeight = Self.lineHeight

    var starts = [0]
    for (index, unit) in Self.document.utf16.enumerated() where unit == 0x0A {
      starts.append(index + 1)
    }
    let lineStarts = starts
    editor.coordinator.utf16Offset = { point in
      let line = Int((point.y / lineHeight).rounded(.down))
      guard line >= 0, line < lineStarts.count else { return nil }
      return lineStarts[line]
    }
    let overlay = editor.wellOverlay
    overlay.schedulesTicks = false
    overlay.reduceMotion = { true }
    overlay.geometry = WellGeometry(
      textEdge: { textEdge },
      lineFragmentRects: { range in
        lineStarts.enumerated()
          .filter { range.contains($0.element) }
          .map {
            CGRect(
              x: textEdge, y: CGFloat($0.offset) * lineHeight, width: 300, height: lineHeight)
          }
      })
    return editor
  }

  private func point(onLine line: Int) -> CGPoint {
    CGPoint(x: 120, y: CGFloat(line) * Self.lineHeight + Self.lineHeight / 2)
  }

  private func buttons(_ editor: EscriboTextView) -> [WellButton] {
    editor.textView.subviews.compactMap { $0 as? WellButton }
  }

  private func bars(_ editor: EscriboTextView) -> [WellSpanBar] {
    editor.textView.subviews.compactMap { $0 as? WellSpanBar }
  }

  private func block(_ editor: EscriboTextView, kind: BlockKind, last: Bool = false) throws
    -> EscriboBlock
  {
    let matching = editor.coordinator.documentBlocks.filter { $0.kind == kind }
    return try #require(last ? matching.last : matching.first)
  }

  private func label(of button: WellButton) -> String? {
    #if os(macOS)
      return button.accessibilityLabel()
    #else
      return button.accessibilityLabel
    #endif
  }

  /// Installs `notice` as the host's callback, answering for the blocks at `offsets`.
  private func install(_ notice: CountingNotice, on editor: EscriboTextView) {
    editor.coordinator.setWellNotice(notice.answer)
  }

  @Test("A notice glyph is drawn with no hover, with help as tooltip and label, and no span bar")
  func noticeIsAlwaysVisibleWithoutBar() throws {
    let editor = makeEditor()
    let target = try block(editor, kind: .paragraph)
    editor.applyWell(EscriboWell(), horizontalSizeClass: Self.sizeClass)
    let notice = CountingNotice()
    notice.noticed = [target.range.lowerBound]
    install(notice, on: editor)

    let drawn = buttons(editor)
    #expect(drawn.count == 1)
    #expect(drawn.first?.item == .notice)
    #expect(drawn.first?.block?.id == target.id)
    #expect(label(of: try #require(drawn.first)) == "help \(target.range.lowerBound)")
    #expect(drawn.first?.noticeShown?.help == "help \(target.range.lowerBound)")
    #if os(macOS)
    #expect(drawn.first?.toolTip == "help \(target.range.lowerBound)")
    #endif
    #expect(bars(editor).isEmpty)
  }

  @Test("Clicking a notice calls onWellAction(.notice, block) once")
  func clickFiresNoticeAction() throws {
    let editor = makeEditor()
    let target = try block(editor, kind: .paragraph, last: true)
    var received: [(EscriboWellItem, EscriboBlock.ID)] = []
    editor.onWellAction = { item, block in received.append((item, block.id)) }
    editor.applyWell(EscriboWell(), horizontalSizeClass: Self.sizeClass)
    let notice = CountingNotice()
    notice.noticed = [target.range.lowerBound]
    install(notice, on: editor)

    editor.wellOverlay.wellButtonPressed(try #require(buttons(editor).first))
    #expect(received.count == 1)
    #expect(received.first?.0 == .notice)
    #expect(received.first?.1 == target.id)
  }

  @Test("A notice still shows when eligibleKinds excludes the block's kind")
  func eligibleKindsDoNotHideNotice() throws {
    let editor = makeEditor()
    let heading = try block(editor, kind: .heading)
    editor.applyWell(EscriboWell(eligibleKinds: [.paragraph]), horizontalSizeClass: Self.sizeClass)
    let notice = CountingNotice()
    notice.noticed = [heading.range.lowerBound]
    install(notice, on: editor)

    #expect(buttons(editor).map { $0.block?.id } == [heading.id])
    #expect(buttons(editor).first?.item == .notice)
  }

  @Test("A notice on a block with no content shows")
  func noticeOnEmptyBlockShows() throws {
    let editor = makeEditor()
    let empty = try #require(editor.coordinator.documentBlocks.first { $0.contentRanges.isEmpty })
    editor.applyWell(EscriboWell(), horizontalSizeClass: Self.sizeClass)
    let notice = CountingNotice()
    notice.noticed = [empty.range.lowerBound]
    install(notice, on: editor)

    #expect(buttons(editor).map { $0.block?.id } == [empty.id])
    #expect(bars(editor).isEmpty)
  }

  @Test("Without a wellNotice the well's geometry and views are unchanged")
  func noCallbackLeavesWellAlone() throws {
    let editor = makeEditor()
    editor.applyWell(EscriboWell(), horizontalSizeClass: Self.sizeClass)
    #expect(buttons(editor).isEmpty)

    editor.wellOverlay.pointerMoved(to: point(onLine: 4))
    let button = try #require(buttons(editor).first)
    #expect(button.item == .readAloud)
    let firstLine = CGRect(x: Self.textEdge, y: 80, width: 300, height: Self.lineHeight)
    #expect(
      button.frame
        == WellPlacement.buttonFrame(
          slot: 0, firstLineFragment: firstLine, textEdge: Self.textEdge,
          laneWidth: editor.wellLaneWidth, platform: .current))
    #expect(bars(editor).count == 1)
  }

  @Test("A hovered noticed block keeps the notice, not read-aloud, and no bar")
  func hoverDoesNotReplaceNotice() throws {
    let editor = makeEditor()
    let target = try block(editor, kind: .paragraph, last: true)
    editor.applyWell(EscriboWell(), horizontalSizeClass: Self.sizeClass)
    let notice = CountingNotice()
    notice.noticed = [target.range.lowerBound]
    install(notice, on: editor)

    editor.wellOverlay.pointerMoved(to: point(onLine: 4))
    #expect(buttons(editor).map { $0.item } == [.notice])
    #expect(bars(editor).isEmpty)
  }

  @Test("The notice disappears after the callback returns nil and invalidateEmbeds() runs")
  func noticeGoesAfterInvalidate() throws {
    let editor = makeEditor()
    let target = try block(editor, kind: .paragraph)
    editor.applyWell(EscriboWell(), horizontalSizeClass: Self.sizeClass)
    let notice = CountingNotice()
    notice.noticed = [target.range.lowerBound]
    install(notice, on: editor)
    #expect(buttons(editor).count == 1)

    notice.noticed = []
    editor.coordinator.invalidateEmbeds()
    #expect(buttons(editor).isEmpty)
  }
}
