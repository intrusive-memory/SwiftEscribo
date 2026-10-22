#if os(macOS)
  import AppKit
  import EscriboCore
  import Foundation
  import Testing

  @testable import SwiftEscribo

  /// ``EscriboEmbed/toolTip`` on macOS: one tool tip rectangle per embed row that has one,
  /// registered on the text view, and only those tags ever removed.
  @MainActor
  @Suite("macOS embed tool tips", .serialized)
  struct MacEmbedToolTipTests {

    @MainActor
    final class Host {
      let layout: EmbedLayoutHarness
      let provider = AccessibleEmbedProvider()
      var editor: EscriboTextView { layout.editor }
      var textView: EscriboNativeTextView { layout.editor.textView }

      init(toolTip: String? = "No render record") throws {
        layout = try EmbedLayoutHarness()
        provider.answer = EscriboEmbed(symbolName: "film", title: "Shot", toolTip: toolTip)
      }

      func install() async {
        editor.coordinator.setEmbedProvider(provider)
        _ = layout.layout()
        await settle()
      }

      /// Lets every refresh queued on the main run loop run.
      func settle() async {
        for _ in 0..<10 {
          await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
          }
          if (textView.embedToolTips?.pendingRefreshCount ?? 0) == 0 { return }
        }
      }

      func row() throws -> CGRect {
        let controller = try #require(editor.embedLayout)
        let entry = try #require(editor.coordinator.embeddedBlocks.first)
        return try #require(controller.rowRect(for: entry))
      }
    }

    @Test("No provider, or no embed: no tool tip object at all")
    func nothingWithoutEmbeds() async throws {
      let host = try Host()
      #expect(host.textView.embedToolTips == nil)
      host.provider.answersNothing = true
      await host.install()
      #expect(host.textView.embedToolTips == nil)
    }

    @Test("An embed with a toolTip registers one rectangle over its row, with its text")
    func registersOverRow() async throws {
      let host = try Host()
      await host.install()
      let toolTips = try #require(host.textView.embedToolTips)
      #expect(toolTips.registrations == [.init(rect: try host.row(), text: "No render record")])

      let tag = try #require(toolTips.registered.first?.tag)
      let text = toolTips.view(
        host.textView, stringForToolTip: tag, point: .zero, userData: nil)
      #expect(text == "No render record")
    }

    @Test("An embed without a toolTip registers nothing")
    func noToolTipNoRectangle() async throws {
      let host = try Host(toolTip: nil)
      await host.install()
      let toolTips = try #require(host.textView.embedToolTips)
      #expect(toolTips.registered.isEmpty)
    }

    @Test("Removing the embed removes its rectangle, and leaves the view's own tool tip")
    func removedWithEmbed() async throws {
      let host = try Host()
      host.textView.toolTip = "The view's own"
      await host.install()
      let toolTips = try #require(host.textView.embedToolTips)
      #expect(toolTips.registered.count == 1)

      host.provider.answersNothing = true
      host.editor.coordinator.invalidateEmbeds()
      await host.settle()
      #expect(toolTips.registered.isEmpty)
      #expect(host.textView.toolTip == "The view's own")

      host.provider.answersNothing = false
      host.editor.coordinator.invalidateEmbeds()
      await host.settle()
      #expect(toolTips.registrations == [.init(rect: try host.row(), text: "No render record")])
    }

    @Test("An edit above the embed moves its rectangle with the row")
    func followsEdits() async throws {
      let host = try Host()
      await host.install()
      let toolTips = try #require(host.textView.embedToolTips)
      let before = try #require(toolTips.registrations.first?.rect)

      host.editor.performInputPathEdit(
        InputPathEdit(replacing: NSRange(location: 0, length: 0), with: "Top line.\n\n"))
      _ = host.layout.layout()
      await host.settle()
      let after = try #require(toolTips.registrations.first?.rect)
      #expect(after.minY > before.minY)
      #expect(after == (try host.row()))
    }

    @Test("A width change moves the rectangle; an unchanged refresh changes nothing")
    func followsWidth() async throws {
      let host = try Host()
      await host.install()
      let toolTips = try #require(host.textView.embedToolTips)
      let changes = toolTips.changeCount
      toolTips.refresh()
      #expect(toolTips.changeCount == changes)

      let before = try #require(toolTips.registrations.first?.rect)
      host.textView.setFrameSize(NSSize(width: 300, height: host.textView.frame.height))
      host.textView.textContainer?.size = NSSize(
        width: 300, height: CGFloat.greatestFiniteMagnitude)
      _ = host.layout.layout()
      await host.settle()
      let after = try #require(toolTips.registrations.first?.rect)
      #expect(after.width < before.width)
      #expect(after == (try host.row()))
    }
  }
#endif
