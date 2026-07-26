import EscriboCore
import Foundation
import Testing

@testable import SwiftEscribo

#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

/// Counts every edit an `NSTextStorage` actually processes.
///
/// ## Why this mechanism, and why it cannot report zero for the wrong reason
///
/// The exit criterion is "**zero** text-storage mutations," so the witness has to be the
/// storage itself rather than anything the code under test reports about itself. Returning
/// `false` from ``EscriboTextView/applyExternalText(_:)`` is that code's own claim; this is
/// the storage's.
///
/// `NSTextStorage.processEditing()` posts `didProcessEditingNotification` at the end of
/// **every** edit it processes — character edits and attribute-only edits alike, once per
/// `beginEditing()`/`endEditing()` transaction and once per unbracketed mutation. So it
/// catches the `replaceCharacters` of rule 2 *and* the `setAttributes` pass of the restyle
/// that follows it. There is no mutation this package can perform that it would miss:
/// ``EditorTextStorage`` is deliberately narrow enough that the only writes available are
/// the ones that go through `processEditing()`.
///
/// Three things could make it read zero for a reason other than the check working —
/// registration against the wrong object, the notification not firing at all, or a
/// counter that never increments — and all three are the same failure. Every test below
/// therefore runs a **positive control first**: it performs a real replacement on the same
/// instance and asserts the count rose, then resets and performs the equal-string
/// replacement. A zero that follows a nonzero on the same counter and the same storage
/// cannot be a wiring failure.
///
/// No `deinit` unregisters: `NotificationCenter` has held zeroing-weak references to
/// selector-based observers since macOS 10.11 / iOS 9, so an observer outliving nothing is
/// not a leak, and a `deinit` touching `self` from a nonisolated context would be the more
/// interesting problem.
@MainActor
final class TextStorageMutationCounter: NSObject {

  /// How many edits the observed storage has processed since the last ``reset()``.
  private(set) var count = 0

  init(observing storage: NSTextStorage) {
    super.init()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(storageDidProcessEditing(_:)),
      name: NSTextStorage.didProcessEditingNotification,
      object: storage)
  }

  /// Zeroes the count without disturbing the registration.
  func reset() { count = 0 }

  @objc private func storageDidProcessEditing(_ notification: Notification) {
    count += 1
  }
}

/// REQUIREMENTS.md § External text replacement, rule by rule.
///
/// Platform-neutral on purpose, like `PlatformCoordinatorParityTests`: every rule is shared
/// code over a shared seam, so the same source file runs unchanged under `make test` and
/// `make test-ios` and any divergence between the platforms shows up as a failure rather
/// than as an untested branch.
@MainActor
@Suite("External text replacement — the four rules")
struct ExternalTextReplacementTests {

  // MARK: - Rule 1

  @Test("Rule 1: an incoming string equal to storage performs zero text-storage mutations")
  func equalStringPerformsZeroMutations() {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    let counter = TextStorageMutationCounter(observing: editor.documentStorage)
    let document = "# Heading\n\nA plain paragraph.\n"

    // Positive control. If the counter or its registration were broken, this would already
    // read zero and the assertion below would prove nothing.
    #expect(editor.applyExternalText(document) == true)
    #expect(counter.count > 0)
    #expect(editor.currentText == document)
    let restylesAfterRealChange = editor.coordinator.restyleCount

    counter.reset()

    // Rule 1: the same string again.
    #expect(editor.applyExternalText(document) == false)
    #expect(counter.count == 0)

    // A second, independent witness: the coordinator never ran.
    #expect(editor.coordinator.restyleCount == restylesAfterRealChange)
    #expect(editor.currentText == document)
  }

  @Test("Rule 1 holds for the empty document, which is where every editor starts")
  func emptyStringIntoEmptyStorageIsAlsoZero() {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    let counter = TextStorageMutationCounter(observing: editor.documentStorage)

    #expect(editor.applyExternalText("") == false)
    #expect(counter.count == 0)

    // Positive control, after the fact: the same counter does fire for a real change.
    #expect(editor.applyExternalText("x") == true)
    #expect(counter.count > 0)
  }

  @Test("Rule 1 compares content, not identity — a distinct String with equal content is a no-op")
  func equalityIsByContent() {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    editor.applyExternalText("# Heading")

    // Built at runtime, so it cannot be the same String instance the storage was seeded
    // from. SwiftUI hands back a fresh value on every pass; identity comparison would make
    // rule 1 fire never.
    let rebuilt = ["#", "Heading"].joined(separator: " ")
    let counter = TextStorageMutationCounter(observing: editor.documentStorage)
    #expect(editor.applyExternalText(rebuilt) == false)
    #expect(counter.count == 0)
  }

  // MARK: - Rule 2

  @Test("Rule 2: a replacement full-scans, so the whole document is restyled, not a window")
  func replacementFullScansTheDocument() throws {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    editor.applyExternalText("Plain.\n")

    let replacement = "Plain paragraph one.\n\n# A heading far from the edit site\n"
    #expect(editor.applyExternalText(replacement) == true)

    // The last thing the coordinator applied covers the whole new document. An incremental
    // scan of the tail would not.
    let applied = try #require(editor.coordinator.lastAppliedRange)
    #expect(applied.lowerBound == 0)
    #expect(applied.upperBound == editor.documentStorage.length)

    // Non-vacuous: the heading that arrived with the replacement is really styled as one.
    let headingOffset = (replacement as NSString).range(of: "A heading").location
    #expect(headingOffset != NSNotFound)
    let headingAttributes = editor.documentStorage.attributes(
      at: headingOffset, effectiveRange: nil)
    let plainAttributes = editor.documentStorage.attributes(at: 0, effectiveRange: nil)
    let headingFont = try #require(headingAttributes[.font] as? PlatformFont)
    let plainFont = try #require(plainAttributes[.font] as? PlatformFont)
    #expect(headingFont.pointSize > plainFont.pointSize)
  }

  // MARK: - Rule 3

  @Test("Rule 3: a shorter replacement clamps an out-of-range selection to the new length")
  func shorterReplacementClampsSelectionToNewLength() {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    editor.applyExternalText("0123456789")

    // A selection entirely past where the new document ends.
    editor.textView.selectedRange = NSRange(location: 8, length: 2)
    #expect(editor.textView.selectedRange == NSRange(location: 8, length: 2))

    editor.applyExternalText("abc")

    #expect(editor.currentText == "abc")
    // Clamped to the new length — the caret sits at the end of the document, not at zero.
    #expect(editor.textView.selectedRange == NSRange(location: 3, length: 0))
  }

  @Test("Rule 3: a selection straddling the new end keeps the part that survives")
  func straddlingSelectionIsTruncatedNotDropped() {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    editor.applyExternalText("0123456789")

    editor.textView.selectedRange = NSRange(location: 2, length: 5)
    editor.applyExternalText("abc")

    // Anchor survives untouched; only the extent is trimmed to what is left of the
    // document. "Dropped to zero" would have produced (0, 0).
    #expect(editor.textView.selectedRange == NSRange(location: 2, length: 1))
  }

  @Test("Rule 3: a selection wholly inside the new length is left exactly where it was")
  func inRangeSelectionSurvivesAReplacement() {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    editor.applyExternalText("0123456789")

    editor.textView.selectedRange = NSRange(location: 1, length: 2)
    editor.applyExternalText("abcdefghijklmno")

    #expect(editor.textView.selectedRange == NSRange(location: 1, length: 2))
  }

  // MARK: - The value, byte for byte

  @Test(
    "Architecture §1: what you set is what you get back, byte for byte",
    arguments: [
      "",
      "a",
      "a\n",
      "# Heading\r\nCRLF body\r\n",
      "Lone \r carriage return\r",
      "Emoji 👋🏽 and an astral 𝄞 clef\n",
      "```fountain\nINT. HOUSE - DAY\n```\n",
      "trailing spaces   \n\n\n",
    ])
  func documentRoundTripsByteForByte(document: String) {
    let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    editor.applyExternalText(document)
    #expect(Array(editor.currentText.utf8) == Array(document.utf8))
  }
}
