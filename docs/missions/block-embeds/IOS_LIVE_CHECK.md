---
type: report
kind: live-check
state: complete
title: SwiftEscribo — iOS live input check for atomic block embeds (Sortie 2 gate)
updated: 2026-10-20
spike_branch: mission/pressed-flower/s02-ios-live-check (from spike/block-embeds @ 506afcf)
paste_veto_commit: b205e38
verdict: GO
---

# iOS live input check: atomic block embeds

**VERDICT: GO**, with the funnel named: every tap, caret drag, selection-handle release,
hardware arrow and forward-delete that proposed a caret or partial selection inside the
embed committed it through the public `UITextView.selectedTextRange` setter, where the
spike's filter snapped or widened it. The model selection was never inside the embed.
Three gaps remain for Sortie 14 and 15 (details below):

1. While a selection handle is being dragged, UIKit draws a preview range that can end
   inside the row. It does this without calling the setter and without changing
   `selectedRange`. On touch-up the range commits through the setter and is widened to
   the whole embed. This is cosmetic, but no public funnel was found that corrects the
   preview itself.
2. iPad pointer and trackpad input (row e) could not be delivered by the simulator
   tooling, so it is **not verified**.
3. VoiceOver (row f): by default the embed's button element is **not** in the live
   accessibility tree, because `UITextView` is itself an accessibility element. Setting
   `isAccessibilityElement = false` on the text view exposes it. Activation could not be
   driven live.

## Setup

| Item | Value |
|---|---|
| Devices | iPhone 17 Pro simulator (iOS 26.5, `E18C6A25-…`); iPad Pro 11-inch (M5) simulator (iOS 26.5, `2EA3EDF5-…`) |
| Toolchain | Xcode 27.1 (27A9275), iOS 26.5 simulator runtime, AXe 1.8.0 (through XcodeBuildMCP and its CLI) |
| Package | Branch `mission/pressed-flower/s02-ios-live-check`, cut from `spike/block-embeds` @ `506afcf`, plus paste-veto commit `b205e38` |
| Host | A throwaway SwiftUI app outside the repo. It depends on the package by local path, shows `EscriboEditor(text:language: .fountain)`, and embeds the three-line note `[[First line of the note / second line / third line]]` (UTF-16 range 42..<92) through the spike controller (`spikeSetEmbed`), reached with `@testable import`. |
| Instrumentation (host only) | A readout line showing `selectedRange`, the embed range, the document length and the number of `selectedTextRange` setter calls. A 60 Hz `CADisplayLink` counts any frame in which `selectedRange` is a caret strictly inside, or a partial overlap of, the embed (`viol`). It is 0 in every run below. The spike's `spikeSelectionFilter` is wrapped to log every proposal as `proposed>result`. |

**How input was delivered.** Taps, holds and drags were real HID touch events
(`axe touch` down/move/up). Hardware keys were HID key events (`axe key <code> --duration
0.2`). Events shorter than about 0.1 s were dropped by the simulator, so instant taps and
`key-combo` (no hold) did not register. `toggle_connect_hardware_keyboard` was run, but
this machine has no Simulator.app; key delivery started working once keys were held for
0.2 s. Shift-arrow combos could not be delivered. The paste menu came from UIKit's real
edit menu. The Paste action was also sent directly (`paste(nil)`) after an exact
programmatic selection. The pasteboard content is irrelevant to the result and is not
recorded here.

## Results

Proposals are written `proposed>result` in UTF-16 `location,length`. The embed is `42,50`.

### iPhone 17 Pro (iOS 26.5)

| Row | Check | Result | Evidence |
|---|---|---|---|
| (a) | Tap on the row | **PASS** | Taps at the left, middle and right of the row, and near its top and bottom edges. UIKit proposed the caret at 66, inside the embed (end of its first line), every time. Each tap went through the setter once and was snapped to an edge: `66,0>92,0` coming from above and `66,0>42,0` coming from below. `viol=0`. A long-press caret drag committed live through the setter on every step (`34,0>34,0 … 41,0>41,0`) and stopped at 41, outside the embed. [ios-live-iphone-a-tap-row.png](evidence/ios-live-iphone-a-tap-row.png) |
| (b) | Selection-handle drag across the row | **PASS (commit) / cosmetic gap (preview)** | Trailing handle held inside the row: UIKit drew the handle and highlight partway into the row ([held](evidence/ios-live-iphone-b-handle-drag-held.png)), while `selectedRange` stayed `22,5` and the setter was not called. On release it committed once through the setter, `22,44>22,70` (proposed end 66 is inside; widened over the whole embed) ([released](evidence/ios-live-iphone-b-handle-drag-released.png)). Leading handle dragged up from the next line into the row committed `66,38>42,62`. `viol=0` throughout. |
| (c) | Paste with the block selected | **FAIL before veto → PASS after `b205e38`** | Before: with exactly `42,50` selected, `canPerformAction(paste:)` was true. `paste(_:)` replaced all 50 characters of the embed (document 122 → 80 UTF-16 units, embed gone). None of `insertText`, `replace(_:withText:)` or `setMarkedText` saw it. After: with exactly the block selected, `canPerformAction(paste:)` is false and `paste(nil)` changes nothing (length 122, no system paste prompt, so the pasteboard was never read) ([vetoed](evidence/ios-live-iphone-c-paste-vetoed.png)). With a real handle-drag selection covering the embed (`22,70`), UIKit's edit menu shows Cut / Copy / AutoFill / Look Up and **no Paste** ([menu](evidence/ios-live-iphone-c-menu-without-paste.png)). |
| (d) | Hardware forward-delete (HID 0x4C) with the block selected | **PASS** | `42,50` selected, then forward-delete: the document went from 122 to 71, removing the embed plus the following blank line (exactly `deletionRange`) in one keystroke. The caret ended at 42 ([after](evidence/ios-live-iphone-d-forward-delete.png)). This shows UIKit routes forward-delete with a selection into `deleteBackward`, the spike's handler. With the caret at 42 (just before the embed), forward-delete first proposed `42,1`, which the setter filter widened to `42,50`, and then deleted the embed and blank line in the same keystroke. Backspace with the caret at 92 (just after the embed) did nothing: the partial delete was vetoed. Hardware ←/→ stepped over the embed through the setter (`91,0>42,0`). |
| (e) | iPad pointer | n/a | iPhone. |
| (f) | Accessibility tree | **FAIL by default; PASS with `isAccessibilityElement = false`** | Default: the tree has `TextArea` (the editor) and **no** child for the embed. The spike's `accessibilityElements` override is never consulted, because the text view is itself an element. With the host setting `textView.isAccessibilityElement = false`, the tree shows `TextArea` and, under it, `Button 'Note' value 'First line of the note, 3 lines'` at {x 13, y 217, w 376, h 44}, which matches the drawn row. `snapshot_ui` lists it as `button|Note|First line of the note, 3 lines`. Activation could not be driven live: XcodeBuildMCP/AXe "tap" on that element is a coordinate touch, which went to the text view (caret 92, `act=0`). Live VoiceOver speech cannot run in the Simulator, so the AX tree is the proxy; activation remains proven only by the unit test (spike row 9). |

### iPad Pro 11-inch (M5) (iOS 26.5)

| Row | Check | Result | Evidence |
|---|---|---|---|
| (a) | Tap on the row | **PASS** | Same as iPhone: every tap proposed 66 and was snapped through the setter (`66,0>92,0` / `66,0>42,0`). A tap near the row's top edge proposed `50,0>92,0`. `viol=0`. [ios-live-ipad-a-tap-row.png](evidence/ios-live-ipad-a-tap-row.png) |
| (b) | Selection-handle drag across the row | **PASS (commit) / cosmetic gap (preview)** | Leading handle dragged up from "enters" into the row and held: the preview handle sat inside the row with `selectedRange` still `98,6` and no setter call ([held](evidence/ios-live-ipad-b-handle-drag-held.png)). Release: `66,38>42,62`, the whole embed ([released](evidence/ios-live-ipad-b-handle-drag-released.png)). |
| (c) | Paste with the block selected | **PASS (partial evidence)** | With exactly `42,50` selected, the live rule verdict (`spikePasteAllowed()`) was false, `canPerformAction(paste:)` false, and `paste(nil)` changed nothing ([vetoed](evidence/ios-live-ipad-c-paste-vetoed.png)). The rule was true at a caret elsewhere. This simulator's pasteboard was empty, and `simctl pbcopy` did not stick. I did not copy in-app to fill it, so a pre-veto failure could not be reproduced here. The iPhone run is the discriminating one; the code path is the same. |
| (d) | Hardware forward-delete with the block selected | **PASS** | 122 → 71, the embed plus the following blank line in one keystroke ([after](evidence/ios-live-ipad-d-forward-delete.png)). Caret at 42, then forward-delete: `42,1>42,50`, then the same deletion. Backspace at 92: no-op (vetoed). |
| (e) | iPad pointer click and trackpad drag | **NOT VERIFIED** | The tools deliver only touch HID (AXe `touch`/`tap`/`drag`/`swipe`) and keyboard HID. There is no pointer injection, and no Simulator.app here for "Capture Pointer". What was delivered instead: touch taps (row a) and touch handle drags (row b). Pointer click and click-drag go through UIKit's pointer selection interaction, which may differ from touch. This needs a device or a Simulator.app run with a captured pointer. |
| (f) | Accessibility tree | **FAIL by default; PASS with `isAccessibilityElement = false`** | Default: `TextArea` only. With `isAccessibilityElement = false`: `Button 'Note' 'First line of the note, 3 lines'` at {x 13, y 176, w 808, h 44}, matching the row. Activation and VoiceOver as on iPhone. |

## Paste veto (commit `b205e38` on `mission/pressed-flower/s02-ios-live-check`)

`EscriboNativeTextView` (iOS) gains `spikePasteAllowed()`. It asks the same `spikeEditFilter`
typing uses (`SpikeBlockEmbedController.allowsEdit`) about the current selection, with a
non-empty stand-in for the pasted text. The pasteboard is never read: reading it would
raise the system paste prompt during menu validation, and it hangs the simulator test
host. `canPerformAction(_:withSender:)` returns false for `paste:`,
`pasteAndMatchStyle:` and `paste(itemProviders:)` while the rule says no. `paste(_:)`,
`pasteAndMatchStyle(_:)` and `paste(itemProviders:)` also return early, because a key
command or host can send the action without asking first.

Unit test: `BlockEmbedSpikeIOSTests` "row 7: paste with the block selected (or partly
covered) changes nothing and is hidden from the menu". It checks the exact block and a
wider selection (vetoed through all three entry points, text unchanged, menu actions
disabled), carets at both edges (allowed), and that the verdict is `allowsEdit`'s.

`make test-ios` on that branch: exit 0, `** TEST SUCCEEDED **`, 279 tests / 34 suites
(SwiftEscriboTests), 48 / 11, 383 / 37. The new test passed. Wall time 1:08.

## Selection funnels UIKit's gestures use (input for Sortie 14)

| Gesture | Goes through | Notes |
|---|---|---|
| Tap | `selectedTextRange` setter, once per tap | Proposal is `closestPosition(to:)`-like: 66 for any point in the row, because the row's first line keeps its real line fragment. |
| Long-press / caret drag | `selectedTextRange` setter, live on every step | Never proposed a position inside the embed in this run. |
| Range-handle drag | **Preview: none public.** Commit: `selectedTextRange` setter, once, on touch-up | During the drag, UIKit calls the public `closestPosition(to:)` (43 calls in one drag; `closestPosition(to:within:)` and `characterRange(at:)` were never called). A host-side override that snapped any position inside the embed to the edge on the point's side of the row's midline fired, but the preview still entered the row ([ios-live-iphone-b-closestposition-snap-held.png](evidence/ios-live-iphone-b-closestposition-snap-held.png)), and the commit still proposed `22,44`. So the preview hit-test is not `closestPosition(to:)`. It is most likely TextKit 2's own selection navigation over the layout fragments. |
| Hardware arrows | `selectedTextRange` setter (spike finding, confirmed live: `91,0>42,0`) | |
| Forward-delete | With a selection: `deleteBackward` (the spike's handler). With a caret: selects one character forward through the setter (widened to the embed), then `deleteBackward`. | Forward-delete at the start edge removes the whole embed in one key press. Backspace at the end edge is a silent no-op. Sortie 14 should choose one behaviour for both, for example "first press selects the block". |
| Paste | `paste(_:)` / `canPerformAction` only | Bypassed every typing hook. Now vetoed. |
| Edit-menu AutoFill / Cut | Not checked | AutoFill stays in the menu over an embed; whether its insertion passes the edit rule is untested. Cut of a selection covering the whole embed is a full deletion, which the rule allows. |

**What Sortie 14 needs:**

- Keep the `selectedTextRange` (and `selectedRange`) setter override as the selection funnel.
  It is proven live to catch every commit.
- Choose the tap's edge from the touch point, not from the travel direction. Today a second
  tap on the same row flips the caret between 42 and 92.
- Treat the handle-drag preview as a known cosmetic limitation, or try a TextKit-level fix.
  Two options: give the row fragment line fragments or an `NSTextSelectionDataSource`
  answer that map the row to its two edges, or override `selectionRects(for:)` to draw a
  covering range. Both are unproven.
- Keep the paste veto (and add AutoFill / drop if they turn out to bypass it).

**What Sortie 15 needs:** set `isAccessibilityElement = false` on the text view while
embeds are present (or expose the text another way). Then check that VoiceOver still reads
and edits the text, and that activation reaches the callback, on a device.

## Verdict

The NO-GO condition did not occur: UIKit's tap and selection-handle gestures never left the
caret or a partial selection inside the embed. Every proposal that landed inside (`66,0`,
`22,44`, `66,38`, `42,1`) reached the public `selectedTextRange` setter and was snapped or
widened by the spike's filter. The 60 Hz watch on `selectedRange` saw no violation on
either device. The one bypass found, the handle-drag preview, is drawing only. It never
changes the selection, and it is corrected by the same public setter at touch-up.
Caveats: iPad pointer input (row e) is unverified, and accessibility needs
`isAccessibilityElement = false` (row f).

VERDICT: GO — the public `selectedTextRange` setter catches every tap, caret-drag and handle-drag commit that UIKit proposed inside the embed, on both iPhone and iPad (handle-drag preview is cosmetic; iPad pointer unverified).
