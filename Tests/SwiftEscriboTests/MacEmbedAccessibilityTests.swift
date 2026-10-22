#if os(macOS)
  import AppKit
  import EscriboCore
  import Foundation
  import Testing

  @testable import SwiftEscribo

  /// Answers one configurable embed for every note block, or none.
  final class AccessibleEmbedProvider: EscriboEmbedProvider {
    var answersNothing = false
    /// Answered instead of ``embed`` when set.
    var answer: EscriboEmbed?
    static let embed = EscriboEmbed(
      symbolName: "note.text", title: "Note", subtitle: "First line of the note",
      accessibilityLabel: "Note label", accessibilityValue: "Note value",
      accessibilityIdentifier: "note-embed",
      actions: [
        .init(id: "open", title: "Open"),
        .init(id: EscriboEmbed.Action.editAsTextID, title: "Edit as Text"),
      ])

    func embed(for block: EscriboBlock, in text: String) -> EscriboEmbed? {
      guard !answersNothing, block.kind == .note else { return nil }
      return answer ?? Self.embed
    }
  }

  /// REQUIREMENTS.md § 1.4 on macOS: one accessibility element per embed.
  @MainActor
  @Suite("macOS embed accessibility", .serialized)
  struct MacEmbedAccessibilityTests {

    @MainActor
    final class Host {
      let layout: EmbedLayoutHarness
      let provider = AccessibleEmbedProvider()
      var activations: [EscriboBlock] = []
      var actions: [(block: EscriboBlock, id: String)] = []
      var textView: EscriboNativeTextView { layout.editor.textView }

      init() throws {
        layout = try EmbedLayoutHarness()
        layout.editor.coordinator.setEmbedCallbacks(
          onActivate: { [unowned self] in self.activations.append($0) },
          onAction: { [unowned self] in self.actions.append((block: $0, id: $1)) },
          onFindMatch: { _ in })
      }

      func install() {
        layout.editor.coordinator.setEmbedProvider(provider)
        _ = layout.layout()
      }

      var elements: [EmbedAccessibilityElement] {
        (textView.accessibilityChildren() ?? []).compactMap { $0 as? EmbedAccessibilityElement }
      }
    }

    @Test("No provider adds no children")
    func noProvider() throws {
      let host = try Host()
      #expect(host.elements.isEmpty)
      let base = host.textView.accessibilityChildren()?.count ?? 0
      host.install()
      host.provider.answersNothing = true
      host.layout.editor.coordinator.invalidateEmbeds()
      #expect(host.elements.isEmpty)
      #expect((host.textView.accessibilityChildren()?.count ?? 0) == base)
    }

    @Test("One button element per embed with the host's label, value and identifier")
    func elementProperties() throws {
      let host = try Host()
      let base = host.textView.accessibilityChildren()?.count ?? 0
      host.install()
      #expect(host.elements.count == 1)
      #expect((host.textView.accessibilityChildren()?.count ?? 0) == base + 1)
      let element = try #require(host.elements.first)
      #expect(element.accessibilityRole() == .button)
      #expect(element.accessibilityLabel() == "Note label")
      #expect(element.accessibilityValue() as? String == "Note value")
      #expect(element.accessibilityIdentifier() == "note-embed")
      #expect((element.accessibilityParent() as AnyObject?) === host.textView)
      // The text view stays the accessible text area.
      #expect(host.textView.isAccessibilityElement())
      // Stable identity across queries.
      #expect(host.elements.first === element)
    }

    @Test("The frame is the row, in screen coordinates")
    func frame() throws {
      let host = try Host()
      host.install()
      let element = try #require(host.elements.first)
      let controller = try #require(host.layout.editor.embedLayout)
      let entry = try #require(host.layout.editor.coordinator.embeddedBlocks.first)
      let row = try #require(controller.rowRect(for: entry))
      #expect(element.rowRect == row)

      let window = NSWindow(
        contentRect: CGRect(x: 100, y: 100, width: 600, height: 800), styleMask: [.titled],
        backing: .buffered, defer: true)
      window.contentView = host.layout.editor.scrollView
      let screen = element.accessibilityFrame()
      let expected = window.convertToScreen(host.textView.convert(row, to: nil))
      #expect(abs(screen.minX - expected.minX) <= 1)
      #expect(abs(screen.minY - expected.minY) <= 1)
      #expect(abs(screen.height - expected.height) <= 1)
    }

    @Test("Press activates the embed once")
    func press() throws {
      let host = try Host()
      host.install()
      let element = try #require(host.elements.first)
      #expect(element.accessibilityPerformPress())
      #expect(host.activations.count == 1)
      #expect(host.activations.first?.range == host.layout.note)
      #expect(host.actions.isEmpty)
    }

    @Test("Each custom action reports its id once")
    func customActions() throws {
      let host = try Host()
      host.install()
      let element = try #require(host.elements.first)
      let actions = element.accessibilityCustomActions() ?? []
      #expect(actions.map(\.name) == ["Open", "Edit as Text"])
      for action in actions { #expect(action.handler?() == true) }
      #expect(host.actions.map(\.id) == ["open", EscriboEmbed.Action.editAsTextID])
      #expect(host.actions.allSatisfy { $0.block.range == host.layout.note })
      #expect(host.activations.isEmpty)
    }

    // MARK: - The state element

    static let state = EscriboEmbed.StateElement(
      label: "Render state", value: "changed", identifier: "storyboard.embed.0.state")

    /// The expected state rectangle, from the row and the geometry the renderer draws by.
    static func expectedStateRect(row: CGRect, embed: EscriboEmbed, theme: EscriboTheme) -> CGRect {
      let geometry = EmbedRowGeometry(
        embed: embed, fontSpec: EmbedLayoutController.nominalFontSpec(of: theme), scale: 1)
      return geometry.stateRect(in: EmbedRowGeometry.drawnRect(forRow: row, scale: 1))
    }

    @Test("A state element follows the embed's element: static text, no actions, over the badge")
    func stateElementOverBadge() throws {
      let host = try Host()
      let embed = EscriboEmbed(
        symbolName: "film", title: "Shot", subtitle: "wide",
        badge: .init(symbolName: "exclamationmark.triangle", word: "changed", tint: .black),
        accessibilityIdentifier: "storyboard.embed.0", actions: [.init(id: "open", title: "Open")],
        stateElement: Self.state)
      host.provider.answer = embed
      let base = host.textView.accessibilityChildren()?.count ?? 0
      host.install()

      let children = host.textView.accessibilityChildren() ?? []
      #expect(children.count == base + 2)
      // The embed's element and its state element are the last two, in that order.
      let embedElement = children[children.count - 2] as? EmbedAccessibilityElement
      #expect(embedElement != nil)
      let state = try #require(children.last as? EmbedStateAccessibilityElement)
      #expect(host.elements.count == 1)

      #expect(state.accessibilityRole() == .staticText)
      #expect(state.accessibilityLabel() == "Render state")
      #expect(state.accessibilityValue() as? String == "changed")
      #expect(state.accessibilityIdentifier() == "storyboard.embed.0.state")
      #expect((state.accessibilityParent() as AnyObject?) === host.textView)
      #expect((state.accessibilityCustomActions() ?? []).isEmpty)

      // Over the drawn badge capsule, inside the row.
      let controller = try #require(host.layout.editor.embedLayout)
      let entry = try #require(host.layout.editor.coordinator.embeddedBlocks.first)
      let row = try #require(controller.rowRect(for: entry))
      let capsule = try #require(
        EmbedRowGeometry(
          embed: embed,
          fontSpec: EmbedLayoutController.nominalFontSpec(of: .fountainLight), scale: 1
        ).badge(in: EmbedRowGeometry.drawnRect(forRow: row, scale: 1))
      ).capsule
      #expect(state.rectInView == capsule)
      #expect(controller.stateRect(for: entry) == capsule)
      #expect(row.contains(capsule))

      // Stable identity across queries.
      let again =
        (host.textView.accessibilityChildren() ?? []).last as? EmbedStateAccessibilityElement
      #expect(again === state)
    }

    @Test("Without a badge the state element is a square at the row's trailing edge")
    func stateElementWithoutBadge() throws {
      let host = try Host()
      let embed = EscriboEmbed(
        symbolName: "film", title: "Shot",
        stateElement: .init(label: "Render state", value: "unknown", identifier: "s"))
      host.provider.answer = embed
      host.install()
      let state = try #require(
        (host.textView.accessibilityChildren() ?? []).compactMap {
          $0 as? EmbedStateAccessibilityElement
        }.first)
      #expect(state.accessibilityValue() as? String == "unknown")

      let controller = try #require(host.layout.editor.embedLayout)
      let entry = try #require(host.layout.editor.coordinator.embeddedBlocks.first)
      let row = try #require(controller.rowRect(for: entry))
      let rect = state.rectInView
      #expect(rect == Self.expectedStateRect(row: row, embed: embed, theme: .fountainLight))
      #expect(rect.width == rect.height && rect.width > 0)
      #expect(row.contains(rect))
      #expect(rect.maxX > row.midX)
    }

    @Test("No stateElement, no extra element; removing the embed removes its state element")
    func stateElementLifecycle() throws {
      let host = try Host()
      let base = host.textView.accessibilityChildren()?.count ?? 0
      host.install()
      #expect((host.textView.accessibilityChildren()?.count ?? 0) == base + 1)

      host.provider.answer = EscriboEmbed(
        symbolName: "film", title: "Shot", stateElement: Self.state)
      host.layout.editor.coordinator.invalidateEmbeds()
      _ = host.layout.layout()
      #expect((host.textView.accessibilityChildren()?.count ?? 0) == base + 2)

      host.provider.answersNothing = true
      host.layout.editor.coordinator.invalidateEmbeds()
      #expect((host.textView.accessibilityChildren()?.count ?? 0) == base)
      #expect(host.layout.editor.embedStateAccessibilityCache.isEmpty)
    }

    @Test("Elements follow invalidateEmbeds() removing and adding an embed")
    func followsInvalidation() throws {
      let host = try Host()
      host.install()
      #expect(host.elements.count == 1)

      host.provider.answersNothing = true
      host.layout.editor.coordinator.invalidateEmbeds()
      #expect(host.elements.isEmpty)

      host.provider.answersNothing = false
      host.layout.editor.coordinator.invalidateEmbeds()
      #expect(host.elements.count == 1)
      let element = try #require(host.elements.first)
      #expect(element.accessibilityPerformPress())
      #expect(host.activations.count == 1)
    }
  }
#endif
