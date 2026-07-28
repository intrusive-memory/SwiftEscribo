import EscriboCore

/// Marks the editor layer's boundary until WU-2 populates it.
///
/// `SwiftEscribo` is the only half of the package allowed to import a UI framework.
/// Everything here consumes the spans and line records that `EscriboCore` emits; the
/// core never learns that a theme, a text view, or a screen exists.
///
/// Intentionally `internal`: nothing becomes `public` speculatively. The 1.0 public
/// surface of this target is the editor view, the theme, and the geometry value
/// types, all of which arrive with the sorties that implement them.
enum EditorLayer {
  /// The grammars the editor will offer. Placed here so this target has a real
  /// compile-time dependency on `EscriboCore` from the first commit — a target that
  /// only nominally links its dependency hides integration breakage until late.
  static let languages: [Language] = [.markdown, .fountain]
}
