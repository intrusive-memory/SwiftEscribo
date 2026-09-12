import CoreGraphics
import EscriboCore
import Foundation
import SwiftUI

#if os(macOS)
  import AppKit
#elseif os(iOS)
  import UIKit
#endif

// MARK: - The model

/// One slot in the paragraph well (REQUIREMENTS-1.1.0 § 5.3).
///
/// A struct with static members rather than an enum, for the same reason as the vocabulary
/// types throughout this package: **a public enum is source-breaking to extend.** Every
/// consumer's exhaustive `switch` stops compiling the day a well item is added, which would
/// make routine feature work a major release. Static members on a struct still pattern-match
/// in a `switch` and still require a `default:`, which is exactly the forward compatibility
/// wanted. Adding a member here is a *minor* release; changing what an existing member is
/// emitted for is *major*.
///
/// Raw values are stable API. Never renumber or respell one.
///
/// The well is a vertical stack of slots and `1.1.0` ships exactly one. Later candidates —
/// a block-type badge, a drag handle, a note marker — are named in the requirements as
/// non-goals and are deliberately not declared here: omitting a member is not a problem.
public struct EscriboWellItem: Hashable, Sendable {
  /// The stable identifier for this item.
  public let rawValue: String

  /// Creates a well item from a raw value.
  ///
  /// Unrecognized items are legal by design, as they are for every other vocabulary in
  /// this package: a consumer reading well items produced by a newer package resolves an
  /// unknown item to its default treatment rather than trapping.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }
}

extension EscriboWellItem {

  /// Read the block aloud. The package draws and tracks the button; the host speaks.
  public static let readAloud = EscriboWellItem(rawValue: "readAloud")

}

/// The host's description of the paragraph well: which slots it holds, which block is
/// playing, and how far along it is (REQUIREMENTS-1.1.0 § 5.3).
///
/// **The package draws and tracks. The app speaks.** Nothing in this type — and nothing in
/// this package — links a speech framework. The host owns the speech engine and reports its
/// state back through ``activeBlock``, ``progress``, and ``spokenRange`` on every update.
///
/// Passing a well to ``EscriboEditor`` is also what reserves the well's lane in the text
/// view's text-container inset. Passing `nil` — the default — reserves nothing, so an
/// adopter that never mentions the well gets exactly the insets and layout it had before.
///
/// ## Eligibility is data, not a language test
///
/// Which blocks get a well is the host's decision, expressed as ``eligibleKinds``. The
/// package holds no opinion about whether a Fountain scene heading or a Markdown code block
/// should be read aloud; it only knows that a block with no content has nothing in it to
/// act on. See ``isEligible(_:)``.
///
/// A set rather than a predicate closure on purpose: a stored closure cannot be compared,
/// and this type must stay `Equatable` so a SwiftUI update pass in which nothing changed can
/// be recognised as one.
public struct EscriboWell: Equatable, Sendable {

  /// The well's slots, top to bottom. `1.1.0` ships `[.readAloud]`.
  public var items: [EscriboWellItem]

  /// The block currently being acted on — pinned and drawn in the accent colour — or `nil`.
  public var activeBlock: EscriboBlock.ID?

  /// `0…1` for the span bar's fill while ``activeBlock`` plays, or `nil`.
  public var progress: Double?

  /// The word being spoken, for the highlight: UTF-16, in document space, or `nil`.
  ///
  /// `NSRange` rather than `Range<Int>` because it is the host's speech engine that reports
  /// it, and that engine speaks `NSRange`. This module imports Foundation; `EscriboCore`,
  /// which does not, is untouched.
  public var spokenRange: NSRange?

  /// The block kinds that get a well, or `nil` for **every** kind.
  ///
  /// The default is `nil` so that the package encodes no language knowledge: a host that
  /// wants the well only on prose and speech says so, e.g.
  /// `[.paragraph, .blockquote, .listItem, .action, .speech]`. Whatever the set, a block
  /// with no content is never eligible — see ``isEligible(_:)``.
  public var eligibleKinds: Set<BlockKind>?

  /// Creates a well description.
  ///
  /// - Parameters:
  ///   - items: The well's slots. Defaults to `[.readAloud]`, the one slot `1.1.0` ships.
  ///   - activeBlock: The block being acted on, or `nil`.
  ///   - progress: `0…1` for the span-bar fill, or `nil`.
  ///   - spokenRange: The word being spoken, UTF-16 in document space, or `nil`.
  ///   - eligibleKinds: The block kinds that get a well, or `nil` for every kind.
  public init(
    items: [EscriboWellItem] = [.readAloud],
    activeBlock: EscriboBlock.ID? = nil,
    progress: Double? = nil,
    spokenRange: NSRange? = nil,
    eligibleKinds: Set<BlockKind>? = nil
  ) {
    self.items = items
    self.activeBlock = activeBlock
    self.progress = progress
    self.spokenRange = spokenRange
    self.eligibleKinds = eligibleKinds
  }

  /// Whether `block` gets a well.
  ///
  /// Two conditions, and neither is a language rule:
  ///
  /// 1. The block has content. An empty ``EscriboBlock/contentRanges`` is the block's own
  ///    documented signal that there is nothing in it — a blank run, a thematic break, a
  ///    bare fence — so there is nothing for any slot to act on. REQUIREMENTS-1.1.0 § 5.2
  ///    rule 5: ineligible blocks show nothing.
  /// 2. Its kind is in ``eligibleKinds``, or ``eligibleKinds`` is `nil`.
  public func isEligible(_ block: EscriboBlock) -> Bool {
    guard !block.contentRanges.isEmpty else { return false }
    guard let eligibleKinds else { return true }
    return eligibleKinds.contains(block.kind)
  }
}

// MARK: - The lane

/// The width of the well's lane, as a pure function of platform and horizontal size class
/// (REQUIREMENTS-1.1.0 § 5.1, D-5).
///
/// Pure and platform-neutral on purpose: both platforms' answers are computable — and
/// testable — on either platform, and no answer needs a live window. The text view reads
/// ``Platform/current``; a test names the platform it is asking about.
enum WellLane {

  /// The platform whose lane is being measured.
  enum Platform: Sendable, Equatable {
    case macOS
    case iOS

    /// The platform this binary was compiled for.
    static var current: Platform {
      #if os(macOS)
        return .macOS
      #else
        return .iOS
      #endif
    }
  }

  /// The horizontal size class, restated here because SwiftUI's `UserInterfaceSizeClass`
  /// is not available on macOS and this function must compile — and be asked about iOS —
  /// on both.
  enum HorizontalSizeClass: Sendable, Equatable {
    case compact
    case regular
  }

  /// The macOS lane: 28 pt, independent of size class. Reserved as a **symmetric**
  /// `NSSize` inset, so the right margin gains the same width.
  static let macOSWidth: CGFloat = 28

  /// The iOS lane at regular width: 44 pt, a full touch target. Reserved **left-only**.
  static let iOSRegularWidth: CGFloat = 44

  /// The lane width for `platform` at `horizontalSizeClass`.
  ///
  /// iOS reserves no lane at compact width (D-5: 44 pt of a 390 pt phone is too much to
  /// spend on one button). An unknown size class — `nil`, which only happens outside a
  /// resolved SwiftUI hierarchy — is treated as compact, so the lane is never reserved on a
  /// guess.
  static func width(on platform: Platform, horizontalSizeClass: HorizontalSizeClass?) -> CGFloat {
    switch platform {
    case .macOS:
      return macOSWidth
    case .iOS:
      return horizontalSizeClass == .regular ? iOSRegularWidth : 0
    }
  }

  /// The lane width to reserve for `well` on the current platform: `0` when there is no
  /// well, so an adopter that passes none keeps today's insets exactly.
  static func reservedWidth(
    for well: EscriboWell?, horizontalSizeClass: HorizontalSizeClass?
  ) -> CGFloat {
    guard well != nil else { return 0 }
    return width(on: .current, horizontalSizeClass: horizontalSizeClass)
  }
}

// MARK: - Applying the well to a text view

extension EscriboTextView {

  /// Stores `well` and reserves — or releases — its lane in the text-container inset.
  ///
  /// The lane is **added to** whatever inset the text view already has, never substituted
  /// for it: the width reserved last time is subtracted before the new width is added, so an
  /// inset set by anything else survives any number of calls. With `well == nil` the
  /// reserved width is `0`, so a text view that has never been given a well is never
  /// touched, and one whose well is removed returns to exactly its previous inset.
  ///
  /// Idempotent and cheap: the inset is written only when the reserved width changes, so a
  /// SwiftUI update pass that carries a new `progress` every frame does no layout work.
  func applyWell(_ well: EscriboWell?, horizontalSizeClass: WellLane.HorizontalSizeClass?) {
    self.well = well

    let lane = WellLane.reservedWidth(for: well, horizontalSizeClass: horizontalSizeClass)
    guard lane != wellLaneWidth else { return }
    let previous = wellLaneWidth
    wellLaneWidth = lane

    #if os(macOS)
      // Symmetric: `NSTextView.textContainerInset` is an `NSSize` whose width applies to
      // both the left and the right edge, so the usable width shrinks by twice the lane.
      let inset = textView.textContainerInset
      textView.textContainerInset = NSSize(
        width: inset.width - previous + lane, height: inset.height)

      // A container that tracks the view's width is resized by AppKit when the *frame*
      // changes; restate that width now so a live editor whose well appears or disappears
      // reflows at once rather than on the next resize. Skipped for an unsized view, which
      // AppKit will size correctly when it gets a frame.
      if let container = textView.textContainer, container.widthTracksTextView {
        let usable = textView.frame.width - 2 * textView.textContainerInset.width
        if usable > 0 {
          container.size = NSSize(width: usable, height: container.size.height)
        }
      }
    #else
      // Left-only: `UIEdgeInsets`, and `UITextView` resizes its tracking container itself.
      var inset = textView.textContainerInset
      inset.left = inset.left - previous + lane
      textView.textContainerInset = inset
    #endif
  }
}

#if os(iOS)
  extension WellLane.HorizontalSizeClass {

    /// SwiftUI's size class, restated. `nil` stays `nil`.
    init?(_ sizeClass: UserInterfaceSizeClass?) {
      guard let sizeClass else { return nil }
      self = sizeClass == .regular ? .regular : .compact
    }
  }
#endif
