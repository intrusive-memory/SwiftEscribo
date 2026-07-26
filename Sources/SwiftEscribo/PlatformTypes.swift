#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

/// The platform's concrete font class.
///
/// Declared once, here, rather than at each use site. Sorties 10 and 11 ship an AppKit
/// and a UIKit Representable over the *same* styler and the same theme values
/// (Architecture §10), so every type between the scanner and the text view has to be
/// spelled without naming a framework. A `#if` per file is how a "platform-neutral"
/// layer quietly becomes AppKit-shaped.
#if canImport(AppKit)
  typealias PlatformFont = NSFont
#elseif canImport(UIKit)
  typealias PlatformFont = UIFont
#endif

/// The platform's concrete color class.
#if canImport(AppKit)
  typealias PlatformColor = NSColor
#elseif canImport(UIKit)
  typealias PlatformColor = UIColor
#endif

/// The platform's symbolic font traits — the bold/italic bits on a font descriptor.
///
/// The *spelling* of the members differs (`.bold` on AppKit, `.traitBold` on UIKit), so
/// this alias narrows the `#if` to the one function that reads them
/// (``FontResolver/apply(_:to:)``) instead of leaking it into the composition code.
#if canImport(AppKit)
  typealias PlatformSymbolicTraits = NSFontDescriptor.SymbolicTraits
#elseif canImport(UIKit)
  typealias PlatformSymbolicTraits = UIFontDescriptor.SymbolicTraits
#endif
