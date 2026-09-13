---
type: doc
title: SwiftEscribo Changelog
updated: 2026-09-12
---

# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] — 2026-09-12

A **minor** bump, per the same `0.x` rule as every entry before it: below `1.0` the minor
is the breaking axis, so a consumer pinned with `.upToNextMinor(from: "0.3.0")` will
**not** pick this up automatically and must move the pin to `0.4.0`.

Nothing was removed or renamed, and every pre-existing call site keeps compiling. But
this release **changes the spans a scan returns for text that has not changed**, which is
a behaviour change an adopter has to read rather than a feature to opt into. If you cache,
snapshot, or assert on span output, read the section below before you bump the pin.

### Added

#### The blocks model: `EscriboBlock`, `BlockKind`, and `ScanResult.blocks`

A **block** is a writer's unit of thought — a whole hard-wrapped paragraph, one list
item, a speech — as opposed to a `LineRecord`, which is the editor's line. Three
consumers previously each rediscovered "where does this paragraph end" from line records
on their own and could, and did, disagree; a block is the one answer they now share
(REQUIREMENTS-1.1.0 § 4).

```swift
public struct EscriboBlock: Sendable, Equatable, Identifiable {
  public struct ID: Hashable, Sendable {
    public let line: Int
    public let offset: Int
  }
  public let kind: BlockKind
  public let lines: Range<Int>            // document line indices
  public let range: Range<Int>            // UTF-16, full extent incl. terminator
  public let contentRanges: [Range<Int>]  // UTF-16, markers and neutral lines excluded
  public let contentLines: [Int]          // index-aligned with contentRanges
  public var id: ID { ID(line: lines.lowerBound, offset: range.lowerBound) }
  public func shifted(byLines: Int, byOffset: Int) -> EscriboBlock
}
```

- **There is no public initializer.** A block is scanner output, for the same reason
  `LineRecord` and `ScanResult` have none: a consumer receives blocks and never
  fabricates one, because grouping is a property of the grammar.
- **`ID` is composite** rather than a bare `Int`, so it cannot be mistaken for either
  coordinate on its own and so two scans of the same unedited text get stable identities
  for free. It is deliberately *not* stable across an edit that moves a block — nothing
  in the scanner carries identity across edits.
- **`contentRanges` and `contentLines` are index-aligned by construction**, not by
  convention: both are projected from one filtered pass over the block's line records, so
  `contentLines[i]` names the line `contentRanges[i]` lies on and the two arrays always
  have equal count. `contentRanges` is filtered twice — a line absorbed into the block
  but not spoken (a `[[note]]` between a cue and its dialogue) has its content excluded,
  and so does a line with no content at all. **A line's absence from `contentLines` is
  itself the signal**: it is how a consumer that tiles per line, such as the script
  preview, learns which lines a block carries but does not speak, with no inference about
  the filter and no hardcoded annotation vocabulary. Both arrays are empty for a block
  with nothing to speak — a blank run, a thematic break.
- **`shifted(byLines:byOffset:)` is pure arithmetic**, with no reference to any document:
  it moves `lines`, `range`, `contentRanges`, and `contentLines` together, so the index
  alignment between the last two survives and so does `id`, which is derived from the
  first two. It exists for a consumer maintaining its own document-wide picture of blocks
  across edits — the editor's own block cache is the first caller — so that a block an
  edit did not touch can be kept and moved rather than rediscovered by a rescan.

```swift
public struct BlockKind: Hashable, Sendable {
  public let rawValue: String
  public init(rawValue: String)
}
```

`BlockKind` is one vocabulary for **both** dialects, because every consumer of blocks —
the well lane, read-aloud, the preview — switches on what a block *is*, not on which
grammar produced it. A struct with static members rather than an enum, for the same
reason as `SpanKind`, `ElementKind`, `Language`, and `SpanRole`: **a public enum is
source-breaking to extend**, and adding a block kind is meant to stay a minor release.
Twenty-one members ship at `0.4.0`:

- Markdown (produced by the package's internal grouper): `.paragraph`, `.heading` (an ATX
  line, or a setext pair, as one block), `.listItem` (each item its own block — a
  five-item list is five blocks), `.blockquote` (a run at the same depth; a depth change
  starts a new block), `.codeBlock`, `.table`, `.frontmatter`, `.thematicBreak`, `.blank`
  (present so blocks tile a scan with no gaps).
- Fountain: `.sceneHeading`, `.action`, `.speech` (a character cue plus its contiguous
  parentheticals and dialogue), `.transition`, `.centered`, `.lyrics`, `.note`,
  `.boneyard`, `.section`, `.synopsis`, `.pageBreak`, `.titlePage`.

Raw values are stable API, and are never renumbered or respelled.

`ScanResult` grows two members to carry this:

```swift
public let blocks: [EscriboBlock]
public let documentLineCount: Int
```

- **`blocks` tiles `lines` with no gaps and no overlaps** — every line is in exactly one
  block, blank runs included — which is what lets an offset-to-block lookup be a search
  with no fallback path. **It is scoped to `lines`, like everything else in `ScanResult`.**
  On a full scan that is the whole document; on an *incremental* scan it is only the
  rescanned window, so the first and last block may be truncated at the window's edge — a
  paragraph beginning three lines above the window appears as a block starting at the
  window's first line. A consumer that needs a document-wide answer keeps its own blocks
  and splices, exactly as it already does for line records. Empty for a language with no
  block structure.
- **`documentLineCount`** is the one field on `ScanResult` describing the whole document
  rather than the scan — the denominator `lines` and `dirtyRange` are a fraction of.
  Comparing it against the previous scan's value is how a consumer computes the line
  delta a splice needs when an edit adds or removes a newline and moves every block after
  it.

**What an adopter must know:** nothing consumed `ScanResult` before `0.4.0`, so this is
purely additive; no existing field changed shape or meaning.

#### Block grouping: Markdown and Fountain group lines into blocks

The rules that populate `ScanResult.blocks`, run by one internal grouper shared by the
full and incremental scanners so the two can never disagree about where a block ends.
Nothing here is public API beyond `ScanResult.blocks` itself and the vocabulary above —
this section documents *behaviour*, because it is exactly the kind of behaviour a `0.4.0`
adopter needs to read before relying on block boundaries.

- **Markdown.** A paragraph run ends at a blank line or any other element. A setext
  heading absorbs its whole preceding text run (CommonMark's own rule), as one block with
  its `===`/`---` underline. Each list item is its own block, never merged with its
  siblings. A blockquote run groups only at the **same depth**, so a `>` line and a `>>`
  line never share a block. A fence, opener through closer, is one `.codeBlock`.
- **Fountain.** A scene heading is one line. Action, transition, centered, and lyric
  lines group per run, the same as Markdown's runs. `.speech` is the one block whose
  boundary is not "a run of one element": a character cue plus every contiguous
  parenthetical, dialogue, and lyric line beneath it, ended by a blank line or a second
  cue. The title page is one block per key, absorbing its continuation values. A leading
  YAML frontmatter region ahead of a title page is handled explicitly, per `FountainGrammar`
  deviations 12/12a/12b.
- **Neutral lines are absorbed, not dropped.** `.note`, `.boneyard`, `.section`, and
  `.synopsis` sit between other block kinds without being either kind's business — `[[a
  note]]` between two dialogue lines does not split the speech, but it also must not be
  spoken as part of it. A neutral run bridges what sits on either side of it **only when
  the surrounding block actually resumes afterwards**; `action / note / blank` is still an
  action block followed by a note block, not one block. This is where `contentLines`
  earns its keep: the note's line is inside `lines` for layout purposes and absent from
  `contentLines` because it is not spoken.
- **Blocks tile with no gaps in either dialect**, including runs of blank lines, which
  are their own `.blank` blocks — the same invariant `ScanResult.blocks` documents, and
  what makes an offset-to-block query total.

**What an adopter must know:** this grouping was ported from Escribir's own
`ScriptPreview` contiguity rule specifically so the package's grouping and the app's
preview cannot disagree about where a speech ends — a host that had its own copy of that
rule should delete it and trust the block boundaries the scanner now reports.

#### Public block queries and the query handle

`EditorCoordinator` — previously an internal implementation type — is now public, so a
host can ask "which block is here" without walking the view hierarchy to find and cast to
the platform `NSTextView`/`UITextView`. `CoreGraphics` joins the coordinator's imports for
this — `CGPoint` and `CGRect` are coordinate values, not a UI framework, so the
platform-neutrality claim in its header stays true.

```swift
public final class EditorCoordinator: NSObject {
  public var utf16Offset: ((CGPoint) -> Int?)?
  public var visibleRangeForRect: ((CGRect) -> Range<Int>?)?
  public func block(atUTF16Offset offset: Int) -> EscriboBlock?
  public func block(at point: CGPoint) -> EscriboBlock?
  public func blocks(in visibleRect: CGRect) -> [EscriboBlock]
}
```

- **`utf16Offset` and `visibleRangeForRect` are geometry supplied by the view**, not
  stored platform state — the coordinator's documented seam rule. Both built-in text
  views install `utf16Offset` as their platform's own *closest-position* call
  (`characterIndexForInsertion(at:)` on macOS, `closestPosition(to:)` on iOS), which is
  the contract the well depends on: a point in the well's lane, to the left of the text
  and outside the container, resolves to the start of the line at that `y` with no
  lane-width special case anywhere in this package. `visibleRangeForRect` is optional even
  when geometry is wanted — `blocks(in:)` derives a range from two corner probes through
  `utf16Offset` when it is `nil`, which is what both built-in views rely on.
- **The three queries are total**, matching the tiling guarantee above: an empty document
  resolves offset `0` to its one blank block rather than `nil`, and an offset equal to the
  document's length resolves to the last block — both are valid caret positions, not
  out-of-range input. `nil`/`[]` mean either no live geometry (a headless coordinator) or
  an offset genuinely outside the document.
- **Block retention is a splice, not a rebuild.** `ScanResult.blocks` covers only the
  rescanned window, so the coordinator retains a document-wide cache and shifts blocks
  past the window by `EscriboBlock.shifted(byLines:byOffset:)`. It only trusts the cache
  when no cached block straddles either edge of the replaced region; otherwise it
  full-scans once, on the query rather than on the typing path.
- **Making the class public makes two more symbols public as an unavoidable
  consequence, not as new API to use.** `EditorCoordinator` conforms to the public
  `@objc` protocol `NSTextStorageDelegate`, so its witness
  `textStorage(_:didProcessEditing:range:changeInLength:)` and the `TextStorageEditActions`
  typealias in its signature must be visible wherever that witness is. **Nothing should
  call this method directly** — it is the text system's own entry point, and calling it by
  hand would report an edit that did not happen.

```swift
public final class EscriboEditorHandle: ObservableObject {
  public private(set) weak var coordinator: EditorCoordinator?
  public init()
  public func block(atUTF16Offset offset: Int) -> EscriboBlock?
  public func block(at point: CGPoint) -> EscriboBlock?
  public func blocks(in visibleRect: CGRect) -> [EscriboBlock]
}
```

`EscriboEditorHandle` is the seam that keeps a host from ever needing that cast:
`EscriboEditor` is a SwiftUI `View` — a value, recreated on every layout pass, with no
identity a host can hold — and the handle is the thing with identity a host holds instead.
`EscriboEditor.init` grows a matching parameter, `handle: EscriboEditorHandle? = nil`,
defaulted so every pre-`0.4.0` call site keeps compiling unchanged:

```swift
@StateObject private var editor = EscriboEditorHandle()

var body: some View {
  EscriboEditor(text: $text, language: .markdown, handle: editor)
    .onHover { location in
      if let block = editor.block(at: location) { … }
    }
}
```

- **The coordinator is held weakly.** The Representable owns the editor; a handle that
  kept it alive would make a host's `@StateObject` outlive the view it was handed. Every
  query answers `nil`/`[]` when there is no live editor — the same answer as before
  installation — so there is no error state to handle and nothing to trap on.
- **`ObservableObject` for lifetime only.** The handle publishes nothing: a block query's
  answer changes on every keystroke, and a published one would invalidate a host's view
  just as often. Conform to hold it in `@StateObject`; do not expect `objectWillChange` to
  fire.

**What an adopter must know:** passing no `handle:` changes nothing. `EditorCoordinator`
becoming public does not change its threading contract — it stays synchronous,
single-threaded, and not `Sendable`; own one per document on the main thread, as before.

#### `EscriboTheme.columnAdvance(for:)` and `.emWidth(for:)`, and public `FontSpec`

Font measurement a host previously had to transcribe for itself, now asked of the package
that owns the font chain:

```swift
public struct FontSpec: Hashable, Sendable {
  public var family: FontFamilyRole
  public var traits: FontTraits
  public var pointSize: Double
  public init(family: FontFamilyRole, traits: FontTraits = [], pointSize: Double)
}

extension EscriboTheme {
  public func columnAdvance(for spec: FontSpec) -> Double
  public func emWidth(for spec: FontSpec) -> Double
}
```

- **`FontSpec` becomes public.** Through `0.3.0` it was `internal`, on the rule that
  nothing in the 1.0 public surface exposes a resolved font and nothing becomes public
  speculatively. It is public now because a public method cannot take an internal
  parameter type, and the widening is *forced by a caller that exists* — Escribir measures
  its own screenplay page today with a transcribed copy of the resolver chain, and
  publishing the measurement is what lets it delete that copy. `FontFamilyRole` and
  `FontTraits`, which `FontSpec` stores, have been public since `0.1.0` and are unaffected.
  **Still not public:** `FontResolver`, `FontGeometry`, and every family name in the
  resolution chain — a consumer can ask for a measurement and cannot ask which face
  produced it, which is the same D-4 boundary the internal rule was protecting.
- **`columnAdvance(for:)`** is the advance width of one character in `spec`'s resolved
  face — the unit a monospaced measure is counted in, so a sixty-character column is
  sixty of these.
- **`emWidth(for:)`** is the width of one **em**, literally measured as the advance of the
  letter `m`. For a **monospaced** spec the two methods agree, because every glyph has the
  same advance; a caller measuring a screenplay page may use either. For a **proportional**
  spec they differ and `columnAdvance` becomes meaningless — an em is the unit proportional
  type is spaced in, so a Markdown measure expressed in ems survives a change of body face
  and one expressed in character advances does not.
- **Both are total and both resolve through the same chain the styler itself lays out
  with** — Courier Prime if installed, then Courier New, then Courier, then the system's
  own monospaced face, with a face that has no glyph for the probe falling back to a
  fraction of the point size rather than to zero. Neither method's return value should be
  asserted as a point constant in a consumer's own tests, because the value is whichever
  face this machine resolves to; assert the relationships instead (positive, linear in
  `pointSize`, near `0.6` of point size for a monospaced spec).

**What an adopter must know:** this is additive on `EscriboTheme` and a widening of
`FontSpec`'s access level only — no existing signature changed.

#### The paragraph well: `EscriboWell`, `EscriboWellItem`, and its lane

The model and layout reservation for the paragraph well (REQUIREMENTS-1.1.0 § 5): the space
it occupies and the host's state it carries. Its drawing and states are the next entry.

```swift
public struct EscriboWellItem: Hashable, Sendable {
  public let rawValue: String
  public init(rawValue: String)
}
extension EscriboWellItem {
  public static let readAloud = EscriboWellItem(rawValue: "readAloud")
}

public struct EscriboWell: Equatable, Sendable {
  public var items: [EscriboWellItem]          // default [.readAloud]
  public var activeBlock: EscriboBlock.ID?
  public var progress: Double?                 // 0…1
  public var spokenRange: NSRange?             // UTF-16, document space
  public var eligibleKinds: Set<BlockKind>?    // nil = every kind
  public init(items:activeBlock:progress:spokenRange:eligibleKinds:)  // all defaulted
  public func isEligible(_ block: EscriboBlock) -> Bool
}
```

- **`well:` and `onWellAction:` on `EscriboEditor.init`**, trailing the parameter list:
  `well: EscriboWell? = nil` and
  `onWellAction: @escaping (EscriboWellItem, EscriboBlock) -> Void = { _, _ in }`. Both are
  defaulted, so every existing call site compiles unchanged. The package draws and tracks;
  the host acts. The package does not import AVFoundation.
- **Eligibility is the host's data.** `eligibleKinds` names the block kinds that get a well;
  its default, `nil`, admits every kind, so the package encodes no language rule. A block
  with no content (an empty `contentRanges` — a blank run, a thematic break) is never
  eligible, whatever the set.
- **The lane is reserved in the text view's text-container inset, and only when a well is
  supplied.** macOS: 28 pt on `NSTextView.textContainerInset.width`, which is symmetric, so
  the usable container width shrinks by 56 pt and the right margin balances the left. iOS:
  44 pt on `UITextView.textContainerInset.left` at a **regular** horizontal size class, and
  **none at compact** (D-5); the size class is read from the SwiftUI environment on every
  update, so crossing compact ↔ regular adds or removes the lane. The lane is added to the
  inset the text view already has, never substituted for it.

**What an adopter must know:** passing no well changes nothing — the insets and layout are
exactly `0.3.0`'s. Passing one moves the text column in by the lane width in both live and
source mode (D-6).

#### The paragraph well draws, and tracks the pointer, the caret, and playback

The well is now drawn as real subviews of the text view, so it scrolls with the text, and it
follows the state machine in REQUIREMENTS-1.1.0 § 5.2. No public API was added.

- **Anatomy.** A button — 20 × 20 pt on macOS with a 10 pt semibold `play.fill` / `stop.fill`,
  a 44 × 44 pt hit area on iOS with a 17 pt symbol — centred in the lane and vertically
  centred on the block's **first** line fragment; and a 2 pt span bar, 4 pt from the text
  edge and inset 2 pt top and bottom, spanning the block's **full** height, soft-wrapped
  lines included. At rest `tertiaryLabel`; the playing block's button and bar are the accent
  colour. macOS buttons keep the arrow cursor and take a `quaternaryLabel` fill on hover.
  The button's accessibility identifier is `editor.well.readAloud`.
- **States.** Rest shows nothing — no hairline, no tint. Hover (macOS, iPad pointer) shows
  the well for the block whose vertical band the pointer is in, across the lane and the
  text, with a 120 ms fade. Caret (iOS) shows it for the caret's block while the editor is
  first responder with an insertion point. Playing shows the host's `activeBlock` with a
  stop button. Finished holds for 400 ms after `activeBlock` returns to `nil`, then goes
  back to Hover or Rest.
- **Rules.** Leaving a block hides its well after 150 ms. Typing hides the hover well until
  the pointer next moves, and a drag-selection hides it for the drag. The playing block's
  well stays pinned while another block is hovered, so two wells can show at once. Reduce
  Motion removes the fade. A block the well's `isEligible(_:)` rejects gets no button at
  all — not a disabled one.
- **`onWellAction` is now invoked**, with the button's item and its block. The package
  reports the click; whether that starts, stops, or switches playback is the host's call,
  made by updating `activeBlock`.

**What an adopter must know:** passing no well still draws nothing and lays nothing out.
Every text view now carries a pointer tracking area (macOS) or a hover gesture recognizer
(iOS), which are inert without a well. With one, layout is read from TextKit 2 only for the
blocks a well is drawn beside. iOS at compact width reserves no lane and so draws no well.

#### The paragraph well shows playback: word highlight and progress fill

The well now draws the host's `spokenRange` and `progress` (REQUIREMENTS-1.1.0 § 5.2 Playing,
D-7). No public API was added.

- **Word highlight.** `spokenRange` is drawn as a TextKit 2 **rendering attribute** —
  `.backgroundColor`, the accent colour at 25% opacity — on the text view's
  `textLayoutManager`. It never touches the text storage: no characters, no character
  attributes, no undo registration, no edited-document state. Each new range removes the
  previous highlight first; `nil`, or removing the well, clears it. A range that no longer
  fits the document — a stale word after an edit — draws nothing rather than being clamped
  onto other text. The highlight is drawn whether or not a lane is reserved, so iOS at compact
  width still gets it.
- **Progress fill.** While a block is active its span bar is a faint accent track that fills
  top to bottom with `progress`, easing each step over 200 ms. `progress` is clamped to
  `0…1`, and NaN is drawn as `0`. An active block with no `progress` shows a full bar.
- **Reduce Motion.** The active block's bar appears already filled in accent and does not
  animate.
- **Active block.** Its button shows `stop.fill` in the accent colour and its bar is accent
  (unchanged from the previous entry, now covered by tests); Finished keeps the full accent
  bar while it holds.

**What an adopter must know:** passing a `spokenRange` is safe at any rate the speech engine
reports words; a repeated range does no work. Only the `.backgroundColor` rendering attribute
is ever added or removed, so other rendering attributes over the same text survive.

### Changed

#### The inline pass runs over a Markdown block's whole content, not line by line

Through `0.3.0` the inline scanner ran once per line, so an emphasis, strikethrough, or
code-span delimiter had to open and close on the same line to pair. `**bold` on one line
and `text**` on the next produced four literal asterisks on screen — a hard-wrapped
paragraph could not carry emphasis across the wrap at all.

From `0.4.0` the inline pass runs over a **paragraph**, a **blockquote**, or a **list
item**'s joined content, so the pair pairs:

```markdown
**bold
text**
```

now comes back as one strong run rather than as literal delimiters.

**What an adopter must know:**

- **Paragraphs, blockquotes, and list items — the three things a writer hard-wraps.** A
  blockquote joins only across lines **at the same depth**, so a `**` inside `>` cannot
  pair with one inside `>>`. A list item joins the marker line with its own continuation
  lines and never across two items, so a `**` in one bullet cannot pair with a `**` in the
  next. A `>` line with no content after it is a paragraph break inside the quote and is
  not joined across, matching CommonMark.
- **Not joined, and unchanged from `0.3.0`:** ATX and setext headings, table cells, code
  blocks, and frontmatter. Tables are excluded permanently — joining a header row to its
  body rows would pair a delimiter in one cell with one in another, which CommonMark does
  not do. Fountain is excluded permanently: joining a speech would let a `*` in a character
  cue pair with a `*` in the dialogue three lines below it.
- **Block markers are untouched.** A `> `, a `- `, a `1. `, and a task-list checkbox come
  back as exactly the spans they did before, with exactly their previous kinds and no
  emphasis applied to them. Only a line's *content* spans are recomputed.
- **Spans are still strictly line-based.** A run that crosses a hard wrap comes back as
  one span per line, so `LineRecord`, `EscriboSpan`, and any styler driven by them need no
  change. A line terminator is never inside a styled span.
- **A one-line block is byte-identical to `0.3.0`.** The joined pass is skipped for
  single-line blocks specifically so that a document with no hard-wrapped emphasis sees no
  change whatsoever, and so is any block whose content carries no inline delimiter at all.
- **An unmatched delimiter still cannot style past its own block.** A blank line, a
  heading, a fence, a change of blockquote depth, or the start of the next list item all
  bound the pass, and the block's content is the entire input the matcher is given.
- **The dirty range grows, but only where joining can change something.** An edit on any
  line of a block can change how every other line of it pairs, so an incremental scan
  widens to cover the whole block before re-running the pass. `ScanResult.dirtyRange`
  has always been permitted to be much larger than the edit; this makes it so more often.
  Two conditions keep the cost bounded, and both are checked *before* anything is
  rescanned:
  - The block must lie in an unbroken run of at most **200** non-blank lines. A longer
    run falls back to line-scoped scanning, and the window is not widened at all — a wall
    of text with no blank line in it costs exactly what it cost in `0.3.0`.
  - **Some line of the block must carry inline syntax.** A block with no delimiter
    anywhere in it cannot pair anything, so it is neither joined nor widened — ordinary
    prose still rescans a handful of lines per keystroke however long the block is, which
    is what the package's typing-latency budgets require.

## [0.3.0] — 2026-07-29

A **minor** bump, per the same `0.x` rule restated in every entry so far: below `1.0`
the minor is the breaking axis, so a consumer pinned with
`.upToNextMinor(from: "0.2.0")` will **not** pick this up automatically and must move
the pin to `0.3.0`. Nothing existing was removed or renamed; both additions are new,
defaulted parameters on `EscriboEditor.init`, so every pre-existing call site keeps
compiling unchanged.

### Added

#### `findBar:` on `EscriboEditor.init`

`EscriboEditor.init` grows a fifth parameter, `findBar: Bool = false`, threaded
through `EscriboEditorRepresentable` and `EscriboEditorBridge` to the macOS text view,
where it sets `usesFindBar` and `isIncrementalSearchingEnabled` alongside the
existing text-system hygiene flags.

This is the find **bar** — the accessory inside the editor's own `NSScrollView` — not
the floating find panel, which is a separate window that covers the document.
`isIncrementalSearchingEnabled` is what makes it search as the user types rather than
only on Return. Both flags are written explicitly in both directions rather than only
when the parameter is on, so an editor asked for no find bar actually has none rather
than inheriting whatever AppKit defaults to.

Platform-neutral in the public signature and honoured on macOS only — `UITextView`
has no find bar, so a cross-platform host still writes one call site; the parameter
is accepted and ignored on iOS.

#### `focusOnAppear:` on `EscriboEditor.init`

`EscriboEditor.init` grows a sixth parameter, `focusOnAppear: Bool = false`, threaded
the same way to `EscriboNativeTextView.focusesOnAppear` on macOS. The mechanism is an
override of `viewDidMoveToWindow()` on the text view this package already ships — the
moment AppKit tells the view it now has a window, which is exactly the "the
representable's view is installed" moment. It fires once, latched, so a window the
user had already clicked into elsewhere does not have its selection yanked back on a
later re-attachment.

This removes a view-hierarchy walk that was previously a consumer's own problem: an
`NSViewRepresentable`'s view is unreachable from SwiftUI's focus system, so a host
that wanted focus-on-open had to hunt the content view for the first `NSTextView`
itself. This package owns the view it is focusing, so that walk collapses to `self`.

Platform-neutral in the public signature; honoured on macOS only. The iOS no-op is a
deliberate decision rather than a gap — `becomeFirstResponder()` on a `UITextView`
raises the software keyboard, and doing that the instant a document opens is an
interruption, not a convenience.

Resulting public signature:

```swift
public init(
  text: Binding<String>,
  language: Language,
  mode: EditorMode = .live,
  theme: EscriboTheme? = nil,
  findBar: Bool = false,
  focusOnAppear: Bool = false
)
```

## [0.2.0] — 2026-07-28

A **minor** bump, and under the `0.x` rules stated in the `0.1.0` entry's § Stability
that is the breaking axis: a consumer pinned with `.upToNextMinor(from: "0.1.0")` —
which is what README recommends — will **not** pick this up automatically and must
move the pin to `0.2.0`. Nothing in the public surface was removed or renamed; the
minor is spent on new behavior in the Fountain scanner, which changes how a document
opening with `---` is classified.

### Added

#### YAML frontmatter in Fountain

A screenplay may now open with a `---`-fenced YAML frontmatter region, the same construct
Markdown has carried since Sortie 20 and with the same span vocabulary —
`SpanKind.frontmatterDelimiter`, `.frontmatterKey`, `.frontmatterValue`, and the
`ElementKind.frontmatterDelimiter` / `.frontmatter` line classifications. No new public
member: this is existing vocabulary reaching a second language.

The line rules now live in one place (`FrontmatterScanning`) and are shared verbatim by
both grammars, so `key: value` splits at the same colon in a `.fountain` file as in a `.md`
one. Markdown's behavior is unchanged, byte for byte.

Three rules are Fountain's own, and all three are stated as deviations 12, 12a, and 12b on
`FountainGrammar`:

- The region opens where the title page may open — the first line of a screenplay, or the
  first line of a ` ```fountain ` fence — and nowhere else.
- **The opening `---` requires corroboration**: the line below it must look like a
  frontmatter entry. Markdown's does not. An unterminated region runs to the end of the
  document, so in a screenplay an uncorroborated rule would turn a scene separator typed at
  the top of the file into a document-wide YAML block; in Markdown the same mistake costs a
  paragraph, and every static-site generator already reads the bare form.
- **A title page may still open below a closed region**, across blank lines. A file that
  writes `---` metadata and then `Title:` has written both leading regions.

`FountainWriter` re-emits the whole region verbatim — indentation is significant in YAML and
this package parses none of it.

### Changed

- The built-in Markdown themes now render frontmatter in a **monospaced** face. Their base is
  proportional, so a `key: value` block previously lost the column alignment that makes it
  readable as metadata. The built-in Fountain themes declare the same for frontmatter and for
  the title page; their base was already monospaced, so nothing there changes on screen.

## [0.1.0] — 2026-07-28

First release. Three products, zero shipping dependencies.

Shipped at `0.1.0` rather than `1.0.0` deliberately: the API below is complete and
audited, but it has no external consumers yet, and the first real adopter is the
thing most likely to find a name or a signature that should have been different.
`0.x` is the honest label for that, and it is what the § Semver commitments section
at the bottom of this entry is written against. See § Stability for what a `0.x`
version number does and does not promise.

### Added

#### `EscriboCore` — the parser (Foundation only)

Hand-written, line-oriented, incremental scanners for Markdown and Fountain. No
regular expressions anywhere under `Sources/`; a SwiftLint rule enforces it.

The public surface is exactly this, and it is the whole of it:

| Type | What it is |
|---|---|
| `EscriboScanner` | The entry point. `init(language:)`, `fullScan(_:)`, `incrementalScan(_:in:)` |
| `Language` | `.markdown`, `.fountain`, or any raw value — an unknown language scans as plain text rather than trapping |
| `ScanResult` | `dirtyRange`, `spans`, `lines`, `lineRecords` |
| `EscriboSpan` | `range`, `kind`, `style`, `role` — inline tokens, in UTF-16 offsets |
| `LineRecord` | `index`, `range`, `contentRange`, `element`, `depth`, `startState`, `tableAlignments` |
| `SpanKind` | 39 members. A struct, not an enum: adding one is a **minor** release |
| `ElementKind` | 28 members, same contract |
| `StyleSet` | `OptionSet` — strong, emphasis, strikethrough, inline code, underline |
| `SpanRole` | `.content` or `.marker` — what makes dimming markers possible |
| `TableAlignment` | GFM column alignment, carried on the delimiter row's record |
| `TextEdit` | `range`, `replacementLength`, `changeInLength` |
| `FountainWriter` | `write(_:from:)` — canonical Fountain from line records |
| `UTF16TextSource` | The read protocol, so a host can hand the scanner an `NSTextStorage` without bridging to `String` |
| `LineState` | Public but **opaque**: no public cases, properties, or initializers |

`LineState`'s opacity is load-bearing rather than stylistic. It is why
`LineRecord` and `ScanResult` have internal initializers, and it is what keeps every
future convergence improvement out of the "breaking change" column. A consumer can
compare two states and do nothing else with them, which is all anyone needs.

#### `SwiftEscribo` — the editor (SwiftUI + TextKit 2)

`EscriboEditor`, bound to a `@Binding var text: String`. `EscriboTheme` with
built-in light and dark themes for both languages, `TokenStyle`, `ParagraphMetrics`,
and `EditorMode` (`.live` / `.source`). Fountain paragraph geometry at 10 CPI,
Markdown heading scale and list indents, Markdown list continuation, Fountain smart
Tab and Return, each rewrite a single coalesced undo action. macOS and iOS are peers.

`EscriboColor`, `FontFamilyRole`, `FontTraits`, and `ParagraphAlignment` are public
because `TokenStyle` and `ParagraphMetrics` store them and a public struct's stored
properties must have public types. They are not independently supported API.

#### `EscriboProject` — project metadata (Foundation only)

`ProjectFrontMatter`, `CastMember`, `SeasonDefinition`, `LanguageDefinition`,
`VariantReference`, `TTSConfig`, `FilePattern`, `AnyCodable`. The org's `PROJECT.md`
model, shipped as its own product so a CLI can read project metadata without linking
the editor — and so that it never enlarges the scanner's audited public surface. It is
**not** part of the audited API commitment above.

### Fixed

- `ProjectFrontMatter.appSections` and `CastMember.extraKeys` are now readable from
  outside `EscriboProject` (`public internal(set)`). Unknown keys always round-tripped
  losslessly and the public initializers already accepted them, but nothing could read
  them back — a host app could confirm its own settings section survived a save only by
  diffing the file.

### Known limitations

Documented rather than discovered. The full list, with what each one costs a user, is
in [README.md § Known limitations](README.md#known-limitations). The two
worth naming here because they lose data rather than merely mis-render it:

- A GLOSA directive **wrapped across a line break is destroyed**, not merely unpaired.
- A `PROJECT.md` with a top-level `episodes:` and no `season:` **loses the episode
  count on decode** (pre-existing; fixing it is a behaviour change, not a bug fix).

### Stability

**This is a `0.x` release, and the public API is not yet frozen.** Under Semantic
Versioning a leading zero means exactly that, and SwiftPM enforces it: for a `0.x`
version, `.upToNextMajor(from: "0.1.0")` resolves to `>=0.1.0 <0.2.0` — the **minor**
is the breaking axis, not the major. A consumer who pins that way is pinned to the
`0.1` line and will not pick up `0.2.0` automatically. That is the intended behaviour
while the surface settles.

Pin it the way you would pin any pre-1.0 package:

```swift
.package(url: "https://github.com/intrusive-memory/SwiftEscribo.git", .upToNextMinor(from: "0.1.0"))
```

The surface itself is complete and was audited declaration by declaration (134 public
declarations in `EscriboCore`, every one deliberate). What `0.x` reserves is the right
to act on what the first real adopters find, without a major-version ceremony for a
package nobody has integrated yet.

### Semver commitments, once this reaches 1.0

These are the rules the design is *built* for — `SpanKind` and `ElementKind` are
structs rather than enums specifically so the first two can hold. They become binding
promises at `1.0.0`; until then they describe intent, and a `0.x` minor may break any
of them if an adopter surfaces a good enough reason.

- Adding a `SpanKind` or `ElementKind` member: **minor**. This is why they are structs.
- Adding a `StyleSet` case: **minor**. Raw values are stable, so bit positions never move.
- Changing what an existing kind is emitted *for*: **major**, even though nothing stops
  compiling. It silently changes how every existing theme renders, which is worse.
- Reordering or renumbering anything with a raw value: **major**.
- Deprecation runs one minor release with `@available(*, deprecated)` before removal.

### The road to 1.0

`1.0.0` is cut when the surface has survived contact with real consumers. Concretely:
at least one downstream package in the collection integrating `EscriboCore`, and the
two content-losing limitations above either fixed or accepted as permanent with a
user's decision on record.
