import EscriboCore
import Foundation

/// The whole of what ``EditorCoordinator`` needs from a document's backing store.
///
/// ## Why this exists rather than a direct `NSTextStorage` reference
///
/// `NSTextStorage` lives in **AppKit on macOS and UIKit on iOS**. A coordinator typed
/// against it must import one of those two frameworks, and REQUIREMENTS.md Architecture
/// §10 is explicit that the coordinator is where platform parity is either structural or
/// lost: "A coordinator shaped around AppKit does not retrofit to UIKit cheaply."
///
/// So the coordinator is typed against this instead. Every member below is inherited by
/// `NSTextStorage` from `NSMutableAttributedString`, which is **Foundation** — the
/// conformance in `NSTextStorageBridge.swift` is therefore literally empty, and there is
/// no adapter, no shim, and no second implementation to keep in sync. The seam costs one
/// existential dispatch per span and buys a coordinator file that provably names no UI
/// framework at all.
///
/// It is deliberately **not** a general "text storage" abstraction. It contains exactly
/// the four mutations Architecture §8 permits and nothing else — note the absence of the
/// whole-string assignment that §8 forbids, and of every character-mutating method. A
/// restyle cannot change the document's characters even by accident, because from here it
/// cannot express one.
///
/// ``UTF16TextSource`` is a refinement rather than a separate parameter because the
/// scanner reads the same object the styler writes: one reference, read as code units and
/// written as attributes, with no possibility of the two disagreeing about which document
/// is under the caret.
protocol EditorTextStorage: AnyObject, UTF16TextSource {

  /// The document's length in UTF-16 code units, as the text system counts it.
  var length: Int { get }

  /// Opens a batch of attribute changes. Balanced by ``endEditing()``.
  func beginEditing()

  /// Closes the batch opened by ``beginEditing()`` and lets layout run once.
  func endEditing()

  /// **Replaces** the entire attribute dictionary over `range`.
  ///
  /// Replaces, not merges — see DL-44 and ``EditorCoordinator/apply(_:)``. Anything set
  /// before this call over an overlapping range is gone.
  func setAttributes(_ attributes: [NSAttributedString.Key: Any]?, range: NSRange)

  /// Adds one attribute over `range`, leaving every other attribute alone.
  ///
  /// The additive counterpart to ``setAttributes(_:range:)``, and the only way a
  /// per-paragraph attribute survives a per-span attribute pass.
  func addAttribute(_ name: NSAttributedString.Key, value: Any, range: NSRange)
}

extension EditorTextStorage {

  /// Scans this document in full.
  ///
  /// ## Why the scan is entered from here rather than from the coordinator
  ///
  /// ``EditorCoordinator`` holds its document as `any EditorTextStorage`, and Swift will
  /// not pass an existential to a `some UTF16TextSource` parameter even when the
  /// existential's protocol refines it — `any EditorTextStorage` does not itself conform
  /// to `UTF16TextSource`. Inside a protocol extension `Self` is a concrete conforming
  /// type, so this is the one place the call is legal.
  ///
  /// The alternative was to make the coordinator generic over its storage type. That was
  /// rejected: Sortie 11 must assert that both Representables drive *the same declared
  /// type*, and a generic coordinator would give macOS and iOS two different
  /// specializations to reason about for no benefit — the storage type is `NSTextStorage`
  /// on both platforms anyway.
  func fullScan(using scanner: inout EscriboScanner) -> ScanResult {
    scanner.fullScan(self)
  }

  /// Applies `edit` and rescans the smallest sufficient window of this document.
  ///
  /// - Parameter edit: The mutation in **old-text coordinates**; this document must
  ///   already be in its post-edit state.
  func incrementalScan(_ edit: TextEdit, using scanner: inout EscriboScanner) -> ScanResult {
    scanner.incrementalScan(edit, in: self)
  }
}
