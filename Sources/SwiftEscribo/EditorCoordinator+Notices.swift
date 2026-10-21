import EscriboCore
import Foundation

// MARK: - The notice

/// The host's answer for one block's well notice: the glyph to draw and its help text.
struct WellNotice: Equatable {

  /// The SF Symbol to draw in the block's well slot.
  let symbolName: String

  /// The tooltip and accessibility label.
  let help: String
}

/// One block the host answered with a notice, and the notice.
struct NoticedBlock: Equatable {

  /// The block, in current-document coordinates.
  let block: EscriboBlock

  /// The host's answer for it.
  let notice: WellNotice
}

// MARK: - The state the coordinator keeps for notices

/// The coordinator's notice state: the host's `wellNotice` callback and its last answer for
/// every block (REQUIREMENTS.md § 2).
///
/// Refreshed at exactly the embed cache's points — see ``EditorCoordinator/refreshAllNotices()``
/// and ``EditorCoordinator/refreshNotices(afterEdit:)`` — but, unlike embeds, in **both**
/// ``EditorMode``s: the notice spec does not restrict mode, and a notice is a flag in the
/// well lane, not a replacement for the block's text.
final class NoticeState {

  /// The host's callback, or `nil` for none — in which case nothing here ever runs.
  var provider: ((EscriboBlock) -> (symbolName: String, help: String)?)?

  /// Every block with a notice, in document order.
  var answers: [NoticedBlock] = []

  /// The change hook: called after ``answers`` changes, with the UTF-16 ranges (current
  /// document coordinates) of the blocks whose notice came, went or changed.
  var didChange: (([Range<Int>]) -> Void)?
}

// MARK: - Asking the host

extension EditorCoordinator {

  /// Every block with a notice, in document order. Empty with no callback.
  var noticedBlocks: [NoticedBlock] { notices.answers }

  /// The notice cached for exactly `block`, or `nil`.
  func notice(for block: EscriboBlock) -> WellNotice? {
    let answers = notices.answers
    var low = answers.startIndex
    var high = answers.endIndex - 1
    while low <= high {
      let middle = low + (high - low) / 2
      let start = answers[middle].block.range.lowerBound
      if start == block.range.lowerBound {
        return answers[middle].block == block ? answers[middle].notice : nil
      } else if start < block.range.lowerBound {
        low = middle + 1
      } else {
        high = middle - 1
      }
    }
    return nil
  }

  /// The IDs of every noticed block: what ``WellTracker/noticesChanged(to:)`` takes.
  var noticedBlockIDs: Set<EscriboBlock.ID> { Set(notices.answers.map(\.block.id)) }

  /// The change hook the overlay redraws from. See ``NoticeState/didChange``.
  var onNoticesChange: (([Range<Int>]) -> Void)? {
    get { notices.didChange }
    set { notices.didChange = newValue }
  }

  /// Installs, replaces or removes the host's callback.
  ///
  /// Asks every block only when the callback **appears** or **disappears**: SwiftUI hands
  /// the editor a closure on every update pass, and closures cannot be compared. A host
  /// whose answers change calls ``EscriboEditorHandle/invalidateEmbeds()``.
  func setWellNotice(_ provider: ((EscriboBlock) -> (symbolName: String, help: String)?)?) {
    let presenceChanged = (notices.provider == nil) != (provider == nil)
    notices.provider = provider
    guard presenceChanged else { return }
    if !blocksSpanDocument, provider != nil {
      restyleEverything()
    } else {
      refreshAllNotices()
    }
  }

  /// Re-asks every block of ``documentBlocks``. Called after every full scan and by
  /// ``invalidateEmbeds()``.
  func refreshAllNotices() {
    let old = notices.answers
    guard blocksSpanDocument, let provider = notices.provider else {
      guard !old.isEmpty else { return }
      notices.answers = []
      notices.didChange?(old.map(\.block.range))
      return
    }

    var fresh: [NoticedBlock] = []
    for block in documentBlocks {
      if let answer = provider(block) {
        fresh.append(
          NoticedBlock(block: block, notice: WellNotice(symbolName: answer.symbolName, help: answer.help)))
      }
    }
    notices.answers = fresh

    let oldSet = Dictionary(old.map { ($0.block.id, $0) }, uniquingKeysWith: { first, _ in first })
    let freshSet = Dictionary(
      fresh.map { ($0.block.id, $0) }, uniquingKeysWith: { first, _ in first })
    var changed: [Range<Int>] = []
    for entry in fresh where oldSet[entry.block.id] != entry { changed.append(entry.block.range) }
    for entry in old where freshSet[entry.block.id] != entry { changed.append(entry.block.range) }
    guard !changed.isEmpty else { return }
    notices.didChange?(changed.sorted { $0.lowerBound < $1.lowerBound })
  }

  /// Folds one incremental edit into the cache: re-asks **only the rescanned blocks** and
  /// carries every other answer across the edit, exactly as ``refreshEmbeds(afterEdit:)``
  /// does for embeds (and for the same reasons).
  func refreshNotices(afterEdit edit: TextEdit) {
    guard !embeds.isEditRefreshDeferred else { return }
    guard let provider = notices.provider else {
      if !notices.answers.isEmpty { refreshAllNotices() }
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
    var carried: [NoticedBlock] = []
    var dropped = false
    for entry in notices.answers {
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
      if current.range.lowerBound < windowEnd, windowStart < current.range.upperBound {
        dropped = true
        continue
      }
      carried.append(NoticedBlock(block: current, notice: entry.notice))
    }

    var asked: [NoticedBlock] = []
    for block in window {
      if let answer = provider(block) {
        asked.append(
          NoticedBlock(block: block, notice: WellNotice(symbolName: answer.symbolName, help: answer.help)))
      }
    }

    notices.answers = (carried + asked).sorted {
      $0.block.range.lowerBound < $1.block.range.lowerBound
    }
    if dropped || !asked.isEmpty {
      notices.didChange?([windowStart..<windowEnd])
    }
  }
}
