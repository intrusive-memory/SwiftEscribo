---
type: execution-plan
feature_name: OPERATION PHANTOM PARAGRAPH
starting_point_commit: f8318df
mission_branch: spike/block-embeds
iteration: 1
---

# EXECUTION_PLAN.md — SwiftEscribo spike: atomic block embeds on TextKit 2

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

## Mission context

- **Source**: `REQUIREMENTS.md` (this directory). **Recon**: `RECON_REPORT.md` (CLEAR, 16/16 confirmed).
- **Repository**: `/Users/stovak/Projects/package-collection/pkg/SwiftEscribo` (PUBLIC). All paths below are relative to the repo root unless absolute.
- **Branch**: every sortie commits to `spike/block-embeds` (cut from `development`). The spike branch is **never merged**. This replaces the default `mission/<slug>/<NN>` branch name — the requirements name the branch.
- **Throwaway code**: all spike source lives under `Sources/SwiftEscribo/Spike/`; all spike tests in files named `Tests/SwiftEscriboTests/BlockEmbedSpike*Tests.swift`. Small hooks into existing files (`EditorInputPath.swift`, `MacTextView.swift`, `IOSTextView.swift`) are allowed when an override or delegate assignment must live there; keep them minimal and comment them `// SPIKE`.
- **Builds/tests**: never `swift build` / `swift test`. Use `make build`, `make test`, `make test-ios`, or the targeted `xcodebuild` lines below (they are the Makefile's own invocations plus `-only-testing`).
  - macOS targeted: `xcodebuild test -scheme SwiftEscribo-Package -destination 'platform=macOS,arch=arm64' -only-testing:SwiftEscriboTests/<SuiteStruct> ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`
  - iOS targeted: `xcodebuild test -scheme SwiftEscribo-Package -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:SwiftEscriboTests/<SuiteStruct> -skipPackagePluginValidation COMPILER_INDEX_STORE_ENABLE=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`
- **Known flaky test**: `FontResolutionTests.swift:141` (serif font missing on some machines). Not this mission's to fix; record it if it fails, do not count it against a sortie.
- **Public repo hygiene**: never name a consuming application. Say "a host app".
- **Commits** end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

### Interpretations carried into the plan (not blocking; recorded so the report can state them)

| Row | Term | Interpretation used by this plan |
|---|---|---|
| 1 | "zoom scales it" | The package's own zoom input is `FontMetrics.pointSizeScale` on `EscriboStyler.environment.metrics` (`FontSpec.swift:119`, `EscriboStyler.swift:300`). The row's height, fonts and symbol scale with it. On macOS, `NSScrollView` magnification is a free second check. |
| 5 | "plus one adjacent blank line" | Remove the block's range plus the **following** blank line (the separator); when the block is the last in the document, the **preceding** blank line instead; when neither exists, the block range only. |
| 9 | "VoiceOver reads it" | Unit-testable proxy: the text view exposes one accessibility element for the embed whose label/value come from the host content and whose default action calls the host callback. A live VoiceOver pass is a manual check, recorded as such in the report. |
| 3–7 | user input | Driven in unit tests through the text view's own responder/`UITextInput` entry points (`moveRight(_:)`, `moveDown(_:)`, `moveRightAndModifySelection(_:)`, `deleteBackward(_:)`, `insertText(_:)`, `copy(_:)` / `UITextInput` position APIs, `selectedTextRange`), never by mutating storage directly. |

## Work Units

| Work Unit | Directory | Sorties | Layer | Dependencies |
|-----------|-----------|---------|-------|-------------|
| Shared | `Sources/SwiftEscribo/Spike/` | 1 | 0 | none |
| macOS | `Sources/SwiftEscribo/Spike/` (macOS files) | 3 | 1 | Shared |
| iOS | `Sources/SwiftEscribo/Spike/` (iOS files) | 3 | 2 | macOS |
| Report | `docs/missions/embed-spike/` | 1 | 3 | macOS, iOS |

## Shared

### Sortie 1: Spike scaffold — branch, embed model, pure selection/deletion logic, row-10 fixture

**Priority**: 21.5 — foundation for every later sortie (depth 7), shared pure logic reused by both platforms; low risk.

**Entry criteria**:
- [ ] First sortie — no prerequisites. Working tree clean on `development` at or after `f8318df`.
- [ ] Recon facts (no re-verification needed): `EscriboTextView` (`MacTextView.swift:32`, `IOSTextView.swift:58`) wraps `EscriboNativeTextView` (`EditorInputPath.swift:93,234`) on TextKit 2; `EscriboBlock` carries a UTF-16 range (`EscriboCore/EscriboBlock.swift`); `NSTextStorage.delegate` is taken by the coordinator and must not be touched.

**Tasks**:
1. Confirm you are on `spike/block-embeds` (the supervisor created it from `development` at `start`).
2. Create `Sources/SwiftEscribo/Spike/BlockEmbedSpike.swift` (platform-neutral, `internal`): `SpikeEmbedContent` (`symbolName`, `title`, `subtitle`, `badge`, `accessibilityLabel`, `accessibilityValue`); `SpikeEmbedRegistry` holding embeds keyed by block start offset plus an `expanded` set, with `embeddedRanges(in blocks: [EscriboBlock]) -> [NSRange]` (expanded blocks excluded).
3. In the same file, the pure logic both platforms will call: `SpikeEmbedSelection.constrain(proposed: NSRange, previous: NSRange, embeds: [NSRange]) -> NSRange` (a caret inside an embed snaps to the edge in the direction of travel; a selection that touches an embed extends to cover it whole) and `SpikeEmbedSelection.deletionRange(for embed: NSRange, in text: NSString) -> NSRange` (row 5 interpretation above).
4. Add `Tests/SwiftEscriboTests/Fixtures`-free fixture string in the test file: a Fountain document with a scene heading, an action line, a standalone **three-line** note (`[[` on the first line, `]]` on the third) followed by a blank line, and an action line after.
5. Create `Tests/SwiftEscriboTests/BlockEmbedSpikeCoreTests.swift` (suite struct `BlockEmbedSpikeCoreTests`): (a) scanning the fixture yields exactly one `.note` block whose range covers all three note lines (row 10 prerequisite, recon § Row 10); (b) ≥ 6 cases for `constrain` (caret forward/backward into embed, caret at each edge stays, extend-left/extend-right selections touching the embed, selection fully outside untouched); (c) ≥ 3 cases for `deletionRange` (middle block, last block, block with no blank neighbour).
6. Commit.

**Exit criteria**:
- [ ] `git rev-parse --abbrev-ref HEAD` prints `spike/block-embeds`.
- [ ] `make build` exits 0.
- [ ] The macOS targeted command with `-only-testing:SwiftEscriboTests/BlockEmbedSpikeCoreTests` exits 0 and its output shows ≥ 10 passing tests, including the multi-line-note-is-one-block test.
- [ ] `git log -1 --format=%B` ends with the `Co-Authored-By` line and `git status --porcelain` is empty.

## macOS

### Sortie 2: macOS draw — fixed-height row, storage untouched, multi-line collapse, zoom (rows 1, 2, 10)

**Priority**: 22.5 — highest risk in the mission (collapsing N layout fragments into one row is the hardest proof, recon handoff); 6 dependents.

**Entry criteria**:
- [ ] Sortie 1 exit criteria met; `Sources/SwiftEscribo/Spike/BlockEmbedSpike.swift` exists on `spike/block-embeds`.

**Tasks**:
1. Create `Sources/SwiftEscribo/Spike/MacBlockEmbed.swift` (`#if os(macOS)`). Install an `NSTextLayoutManagerDelegate` (free slot per recon A-07) on `EscriboTextView.textView.textLayoutManager` and return a custom `NSTextLayoutFragment` subclass for paragraphs inside an embedded block. The first paragraph's fragment draws the row (SF Symbol via `NSImage(systemSymbolName:)`, title + subtitle on two lines, trailing badge) at the paragraph's leading indent with a fixed height; the remaining N−1 paragraphs of the same block contribute zero visible height. If a custom fragment alone cannot collapse the extra height, try in order: overriding the fragment's `layoutFragmentFrame`/`renderingSurfaceBounds`; an `NSTextContentStorageDelegate` (free slot) returning a display-only `NSTextParagraph` with a collapsing paragraph style. Record which worked and why the others did not.
2. Expose a spike entry point on `EscriboTextView` (in the spike file, via extension): `spikeSetEmbed(_ content: SpikeEmbedContent?, forBlockStartingAt offset: Int)` that updates the registry and invalidates layout for that range only.
3. Create `Tests/SwiftEscriboTests/BlockEmbedSpikeMacTests.swift` (suite struct `BlockEmbedSpikeMacTests`, `#if os(macOS)`, `@MainActor`), building a real `EscriboTextView(language: .fountain, …)` with the Sortie 1 fixture, sized in a frame, with `ensureLayout` over the document. Assert: (row 1) the embed's first fragment is the custom class and its frame height equals the configured row height (± 0.5 pt); fragments before/after the block keep their non-embed heights and are positioned contiguously; with `pointSizeScale = 2` the row height scales (> 1.5× baseline); (row 2) `textStorage.string` is byte-identical with and without the embed and the coordinator's word count / `string` `range(of:)` find of a note word still succeeds; (row 10) the three note paragraphs together occupy exactly one row height.
4. Commit.

**Exit criteria**:
- [ ] `make build` exits 0.
- [ ] macOS targeted command with `-only-testing:SwiftEscriboTests/BlockEmbedSpikeMacTests` exits 0; the output names a passing test for each of rows 1, 2, 10 (test display names include `row 1`, `row 2`, `row 10`).
- [ ] `git diff development --stat -- Sources/SwiftEscribo/EditorCoordinator.swift Sources/SwiftEscribo/NSTextStorageBridge.swift` is empty (storage pipeline untouched).
- [ ] The commit message body names the collapse mechanism that worked.

### Sortie 3: macOS atomic behaviour — caret step-over, select whole, delete whole, copy source, typing ignored (rows 3–7)

**Priority**: 20 — selection constraint pattern reused by iOS; new technique; 5 dependents.

**Entry criteria**:
- [ ] Sortie 2 exit criteria met; `BlockEmbedSpikeMacTests` green.

**Tasks**:
1. In `EscriboNativeTextView` (macOS, `EditorInputPath.swift`) add a `// SPIKE` hook — an override of `setSelectedRanges(_:affinity:stillSelecting:)` that routes through an optional `spikeSelectionFilter` closure — and wire it from `MacBlockEmbed.swift` to `SpikeEmbedSelection.constrain`. (Subclass, not `NSTextViewDelegate`: the delegate slot belongs to `EscriboEditorBridge` and exists only under SwiftUI — recon A-04/A-06.)
2. Delete/Backspace/forward-delete with an embed exactly selected removes `SpikeEmbedSelection.deletionRange` through `shouldChangeText(in:replacementString:)` / `replaceCharacters` / `didChangeText()` as one undo group.
3. Copy with an embed selected writes the original characters (default `NSTextView` copy of the storage range is acceptable if it already does so — prove it).
4. Typing (`insertText(_:replacementRange:)`) with an embed in the selection changes nothing.
5. Add tests to `BlockEmbedSpikeMacTests` (display names include the row number): (row 3) `moveRight`/`moveLeft` from the block's edges and `moveUp`/`moveDown` from the lines above/below never yield a selection location strictly inside the block; a click via `characterIndexForInsertion(at:)` + `setSelectedRange` inside the row lands on an edge; (row 4) `moveRightAndModifySelection`/`moveLeftAndModifySelection` across the block and a `setSelectedRange(_:affinity:stillSelecting: true)` drag that touches it extend to the full range; (row 5) `deleteBackward(nil)` with the block selected removes exactly `deletionRange`, and one `undoManager.undo()` restores the original string byte-for-byte; (row 6) `writeSelection(to:types:)` on a private `NSPasteboard(name:)` yields the original characters; (row 7) `insertText("x", replacementRange:)` with the block selected leaves `string` unchanged.
6. Commit.

**Exit criteria**:
- [ ] `make build` exits 0.
- [ ] macOS targeted `-only-testing:SwiftEscriboTests/BlockEmbedSpikeMacTests` exits 0 with passing tests whose names include `row 3`, `row 4`, `row 5`, `row 6`, `row 7`; any row that cannot pass is instead a test marked `withKnownIssue` with the observed failure, and the sortie report lists it.
- [ ] `make test` exits 0, or its only failures are `FontResolutionTests.swift:141`.

### Sortie 4: macOS expand/collapse, accessibility, scroll/edit stability, screenshot evidence (rows 8, 9, 11)

**Priority**: 15.5 — completes the macOS column; 4 dependents.

**Entry criteria**:
- [ ] Sortie 3 exit criteria met.

**Tasks**:
1. `spikeSetExpanded(_:forBlockStartingAt:)` toggles the registry's expanded set and invalidates layout; while expanded the block draws as ordinary text and the selection filter lets the caret in.
2. Expose one accessibility element per visible embed from the text view (`NSAccessibilityElement` child, role button or group, label = title, value = subtitle + badge, `accessibilityPerformPress` → an `onSpikeEmbedActivate` callback), frame = row rect in screen coordinates.
3. Add tests (names include the row number): (row 8) expand → caret can be placed inside and the block's first fragment is no longer the custom class; collapse → custom class returns and caret snaps again; (row 9) exactly one accessibility element per embed with the expected label/value, and performing press fires the callback once; (row 11) insert 20 characters one at a time on a line above the block and scroll the view (`scroll(_:)` the clip view to the bottom and back) — after each step the embed's first fragment is still the custom class with the fixed height, and the number of custom-fragment creations is ≤ 2 per edit (instrument with a counter).
4. Screenshot evidence: a test that, only when the environment variable `ESCRIBO_SPIKE_EVIDENCE_DIR` is set (pass it as `TEST_RUNNER_ESCRIBO_SPIKE_EVIDENCE_DIR=<abs path>` on the xcodebuild line), renders the scroll view with `cacheDisplay(in:to:)` to `mac-embed-collapsed.png`, `mac-embed-expanded.png`, `mac-embed-zoom2x.png` in that directory; without the variable it does nothing and passes.
5. Run the evidence test once with the variable set to `<repo>/docs/missions/embed-spike/evidence`; commit the PNGs and the code.

**Exit criteria**:
- [ ] macOS targeted `-only-testing:SwiftEscriboTests/BlockEmbedSpikeMacTests` exits 0 with passing tests whose names include `row 8`, `row 9`, `row 11` (or `withKnownIssue` with the observed failure, listed in the report).
- [ ] `ls docs/missions/embed-spike/evidence/mac-embed-*.png | wc -l` prints `3`, and each file is > 1 KB.
- [ ] `make test` exits 0, or its only failures are `FontResolutionTests.swift:141`.
- [ ] [judgment] Opening `mac-embed-collapsed.png` shows the note as a single row with a symbol, two text lines and a trailing badge, and the surrounding scene heading and action lines laid out normally.

## iOS

### Sortie 5: iOS draw — fixed-height row, storage untouched, multi-line collapse, zoom (rows 1, 2, 10)

**Priority**: 14.5 — iOS draw, informed by Sortie 2; 3 dependents.

**Entry criteria**:
- [ ] Sortie 4 exit criteria met. Read the Sortie 2 commit message and `MacBlockEmbed.swift` for the mechanism that worked on macOS.
- [ ] `xcrun simctl list devices available | grep "iPhone 17"` shows an iPhone 17 on iOS 26.5.

**Tasks**:
1. Create `Sources/SwiftEscribo/Spike/IOSBlockEmbed.swift` (`#if os(iOS)`), mirroring Sortie 2 on `UITextView`'s `textLayoutManager` (SF Symbol via `UIImage(systemName:)`). Same fallback order for collapsing N−1 paragraphs; record what worked.
2. `spikeSetEmbed` on the iOS `EscriboTextView`, same signature as macOS.
3. Create `Tests/SwiftEscriboTests/BlockEmbedSpikeIOSTests.swift` (suite struct `BlockEmbedSpikeIOSTests`, `#if os(iOS)`, `@MainActor`) with the row 1, 2, 10 assertions of Sortie 2, adapted to UIKit.
4. Commit.

**Exit criteria**:
- [ ] iOS targeted command with `-only-testing:SwiftEscriboTests/BlockEmbedSpikeIOSTests` exits 0 with passing tests whose names include `row 1`, `row 2`, `row 10`.
- [ ] `make build` (macOS) still exits 0.
- [ ] The commit message body names the collapse mechanism that worked on iOS.

### Sortie 6: iOS atomic behaviour — rows 3–7

**Priority**: 12.5 — iOS selection differs most from macOS (UITextInput); 2 dependents.

**Entry criteria**:
- [ ] Sortie 5 exit criteria met.

**Tasks**:
1. In `EscriboNativeTextView` (iOS, `EditorInputPath.swift`) add a `// SPIKE` hook constraining selection — override the `selectedTextRange` setter (and, if hardware-keyboard arrows bypass it, `UITextInput` movement or `UIKeyCommand` handling) — routed to `SpikeEmbedSelection.constrain`. Not the bridge's `textViewDidChangeSelection`: it exists only under SwiftUI (recon A-04/A-05).
2. `deleteBackward()` with an embed selected removes `deletionRange` as one undo step; `insertText(_:)` with an embed in the selection changes nothing (extend the existing override; keep Return/Tab handlers working).
3. Copy with the block selected yields the original characters (use a named `UIPasteboard` or assert the `copy(_:)` path's string).
4. Tests in `BlockEmbedSpikeIOSTests`, names including the row number, mirroring Sortie 3: row 3 via `position(from:in:offset:)` + setting `selectedTextRange` for left/right/up/down and via `closestPosition(to:)` for a tap; row 4 via extending ranges that touch the block; rows 5–7 as on macOS.
5. Commit.

**Exit criteria**:
- [ ] iOS targeted `-only-testing:SwiftEscriboTests/BlockEmbedSpikeIOSTests` exits 0 with passing tests whose names include `row 3` … `row 7` (or `withKnownIssue` with the observed failure, listed in the report).
- [ ] `make test-ios` exits 0, or its only failures are `FontResolutionTests.swift:141`.

### Sortie 7: iOS expand/collapse, accessibility, scroll/edit stability, screenshot evidence (rows 8, 9, 11)

**Priority**: 8.5 — completes the iOS column; 1 dependent.

**Entry criteria**:
- [ ] Sortie 6 exit criteria met.

**Tasks**:
1. `spikeSetExpanded` on iOS, as Sortie 4 task 1.
2. Accessibility: one `UIAccessibilityElement` per visible embed in the text view's accessibility elements (trait `.button`, label/value from the content, `accessibilityActivate()` → `onSpikeEmbedActivate`).
3. Tests (names include the row number) for rows 8, 9, 11 as in Sortie 4, using `setContentOffset` for scroll.
4. Evidence test, gated on `ESCRIBO_SPIKE_EVIDENCE_DIR` exactly as Sortie 4, rendering with `UIGraphicsImageRenderer` (text view hosted in a `UIWindow`) to `ios-embed-collapsed.png`, `ios-embed-expanded.png`, `ios-embed-zoom2x.png`. The simulator shares the host filesystem, so an absolute repo path works.
5. Run it once with the variable set; commit PNGs and code.

**Exit criteria**:
- [ ] iOS targeted `-only-testing:SwiftEscriboTests/BlockEmbedSpikeIOSTests` exits 0 with passing tests whose names include `row 8`, `row 9`, `row 11` (or `withKnownIssue`, listed).
- [ ] `ls docs/missions/embed-spike/evidence/ios-embed-*.png | wc -l` prints `3`, each > 1 KB.
- [ ] `make test-ios` exits 0, or its only failures are `FontResolutionTests.swift:141`.
- [ ] [judgment] Opening `ios-embed-collapsed.png` shows the note as a single row with a symbol, two text lines and a trailing badge, with the surrounding lines laid out normally.

## Report

### Sortie 8: Evidence run and SPIKE_REPORT.md

**Priority**: 3 — leaf; documentation from evidence.

**Entry criteria**:
- [ ] Sorties 1–7 complete; all spike commits pushed or pushable on `spike/block-embeds`.

**Tasks**:
1. Run `make test` and `make test-ios` on `spike/block-embeds`; save the `BlockEmbedSpike*` lines of each run's output (pass/fail/known-issue per test) for the report.
2. Write `docs/missions/embed-spike/SPIKE_REPORT.md` (frontmatter `type: report`, `kind: spike`, `state: complete`): per platform — mechanism (draw, collapse, selection constraint, delete/typing/copy, a11y); a table of rows 1–11 with PASS / PARTIAL / FAIL and the evidence (test name + result line, PNG path); the four interpretations from this plan; known limitations (including what unit tests cannot prove: live VoiceOver, real hardware-keyboard/trackpad input, drag in a live window); an estimate for the release mission (`docs/missions/block-embeds/REQUIREMENTS.md`) in sorties; and a **recommended** go / no-go per platform, labelled as a recommendation for the user to accept.
3. Commit the report on `spike/block-embeds`.

**Exit criteria**:
- [ ] `docs/missions/embed-spike/SPIKE_REPORT.md` exists and `grep -cE '^\| *([1-9]|1[01]) *\|' docs/missions/embed-spike/SPIKE_REPORT.md` prints ≥ 22 (11 behaviour rows per platform).
- [ ] `grep -ci "go / no-go\|no-go" docs/missions/embed-spike/SPIKE_REPORT.md` ≥ 2.
- [ ] `grep -niE "escribir|vinetas|produciesta|granville" docs/missions/embed-spike/SPIKE_REPORT.md` prints nothing.
- [ ] [judgment] Every PASS in the report cites a specific test name or evidence file that exists on the branch.

## Parallelism Structure

**Critical Path**: Sortie 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 (8 sorties, fully sequential).

**Why no parallel groups**: the iOS column (5–7) could in principle start after Sortie 1, but it is deliberately serialised behind macOS: (a) both columns edit `EditorInputPath.swift` and `Sources/SwiftEscribo/Spike/`, (b) concurrent `xcodebuild` runs of the same package contend for one DerivedData directory, and (c) the iOS sorties reuse the mechanism macOS proves first, which is cheaper than discovering it twice.

**Agent Constraints**:
- **Supervising agent**: dispatches one sortie agent at a time; every sortie has build/test steps, so every sortie runs alone (one build at a time on this machine).
- **Sub-agents**: none run concurrently. Independent verifier agents (for `[judgment]` criteria in Sorties 4, 7, 8) do no builds.

## Local Dependency Map

<!-- Carried from RECON_REPORT.md. Sortie agents may read these paths; they may not edit them. -->

| Dependency | Resolved version | Local checkout | Status |
|------------|------------------|----------------|--------|
| swiftlang/swift-markdown | 0.8.0 (`3c6f9523da3a`) | — | NO_LOCAL_CHECKOUT (EscriboCoreTests only) |
| swiftlang/swift-cmark (transitive) | 0.8.0 (`924936d0427c`) | — | NO_LOCAL_CHECKOUT |

No sortie reads dependency source.

## Open Questions

_No blocking open questions identified during breakdown._

## Summary

| Metric | Value |
|--------|-------|
| Work units | 4 |
| Total sorties | 8 |
| Open questions | 0 |
| Dependencies mapped | 2 |
| Dependency structure | layers (Shared → macOS → iOS → Report) |
