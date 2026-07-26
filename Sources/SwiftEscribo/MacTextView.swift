#if os(macOS)
  import AppKit
  import EscriboCore
  import Foundation

  /// The macOS half of "both Representables ship together"
  /// (REQUIREMENTS.md Architecture §10): a TextKit 2 `NSTextView` embedded in an
  /// `NSScrollView`, wired to the platform-neutral ``EditorCoordinator``.
  ///
  /// ## What this type does, and does not, own
  ///
  /// It **constructs**, **configures**, and **attaches** — nothing more. Every character
  /// attribute this view's text storage ever carries is written by the coordinator's own
  /// two-pass application (span attributes, then paragraph geometry — DL-44). This file
  /// contains no call that assigns a whole new attributed string to the text storage and
  /// no call that sets an individual attribute range itself; that authority stays on the
  /// coordinator's side of the seam, on purpose.
  ///
  /// ## Sortie 11 mirrors this shape
  ///
  /// `UITextView` self-scrolls, so the iOS counterpart has no `scrollView` property, but
  /// it exposes the same `textView` and `coordinator` members, is wired with the same
  /// three lines documented on ``EditorCoordinator``, and drives the **same declared**
  /// `EditorCoordinator` type — nothing AppKit-only was added to the coordinator to make
  /// this file work, and nothing here would need to move for iOS to adopt it.
  ///
  /// `@MainActor` because `NSTextView` and `NSScrollView` are main-actor-isolated AppKit
  /// types, and because ``EditorCoordinator`` is main-thread-owned by its own contract
  /// (REQUIREMENTS.md § Concurrency and failure) — this type is where that contract meets
  /// a real text view, so it is pinned to the same actor as both.
  @MainActor
  final class EscriboTextView {

    /// The scroll container hosting `textView`. This is the view a future
    /// `NSViewRepresentable` (Sortie 12) would return from `makeNSView(context:)`.
    let scrollView: NSScrollView

    /// The text view itself, guaranteed to sit on the TextKit 2 stack — see
    /// ``makeTextView()``.
    let textView: NSTextView

    /// The platform-neutral coordinator, adopted unchanged (Sortie 9).
    let coordinator: EditorCoordinator

    /// Builds the view over `styler`.
    ///
    /// - Parameters:
    ///   - language: The grammar to scan with.
    ///   - styler: The style cache. Pass the same instance for the document's lifetime —
    ///     ``EscriboStyler`` is a cache, and a fresh one per edit would make it pointless.
    init(language: Language, styler: EscriboStyler) {
      let textView = Self.makeTextView()
      self.textView = textView
      self.scrollView = Self.makeScrollView(hosting: textView)

      guard let storage = textView.textStorage else {
        preconditionFailure("an NSTextView always vends a textStorage")
      }

      let coordinator = EditorCoordinator(
        attachingTo: storage, language: language, styler: styler)
      self.coordinator = coordinator

      // The exact wiring EditorCoordinator's own doc comment specifies: bind the
      // marked-text closure, then run the first full scan.
      coordinator.hasMarkedText = { [weak textView] in textView?.hasMarkedText() ?? false }
      coordinator.restyleEverything()
    }

    /// Builds the view over a fresh styler constructed from `theme`.
    convenience init(language: Language, theme: EscriboTheme) {
      self.init(language: language, styler: EscriboStyler(theme: theme))
    }

    // MARK: - Construction

    /// Builds an `NSTextView` guaranteed to sit on the TextKit 2 stack, with the
    /// text-system hygiene settings REQUIREMENTS.md § Text-system hygiene requires.
    ///
    /// `NSTextView`'s older initializers do not all agree on which layout stack they hand
    /// back, and the plan calls that out explicitly: "`NSTextView` can silently fall back
    /// to TextKit 1 depending on how it is created." `init(usingTextLayoutManager:)` is
    /// the one initializer that states the layout stack as an explicit, checkable
    /// argument rather than an inferred default, so it is the only one used here — the
    /// resulting view's `textLayoutManager` is guaranteed non-nil.
    private static func makeTextView() -> NSTextView {
      let textView = NSTextView(usingTextLayoutManager: true)

      // REQUIREMENTS.md § Text-system hygiene: every one of these rewrites the user's
      // source behind their back, and in an editor whose premise is that the string is
      // the value (Architecture §1), that is corruption, not convenience.
      textView.isAutomaticQuoteSubstitutionEnabled = false
      textView.isAutomaticDashSubstitutionEnabled = false
      textView.isAutomaticTextReplacementEnabled = false
      textView.isAutomaticSpellingCorrectionEnabled = false

      // Spell *checking* is explicitly permitted: it draws with temporary attributes on
      // the layout manager, never with a text-storage attribute, so it cannot be clobbered
      // by a restyle and cannot corrupt the source. Left on, and left explicit rather than
      // relying on the system default.
      textView.isContinuousSpellCheckingEnabled = true

      // Plain text is the value (Architecture §1): every attribute this view's storage
      // ever carries is syntax styling the coordinator applies, never user-chosen rich
      // text from a font panel or a formatted paste.
      textView.isRichText = false
      textView.usesFontPanel = false
      textView.allowsUndo = true

      textView.isVerticallyResizable = true
      textView.isHorizontallyResizable = false
      textView.autoresizingMask = [.width]
      textView.minSize = NSSize(width: 0, height: 0)
      textView.maxSize = NSSize(
        width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
      textView.textContainer?.widthTracksTextView = true
      textView.textContainer?.containerSize = NSSize(
        width: 0, height: CGFloat.greatestFiniteMagnitude)

      return textView
    }

    /// Wraps `textView` in a scroll view configured for vertical text flow.
    private static func makeScrollView(hosting textView: NSTextView) -> NSScrollView {
      let scrollView = NSScrollView()
      scrollView.hasVerticalScroller = true
      scrollView.hasHorizontalScroller = false
      scrollView.autohidesScrollers = true
      scrollView.documentView = textView
      return scrollView
    }
  }
#endif
