#if os(macOS) || os(iOS)
  import EscriboCore
  import Foundation

  #if os(macOS)
    import AppKit
  #else
    import UIKit
  #endif

  #if os(macOS)
    // MARK: - macOS: tool tip rectangles over the rows

    /// The drawn embeds' tool tips on macOS (``EscriboEmbed/toolTip``): one tool tip
    /// rectangle per embed that has one, over its row, registered on the text view with
    /// `addToolTip(_:owner:userData:)`.
    ///
    /// Only the tags added here are ever removed (`removeToolTip(_:)`), never
    /// `removeAllToolTips()`, which would also take AppKit's own.
    ///
    /// ## Keeping the rectangles on their rows
    ///
    /// A tool tip rectangle is in the text view's coordinates, so scrolling moves it for
    /// free. What moves a row is a change to the embed set, an edit or restyle above it, or a
    /// width change. Each asks for a refresh on the next turn of the main run loop — never
    /// synchronously, because the first two arrive from inside the text storage's edit
    /// processing, where laying text out is not safe, and an embed that just appeared is
    /// re-vended as a row only on that later turn (``EmbedLayoutController/redraw(_:)``).
    /// A refresh that would register exactly the rectangles and strings already registered
    /// changes nothing.
    ///
    /// Created with the first embed (``EscriboTextView/installEmbedLayout()``); with none in
    /// the document there is no object, no observer and no tool tip.
    @MainActor
    final class MacEmbedToolTips: NSObject, NSViewToolTipOwner {

      /// One registered tool tip.
      struct Registration: Equatable {
        var rect: CGRect
        var text: String
      }

      private weak var editor: EscriboTextView?

      /// The tool tips registered, in document order, with the tags AppKit gave them.
      private(set) var registered: [(tag: NSView.ToolTipTag, registration: Registration)] = []

      /// How many refreshes are queued on the main run loop.
      private(set) var pendingRefreshCount = 0

      /// How many refreshes changed the registered tool tips.
      private(set) var changeCount = 0

      init(editor: EscriboTextView) {
        self.editor = editor
        super.init()
        NotificationCenter.default.addObserver(
          self, selector: #selector(storageDidProcessEditing(_:)),
          name: NSTextStorage.didProcessEditingNotification, object: editor.documentStorage)
      }

      /// The registered tool tips, without their tags.
      var registrations: [Registration] { registered.map(\.registration) }

      // MARK: - Staleness

      /// An edit or restyle moved text, so the rows below it may have moved too.
      @objc private func storageDidProcessEditing(_ notification: Notification) {
        setNeedsRefresh()
      }

      /// Queues a refresh on the next turn of the main run loop. Cheap without tool tips:
      /// with nothing registered and no embed, nothing is queued.
      func setNeedsRefresh() {
        guard let editor, !registered.isEmpty || !editor.coordinator.embeddedBlocks.isEmpty
        else { return }
        pendingRefreshCount += 1
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          self.pendingRefreshCount -= 1
          self.refresh()
        }
      }

      // MARK: - Refreshing

      /// Registers one tool tip per drawn embed with a ``EscriboEmbed/toolTip``, over its
      /// row, removing the tags it added before. Does nothing when that set is unchanged.
      func refresh() {
        guard let editor else { return }
        let textView = editor.textView
        var wanted: [Registration] = []
        if let layout = editor.embedLayout {
          let length = editor.documentStorage.length
          for embedded in editor.coordinator.embeddedBlocks
          where embedded.block.range.upperBound <= length {
            guard let text = embedded.embed.toolTip, !text.isEmpty,
              let row = layout.rowRect(for: embedded), !row.isEmpty
            else { continue }
            wanted.append(Registration(rect: row, text: text))
          }
        }
        guard wanted != registrations else { return }
        changeCount += 1
        for entry in registered { textView.removeToolTip(entry.tag) }
        registered = wanted.map { registration in
          (textView.addToolTip(registration.rect, owner: self, userData: nil), registration)
        }
      }

      // MARK: - NSViewToolTipOwner

      func view(
        _ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
        userData data: UnsafeMutableRawPointer?
      ) -> String {
        registered.first { $0.tag == tag }?.registration.text ?? ""
      }
    }
  #else
    // MARK: - iOS: a tool tip interaction on the text view

    /// The drawn embeds' tool tips on iPadOS with a pointer (``EscriboEmbed/toolTip``): one
    /// `UIToolTipInteraction` on the text view, whose delegate answers the tool tip of the
    /// embed row under the pointer, or `nil` anywhere else.
    ///
    /// Pull-based, so nothing moves with the rows: the rows are looked up when the pointer
    /// rests. Created with the first embed (``EscriboTextView/installEmbedLayout()``); with
    /// none in the document there is no interaction.
    @MainActor
    final class IOSEmbedToolTips: NSObject, UIToolTipInteractionDelegate {

      private weak var editor: EscriboTextView?

      /// The interaction installed on the text view.
      let interaction = UIToolTipInteraction()

      init(editor: EscriboTextView) {
        self.editor = editor
        super.init()
        interaction.delegate = self
        editor.textView.addInteraction(interaction)
      }

      /// The tool tip of the embed row containing `point` (text-view coordinates), and that
      /// row, or `nil`.
      func toolTip(at point: CGPoint) -> (text: String, row: CGRect)? {
        guard let editor, let layout = editor.embedLayout else { return nil }
        let length = editor.documentStorage.length
        for embedded in editor.coordinator.embeddedBlocks
        where embedded.block.range.upperBound <= length {
          guard let text = embedded.embed.toolTip, !text.isEmpty,
            let row = layout.rowRect(for: embedded), row.contains(point)
          else { continue }
          return (text, row)
        }
        return nil
      }

      func toolTipInteraction(
        _ interaction: UIToolTipInteraction, configurationAt point: CGPoint
      ) -> UIToolTipConfiguration? {
        guard let hit = toolTip(at: point) else { return nil }
        return UIToolTipConfiguration(toolTip: hit.text, in: hit.row)
      }
    }
  #endif

  // MARK: - Installing on the editor

  extension EscriboTextView {

    /// Creates the embed tool tips. Called once, when the first embed appears.
    func installEmbedToolTips() {
      guard textView.embedToolTips == nil else { return }
      #if os(macOS)
        textView.embedToolTips = MacEmbedToolTips(editor: self)
      #else
        textView.embedToolTips = IOSEmbedToolTips(editor: self)
      #endif
    }
  }
#endif
