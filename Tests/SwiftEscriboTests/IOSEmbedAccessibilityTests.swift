#if os(iOS)
  import EscriboCore
  import Foundation
  import Testing
  import UIKit

  @testable import SwiftEscribo

  /// Answers every note block with an embed that carries the host's accessibility and two
  /// actions, *Edit as Text* among them, unless told to answer nothing.
  final class AccessibleNoteProvider: EscriboEmbedProvider {
    var answersNothing = false
    /// Answered instead of ``embed`` when set.
    var answer: EscriboEmbed?

    static let embed = EscriboEmbed(
      symbolName: "note.text", title: "Note", subtitle: "First line of the note",
      accessibilityLabel: "Directive note", accessibilityValue: "First line of the note, 3 lines",
      accessibilityIdentifier: "embed.note",
      actions: [
        .init(id: EscriboEmbed.Action.editAsTextID, title: "Edit as Text"),
        .init(id: "host.copy", title: "Copy Note"),
      ])

    func embed(for block: EscriboBlock, in text: String) -> EscriboEmbed? {
      guard !answersNothing, block.kind == .note else { return nil }
      return answer ?? Self.embed
    }
  }

  /// REQUIREMENTS.md § 1.4 on iOS: one button element per embed, laid over its row, while the
  /// text view stays the accessible text area. What VoiceOver itself does cannot run in a
  /// unit-test host; the live accessibility tree is in the PR (IOS_LIVE_CHECK.md row f).
  @MainActor
  @Suite("iOS embed accessibility: one button per embed over its row", .serialized)
  struct IOSEmbedAccessibilityTests {

    @MainActor
    struct Fixture {
      let harness: EmbedLayoutHarness
      let provider = AccessibleNoteProvider()
      let recorder = EmbedCallbackRecorder()
      var editor: EscriboTextView { harness.editor }
      var textView: EscriboNativeTextView { harness.editor.textView }
      var note: NSRange { NSRange(location: harness.note.lowerBound, length: harness.note.count) }

      var accessibility: IOSEmbedAccessibility {
        get throws { try #require(harness.editor.textView.embedAccessibility) }
      }

      init(embedded: Bool = true, answer: EscriboEmbed? = nil) throws {
        harness = try EmbedLayoutHarness()
        provider.answer = answer
        if embedded { harness.editor.coordinator.setEmbedProvider(provider) }
        _ = harness.layout()
        recorder.install(on: harness.editor)
        settle()
      }

      /// Runs the text view's pending layout pass, which is where the elements sync.
      func settle() {
        textView.layoutIfNeeded()
      }

      /// The single element, after a sync.
      func onlyElement() throws -> EmbedAccessibilityElement {
        let elements = try accessibility.elements
        #expect(elements.count == 1)
        return try #require(elements.first)
      }

      /// The note's row in text-view coordinates.
      func row() throws -> CGRect {
        let layout = try #require(editor.embedLayout)
        let hit = try #require(layout.embeddedBlock(containingUTF16Offset: note.location))
        return try #require(layout.rowRect(for: hit))
      }
    }

    /// The text view's own accessibility, which embeds must leave alone.
    struct TextViewAccessibility: Equatable {
      var isElement: Bool
      var traits: UIAccessibilityTraits
      var value: String?
      var hasElementsOverride: Bool

      @MainActor init(_ textView: UITextView) {
        isElement = textView.isAccessibilityElement
        traits = textView.accessibilityTraits
        value = textView.accessibilityValue
        hasElementsOverride = textView.accessibilityElements != nil
      }
    }

    @Test("one button element per embed, with the host's label, value and identifier, over the row")
    func oneButtonPerEmbed() throws {
      let f = try Fixture()
      let element = try f.onlyElement()
      let embed = AccessibleNoteProvider.embed

      #expect(element.isAccessibilityElement)
      #expect(element.accessibilityTraits == .button)
      #expect(element.accessibilityLabel == embed.accessibilityLabel)
      #expect(element.accessibilityValue == embed.accessibilityValue)
      #expect(element.accessibilityIdentifier == embed.accessibilityIdentifier)
      #expect(element.embedded?.block.range == f.harness.note)

      // Over the drawn row: its frame in the text view is the row, and its accessibility
      // frame is that row converted to screen coordinates.
      let window = IOSEmbedInputTests.host(f.textView)
      defer { window.isHidden = true }
      f.settle()
      let row = try f.row()
      let container = try #require(try f.accessibility.container)
      #expect(container.convert(element.frame, to: f.textView) == row)
      let screenRow = UIAccessibility.convertToScreenCoordinates(row, in: f.textView)
      #expect(
        element.accessibilityFrame == screenRow,
        "\(element.accessibilityFrame) vs \(screenRow) (row \(row))")

      // Touch-free, so a tap on the row still reaches the text view; the container is a
      // plain subview of the text view and not an element itself.
      #expect(!container.isUserInteractionEnabled && !element.isUserInteractionEnabled)
      #expect(!container.isAccessibilityElement)
      #expect(container.superview === f.textView)
      #expect(element.superview === container)
      let center = f.textView.convert(CGPoint(x: row.midX, y: row.midY), to: window)
      let hit = window.hitTest(center, with: nil)
      #expect(hit?.isDescendant(of: f.textView) == true)
      #expect(!(hit is EmbedAccessibilityElement) && !(hit is EmbedAccessibilityContainer))
    }

    @Test("the text view stays an accessibility element exposing the document text")
    func textViewStaysAccessible() throws {
      // A unit-test host runs without the accessibility runtime, where UIKit reports a
      // text view as no element at all; on a device (and in the live tree) it is the text
      // area. So say what the runtime says, then show the embeds leave it that way.
      let f = try Fixture(embedded: false)
      f.textView.isAccessibilityElement = true
      let before = TextViewAccessibility(f.textView)

      f.editor.coordinator.setEmbedProvider(f.provider)
      _ = f.harness.layout()
      f.settle()
      #expect(try f.accessibility.elements.count == 1)

      // Still an element, with no `accessibilityElements` override and the same traits
      // and value: VoiceOver still reads and edits the document through it.
      #expect(f.textView.isAccessibilityElement)
      #expect(TextViewAccessibility(f.textView) == before)
      #expect(!before.hasElementsOverride)
      #expect(f.textView.text == f.harness.storage.string)

      // And without that, exactly what a stock text view and an editor without embeds say.
      let plain = try Fixture(embedded: false)
      let embedded = try Fixture()
      #expect(try embedded.accessibility.elements.count == 1)
      #expect(TextViewAccessibility(embedded.textView) == TextViewAccessibility(plain.textView))
      #expect(
        embedded.textView.isAccessibilityElement == UITextView().isAccessibilityElement)
    }

    @Test("activating the element selects the whole block and calls onEmbedActivate once")
    func activateFiresOnce() throws {
      let f = try Fixture()
      let element = try f.onlyElement()
      f.textView.selectedRange = NSRange(location: 0, length: 0)

      #expect(element.accessibilityActivate())
      #expect(f.recorder.activations.count == 1)
      #expect(f.recorder.activations.first?.range == f.harness.note)
      #expect(f.textView.selectedRange == f.note)
      #expect(f.recorder.actions.isEmpty)
    }

    @Test("each custom action is one of the host's actions and fires its id, Edit as Text included")
    func customActionsFireTheirIDs() throws {
      let f = try Fixture()
      let element = try f.onlyElement()
      let actions = try #require(element.accessibilityCustomActions)
      #expect(actions.map(\.name) == AccessibleNoteProvider.embed.actions.map(\.title))

      for action in actions {
        let handler = try #require(action.actionHandler)
        #expect(handler(action))
      }
      #expect(f.recorder.actions.map(\.id) == [EscriboEmbed.Action.editAsTextID, "host.copy"])
      #expect(f.recorder.actions.allSatisfy { $0.block.range == f.harness.note })
      #expect(f.recorder.activations.isEmpty)
    }

    @Test("invalidateEmbeds() removing and restoring the embed removes and restores its element")
    func elementsFollowInvalidate() throws {
      let f = try Fixture()
      let container = try #require(try f.accessibility.container)
      #expect(container.subviews.count == 1)

      f.provider.answersNothing = true
      f.editor.coordinator.invalidateEmbeds()
      f.settle()
      #expect(try f.accessibility.elements.isEmpty)
      #expect(container.subviews.isEmpty)

      f.provider.answersNothing = false
      f.editor.coordinator.invalidateEmbeds()
      _ = f.harness.layout()
      f.settle()
      let element = try f.onlyElement()
      #expect(element.accessibilityLabel == AccessibleNoteProvider.embed.accessibilityLabel)
      #expect(container.subviews.count == 1)
      #expect(container.convert(element.frame, to: f.textView) == (try f.row()))
    }

    @Test("an edit above the embed moves its element with the row and retargets activation")
    func elementFollowsEdits() throws {
      let f = try Fixture()
      let before = try f.onlyElement().frame

      f.editor.performInputPathEdit(
        InputPathEdit(replacing: NSRange(location: 0, length: 0), with: "Top line.\n\n"))
      _ = f.harness.layout()
      f.settle()

      let element = try f.onlyElement()
      let block = try #require(f.editor.coordinator.embeddedBlocks.first)
      #expect(element.frame.minY > before.minY)
      #expect(
        element.frame == (try #require(try f.editor.embedLayout?.rowRect(for: block))))
      #expect(element.embedded?.block.range == block.block.range)
      #expect(element.accessibilityActivate())
      #expect(f.recorder.activations.last?.range == block.block.range)
    }

    // MARK: - The state element

    static func stateEmbed(badge: Bool) -> EscriboEmbed {
      EscriboEmbed(
        symbolName: "film", title: "Shot", subtitle: "wide",
        badge: badge
          ? .init(symbolName: "exclamationmark.triangle", word: "changed", tint: .black) : nil,
        accessibilityIdentifier: "storyboard.embed.0",
        actions: [.init(id: EscriboEmbed.Action.editAsTextID, title: "Edit as Text")],
        stateElement: .init(
          label: "Render state", value: badge ? "changed" : "unknown",
          identifier: "storyboard.embed.0.state"))
    }

    /// Equal to within float rounding (a frame converted through the container is not bit-exact).
    static func isClose(_ a: CGRect, _ b: CGRect) -> Bool {
      abs(a.minX - b.minX) < 0.001 && abs(a.minY - b.minY) < 0.001
        && abs(a.width - b.width) < 0.001 && abs(a.height - b.height) < 0.001
    }

    /// The state rectangle the geometry gives for `row`, as the renderer draws it.
    static func expectedStateRect(row: CGRect, embed: EscriboEmbed) -> CGRect {
      EmbedRowGeometry(
        embed: embed, fontSpec: EmbedLayoutController.nominalFontSpec(of: .fountainLight),
        scale: 1
      ).stateRect(in: EmbedRowGeometry.drawnRect(forRow: row, scale: 1))
    }

    @Test("a state element follows the embed's element: static text, over the badge capsule")
    func stateElementOverBadge() throws {
      let embed = Self.stateEmbed(badge: true)
      let f = try Fixture(answer: embed)
      let element = try f.onlyElement()
      let states = try f.accessibility.stateElements
      #expect(states.count == 1)
      let state = try #require(states.first)

      #expect(state.isAccessibilityElement)
      #expect(state.accessibilityTraits == .staticText)
      #expect(state.accessibilityLabel == "Render state")
      #expect(state.accessibilityValue == "changed")
      #expect(state.accessibilityIdentifier == "storyboard.embed.0.state")
      #expect((state.accessibilityCustomActions ?? []).isEmpty)
      #expect(!state.isUserInteractionEnabled)
      #expect(element.accessibilityTraits == .button)

      // A sibling, right after the embed's element, in the same container.
      let container = try #require(try f.accessibility.container)
      #expect(container.subviews.count == 2)
      #expect(container.subviews.first === element)
      #expect(container.subviews.last === state)
      #expect(element.subviews.isEmpty)

      // Over the drawn badge capsule.
      let row = try f.row()
      let theme = f.editor.coordinator.styler.environment.resolvedTheme
      let capsule = try #require(
        EmbedRowGeometry(
          embed: embed, fontSpec: EmbedLayoutController.nominalFontSpec(of: theme), scale: 1
        ).badge(in: EmbedRowGeometry.drawnRect(forRow: row, scale: 1))
      ).capsule
      let frame = container.convert(state.frame, to: f.textView)
      #expect(Self.isClose(frame, capsule), "\(frame) vs \(capsule) in row \(row)")
      #expect(row.contains(capsule))

      let window = IOSEmbedInputTests.host(f.textView)
      defer { window.isHidden = true }
      f.settle()
      let screen = UIAccessibility.convertToScreenCoordinates(capsule, in: f.textView)
      #expect(
        Self.isClose(state.accessibilityFrame, screen), "\(state.accessibilityFrame) vs \(screen)")
    }

    @Test("without a badge the state element is a square at the row's trailing edge")
    func stateElementWithoutBadge() throws {
      let embed = Self.stateEmbed(badge: false)
      let f = try Fixture(answer: embed)
      let state = try #require(try f.accessibility.stateElements.first)
      #expect(state.accessibilityValue == "unknown")
      let row = try f.row()
      let container = try #require(try f.accessibility.container)
      let frame = container.convert(state.frame, to: f.textView)
      #expect(Self.isClose(frame, Self.expectedStateRect(row: row, embed: embed)))
      #expect(frame.width == frame.height && frame.width > 0)
      #expect(row.contains(frame) && frame.minX > row.midX)
    }

    @Test("no stateElement adds no view; removing the embed removes its state element")
    func stateElementLifecycle() throws {
      let f = try Fixture()
      let container = try #require(try f.accessibility.container)
      #expect(try f.accessibility.stateElements.isEmpty)
      #expect(container.subviews.count == 1)

      f.provider.answer = Self.stateEmbed(badge: false)
      f.editor.coordinator.invalidateEmbeds()
      _ = f.harness.layout()
      f.settle()
      #expect(try f.accessibility.stateElements.count == 1)
      #expect(container.subviews.count == 2)

      f.provider.answersNothing = true
      f.editor.coordinator.invalidateEmbeds()
      f.settle()
      #expect(try f.accessibility.stateElements.isEmpty)
      #expect(container.subviews.isEmpty)
    }

    @Test("no provider: no elements, no container, and the layout pass does no work")
    func noProviderNoElements() throws {
      let f = try Fixture(embedded: false)
      let accessibility = try f.accessibility
      f.textView.setNeedsLayout()
      f.settle()
      #expect(accessibility.elements.isEmpty)
      #expect(accessibility.container == nil)
      #expect(accessibility.syncCount == 0)
      #expect(!f.textView.subviews.contains { $0 is EmbedAccessibilityContainer })
    }
  }
#endif
