---
type: mission-brief
state: complete
updated: 2026-10-20
---

# Iteration 01 Brief — OPERATION PRESSED FLOWER

**Mission:** Block embeds, a notice well slot, and JSON scanning inside Fountain notes, shipped as the next minor release.
**Branch:** one branch per sortie, `mission/pressed-flower/sNN-*`, each merged to `development` by PR (#25–#43)
**Starting Point Commit:** `42ff695` (development after PR #23)
**Sorties Planned:** 18
**Sorties Completed:** 18, plus 1 supplementary (S1b)
**Sorties Failed/Blocked:** 0
**Duration:** one session, 2026-10-20
**Outcome:** Complete
**Verdict:** `KEEP` — every sortie merged green on the first attempt, the iOS gate passed with evidence, and no sortie's output was later reverted.
**Tests pruned:** 0
**Tests flagged for review:** 8

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

## Section 1: Hard Discoveries

### 1. macOS over-reports a typed character's edited range

**What happened:** `NSTextView.insertText` reports one typed character as `editedRange {n,2}`; AppKit's attribute fixing stretches it over the line terminator between will- and did-process-editing. iOS reports `{n,1}`. The extra unit pushed convergence into the next block and the splice declined. Separately, the scanner's window was never block-aligned, so typing *inside* any long block declined on both platforms.
**What was built to handle it:** A block-aligned incremental window (`EscriboScanner.incrementalScan(_:in:alignedToBlocks:)`, package-level), capped at +64 lines beyond convergence; over the cap it behaves exactly as before. A `fullScanCount` counter proves it.
**Should we have known this?** Partly. The spike saw the symptom, not the cause.
**Carry forward:** A block longer than ~64 lines with embeds active costs one full scan per keystroke. Taking the edit range from `willProcessEditing` would remove the macOS over-report.

### 2. `UITextView` hides `accessibilityElements` overrides

**What happened:** `UITextView` is itself an accessibility element, so the spike's `accessibilityElements` override never reached the live AX tree. The spike's workaround (`isAccessibilityElement = false`) would break VoiceOver text editing.
**What was built to handle it:** Transparent per-embed accessibility subviews inside one plain container subview. A direct subview with an identifier is listed twice by the simulator's AX tree; the container avoids it.
**Should we have known this?** Yes. A live AX snapshot in the spike would have shown it.
**Carry forward:** Verify accessibility in the live tree, not in unit-test hosts (they report `isAccessibilityElement == false` even for a stock text view).

### 3. UIKit gesture and key paths that bypass public funnels

**What happened:** Tap and handle-drag commits go through the public `selectedTextRange` setter (GO), but the handle-drag *preview* does not. A `UIKeyCommand` for forward-delete never fires. After undo, UIKit reselects the restored range without the setters.
**What was built to handle it:** Forward-delete taken in `pressesBegan`; post-undo reselection deferred one run-loop turn; `RunLoop.main.perform` instead of `DispatchQueue.main.async` (the latter does not drain in main-actor tests).
**Carry forward:** The handle-drag preview drawing inside a row is cosmetic and unfixed. iPad pointer input is unverified (the simulator tools cannot send pointer events).

### 4. A literal `]]` closes a Fountain note before any JSON scanning

**What happened:** The note grammar closes at the first `]]`, so a JSON string cannot protect it. Writers use the `]` escape.
**Carry forward:** Documented. Changing it would be a grammar change.

### 5. Font service misbehaves under load

**What happened:** Under heavy parallel load, `NSFont(name:size:)` blocked on the font-registry XPC (13 threads), returned 0 pt monospaced fonts, and once returned Helvetica 12 for the system font.
**What was built to handle it:** An installed-family check before named lookups, serialised and cached lookups, retries on size-mismatched replies (never cached), and `-test-timeouts-enabled YES` with a 300 s allowance on every `xcodebuild test`.
**Carry forward:** The S1b root cause is unproven. `CTFontGetAdvancesForGlyphs` can still stall; the timeout now fails the run instead of hanging it.

### 6. The CI runner image intermittently lacks the pinned simulator

**What happened:** "Unable to find a device matching … iPhone 17, OS 26.5" before any test ran, twice. One rerun passed each time.
**Carry forward:** If it recurs, resolve the iOS simulator dynamically, the way the host app's workflow does.

## Section 2: Process Discoveries

### What the Agents Did Right

- **Measured before choosing.** S7 measured both platforms' edit ranges and rejected the "merge edge blocks" route because grouping is not line-local.
- **Live checks beyond the exit criteria.** S14 and S15 verified their behaviour on running simulators and found three UIKit paths the unit tests could not reach.
- **Honesty.** S1b said its root cause was unproven. S4 explained why it dropped the string and escape bits: JSON forbids a raw newline inside a string.

### What the Agents Did Wrong

- **Gamed a grep criterion.** S1 met the `grep -c ≥ 2` criterion with a comment line. The underlying intent (every invocation carries the flags) was met, so this was a criterion defect.

### What the Planner Did Wrong

- **Garbled an escape in the orders.** The `]` escape in S3's orders was decoded in transit, so S3 needed a continuation. Write escapes in words, or as doubled backslashes, in dispatch prompts.
- **Left a performance cost unmeasured.** S7's widened window was not bounded until the supervisor asked. Plans that change scanner windows should require editor-path performance cases.
- **Missed a cross-platform rule.** S10 left a gap: `allowsEdit` permits replacing a selected embed. Both platforms added their own veto. The shared rule should have been specified.

## Section 3: Open Decisions

### 1. A notice hides the read-aloud stop control while its block is playing

**Why it matters:** Q-4 says the notice is "shown at all times" in the shared slot. Read literally, that removes the stop button on a block that has a notice while it plays.
**Options:** (a) keep, as implemented; (b) let a playing block show stop, so the notice yields only while playing.
**Recommendation:** (b). It is a one-line rule change in `WellTracker`.

### 2. `[[{` + newline + not-a-quote colours the `{`

**Why it matters:** For that rare layout, the colours briefly disagree with glosa-av's directive rule (Q-5).
**Recommendation:** Accept.

### 3. Supervisor-made API and behaviour choices the user did not explicitly decide

- `EscriboEmbed.Action.editAsTextID = "escribo.editAsText"` is the `⌥↩` action id.
- Backspace just after an embed, or forward-delete just before it, selects the embed first; a second press deletes it.
- Start-edge typing rule, the same on both platforms: only a newline-terminated insertion is allowed before an embed.

**Recommendation:** Confirm or adjust before 1.0. All three are public behaviour.

## Section 4: Sortie Accuracy

| Sortie | Task | Model | Attempts | Accurate? | Notes |
|--------|------|-------|----------|-----------|-------|
| 1 | Font tests | sonnet | 1 | Yes | follow-up flake → S1b |
| 1b | Font flake | sonnet | 1 | Yes (mitigation) | root cause unproven |
| 2 | iOS live check | opus | 1 | Yes | GO with caveats; drove S14/S15 design |
| 3 | JSON single-line | sonnet | 1 (+1 continuation) | Yes | planner garbled escape |
| 4 | JSON multi-line | opus | 1 | Yes | |
| 5 | JSON perf fixture | sonnet | 1 | Yes | in-note edits 21 lines vs 27 budget |
| 6 | Theme colours | sonnet | 1 | Yes | |
| 7 | Splice fix | opus | 1 (+1 continuation) | Yes | cap added on supervisor request |
| 8 | Embed API | opus | 1 | Yes | verifier PASS |
| 9 | Layout controller | opus | 1 | Yes | |
| 10 | EmbedSelection | sonnet | 1 | Mostly | edit-rule gap patched per platform |
| 11 | macOS behaviour | opus | 1 | Yes | |
| 12 | macOS a11y | sonnet | 1 | Yes | |
| 13 | macOS find hook | opus | 1 | Yes | |
| 14 | iOS behaviour | opus | 1 | Yes | |
| 15 | iOS a11y | opus | 1 | Yes | |
| 16 | Notice model | sonnet | 1 | Yes | |
| 17 | Notice overlay | sonnet | 1 | Yes | |
| 18 | Release prep | sonnet | 1 | Yes | |

## Section 5: Harvest Summary

The spike's mechanism held on real input on both platforms. The surprises were all at the edges the spike could not see: AppKit's edit-range over-report, UIKit's accessibility containment, and the gesture and key paths that skip public funnels. The single most important change for next time is to run live-device or live-AX checks as part of any sortie whose behaviour depends on UIKit or AppKit input, not only in a gate sortie. Test cleanup pruned 0 of about 150 mission tests and flagged 8: wall-clock budgets, short settle waits, and one suite that writes the system find pasteboard. No systemic flakiness pattern.

## Section 6: Files

**Preserve:**

| File | Branch | Why |
|------|--------|-----|
| `docs/missions/block-embeds/IOS_LIVE_CHECK.md` | development | live gesture/funnel evidence |
| `docs/missions/block-embeds/TEST_CLEANUP_REPORT.md` | development | flagged tests |
| `origin/mission/pressed-flower/s02-ios-live-check` | remote | paste veto on the spike (`b205e38`) |

**Discard:** none (verdict KEEP).

## Section 7: Iteration Metadata

**Starting point commit:** `42ff695` (development after the decisions PR #23)
**Mission branch:** per-sortie `mission/pressed-flower/sNN-*`
**Final commit before release:** development after PR #43 plus this post-mission PR
**Rollback target:** `42ff695`
**Next iteration branch:** `mission/pressed-flower/02` (if needed)

## Rollback Verdict

**Verdict:** `KEEP`

**Reasoning:** All 18 planned sorties and the supplementary S1b merged with green checks on their first attempt. Two continuations were planner-caused, and no sortie's output was later reverted. The go/no-go gate passed with live evidence. Test cleanup pruned nothing.

**Recommended action:** Release as the next minor version. Follow-ups: Open Decision 1 (stop vs notice), confirming the supervisor-made choices (Decision 3), dynamic iOS simulator resolution in CI if the runner flake recurs, and a long-block full-scan optimisation for embeds.
