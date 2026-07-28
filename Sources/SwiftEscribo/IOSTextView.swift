#if os(iOS)
  import EscriboCore
  import Foundation
  import UIKit

  /// The iOS half of "both Representables ship together" (REQUIREMENTS.md Architecture
  /// §10): a TextKit 2 `UITextView` wired to the platform-neutral ``EditorCoordinator`` —
  /// the identical declared type ``EscriboTextView`` on macOS (Sortie 10) drives.
  ///
  /// ## `UITextView` self-scrolls
  ///
  /// Unlike the macOS `NSTextView`, which needs an `NSScrollView` to host it, `UITextView`
  /// scrolls itself. That is the entire reason this type has no `scrollView` member where
  /// the macOS `EscriboTextView` has one — there is no second view to construct, own, or
  /// hand to a future `UIViewRepresentable` (Sortie 12). Everything else about the shape
  /// mirrors macOS exactly: `textView`, `coordinator`, the same two initializers.
  ///
  /// ## What this type does, and does not, own
  ///
  /// It **constructs**, **configures**, and **attaches** — nothing more. Every character
  /// attribute this view's text storage ever carries is written by the coordinator's own
  /// two-pass application (span attributes, then paragraph geometry — DL-44). This file
  /// contains no call that assigns a whole new attributed string to the text storage and
  /// no call that sets an individual attribute range itself; that authority stays on the
  /// coordinator's side of the seam, on purpose — exactly as on macOS.
  ///
  /// ## The same coordinator, not a parallel one
  ///
  /// `coordinator` is an ``EditorCoordinator`` — the identical declared type the macOS
  /// `EscriboTextView` drives (DL-58: the coordinator is deliberately non-generic so this
  /// is a fact the type checker enforces, not a convention two files happen to follow).
  /// Nothing AppKit-shaped was added to that type to make this file work, and nothing here
  /// would need to move for a third platform to adopt the same coordinator.
  ///
  /// ## Marked text
  ///
  /// UIKit spells "is a composition in flight" as a **property**, where AppKit spells it
  /// as a method: `markedTextRange != nil` here, `hasMarkedText()` there. The coordinator
  /// only ever sees a closure (DL-55) — the policy that skips restyling during a
  /// composition, counts the skip, and forces a full rescan once composition ends lives
  /// entirely on the coordinator's side, unchanged from macOS. This file supplies only the
  /// one-line answer to the question, nothing more.
  ///
  /// ## Undo
  ///
  /// UIKit's native undo grouping is accepted as-is (REQUIREMENTS.md Known limitations
  /// §1). This file adds no `UndoManager` wiring and no coalescing, and shapes nothing
  /// here around an undo seam — the coordinator has none to begin with (DL-58), so there
  /// is nothing for this view to disturb.
  ///
  /// `@MainActor` because `UITextView` is a main-actor-isolated UIKit type (DL-64), and
  /// because ``EditorCoordinator`` is main-thread-owned by its own contract
  /// (REQUIREMENTS.md § Concurrency and failure) but is deliberately **not** itself
  /// `@MainActor` — `NSTextStorageDelegate` is nonisolated in the SDK, and annotating the
  /// coordinator would force a `MainActor.assumeIsolated` trap onto the hot path of a
  /// text-storage callback. This view is the isolation boundary, exactly as on macOS.
  @MainActor
  final class EscriboTextView {

    /// The text view itself, guaranteed to sit on the TextKit 2 stack — see
    /// ``makeTextView()``. `UITextView` self-scrolls, so unlike the macOS
    /// `EscriboTextView` there is no `scrollView` property here.
    ///
    /// Declared as ``EscriboNativeTextView``, not as `UITextView`, for the reason the macOS
    /// half gives: Sortie 25's Return affordance is an override on that subclass, and typing
    /// the property as the subclass makes "this editor's Return key is wired" a fact the
    /// compiler checks rather than a line someone could delete.
    let textView: EscriboNativeTextView

    /// The platform-neutral coordinator, adopted unchanged (Sortie 9) — the same declared
    /// type the macOS Representable drives.
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

      // Unlike `NSTextView.textStorage`, `UITextView.textStorage` is never optional — no
      // guard, no precondition, nothing to fail.
      let storage = textView.textStorage

      let coordinator = EditorCoordinator(
        attachingTo: storage, language: language, styler: styler)
      self.coordinator = coordinator

      // The exact wiring EditorCoordinator's own doc comment specifies: bind the
      // marked-text closure, then run the first full scan. DL-55: the iOS half of the
      // question is a property, not a method.
      coordinator.hasMarkedText = { [weak textView] in textView?.markedTextRange != nil }
      coordinator.restyleEverything()

      // Sortie 25, wired identically to macOS. UIKit spells the Return key as
      // `insertText("\n")` where AppKit spells it `insertNewline(_:)`; both land on the same
      // `EscriboTextView.handleReturnKey()`, which is the point of Architecture §10.
      textView.returnKeyHandler = { [weak self] in self?.handleReturnKey() ?? false }

      // Sortie 26, wired identically to macOS. UIKit spells the Tab key as
      // `insertText("\t")` where AppKit spells it `insertTab(_:)`; both land on the same
      // `EscriboTextView.handleTabKey()`. Undo granularity for what it does is whatever UIKit
      // provides (Known limitations §1); the *shape* — one transaction through the text
      // view's own input path — is identical on both platforms, which is what Architecture
      // §10 requires.
      textView.tabKeyHandler = { [weak self] in self?.handleTabKey() ?? false }
    }

    /// Builds the view over a fresh styler constructed from `theme`.
    convenience init(language: Language, theme: EscriboTheme) {
      self.init(language: language, styler: EscriboStyler(theme: theme))
    }

    // MARK: - Host configuration

    /// Whether autocorrect is enabled. **Off by default**
    /// (REQUIREMENTS.md § Text-system hygiene: "Autocorrect on iOS, by default. A host may
    /// opt in; it mutates text and can eat markers.") — the one hygiene setting a host may
    /// override. Smart quotes and smart dashes have no such opt-in anywhere in this file:
    /// Text-system hygiene forbids them outright, on both platforms, with no exception
    /// carved out for a host to reverse.
    var isAutocorrectionEnabled: Bool {
      get { textView.autocorrectionType == .yes }
      set { textView.autocorrectionType = newValue ? .yes : .no }
    }

    // MARK: - Construction

    /// Builds a `UITextView` guaranteed to sit on the TextKit 2 stack, with the
    /// text-system hygiene settings REQUIREMENTS.md § Text-system hygiene requires.
    ///
    /// Sortie 10 hit the AppKit shape of this trap: "`NSTextView`'s older initializers do
    /// not all agree on which layout stack they hand back." UIKit carries the identical
    /// trap and the identical fix — `UITextView` also vends `init(usingTextLayoutManager:)`,
    /// the one initializer that states the layout stack as an explicit, checkable argument
    /// rather than an inferred default. The resulting view's `textLayoutManager` is
    /// guaranteed non-nil.
    private static func makeTextView() -> EscriboNativeTextView {
      let textView = EscriboNativeTextView(usingTextLayoutManager: true)

      // REQUIREMENTS.md § Text-system hygiene: every one of these rewrites the user's
      // source behind their back, and in an editor whose premise is that the string is
      // the value (Architecture §1), that is corruption, not convenience.
      textView.smartQuotesType = .no
      textView.smartDashesType = .no
      textView.autocorrectionType = .no

      // Spell *checking* is a separate trait from autocorrect, but `.default` is not a
      // neutral choice here: UIKit defines `.default` as "enable spell checking based on
      // the state of autocorrection", so leaving it alone with `autocorrectionType = .no`
      // above would silently turn spell checking off too. REQUIREMENTS.md § Text-system
      // hygiene wants checking on regardless — "permitted and encouraged," with no
      // platform qualification, because it draws with temporary attributes that never
      // participate in `setAttributes(_:range:)` and so cannot be clobbered by a restyle.
      // Sortie 10 expresses the identical intent on macOS with
      // `isContinuousSpellCheckingEnabled = true`; this is that same intent stated
      // explicitly rather than left to an autocorrect-coupled default.
      textView.spellCheckingType = .yes

      // Self-scrolling — the whole reason this type has no `scrollView` member.
      textView.isScrollEnabled = true

      return textView
    }
  }
#endif
