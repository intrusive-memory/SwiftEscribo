---
type: execution-plan
title: SwiftEscribo — block embeds, notice well slot, JSON in notes
requirements: docs/missions/block-embeds/REQUIREMENTS.md
recon: docs/missions/block-embeds/RECON_REPORT.md (revision 4, CLEAR)
state: refined
updated: 2026-10-20
---

# EXECUTION_PLAN.md — SwiftEscribo block embeds

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

## Mission

Deliver `REQUIREMENTS.md` (block embeds § 1, notice well slot § 2, JSON inside notes § 3,
tests § 4) and ship it as **our next minor release version** (§ 5). Every requirement
section reference below (`§ n`) is to `docs/missions/block-embeds/REQUIREMENTS.md`.

## Ground rules for every sortie

These apply to every sortie and are part of each one's orders.

1. **Branch and PR.** Each sortie works in its own git worktree on its own branch,
   `mission/<slug>/sNN-<short-name>`, cut from the current `origin/development`
   (S2 is the one exception; see its tasks). The sortie ends with a PR to `development`,
   marked **ready** (draft PRs do not run CI), and the three required checks green:
   `SwiftLint`, `Test on macOS`, `Test on iOS Simulator`. A check that fails once is
   re-run once; a second failure is fixed or reported. The supervisor merges.
2. **Builds.** Never `swift build` / `swift test`. Use the `make` targets, raw
   `xcodebuild`, or XcodeBuildMCP. Each agent builds in its own worktree (separate
   DerivedData). Only sorties whose exit criteria name `make test-ios` run the iOS
   simulator locally; every other sortie relies on the PR's `Test on iOS Simulator` check
   for iOS, so parallel agents do not fight over one simulator.
3. **Public repo.** No private app, product or podcast names in code, comments, docs,
   commit messages or PR text. Say "the host app" / "a screenplay host".
4. **Spike code** lives only on `origin/spike/block-embeds` (`506afcf`). Read it with
   `git show origin/spike/block-embeds:<path>`. Port what a sortie needs; never merge
   that branch, and never ship anything named `Spike`/`spike` or `// SPIKE`.
5. **Recon facts are ground truth.** `RECON_REPORT.md` items marked CONFIRMED need no
   re-verification; cite them.
6. Commit messages end with the `Co-Authored-By` trailer the supervisor gives you.

## Work Units

| Work Unit | Directory | Sorties | Layer | Dependencies |
|-----------|-----------|---------|-------|-------------|
| Gate | repo root | S1, S2 | 0 | none |
| Core JSON | `Sources/EscriboCore`, `Tests/EscriboCoreTests`, `Tests/EscriboPerformanceTests`, `Sources/SwiftEscribo/BuiltInThemes.swift` | S3, S4, S5, S6 | 0 | none (S6 needs S3) |
| Embeds — shared + macOS | `Sources/SwiftEscribo`, `Tests/SwiftEscriboTests` | S7, S8, S9, S10, S11, S12, S13 | 1 | Gate (S1 merged, S2 **GO**) |
| Embeds — iOS | `Sources/SwiftEscribo`, `Tests/SwiftEscriboTests` | S14, S15 | 2 | S2 GO, S9, S10 |
| Notice well slot | `Sources/SwiftEscribo`, `Tests/SwiftEscriboTests` | S16, S17 | 2 | S8 |
| Release | repo root | S18 | 3 | every other sortie |

---

## Work Unit: Gate

### Sortie 1: Fix the flaky serif check and the font-service hang

**Entry criteria**:
- [ ] First sortie — no prerequisites. Branch `mission/<slug>/s01-font-tests` from `origin/development`.
- [ ] Read: `Sources/SwiftEscribo/FontResolver.swift` (`firstAvailable` at `:168`), `Tests/SwiftEscriboTests/FontResolutionTests.swift:141`, `Tests/SwiftEscriboTests/GeometryRuleSetTests.swift:75`, `Makefile`, `.github/workflows/tests.yml` (comment at `:22-37`), REQUIREMENTS.md *Gate in* "Flaky tests to fix first".

**Tasks**:
1. Make `FontResolutionTests.swift:141` independent of which serif fonts the machine has: assert what the resolver guarantees (it returns a font; when a serif family is installed it differs from the system family), and record the skip reason when none is installed — never a silent pass on a wrong font.
2. Remove the blocking wait from the test path: change `FontResolver` so tests that resolve named fonts do not call `NSFont(name:size:)` / `UIFont(name:size:)` for a family that is not installed (check availability first through a non-blocking API such as the font manager's / `UIFont.familyNames` lists, or cache the lookup), keeping production behaviour identical.
3. Add `-test-timeouts-enabled YES -default-test-execution-time-allowance 300` to every `xcodebuild test` invocation in `Makefile` and in `.github/workflows/tests.yml`, so a wedge fails the run instead of holding it.
4. Add a unit test that pins the resolver change (an unknown family resolves to the fallback without a named-font lookup).

**Exit criteria**:
- [ ] `make lint` exits 0.
- [ ] `make test` exits 0 three times in a row locally (record the three wall times in the PR body).
- [ ] `grep -c "test-timeouts-enabled YES" Makefile` ≥ 3 and `grep -c "test-timeouts-enabled YES" .github/workflows/tests.yml` ≥ 2.
- [ ] PR to `development` is ready and the three required checks are green.

### Sortie 2: iOS live input check on iPhone and iPad simulators (GO / NO-GO gate)

**Entry criteria**:
- [ ] First sortie — no prerequisites. Runs in parallel with S1.
- [ ] Read: the spike report (`git show origin/spike/block-embeds:docs/missions/embed-spike/SPIKE_REPORT.md`), `Sources/SwiftEscribo/Spike/IOSBlockEmbed.swift` and the iOS `// SPIKE` hooks in `Sources/SwiftEscribo/EditorInputPath.swift` on that branch, REQUIREMENTS.md *Gate in* "iOS — live input check first".

**Tasks**:
1. Create branch `mission/<slug>/s02-ios-live-check` from `origin/spike/block-embeds` (this sortie alone builds on the spike, because no production embed code exists yet).
2. Build a throwaway iOS host app **outside the repo** (in the agent's scratch directory, e.g. with XcodeBuildMCP `scaffold_ios_project`) that depends on the worktree's package by local path and shows `EscriboEditor` with one multi-line Fountain note embedded through the spike controller.
3. On an **iPhone 17 (iOS 26.5)** and on an **iPad** simulator (prefer iPad Pro 11-inch (M5); resolve by UDID from `xcrun simctl list devices available` if the name is missing), drive the real input paths with XcodeBuildMCP UI automation and record what happens for each: (a) tap on the row; (b) selection-handle drag across the row; (c) paste into the row with the block selected; (d) hardware-keyboard forward-delete with the block selected (`toggle_connect_hardware_keyboard`, `key_press`); (e) iPad pointer click and trackpad-style drag on the row; (f) the accessibility tree from `snapshot_ui` (one button element with the host label/value; activate fires the callback). Live VoiceOver speech cannot run in the Simulator; say so and use the AX tree as the proxy.
4. Implement the paste veto on this branch (iOS `paste(_:)` / `canPerformAction(_:withSender:)` with an embed selected, routed through the same edit rule as typing), add a unit test for it, and re-verify (c) live.
5. Write `docs/missions/block-embeds/IOS_LIVE_CHECK.md` (`type: report`): device, OS, each check (a)–(f) per device with PASS / FAIL / PARTIAL and the evidence (screenshot file names, AX snapshot excerpt), the paste-veto commit SHA on the spike-based branch, and a final line `VERDICT: GO` or `VERDICT: NO-GO` with the reason. **NO-GO** if UIKit's tap or selection-handle gesture puts the caret or a partial selection inside the embed and no public funnel catches it.
6. Push the spike-based branch (do not PR it). Open a PR to `development` from a second branch, `mission/<slug>/s02-ios-live-check-report`, cut from `origin/development`, that adds **only** `IOS_LIVE_CHECK.md` (and evidence PNGs under `docs/missions/block-embeds/evidence/` if any).

**Exit criteria**:
- [ ] `IOS_LIVE_CHECK.md` exists and contains rows (a)–(f) for both an iPhone and an iPad simulator, and a `VERDICT:` line.
- [ ] The spike-based branch has a commit adding the paste veto and its unit test, and `make test-ios` exits 0 on it.
- [ ] The report PR to `development` is ready, its three required checks are green, and its diff touches only `docs/`.
- [ ] **If `VERDICT: NO-GO`: the supervisor stops the mission and reports to the user.** No embed sortie (S7–S17) is dispatched.

---

## Work Unit: Core JSON

### Sortie 3: JSON span kinds, the glosa-av trigger, and single-line JSON notes

**Entry criteria**:
- [ ] First sortie of this work unit — no prerequisites. Branch from `origin/development`.
- [ ] Read: REQUIREMENTS.md § 3; `Sources/EscriboCore/GlosaScanner.swift`, `SpanKind.swift:294-331`, `FountainGrammar.swift:1024-1026`, `Tests/EscriboCoreTests/GlosaScannerTests.swift`, `KindVocabularyTests.swift`, `PublicSurfaceTests.swift`.

**Tasks**:
1. Add `SpanKind` members `glosaJSONKey`, `glosaJSONString`, `glosaJSONNumber`, `glosaJSONLiteral` next to the existing `glosa*` kinds, with doc comments; update the kind vocabulary / public-surface tests.
2. In `GlosaScanner`, scan a note's content as JSON **only** when its trimmed content matches `{`, optional whitespace, `"` (glosa-av 0.9.0 rule, § 3). Braces, brackets, colons and commas use `glosaPunctuation`. Malformed JSON stops subdividing at the first error; the rest stays `note`. Spans must still tile the range (totality rule, `GlosaScanner.swift:70-77`).
3. Tests (single-line notes): valid object with every value type; `[[{"a":"]]"}]]` escape; malformed at several points; trigger cases (`{"` and `{ "` scan as JSON; `{sic}`, `{}`, `{ 1 }` do not); existing tag-directive notes unchanged.

**Exit criteria**:
- [ ] `make test-core` exits 0, and `GlosaScannerTests` contains the trigger cases named in task 3 (`grep -c 'sic' Tests/EscriboCoreTests/GlosaScannerTests.swift` ≥ 1).
- [ ] `make lint` exits 0.
- [ ] PR ready, three required checks green.

### Sortie 4: Multi-line JSON notes across lines (`LineState`, `NestedFountainState`, incremental)

**Entry criteria**:
- [ ] Sortie 3 merged to `development`.
- [ ] Read: REQUIREMENTS.md § 3 (multi-line bullet, Q-5 bits, depth cap); `LineState.swift` (`:26`, init `:163-181`, `NestedFountainState` `:265-313`); `IncrementalScanner.swift:20-31,268-292`; `EscriboBlockGrouper.swift:198-202,278-284`; `FountainBlockGroupingTests.swift:127-137`.

**Tasks**:
1. Add to `LineState` an internal JSON-note context: note-open-no-content bit, `{`-seen-awaiting-`"` bit, in-string and escape bits, a container stack with a fixed depth cap (past it → malformed), and a key-or-value expectation. Keep `LineState` `Equatable`/`Sendable` with synthesized `==`.
2. Thread the context through the Fountain grammar so a JSON note scans correctly across lines, including `[[` alone on its line.
3. Add the same context to `NestedFountainState` (`nested(_:)` / `fountainHalf`) so fenced Fountain in Markdown scans the same.
4. Tests: multi-line valid note; string spanning the edit point; `[[` alone; depth-cap overflow → `note`; the same document inside a Markdown fence gives the same spans; incremental edit inside a JSON note equals a full rescan (use the existing incremental-vs-full oracle pattern); a standalone multi-line JSON note groups as one `.note` block.

**Exit criteria**:
- [ ] `make test-core` exits 0.
- [ ] `make test` exits 0.
- [ ] `make lint` exits 0.
- [ ] PR ready, three required checks green.

### Sortie 5: Performance fixture with multi-line JSON notes and the in-note convergence case

**Entry criteria**:
- [ ] Sortie 4 merged to `development`.
- [ ] Read: REQUIREMENTS.md § 3 (Q-3 convergence budget); `Tests/EscriboPerformanceTests/ScanBudgetTests.swift` (budgets `:150,173,180,210,250,286`; fixture guards `:82-100`); the fixture `long_screenplay.fountain`.

**Tasks**:
1. Add multi-line pretty-printed JSON notes (10–25 lines each, at least 10 of them) to the performance fixture. They contain no `` ``` `` and no `/*`.
2. Add a fixture guard that asserts the fixture contains at least 10 multi-line JSON notes.
3. Add the pathological case: an edit that opens a string or container near the top of a ≥ 20-line JSON note converges within (lines to the note's end) + 8; an unterminated `[[{"` prologue converges once the scan hits an error. Edits outside JSON notes keep ≤ 8.

**Exit criteria**:
- [ ] `make test-performance` exits 0 (run it twice; record both summaries in the PR body).
- [ ] `make lint` exits 0.
- [ ] PR ready, three required checks green.

### Sortie 6: Theme colours for every `glosa*` kind in the four built-in themes

**Entry criteria**:
- [ ] Sortie 3 merged to `development` (the new kinds exist). May run in parallel with S4/S5.
- [ ] Read: REQUIREMENTS.md § 3 (colours bullet); `Sources/SwiftEscribo/BuiltInThemes.swift` (`kindStyles` tables at `:46,88,132,175`; `source` at `:224` stays table-less); existing theme tests.

**Tasks**:
1. Add `kindStyles` entries for all eight `glosa*` kinds (four existing, four new) to each of the four language themes, using colours already in each theme's palette, readable in light and dark.
2. Add a test that iterates every `glosa*` kind × the four themes and asserts a style exists, and that `source` stays uncoloured.

**Exit criteria**:
- [ ] `make test` exits 0 and the new test is in the run.
- [ ] `make lint` exits 0.
- [ ] PR ready, three required checks green.

---

## Work Unit: Embeds — shared + macOS

### Sortie 7: macOS block-cache splice stays current on edits in multi-line blocks

**Entry criteria**:
- [ ] Sortie 1 merged; Sortie 2 reported `VERDICT: GO`.
- [ ] Read: REQUIREMENTS.md *Gate in* "macOS — the stale block cache"; `EditorCoordinator.swift:497-522,535-560`; `IncrementalScanner.swift`; `ScanResult.swift:27-104`; the spike's fallback `BlockEmbedSpike.swift:238-256` (spike branch).

**Tasks**:
1. Find out (and write down in the PR body) why the iOS path stays spliced for the same keystrokes that make the macOS splice decline.
2. Fix the macOS path so an ordinary keystroke in or above a multi-line block keeps `blocksSpanDocument == true` without a full rescan: merge the straddling edge blocks during the splice, or widen the incremental window to block edges — pick from task 1's finding.
3. Tests: typing a character above, inside and below a multi-line block (paragraph, speech, standalone note) keeps the block list equal to a full rescan's block list and `blocksSpanDocument == true`, with zero full rescans (count them).

**Exit criteria**:
- [ ] `make test` exits 0.
- [ ] `make test-performance` exits 0.
- [ ] `make lint` exits 0.
- [ ] PR ready, three required checks green.

### Sortie 8: Embed public API, `invalidateEmbeds()`, and the no-provider guarantee

**Entry criteria**:
- [ ] Sortie 2 reported `VERDICT: GO`. (Independent of S7; may run in parallel.)
- [ ] Read: REQUIREMENTS.md § 1.1, § 1.5; `EscriboEditor.swift` (init `:142-151`, `findBar` `:59`); `EscriboEditorHandle.swift`; `EscriboEditorRepresentable.swift`; `EscriboWell.swift:68-71` (the Equatable rationale); `EditorMode.swift:3-8`.

**Tasks**:
1. Add `public protocol EscriboEmbedProvider` and `public struct EscriboEmbed: Equatable, Sendable` (with `Badge` and `Action`) exactly as § 1.1 names them.
2. Add the `EscriboEditor` parameters `embedProvider`, `onEmbedActivate`, `onEmbedAction`, `onFindMatchInEmbed`, all defaulted and **after `onWellAction`**; thread them to the coordinator. `onFindMatchInEmbed` is present on iOS as a no-op.
3. Add `EscriboEditorHandle.invalidateEmbeds()` → coordinator; a detached handle ignores it. In the coordinator, keep a per-block embed answer cache filled on install/load, refreshed for the rescanned blocks on every edit, and fully refreshed on `invalidateEmbeds()`. The provider is asked in `.live` only.
4. Update the `EditorMode.swift` doc comment (a provider makes mode a code path).
5. Tests: existing call sites compile (a test that calls the old init shape, including a trailing-closure `onWellAction`); no provider → paragraph insets and layout geometry identical to today; provider call counts on load, on an edit (only rescanned blocks), and on `invalidateEmbeds()` (every block); no calls in `.source`.

**Exit criteria**:
- [ ] `make test` exits 0.
- [ ] `make lint` exits 0.
- [ ] PR ready, three required checks green.
- [ ] [judgment] Every new public symbol has a doc comment, and the new init parameters appear after `onWellAction` in declaration order.

### Sortie 9: Shared embed layout controller and the iOS delegate-forwarding type

**Entry criteria**:
- [ ] Sortie 8 merged.
- [ ] Read: REQUIREMENTS.md § 1.2, *Gate in* "Mechanism" and "iOS — accepted risk"; spike `Sources/SwiftEscribo/Spike/BlockEmbedSpike.swift` (fragment `:478,517,523,551`; delegate forwarding `:203-230`; invalidation `:311`); `Tests/SwiftEscriboTests/BlockEmbedSpikeCoreTests.swift` (spike branch).

**Tasks**:
1. Port the spike's controller as production code driven by the coordinator's embed cache (S8), not an offset registry: custom `NSTextLayoutFragment` per paragraph of an embedded block, paragraph 1 draws the row, the rest have zero height, text storage never modified, invalidation via a same-range `recordEditAction`.
2. Row height = two lines of the current font × zoom; indent = the block's; width ≤ text column; theme colours. Draws symbol, title, subtitle, badge (symbol, word, tint).
3. Put the iOS layout-manager-delegate chaining in **one** type that holds UIKit's delegate weakly and forwards everything it does not answer, plus a test that fails loudly if UIKit's delegate is missing on iOS. macOS installs as the delegate directly (slot is free, recon A-35).
5. Tests (both platforms): row height and frame, zoom, storage byte-identical, N paragraphs collapse to one row, provider returning `nil` after `invalidateEmbeds()` draws text again.

**Exit criteria**:
- [ ] `make test` exits 0 and `make test-ios` exits 0.
- [ ] `grep -rniE 'spike' Sources/` prints nothing.
- [ ] `make lint` exits 0.
- [ ] PR ready, three required checks green.

### Sortie 10: Shared embed selection and deletion rules (`EmbedSelection`)

**Entry criteria**:
- [ ] Sortie 8 merged. Runs in parallel with Sortie 9 (no shared files: pure logic plus its own test file).
- [ ] Read: REQUIREMENTS.md § 1.3; spike `SpikeEmbedSelection` in `Sources/SwiftEscribo/Spike/BlockEmbedSpike.swift` and `Tests/SwiftEscriboTests/BlockEmbedSpikeCoreTests.swift` (spike branch); `EscriboBlock.swift`.

**Tasks**:
1. Port `SpikeEmbedSelection` as an internal, platform-free `EmbedSelection` in `Sources/SwiftEscribo/EmbedSelection.swift`: constrain a proposed selection against the embedded blocks (caret never inside; step over in the direction of travel; a selection touching an embed extends to the whole block; a find-originated selection passes through unchanged); `deletionRange` (block + the following blank line, else the preceding one, else the block alone); the edit rule (an edit that inserts into or removes part of an embed is vetoed).
2. Port and extend its tests in `Tests/SwiftEscriboTests/EmbedSelectionTests.swift`, including adjacent embeds, an embed at document start and end, and the find pass-through flag.

**Exit criteria**:
- [ ] `make test` exits 0 and runs `EmbedSelectionTests`.
- [ ] `grep -rniE 'spike' Sources/` prints nothing.
- [ ] `make lint` exits 0.
- [ ] PR ready, three required checks green.

### Sortie 11: macOS embed behaviour (the behaviour table, click, `⌥↩`, undo)

**Entry criteria**:
- [ ] Sorties 7, 9 and 10 merged.
- [ ] Read: REQUIREMENTS.md § 1.3; spike `MacBlockEmbed.swift`, macOS `// SPIKE` hooks in `EditorInputPath.swift` (`:174,181,191`), `BlockEmbedSpikeMacTests.swift` (spike branch).

**Tasks**:
1. `setSelectedRanges(_:affinity:stillSelecting:)` constraint: caret never inside; arrows step over; selections that touch an embed extend to the whole block.
2. Delete/forward-delete removes block + one adjacent blank line as one undo step; `shouldChangeText` veto for typing, Return, Tab, paste; Copy writes the source.
3. Click anywhere on the row selects the whole block and calls `onEmbedActivate` once; no edge caret.
4. `⌥↩` with an embed selected calls `onEmbedAction(block, EscriboEmbed.Action.editAsTextID)`. `editAsTextID` is a public static `String` constant (`"escribo.editAsText"`) added to `EscriboEmbed.Action` in this sortie; a host that wants *Edit as Text* in the accessibility custom actions lists an `Action` with that id. Document this on the constant and on `onEmbedAction`.
5. Undo of a deleted embed restores text and embed with the block selected; redo removes it.
6. Port the spike's "typing above" test without any full-rescan fallback (asserts zero full scans, S7).

**Exit criteria**:
- [ ] `make test` exits 0; the macOS embed test suite has one test per § 1.3 behaviour (step-over, extend, delete, copy, typing veto, click-activate, `⌥↩`, undo/redo, typing-above).
- [ ] `make lint` exits 0.
- [ ] PR ready, three required checks green.

### Sortie 12: macOS embed accessibility

**Entry criteria**:
- [ ] Sortie 11 merged.
- [ ] Read: REQUIREMENTS.md § 1.4; spike macOS `accessibilityChildren` hook (`EditorInputPath.swift:199`, spike branch).

**Tasks**:
1. One `NSAccessibilityElement` per embed: button role, host label/value/identifier, frame via `NSAccessibility.screenRect(fromView:)`, press → `onEmbedActivate`, custom actions from `EscriboEmbed.actions` → `onEmbedAction`.
2. Tests: element count, role, label/value/identifier, press fires once, each custom action fires its id.

**Exit criteria**:
- [ ] `make test` exits 0 with the new tests.
- [ ] `make lint` exits 0.
- [ ] PR ready, three required checks green.

### Sortie 13: macOS find current-match hook (`onFindMatchInEmbed`)

**Entry criteria**:
- [ ] Sortie 11 merged. May run in parallel with S12.
- [ ] Read: REQUIREMENTS.md § 1.3 (Find); `MacTextView.swift:189-202`.

**Tasks**:
1. Detect a find-originated selection (the `NSTextFinder` path: `performFindPanelAction` / `performTextFinderAction` and incremental search) that lands inside an embed.
2. Call `onFindMatchInEmbed(block)`, let that selection through unsnapped, and redraw the block when the host calls `invalidateEmbeds()`.
3. Tests: a find-next whose match is inside an embed calls the callback once and keeps the match's selection; after the host stops returning the embed and invalidates, the block draws as text; a non-find selection inside an embed still snaps.

**Exit criteria**:
- [ ] `make test` exits 0 with the new tests.
- [ ] `make lint` exits 0.
- [ ] PR ready, three required checks green.

---

## Work Unit: Embeds — iOS

### Sortie 14: iOS embed behaviour (selection setters, edits, paste, forward-delete, tap, `⌥↩`, undo)

**Entry criteria**:
- [ ] Sorties 9 and 10 merged; `IOS_LIVE_CHECK.md` says `VERDICT: GO`.
- [ ] Read: REQUIREMENTS.md § 1.3; `IOS_LIVE_CHECK.md` (any hook it says the gestures need); spike `IOSBlockEmbed.swift`, iOS `// SPIKE` hooks in `EditorInputPath.swift` (`:292,353,375`), `BlockEmbedSpikeIOSTests.swift`; the S2 paste-veto commit on `mission/<slug>/s02-ios-live-check`.

**Tasks**:
1. `selectedTextRange` / `selectedRange` setter constraint (plus any extra funnel S2 found).
2. Edit veto in `insertText`, `setMarkedText`, `replace(_:withText:)`, paste; Backspace and hardware forward-delete remove block + one blank line as one undo step; copy reads the source.
3. Tap or pointer click selects the whole block and calls `onEmbedActivate` once.
4. `⌥↩` via `UIKeyCommand` calls `onEmbedAction(block, EscriboEmbed.Action.editAsTextID)` (constant from S11).
5. Undo restores text and embed with the block selected.
6. Tests: one per behaviour above, on the iOS simulator.

**Exit criteria**:
- [ ] `make test-ios` exits 0 with the new tests; `make test` exits 0.
- [ ] `make lint` exits 0.
- [ ] PR ready, three required checks green.

### Sortie 15: iOS embed accessibility

**Entry criteria**:
- [ ] Sortie 14 merged.
- [ ] Read: REQUIREMENTS.md § 1.4; spike `accessibilityElements` hook (`EditorInputPath.swift:394`, spike branch); `IOS_LIVE_CHECK.md` row (f).

**Tasks**:
1. One `UIAccessibilityElement` per embed: `.button` trait, host label/value/identifier, explicit frame conversion, `accessibilityActivate()` → `onEmbedActivate`, `accessibilityCustomActions` from `actions` (including *Edit as Text* for touch users).
2. Answer the count/index API by hand unless `IOS_LIVE_CHECK.md` row (f) shows UIKit's default is correct.
3. Tests: count, trait, label/value/identifier, activate fires once, custom actions fire their ids.

**Exit criteria**:
- [ ] `make test-ios` exits 0 with the new tests.
- [ ] `make lint` exits 0.
- [ ] PR ready, three required checks green.

---

## Work Unit: Notice well slot

### Sortie 16: Notice model and tracker (`.notice`, `wellNotice`, visibility, eligibility)

**Entry criteria**:
- [ ] Sortie 8 merged (the editor's re-ask mechanism and parameter order exist).
- [ ] Read: REQUIREMENTS.md § 2; `EscriboWell.swift` (`:16-29,46,68-71,128-132`); `WellTracker.swift` (roles `:80-89`, presentations `:213-230`, `symbolName` `:373-378`); `EscriboWellTests.swift`.

**Tasks**:
1. Add `EscriboWellItem.notice` (static member, additive).
2. Add the `EscriboEditor` parameter `wellNotice: ((EscriboBlock) -> (symbolName: String, help: String)?)? = nil` after the S8 parameters; cache answers per block alongside the embed cache (same refresh points, including `invalidateEmbeds()`).
3. Tracker: a block with a notice always presents the notice in its one slot; `.readAloud` keeps hover/caret behaviour on blocks without one; the notice's glyph comes from the callback; `.notice` is exempt from `eligibleKinds` and from the "has content" rule.
4. Tests for each rule in task 3 and for the re-ask points.

**Exit criteria**:
- [ ] `make test` exits 0 with the new tests.
- [ ] `make lint` exits 0.
- [ ] PR ready, three required checks green.

### Sortie 17: Notice drawing and click (overlay, both platforms)

**Entry criteria**:
- [ ] Sortie 16 merged.
- [ ] Read: REQUIREMENTS.md § 2; `WellOverlay.swift` (`:217,314,320-322,331,368`).

**Tasks**:
1. Overlay draws the notice glyph from the callback (no span bar), always visible, on macOS and iOS; tooltip / accessibility label = `help`.
2. Click/tap on the notice calls `onWellAction(.notice, block)`.
3. Tests: notice glyph present without hover; no span bar for a notice; click fires `onWellAction(.notice, block)` once; `eligibleKinds` exclusion still shows the notice; no `wellNotice` → well geometry unchanged.

**Exit criteria**:
- [ ] `make test` exits 0 and `make test-ios` exits 0.
- [ ] `make lint` exits 0.
- [ ] PR ready, three required checks green.

---

## Work Unit: Release

### Sortie 18: Release preparation (CHANGELOG, README, full gates)

**Entry criteria**:
- [ ] Sorties 1–17 merged to `development`.

**Tasks**:
1. CHANGELOG `[Unreleased]`: embeds, `invalidateEmbeds()`, notice slot, JSON in notes, theme colours, font-test fixes; the pin note from § 5 (hosts pinned `upToNextMinor` from any 0.x must raise their pin).
2. README / DocC-style docs for `EscriboEmbedProvider`, `EscriboEmbed`, `wellNotice`, `invalidateEmbeds()`.
3. Run `make lint`, `make test`, `make test-ios`, `make test-performance`.

**Exit criteria**:
- [ ] All four make targets exit 0.
- [ ] `grep -n "upToNextMinor" CHANGELOG.md` finds the pin note under `[Unreleased]`.
- [ ] PR ready, three required checks green.

The release itself (`ship-swift-library minor`, branch hygiene, package-collection update) is run by the supervisor after S18, not by a sortie.

---

## Priority (refine Pass 3)

Scores use `dependency_depth×3 + foundation×2 + risk + complexity×0.5`. Execution order
follows the dependency graph; within a ready set, higher scores dispatch first.

| Sortie | Priority | Why |
|--------|----------|-----|
| S2 iOS live check | 53 | Go/no-go gate for 10 embed sorties; real-input risk (4) |
| S1 font tests | 50 | Every later `make test` gate depends on it |
| S8 embed API | 35 | Foundation for S9–S17 |
| S9 layout controller | 26 | Foundation for S11–S15; private-UIKit risk |
| S10 EmbedSelection | 22 | Shared by S11 and S14 |
| S7 splice fix | 19 | Gates S11; touches the performance budget |
| S3 JSON single-line | 17 | Foundation for S4–S6 |
| S11 macOS behaviour | 14 | Unblocks S12, S13 |
| S14 iOS behaviour | 11 | Unblocks S15 |
| S4 JSON multi-line | 10 | Complex algorithm (3); unblocks S5 |
| S16 notice model | 9 | Unblocks S17 |
| S5, S6, S12, S13, S15, S17 | 4–7 | Leaves |
| S18 release prep | 3 | Last |

No reordering beyond the S9 split was needed: the plan already put the gate sorties first,
as REQUIREMENTS.md requires (font fixes and the iOS live check first; the splice fix before
any macOS embed sortie; the live check before any iOS embed sortie).

## Parallelism Structure (refine Pass 4)

**Critical path**: S2 → S8 → S9 → S11 → S13 → S18 (6 sorties); S2 → S8 → S9 → S14 → S15 → S18 is the same length.

**Parallel execution groups** (never more than 4 agents at once):
- **Group 1**: S1 (Agent 1), S2 (Agent 2), S3 (Agent 3).
- **Group 2** (after S3): S4 and S6 (S6 needs only S3).
- **Group 3** (after S1 merged and S2 GO): S7 and S8, alongside any Core JSON sortie still running.
- **Group 4** (after S8): S9, S10, S16; S5 when S4 lands.
- **Group 5** (after S9 + S10, and S7 for S11): S11, S14, S17 (after S16).
- **Group 6** (after S11): S12, S13; S15 after S14.
- **Group 7**: S18 alone.

**Agent constraints** (a deliberate deviation from the skill's "sub-agents do not build"):
every sortie here is code that must compile and pass tests, so each sortie agent builds
**in its own git worktree** (`../SwiftEscribo-wt/sNN`, separate DerivedData), which removes
the shared-build contention that rule exists to prevent. Two constraints remain:
- **iOS simulator**: only sorties whose exit criteria name `make test-ios` (S2, S9, S14, S15, S17)
  run it locally, and the supervisor never has two of them running `make test-ios` at
  once; S2's interactive simulators are separate devices from the `make test-ios` iPhone 17.
- **Performance**: `make test-performance` (S5, S7, S18) is wall-clock sensitive; the
  supervisor runs it once more itself on the merged result before S18.
- **Shared files**: S11 and S14 both edit `EditorInputPath.swift` (different `#if`
  sections); S16/S17 edit `EscriboEditor.swift` after S8. The later PR rebases on
  `development` before it is marked ready.

## Refinement log

| Pass | Result |
|------|--------|
| 1. Blocking open questions | PASS — 0 in `## Open Questions`. Fallback scan found one API gap: which action `⌥↩` invokes. Resolved as an implementation detail, not a product decision: a public constant `EscriboEmbed.Action.editAsTextID` (S11 task 4, S14 task 4). Flagged to the user in the mission report. |
| 2. Atomicity & testability | PASS — S9 (≈48 est. turns, over the 40-turn line) split: selection/deletion rules moved to a new S10. 17 → 18 sorties. Every sortie has `make` exit criteria and a green-PR criterion. |
| 3. Priority | PASS — scores above; order unchanged. |
| 4. Parallelism | PASS — 7 groups, ≤ 4 agents, worktree builds, serialized `make test-ios`. |
| 5. Vague criteria | PASS — 2 fixed: S1's "default per-test allowance" → `-default-test-execution-time-allowance 300`; the `⌥↩` id contract made explicit. No TBDs remain. |

## Local Dependency Map

<!-- Carried from RECON_REPORT.md. Sortie agents may read these paths; they may not edit them. -->

| Dependency | Resolved version | Local checkout | Status |
|------------|------------------|----------------|--------|
| swiftlang/swift-markdown (test-only) | 0.8.0 (`3c6f9523da3a`) | — | NO_LOCAL_CHECKOUT |
| swiftlang/swift-cmark (transitive, test-only) | 0.8.0 (`924936d0427c`) | — | NO_LOCAL_CHECKOUT |
| intrusive-memory/glosa-av (spec source only) | `v0.9.0` (`ac24606`) | `~/Projects/package-collection/pkg/glosa-av` | not a dependency |

## Open Questions

_No blocking open questions identified during breakdown._ The recon's Q-1 to Q-6 were
answered by the user on 2026-10-20 and are written into REQUIREMENTS.md.

## Summary

| Metric | Value |
|--------|-------|
| Work units | 6 |
| Total sorties | 18 |
| Open questions | 0 |
| Dependencies mapped | 3 |
| Dependency structure | layers |
