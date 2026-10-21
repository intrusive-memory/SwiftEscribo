#if os(iOS)
  import Foundation
  import UIKit

  /// The one place the editor sits in front of UIKit's private text layout manager
  /// delegate.
  ///
  /// ## Why it exists (REQUIREMENTS.md, *iOS — accepted risk*)
  ///
  /// On iOS 26 `UITextView` installs its own object as `NSTextLayoutManager.delegate`.
  /// Embed rows need that slot (``EmbedLayoutController``). Replacing UIKit's delegate
  /// outright would drop whatever it does there, so this type takes the slot, answers the
  /// one call it needs — the layout fragment for an embedded paragraph — and hands
  /// **everything else** to UIKit's delegate:
  ///
  /// - a paragraph that is not part of an embed gets the fragment UIKit's delegate would
  ///   have vended;
  /// - every other delegate method is forwarded at the Objective-C level
  ///   (`responds(to:)` / `forwardingTarget(for:)`), so UIKit keeps answering the calls it
  ///   answered before, including ones this file does not know about.
  ///
  /// A future iOS may stop installing its delegate, or rely on the slot in a way forwarding
  /// cannot preserve. The user accepted that risk; `UIKitLayoutDelegateChainTests` fails
  /// loudly the day UIKit's delegate is missing, so it is found in CI, not by users.
  ///
  /// UIKit's delegate is held **weakly**, like the slot itself: its owner is the text view.
  @MainActor
  final class UIKitLayoutDelegateChain: NSObject {

    /// UIKit's own delegate, displaced from the slot. `nil` would mean UIKit installed none.
    private(set) weak var uikitDelegate: (any NSTextLayoutManagerDelegate)?

    /// Vends the editor's fragment for an element, or `nil` to let UIKit's delegate vend.
    private let vend: (NSTextLayoutManager, NSTextElement) -> NSTextLayoutFragment?

    /// - Parameters:
    ///   - uikitDelegate: Whatever is in the layout manager's delegate slot now.
    ///   - vend: The editor's fragment for an element, or `nil` for "not mine".
    init(
      displacing uikitDelegate: (any NSTextLayoutManagerDelegate)?,
      vend: @escaping (NSTextLayoutManager, NSTextElement) -> NSTextLayoutFragment?
    ) {
      self.uikitDelegate = uikitDelegate
      self.vend = vend
      super.init()
    }

    // MARK: - Forwarding

    override func responds(to aSelector: Selector!) -> Bool {
      if super.responds(to: aSelector) { return true }
      return (uikitDelegate as AnyObject?)?.responds(to: aSelector) == true
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
      if let target = uikitDelegate as AnyObject?, target.responds(to: aSelector) {
        return target
      }
      return super.forwardingTarget(for: aSelector)
    }
  }

  extension UIKitLayoutDelegateChain: @preconcurrency NSTextLayoutManagerDelegate {
    func textLayoutManager(
      _ textLayoutManager: NSTextLayoutManager,
      textLayoutFragmentFor location: any NSTextLocation,
      in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
      if let fragment = vend(textLayoutManager, textElement) { return fragment }
      return uikitDelegate?.textLayoutManager?(
        textLayoutManager, textLayoutFragmentFor: location, in: textElement)
        ?? NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
    }
  }
#endif
