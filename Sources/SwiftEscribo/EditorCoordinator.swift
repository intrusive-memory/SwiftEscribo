import CoreGraphics
import EscriboCore
import Foundation

/// The editor's engine room: it owns the scanner, owns the styler, translates text-system
/// edits into ``TextEdit`` values, and writes the resulting attributes back.
///
/// Both Representables — `NSTextView` on macOS, `UITextView` on iOS — drive **this same
/// type**, not two parallel ones. REQUIREMENTS.md Architecture §10 makes that structural
/// rather than aspirational: "The coordinator, styler, and geometry layer are
/// platform-neutral… A coordinator shaped around AppKit does not retrofit to UIKit
/// cheaply."
///
/// ## How this file stays platform-neutral
///
/// It imports Foundation, CoreGraphics, and `EscriboCore`, and nothing else. Every type
/// that appears in its API is from one of those three. **CoreGraphics is not a UI
/// framework** — it supplies `CGPoint` and `CGRect`, two coordinate structs, and names no
/// text system; it joined the list in 0.4.0 for the block queries (§ 4.3). The
/// distinction that matters is that a `CGPoint` in this type's API is a geometry *value*,
/// while an `NSTextLayoutManager` in its stored state would have been a platform *shape*.
///
/// The four things a real editor needs that *are* platform-specific are each handled
/// without naming a UI framework:
///
/// | Need | AppKit | UIKit | How it enters here |
/// |---|---|---|---|
/// | The document | `NSTextStorage` (AppKit) | `NSTextStorage` (UIKit) | ``EditorTextStorage``, whose members are all `NSMutableAttributedString`'s and therefore Foundation's |
/// | "Is an IME composition in flight?" | `hasMarkedText()` | `markedTextRange != nil` | ``hasMarkedText``, a closure the view supplies |
/// | The edit notification | `NSTextStorageDelegate` | `NSTextStorageDelegate` | ``didProcessCharacterEdit(editedRange:changeInLength:)``, called by the bridge |
/// | "Which character is at this point?" | `characterIndexForInsertion(at:)` | `closestPosition(to:)` + `offset(from:to:)` | ``utf16Offset``, a closure the view supplies |
///
/// The middle row is the one that decides whether the seam retrofits. AppKit spells the
/// question as a **method** on `NSTextInputClient`; UIKit spells it as a **property** on
/// `UITextInput`. No protocol requirement can be satisfied by both directly, so a
/// coordinator that declared one would have forced an adapter type on whichever platform
/// lost the coin toss — and, in practice, would have been written with `hasMarkedText()`
/// in it because macOS is built first. A closure is satisfied by a one-line binding on
/// either platform and by a literal in a test.
///
/// ## Threading
///
/// Synchronous, single-threaded, and **not** `Sendable` — deliberately, and for the same
/// reason ``EscriboScanner`` and ``EscriboStyler`` are not (REQUIREMENTS.md § Concurrency
/// and failure). Own one per document on the main thread, beside the text storage it
/// reads. It is not `@MainActor`-isolated because `NSTextStorageDelegate` is not, and
/// bridging the two would mean a `MainActor.assumeIsolated` — a *trap* — on the hot path
/// of a text-view callback, which is precisely the failure mode this package refuses
/// everywhere else.
///
/// ## Lifecycle
///
/// ```swift
/// let coordinator = EditorCoordinator(textStorage: storage, language: .markdown, theme: theme)
/// coordinator.hasMarkedText = { [weak view] in view?.hasMarkedText() ?? false }  // macOS
/// coordinator.attach(to: storage)     // installs the delegate
/// coordinator.restyleEverything()     // first full scan
/// ```
///
/// After that the coordinator is driven entirely by the text system.
public final class EditorCoordinator: NSObject {

  // MARK: - Owned state

  /// The document, read as UTF-16 by the scanner and written as attributes by the styler.
  ///
  /// One reference for both directions. The scanner never sees a Swift `String` of the
  /// document — REQUIREMENTS.md § Edits and text access: bridging 120 KB per keystroke
  /// "would exceed the whole budget before scanning began."
  let textStorage: any EditorTextStorage

  /// The scanner, one per document.
  ///
  /// `private(set)` and replaced wholesale by ``setLanguage(_:)`` rather than mutated:
  /// DL-28 — `EscriboScanner.language` is a `let`, because every line's cached state is
  /// meaningless under a different grammar.
  private(set) var scanner: EscriboScanner

  /// The style cache, one per document and shared across every span of every scan.
  ///
  /// A `final class` on purpose (Sortie 7): it *is* the cache, and a per-lookup copy
  /// would defeat it. Hosts change appearance, theme, mode, and font metrics by assigning
  /// `styler.environment`, which runs the one invalidation path and nothing else.
  let styler: EscriboStyler

  // MARK: - The platform seam

  /// Whether the text view currently has an active marked-text (IME) composition.
  ///
  /// **Restyling is skipped entirely while this answers `true`** — REQUIREMENTS.md
  /// Architecture §8: "Skip restyling while `hasMarkedText` is true, or CJK input
  /// breaks." Reapplying attributes underneath a composition tears down the marked-text
  /// underline and, on some input methods, cancels the composition outright.
  ///
  /// Bound by the Representable, and spelled as a closure because the two platforms spell
  /// the question incompatibly:
  ///
  /// ```swift
  /// coordinator.hasMarkedText = { [weak view] in view?.hasMarkedText() ?? false }   // macOS
  /// coordinator.hasMarkedText = { [weak view] in view?.markedTextRange != nil }     // iOS
  /// ```
  ///
  /// Defaults to "no composition", so an unattached coordinator — or a test — behaves as
  /// if the user were typing Latin text.
  var hasMarkedText: () -> Bool = { false }

  // MARK: - Instrumentation

  /// The most recent edit, as translated into old-text coordinates.
  ///
  /// Recorded even when the restyle is skipped for marked text, because the translation
  /// is what is under test and it happens either way.
  private(set) var lastEdit: TextEdit?

  /// The range whose attributes were most recently reapplied — the last scan's
  /// `dirtyRange`, clamped to the document.
  private(set) var lastAppliedRange: Range<Int>?

  /// How many times attributes have been applied.
  private(set) var restyleCount = 0

  /// How many edits have been skipped because a composition was in flight.
  private(set) var markedTextSkipCount = 0

  /// The line records the most recent scan produced, in order.
  ///
  /// ## Why records are retained when spans are not
  ///
  /// REQUIREMENTS.md § Spans is explicit that spans "are produced for a requested range on
  /// demand and are **not** retained for the whole document" — they exist to become
  /// character attributes and are worthless the moment they have. Line records are the other
  /// output of the same pass and answer a different question, "what *is* this line," which
  /// an editing affordance has to ask between scans rather than during one.
  ///
  /// Sortie 25's list continuation is the first caller. It has to know whether the caret's
  /// line is a list item — and, just as importantly, whether it is a YAML frontmatter entry
  /// or the inside of a code fence that merely looks like one (DL-108). Re-deriving that
  /// lexically would put a second, disagreeing copy of the grammar beside the editor; asking
  /// the scanner for it is free, because the scan already happened.
  ///
  /// Bounded by the last scan, which is a handful of lines per keystroke and the whole
  /// document exactly once per full scan. That last case is a real cost — on the order of a
  /// few hundred kilobytes for a 120 KB screenplay — paid on attach, language switch, and
  /// external reset, and never on the typing path.
  private(set) var lastLineRecords: [LineRecord] = []

  /// The blocks the most recent scan produced, in order.
  ///
  /// ## These are the last scan's **window**, not the document
  ///
  /// `ScanResult.blocks` covers only the lines that were rescanned, and its first and last
  /// block may be **truncated** at the window's edge: a paragraph that begins three lines
  /// above the window arrives as a block starting at the window's first line. The scanner
  /// cannot do better — it retains one `LineState` per line and never retains records, so
  /// document-wide blocks are not derivable from it.
  ///
  /// So a query may only answer from here when it can prove the block it found was not
  /// truncated — see ``isWholeBlock(_:)``. Everything else full-scans and asks again,
  /// exactly as ``elementKind(atUTF16Offset:)`` does, and for the reason that method gives:
  /// a document-wide cache the coordinator maintained across every edit would buy a rare
  /// query some milliseconds in exchange for an invalidation rule on the hot path.
  private(set) var lastBlocks: [EscriboBlock] = []

  /// The UTF-16 range ``lastBlocks`` was produced for — the last scan's `dirtyRange`,
  /// unclamped.
  ///
  /// The evidence ``isWholeBlock(_:)`` reasons from: a block touching this range's edge
  /// might continue past it, unless that edge is the document's own.
  private(set) var lastBlockCoverage: Range<Int> = 0..<0

  /// Every block in the document, maintained across edits by splicing each incremental
  /// scan's window into it.
  ///
  /// ## Why this exists as well as ``lastBlocks``
  ///
  /// A query that answered only from the last scan's window would be right, because
  /// ``isWholeBlock(_:)`` refuses a truncated block — but it would pay a full scan every
  /// time the answer lay outside the window. ``blocks(in:)`` is asked for a viewport on
  /// every scroll, and a viewport is almost always larger than a rescan window, so that
  /// cost would be a full scan per frame.
  ///
  /// So each result is **spliced**: blocks before the window are kept, blocks after it are
  /// shifted by the line and offset deltas, and the window's own blocks go in between.
  /// `ScanResult.documentLineCount` is what makes the line delta knowable, and is why it
  /// was added.
  ///
  /// ## And why the conservative path is still here
  ///
  /// ``blocksSpanDocument`` is `false` whenever a splice could not be proved sound, and
  /// every query then falls back to ``lastBlocks`` plus ``isWholeBlock(_:)`` and finally to
  /// a full scan. That belt-and-braces arrangement is deliberate: a splice bug returns a
  /// *confidently wrong* block, which nobody notices until a well lane brackets half a
  /// paragraph, whereas the fallback merely costs a scan.
  private(set) var documentBlocks: [EscriboBlock] = []

  /// Whether ``documentBlocks`` describes the whole document and every block in it is
  /// whole.
  ///
  /// Set by a full scan, kept by a sound splice, cleared by a splice that could not be
  /// proved sound. A query may trust ``documentBlocks`` only while this is `true`.
  private(set) var blocksSpanDocument = false

  /// The document line count ``documentBlocks`` was built against — the previous scan's
  /// `documentLineCount`, and the minuend of the next splice's line delta.
  private var documentBlocksLineCount = 0

  // MARK: - Geometry, supplied by the view

  /// Maps a point in text-view coordinates to a UTF-16 offset in the document.
  ///
  /// The fourth row of the platform-seam table in this type's discussion, and handled the
  /// same way as the third: a closure the view supplies. Resolving a point needs the text
  /// **layout**, which is `NSTextLayoutManager` on both platforms but reached through
  /// different view API, and which this type must not acquire — a coordinator that held a
  /// layout manager would be a coordinator shaped around one platform's text system.
  ///
  /// ## The contract, which the well depends on
  ///
  /// Must be the platform's **closest-position** behaviour: a point outside the text
  /// resolves to the nearest position, not to nothing. That is what makes a point in the
  /// well's lane — to the left of the text, outside the container — resolve to the start of
  /// the line at that `y`, and it is why ``block(at:)`` needs no lane-width special case.
  /// Both `NSTextView` and `UITextView` already do this.
  ///
  /// `nil` when nothing has been installed, which is every headless coordinator and every
  /// test that does not care about geometry.
  public var utf16Offset: ((CGPoint) -> Int?)?

  /// Maps a rect in text-view coordinates to the UTF-16 range of the text laid out in it.
  ///
  /// **Optional even when geometry is wanted.** ``blocks(in:)`` derives a range from two
  /// corner probes through ``utf16Offset`` when this is `nil`, which is what both built-in
  /// views rely on — neither installs this. It exists for a host whose layout it can answer
  /// more precisely or more cheaply than two hit-tests.
  ///
  /// Contracted to return the range of every line the rect touches, including partially
  /// visible ones, because a well lane drawn only beside fully visible lines flickers at
  /// both edges of a scroll.
  public var visibleRangeForRect: ((CGRect) -> Range<Int>?)?

  // MARK: - Private state

  /// Set while ``apply(_:)`` is writing, so the attribute edits it causes cannot re-enter
  /// ``didProcessCharacterEdit(editedRange:changeInLength:)`` and rescan the document
  /// from inside its own restyle.
  ///
  /// Belt and braces: the bridge already filters to `.editedCharacters`, and an attribute
  /// pass reports `.editedAttributes`. This makes the guarantee local to the coordinator
  /// so it does not depend on a filter in another file staying correct.
  private var isApplying = false

  /// Set when an edit was dropped on the floor for marked text.
  ///
  /// The scanner's line index now describes a document that no longer exists, and no
  /// sequence of incremental edits can recover it, because the edits it missed were never
  /// recorded. The next edit that arrives with no composition in flight therefore
  /// **full-scans** instead. This is why the Representables need no "composition ended"
  /// callback: the recovery is driven by the next real edit, which is the first moment
  /// the document is stable enough to scan anyway.
  private var needsFullRescan = false

  // MARK: - Creation

  /// Creates a coordinator over `textStorage`.
  ///
  /// - Parameters:
  ///   - textStorage: The document. Not retained by the text system on the coordinator's
  ///     behalf — the caller owns the lifetime.
  ///   - language: The grammar to scan with. Change it later with ``setLanguage(_:)``.
  ///   - styler: The style cache. Pass the same one for the lifetime of the document.
  ///
  /// Does **not** scan. Call ``restyleEverything()`` once the storage has its initial
  /// contents; scanning an empty storage that is about to be filled is wasted work, and
  /// the scanner's "assume empty until told otherwise" contract makes it harmless to
  /// defer.
  init(textStorage: any EditorTextStorage, language: Language, styler: EscriboStyler) {
    self.textStorage = textStorage
    self.scanner = EscriboScanner(language: language)
    self.styler = styler
    super.init()
  }

  /// Creates a coordinator with a styler built over `theme`.
  convenience init(
    textStorage: any EditorTextStorage, language: Language, theme: EscriboTheme
  ) {
    self.init(
      textStorage: textStorage, language: language, styler: EscriboStyler(theme: theme))
  }

  // MARK: - Language

  /// The grammar the document is currently scanned with.
  var language: Language { scanner.language }

  /// Switches grammars and restyles the whole document.
  ///
  /// DL-28: a new ``EscriboScanner`` and a full scan, never a mutation of the existing
  /// one. `EscriboScanner.language` is a `let` precisely so this cannot be got wrong —
  /// every line's `startState` is a claim about a grammar, and reusing them across a
  /// switch would misclassify exactly the multi-line constructs the state exists for.
  ///
  /// A no-op when the language is unchanged, so a host may push its configuration on
  /// every layout pass without throwing away the document's styling.
  func setLanguage(_ language: Language) {
    guard language != scanner.language else { return }
    scanner = EscriboScanner(language: language)
    restyleEverything()
  }

  // MARK: - Scanning

  /// Scans the whole document and reapplies every attribute.
  ///
  /// The entry point for the three events that invalidate everything: the first attach,
  /// a language switch, and an external replacement of the text (Sortie 12). Also the
  /// recovery path after a composition, which is why it clears ``needsFullRescan``.
  func restyleEverything() {
    needsFullRescan = false
    apply(textStorage.fullScan(using: &scanner), edit: nil)
  }

  /// Handles one **character** edit reported by the text system.
  ///
  /// Called by the `NSTextStorageDelegate` bridge, which has already filtered out
  /// attribute-only edits. Kept platform-neutral by taking the two values the callback
  /// carries rather than the callback's own types: `NSRange` and `Int` are Foundation,
  /// `NSTextStorage.EditActions` is not.
  ///
  /// - Parameters:
  ///   - editedRange: The edited range in **new**-text coordinates, exactly as the text
  ///     system reports it.
  ///   - changeInLength: How much the document grew or shrank.
  func didProcessCharacterEdit(editedRange: NSRange, changeInLength: Int) {
    guard !isApplying else { return }

    let edit = Self.textEdit(editedRange: editedRange, changeInLength: changeInLength)
    lastEdit = edit

    // Architecture §8. Nothing below this line runs during a composition — not the scan,
    // and above all not the styler.
    guard !hasMarkedText() else {
      markedTextSkipCount += 1
      needsFullRescan = true
      return
    }

    guard !needsFullRescan else {
      restyleEverything()
      return
    }

    apply(textStorage.incrementalScan(edit, using: &scanner), edit: edit)
  }

  /// Translates a text-system edit notification into a ``TextEdit``.
  ///
  /// `textStorage(_:didProcessEditing:range:changeInLength:)` reports `editedRange` in
  /// **new**-text coordinates; ``TextEdit`` is in **old**-text coordinates. The location
  /// needs no adjustment — an edit does not move its own start — but the length does:
  ///
  /// ```
  /// oldLength = editedRange.length - changeInLength
  /// ```
  ///
  /// That subtraction is the one that gets forgotten, which is why this is a static
  /// function with no dependencies rather than four lines inlined into the callback.
  ///
  /// Total: a nonsensical notification (negative location, a `changeInLength` larger than
  /// the range) is clamped to a well-formed edit rather than trapping. `EscriboScanner`
  /// clamps stale edits itself, so a clamped edit degrades to a larger rescan and never
  /// to a crash inside a delegate callback.
  static func textEdit(editedRange: NSRange, changeInLength: Int) -> TextEdit {
    let location = max(0, editedRange.location)
    let newLength = max(0, editedRange.length)
    let oldLength = max(0, newLength - changeInLength)
    return TextEdit(
      range: location..<(location + oldLength), replacementLength: newLength)
  }

  // MARK: - Attribute application

  /// Writes `result` to the text storage: span attributes, then paragraph geometry.
  ///
  /// ## Never replace the attributed string wholesale
  ///
  /// REQUIREMENTS.md Architecture §8 forbids the whole-string assignment outright: it
  /// "destroys selection, undo stack, and marked text." The permitted shape is
  /// `beginEditing()` / `setAttributes(_:range:)` / `endEditing()` over the rescanned
  /// range only, and ``EditorTextStorage`` is narrow enough that this function could not
  /// express the forbidden call even if it wanted to.
  ///
  /// ## DL-44 — why the paragraph pass comes second, and additively
  ///
  /// `setAttributes(_:range:)` **replaces** the whole dictionary for a range. Sortie 8
  /// produces geometry separately from span attributes: `paragraphStyleRuns(for:)`
  /// returns `(range, NSParagraphStyle)` pairs and `attributes(for:on:)` carries no
  /// paragraph style at all. Setting the paragraph styles first and then setting span
  /// attributes over them would drop every one of them — silently, with the document
  /// rendering exactly as if the geometry layer were switched off, and with no test
  /// failing unless one asserts the *composed* result.
  ///
  /// So the order is: span attributes with `setAttributes`, then paragraph styles with
  /// `addAttribute(.paragraphStyle:)`, which merges. The runs cover each line's **full
  /// `LineRecord.range`, terminator included** — a paragraph style that stopped short of
  /// its terminator would leave the newline carrying the previous paragraph's geometry,
  /// and `NSParagraphStyle` is applied per paragraph by the layout system, so the
  /// terminator is the character that decides.
  ///
  /// ## Spell checking survives this
  ///
  /// Deliberately. Misspelling underlines are *temporary* attributes on the layout
  /// manager, not text-storage attributes, so `setAttributes` never sees them
  /// (REQUIREMENTS.md § Text-system hygiene).
  private func apply(_ result: ScanResult, edit: TextEdit?) {
    let limit = textStorage.length
    restyleCount += 1
    lastAppliedRange = Self.clamped(result.dirtyRange, to: limit) ?? (0..<0)
    lastLineRecords = result.lineRecords
    lastBlocks = result.blocks
    lastBlockCoverage = result.dirtyRange
    updateDocumentBlocks(with: result, edit: edit)

    isApplying = true
    textStorage.beginEditing()
    defer {
      textStorage.endEditing()
      isApplying = false
    }

    // Pass 1 — character attributes, one `setAttributes` per span.
    //
    // The line record a span sits on is found by walking both sorted sequences with a
    // single cursor: spans exactly tile `dirtyRange` and line records exactly tile the
    // same lines, so this is linear rather than a search per span. Point size comes from
    // the *line* (Sortie 7), which is the whole reason the record is needed here at all.
    if !result.lineRecords.isEmpty {
      var cursor = result.lineRecords.startIndex
      let lastRecord = result.lineRecords.index(before: result.lineRecords.endIndex)
      for span in result.spans {
        while cursor < lastRecord,
          result.lineRecords[cursor].range.upperBound <= span.range.lowerBound
        {
          cursor += 1
        }
        guard let range = Self.clamped(span.range, to: limit) else { continue }
        textStorage.setAttributes(
          styler.attributes(for: span, on: result.lineRecords[cursor]),
          range: Self.nsRange(range))
      }
    }

    // Pass 2 — paragraph geometry, additively, over each line's full range. DL-44.
    for run in styler.paragraphStyleRuns(for: result.lineRecords) {
      guard let range = Self.clamped(run.range, to: limit) else { continue }
      textStorage.addAttribute(
        .paragraphStyle, value: run.style, range: Self.nsRange(range))
    }
  }

  // MARK: - Asking the scanner about a line

  /// How the scanner classified the line containing `offset`, or `nil` if it cannot say.
  ///
  /// The seam an editing affordance uses to ask "what is this line?" without re-deriving the
  /// grammar beside the editor. A `- item` inside YAML frontmatter is YAML; inside a fenced
  /// code block it is code; inside a `fountain` fence it is Fountain. All three answers come
  /// out of this one call, and none of them needed a rule at the call site (DL-108).
  ///
  /// ## The miss path is a full scan, and that is the right cost
  ///
  /// ``lastLineRecords`` holds the last scan's window, so the common case — the writer typed
  /// on this line and then pressed Return — is a hit with no work at all. A miss means the
  /// caret is somewhere the last scan did not cover, which happens when the writer clicks
  /// elsewhere and presses Return without typing first. Rather than guess, or answer from a
  /// stale index, that path full-scans and asks again.
  ///
  /// A full scan is the cold-scan budget (REQUIREMENTS.md § Performance budget: 50 ms
  /// ceiling, 10 ms target for 120 KB) paid on a single Return keystroke, not on the typing
  /// path, and not per character. The alternative — a document-wide record cache the
  /// coordinator maintains across every edit — buys a rare keystroke some milliseconds in
  /// exchange for an invalidation rule on the hot path, which is the wrong trade and the
  /// usual source of "the affordance fired on stale state" bugs.
  ///
  /// - Returns: `nil` when the document has never been scanned, or when `offset` lies
  ///   outside it. A caller that gets `nil` must do the boring thing.
  func elementKind(atUTF16Offset offset: Int) -> ElementKind? {
    if let record = Self.record(containing: offset, in: lastLineRecords) {
      return record.element
    }
    restyleEverything()
    return Self.record(containing: offset, in: lastLineRecords)?.element
  }

  // MARK: - Maintaining the document-wide block cache

  /// Folds `result` into ``documentBlocks``, either by replacing it outright or by splicing.
  ///
  /// A **full** scan replaces: it describes every line, so every block in it is whole by
  /// construction and there is nothing to reconcile. An **incremental** scan splices, and
  /// the splice is attempted only when it can be proved sound — see
  /// ``splicedDocumentBlocks(with:edit:)``. When it cannot, ``blocksSpanDocument`` goes
  /// `false` and the queries fall back to the window and then to a scan.
  private func updateDocumentBlocks(with result: ScanResult, edit: TextEdit?) {
    let coversDocument =
      result.lines.lowerBound == 0 && result.lines.upperBound == result.documentLineCount
    if coversDocument {
      documentBlocks = result.blocks
      documentBlocksLineCount = result.documentLineCount
      blocksSpanDocument = true
      return
    }

    guard let edit, blocksSpanDocument,
      let spliced = splicedDocumentBlocks(with: result, edit: edit)
    else {
      blocksSpanDocument = false
      return
    }
    documentBlocks = spliced
    documentBlocksLineCount = result.documentLineCount
    blocksSpanDocument = true
  }

  /// ``documentBlocks`` with `result`'s window spliced in, or `nil` when that cannot be
  /// done soundly.
  ///
  /// ## The two deltas
  ///
  /// - **Lines.** `result.documentLineCount - documentBlocksLineCount`. An edit that adds
  ///   or removes a newline moves every line after it, so the cached blocks past the window
  ///   must shift by this before they are kept. A splice that ignored it would return
  ///   blocks whose `lines` were right before the edit and silently wrong after — which is
  ///   why there is a test that changes the line count specifically.
  /// - **Offsets.** `edit.changeInLength`, which is the text system's own count of how many
  ///   code units the document grew or shrank. Everything after the edit shifts by it.
  ///
  /// ## The soundness conditions, and the convergence argument behind them
  ///
  /// 1. **The window produced blocks at all.** Nothing to splice otherwise.
  /// 2. **No cached block straddles either edge of the region being replaced.** A cached
  ///    block half inside the window is a block whose other half is about to be described
  ///    by different values; keeping either would contradict the other.
  ///
  /// Condition 2 is doing more work than it looks. It also establishes that the window's
  /// own edge blocks are **not fragments** — which is the thing that actually matters, and
  /// it is worth writing down why, because the obvious extra test is both redundant and
  /// nearly always false.
  ///
  /// A block boundary at line *X* is decided by the records for lines *X* and *X − 1*. For
  /// the boundary at the window's end: line *X* lies outside the window, so both its text
  /// and — by the convergence rule that stopped the scan there — the state it begins in are
  /// unchanged, hence its record is unchanged. Line *X − 1* is the window's last line and
  /// may have changed, but any change to it that would let *X* **join** its block also
  /// changes the state *X* begins in, which is precisely what stops convergence and extends
  /// the window past *X*. So if the scan stopped at *X* and no cached block straddles *X*,
  /// the boundary at *X* still holds. The mirror argument covers the window's start, where
  /// the lines before it are untouched outright.
  ///
  /// Testing ``isWholeBlock(_:)`` on the result's edge blocks instead would be wrong in
  /// practice as well as redundant: a window's last block ends exactly where the window's
  /// coverage ends, so that test is false for almost every edit and the splice would never
  /// fire. The empirical check on all of this is
  /// `splicedAnswersAgreeWithAFreshScan`, which compares a spliced cache against a scanner
  /// that never saw the earlier document.
  ///
  /// Both conditions fail *safely*: the caller clears ``blocksSpanDocument`` and the queries
  /// take the conservative path. The splice is therefore a pure saving — it never produces
  /// an answer the fallback would not also have produced, it only avoids the scan.
  private func splicedDocumentBlocks(with result: ScanResult, edit: TextEdit) -> [EscriboBlock]? {
    guard !result.blocks.isEmpty else { return nil }

    let lineDelta = result.documentLineCount - documentBlocksLineCount
    let offsetDelta = edit.changeInLength
    let window = result.lines

    // The region being replaced, in the **cache's** (pre-edit) line coordinates. Lines
    // below the window did not move, so its lower bound is shared; its upper bound is the
    // window's, less however many lines the edit added.
    let replaced = window.lowerBound..<(window.upperBound - lineDelta)
    guard replaced.lowerBound <= replaced.upperBound else { return nil }

    var before: [EscriboBlock] = []
    var after: [EscriboBlock] = []
    for block in documentBlocks {
      if block.lines.upperBound <= replaced.lowerBound {
        before.append(block)
      } else if block.lines.lowerBound >= replaced.upperBound {
        after.append(block)
      } else if block.lines.lowerBound < replaced.lowerBound
        || block.lines.upperBound > replaced.upperBound
      {
        // Straddles an edge: condition 2.
        return nil
      }
      // Anything else lies wholly inside the replaced region and is simply dropped.
    }

    return before + result.blocks + after.map { $0.shifted(byLines: lineDelta, byOffset: offsetDelta) }
  }

  // MARK: - Asking the scanner about a block

  /// The block containing `offset`, or `nil` if the document cannot say.
  ///
  /// A **block** is the writer's unit of thought rather than the editor's line — a whole
  /// hard-wrapped paragraph, one list item, a speech — as grouped by `EscriboCore`
  /// (REQUIREMENTS-1.1.0 § 4). This is the query the paragraph well, read-aloud, and the
  /// script preview all resolve a position through, so that none of them rediscovers where
  /// a paragraph ends and none of them can disagree.
  ///
  /// ## Why this is not just a lookup in `lastBlocks`
  ///
  /// ``lastBlocks`` is the last scan's *window*, and on an incremental scan its first and
  /// last block may be truncated at the window's edge. Answering from it unconditionally
  /// would be wrong for every document larger than one rescan window — and, worse, right
  /// in every small fixture, because a small fixture's window is the whole document. So a
  /// hit is returned only when ``isWholeBlock(_:)`` can prove the block was not cut off;
  /// otherwise this full-scans and asks again, which makes ``lastBlocks`` document-wide and
  /// every block in it whole by construction.
  ///
  /// The miss path is the same trade ``elementKind(atUTF16Offset:)`` makes and costs the
  /// same: one cold scan, on a query rather than on the typing path. It is reached when the
  /// caret's block straddles the edge of the last rescan — not on every keystroke, because
  /// the writer's caret is normally well inside the window their own edit produced.
  ///
  /// ## What counts as "no block", and what does not
  ///
  /// Blocks **tile** a scan completely — blank runs are blocks, established in Sortie 1
  /// precisely so that this query is a total function with no "not found" branch. Two
  /// consequences a caller should not be surprised by:
  ///
  /// - An **empty document** has one blank block covering `0..<0`, and offset `0` resolves
  ///   to it. Offset zero in an empty document is a valid caret position, not an
  ///   out-of-range offset, and answering `nil` there would put a hole in a total function
  ///   for the one document in which nothing can go wrong.
  /// - An offset **equal to the document's length** resolves to the last block. That is the
  ///   caret at the very end of the document, which is where a writer leaves it.
  ///
  /// - Returns: `nil` only when `offset` is genuinely outside the document — negative, or
  ///   past its last code unit. A coordinator that has never scanned does **not** return
  ///   `nil`: it scans and answers, which is the same miss path described above.
  public func block(atUTF16Offset offset: Int) -> EscriboBlock? {
    // The spliced cache describes the whole document, so its answer is final — **including
    // when the answer is `nil`**, which then means the offset is genuinely outside the
    // document rather than merely outside a window. Returning here rather than falling
    // through is what stops an out-of-range offset from costing a full scan, and a hover
    // just past the edge of a text view produces exactly those (§ 4.3, Sortie 5).
    if blocksSpanDocument { return Self.block(containing: offset, in: documentBlocks) }

    // Otherwise the last window, but only for a block the window provably did not cut.
    if let block = Self.block(containing: offset, in: lastBlocks), isWholeBlock(block) {
      return block
    }
    restyleEverything()
    return Self.block(containing: offset, in: documentBlocks)
  }

  /// The block under `point`, in **text-view coordinates**, or `nil` if there is none.
  ///
  /// ## A point in the well's lane resolves by its `y` alone
  ///
  /// The paragraph well draws a lane down the left of the text, outside the text container,
  /// and a pointer in it must still resolve to the block on that line. That needs no
  /// special path here, and this is the reasoning — **please do not add one**:
  /// ``utf16Offset`` is contracted to be the platform's own *closest-position* call, and
  /// for a point to the left of the text the closest position is the first character of the
  /// line at that `y`. Both platforms already behave that way. A lane-width check here
  /// would duplicate a rule the text system enforces, and would then have to be kept in
  /// step with a lane whose width this type does not know.
  ///
  /// - Returns: `nil` when no ``utf16Offset`` closure has been installed — a headless
  ///   coordinator has no geometry and says so rather than guessing — or when the point
  ///   resolves outside the document.
  public func block(at point: CGPoint) -> EscriboBlock? {
    guard let offset = utf16Offset?(point) else { return nil }
    return block(atUTF16Offset: offset)
  }

  /// Every block intersecting `visibleRect`, in **text-view coordinates**, in document
  /// order.
  ///
  /// What the well asks on every scroll and layout pass, which is why the splice in
  /// ``updateDocumentBlocks(with:edit:)`` exists: a viewport is almost always wider than a
  /// rescan window, so without a document-wide cache this would scan per frame.
  ///
  /// - Returns: `[]` when neither ``visibleRangeForRect`` nor ``utf16Offset`` has been
  ///   installed — a headless coordinator has no geometry — or when the rect covers no text.
  public func blocks(in visibleRect: CGRect) -> [EscriboBlock] {
    guard let range = utf16Range(for: visibleRect) else { return [] }
    if !blocksSpanDocument { restyleEverything() }
    guard blocksSpanDocument else { return [] }
    return documentBlocks.filter {
      $0.range.lowerBound < range.upperBound && range.lowerBound < $0.range.upperBound
    }
  }

  /// The UTF-16 range laid out in `rect`, from ``visibleRangeForRect`` if a view supplied one
  /// otherwise derived from two corner probes through ``utf16Offset``.
  ///
  /// ## Why two probes are enough
  ///
  /// ``utf16Offset`` is contracted to be the platform's closest-position call, so probing
  /// the rect's **top-left** lands on the first character of the topmost line it touches
  /// and probing its **bottom-right** lands on the last character of the bottommost. Every
  /// line between them is therefore inside the range, which is exactly what a caller
  /// wanting "the blocks on screen" needs — and it costs two hit-tests rather than a walk
  /// over every layout fragment in the document, which is what enumerating fragments would
  /// cost on every scroll frame.
  ///
  /// The approximation is at the character rather than the line: a rect whose edge falls
  /// mid-line yields the nearest character, so a block can be excluded only when *no* part
  /// of it is within a character's width of the rect. A viewport query is padded by the
  /// caller anyway, and ``visibleRangeForRect`` is the hook for a host that can do better.
  private func utf16Range(for rect: CGRect) -> Range<Int>? {
    if let supplied = visibleRangeForRect?(rect) { return supplied }
    guard let probe = utf16Offset else { return nil }
    guard let start = probe(CGPoint(x: rect.minX, y: rect.minY)),
      let end = probe(CGPoint(x: rect.maxX, y: rect.maxY))
    else { return nil }
    return min(start, end)..<(max(start, end) + 1)
  }

  /// Whether `block` is certainly the whole block and not a fragment the rescan window cut.
  ///
  /// Two clauses, one per end, and each says "the scan saw past me, or there is nothing
  /// past me to see":
  ///
  /// - the block starts after the covered range began, or that range begins at the
  ///   document's first code unit;
  /// - the block ends before the covered range ended, or that range ends at the document's
  ///   last code unit.
  ///
  /// Stated in UTF-16 offsets rather than line indices because `dirtyRange` is the coverage
  /// the scanner reports and `textStorage.length` is the document bound this type already
  /// knows. Conservative in the only direction that matters: a whole block misjudged as a
  /// fragment costs a full scan, while a fragment mistaken for a whole block is a wrong
  /// answer nobody would notice until a well lane bracketed half a paragraph.
  private func isWholeBlock(_ block: EscriboBlock) -> Bool {
    let startsInside =
      block.range.lowerBound > lastBlockCoverage.lowerBound || lastBlockCoverage.lowerBound == 0
    let endsInside =
      block.range.upperBound < lastBlockCoverage.upperBound
      || lastBlockCoverage.upperBound >= textStorage.length
    return startsInside && endsInside
  }

  /// The block whose range contains `offset`, by binary search.
  ///
  /// Blocks tile the lines they cover in order and their ranges include terminators, so the
  /// **last** block starting at or before `offset` is the right one for every offset inside
  /// the covered window — the same argument, and the same two boundary cases, as
  /// ``record(containing:in:)``.
  /// Deliberately the same shape as ``record(containing:in:)``, including its inclusive
  /// upper-bound comparison: an offset equal to a block's `upperBound` is the caret sitting
  /// at the end of that block, which is where a writer leaves it after typing.
  static func block(containing offset: Int, in blocks: [EscriboBlock]) -> EscriboBlock? {
    var low = blocks.startIndex
    var high = blocks.endIndex - 1
    var found = -1
    while low <= high {
      let middle = low + (high - low) / 2
      if blocks[middle].range.lowerBound <= offset {
        found = middle
        low = middle + 1
      } else {
        high = middle - 1
      }
    }
    guard found >= 0 else { return nil }
    let block = blocks[found]
    return offset <= block.range.upperBound ? block : nil
  }

  /// The record whose line contains `offset`, by binary search.
  ///
  /// Records tile the lines they cover in order and their ranges include terminators, so a
  /// search for the **last** record starting at or before `offset` lands on the right line
  /// for every offset inside the covered window.
  ///
  /// Two boundary cases decide the comparisons, and both are real:
  ///
  /// - `offset` may equal a record's `upperBound`. The final line of a document that ends
  ///   without a terminator has an offset one past its last character where the caret
  ///   legitimately sits, and an empty final line after a trailing terminator has an *empty*
  ///   range. `<=` admits both; `<` would answer `nil` for a caret at the end of the
  ///   document, which is where a writer presses Return most often.
  /// - `records` may be an incremental window rather than the whole document. An offset
  ///   before the window finds nothing; one after it lands on the last record and fails the
  ///   `upperBound` check. Both answer `nil`, which is the honest answer — this window
  ///   cannot classify that line.
  static func record(containing offset: Int, in records: [LineRecord]) -> LineRecord? {
    var low = records.startIndex
    var high = records.endIndex - 1
    var found = -1
    while low <= high {
      let middle = low + (high - low) / 2
      if records[middle].range.lowerBound <= offset {
        found = middle
        low = middle + 1
      } else {
        high = middle - 1
      }
    }
    guard found >= 0 else { return nil }
    let record = records[found]
    return offset <= record.range.upperBound ? record : nil
  }

  // MARK: - Range arithmetic

  /// `range` confined to `0..<limit`, or `nil` if nothing of it survives.
  ///
  /// The scanner's invariants already guarantee ranges inside the document, and the
  /// invariant harness enforces them. This exists anyway because the cost of being wrong
  /// is an `NSRangeException` raised inside a text-view delegate — an uncatchable crash
  /// in the host app, from a scanner bug that a clamp would have rendered as slightly
  /// wrong styling.
  private static func clamped(_ range: Range<Int>, to limit: Int) -> Range<Int>? {
    let lower = min(max(0, range.lowerBound), limit)
    let upper = min(max(lower, range.upperBound), limit)
    return lower < upper ? lower..<upper : nil
  }

  /// A `Range<Int>` of UTF-16 offsets as the text system's `NSRange`.
  ///
  /// Free, by Architecture §4: token ranges are UTF-16 code-unit offsets precisely so
  /// this conversion is arithmetic and not a `String.Index` walk.
  private static func nsRange(_ range: Range<Int>) -> NSRange {
    NSRange(location: range.lowerBound, length: range.count)
  }
}
