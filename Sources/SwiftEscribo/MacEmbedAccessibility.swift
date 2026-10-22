#if os(macOS)
  import AppKit
  import EscriboCore
  import Foundation

  /// An accessibility element laid over a rectangle of the text view.
  ///
  /// AppKit's default conversion from the frame in parent space is wrong for the flipped
  /// text view, so the screen frame is converted through the view explicitly.
  class EmbedAnchoredAccessibilityElement: NSAccessibilityElement {

    /// The text view the element lives in; the frame is converted from its coordinates.
    weak var view: NSView?

    /// The element's rectangle in `view`'s (flipped) coordinates.
    var rectInView: CGRect = .zero

    override func accessibilityFrame() -> NSRect {
      guard let view, view.window != nil else { return super.accessibilityFrame() }
      return NSAccessibility.screenRect(fromView: view, rect: rectInView)
    }
  }

  /// The accessibility element standing for one embed row (REQUIREMENTS.md § 1.4).
  ///
  /// A button whose label, value and identifier come from the host's ``EscriboEmbed``,
  /// whose press activates the embed, and whose custom actions are the embed's actions.
  final class EmbedAccessibilityElement: EmbedAnchoredAccessibilityElement {

    /// Called when the element is pressed (VoiceOver's default action).
    var onPress: (@MainActor () -> Void)?

    /// The row in `view`'s (flipped) coordinates.
    var rowRect: CGRect {
      get { rectInView }
      set { rectInView = newValue }
    }

    override func accessibilityPerformPress() -> Bool {
      guard let onPress else { return false }
      MainActor.assumeIsolated { onPress() }
      return true
    }
  }

  /// The accessibility element of an embed's state (``EscriboEmbed/StateElement``): static
  /// text over the badge, or over a small square at the row's trailing edge when no badge is
  /// drawn. A sibling placed right after the embed's own element; it has no actions.
  final class EmbedStateAccessibilityElement: EmbedAnchoredAccessibilityElement {}

  extension EscriboTextView {

    /// Wires the text view's extra accessibility children. Called once, from the
    /// initializer. With no embeds the closure answers an empty list, so the text view's
    /// own children are returned untouched.
    func installEmbedAccessibility() {
      textView.embedAccessibilityChildren = { [weak self] in
        self?.embedAccessibilityElements() ?? []
      }
    }

    /// One element per drawn embed, in document order, each followed by its state element
    /// when the embed has one. Elements are cached by block start so VoiceOver sees stable
    /// identities, and refreshed from the coordinator's embed cache on every query, so they
    /// follow the embeds without any further bookkeeping.
    func embedAccessibilityElements() -> [Any] {
      let entries = coordinator.embeddedBlocks
      guard !entries.isEmpty, let controller = embedLayout else {
        embedAccessibilityCache = [:]
        embedStateAccessibilityCache = [:]
        return []
      }
      let length = documentStorage.length
      var live: [Int: EmbedAccessibilityElement] = [:]
      var liveStates: [Int: EmbedStateAccessibilityElement] = [:]
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

        guard let state = entry.embed.stateElement else { continue }
        let stateElement = embedStateAccessibilityCache[start] ?? EmbedStateAccessibilityElement()
        stateElement.setAccessibilityRole(.staticText)
        stateElement.setAccessibilityLabel(state.label)
        stateElement.setAccessibilityValue(state.value)
        stateElement.setAccessibilityIdentifier(state.identifier)
        stateElement.setAccessibilityParent(textView)
        stateElement.view = textView
        stateElement.rectInView = controller.stateRect(for: entry) ?? .zero
        stateElement.setAccessibilityFrameInParentSpace(stateElement.rectInView)
        liveStates[start] = stateElement
        result.append(stateElement)
      }
      embedAccessibilityCache = live
      embedStateAccessibilityCache = liveStates
      return result
    }

    /// The embeds changed (called from the layout's change callout): tell assistive
    /// technology to re-read the text view's children.
    func embedAccessibilityDidChange() {
      NSAccessibility.post(element: textView, notification: .layoutChanged)
    }
  }
#endif
