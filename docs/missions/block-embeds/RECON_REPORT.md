---
type: recon-report
state: current
requirements_file: REQUIREMENTS.md
requirements_sha256: bf8c20106ee729dd2b95aa5d67d2d0d719acb9aedc0f253446b20f347b524b61
project_head: d1abe982f2f5a1c1da4971989f9df3ee4e8883c3
spike_head: 506afcf (origin/spike/block-embeds)
search_root: ~/Projects
generated: 2026-10-20
verdict: CLEAR
---

# Recon Report: block embeds, notice well slot, JSON in notes (revision 3)

## Terminology

> **Mission**: a definable, testable scope of work.
> **Sortie**: an atomic, testable unit of work that one agent executes in one dispatch.
> **Work Unit**: a grouping of sorties.

## Verdict

**CLEAR.** 36 assumptions checked. All hold or were factual slips now corrected. 0 blocking, 0 unverifiable.

- **False premises (hard stop): 0.**
- **Fix-in-requirements: 6.** Five are factual and were corrected in `REQUIREMENTS.md` in
  the same commit as this report (F-1 to F-5). One is a design gap, listed as question Q-1.
- **Notes: 12** (N-1 to N-12), for breakdown. Five of them carry a question (Q-2 to Q-6).

What changed since revision 2 (BLOCKED):

| Revision 2 | Now |
|---|---|
| A-28: embed spike not run | Resolved. `SPIKE_REPORT.md` (go on both platforms) is on `development`, and the requirements' *Gate in* section records the user's acceptance and conditions. The mechanism claims were checked against the spike branch's code (A-31 to A-34). |
| A-17: note grouping described wrongly | Resolved. § 3 now says a note between lines of one block is absorbed into it, and a standalone note is its own `.note` block. |
| A-29: glosa-av 0.9.0 unreleased | Resolved. `v0.9.0` is tagged (`ac24606`, "GLOSA notation 2.0 (JSON block directives)"). N-10 covers one difference in the detection rule. |
| N-1 (notice data path), N-2 (`NestedFountainState`), N-3 (perf fixture) | Now requirements (§ 2, § 3). |

Method: hub-only, read-only checks against `development` at `d1abe98` and the spike branch at
`506afcf`. `Sources/` and `Tests/` are byte-identical to revision 2's `16d03e0`:
`git diff --stat 16d03e0 d1abe98` touches only `docs/missions/`. Revision 2's confirmed code
facts therefore carry over, and they were spot-checked again. Nothing was built, resolved, or
run.

Scope: everything the document asks to *add* is a deliverable, not an assumption. That
covers the embed API, the editor parameters, the find-bar hook, `.notice`,
`wellNotice(for:)`, the JSON span kinds, the new line-state context, the theme colours, the
incremental block-range fix, the iOS delegate-forwarding type, and the CHANGELOG entry.

## Assumption Findings

| ID | Kind | Claim | Verdict | Evidence |
|----|------|-------|---------|----------|
| A-01 | A-API | `EscriboWell` is `Equatable, Sendable` | CONFIRMED | `Sources/SwiftEscribo/EscriboWell.swift:71` |
| A-02 | A-INVARIANT | `EscriboWellItem` is a struct with static members, so adding one is minor | CONFIRMED | `EscriboWell.swift:16-29`, `.readAloud` at `:46` |
| A-03 | A-API | `onWellAction` can carry a click on a new slot | CONFIRMED | `EscriboEditor.swift:73,151`: `(EscriboWellItem, EscriboBlock) -> Void` |
| A-04 | A-API | New defaulted `EscriboEditor` parameters leave call sites compiling | CONFIRMED | `EscriboEditor.swift:142-151`. Every parameter after `language` has a default, and `onWellAction` is last (N-5) |
| A-05 | A-API | `EditorMode.live` / `.source` exist | CONFIRMED | `EditorMode.swift:11,22,27` |
| A-06 | A-BEHAVIOR | `EscriboBlock.ID` is not stable across edits (`EscriboBlock.swift:26–33`) | CONFIRMED | `EscriboBlock.swift:26-33` |
| A-07 | A-API | `EscriboColor` is `Sendable` and usable in an `Equatable` struct | CONFIRMED | `EscriboColor.swift:27` (`Hashable, Sendable`) |
| A-08 | A-API | The GLOSA span kinds are at `SpanKind.swift:294–331` | CONFIRMED | `SpanKind.swift:294` (MARK) to `:331` (`glosaPunctuation`) |
| A-09 | A-BEHAVIOR | `GlosaScanner` has no cross-line state (`GlosaScanner.swift:60–68`, `FountainGrammar.swift:1024`) | CONFIRMED; citation fixed (F-4) | The prose is at `GlosaScanner.swift:60-68`. The call spans `FountainGrammar.swift:1024-1026` (`if kind == .note` → `GlosaScanner.scan`) |
| A-10 | A-INVARIANT | Totality: spans tile the range, with no throw and no trap | CONFIRMED | `GlosaScanner.swift:70-77` |
| A-11 | A-API | `LineState` exists and can gain internal fields | CONFIRMED | `LineState.swift:26` (`Equatable, Sendable`, synthesized `==`); defaulted memberwise `init` at `:163-181` |
| A-12 | A-BEHAVIOR | Incremental rescans continue until line states match again | CONFIRMED | `IncrementalScanner.swift:20-31`, `:268-292` |
| A-13 | A-API | `NestedFountainState` carries the Fountain half of the state inside a fence | CONFIRMED | `LineState.swift:265-313`: fields `openConstruct`, `followsNonBlankLine`, `inDialogueBlock`, `titlePage`; helpers `nested(_:)` and `fountainHalf` |
| A-14 | A-CONFIG | `make test-performance` exists, with budgets of 50 ms / 1 ms / ≤ 8 lines | CONFIRMED | `Makefile:61-67`; `ScanBudgetTests.swift:150,173,180,210,250,286` |
| A-15 | A-DATA | The perf fixture has no multi-line JSON notes | CONFIRMED | `long_screenplay.fountain` has 300 `[[` notes and none matching `[[ *{` |
| A-16 | A-BEHAVIOR | A standalone note is one `.note` block, and a bridging note is absorbed (`FountainBlockGroupingTests.swift:131–137`) | CONFIRMED; citation fixed (F-5) | The bridging case is `FountainBlockGroupingTests.swift:127-130` and the standalone case is `:131-137`. Grouper: `EscriboBlockGrouper.swift:198-202,278-284` |
| A-17 | A-BEHAVIOR | No built-in theme colours `glosa*` or `.note` | CONFIRMED | No `kindStyles` table in `BuiltInThemes.swift` has such a key (`:140-165` and the other three). A grep for `glosa` and `\.note` in `BuiltInThemes.swift`, `EscriboStyler.swift`, and `EscriboTheme.swift` finds nothing. The four language themes are at `:46,88,132,175`. `source` (`:224`) has no tables, by design |
| A-18 | A-BEHAVIOR | The find bar is macOS-only, is AppKit's built-in bar, and has no current-match hook | CONFIRMED | `MacTextView.swift:189-202` (`usesFindBar`, `isIncrementalSearchingEnabled`). `Sources/` has no `NSTextFinder` subclass, client, or delegate. `EscriboEditor.swift:59`: "macOS only; a no-op on iOS" |
| A-19 | A-BEHAVIOR | Well slots show only on hover or for the caret's block (plus playing and finished) | CONFIRMED | Roles at `WellTracker.swift:80-89`; presentations at `:213-230` |
| A-20 | A-BEHAVIOR | Slot glyphs are hard-coded | CONFIRMED | `WellPlacement.symbolName`, `WellTracker.swift:373-378`: `.readAloud` only, `default: return nil` |
| A-21 | A-BEHAVIOR | "today's item filtering would drop `.notice`; it is exempt from the `eligibleKinds` filter" | Effect CONFIRMED, cause misattributed; fixed (F-3) | The **glyph** filter drops `.notice` (`WellOverlay.swift:320-322`), not `eligibleKinds`. `eligibleKinds` filters **blocks**, not items (`EscriboWell.swift:128-132`, applied at `WellOverlay.swift:217,314,368`). See Q-4 |
| A-22 | A-FILE | There is no UI test target and no snapshot setup | CONFIRMED | `Tests/` holds `EscriboCoreTests`, `EscriboPerformanceTests`, `EscriboProjectTests`, `SwiftEscriboTests` |
| A-23 | A-BEHAVIOR | § 1.5: "the existing UI tests pass untouched" | Contradicts A-22; fixed (F-2) | No UI tests exist. The text now reads "the existing tests pass untouched (the package has no UI test target)" |
| A-24 | A-FILE | `SwiftEscriboTests` has inset and geometry tests to model on | CONFIRMED | `ParagraphGeometryTests.swift`, `MacTextViewTests.swift`, `IOSTextViewTests.swift`, `EscriboWellTests.swift` |
| A-25 | A-CONFIG | `make lint`, `make test`, and `make test-ios` exist | CONFIRMED | `Makefile:103,29,43`. `swiftlint` is on PATH. `test-ios` pins `iPhone 17, OS=26.5` (`Makefile:17`), and the 26.5 runtime is installed locally |
| A-26 | A-BEHAVIOR | `FontResolutionTests.swift:141` is the flaky serif check | CONFIRMED | `FontResolutionTests.swift:141`: `#expect(serif.familyName != system.familyName)` |
| A-27 | A-BEHAVIOR | "a font test that hangs waiting on the system font service" | CONFIRMED; now named (F-1) | Spike report: `GeometryRuleSetTests.swift:75` hung for 29 min in `FontResolver.firstAvailable` (`FontResolver.swift:168`) → `NSFont(name:size:)`. The CI workflow records three such wedges (`.github/workflows/tests.yml:22-37`) |
| A-28 | A-CONFIG | The next minor release is `0.5.0` | CONFIRMED | Latest tag is `v0.4.5`; `CHANGELOG.md:13` has `[Unreleased]` |
| A-29 | A-INVARIANT | `upToNextMinor` pins from 0.3.x and 0.4.x exist downstream | CONFIRMED | One host package pins `.upToNextMinor(from: "0.3.0")`. One host Xcode project pins `upToNextMinorVersion`, minimum `0.4.4` |
| A-30 | A-DEP | glosa-av 0.9.0 defines JSON block directives in notes | CONFIRMED | glosa-av `v0.9.0` (`ac24606`): `CHANGELOG.md:23`, `AGENTS.md:35`. glosa-av is not a SwiftEscribo dependency. See N-10 |
| A-31 | A-BEHAVIOR | Spike mechanism: a custom layout fragment; paragraph 1 is the row and the rest have zero height; storage is never modified | CONFIRMED (spike) | `spike/block-embeds:Sources/SwiftEscribo/Spike/BlockEmbedSpike.swift:478` (`textLayoutManager(_:textLayoutFragmentFor:in:)`); `:517,523` (`layoutFragmentFrame` and `renderingSurfaceBounds` overrides); `:551`. Invalidation goes through `recordEditAction` on the content storage (`:311`) |
| A-32 | A-BEHAVIOR | On iOS, UIKit occupies the layout-manager delegate, and the spike forwards to it | CONFIRMED (spike) | `BlockEmbedSpike.swift:203-230`: weak `forwardedLayoutDelegate` (`:212`), `responds(to:)`, `forwardingTarget(for:)` |
| A-33 | A-BEHAVIOR | The macOS selection hook is `setSelectedRanges(_:affinity:stillSelecting:)`; the iOS hooks are the `selectedTextRange` and `selectedRange` setters | CONFIRMED (spike) | `spike/block-embeds:Sources/SwiftEscribo/EditorInputPath.swift:174` (macOS), `:353,375` (iOS). Also `shouldChangeText` (`:181`), `deleteForward` (`:191`), `accessibilityChildren` (`:199`), `insertText` (`:292`), `accessibilityElements` (`:394`). There is no `paste` override, so iOS paste is not blocked, as the gate says |
| A-34 | A-BEHAVIOR | The macOS block cache goes stale when typing above an embed, and a fix "from the scanner's edit results" is feasible | CONFIRMED | The coordinator already splices incremental results (`EditorCoordinator.swift:497-522`). The splice declines when a cached block straddles the rescanned window (`:540-560`, returns `nil`), which leaves `blocksSpanDocument == false`. The spike then fell back to a full rescan (`BlockEmbedSpike.swift:238-256`). `ScanResult` carries `blocks`, `dirtyRange`, `lines`, and `documentLineCount` (`ScanResult.swift:27-104`). See N-7 |
| A-35 | A-CONFIG | The package installs no TextKit 2 delegate of its own today | CONFIRMED | The only delegates it sets are `textView.delegate` (`EscriboEditorRepresentable.swift:121`) and the storage delegate (`NSTextStorageBridge.swift:153`) |
| A-36 | A-CONFIG | `development` is protected by the three CI checks | CONFIRMED | Required, non-strict: `SwiftLint`, `Test on macOS`, `Test on iOS Simulator`. The suite skips draft PRs (`tests.yml:7-19`) |

## Fix-in-requirements

Corrected in `REQUIREMENTS.md`. These are factual fixes only; no design changed.

- **F-1** (A-27): names the hanging test, `GeometryRuleSetTests.swift:75`, and the call it waits in.
- **F-2** (A-23): § 1.5 now says "existing tests (the package has no UI test target)" instead of "existing UI tests".
- **F-3** (A-21): § 2 eligibility now names the filter that actually drops `.notice` (the
  glyph filter). It keeps the stated exemption from the block-level `eligibleKinds` filter.
- **F-4** (A-09): `FountainGrammar.swift:1024` → `:1024–1026`.
- **F-5** (A-16): `FountainBlockGroupingTests.swift:131–137` → `:127–137`, because the absorbed case is at `:127-130`.

Not corrected, because it is a design decision for the user:

- **Q-1. When does the editor ask the provider again?** The requirements say how a host
  answers (`embed(for:in:)`, `wellNotice(for:)`) but not when the editor asks. Two features
  depend on the answer changing with no text edit. *Edit as Text* works by the provider
  starting to return `nil`. Find works by the host then stopping its embed. The editor
  needs a trigger for both, and SwiftUI cannot supply one: `any EscriboEmbedProvider` is
  not `Equatable`, so an update cannot show that anything changed. Options:
  - (a) Re-ask for every visible block on every SwiftUI update. Simple, but one provider
    call per block per update.
  - (b) An explicit `EscriboEditorHandle.invalidateEmbeds()` call (whole document or one
    block) that the host makes.
  - (c) An `embedRevision: Int` token parameter that the host bumps.

  *Recommendation: (b), plus re-asking for the blocks inside each edit's rescanned window.*
  The same answer should apply to `wellNotice(for:)`.

## Notes (for breakdown)

- **N-1. Where does `wellNotice(for:)` live?** (→ Q-2) `EscriboWell` must stay `Equatable`
  (`EscriboWell.swift:68-71`), so it cannot hold a closure. The callback fits as an
  `EscriboEditor` parameter (defaulted to `nil`, placed after `onWellAction`, see N-5) or
  as a second method on a provider protocol. *Recommendation: an `EscriboEditor` parameter.*
- **N-2. Multi-line JSON breaks the "uniform state" argument behind ≤ 8 lines.** (→ Q-3)
  The existing budgets hold for unterminated fences and boneyards because the carried
  state is the same on every line inside them (see the pathological cases in
  `ScanBudgetTests.swift`, comment around `:246-250`). Inside a JSON note the state differs
  from line to line: the container stack and the key/value expectation change. Typing `{`
  or `"` near the top of an N-line JSON note changes the end state of every later line in
  that note, so the rescan runs to the note's end: N lines, not ≤ 8.
  - The worst case is bounded by note length. The rescan converges at the closing `]]`,
    and an error state is uniform (the rest of the note is plain `note`).
  - An unterminated `[[{` prologue still converges once the scan hits an error.
  - A pretty-printed shot directive is probably 10–25 lines.

  *Question: does ≤ 8 lines apply to edits inside a JSON note, or is the bound "to the
  note's end + 8"?* Recommended: the second, pinned by a new pathological case.
- **N-3. Notice layout and eligibility details.** (→ Q-4) The exemption from
  `eligibleKinds` is stated. Three details are still open:
  - (a) Does the exemption also skip `isEligible`'s "block has content" rule
    (`EscriboWell.swift:129`)?
  - (b) On an eligible block, does the always-visible notice share one slot with
    `.readAloud`, which still appears only on hover or caret?
  - (c) Does an always-visible notice draw the span bar (`WellOverlay.swift:331`), or only
    its glyph?

  *Recommendation: (a) yes, skip it; (b) one slot, with the notice always shown and
  `.readAloud` on hover or caret as today; (c) glyph only.*
- **N-4. Find versus the selection rule (macOS).** `NSTextFinder` reports a match only by
  setting the selection. The selection filter (the spike's `setSelectedRanges` override)
  would snap that selection to the whole block before the host can stop returning an
  embed. The find-hook sortie must:
  1. Detect a find-originated selection.
  2. Call `onFindMatchInEmbed`.
  3. Let the selection through unsnapped, and rely on Q-1's trigger for the redraw.
- **N-5. Add the new closures after `onWellAction`.** It is the last parameter today
  (`EscriboEditor.swift:151`), and inserting parameters before it could change which one a
  trailing closure binds to. The macOS-only `onFindMatchInEmbed` should follow `findBar`'s
  pattern rather than use `#if`: present on both platforms, a no-op on iOS
  (`EscriboEditor.swift:59`).
- **N-6. `EditorMode` doc comment.** `EditorMode.swift:3-8` says that switching modes "is
  not a code path". A provider that is asked only in `.live` makes it one, so the comment
  must change.
- **N-7. The macOS block-cache fix is a coordinator change, not an embed change.** The
  splice declines whenever a cached block straddles the rescanned window
  (`EditorCoordinator.swift:540-560`), and an ordinary keystroke in a multi-line block
  causes exactly that. There are two routes:
  - Widen the incremental window to whole-block edges in `IncrementalScanner`. This
    touches the ≤ 8-line convergence budget, so the sortie must run `make test-performance`.
  - Merge the straddling edge blocks during the splice.

  The spike measured that iOS stayed spliced for the same keystrokes. The sortie should
  find out why the two paths differ before it picks a route.
- **N-8. A test-level timeout cannot stop the font hang.** The hang is a synchronous XPC
  wait inside `NSFont(name:size:)`. Swift Testing's `.timeLimit` records a failure but
  cannot interrupt a blocked thread. CI already caps the job at 30 minutes
  (`tests.yml:37`). The fix sortie needs a resolver that avoids the blocking call under
  test, an `xcodebuild -test-timeouts-enabled YES` setting in the `Makefile`, or both.
- **N-9. Run the iOS live check on an iPad as well.** `make test-ios` and the spike both
  used an iPhone 17 simulator. The host app is iPad-only, and iPad users often have a
  hardware keyboard and a pointer. Pointer clicks and trackpad drags are one more input
  path to verify.
- **N-10. The JSON trigger is broader than glosa-av's.** (→ Q-5) The requirement scans a
  note as JSON when its trimmed content starts with `{`. glosa-av 0.9.0 treats a note as a
  candidate block directive only when it starts with `{`, optional whitespace, then `"`
  (`AGENTS.md:35` at `v0.9.0`). Under the broader rule, `[[{sic}]]` is scanned as JSON and
  hits an error at once, which leaves the rest as `note`. That is harmless, but the colours
  would disagree with what the compiler treats as a directive. Separately, when `[[` sits
  alone on its line, the content starts on the next line, so line state also needs a "note
  open, no content yet" bit. *Recommendation: match glosa-av's rule.*
- **N-11. `⌥↩` on iOS.** (→ Q-6) § 1.3 does not mark `⌥↩` as macOS-only. On iOS it needs
  a `UIKeyCommand` and works only with a hardware keyboard. Touch users would reach *Edit
  as Text* through accessibility custom actions or through the host. *Recommendation:
  required on both platforms, via `UIKeyCommand` on iOS.*
- **N-12. Spike behaviours that change in the release.**
  - Click: the spike puts the caret on an edge (row 3). The release selects the block and
    calls `onEmbedActivate`.
  - Row height: the spike uses 44 pt × zoom. The release uses two lines of the current font.
  - The spike's offset-keyed registry and `spikeSetExpanded` go away; the provider is
    asked per block instead.
  - Undo of a deleted embed restored the text but not the embed in the spike. With a
    provider it should come back by itself, but nothing proves that yet, so add a test.
  - The container bit-stack needs a depth cap; past it, treat the JSON as malformed.
  - The iOS accessibility count/index API is answered by hand in the spike. Keep that
    until the live VoiceOver check says otherwise.

One correction to revision 2: its N-3 said the performance suite asserts that the fixture is
unchanged. It does not. It asserts that the fixture is at least 110 KB and contains no
`` ``` `` and no `/*` (`ScanBudgetTests.swift:82-100`). JSON notes may be added to the
fixture as long as they contain neither.

## Questions for the user

| ID | Question | Recommendation |
|----|----------|----------------|
| Q-1 | How does the editor learn that the provider's answer changed with no text edit (*Edit as Text*, Find)? | `EscriboEditorHandle.invalidateEmbeds()`, plus re-asking for each edit's rescanned blocks; the same for notices |
| Q-2 | Where does `wellNotice(for:)` live? | An `EscriboEditor` parameter, after `onWellAction` |
| Q-3 | Does the ≤ 8-line convergence budget apply to edits inside a multi-line JSON note? | No. The bound is "to the note's end + 8", pinned by a new pathological case |
| Q-4 | Notice details: skip the "has content" rule? Share a slot with `.readAloud`? Draw the span bar? | Yes; one slot; glyph only |
| Q-5 | JSON trigger: `{` (as written) or glosa-av's `{` + whitespace + `"`? | Match glosa-av |
| Q-6 | Is `⌥↩` required on iOS (hardware keyboard)? | Yes, via `UIKeyCommand` |

None of these blocks breakdown. `breakdown` copies them into `## Open Questions`, and
`refine-blockers` stops on them there.

## Local Dependency Map

| Dependency | Declared | Resolved | Local checkout | Local HEAD | Status |
|------------|----------|----------|----------------|-----------|--------|
| swiftlang/swift-markdown (test-only) | `upToNextMajor(from: "0.8.0")` | `0.8.0` (`3c6f9523da3a`) | none | none | NO_LOCAL_CHECKOUT |
| swiftlang/swift-cmark (transitive, test-only) | n/a | `0.8.0` (`924936d0427c`) | none | none | NO_LOCAL_CHECKOUT |
| intrusive-memory/glosa-av (spec source only, not a dependency) | n/a | n/a | `~/Projects/package-collection/pkg/glosa-av` | `7459eb8` (`development`, latest tag `v0.9.0`) | n/a |

The package has no shipping dependencies and no sibling pattern. No assumption rests on
dependency source.

## Unverifiable

None. Live input behaviour (VoiceOver, real taps, selection-handle drags, paste) cannot be
checked offline, but the requirements already make it the first iOS sortie's job. That makes
it a deliverable, not an assumption.

## Sortie estimate

The spike estimated about 16 sorties (range 14–18). This recon adds 1–2:

- The flaky and hanging font tests (§ Gate in) need a sortie that the spike's estimate did
  not count.
- Q-1 (the trigger for asking the provider again) adds API and test work that embeds and
  notices share.

**Revised: about 17–18 sorties (range 15–20).**

## Handoff to breakdown

- Breakdown may run after the user answers Q-1 to Q-6, or it may carry them as Open
  Questions.
- Order the first sorties as the gate requires. The font-test sortie goes first. The macOS
  block-cache fix (N-7) comes before any macOS embed sortie, and the iOS live check comes
  before any iOS embed sortie.
- Turn N-2, N-5, N-6, N-8, and N-12 into acceptance criteria on the scanner, API,
  test-infrastructure, and embed sorties.
- The spike code to port lives only on `spike/block-embeds`, not on `development`: the
  `Sources/SwiftEscribo/Spike/` files, the `// SPIKE` hooks in `EditorInputPath.swift`, and
  the three `BlockEmbedSpike*Tests.swift` files.
