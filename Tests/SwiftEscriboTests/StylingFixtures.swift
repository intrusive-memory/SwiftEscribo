import EscriboCore
import Testing

#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

@testable import SwiftEscribo

/// Shared scaffolding for the styling suites.
///
/// Everything here drives a **real** ``EscriboScanner``. DL-12 keeps `LineRecord`'s and
/// `ScanResult`'s initializers internal to `EscriboCore` by design — a public memberwise
/// init for `LineRecord` would require a publicly constructible `startState` and destroy
/// the opacity Sortie 2 exists to provide. Hand-building spans would also be a weaker
/// test: it cannot catch a styler that mishandles a span shape the scanner actually
/// emits, and the leading-indent `.text` span on an indented heading is exactly such a
/// shape.
enum StylingFixtures {

  /// A document that exercises every span kind and both span roles the Sortie 5 grammar
  /// emits: headings (with and without a closing run, indented and not), a backtick fence
  /// with an info string, a tilde fence without one, and plain paragraphs.
  static let mixedMarkdown = """
    # Title
    Plain paragraph with no syntax at all.

       ### Indented heading
    ```swift
    let answer = 42
    ```
    ## Closed heading ##
    ~~~
    tilde fenced code
    ~~~
    Trailing paragraph.
    """

  /// Scans `text` as Markdown in full.
  static func scan(_ text: String) -> ScanResult {
    var scanner = EscriboScanner(language: .markdown)
    return scanner.fullScan(text)
  }

  /// The line record whose range contains `offset`.
  static func record(containing offset: Int, in result: ScanResult) throws -> LineRecord {
    try #require(result.lineRecords.first { $0.range.contains(offset) })
  }

  /// The record for the line `span` sits on.
  static func record(for span: EscriboSpan, in result: ScanResult) throws -> LineRecord {
    try record(containing: span.range.lowerBound, in: result)
  }

  /// An attribute dictionary reduced to something comparable.
  ///
  /// `[NSAttributedString.Key: Any]` is not `Equatable`, which is precisely why the
  /// styler caches ``ResolvedStyle`` values rather than dictionaries. The exit criterion
  /// is nonetheless stated in terms of an *attribute dictionary*, so it is discharged
  /// against a real one here — keys unwrapped to their raw strings so the comparison does
  /// not depend on how `NSAttributedString.Key` bridges.
  static func comparable(_ attributes: [NSAttributedString.Key: Any]) -> NSDictionary {
    var unwrapped: [String: Any] = [:]
    for (key, value) in attributes {
      unwrapped[key.rawValue] = value
    }
    return unwrapped as NSDictionary
  }

  /// Every `StyleSet` combination over the five flags defined in 1.0 — 32 of them.
  ///
  /// The Sortie 5 grammar emits no emphasis yet, so a scan cannot supply the *style* axis
  /// that "regardless of kind, style, or role" names. Sweeping the axis directly through
  /// the styler's own entry point covers it without fabricating spans.
  static let allStyleCombinations: [StyleSet] = (0..<32).map { StyleSet(rawValue: UInt16($0)) }
}
