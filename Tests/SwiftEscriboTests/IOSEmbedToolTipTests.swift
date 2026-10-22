#if os(iOS)
  import EscriboCore
  import Foundation
  import Testing
  import UIKit

  @testable import SwiftEscribo

  /// ``EscriboEmbed/toolTip`` on iPadOS: a `UIToolTipInteraction` on the text view whose
  /// delegate answers the tool tip of the embed row under the pointer, or `nil`.
  @MainActor
  @Suite("iOS embed tool tips", .serialized)
  struct IOSEmbedToolTipTests {

    static let embed = EscriboEmbed(
      symbolName: "film", title: "Shot", toolTip: "No render record")

    @MainActor
    struct Fixture {
      let harness: EmbedLayoutHarness
      let provider = AccessibleNoteProvider()
      var editor: EscriboTextView { harness.editor }
      var textView: EscriboNativeTextView { harness.editor.textView }

      init(answer: EscriboEmbed? = IOSEmbedToolTipTests.embed, embedded: Bool = true) throws {
        harness = try EmbedLayoutHarness()
        provider.answer = answer
        if embedded { harness.editor.coordinator.setEmbedProvider(provider) }
        _ = harness.layout()
      }

      func row() throws -> CGRect {
        let layout = try #require(editor.embedLayout)
        let hit = try #require(layout.embeddedBlock(containingUTF16Offset: harness.note.lowerBound))
        return try #require(layout.rowRect(for: hit))
      }
    }

    @Test("no provider, or no embed: no tool tip interaction at all")
    func nothingWithoutEmbeds() throws {
      let plain = try Fixture(embedded: false)
      #expect(plain.textView.embedToolTips == nil)
      #expect(!plain.textView.interactions.contains { $0 is UIToolTipInteraction })

      let refusing = try Fixture(embedded: false)
      refusing.provider.answersNothing = true
      refusing.editor.coordinator.setEmbedProvider(refusing.provider)
      #expect(refusing.textView.embedToolTips == nil)
    }

    @Test("the delegate answers the row's tool tip inside the row and nil outside it")
    func answersInsideRowOnly() throws {
      let f = try Fixture()
      let toolTips = try #require(f.textView.embedToolTips)
      #expect(f.textView.interactions.contains { $0 === toolTips.interaction })
      #expect(toolTips.interaction.delegate === toolTips)

      let row = try f.row()
      let inside = toolTips.toolTipInteraction(
        toolTips.interaction, configurationAt: CGPoint(x: row.midX, y: row.midY))
      #expect(inside?.toolTip == "No render record")
      #expect(inside?.sourceRect == row)

      let above = toolTips.toolTipInteraction(
        toolTips.interaction, configurationAt: CGPoint(x: row.midX, y: row.minY - 4))
      #expect(above == nil)
      let below = toolTips.toolTipInteraction(
        toolTips.interaction, configurationAt: CGPoint(x: row.midX, y: row.maxY + 4))
      #expect(below == nil)
    }

    @Test("an embed without a toolTip answers nil, even inside its row")
    func noToolTipAnswersNil() throws {
      let f = try Fixture(answer: EscriboEmbed(symbolName: "film", title: "Shot"))
      let toolTips = try #require(f.textView.embedToolTips)
      let row = try f.row()
      #expect(
        toolTips.toolTipInteraction(
          toolTips.interaction, configurationAt: CGPoint(x: row.midX, y: row.midY)) == nil)
    }

    @Test("once the embed goes away, the row's point answers nil")
    func followsTheEmbedSet() throws {
      let f = try Fixture()
      let toolTips = try #require(f.textView.embedToolTips)
      let row = try f.row()
      f.provider.answersNothing = true
      f.editor.coordinator.invalidateEmbeds()
      #expect(
        toolTips.toolTipInteraction(
          toolTips.interaction, configurationAt: CGPoint(x: row.midX, y: row.midY)) == nil)
    }
  }
#endif
