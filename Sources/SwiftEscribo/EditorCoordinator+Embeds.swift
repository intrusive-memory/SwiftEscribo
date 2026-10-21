import EscriboCore
import Foundation

// MARK: - The answer cache's value

/// One block the provider answered with an embed, and the embed it answered with.
///
/// The cache holds these and nothing else: a block whose answer is `nil` is simply absent,
/// so a document with no embeds costs an empty array.
struct EmbeddedBlock: Equatable {

  /// The block, in current-document coordinates.
  let block: EscriboBlock

  /// The provider's answer for it.
  let embed: EscriboEmbed
}

// MARK: - The state the coordinator keeps for embeds

/// The coordinator's embed state: the host's provider and callbacks, and the provider's
/// last answer for every block (REQUIREMENTS.md § 1.1, "When the editor asks the provider").
///
/// A separate reference type, held by one `let` on ``EditorCoordinator``, so that all of
/// the embed bookkeeping lives in this file and the coordinator's scanning code gains only
/// the two calls that drive it.
final class EmbedState {

  /// The host's provider, or `nil` for none — in which case nothing here ever runs.
  var provider: (any EscriboEmbedProvider)?

  /// Every block whose answer is an embed, in document order (ascending
  /// `block.range.lowerBound`). Empty with no provider and in ``EditorMode/source``.
  var answers: [EmbeddedBlock] = []

  /// Called with a click or tap on an embed row. Stored for the input sorties.
  var onActivate: (EscriboBlock) -> Void = { _ in }

  /// Called with an embed's block and the ``EscriboEmbed/Action/id`` performed on it.
  var onAction: (EscriboBlock, String) -> Void = { _, _ in }

  /// Called when Find lands a match inside an embed, once per match, from the macOS embed
  /// behaviour (`MacEmbedBehaviour.swift`). Never called on iOS, which has no find bar: the
  /// parameter is accepted there and stays a no-op, like `findBar`.
  var onFindMatch: (EscriboBlock) -> Void = { _ in }

  /// Set while an external reset is replacing the whole document: the reset's edit is not
  /// re-asked, because the full scan that follows it re-asks every block anyway. Without
  /// this a load would ask every block twice.
  var isEditRefreshDeferred = false

  /// The change hook: called after ``answers`` changes, with the UTF-16 ranges (current
  /// document coordinates) of the blocks whose rendering may have changed.
  var didChange: (([Range<Int>]) -> Void)?
}

// MARK: - Asking the provider

extension EditorCoordinator {

  /// Whether the provider is consulted at all: a provider is installed **and** the editor
  /// is in ``EditorMode/live``.
  ///
  /// This is the line that makes ``EditorMode`` a code path. A mode switch reaches here
  /// through the full restyle ``EscriboTextView/applyConfiguration(language:mode:theme:appearance:)``
  /// already runs, so entering `.source` empties the cache and returning to `.live` refills
  /// it, with no extra wiring.
  var embedsAreActive: Bool {
    embeds.provider != nil && styler.environment.mode == .live
  }

  /// Every block currently drawn as an embed, with its embed, in document order.
  ///
  /// The query the layout sortie draws from. Empty with no provider and in `.source`.
  var embeddedBlocks: [EmbeddedBlock] { embeds.answers }

  /// The embedded block whose range contains `offset`, or `nil`.
  ///
  /// Uses the same inclusive-start, exclusive-end rule a layout fragment needs: an offset
  /// equal to a block's `upperBound` belongs to the next block, not this one.
  func embeddedBlock(containingUTF16Offset offset: Int) -> EmbeddedBlock? {
    let answers = embeds.answers
    var low = answers.startIndex
    var high = answers.endIndex - 1
    var found = -1
    while low <= high {
      let middle = low + (high - low) / 2
      if answers[middle].block.range.lowerBound <= offset {
        found = middle
        low = middle + 1
      } else {
        high = middle - 1
      }
    }
    guard found >= 0, offset < answers[found].block.range.upperBound else { return nil }
    return answers[found]
  }

  /// The embed cached for exactly `block`, or `nil`.
  func embed(for block: EscriboBlock) -> EscriboEmbed? {
    guard let hit = embeddedBlock(containingUTF16Offset: block.range.lowerBound),
      hit.block == block
    else { return nil }
    return hit.embed
  }

  /// The change hook later sorties redraw from. See ``EmbedState/didChange``.
  ///
  /// Fired only when the answers actually changed. On an edit or a full scan the text
  /// system has already invalidated layout over every range the scan restyled, so the hook
  /// matters most for ``invalidateEmbeds()``, where no character moved.
  var onEmbedsChange: (([Range<Int>]) -> Void)? {
    get { embeds.didChange }
    set { embeds.didChange = newValue }
  }

  /// Installs the host's callbacks. Re-applied on every SwiftUI update pass, so a callback
  /// never targets a stale view graph.
  func setEmbedCallbacks(
    onActivate: @escaping (EscriboBlock) -> Void,
    onAction: @escaping (EscriboBlock, String) -> Void,
    onFindMatch: @escaping (EscriboBlock) -> Void
  ) {
    embeds.onActivate = onActivate
    embeds.onAction = onAction
    embeds.onFindMatch = onFindMatch
  }

  /// Installs, replaces or removes the provider.
  ///
  /// Asks every block only when a provider **appears** or **disappears**. SwiftUI hands the
  /// editor a provider value on every update pass, and re-asking then would put a
  /// whole-document walk on every layout invalidation — REQUIREMENTS.md § 1.1 says the
  /// editor does not re-ask on every SwiftUI update. A host whose replacement provider
  /// answers differently calls ``invalidateEmbeds()``.
  func setEmbedProvider(_ provider: (any EscriboEmbedProvider)?) {
    let presenceChanged = (embeds.provider == nil) != (provider == nil)
    embeds.provider = provider
    guard presenceChanged else { return }
    invalidateEmbeds()
  }

  /// Runs `body` — an edit that a full scan will follow — without re-asking the edit's
  /// blocks, so the full scan's re-ask is the only one.
  func withEmbedEditRefreshDeferred(_ body: () -> Void) {
    let wasDeferred = embeds.isEditRefreshDeferred
    embeds.isEditRefreshDeferred = true
    defer { embeds.isEditRefreshDeferred = wasDeferred }
    body()
  }

  /// Asks the provider again for **every block** — the body of
  /// ``EscriboEditorHandle/invalidateEmbeds()``.
  ///
  /// Normally no scan is needed: the document-wide block list is current. When it is not
  /// (a splice could not be proved sound), this full-scans, which refreshes every answer
  /// as a side effect.
  func invalidateEmbeds() {
    if embedsAreActive || notices.provider != nil, !blocksSpanDocument {
      restyleEverything()  // re-asks embeds and notices alike
      return
    }
    refreshAllEmbeds()
    refreshAllNotices()
  }

  /// Re-asks every block of ``documentBlocks``. Called after every full scan.
  ///
  /// Empties the cache when embeds are inactive, which is how `.source` and "no provider"
  /// end up with no embeds without a branch anywhere else.
  func refreshAllEmbeds() {
    let old = embeds.answers
    guard embedsAreActive, blocksSpanDocument, let provider = embeds.provider else {
      guard !old.isEmpty else { return }
      embeds.answers = []
      embeds.didChange?(old.map(\.block.range))
      return
    }

    var fresh: [EmbeddedBlock] = []
    for block in documentBlocks {
      if let embed = provider.embed(for: block, in: sourceText(of: block)) {
        fresh.append(EmbeddedBlock(block: block, embed: embed))
      }
    }
    embeds.answers = fresh

    // Symmetric difference, by value. Without an edit the blocks are unchanged, so an
    // unchanged answer matches itself exactly and only real changes are reported.
    let oldSet = Dictionary(old.map { ($0.block.id, $0) }, uniquingKeysWith: { first, _ in first })
    let freshSet = Dictionary(
      fresh.map { ($0.block.id, $0) }, uniquingKeysWith: { first, _ in first })
    var changed: [Range<Int>] = []
    for entry in fresh where oldSet[entry.block.id] != entry { changed.append(entry.block.range) }
    for entry in old where freshSet[entry.block.id] != entry { changed.append(entry.block.range) }
    guard !changed.isEmpty else { return }
    embeds.didChange?(changed.sorted { $0.lowerBound < $1.lowerBound })
  }

  /// Folds one incremental edit into the cache: re-asks **only the rescanned blocks** and
  /// carries every other answer across the edit.
  ///
  /// Called after the incremental scan has been applied, so ``lastBlocks`` is the window
  /// the scan returned and ``documentBlocks`` is the spliced document.
  ///
  /// ## Carrying an answer across the edit
  ///
  /// An answered block that ends at or before the edit keeps its offsets; one that starts
  /// at or after the edit's end shifts by `changeInLength`; one the edit touched is
  /// dropped (it is inside the window and is re-asked). Each carried answer is then checked
  /// against the spliced ``documentBlocks`` — a block of the same start, length and kind
  /// must be there — and takes that block's current value, so its `lines` are right too.
  /// The check is what keeps this from duplicating the splice's own line arithmetic.
  ///
  /// ## When the splice failed
  ///
  /// If ``blocksSpanDocument`` is `false` there is no document-wide block list to keep
  /// answers against, so this full-scans instead (which re-asks every block). That is a
  /// cost paid only with a provider installed, and only on an edit the splice declined.
  func refreshEmbeds(afterEdit edit: TextEdit) {
    guard !embeds.isEditRefreshDeferred else { return }
    guard embedsAreActive, let provider = embeds.provider else {
      if !embeds.answers.isEmpty { refreshAllEmbeds() }
      return
    }
    guard blocksSpanDocument else {
      restyleEverything()
      return
    }

    let window = lastBlocks
    guard let windowStart = window.first?.range.lowerBound,
      let windowEnd = window.last?.range.upperBound
    else { return }

    let delta = edit.changeInLength
    var carried: [EmbeddedBlock] = []
    var dropped = false
    for entry in embeds.answers {
      let old = entry.block.range
      let start: Int
      if old.upperBound <= edit.range.lowerBound {
        start = old.lowerBound
      } else if old.lowerBound >= edit.range.upperBound {
        start = old.lowerBound + delta
      } else {
        dropped = true
        continue
      }
      guard let current = Self.block(containing: start, in: documentBlocks),
        current.range.lowerBound == start, current.range.count == old.count,
        current.kind == entry.block.kind
      else {
        dropped = true
        continue
      }
      // Inside the window: re-asked below, so the stale answer goes.
      if current.range.lowerBound < windowEnd, windowStart < current.range.upperBound {
        dropped = true
        continue
      }
      carried.append(EmbeddedBlock(block: current, embed: entry.embed))
    }

    var asked: [EmbeddedBlock] = []
    for block in window {
      if let embed = provider.embed(for: block, in: sourceText(of: block)) {
        asked.append(EmbeddedBlock(block: block, embed: embed))
      }
    }

    embeds.answers = (carried + asked).sorted {
      $0.block.range.lowerBound < $1.block.range.lowerBound
    }
    // Conservative: the whole window, whenever an answer in it came or went.
    if dropped || !asked.isEmpty {
      embeds.didChange?([windowStart..<windowEnd])
    }
  }

  /// `block`'s characters as a `String`, terminator included — what the provider reads.
  ///
  /// Bridged per asked block, never for the whole document: a provider reading one note
  /// should not cost a 120 KB copy per keystroke.
  private func sourceText(of block: EscriboBlock) -> String {
    let lower = min(max(0, block.range.lowerBound), textStorage.length)
    let upper = min(max(lower, block.range.upperBound), textStorage.length)
    var units = [UInt16](repeating: 0, count: upper - lower)
    units.withUnsafeMutableBufferPointer { buffer in
      textStorage.copyUTF16CodeUnits(in: lower..<upper, into: buffer)
    }
    return String(decoding: units, as: UTF16.self)
  }
}
