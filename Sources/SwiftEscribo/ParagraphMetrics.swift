/// How a paragraph is aligned on the page.
///
/// A struct with static members rather than an enum, matching the rest of the package's
/// vocabulary types: a public enum is source-breaking to extend, and a theme file is
/// exactly the kind of code that ends up with an exhaustive `switch` over this.
///
/// Named `ParagraphAlignment` rather than `Alignment`. The SwiftUI view arrives in a later
/// sortie and `SwiftUI.Alignment` is a different concept with the more obvious name; a
/// public type that collides with it inside a file that imports SwiftUI is a rename
/// waiting to happen, and renaming public API is a major release.
public struct ParagraphAlignment: Hashable, Sendable {

  /// The stable identifier for this alignment.
  public let rawValue: String

  /// Creates an alignment from a raw value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Whatever the paragraph's writing direction implies. The default, and the only
  /// alignment that is correct in both writing directions without being chosen per
  /// document.
  public static let natural = ParagraphAlignment(rawValue: "natural")

  /// Flush left.
  public static let left = ParagraphAlignment(rawValue: "left")

  /// Flush right. Fountain transitions.
  public static let right = ParagraphAlignment(rawValue: "right")

  /// Centered. Fountain centered text.
  public static let center = ParagraphAlignment(rawValue: "center")
}

/// A paragraph's geometry, **in characters and multiples of line height — never points**.
///
/// ## Why characters
///
/// Screenplay margins are defined in characters at 10 CPI (REQUIREMENTS.md § Editor 3), so
/// the theme stores characters and the styler converts to points against the resolved
/// font's advance width. Storing points would silently break every margin the moment a
/// user changed font size, and would make the monospaced-face requirement a hidden
/// coupling instead of an explicit one. The same argument applies vertically, which is why
/// ``spaceBeforeLines`` is a multiple of line height rather than a point value.
///
/// Nothing in this type can be applied to a text view on its own — it has no units. Points
/// appear only in ``paragraphStyle(in:)``, against a ``FontGeometry`` measured from the
/// face that was actually resolved.
///
/// ## Why `firstLineIndentChars` is relative
///
/// It is an offset **from** ``leftIndentChars``, not an absolute left edge. A hanging
/// indent — a Markdown list item whose continuation lines sit under its text — is then a
/// negative value, an ordinary first-line indent is positive, and "same as the rest of the
/// paragraph" is `0`. Were it absolute, the overwhelmingly common case of "no special
/// first line" would have to repeat `leftIndentChars`, and every rule set that forgot
/// would silently render its first line flush left.
public struct ParagraphMetrics: Equatable, Sendable {

  /// The left margin, in characters. Applies to every line of the paragraph.
  public var leftIndentChars: Double

  /// The right margin, in characters, measured inward from the text container's trailing
  /// edge. `0` is the container's own margin.
  public var rightIndentChars: Double

  /// The first line's additional indent, in characters, **relative to**
  /// ``leftIndentChars``. Negative hangs the first line outward.
  public var firstLineIndentChars: Double

  /// Vertical space before the paragraph, in multiples of the resolved line height.
  public var spaceBeforeLines: Double

  /// How the paragraph is aligned.
  public var alignment: ParagraphAlignment

  /// Creates paragraph metrics. Every field defaults to "no geometry".
  public init(
    leftIndentChars: Double = 0,
    rightIndentChars: Double = 0,
    firstLineIndentChars: Double = 0,
    spaceBeforeLines: Double = 0,
    alignment: ParagraphAlignment = .natural
  ) {
    self.leftIndentChars = leftIndentChars
    self.rightIndentChars = rightIndentChars
    self.firstLineIndentChars = firstLineIndentChars
    self.spaceBeforeLines = spaceBeforeLines
    self.alignment = alignment
  }

  /// No geometry: no indents, no space before, natural alignment.
  ///
  /// This is what an element with no rule resolves to, what *every* element resolves to
  /// when a theme's geometry is switched off, and — because it converts through the same
  /// arithmetic as any other value — what a text view sees as its own default paragraph
  /// style. Geometry-off is therefore not a second code path; it is this value.
  public static let `default` = ParagraphMetrics()

  /// Whether this is ``default`` — no geometry at all.
  public var isDefault: Bool { self == .default }
}
