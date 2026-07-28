import EscriboCore
import Foundation

#if canImport(AppKit)
  import AppKit

  /// The edit-kind option set, spelled as the AppKit SDK vends it.
  typealias TextStorageEditActions = NSTextStorageEditActions
#elseif canImport(UIKit)
  import UIKit

  /// The same option set, which the UIKit SDK renames with `NS_SWIFT_NAME` and AppKit
  /// does not. One `typealias` rather than a branched method body: the difference is how
  /// the two SDKs spell a type, not anything the coordinator does about it.
  typealias TextStorageEditActions = NSTextStorage.EditActions
#endif

// The one file in the editor layer that names a UI framework.
//
// `NSTextStorage` and `NSTextStorageDelegate` live in AppKit on macOS and UIKit on iOS;
// there is no Foundation spelling of either. Everything platform-bound about the
// coordinator is therefore concentrated here, in three small conformances, so that
// `EditorCoordinator.swift` imports nothing but Foundation and `EscriboCore` and the
// claim "the coordinator is platform-neutral" is checkable by `grep` rather than by
// argument.
//
// Note what is *not* here: no branch on behavior. The conditional import picks the
// framework the type is vended from, and the one conditional `typealias` exists because
// AppKit and UIKit disagree about how to *spell* `NSTextStorageEditActions` in Swift —
// not about what it means. Every executable line below is shared. A behavioral `#if`
// appearing in this file later would be the first real evidence that the seam had
// stopped being neutral.

// MARK: - Reading the document as UTF-16

extension NSTextStorage: UTF16TextSource {

  /// The document's length in UTF-16 code units.
  ///
  /// `NSTextStorage` is `NSString`-backed, so its `length` *is* a UTF-16 count. No
  /// conversion, and in particular no `String` bridge.
  public var utf16Count: Int { length }

  /// Copies `range` out of the backing store into `buffer`.
  ///
  /// ## Why `mutableString` and not `string`
  ///
  /// This is the entire point of ``UTF16TextSource`` and it is easy to undo by accident.
  /// `NSAttributedString.string` is imported into Swift as a **`String`**, and bridging
  /// an `NSMutableString` to a Swift `String` must copy it to preserve value semantics.
  /// Reading the document through `.string` would therefore copy the whole document on
  /// every keystroke — the exact cost REQUIREMENTS.md § Edits and text access forbids:
  /// "bridging 120 KB on every keystroke would exceed the whole budget before scanning
  /// began."
  ///
  /// `NSMutableAttributedString.mutableString` returns the backing `NSMutableString`
  /// itself, and `getCharacters(_:range:)` fills the caller's buffer directly. One call
  /// per line, never one per code unit — see ``UTF16TextSource`` on why that shape is the
  /// performance contract rather than a convenience.
  ///
  /// Reading through the mutable-string proxy does not mutate anything and does not open
  /// an editing transaction; only its mutating methods do.
  public func copyUTF16CodeUnits(
    in range: Range<Int>, into buffer: UnsafeMutableBufferPointer<UInt16>
  ) {
    guard !range.isEmpty, let base = buffer.baseAddress else { return }
    mutableString.getCharacters(
      base, range: NSRange(location: range.lowerBound, length: range.count))
  }
}

// MARK: - The coordinator's document seam

/// `NSTextStorage` satisfies ``EditorTextStorage`` with no members of its own.
///
/// `length`, `beginEditing()`, `endEditing()`, `setAttributes(_:range:)`, and
/// `addAttribute(_:value:range:)` are all inherited from `NSMutableAttributedString`,
/// which is Foundation. That emptiness is the load-bearing part: the coordinator's
/// document abstraction is not an adapter over the text system, it is a *subset* of it,
/// so there is no second implementation to drift and no behavior the tests exercise that
/// the real editor does not.
extension NSTextStorage: EditorTextStorage {}

// MARK: - The edit notification

extension EditorCoordinator: NSTextStorageDelegate {

  /// Turns the text system's edit notification into a rescan.
  ///
  /// Two filters, in order:
  ///
  /// 1. **`.editedCharacters` only.** An attribute-only edit reports `.editedAttributes`,
  ///    and every restyle this coordinator performs is an attribute-only edit. Without
  ///    this the coordinator would rescan the document in response to its own output,
  ///    forever.
  /// 2. The coordinator's own re-entrancy guard, inside
  ///    ``EditorCoordinator/didProcessCharacterEdit(editedRange:changeInLength:)``.
  ///
  /// The marked-text guard lives in the coordinator rather than here, because it is a
  /// policy about restyling and not a fact about the notification — and because putting
  /// it here would put it on the platform-specific side of the seam, where each
  /// Representable would have to remember it separately.
  @objc
  func textStorage(
    _ textStorage: NSTextStorage,
    didProcessEditing editedMask: TextStorageEditActions,
    range editedRange: NSRange,
    changeInLength delta: Int
  ) {
    guard editedMask.contains(.editedCharacters) else { return }
    didProcessCharacterEdit(editedRange: editedRange, changeInLength: delta)
  }
}

extension EditorCoordinator {

  /// Installs the coordinator as `storage`'s delegate.
  ///
  /// `NSTextStorage.delegate` is a **weak** reference, so the caller must keep the
  /// coordinator alive for as long as the document exists — which the Representables do
  /// by holding it as their SwiftUI coordinator.
  ///
  /// Does not scan. Call ``EditorCoordinator/restyleEverything()`` once the storage holds
  /// the document's initial contents.
  func attach(to storage: NSTextStorage) {
    storage.delegate = self
  }

  /// Creates a coordinator over `storage` and installs itself as its delegate.
  ///
  /// The shape both Representables use: one call, one object, no window in which the
  /// storage is live but unobserved.
  convenience init(
    attachingTo storage: NSTextStorage, language: Language, styler: EscriboStyler
  ) {
    self.init(textStorage: storage, language: language, styler: styler)
    attach(to: storage)
  }
}
