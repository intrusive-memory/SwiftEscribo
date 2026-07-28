/// Which family a run of text is set in — the one font choice a theme makes by name-free
/// intent rather than by naming a face.
///
/// A struct with static members rather than an enum, for the same forward-compatibility
/// reason as `SpanKind` and `ElementKind`: a public enum is source-breaking to extend,
/// and a theme file is exactly the kind of code that ends up with an exhaustive `switch`
/// over this.
///
/// There is deliberately no `.courierPrime` here and no way to spell one. D-4 settles
/// that the screenplay face resolves through a chain ending in
/// `.monospacedSystemFont`, because none of the Courier faces is guaranteed to exist on
/// a CI runner or an iOS device. What geometry depends on is the face being
/// *monospaced*, not which monospaced face it is.
public struct FontFamilyRole: Hashable, Sendable {

  /// The stable identifier for this role.
  public let rawValue: String

  /// Creates a family role from a raw value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// The reading face — the system body font.
  public static let body = FontFamilyRole(rawValue: "body")

  /// A fixed-advance face. Screenplay geometry at 10 CPI and Markdown code both resolve
  /// here; ``FontResolver`` decides which concrete face that is.
  public static let monospaced = FontFamilyRole(rawValue: "monospaced")
}

/// The font traits a theme can ask for, as a set rather than a scalar.
///
/// A set because traits are the one thing that **unions** across composition stages
/// (REQUIREMENTS.md § Composition order): a code span inside a bold heading must render
/// bold-mono, not mono-only. Everything else a stage contributes overrides.
public struct FontTraits: OptionSet, Hashable, Sendable {

  /// The bitfield backing this trait set.
  public let rawValue: UInt8

  /// Creates a trait set from its raw bitfield.
  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  /// Bold.
  public static let bold = FontTraits(rawValue: 1 << 0)

  /// Italic.
  public static let italic = FontTraits(rawValue: 1 << 1)
}

/// A font, described by intent rather than by a face name.
///
/// This — not a `PlatformFont` — is what ``ResolvedStyle`` carries and what tests
/// compare. Two consequences, both wanted:
///
/// 1. "The marker and its content resolve to the same font at the same point size" is a
///    value comparison of two `Equatable` structs, not an interrogation of two font
///    objects whose equality depends on which of them was built from a descriptor.
/// 2. No test can accidentally assert a resolved family name (D-4), because the family
///    name is not in this type. It appears for the first and only time inside
///    ``FontResolver``.
/// `internal`: nothing in the 1.0 public surface (REQUIREMENTS.md § What is public in
/// 1.0) exposes a resolved font, and nothing becomes public speculatively.
struct FontSpec: Hashable, Sendable {

  /// The family the theme asked for.
  var family: FontFamilyRole

  /// The union of every trait the composition stages contributed.
  var traits: FontTraits

  /// The point size, already scaled by the line's element and the current font metrics.
  ///
  /// Set **per line, never per span** — see ``EscriboStyler``. Two spans on the same line
  /// always carry the same value here, which is Architecture §3 expressed as data.
  var pointSize: Double

  /// Creates a font specification.
  init(family: FontFamilyRole, traits: FontTraits = [], pointSize: Double) {
    self.family = family
    self.traits = traits
    self.pointSize = pointSize
  }
}

/// The text-system metrics the styler resolves against — the fourth of its four
/// invalidation triggers.
///
/// One field today. It is a struct rather than a bare `Double` because Dynamic Type on
/// iOS and the user font-size preference on macOS are the same *trigger* but not the
/// same *quantity*, and a second field arriving later must not change the styler's API or
/// its single invalidation path.
struct FontMetrics: Equatable, Sendable {

  /// A multiplier over every theme's base point size. `1` is the theme's own size.
  var pointSizeScale: Double

  /// The nominal metrics: the theme's declared size, unscaled.
  static let nominal = FontMetrics(pointSizeScale: 1)

  init(pointSizeScale: Double = 1) {
    self.pointSizeScale = pointSizeScale
  }
}
