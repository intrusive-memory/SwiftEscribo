---
type: report
kind: spike
state: complete
title: SwiftEscribo — spike report: atomic block embeds on TextKit 2
updated: 2026-10-20
branch: spike/block-embeds
---

# Spike report: atomic block embeds on TextKit 2

> The spike code, tests, `EXECUTION_PLAN.md` and `SUPERVISOR_STATE.md` live on the unmerged
> branch `spike/block-embeds`. Only this report and its evidence PNGs are proposed for `development`.

**Question** (`REQUIREMENTS.md`): can SwiftEscribo draw one block as a single atomic row
(symbol, title, subtitle, badge) while its characters stay in the text storage unchanged,
on macOS (`NSTextView`) and iOS (`UITextView`), on TextKit 2?

**Short answer:** yes on both platforms, with the same drawing mechanism. Every behaviour
row has a passing unit test on both platforms. The gaps are in what unit tests can reach
(live VoiceOver, real pointer/touch/keyboard events, the system pasteboard on iOS) and in
two findings the release mission must design for: the macOS block cache goes stale on
typing above an embed, and on iOS the layout-manager delegate slot belongs to UIKit.

**Recommendation (for the user to accept or reject):**

| Platform | Recommended go / no-go |
|---|---|
| macOS | **Go**, conditional on the release fixing the stale block cache (below) instead of the spike's per-keystroke rescan. |
| iOS | **Go**, conditional on a live-simulator or device check of tap, handle drag, paste, forward-delete and VoiceOver as the first iOS release sortie, and on accepting the private-UIKit-delegate chaining risk. |

Neither is a no-go: nothing in the table failed. A no-go would be warranted if the live
check on iOS shows UIKit's tap or selection-handle gestures bypassing the
`selectedTextRange` setter and no other public funnel exists; the fallback then is the
well-slot design named in the release requirements' gate.

## Test runs (Sortie 8)

Run on branch `spike/block-embeds` at `f1d12fc`, macOS 26 / Xcode 26, Apple Silicon;
iOS on the iPhone 17 simulator, iOS 26.5.

| Run | Result |
|---|---|
| `make test` | Exit 0, `** TEST SUCCEEDED **` on the second attempt: 315 tests / 40 suites, 48 / 11, 383 / 37, all passed. The first attempt hung (see below). |
| `make test-ios` | Exit 0, `** TEST SUCCEEDED **`: 278 tests / 34 suites, 48 / 11, 383 / 37, all passed. |

Spike-suite lines:

```
# make test (macOS)
Test "row 10: a three-line standalone note is exactly one .note block covering all lines" passed
Suite "Block embed spike — core logic" passed
Test "row 1: the embed draws as one fixed-height custom row; the rest lays out normally" passed
Test "row 1: zoom (pointSizeScale 2) scales the row, and it survives the coordinator's restyle" passed
Test "row 2: textStorage is byte-identical with the embed; find, copy-all and word count see the source" passed
Test "row 10: the three note paragraphs (three layout fragments) together occupy exactly one row" passed
Test "row 10: mechanism comparison — only the frame override collapses N fragments without a storage edit" passed
Test "row 3: left/right arrows from the block's edges step over it; never inside" passed
Test "row 3: up/down from the adjacent lines land after/before the block; never inside" passed
Test "row 3: a click inside the row lands the caret on one of the block's edges" passed
Test "row 4: shift-arrows that touch the block extend the selection over all of it" passed
Test "row 4: a drag (stillSelecting) that touches the block extends over all of it" passed
Test "row 5: Delete with the block selected removes exactly deletionRange as one undo step" passed
Test "row 6: copy with the block selected writes the original characters" passed
Test "row 7: typing with the block selected changes nothing" passed
Test "row 8: expand draws the block as text and lets the caret in; collapse restores the row and the snap" passed
Test "row 9: one accessibility element per embed, label/value from the host, press fires the callback once" passed
Test "row 11: typing above the block and scrolling keep the row drawn; ≤ 2 row-fragment creations per step" passed
Test "evidence: renders collapsed / expanded / zoom2x PNGs when ESCRIBO_SPIKE_EVIDENCE_DIR is set" passed
Suite "Block embed spike — macOS draw" passed

# make test-ios (iOS 26.5 simulator)
Test "row 10: a three-line standalone note is exactly one .note block covering all lines" passed
Suite "Block embed spike — core logic" passed
Test "row 1: the embed draws as one fixed-height custom row; the rest lays out normally" passed
Test "row 1: zoom (pointSizeScale 2) scales the row, and it survives the coordinator's restyle" passed
Test "row 2: textStorage is byte-identical with the embed; find, copy-all and word count see the source" passed
Test "row 10: the three note paragraphs (three layout fragments) together occupy exactly one row" passed
Test "row 10: mechanism comparison — only the frame override collapses N fragments without a storage edit" passed
Test "row 3: left/right (position(from:in:offset:) + selectedTextRange) step over the block; never inside" passed
Test "row 3: up/down from the adjacent lines land before/after the block; never inside" passed
Test "row 3: a tap inside the row (closestPosition(to:)) lands the caret on one of the block's edges" passed
Test "row 3/row 4: hardware-keyboard arrows (UIKit's private _move*:withHistory:) reach the selection filter" passed
Test "row 4: extending selections that touch the block grow to cover all of it" passed
Test "row 5: Backspace with the block selected removes exactly deletionRange as one undo step" passed
Test "row 6: copy with the block selected — the copy source is the original characters" passed
Test "row 7: typing with the block selected changes nothing" passed
Test "row 8: expand draws the block as text and lets the caret in; collapse restores the row and the snap" passed
Test "row 9: one accessibility element per embed, label/value from the host, activate fires the callback once" passed
Test "row 11: typing above the block and scrolling keep the row drawn; ≤ 2 row-fragment creations per step" passed
Test "evidence: renders collapsed / expanded / zoom2x PNGs when ESCRIBO_SPIKE_EVIDENCE_DIR is set" passed
Suite "Block embed spike — iOS draw" passed
```

The other 13 `BlockEmbedSpikeCoreTests` cases (selection and deletion rules) passed in
both runs; only row-named lines are listed. The evidence test is a no-op in these runs
(`ESCRIBO_SPIKE_EVIDENCE_DIR` unset); the PNGs were produced in Sorties 4 and 7.
No test was marked `withKnownIssue`. The known flaky `FontResolutionTests.swift:141` did not fail in either completed run.

The first `make test` attempt did **not** complete. It hung for 29 minutes at 0% CPU in a
pre-existing test, `GeometryRuleSetTests` (`GeometryRuleSetTests.swift:75`), inside
`FontResolver.firstAvailable` → `NSFont(name:size:)` → a synchronous font-registry XPC
reply that never came. It was killed before any spike suite ran. This is environmental
(the same font-resolution family as the known flaky test), not spike code; the re-run
with a 15-minute cap passed in full. Earlier full `make test` / `make test-ios` passes
are recorded for Sorties 3, 4, 6 and 7 in `SUPERVISOR_STATE.md`.

## Mechanism

Shared code: `Sources/SwiftEscribo/Spike/BlockEmbedSpike.swift`
(`SpikeBlockEmbedController`, `SpikeEmbedSelection`, fragment classes). Platform code:
`MacBlockEmbed.swift`, `IOSBlockEmbed.swift`. Input hooks: `// SPIKE` overrides on
`EscriboNativeTextView` in `Sources/SwiftEscribo/EditorInputPath.swift`. The storage
pipeline (`EditorCoordinator.swift`, `NSTextStorageBridge.swift`) is unchanged.

### Draw and collapse (both platforms, identical)

- `NSTextLayoutManagerDelegate.textLayoutManager(_:textLayoutFragmentFor:in:)` vends a
  custom `NSTextLayoutFragment` for each paragraph of an embedded block.
- The fragment **overrides `layoutFragmentFrame` and `renderingSurfaceBounds`**.
  Paragraph 1 claims a fixed row height (44 pt × `pointSizeScale`) and draws the row
  (`NSImage(systemSymbolName:)` / `UIImage(systemName:)`, title, subtitle, trailing
  badge). Paragraphs 2..N claim height 0 and draw nothing. `NSTextLayoutManager` stacks
  each fragment under the previous fragment's overridden frame, so N fragments occupy
  one row.
- Tried and rejected, on both platforms (the row 10 "mechanism comparison" tests keep
  the comparison):
  - **Draw-only fragment:** layout uses the fragment's own line geometry; the three-line
    note stays three lines tall.
  - **`NSTextContentStorageDelegate` display paragraph:** collapses only on first vend.
    `recordEditAction` re-creates fragments, not paragraphs, so embedding a block already
    on screen needs a `textStorage` edit, which the spike forbids. It also re-attributes
    the real characters (tiny font), distorting caret geometry.
- **Invalidation:** `invalidateLayout(for:)` keeps the old fragment objects. The spike
  records a same-range edit on the content storage (`performEditingTransaction` +
  `recordEditAction`) so the block's fragments are re-requested. `textStorage` is never
  written; the row 2 tests assert the string and attributes are identical and the
  coordinator's `restyleCount` does not move.

### Selection constraint

- **macOS:** override of `setSelectedRanges(_:affinity:stillSelecting:)`, routed to
  `SpikeEmbedSelection.constrain`. Arrows, shift-arrows, clicks and drags all funnel
  through it (AppKit documents this method as the override point for constraining
  selection). `characterIndexForInsertion(at:)` does return offsets inside the row; the
  filter snaps them. The `NSTextViewDelegate` slot is untouched.
- **iOS:** overrides of the `selectedTextRange` and `selectedRange` setters. UIKit's
  private `_moveRight/Left/Up/Down:withHistory:` (what hardware arrows call) each commit
  through the public `selectedTextRange` setter once, so the filter covers them. UIKit has
  no documented single selection funnel, so tap and selection-handle drag are covered only
  if they too use the setter (not proven; see row 3/4).

### Delete, typing, copy

- **macOS:** `deleteBackward`/`deleteForward` overrides delete
  `SpikeEmbedSelection.deletionRange` (block + following blank line, or preceding when
  last) in one `shouldChangeText` / `replaceCharacters` / `didChangeText` group, one undo
  registration. A `shouldChangeText(in:replacementString:)` override vetoes any edit that
  inserts into, or removes part of, an embed (typing, Return, Tab, paste). Default
  `NSTextView` copy already writes the storage range.
- **iOS:** UIKit has no view-level `shouldChangeText`, so `insertText`, `setMarkedText`,
  `replace(_:withText:)` and `deleteBackward` each consult the edit rule. Backspace with
  an embed selected deletes through `performInputPathEdit`, one undo step. `copy(_:)`
  reads the selected range's text from storage.

### Accessibility

- **macOS:** `accessibilityChildren()` override appends one cached
  `NSAccessibilityElement` per collapsed embed: role button, label = title, value =
  "subtitle, badge", press → `onSpikeEmbedActivate`, frame converted with
  `NSAccessibility.screenRect(fromView:)` (the default conversion was wrong for the
  flipped text view).
- **iOS:** `accessibilityElements` override appends one `UIAccessibilityElement` per
  collapsed embed (trait `.button`, same label/value, `accessibilityActivate()` → the
  callback). In the test host UIKit's default `accessibilityElementCount()` returned 0
  and `accessibilityFrame` returned `.zero` without the accessibility runtime loaded, so
  the spike also answers the count/index API itself and converts the frame explicitly.

### Expand / collapse and edits elsewhere

- `spikeSetExpanded` toggles the registry's expanded set and re-vends the block's
  fragments; expanded blocks are not embeds, so they draw as text and the caret can enter.
  Collapsing re-asserts the selection so a caret inside is pushed to an edge.
- Registry keys (block start offsets) are shifted on
  `NSTextStorage.willProcessEditing` (a notification; the storage delegate is the
  coordinator's).
- **macOS finding:** an ordinary keystroke above the note left the coordinator's spliced
  block list stale (`blocksSpanDocument == false`). The spike falls back to a read-only
  full `EscriboScanner` scan, cached until the next character edit — i.e. **one full scan
  per keystroke**. Not acceptable for release.
- **iOS:** the same keystrokes through `insertText` kept the block list spliced
  (`blocksSpanDocument == true`); the fallback scan never ran.

### iOS delegate-slot finding

Recon A-07 found the `NSTextLayoutManager.delegate` slot free. That held for package
code only: on iOS 26 `UITextView` installs its own `_UITextKit2LayoutController` there.
The spike keeps the displaced delegate weakly and forwards every call it does not answer
(`responds(to:)` / `forwardingTarget(for:)`); non-embedded paragraphs get whatever
fragment UIKit's delegate vends. Replacing it outright also passed rows 1, 2, 10 but
would silently drop UIKit behaviour. **Release risk:** the package sits in front of a
private UIKit object whose behaviour can change in any iOS release. The content-storage
delegate slot is free on both platforms; the macOS layout-manager slot is free.

## Interpretations used (from `EXECUTION_PLAN.md`)

| Row | Term | Interpretation |
|---|---|---|
| 1 | "zoom scales it" | Zoom = the package's `FontMetrics.pointSizeScale`. The row height scales with it. |
| 5 | "plus one adjacent blank line" | The following blank line; if the block is last, the preceding one; if neither exists, the block alone. |
| 9 | "VoiceOver reads it" | Unit proxy: one accessibility element with host label/value whose default action calls the host callback. Live VoiceOver is a manual check. |
| 3–7 | user input | Driven through the text view's own responder / `UITextInput` entry points, never by mutating storage. |

## Results

PASS = the behaviour is proven by the cited test or evidence, with no gap the requirement
cares about. PARTIAL = the test passes but a part of the requirement is not proven.
FAIL = none. Test names are the `@Test` display names in
`Tests/SwiftEscriboTests/BlockEmbedSpikeMacTests.swift` (`BlockEmbedSpikeMacTests`) and
`Tests/SwiftEscriboTests/BlockEmbedSpikeIOSTests.swift` (`BlockEmbedSpikeIOSTests`); row
10's block-grouping prerequisite is in `BlockEmbedSpikeCoreTests`.

### macOS

| # | Behaviour | Result | Evidence |
|---|---|---|---|
| 1 | Draw | PASS | "row 1: the embed draws as one fixed-height custom row; the rest lays out normally"; "row 1: zoom (pointSizeScale 2) scales the row, and it survives the coordinator's restyle"; [evidence/mac-embed-collapsed.png](evidence/mac-embed-collapsed.png), [evidence/mac-embed-zoom2x.png](evidence/mac-embed-zoom2x.png) |
| 2 | Storage untouched | PASS | "row 2: textStorage is byte-identical with the embed; find, copy-all and word count see the source". Find is checked as a string search of the storage, not through the find bar. |
| 3 | Caret step-over | PASS | "row 3: left/right arrows from the block's edges step over it; never inside"; "row 3: up/down from the adjacent lines land after/before the block; never inside"; "row 3: a click inside the row lands the caret on one of the block's edges". Down from the line above stops on the block's start edge first and needs a second press to pass it. |
| 4 | Select whole | PASS | "row 4: shift-arrows that touch the block extend the selection over all of it"; "row 4: a drag (stillSelecting) that touches the block extends over all of it" |
| 5 | Delete whole | PASS | "row 5: Delete with the block selected removes exactly deletionRange as one undo step" (Delete and forward-delete, one undo registration, undo restores the string byte-for-byte). Undo restores the text but not the embed (it redraws as plain text). |
| 6 | Copy source | PASS | "row 6: copy with the block selected writes the original characters" (`writeSelection(to:types:)` on a private named pasteboard) |
| 7 | Typing ignored | PASS | "row 7: typing with the block selected changes nothing" |
| 8 | Expand / collapse | PASS | "row 8: expand draws the block as text and lets the caret in; collapse restores the row and the snap"; [evidence/mac-embed-expanded.png](evidence/mac-embed-expanded.png) |
| 9 | Accessibility | PARTIAL | "row 9: one accessibility element per embed, label/value from the host, press fires the callback once" passes. Not proven: that VoiceOver actually reads and activates it (no live VoiceOver run). |
| 10 | Multi-line block | PASS | "row 10: the three note paragraphs (three layout fragments) together occupy exactly one row"; "row 10: mechanism comparison — only the frame override collapses N fragments without a storage edit"; Core: "row 10: a three-line standalone note is exactly one .note block covering all lines" |
| 11 | Scroll and edit elsewhere | PARTIAL | "row 11: typing above the block and scrolling keep the row drawn; ≤ 2 row-fragment creations per step" passes (1 row fragment per keystroke, 0 per scroll). It passes only because of a full read-only rescan per keystroke, added after the coordinator's block cache went stale; that workaround is not shippable. |

macOS: **9 PASS, 2 PARTIAL, 0 FAIL.**

### iOS

| # | Behaviour | Result | Evidence |
|---|---|---|---|
| 1 | Draw | PASS | "row 1: the embed draws as one fixed-height custom row; the rest lays out normally"; "row 1: zoom (pointSizeScale 2) scales the row, and it survives the coordinator's restyle"; [evidence/ios-embed-collapsed.png](evidence/ios-embed-collapsed.png), [evidence/ios-embed-zoom2x.png](evidence/ios-embed-zoom2x.png) |
| 2 | Storage untouched | PARTIAL | "row 2: textStorage is byte-identical with the embed; find, copy-all and word count see the source" passes for storage, find (string search) and word count. Copy-all is checked as the selected text the copy path reads, not the pasteboard: reading `UIPasteboard.general` hangs the simulator test host. |
| 3 | Caret step-over | PARTIAL | "row 3: left/right (position(from:in:offset:) + selectedTextRange) step over the block; never inside"; "row 3: up/down from the adjacent lines land before/after the block; never inside"; "row 3/row 4: hardware-keyboard arrows (UIKit's private _move*:withHistory:) reach the selection filter"; "row 3: a tap inside the row (closestPosition(to:)) lands the caret on one of the block's edges". Arrows are proven through UIKit's private movement methods, not key events. The tap test sets the selection through the public setter; that UIKit's tap gesture uses the same setter is not proven. |
| 4 | Select whole | PARTIAL | "row 4: extending selections that touch the block grow to cover all of it"; shift-arrow via the private route in the row 3/row 4 hardware-arrow test. Drag is simulated by setting ranges; selection-handle drag through UIKit's text interaction is not exercised. |
| 5 | Delete whole | PARTIAL | "row 5: Backspace with the block selected removes exactly deletionRange as one undo step" passes (one undo step, byte-identical restore, partial Backspace vetoed). Forward-delete (hardware) is not hooked or tested. Undo restores the text but not the embed. |
| 6 | Copy source | PARTIAL | "row 6: copy with the block selected — the copy source is the original characters" asserts `text(in: selectedTextRange)` and the attributed substring, not the pasteboard (`copy(_:)` writes only to the general pasteboard, which hangs the test host). |
| 7 | Typing ignored | PASS | "row 7: typing with the block selected changes nothing" (`insertText` of x, Return, Tab; `setMarkedText`; `replace(_:withText:)`). Paste is not a keystroke and is not covered: it is untested and may bypass the veto. |
| 8 | Expand / collapse | PASS | "row 8: expand draws the block as text and lets the caret in; collapse restores the row and the snap"; [evidence/ios-embed-expanded.png](evidence/ios-embed-expanded.png) |
| 9 | Accessibility | PARTIAL | "row 9: one accessibility element per embed, label/value from the host, activate fires the callback once" passes. Not proven: live VoiceOver. The test host's own count/index API returned 0, so the spike answers it itself; whether VoiceOver needs that is unknown. |
| 10 | Multi-line block | PASS | "row 10: the three note paragraphs (three layout fragments) together occupy exactly one row"; "row 10: mechanism comparison — only the frame override collapses N fragments without a storage edit"; Core: "row 10: a three-line standalone note is exactly one .note block covering all lines" |
| 11 | Scroll and edit elsewhere | PASS | "row 11: typing above the block and scrolling keep the row drawn; ≤ 2 row-fragment creations per step" (1 row fragment per keystroke, 0 per scroll, 0 fallback scans, block list stayed spliced) |

iOS: **5 PASS, 6 PARTIAL, 0 FAIL.**

## Known limitations

What the unit tests cannot prove, on either platform:

- **Live VoiceOver.** No run with VoiceOver on. Row 9 proves the element tree only.
- **Real input events.** No hardware key presses, trackpad clicks or drags, or touches
  were delivered. macOS drives responder methods (`moveDown(_:)`,
  `setSelectedRange(_:affinity:stillSelecting:)`); iOS drives `UITextInput` and UIKit's
  private `_move…:withHistory:` methods.
- **IME** composition in a live window (only `setMarkedText` was called directly on iOS).
- Rendering in a live window: PNGs come from `cacheDisplay(in:to:)` (macOS) and
  `layer.render(in:)` (iOS; `drawHierarchy` rendered blank in the test host).

macOS:

- Down from the line above takes two presses: the first lands on the block's start edge.
- Undo of a deleted embed restores the text, not the embed (the spike registry dropped
  it). The release design, where a provider is asked per block, should restore it
  naturally; unproven.
- Word/line deletions that would take part of an embed are vetoed rather than taking the
  embed whole.
- Typing above an embed leaves the coordinator's block cache stale; the spike rescans the
  whole document per keystroke. The release must make the coordinator's splice reliable
  (or give embeds an incremental path) and measure it against the performance budgets.
- Find was checked as a string search; the find bar's behaviour on a match inside a
  collapsed embed is untested (the release requirements already name this as new work).

iOS:

- Copy is proven only through the selected text; the general pasteboard hangs the
  simulator test host (one run hung 38 minutes before it was killed).
- Arrows proven via UIKit's private movement methods; tap and handle drag via the public
  setter only.
- Forward-delete and paste are untested; paste is not blocked by the spike.
- The accessibility count/index API is answered by the spike because it returned 0 in
  the test host.
- The spike chains behind UIKit's private `_UITextKit2LayoutController` in the
  layout-manager delegate slot.

Spike-wide: the row height is a fixed 44 pt × zoom; the release requirements ask for two
lines of the current font. The embed registry is keyed by block start offsets; the
release API (provider asked per block) replaces it.

## Estimate for the release mission

Against `docs/missions/block-embeds/REQUIREMENTS.md`, in sorties of the size this spike
used:

| Area | Sorties | Notes |
|---|---|---|
| Embed API (`EscriboEmbedProvider`, `EscriboEmbed`, editor parameters, no-provider = no change) | 1 | |
| Shared controller productionised: provider-driven ranges, no offset registry, layout-manager delegate chaining | 1 | |
| macOS block-cache splice fix + performance budget check | 1 | Replaces the per-keystroke rescan. |
| macOS draw + behaviour (rows 1–8, 10, 11), click → activate, `⌥↩` | 1 | Mostly a port of the spike code. |
| macOS accessibility (custom actions, identifier) + find current-match hook (`onFindMatchInEmbed`) | 2 | The find hook is new work with no current API. |
| iOS live check (tap, handle drag, paste, forward-delete, VoiceOver) | 1 | Gate for the iOS sorties; may change the selection hook. |
| iOS draw + behaviour incl. paste veto and forward-delete | 1 | |
| iOS accessibility + tap → activate | 1 | |
| Notice well slot (per-block content, always-visible, eligibility exemption; both platforms) | 2 | |
| JSON in notes: span kinds + single-line scan | 1 | |
| JSON in notes: multi-line `LineState` / `NestedFountainState`, incremental re-scan | 2 | |
| JSON in notes: performance fixture with multi-line JSON notes + theme colours (4 themes) | 1 | |
| Release (0.5.0, CHANGELOG pin note, lint, full test runs) | 1 | |

**Total: about 16 sorties (range 14–18), 9 of them for embeds.** The spike removes the
drawing risk; the open risk is the iOS live check, which could add a sortie if UIKit's
gestures need a second selection hook.
