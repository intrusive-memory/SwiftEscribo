#if os(macOS)
  import AppKit
  import EscriboCore
  import Foundation

  /// The accessibility element standing for one embed row (REQUIREMENTS.md § 1.4).
  ///
  /// A button whose label, value and identifier come from the host's ``EscriboEmbed``,
  /// whose press activates the embed, and whose custom actions are the embed's actions.
  final class EmbedAccessibilityElement: NSAccessibilityElement {

    /// Called when the element is pressed (VoiceOver's default action).
    var onPress: (@MainActor () -> Void)?

    /// The text view the row lives in; the frame is converted from its coordinates.
    weak var view: NSView?

    /// The row in `view`'s (flipped) coordinates.
    var rowRect: CGRect = .zero

    /// Screen coordinates. AppKit's default conversion from the frame in parent space is
    /// wrong for the flipped text view, so convert through the view explicitly.
    override func accessibilityFrame() -> NSRect {
      guard let view, view.window != nil else { return super.accessibilityFrame() }
      return NSAccessibility.screenRect(fromView: view, rect: rowRect)
    }

    override func accessibilityPerformPress() -> Bool {
      guard let onPress else { return false }
      MainActor.assumeIsolated { onPress() }
      return true
    }
  }

  extension EscriboTextView {

    /// Wires the text view's extra accessibility children. Called once, from the
    /// initializer. With no embeds the closure answers an empty list, so the text view's
    /// own children are returned untouched.
    func installEmbedAccessibility() {
      textView.embedAccessibilityChildren = { [weak self] in
        self?.embedAccessibilityElements() ?? []
      }
    }

    /// One element per drawn embed, in document order. Elements are cached by block start
    /// so VoiceOver sees stable identities, and refreshed from the coordinator's embed
    /// cache on every query, so they follow the embeds without any further bookkeeping.
    func embedAccessibilityElements() -> [Any] {
      let entries = coordinator.embeddedBlocks
      guard !entries.isEmpty, let controller = embedLayout else {
        embedAccessibilityCache = [:]
        return []
      }
      let length = documentStorage.length
      var live: [Int: EmbedAccessibilityElement] = [:]
      var result: [Any] = []
      for entry in entries where entry.block.range.upperBound <= length {
        let start = entry.block.range.lowerBound
        let element = embedAccessibilityCache[start] ?? EmbedAccessibilityElement()
        let block = entry.block
        element.setAccessibilityRole(.button)
        element.setAccessibilityLabel(entry.embed.accessibilityLabel)
        element.setAccessibilityValue(entry.embed.accessibilityValue)
        element.setAccessibilityIdentifier(entry.embed.accessibilityIdentifier)
        element.setAccessibilityParent(textView)
        element.view = textView
        element.rowRect = controller.rowRect(for: entry) ?? .zero
        element.setAccessibilityFrameInParentSpace(element.rowRect)
        element.onPress = { [weak self] in self?.coordinator.embeds.onActivate(block) }
        element.setAccessibilityCustomActions(
          entry.embed.actions.map { action in
            NSAccessibilityCustomAction(name: action.title) { [weak self] in
              MainActor.assumeIsolated { self?.coordinator.embeds.onAction(block, action.id) }
              return true
            }
          })
        live[start] = element
        result.append(element)
      }
      embedAccessibilityCache = live
      return result
    }

    /// The embeds changed (called from the layout's change callout): tell assistive
    /// technology to re-read the text view's children.
    func embedAccessibilityDidChange() {
      NSAccessibility.post(element: textView, notification: .layoutChanged)
    }
  }
#endif
