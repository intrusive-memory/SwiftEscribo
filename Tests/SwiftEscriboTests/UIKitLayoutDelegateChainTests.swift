#if os(iOS)
  import EscriboCore
  import Foundation
  import Testing
  import UIKit

  @testable import SwiftEscribo

  /// The accepted-risk tripwire (REQUIREMENTS.md, *iOS — accepted risk*).
  ///
  /// Embed rows sit in front of UIKit's own text layout manager delegate and forward
  /// everything else to it. If a future iOS stops installing that delegate, these tests
  /// fail, by name, before anyone ships on that iOS.
  @MainActor
  @Suite("UIKit layout delegate chain (iOS accepted-risk tripwire)", .serialized)
  struct UIKitLayoutDelegateChainTests {

    @Test("UITextView still installs its own text layout manager delegate")
    func uikitDelegateIsPresent() throws {
      let editor = EscriboTextView(language: .fountain, theme: .fountainLight)
      let layoutManager = try #require(editor.textView.textLayoutManager)
      #expect(
        layoutManager.delegate != nil,
        """
        UIKit no longer installs a text layout manager delegate on UITextView. \
        UIKitLayoutDelegateChain forwards to it; embed rows must be re-verified on this iOS.
        """)
    }

    @Test("The chain holds UIKit's delegate and forwards what it does not answer")
    func chainHoldsAndForwards() throws {
      let harness = try EmbedLayoutHarness()
      let layoutManager = try #require(harness.layoutManager)
      guard let uikit = layoutManager.delegate else {
        Issue.record(
          "UIKit's text layout manager delegate is missing; the embed chain has nothing to forward to.")
        return
      }
      let uikitObject: NSObject = try #require(uikit as? NSObject)
      let before = harness.layout()

      harness.embed()
      let chain = try #require(harness.editor.embedLayout?.delegateChain)
      #expect(layoutManager.delegate === chain)
      guard let held = chain.uikitDelegate else {
        Issue.record("UIKitLayoutDelegateChain lost UIKit's delegate after installing.")
        return
      }
      #expect(held === uikit)

      // Every selector UIKit's delegate answers and the chain does not implement itself is
      // forwarded to UIKit's delegate.
      let forwarded = Self.selectors(of: type(of: uikitObject)).filter {
        uikitObject.responds(to: $0)
          && class_getInstanceMethod(UIKitLayoutDelegateChain.self, $0) == nil
      }
      for selector in forwarded {
        #expect(chain.responds(to: selector), "chain does not answer \(selector)")
        let target = chain.forwardingTarget(for: selector) as? NSObject
        #expect(target === uikitObject)
      }

      // Paragraphs outside the embed get exactly what UIKit's delegate vends.
      let after = harness.layout()
      for (old, new) in zip(before, after) where !harness.note.contains(new.offset) {
        #expect(type(of: new.fragment) == type(of: old.fragment))
        #expect(!(new.fragment is EmbedLayoutFragment))
      }
      #expect(harness.noteParagraphs(after).first?.fragment is EmbedRowFragment)
    }

    /// The instance methods `cls` itself declares.
    private static func selectors(of cls: AnyClass) -> [Selector] {
      var count: UInt32 = 0
      guard let methods = class_copyMethodList(cls, &count) else { return [] }
      defer { free(methods) }
      return (0..<Int(count)).map { method_getName(methods[$0]) }
    }
  }
#endif
