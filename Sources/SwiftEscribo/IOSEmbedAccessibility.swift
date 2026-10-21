#if os(iOS)
  import EscriboCore
  import Foundation
  import UIKit

  /// Block embeds for VoiceOver on iOS (REQUIREMENTS.md § 1.4): one button element per drawn
  /// embed, with the host's label, value and identifier, activation calling
  /// `onEmbedActivate`, and the host's ``EscriboEmbed/actions`` as custom actions — which is
  /// how a touch-only user reaches *Edit as Text*.
  ///
  /// ## Why subviews, not `accessibilityElements`
  ///
  /// `UITextView` is itself an accessibility element (the text area VoiceOver reads and
  /// edits the document through), and UIKit never asks an element for its
  /// `accessibilityElements`. The live check (IOS_LIVE_CHECK.md row f) showed exactly that:
  /// an override there leaves the tree with the text area and no embed. Turning the text
  /// view into a plain container (`isAccessibilityElement = false`) would surface the
  /// override, but it would take the document text away from VoiceOver, so it is not done.
  ///
  /// UIKit *does* walk a text view's subviews — the scroll bars are found that way — so each
  /// embed gets an ``EmbedAccessibilityElement``: a transparent `UIView` laid over its row.
  /// The text view stays the same text area, the embed appears as a button under it, and
  /// UIKit's own count / index answers are correct, so nothing is answered by hand.
  ///
  /// The elements sit in one ``EmbedAccessibilityContainer``, a plain subview of the text
  /// view at its content origin, rather than directly in the text view: in the simulator's
  /// accessibility tree a **direct** subview of a text view that carries an
  /// `accessibilityIdentifier` is listed twice (any view, not just these), which would make
  /// a host's UI test query for the identifier ambiguous. Inside a container it is listed
  /// once.
  ///
  /// The views draw nothing and take no touches (`isUserInteractionEnabled == false` on the
  /// container): a tap on the row still reaches the text view and ``IOSEmbedInput``.
  /// VoiceOver activates through `accessibilityActivate()`, which needs no touch handling.
  ///
  /// ## Keeping the views on their rows
  ///
  /// Subviews of a scroll view live in content coordinates, so scrolling moves them for
  /// free. What moves a row is a change to the embed set, an edit or restyle (anything
  /// above the row can change its `y`), or a width change. Each marks the views stale and
  /// asks the text view for a layout pass, in which ``syncIfNeeded()`` reads the
  /// coordinator's embed cache and ``EmbedLayoutController/rowRect(for:)`` again.
  ///
  /// - The embed set: a callout from the layout controller's change hook
  ///   (``EscriboTextView/installEmbedLayout()``), which owns the coordinator's single slot.
  /// - Edits and restyles: the text storage's did-process-editing notification.
  /// - Width: ``EscriboNativeTextView/layoutSubviews()``.
  ///
  /// With no embed in the document there are no views, and a sync does nothing (§ 1.5).
  @MainActor
  final class IOSEmbedAccessibility: NSObject {

    private weak var editor: EscriboTextView?

    /// One view per drawn embed, in document order. Valid after ``syncIfNeeded()``.
    private(set) var elements: [EmbedAccessibilityElement] = []

    /// The view the elements live in. Created with the first element.
    private(set) var container: EmbedAccessibilityContainer?

    /// Whether the views may no longer match the embed cache or the rows.
    private(set) var isStale = false

    /// How many syncs have run. Lets a test prove a pass without embeds does nothing.
    private(set) var syncCount = 0

    init(editor: EscriboTextView) {
      self.editor = editor
      super.init()
      NotificationCenter.default.addObserver(
        self, selector: #selector(storageDidProcessEditing(_:)),
        name: NSTextStorage.didProcessEditingNotification, object: editor.textView.textStorage)
    }

    // MARK: - Staleness

    /// The embed set changed (the layout controller's callout).
    func embedsDidChange() {
      invalidate()
    }

    /// The text view's width changed.
    func layoutDidChange() {
      invalidate()
    }

    /// An edit or restyle moved text, so the rows below it may have moved too.
    @objc private func storageDidProcessEditing(_ notification: Notification) {
      invalidate()
    }

    /// Marks the views stale and asks for a layout pass. Cheap without embeds: nothing to
    /// move, so no layout pass is requested.
    private func invalidate() {
      guard let editor, !elements.isEmpty || !editor.coordinator.embeddedBlocks.isEmpty
      else { return }
      isStale = true
      editor.textView.setNeedsLayout()
    }

    // MARK: - Syncing

    /// Brings the views in line with the embed cache and the rows, if anything moved since
    /// the last sync. Called from the text view's layout pass.
    func syncIfNeeded() {
      guard isStale else { return }
      sync()
    }

    /// Makes one view per drawn embed, over its row, with the embed's accessibility.
    func sync() {
      isStale = false
      guard let editor else { return }
      syncCount += 1
      let textView = editor.textView
      let length = editor.documentStorage.length
      let layout = editor.embedLayout
      var placed: [(EmbeddedBlock, CGRect)] = []
      for embedded in editor.coordinator.embeddedBlocks
      where embedded.block.range.upperBound <= length {
        guard let layout, let row = layout.rowRect(for: embedded) else { continue }
        placed.append((embedded, row))
      }

      let countChanged = placed.count != elements.count
      while elements.count > placed.count {
        elements.removeLast().removeFromSuperview()
      }
      if !placed.isEmpty, container == nil {
        let container = EmbedAccessibilityContainer()
        textView.addSubview(container)
        self.container = container
      }
      // At the content origin, so an element's frame is its row's text-view rectangle.
      container?.frame = CGRect(
        x: 0, y: 0, width: textView.bounds.width,
        height: max(textView.contentSize.height, textView.bounds.height))
      while elements.count < placed.count {
        let element = EmbedAccessibilityElement(owner: self)
        container?.addSubview(element)
        elements.append(element)
      }
      for (element, (embedded, row)) in zip(elements, placed) {
        element.update(embedded: embedded, frame: row)
      }
      if countChanged {
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
      }
    }

    // MARK: - Actions

    /// VoiceOver activated `element`: the same as a tap on the row — the whole block is
    /// selected and `onEmbedActivate` is called once.
    fileprivate func activate(_ element: EmbedAccessibilityElement) -> Bool {
      guard let editor, let embedded = element.embedded else { return false }
      let range = embedded.block.range
      editor.textView.selectedRange = NSRange(location: range.lowerBound, length: range.count)
      editor.coordinator.embeds.onActivate(embedded.block)
      return true
    }

    /// VoiceOver ran the custom action `id` on `element`.
    fileprivate func perform(_ id: String, on element: EmbedAccessibilityElement) -> Bool {
      guard let editor, let embedded = element.embedded else { return false }
      editor.coordinator.embeds.onAction(embedded.block, id)
      return true
    }
  }

  // MARK: - The container

  /// Holds the embeds' accessibility elements; see ``IOSEmbedAccessibility``. Not an
  /// element itself, draws nothing, and takes no touches.
  final class EmbedAccessibilityContainer: UIView {
    override init(frame: CGRect) {
      super.init(frame: frame)
      isUserInteractionEnabled = false
      isOpaque = false
      backgroundColor = nil
      isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
  }

  // MARK: - The element

  /// The accessibility element of one drawn embed: a transparent, touch-free view over its
  /// row, inside the ``EmbedAccessibilityContainer``. See ``IOSEmbedAccessibility``.
  final class EmbedAccessibilityElement: UIView {

    private weak var owner: IOSEmbedAccessibility?

    /// The embedded block this element stands for, as of the last sync.
    private(set) var embedded: EmbeddedBlock?

    init(owner: IOSEmbedAccessibility) {
      self.owner = owner
      super.init(frame: .zero)
      isUserInteractionEnabled = false
      isOpaque = false
      backgroundColor = nil
      isAccessibilityElement = true
      accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Points the element at `embedded`, drawn in `frame` (text-view coordinates).
    func update(embedded: EmbeddedBlock, frame: CGRect) {
      self.embedded = embedded
      if self.frame != frame { self.frame = frame }
      let embed = embedded.embed
      accessibilityLabel = embed.accessibilityLabel
      accessibilityValue = embed.accessibilityValue
      accessibilityIdentifier = embed.accessibilityIdentifier
      if installedActions != embed.actions {
        installedActions = embed.actions
        accessibilityCustomActions = embed.actions.map { action in
          UIAccessibilityCustomAction(name: action.title) { [weak self] _ in
            guard let self else { return false }
            return self.owner?.perform(action.id, on: self) ?? false
          }
        }
      }
    }

    /// The host's actions the custom actions were last built from.
    private var installedActions: [EscriboEmbed.Action] = []

    /// The row in screen coordinates, converted explicitly rather than left to the
    /// accessibility runtime's default: into the text view's coordinates first (the row's
    /// own space), then to the screen through the text view, which accounts for scrolling.
    override var accessibilityFrame: CGRect {
      get {
        guard let textView = superview?.superview else { return .zero }
        return UIAccessibility.convertToScreenCoordinates(
          convert(bounds, to: textView), in: textView)
      }
      set {}
    }

    override func accessibilityActivate() -> Bool {
      owner?.activate(self) ?? false
    }
  }

  // MARK: - Installing on the editor

  extension EscriboTextView {

    /// Wires embed accessibility into the text view. Called once, from the initializer.
    /// Inert without embeds: no view is added until the cache holds one.
    func installEmbedAccessibility() {
      let accessibility = IOSEmbedAccessibility(editor: self)
      textView.embedAccessibility = accessibility
    }
  }
#endif
