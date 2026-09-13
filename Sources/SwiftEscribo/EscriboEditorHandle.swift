import Combine
import CoreGraphics
import EscriboCore
import Foundation

/// A host's handle on a live ``EscriboEditor``, and the only way to ask the editor a
/// question about its document without reaching for the platform text view.
///
/// ## Why this exists
///
/// ``EscriboEditor`` is a SwiftUI `View`: a value, recreated on every layout pass, with no
/// identity a host can hold. The thing with identity is its ``EditorCoordinator``, which
/// the Representable creates once and keeps. A host that wanted to ask "which block is the
/// caret in?" therefore had exactly one option before 0.4.0 — walk the view hierarchy,
/// find the `NSTextView` or `UITextView`, and cast. Escribir has exactly one such cast per
/// platform in its whole codebase, and a later check asserts that count never grows.
///
/// This is the seam that keeps it at one. The host creates a handle, passes it to the
/// editor, and the editor fills it in:
///
/// ```swift
/// @StateObject private var editor = EscriboEditorHandle()
///
/// var body: some View {
///   EscriboEditor(text: $text, language: .markdown, handle: editor)
///     .onHover { _ in
///       if let block = editor.block(at: location) { … }
///     }
/// }
/// ```
///
/// ## Lifetime and identity
///
/// A handle is empty until the editor is installed, and it is filled in on the main thread
/// during view construction. It holds its coordinator **weakly**: the Representable owns
/// the editor, and a handle that kept it alive would make a host's `@StateObject` outlive
/// the view it was handed to. So every query answers `nil` or `[]` when there is no live
/// editor, which is also what a query before installation gets. There is no error to
/// report and nothing to trap on — a host asking early gets the same answer as a host
/// asking about an offset that does not exist.
///
/// `ObservableObject`, but it publishes nothing. It conforms so a host can hold it in
/// `@StateObject` and get SwiftUI's lifetime guarantees; the queries are pull-only,
/// because a block query's answer changes on every keystroke and a published one would
/// invalidate a host's view on every keystroke with it.
public final class EscriboEditorHandle: ObservableObject {

  /// The live editor's coordinator, or `nil` before one is installed.
  ///
  /// Weak on purpose — see the discussion. `public` to read because a host may legitimately
  /// want the richer surface; `internal` to set, because only the Representable knows when
  /// there is an editor to point at.
  public private(set) weak var coordinator: EditorCoordinator?

  /// Creates an empty handle. Fill it by passing it to ``EscriboEditor``.
  public init() {}

  /// Points this handle at `coordinator`.
  ///
  /// Called by ``EscriboEditorBridge`` as it builds the editor, and by nothing else.
  /// Idempotent, and safe to call again when a Representable rebuilds its editor.
  func attach(to coordinator: EditorCoordinator) {
    self.coordinator = coordinator
  }

  // MARK: - Block queries (REQUIREMENTS-1.1.0 § 4.3)

  /// The block containing `offset`, or `nil` if there is no live editor or the offset lies
  /// outside its document.
  ///
  /// A **block** is the writer's unit of thought rather than the editor's line — a whole
  /// hard-wrapped paragraph, one list item, a speech. See
  /// ``EditorCoordinator/block(atUTF16Offset:)`` for what it costs to ask.
  public func block(atUTF16Offset offset: Int) -> EscriboBlock? {
    coordinator?.block(atUTF16Offset: offset)
  }

  /// The block under `point`, in the editor's text-view coordinates.
  ///
  /// A point in the well's lane — to the left of the text — resolves to the block on the
  /// line at that `y`. See ``EditorCoordinator/block(at:)`` for why that needs no special
  /// case.
  public func block(at point: CGPoint) -> EscriboBlock? {
    coordinator?.block(at: point)
  }

  /// Every block intersecting `visibleRect`, in the editor's text-view coordinates, in
  /// document order.
  public func blocks(in visibleRect: CGRect) -> [EscriboBlock] {
    coordinator?.blocks(in: visibleRect) ?? []
  }
}
