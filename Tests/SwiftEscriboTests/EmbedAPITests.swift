import EscriboCore
import Foundation
import SwiftUI
import Testing

@testable import SwiftEscribo

#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

/// A provider that records every block it is asked about, and answers with an embed for
/// every block of one kind.
final class CountingEmbedProvider: EscriboEmbedProvider {

  /// The blocks asked about, in call order.
  private(set) var asked: [EscriboBlock] = []

  /// The texts handed over with them.
  private(set) var texts: [String] = []

  /// Blocks of this kind are embeds; everything else is text.
  var embeddedKind: BlockKind? = .paragraph

  /// Block start offsets the provider refuses, as *Edit as Text* would.
  var refused: Set<Int> = []

  func embed(for block: EscriboBlock, in text: String) -> EscriboEmbed? {
    asked.append(block)
    texts.append(text)
    guard block.kind == embeddedKind, !refused.contains(block.range.lowerBound) else {
      return nil
    }
    return EscriboEmbed(symbolName: "doc", title: "Block", subtitle: "at \(block.range)")
  }

  func reset() {
    asked = []
    texts = []
  }
}

/// Sortie 8: the embed public API, `invalidateEmbeds()`, and the no-provider guarantee
/// (REQUIREMENTS.md § 1.1, § 1.5).
@MainActor
@Suite("Embed API and the provider-asking rules")
struct EmbedAPITests {

  /// Eighty one-line paragraphs separated by blank lines: paragraph `i` starts at `21 * i`.
  ///
  /// One-line paragraphs so an edit inside one is a sound splice and the incremental path
  /// is what is measured, not the fallback full scan.
  static let largeDocument = Array(repeating: "alpha bravo charlie", count: 80)
    .joined(separator: "\n\n")

  // MARK: - Source compatibility

  @Test("Every pre-embed call shape compiles, including a trailing-closure onWellAction")
  func oldInitShapesCompile() {
    var fired = false
    _ = EscriboEditor(text: .constant(""), language: .markdown)
    _ = EscriboEditor(text: .constant(""), language: .fountain, mode: .source)
    _ = EscriboEditor(text: .constant(""), language: .markdown) { _, _ in fired = true }
    // Typed parameters: this compiles only if the trailing closure still binds to
    // `onWellAction` — `onEmbedAction` also takes two arguments, but not these two.
    let wellAction = { (item: EscriboWellItem, block: EscriboBlock) in _ = (item, block) }
    _ = EscriboEditor(text: .constant(""), language: .fountain, well: EscriboWell()) {
      wellAction($0, $1)
    }
    _ = EscriboEditor(
      text: .constant(""), language: .markdown, mode: .live, theme: nil, findBar: true,
      focusOnAppear: true, handle: nil, well: nil, onWellAction: { _, _ in })
    #expect(fired == false)
  }

  @Test("The new parameters are accepted, after onWellAction, on every platform")
  func newParametersCompile() {
    let provider = CountingEmbedProvider()
    let view: any View = EscriboEditor(
      text: .constant(""), language: .fountain,
      onWellAction: { _, _ in },
      embedProvider: provider,
      onEmbedActivate: { _ in },
      onEmbedAction: { _, _ in },
      onFindMatchInEmbed: { _ in })
    #expect(view is EscriboEditor)
    // Nothing is asked until an editor is built from the view.
    #expect(provider.asked.isEmpty)
  }

  @Test("EscriboEmbed defaults its accessibility text to its visible text and is Equatable")
  func embedDefaultsAndEquality() {
    let plain = EscriboEmbed(symbolName: "film", title: "Shot", subtitle: "wide")
    #expect(plain.accessibilityLabel == "Shot")
    #expect(plain.accessibilityValue == "wide")
    #expect(plain.accessibilityIdentifier == nil)
    #expect(plain.badge == nil)
    #expect(plain.actions.isEmpty)

    let full = EscriboEmbed(
      symbolName: "film", title: "Shot", subtitle: "wide",
      badge: .init(symbolName: "checkmark", word: "valid", tint: .black),
      accessibilityLabel: "Camera shot", accessibilityValue: "Wide",
      accessibilityIdentifier: "embed.shot",
      actions: [.init(id: "edit-as-text", title: "Edit as Text")])
    #expect(full != plain)
    #expect(full == full)
    #expect(full.badge?.word == "valid")
    #expect(full.actions.first?.id == "edit-as-text")
  }

  // MARK: - No provider changes nothing

  @Test("No provider: insets, paragraph attributes, and layout geometry are today's")
  func noProviderChangesNothing() throws {
    let text = Self.largeDocument
    let reference = EscriboTextView(language: .markdown, theme: .markdownLight)
    reference.applyExternalText(text)

    let bridge = EscriboEditorBridge(text: .constant(text))
    let editor = bridge.makeEditor(
      language: .markdown, mode: .live, theme: .markdownLight, appearance: .light)
    bridge.update(
      language: .markdown, mode: .live, theme: .markdownLight, appearance: .light, text: text)

    #expect(editor.coordinator.embeddedBlocks.isEmpty)
    #expect(editor.textView.textContainerInset == reference.textView.textContainerInset)
    #expect(
      CoordinatorFixtures.attributeSnapshot(editor.documentStorage)
        == CoordinatorFixtures.attributeSnapshot(reference.documentStorage))
    #expect(try fragmentFrames(editor) == fragmentFrames(reference))
  }

  /// Every layout fragment's frame, after laying out the whole document at a fixed width.
  private func fragmentFrames(_ editor: EscriboTextView) throws -> [CGRect] {
    #if os(macOS)
      editor.textView.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
    #else
      editor.textView.frame = CGRect(x: 0, y: 0, width: 500, height: 400)
    #endif
    let layout = try #require(editor.textView.textLayoutManager)
    layout.ensureLayout(for: layout.documentRange)
    var frames: [CGRect] = []
    layout.enumerateTextLayoutFragments(from: layout.documentRange.location, options: []) {
      frames.append($0.layoutFragmentFrame)
      return true
    }
    #expect(!frames.isEmpty)
    return frames
  }

  // MARK: - When the provider is asked

  @Test("Installing a provider asks every block once, with the block's own text")
  func installAsksEveryBlock() {
    let editor = CoordinatorFixtures.makeEditor(Self.largeDocument)
    let provider = CountingEmbedProvider()
    editor.coordinator.setEmbedProvider(provider)

    let blocks = editor.coordinator.documentBlocks
    #expect(provider.asked == blocks)
    #expect(provider.texts.first == "alpha bravo charlie\n")
    #expect(editor.coordinator.embeddedBlocks.count == 80)
    #expect(
      editor.coordinator.embeddedBlocks.map(\.block) == blocks.filter { $0.kind == .paragraph })
  }

  @Test("The bridge asks every block exactly once on load, and not again on update passes")
  func bridgeLoadAsksEveryBlockOnce() {
    let provider = CountingEmbedProvider()
    let embeds = EmbedConfiguration(provider: provider)
    let bridge = EscriboEditorBridge(text: .constant(Self.largeDocument))
    let editor = bridge.makeEditor(
      language: .markdown, mode: .live, theme: .markdownLight, appearance: .light,
      embeds: embeds)
    #expect(provider.asked == editor.coordinator.documentBlocks)

    provider.reset()
    for _ in 0..<3 {
      bridge.update(
        language: .markdown, mode: .live, theme: .markdownLight, appearance: .light,
        text: Self.largeDocument, embeds: embeds)
    }
    #expect(provider.asked.isEmpty, "a SwiftUI update pass is not a re-ask")

    // A new document is a load.
    bridge.update(
      language: .markdown, mode: .live, theme: .markdownLight, appearance: .light,
      text: "one\n\ntwo\n", embeds: embeds)
    #expect(provider.asked == editor.coordinator.documentBlocks)
  }

  @Test("An edit asks only the rescanned blocks and carries every other answer across it")
  func editAsksOnlyRescannedBlocks() throws {
    let editor = CoordinatorFixtures.makeEditor(Self.largeDocument)
    let provider = CountingEmbedProvider()
    editor.coordinator.setEmbedProvider(provider)
    provider.reset()

    // One character into paragraph 40.
    editor.storage.replaceCharacters(in: NSRange(location: 21 * 40 + 5, length: 0), with: "X")

    try #require(editor.coordinator.blocksSpanDocument, "the edit must have spliced")
    let window = editor.coordinator.lastBlocks
    #expect(!window.isEmpty)
    #expect(window.count < editor.coordinator.documentBlocks.count)
    #expect(provider.asked == window)

    // Every paragraph is still an embed, at its post-edit position, matching the document.
    let paragraphs = editor.coordinator.documentBlocks.filter { $0.kind == .paragraph }
    #expect(editor.coordinator.embeddedBlocks.map(\.block) == paragraphs)
    #expect(
      editor.coordinator.embeddedBlock(containingUTF16Offset: 21 * 41 + 1)?.block
        .range.lowerBound == 21 * 41 + 1)
  }

  @Test("invalidateEmbeds() asks every block; a detached handle ignores it")
  func invalidateAsksEveryBlock() {
    let editor = CoordinatorFixtures.makeEditor(Self.largeDocument)
    let provider = CountingEmbedProvider()
    editor.coordinator.setEmbedProvider(provider)
    provider.reset()

    let handle = EscriboEditorHandle()
    handle.attach(to: editor.coordinator)
    handle.invalidateEmbeds()
    #expect(provider.asked == editor.coordinator.documentBlocks)

    EscriboEditorHandle().invalidateEmbeds()  // no editor: nothing to do, nothing to trap on
  }

  @Test("The change hook reports exactly the blocks whose answer changed")
  func changeHookReportsChangedBlocks() {
    let editor = CoordinatorFixtures.makeEditor(Self.largeDocument)
    let provider = CountingEmbedProvider()
    editor.coordinator.setEmbedProvider(provider)
    var reports: [[Range<Int>]] = []
    editor.coordinator.onEmbedsChange = { reports.append($0) }

    editor.coordinator.invalidateEmbeds()
    #expect(reports.isEmpty, "unchanged answers are not a change")

    // Edit as Text on paragraph 3.
    provider.refused = [21 * 3]
    editor.coordinator.invalidateEmbeds()
    #expect(reports == [[(21 * 3)..<(21 * 3 + 20)]])
    #expect(editor.coordinator.embed(for: editor.coordinator.documentBlocks[6]) == nil)
    #expect(editor.coordinator.embeddedBlocks.count == 79)
  }

  @Test("Removing the provider empties the cache")
  func removingTheProviderEmptiesTheCache() {
    let editor = CoordinatorFixtures.makeEditor(Self.largeDocument)
    let provider = CountingEmbedProvider()
    editor.coordinator.setEmbedProvider(provider)
    #expect(!editor.coordinator.embeddedBlocks.isEmpty)
    editor.coordinator.setEmbedProvider(nil)
    #expect(editor.coordinator.embeddedBlocks.isEmpty)
  }

  // MARK: - Source mode

  @Test("In .source the provider is never called: install, edit, invalidate")
  func sourceModeNeverAsks() {
    let storage = NSTextStorage(string: Self.largeDocument)
    let styler = EscriboStyler(
      environment: EditorStyleEnvironment(theme: .markdownLight, mode: .source, appearance: .light))
    let coordinator = EditorCoordinator(attachingTo: storage, language: .markdown, styler: styler)
    coordinator.restyleEverything()

    let provider = CountingEmbedProvider()
    coordinator.setEmbedProvider(provider)
    storage.replaceCharacters(in: NSRange(location: 5, length: 0), with: "X")
    coordinator.invalidateEmbeds()
    coordinator.restyleEverything()

    #expect(provider.asked.isEmpty)
    #expect(coordinator.embeddedBlocks.isEmpty)
  }

  @Test("live → source empties the cache without asking; source → live asks every block")
  func modeSwitchDrivesTheCache() {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    editor.applyExternalText(Self.largeDocument)
    let provider = CountingEmbedProvider()
    editor.coordinator.setEmbedProvider(provider)
    #expect(editor.coordinator.embeddedBlocks.count == 80)
    provider.reset()

    editor.applyConfiguration(
      language: .markdown, mode: .source, theme: .markdownLight, appearance: .light)
    #expect(provider.asked.isEmpty)
    #expect(editor.coordinator.embeddedBlocks.isEmpty)

    editor.applyConfiguration(
      language: .markdown, mode: .live, theme: .markdownLight, appearance: .light)
    #expect(provider.asked == editor.coordinator.documentBlocks)
    #expect(editor.coordinator.embeddedBlocks.count == 80)
  }
}
