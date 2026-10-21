---
type: project
title: SwiftEscribo — block embeds, notice well slot, and JSON in notes (minor release)
updated: 2026-10-20
state: complete
depends_on: docs/missions/embed-spike (go on both platforms, accepted by the user)
---

# SwiftEscribo — block embeds

A host can ask the editor to draw any block as an **embed**: one atomic row with a
glyph, title, subtitle and badge, while the block's characters stay in the document. A
screenplay host uses it to show a structured directive note as a compact object instead
of its markup. The package knows nothing about what an embed means.

Also in this release: a **notice** slot in the paragraph well, and **JSON scanning
inside Fountain notes** so GLOSA notation 2.0 block directives (a JSON object in a
note, defined by glosa-av 0.9.0) are syntax-coloured.

**Gate in — met 2026-10-20.** The embed spike (`docs/missions/embed-spike/SPIKE_REPORT.md`,
branch `spike/block-embeds`) recommended go on macOS and iOS; the user accepted **go on
both**, with the spike's conditions, which are requirements of this release:

- **macOS — the stale block cache.** Typing above an embed leaves the cached block list
  stale; the spike re-scanned the whole document on every keystroke, which cannot ship.
  The release keeps block ranges current incrementally (from the scanner's edit
  results) and proves it with a test that types above an embed. The cause is in the
  coordinator, not the embed code: the incremental splice declines whenever a cached
  block straddles the rescanned window (`EditorCoordinator.swift:540-560`, returns
  `nil`), and an ordinary keystroke in a multi-line block does exactly that. The fix
  either widens the incremental window to whole-block edges or merges the straddling
  edge blocks during the splice; the sortie first finds out why iOS stayed spliced for
  the same keystrokes, then picks a route. That sortie runs `make test-performance`
  (the window route touches the ≤ 8-line convergence budget) and it must pass.
  This fix lands before any macOS embed sortie.
- **iOS — live input check first.** The first iOS sortie verifies tap, selection-handle
  drag, paste, forward-delete and VoiceOver on a running simulator or device (the spike
  drove them only through UIKit's internal methods), and blocks paste into an embed.
  The check runs on an **iPhone and an iPad simulator**: the host app is iPad-only, and
  iPad users often have a hardware keyboard and a pointer, so pointer clicks and
  trackpad drags are verified too. It comes before any other iOS embed sortie. If the
  spike's mechanism does not hold on a running simulator, the mission stops there:
  that is a go/no-go decision for the user.
- **iOS — accepted risk.** On iOS 26 UIKit already occupies the text layout manager's
  delegate; the embed implementation sits in front of UIKit's private delegate and
  forwards everything else to it. The user accepted that a future iOS release may break
  this; the release isolates it in one type with a test that fails loudly if UIKit's
  delegate is missing.
- **Mechanism (from the spike):** a custom layout fragment draws the block's first
  paragraph as the row and gives the block's other paragraphs zero height; text
  storage is never modified.
- **Flaky tests to fix first:** `FontResolutionTests.swift:141` (serif font missing on
  some runners) and `GeometryRuleSetTests.swift:75`, which hung in
  `FontResolver.firstAvailable` → `NSFont(name:size:)` waiting on the system font
  service (any test that resolves a named font can hit the same wait). This release's
  `make test` gate depends on them, so they are the first sortie. A test-level timeout
  cannot stop the hang: it is a synchronous XPC wait, and Swift Testing's `.timeLimit`
  records a failure but cannot interrupt a blocked thread. The fix is a `FontResolver`
  change that avoids the blocking call under test, `-test-timeouts-enabled YES` on the
  `Makefile`'s `xcodebuild test` invocations, or both. The serif check must not depend
  on which fonts a runner has installed.
- Spike estimate: about 16 sorties.

**Decisions — 2026-10-20.** The user accepted all six recommendations of the recon
(`RECON_REPORT.md`, revision 3, Q-1 to Q-6). Each is written into the section it governs:
Q-1 `invalidateEmbeds()` and when the editor re-asks (§ 1.1); Q-2 `wellNotice` as an
`EscriboEditor` parameter (§ 2); Q-3 the in-note convergence budget (§ 3); Q-4 notice
eligibility, slot sharing and drawing (§ 2); Q-5 the glosa-av JSON trigger (§ 3); Q-6
`⌥↩` on iOS (§ 1.3). The recon's breakdown notes are folded in as requirements in the
same places. Spike + recon estimate: about 17–18 sorties.

## 1. Embeds

1. **API.**
   - `public protocol EscriboEmbedProvider` — asked for each block in `EditorMode.live`
     only: `func embed(for block: EscriboBlock, in text: String) -> EscriboEmbed?`.
     `nil` draws the text as today.
   - `public struct EscriboEmbed: Equatable, Sendable` — `symbolName`, `title`,
     `subtitle`, `badge: Badge?` (`symbolName`, `word`, `tint` as an `EscriboColor`),
     `accessibilityLabel`, `accessibilityValue`, `accessibilityIdentifier`,
     `actions: [Action]` (`id`, `title`). Equatable for the same SwiftUI-diffing reason
     as `EscriboWell` (`EscriboWell.swift`).
   - `EscriboEditor` gains `embedProvider: (any EscriboEmbedProvider)? = nil`,
     `onEmbedActivate: (EscriboBlock) -> Void`, `onEmbedAction: (EscriboBlock, String)
     -> Void`, and `onFindMatchInEmbed: (EscriboBlock) -> Void`. All defaulted, so
     existing call sites compile unchanged. **All new parameters go after
     `onWellAction`**, today's last parameter (`EscriboEditor.swift:151`); inserting
     one before it could change which parameter a trailing closure binds to.
     `onFindMatchInEmbed` follows `findBar`'s pattern rather than `#if`: present on both
     platforms, a no-op on iOS (`EscriboEditor.swift:59`).
   - **When the editor asks the provider (decided 2026-10-20, Q-1).** `any
     EscriboEmbedProvider` is not `Equatable`, so a SwiftUI update cannot show that its
     answers changed. The editor asks the provider:
     - for every block when the provider is first installed and when the document is
       loaded;
     - for the blocks inside each edit's rescanned window (the blocks the incremental
       scan returns), on every edit;
     - for **every block** when the host calls the new
       `EscriboEditorHandle.invalidateEmbeds()`. The host calls it whenever its
       provider's answers change without a text edit: *Edit as Text* (the provider starts
       returning `nil` for that block) and Find expansion (§ 1.3).

     The editor does not re-ask on every SwiftUI update. Notices (§ 2) use the same
     mechanism: `invalidateEmbeds()` also re-asks `wellNotice(for:)` for every block, and
     each edit re-asks it for the rescanned blocks. A handle with no editor attached
     ignores the call, like the handle's other methods.
   - `EditorMode.swift:3-8` says switching modes "is not a code path". A provider asked
     only in `.live` makes it one, so that doc comment changes.
   - **No expanded-set parameter.** `EscriboBlock.ID` is not stable across edits
     (`EscriboBlock.swift:26–33`), so a host-held `Set<EscriboBlock.ID>` would go stale
     after any edit above the block. *Edit as Text* is expressed by the provider itself
     returning `nil` for that block; the host keys its own expanded state on something
     stable to it (for a directive note, its content or an id inside it).
2. **Drawing** by the mechanism the spike proved: a fixed-height row (two lines of the
   current font; the spike's fixed 44 pt × zoom does not ship) at the block's indent, at
   most the text column's width; scales with zoom; uses the theme's colours. The
   spike's offset-keyed registry and `spikeSetExpanded` do not ship; the provider is
   asked per block (§ 1.1).
3. **Behaviour** (the spike's table, now required): caret never inside; arrows step
   over; selection extends to the whole block; Delete/Backspace removes the block plus
   one adjacent blank line as one undo step; Copy yields the source; typing with it
   selected is ignored; Find expands the embed holding the current match — **macOS
   only**, since the find bar is macOS-only — by calling `onFindMatchInEmbed`; the host
   then stops returning an embed for that block, and the match's text selection inside
   it is allowed because the block is no longer an embed (the whole-block selection rule
   applies only while it is one). The find bar is AppKit's built-in one and has no
   current-match hook today, so this needs one (new work, named here). `NSTextFinder`
   reports a match only by setting the selection, which the whole-block selection rule
   would snap before the host can react, so the editor detects a find-originated
   selection, calls `onFindMatchInEmbed`, lets that selection through unsnapped, and
   redraws when the host calls `invalidateEmbeds()` (§ 1.1).
   - **Click and caret placement.** A click (macOS mouse, iOS tap or pointer click)
     anywhere on the row selects the **whole block** and calls `onEmbedActivate` once.
     It never leaves a collapsed caret at the block's edge; the spike's edge-caret
     behaviour does not ship. The block stays selected after the call, so Copy, Delete
     and `⌥↩` act on it. A click outside any embed places the caret as today.
   - **Undo restores the embed.** Undoing a Delete/Backspace that removed an embed puts
     back the block's text **and** its embed (the editor asks the provider for the
     restored block like any other rescanned block), with the block selected. Redo
     removes it again. The spike restored only the text; a test proves the release
     restores both.
   - **`⌥↩` (Edit as Text) on both platforms (decided 2026-10-20, Q-6).** With an embed
     selected, `⌥↩` calls the *Edit as Text* action on macOS and on iOS. On iOS this is a
     `UIKeyCommand` and works with a hardware keyboard. Touch-only users reach *Edit as
     Text* through the accessibility custom actions (§ 1.4) or the host.
   - **iOS paste** into a selected embed is blocked, like typing.
4. **Accessibility:** one element per embed, button role, the host's label / value /
   identifier, default action = activate, custom actions = `actions`. On iOS the
   accessibility element count/index is answered by hand, as in the spike, until the
   live VoiceOver check shows that UIKit's default is correct.
5. **Off by default:** no provider → no change to layout, insets or behaviour; the
   existing tests pass untouched (the package has no UI test target).

## 2. Notice well slot

`EscriboWellItem.notice` (a new static member — additive, per the type's own
forward-compatibility rule) with a click callback through the existing `onWellAction`.
The well cannot do this today and needs real work, named here:
- **per-block content**: slots are global and their glyphs hard-coded; add a host
  callback `wellNotice(for block: EscriboBlock) -> (symbolName: String, help: String)?`
  — `nil` means the block has no notice;
- **where the callback lives (decided 2026-10-20, Q-2)**: `wellNotice` is an
  `EscriboEditor` init parameter, `wellNotice: ((EscriboBlock) -> (symbolName: String,
  help: String)?)? = nil`, placed **after `onWellAction`** (see § 1.1 for the ordering
  of the other new parameters) and defaulted, so existing call sites compile unchanged.
  It is **not** on `EscriboWell`, which holds no closures and stays `Equatable`
  (`EscriboWell.swift:68-71`). When the editor re-asks it is defined in § 1.1: on load,
  for each edit's rescanned blocks, and for every block on
  `EscriboEditorHandle.invalidateEmbeds()`;
- **visibility**: slots show only on hover or for the caret's block today; a notice is
  shown **always** for the blocks that have one;
- **slot sharing and drawing (decided 2026-10-20, Q-4)**: a notice **shares one slot
  with `.readAloud`**. On a block with a notice the slot shows the notice glyph at all
  times; on a block without one, `.readAloud` appears on hover or caret as today. A
  notice draws **its glyph only**, never the span bar (`WellOverlay.swift:331`);
- **eligibility**: today the well drops any item the package has no glyph for
  (`WellOverlay.swift:320–322`, `WellPlacement.symbolName`, `WellTracker.swift:373–378`),
  so `.notice` would never draw; it takes its glyph from the callback instead. It is
  exempt from the block-level `eligibleKinds` filter (`EscriboWell.isEligible`,
  `EscriboWell.swift:128–132`), so a block whose kind the host left out of
  `eligibleKinds` still shows its notice, **and** from `isEligible`'s "block has
  content" rule (`EscriboWell.swift:129`, decided 2026-10-20, Q-4): whether a block has
  a notice is the callback's answer alone.

## 3. JSON inside notes

Today `GlosaScanner` (`EscriboCore/GlosaScanner.swift`) subdivides tag directives inside
notes into `glosaTag` / `glosaAttributeName` / `glosaAttributeValue` /
`glosaPunctuation` spans (`SpanKind.swift:294–331`). It sees **one line at a time** and
carries no state between lines (`GlosaScanner.swift:60–68`, `FountainGrammar.swift:1024–1026`),
so it cannot know that line 2 of a note is inside JSON. Add: a note is scanned as JSON
**only when its trimmed content matches glosa-av 0.9.0's block-directive rule: `{`, then
optional whitespace (including newlines), then `"`** (decided 2026-10-20, Q-5; glosa-av
`AGENTS.md:35` at `v0.9.0`). This replaces "starts with `{`", so the colours agree with
what the compiler treats as a directive: `[[{sic}]]` and `[[{}]]` stay plain `note`. When
`[[` sits alone on its line the content starts on a later line, so the line state also
carries a "note open, no content yet" bit (and, for `[[{` followed by a line break, a
"`{` seen, waiting for `"`" bit) until the rule can be decided —

- new span kinds `glosaJSONKey`, `glosaJSONString`, `glosaJSONNumber`,
  `glosaJSONLiteral` (`true`/`false`/`null`), reusing `glosaPunctuation` for braces,
  brackets, colons and commas;
- malformed JSON stops subdividing at the first error and leaves the rest as `note`
  (no exception, no trap — the scanner's totality rule);
- **multi-line JSON notes are scanned across lines.** This is real work, named here:
  the line state the scanner carries (`LineState`) gains an "inside a JSON note"
  context — string/escape state, a container stack (object/array), and whether the
  next token in the current object is a key or a value (depth alone cannot tell keys
  from values) — and the incremental scanner re-scans following lines until line states
  match again, as it does today. The same context is added to `NestedFountainState` so
  fenced Fountain inside Markdown scans correctly. The container stack has a depth cap;
  JSON nested past it is treated as malformed (the rest of the note is plain `note`).
  The existing performance budgets (`make test-performance`: 50 ms, 1 ms, ≤ 8 lines)
  must still pass **with a fixture that contains multi-line JSON notes** — the current
  fixture has none, so it would pass without exercising the new path. JSON notes added
  to the fixture must contain no `` ``` `` and no `/*` (`ScanBudgetTests.swift:82-100`
  asserts both).
  **Convergence budget inside a JSON note (decided 2026-10-20, Q-3).** Inside a JSON note
  the carried state differs from line to line (the container stack and key/value
  expectation change), so typing `{` or `"` near the top of an N-line note changes the
  end state of every later line in it. For an edit **inside a multi-line JSON note** the
  rescan budget is therefore **"to the end of the enclosing multi-line JSON note + 8
  lines"**, not ≤ 8 lines. Edits anywhere else keep the ≤ 8-line budget. A new
  pathological case in `ScanBudgetTests` pins it: an edit that opens a string or a
  container near the top of a long (≥ 20-line) JSON note converges within the note's
  remaining lines + 8, and an unterminated `[[{"` prologue converges once the scan hits
  an error. A note's lines are one `.note` block when the note
  is followed by a blank line or the end of the document; a note **between** lines of
  the same block (action / note / action, or inside a speech) is absorbed into that
  block (`FountainBlockGroupingTests.swift:127–137`);
- **colours**: none of the four built-in themes colours any `glosa*` kind or `.note`
  today, so "same as the tag kinds" would mean uncoloured. Add colours for all `glosa*`
  kinds — existing and new — to all four built-in themes.

## 4. Tests

- Core: JSON span tiling over valid, multi-line, escaped (`]\u005d`) and malformed
  notes; the glosa-av trigger (`{"` and `{` + whitespace/newline + `"` scan as JSON;
  `{sic}`, `{}` and `{ 1 }` do not); `[[` alone on its line; depth-cap overflow; block
  grouping of a multi-line note as one `.note` block.
- Performance: `make test-performance` passes with the JSON-note fixture and the new
  in-note convergence case (§ 3).
- macOS and iOS: the spike's behaviour table as **unit tests** (the package has no UI
  test target), including click-selects-whole-block (no edge caret), undo restoring the
  embed, `invalidateEmbeds()` re-asking the provider and `wellNotice`, `⌥↩` (iOS through
  the `UIKeyCommand`), the macOS find-originated selection, and a test that types above
  an embed with no full rescan (macOS); no-provider behaviour checked by unit assertions
  on insets and layout geometry (there is no snapshot-testing setup). Existing
  `SwiftEscriboTests` pass. An iOS test fails loudly if UIKit's text layout manager
  delegate is missing.
- iOS live check (manual, recorded in the sortie's report): iPhone and iPad simulators.
- `make lint`, `make test`, `make test-ios` green.

## 5. Release

Minor release (`0.5.0`). Note in the CHANGELOG that hosts pinned `upToNextMinor` from
any 0.x (0.3.x and 0.4.x pins both exist downstream) must raise their pin to receive
it.

## Non-goals

- Anything about what an embed represents (storyboards, images, render state).
- Inline (mid-line) embeds; only whole blocks.
- Embeds in `EditorMode.source`.
