---
type: supervisor-state
title: OPERATION FOUNTAIN SURGEON — Supervisor State
updated: 2026-07-26
---

# SUPERVISOR_STATE.md — OPERATION FOUNTAIN SURGEON

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance
> criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI
> agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

---

## Mission Metadata

- Operation: OPERATION FOUNTAIN SURGEON
- Iteration: 1
- Starting point commit: `6b8c3ee3d07ad15afe5d6f44fe7c218db334585e`
- Mission branch: `mission/fountain-surgeon/01`
- Base branch: `development`
- Plan: `EXECUTION_PLAN.md`
- max_retries: 3
- Pre-build dependency purge: skipped (no-op — package declares zero dependencies)
- Purge decision recorded: 2026-07-25 (see Decisions Log DL-1)
- **Supervising session: `fa1c4c1d` (has the con since 2026-07-26 06:43 PDT — see DL-30)**

---

## Plan Summary

- Work units: 7
- Total sorties: 30
- Dependency structure: layers (0 → 4)
- Dispatch mode: dynamic (no explicit dispatch template in the plan)

## Work Units

| Name | Directory | Sorties | Range | Layer | Dependencies |
|------|-----------|---------|-------|-------|-------------|
| WU-1 Core Substrate | `Sources/EscriboCore` | 6 | 1–6 | 0 | none |
| WU-2 Editor Substrate | `Sources/SwiftEscribo` | 6 | 7–12 | 1 | WU-1 |
| WU-3 Fountain Depth | `Sources/EscriboCore/Fountain` | 5 | 13–17 | 2 | WU-1, WU-2 |
| WU-4 Markdown Breadth | `Sources/EscriboCore/Markdown` | 5 | 18–22 | 2 | WU-1, WU-2 (S21 also WU-3) |
| WU-5 Writer | `Sources/EscriboCore/Writer` | 2 | 23–24 | 3 | WU-3 |
| WU-6 Editor Behavior | `Sources/SwiftEscribo` | 3 | 25–27 | 3 | WU-2, WU-3, WU-4 |
| WU-7 Verification & Hardening | repo root, `.github/` | 3 | 28–30 | 4 | WU-1…WU-6 |

---

## Work Unit States

### WU-1 Core Substrate
- Work unit state: **COMPLETED**
- Current sortie: 6 of 6 — all complete
- Sortie state: COMPLETED
- Last verified: Sortie 6 COMPLETED, commit `43ac4e2`. Supervisor independently re-ran
  every exit criterion on 2026-07-26: `make test-core` exit **0**, **98 tests / 11
  suites**, `** TEST SUCCEEDED **`. Gate runs **224** parameterized cases (32 seeds × 7
  documents) × 3 grammars × 7 edits; the ≥200 floor is asserted in-suite at
  `ScanGateTests.swift:674`, not claimed in a comment. `grep 'import XCTest' Tests/` →
  no matches. Every `Int.random(in:)` under `Tests/EscriboCoreTests/` passes
  `using: &generator` (13 sites, all checked); no `Date()`, no `randomElement()`, no
  bare `shuffled()`. Invariant-helper coverage confirmed structurally rather than by
  count: `IncrementalScannerTests.expectInvariants` (line 55) and
  `MarkdownGrammarTests.fullScan` (line 32) both forward to `ScanInvariants.check`, so
  the 79 scan sites reduce to 27 direct + wrapped. Charter re-checked: no regex anywhere
  under `Sources/`, `EscriboCore` still imports **nothing at all**.
  **EC5 discharged in substance but not as written — see DL-31.**
- Notes: DL-25's blind spot (the gate cannot catch grammar state omission) now has a
  companion, DL-31. Both must be honored by Sorties 13–21.

#### Sortie history — WU-1
| Sortie | State | Model | Attempts | Commit | Verified by supervisor |
|--------|-------|-------|----------|--------|------------------------|
| 1 | COMPLETED | opus | 1 | `6a3c8ae` | build 0, test-core 0 (13 tests), 4/4 greps clean, 5 targets |
| 2 | COMPLETED | opus | 1 | `c30ede2` | build 0, test-core 0 (32 tests), greps clean, opacity negative reproduced by supervisor probe |
| 3 | COMPLETED | opus | 1 | `224a248` | build 0, test-core 0 (57 tests), 7/7 terminator fixtures, access levels correct, no timing API, ~2,200-edit incremental sweep |
| 4 | COMPLETED | opus | 1 | `26ad85f` | test-core 0 (73 tests / 8 suites), EC2 grep clean, DL-14 discharged, thousands-of-edits sweep, no regex |
| 5 | COMPLETED | opus | 1 | `fbb14c0` | test-core 0 (93 tests / 10 suites), public `EscriboScanner` facade created per DL-20, fence flag in `LineState` |
| 6 | COMPLETED | opus | 1 | `43ac4e2` | test-core 0 (98 tests / 11 suites), 224 gate cases, seed audit clean, XCTest-free, **gate falsified by supervisor probe 2** (DL-31) |

### WU-2 Editor Substrate
- Work unit state: **RUNNING** (unlocked 2026-07-26 — WU-1 COMPLETED)
- Current sortie: 10 of 30 (fourth of 7–12)
- Sortie state: DISPATCHED
- Sortie type: code
- Model: **sonnet** (first non-opus dispatch of the mission — see DL-60)
- Complexity score: 9
- Attempt: 1 of 3
- Last verified: Sortie 9 COMPLETED, commit `370f918`. Supervisor independently re-ran
  every exit criterion: `make test` exit **0** and `make test-ios` exit **0**
  (`SwiftEscriboTests` **62 tests / 11 suites**, up from 40/6; core unchanged at 98/11).
  `setAttributedString` → no matches. `hasMarkedText` guard sited at
  `EditorCoordinator.swift:218`, before both the scan and the styler. The
  UI-framework-import count for `EditorCoordinator.swift` is **0** — its only imports are
  `EscriboCore` and `Foundation`. DL-40 and DL-12 both still hold. **Both falsification
  probes fired (DL-53), including the DL-44 hazard probe, which is the one that mattered.**
- Previously verified: Sortie 8 COMPLETED, commit `a1947c9`. Supervisor independently re-ran
  every exit criterion: `make test` exit **0** and `make test-ios` exit **0**
  (`SwiftEscriboTests` **40 tests / 6 suites**, up from 22/4; core unchanged at 98/11).
  All four greps clean: no point constants in the theme tables, no family name anywhere
  under `Tests/`, no `resources:` in `Package.swift`, and DL-40's styler-mode grep still
  empty. One `invalidate()` remains the only invalidation path and now clears both the
  style and paragraph caches. `TokenStyle` still has no size field (DL-33). Two
  falsification probes fired correctly (DL-45).
- Previously verified: Sortie 7 COMPLETED, commit `9d7faf2`. Supervisor independently re-ran
  every exit criterion: `make test` exit **0** (`SwiftEscriboTests` **22 tests / 4
  suites**, up from 2/1; `EscriboCoreTests` unchanged at 98/11), `** TEST SUCCEEDED **`.
  `grep -rE 'protocol .*Theme' Sources/SwiftEscribo/` → no matches. Charter re-checked:
  no regex under `Sources/`, `EscriboCore` still imports **nothing at all**, no XCTest
  under `Tests/`. DL-12 intact — `LineRecord`, `ScanResult`, and `LineState` still have
  no public initializer. Sortie 12's styler-mode grep already returns no matches.
  **DL-26 is enforced structurally, not by convention** (DL-33), and both supervisor
  falsification probes fired correctly (DL-34).

#### Sortie history — WU-2
| Sortie | State | Model | Attempts | Commit | Verified by supervisor |
|--------|-------|-------|----------|--------|------------------------|
| 7 | COMPLETED | opus | 1 | `9d7faf2` | test 0 (22/4 + 98/11), theme-protocol grep clean, DL-12 intact, two falsification probes fired (DL-34) |
| 8 | COMPLETED | opus | 1 | `a1947c9` | test 0 **and test-ios 0** (40/6 + 98/11), 4/4 greps clean, one invalidation path preserved, two falsification probes fired (DL-45) |
| 9 | COMPLETED | opus | 1 | `370f918` | test 0 and test-ios 0 (62/11 + 98/11), coordinator imports 0 UI frameworks, DL-44 hazard probed and guarded (DL-53) |

### WU-3 Fountain Depth
- Work unit state: NOT_STARTED
- Current sortie: 13 of 30
- Sortie state: PENDING
- Notes: Gated on WU-2 (Sortie 12).

### WU-4 Markdown Breadth
- Work unit state: NOT_STARTED
- Current sortie: 18 of 30
- Sortie state: PENDING
- Notes: Gated on WU-2 (Sortie 12). Runs parallel with WU-3.

### WU-5 Writer
- Work unit state: NOT_STARTED
- Current sortie: 23 of 30
- Sortie state: PENDING
- Notes: Gated on Sortie 17.

### WU-6 Editor Behavior
- Work unit state: NOT_STARTED
- Current sortie: 25 of 30
- Sortie state: PENDING
- Notes: Gated on Sortie 20 + Sortie 12.

### WU-7 Verification & Hardening
- Work unit state: NOT_STARTED
- Current sortie: 28 of 30
- Sortie state: PENDING
- Notes: Gated on Sorties 27, 17, 22.

---

## Active Agents

| Work Unit | Sortie | Sortie State | Attempt | Model | Complexity Score | Task ID | Output File | Dispatched At |
|-----------|--------|-------------|---------|-------|-----------------|---------|-------------|---------------|
| WU-2 | 10 | DISPATCHED | 1/3 | sonnet | 9 | (session `fa1c4c1d`) | — | 2026-07-26 09:15 PDT |

---

## Decisions Log

| ID | Timestamp | Work Unit | Sortie | Decision | Rationale |
|----|-----------|-----------|--------|----------|-----------|
| DL-1 | 2026-07-25 | — | — | Pre-build dependency purge SKIPPED | `Package.swift` declares zero dependencies (charter), there is no `Package.resolved`, and no DerivedData exists for this project. The purge's stated value — bumping `intrusive-memory/*` floors and forcing a clean resolve — is nil here, while clearing the *global* SPM cache would force every other Swift project on this machine to re-download. Zero benefit, real cost. |
| DL-2 | 2026-07-25 | — | — | Operation named OPERATION FOUNTAIN SURGEON (haiku) | THE RITUAL. Branch slug `fountain-surgeon`. |
| DL-3 | 2026-07-25 | WU-1 | 1 | Model: opus | Complexity 21. Override also forces opus: foundation_score 1 with 29 dependents. The kind vocabulary is source-breaking to get wrong. |
| DL-4 | 2026-07-25 | WU-7 | 29 | FLAGGED, not resolved | Sortie 29 exit criteria require the CI lint job to invoke `make lint`, but the existing `make lint` target runs `swift format -i -r .`, not SwiftLint. Sortie 29's agent must reconcile the Makefile target with the SwiftLint requirement. |
| DL-5 | 2026-07-25 | WU-1 | 1 | ACCEPTED: Makefile + CI scheme changed to `SwiftEscribo-Package` | SwiftPM's per-product `SwiftEscribo` scheme has no test action, so **every** `xcodebuild test` in the repo was broken from scaffolding and could not surface until test targets existed. |
| DL-6 | 2026-07-25 | WU-1 | 1 | RULING: `SpanRole` stays a `Hashable, Sendable` struct | The plan required only `Equatable, Sendable`; `Hashable` is a superset and Sortie 7's cache key `(SpanKind, StyleSet, SpanRole)` needs it. |
| DL-7 | 2026-07-25 | WU-1 | 1 | RULING: `ElementKind.heading` carries level in `LineRecord.depth` | Not `.heading1…heading6`. REQUIREMENTS.md keys geometry by `(ElementKind, depth)`. Sorties 5 and 27 must honor this. |
| DL-8 | 2026-07-25 | WU-1 | 2 | Model: opus | Complexity 21. The span/record model is the scanner→editor seam. |
| DL-9 | 2026-07-25 | WU-1 | 2 | KEPT: `TextEdit.changeInLength` (public computed) | Derived, names the quantity `NSTextStorage` names, and prevents four later sorties each recomputing it with a possible sign error. **Pre-authorized for Sortie 30's API audit.** |
| DL-10 | 2026-07-25 | WU-1 | 2 | KEPT: `ScanResult: Equatable` | Plan says `Equatable`; REQUIREMENTS.md line 211 declares only `Sendable`. Sortie 6's gate needs wholesale comparison. Strictly additive. |
| DL-11 | 2026-07-25 | WU-1 | 2 | Supervisor independently reproduced the opacity negative | A test that must *fail to compile* cannot live in a passing suite, so the supervisor wrote a throwaway non-`@testable` probe, confirmed three `inaccessible` errors, and deleted it. |
| DL-12 | 2026-07-25 | WU-1 | 2 | CONSEQUENCE, carried forward: `LineRecord`/`ScanResult` inits are internal | Forced by `LineState` opacity. `SwiftEscriboTests` (Sortie 7 styler, Sortie 9 edit translation) must `@testable import EscriboCore` or drive a real scanner. **If a later sortie "fixes" this by making those inits public, the opacity guarantee is gone.** |
| DL-13 | 2026-07-25 | WU-1 | 3 | Model: opus | Complexity 20. Terminator handling plus incremental range adjustment is algorithmic and blocks 27 sorties. |
| DL-14 | 2026-07-25 | WU-1 | 3 | ACCEPTED with follow-up: `LineIndex.provisionalRecord(at:)` | Set `startState = .documentStart` for every line — false data in a real type. Sortie 4 deleted it; discharged. |
| DL-15 | 2026-07-25 | WU-1 | 3 | NOTED: two different "one line back" rules | Sortie 3's backward widening is about **code units**; Sortie 4's is about **grammar state**. They must stay separate functions. |
| DL-16 | 2026-07-25 | WU-1 | 3 | ACCEPTED: `LineIndex.apply` clamps out-of-range edits rather than trapping | Scanning is total. An edit from an already-mutated text view is a real, survivable race. |
| DL-17 | 2026-07-25 | WU-1 | 4 | Model: opus | Complexity 23. Highest-risk algorithm in the package. |
| DL-18 | 2026-07-25 | WU-1 | 4 | ~~Sortie 4 RE-DISPATCHED~~ **RETRACTED — see DL-19.** | The liveness verification behind this decision was wrong. |
| DL-19 | 2026-07-25 | WU-1 | 4 | CORRECTION: the original Sortie 4 agent was ALIVE the whole time | `TaskList` is per-session; `ps` cannot see an agent between tool calls; a clean tree is satisfied identically by a dead agent and a live one that has read but not written. **Reliable liveness signal, adopted going forward:** mtime of the agent's own transcript at `~/.claude/projects/<project>/<session>/subagents/agent-<id>.jsonl`. Never `ps`, never cross-session task lists, never a clean tree alone. |
| DL-20 | 2026-07-25 | WU-1 | 4 | ACCEPTED with follow-up: scanner entry points are **internal**, not public | Public generic scanner ⇒ public `LineGrammar` ⇒ public `LineState` ⇒ opacity gone. Sortie 5 created the non-generic `Language`-dispatching facade (`EscriboScanner`). Discharged. |
| DL-21 | 2026-07-25 | WU-1 | 4 | ACCEPTED: `LineState` gained one internal field, `openConstruct: UInt16` | Without at least one field every `LineState` equals every other and a stateful test grammar is impossible. A scalar, not a stack — one state per line, so an allocating field would put an allocation per line on the hot path. |
| DL-22 | 2026-07-25 | WU-1 | 4 | NOTED for Sortie 28: one `[UInt16]` allocation per line scanned | The bulk-read contract holds, but the array is a real allocation on the hot path. **Sortie 28 must measure it**; the fix, if needed, is local to `grammarLine(at:in:)`. |
| DL-23 | 2026-07-25 | WU-1 | 4 | RECORDED: convergence condition 3 is weaker than conditions 1 and 2 | The agent could not construct a case where dropping the lookahead extension produces *wrong output* — only a wrong dirty-range extent. Implemented anyway as insurance. **Confirmed empirically by DL-31.** |
| DL-24 | 2026-07-25 | WU-1 | 5 | Model: opus | Complexity 20; override applies. First grammar through the seam. |
| DL-25 | 2026-07-25 | WU-1 | 5 | **CRITICAL: the gate property has a structural blind spot** | Breaking the fence flag turned six classification tests red and left `incrementalScan == fullScan` **green**, because both sides ran the same broken grammar. **The gate catches convergence bugs in the *engine* and can never catch state-omission bugs in a *grammar*.** Sorties 13–21 must not treat a green gate as grammar evidence. |
| DL-26 | 2026-07-25 | WU-1 | 5 | ACCEPTED with carry-forward to Sortie 7: leading indent is engine `.text` filler | A heading's leading indent is emitted as `.text`-kind filler, not as part of the `.marker` span. **Sortie 7's styler must take point size from the line's `ElementKind`, not from the span's `SpanKind`** — otherwise a `.text`-kind indent span on a scaled heading line breaks the within-line size uniformity REQUIREMENTS.md Architecture §3 requires and Sortie 27 asserts. |
| DL-27 | 2026-07-25 | WU-1 | 5 | ACCEPTED: `contentRange` inside a fence keeps all leading indentation | Deviates from CommonMark, which strips to the opening fence's indent. Chosen so Sortie 23/24's writer stays lossless. Correct trade for a package whose writer must round-trip. |
| DL-28 | 2026-07-25 | WU-1 | 5 | ACCEPTED: `EscriboScanner` is deliberately not `Sendable`, and `language` is `let` | It carries mutable scan state and scanning is synchronous and single-threaded. **Sortie 9 should hold one scanner per document beside the text storage.** Switching language means a new scanner and a full scan. |
| DL-29 | 2026-07-25 | WU-1 | 6 | Model: opus | Complexity 20; override applies. Designed around a known blind spot rather than trusting its own headline assertion. |
| DL-30 | 2026-07-26 | — | — | **Session `fa1c4c1d` takes the con. The split brain is resolved — both prior sessions are dead.** | Verified by the DL-19 signal, not by inference: `8380d2fe` ran `/exit` at 13:42:42Z (its transcript's last record is `Bye!`), and `d1a5e802`'s transcript has been silent since 06:50:19Z. No subagent transcript under either session has been written since 23:48 PDT on 2026-07-25. Working tree clean at `43ac4e2`. One supervisor, no live agents. |
| DL-31 | 2026-07-26 | WU-1 | 6 | **Sortie 6 EC5 met in substance, NOT as written — and the difference is a second blind spot worth recording** | EC5 asks that "temporarily returning after one converged line with no lookahead" turn the gate **red**. The supervisor ran exactly that break (replacing the `stop = min(lineCount, line + lookahead)` extension with an immediate `break`) and the gate stayed **green — 224/224 cases passed** — while only `IncrementalScannerTests`' direct convergence assertions went red. This is not a defect in the harness; it is DL-23 confirmed empirically. Output at lines ≥ the converged line is a function of `(state, text)`, both proved unchanged, so the un-repainted lines were already correct and a painted-document comparison cannot see the difference. It holds even for `CueGrammar(lookahead: 1)`, which the gate does exercise. **The gate is nonetheless falsifiable, and the supervisor proved it:** a second probe setting `backwardWidening` to `0` turned the gate **red across many seeds** (272 issues across the run, `incrementalScanEqualsFullScan` among the failures). Both probes reverted; tree clean; `make test-core` green again at 98/11. **Consequence for Sorties 13–21:** the gate is blind in *two* directions — grammar state omission (DL-25) and a too-short forward extension past convergence (here). A lookahead rule's correctness — Sortie 14's cue rule above all — must be asserted directly, by naming expected `ElementKind`s, and can never be inferred from a green gate. |
| DL-33 | 2026-07-26 | WU-2 | 7 | **RULING: `TokenStyle` carries no size or size-scale field. DL-26 beats the plan's stage-2 wording, and the agent was right to say so rather than split the difference.** | Plan task 4 lists the kind stage as "color, font traits, **size scale**"; DL-26 requires size to come from the line's `ElementKind`. The agent resolved for DL-26 and deleted the field, moving size to `EscriboTheme.elementSizeScales: [ElementKind: [Int: Double]]` — keyed by `(ElementKind, depth)`, the same key REQUIREMENTS.md already uses for geometry and DL-7 already established for headings. **This is the stronger design and it is what REQUIREMENTS.md actually wants:** § "Marker dimming is unfalsifiable by construction" says the absence of a marker `TokenStyle` means "markers a size smaller" is a thing *the type system refuses*, not a rule someone remembers. Removing size from `TokenStyle` extends that property from markers to every span on a line. A size scale hung off `SpanKind` is now unrepresentable, not merely discouraged. Point size is computed at exactly one site, `EscriboStyler.swift:224`, as `theme.baseFontSize × metrics.pointSizeScale × theme.sizeScale(for: line.element, depth: line.depth)`. |
| DL-34 | 2026-07-26 | WU-2 | 7 | Supervisor falsified the two claims most easily written vacuously | A cache-hit test and a "resolves to base" test both pass trivially if the styler does nothing interesting, so neither was taken on report. **Probe A** narrowed the invalidation guard to compare only the theme; the parameterized trigger test went red on exactly `.mode`, `.appearance`, and `.fontMetrics` and stayed green on `.theme` — it genuinely distinguishes the four triggers and names the broken one. **Probe B** made the role stage multiply point size by 0.9; `A marker and its content sibling differ only in foreground alpha`, `The role stage touches the foreground alpha and nothing else`, and `Every span on an indented heading line resolves to the same point size` all went red, as did the source-theme collapse tests (137 issues). Both probes reverted; tree clean; `make test` green at 22/4 + 98/11. The DL-26 guard is real. |
| DL-35 | 2026-07-26 | WU-2 | 7 | ACCEPTED: the style cache is two-level, `[LineStyleKey: [StyleKey: ResolvedStyle]]` | The mandated `(SpanKind, StyleSet, SpanRole)` key is the **inner** key, verbatim and unmodified. The outer partition is `(ElementKind, depth)`. This is forced by DL-33, not a liberty taken: once point size is a per-line quantity, a flat `(SpanKind, StyleSet, SpanRole)` cache returns the *wrong size* for the same span shape on a heading line versus a body line. Partitioning by the key REQUIREMENTS.md already uses for geometry keeps the mandated key intact and both levels in the tens. **Sortie 30 must not "simplify" this to one level** — that reintroduces the exact bug DL-26 exists to prevent. |
| DL-36 | 2026-07-26 | WU-2 | 7 | ACCEPTED: the styler caches `ResolvedStyle` values, not attribute dictionaries | `[NSAttributedString.Key: Any]` is not `Equatable`, so a dictionary cache cannot be asserted against the invariants this layer exists to guarantee. Dictionaries are produced on demand via `attributes(resolver:)`. The exit criterion stated in terms of an attribute dictionary is nonetheless discharged against a real `NSDictionary` comparison, not against the value type only. |
| DL-37 | 2026-07-26 | WU-2 | 7 | ACCEPTED with a flag for Sorties 10–12: `EscriboColor` stores sRGB components; fonts are described by `FontSpec` **intent**, not by `NSFont`/`UIFont` | Buys `Sendable` + `Equatable` on the theme for free, keeps any family name out of every type a test can reach (so D-4 is enforced structurally rather than by convention), and — the real argument — keeps appearance one of the four **declared** invalidation triggers instead of an invisible mutation inside a dynamic system color. **The cost is real and is being accepted knowingly:** static sRGB does not follow macOS accent color or the increased-contrast accessibility setting the way `NSColor.labelColor` does. That is a theme-authoring problem, not a styler problem, and the appearance trigger is the seam through which a host can fix it. Sorties 10–12 must route appearance changes through `EditorStyleEnvironment.appearance` and must not reach for semantic colors to paper over it. |
| DL-38 | 2026-07-26 | WU-2 | 7 | ACCEPTED: `FontResolver` (the D-4 chain) shipped in Sortie 7 rather than Sortie 8 | Producing an attribute dictionary at all requires a resolved font, so the alternative was a sortie that could not discharge its own exit criteria. Scope stayed bounded and verified: the chain plus a `FontSpec`-keyed cache, and **no** `ParagraphMetrics`, no character-to-point conversion, no `NSParagraphStyle`, no advance-width measurement. `Package.swift` still declares no `resources:`. **Sortie 8 extends `FontResolver`, never replaces it** — `FontSpec` is the cache key and the D-4 name list lives there. |
| DL-39 | 2026-07-26 | WU-2 | 7 | ACCEPTED: the kind stage may override font family | REQUIREMENTS.md lists family at the base and style stages, but "everything else overrides" covers it and the requirements settle the substance directly: Architecture §3 constrains markers **relative to their content**, not content relative to other content, and REQUIREMENTS.md says in as many words that "a Markdown code span legitimately swaps to a mono family and changes advance width; that is the feature working." A fenced code block is a *kind*. Marker/content parity is untouched because a marker and its content share a kind. |
| DL-40 | 2026-07-26 | WU-2 | 7 | ACCEPTED: `EditorMode` never reaches the styler — it is folded into the theme by `strippedToSource()` | One consequence worth naming: Sortie 12's exit criterion `grep -rE 'EditorMode\|\.source\|\.live' Sources/SwiftEscribo/*Styler*` **already returns no matches** and must stay that way. Sortie 12 switches mode by assigning `styler.environment.mode`; it must not add a mode parameter to the styler. |
| DL-41 | 2026-07-26 | WU-2 | 7 | **PRE-AUTHORIZED for Sortie 30's audit: `EscriboColor`, `FontFamilyRole`, `FontTraits` are public and are not on the 1.0 list** | They are *forced*, not speculative: REQUIREMENTS.md § What is public in 1.0 names `TokenStyle`, and a public struct's stored-property types must be public. Same class of exception as DL-9. Sortie 30 should confirm the set is still exactly these three and record them in the report rather than re-litigating them. Everything else the sortie added — `EscriboStyler`, `FontSpec`, `ResolvedStyle`, `FontMetrics`, `EscriboAppearance`, `EditorStyleEnvironment` — is correctly `internal`. |
| DL-42 | 2026-07-26 | WU-2 | 7 | NOTED, not a defect: the Fountain built-in themes are deliberately thin | Base monospaced at 12 pt, no per-element size scaling (a screenplay page is uniform), marker dimming, no `.inlineCode` entry. Scene-heading, cue, and dialogue entries would be decoration for `SpanKind`s that Sortie 13 has not created yet. **Sortie 13 adds them to `BuiltInThemes.swift`, never as a `default:` in the styler** — an unthemed kind rendering as base text is correct behavior, and DL-33 plus the unknown-kind test make that the guaranteed path. |
| DL-43 | 2026-07-26 | WU-2 | 8 | Model: opus | Complexity 20 (5 turns-band + 2 file-count + 10 foundation/dependents + 3 risk). CoreText font resolution and the characters-to-points conversion are reused by both language rule sets in Sortie 27, and D-4 exists precisely because the naive version of this sortie authors a test that passes locally and fails in CI. |
| DL-44 | 2026-07-26 | WU-2 | 8 | **HAZARD for Sortie 9, and the most consequential thing this sortie found: paragraph styles are produced separately from span attributes and must be applied AFTER the span pass.** | `paragraphStyleRuns(for:)` returns `(range, NSParagraphStyle)` pairs; `attributes(for:on:)` is unchanged and carries no paragraph style. Merging them would have broken `SourceThemeTests.everySpanCollapsesToBase`, which compares one-arg and two-arg attribute dictionaries for equality. **The consequence is a live collision with Sortie 9's plan text**, which says to apply attributes with `setAttributes(_:range:)` over the rescanned range: `setAttributes` **replaces** the entire dictionary for a range, so a paragraph style set beforehand is silently dropped and the geometry layer renders as if it were switched off. Sortie 9 must apply the paragraph attribute additively *after* the span pass (`addAttribute(.paragraphStyle:range:)`), or fold the run's style into each span dictionary before setting. Runs are one per line, uncoalesced, over the **full `LineRecord.range` including the terminator** — a paragraph style stopping short of its terminator leaves the newline carrying the previous paragraph's geometry. |
| DL-45 | 2026-07-26 | WU-2 | 8 | Supervisor falsified both properties the sortie exists to establish | **Probe A** replaced the advance-width multiplier in `ParagraphMetrics.paragraphStyle(in:)` with a constant `7.0`; four tests went red, including `Doubling the resolved font size doubles the computed point indent` and `A line's margins are measured against that line's own point size`. **Probe B** dropped the `isGeometryEnabled` guard from `paragraphMetrics(for:depth:)`; `Geometry switched off produces the default paragraph style for every ElementKind` went red — so the geometry-off test is asserted against a *populated* table and cannot pass vacuously. Both reverted; tree clean; `make test` green at 40/6 + 98/11. |
| DL-46 | 2026-07-26 | WU-2 | 8 | **PLAN DEFECT recorded, not repaired: Sortie 8's point-constant grep is broader than its intent and must not become a standing invariant.** | The criterion `grep -rE '(leftIndent\|headIndent\|firstLineHeadIndent)[A-Za-z]*: *[0-9.]+' Sources/SwiftEscribo/` also matches `leftIndentChars: 10` — a **character** constant, which is exactly what Sortie 27 is required to write. It passes today only because Sortie 8 leaves the tables empty. Checked, and the good news is narrow: **Sortie 27 does not carry this grep among its own exit criteria**, so it is not gated on a check it must fail. The risk is that Sortie 30's audit or a regression sweep resurrects it as a standing invariant and reads Sortie 27's correct work as a violation. **The correct standing form of the check is not a text pattern over the tables at all**: `ParagraphMetrics`'s fields are all `…Chars` or `…Lines`, so a point constant can only enter through an `NSMutableParagraphStyle` property assignment, and those occur at exactly one site — `ParagraphMetrics.paragraphStyle(in:)`, where each is a `CGFloat(...)` of a product with `geometry.advanceWidth` or `geometry.lineHeight`. The invariant to assert after Sortie 27 is **"the only writes to `firstLineHeadIndent`, `headIndent`, `tailIndent`, and `paragraphSpacingBefore` live in `paragraphStyle(in:)`"**. EXECUTION_PLAN.md is not edited during execution, so this is recorded here and carried into Sortie 27's and Sortie 30's dispatch prompts. |
| DL-47 | 2026-07-26 | WU-2 | 8 | ACCEPTED: `firstLineIndentChars` is **relative to** `leftIndentChars`, not absolute | A hanging indent is then negative, an ordinary first-line indent positive, and "no special first line" is `0` — the common case is the zero value, which is the property worth having. Absolute would force every rule set to repeat `leftIndentChars`, and any rule that forgot would silently render its first line flush left. Converted as `left + firstLineIndentChars * advanceWidth` into `NSParagraphStyle.firstLineHeadIndent`, which is itself absolute. **Sortie 27 must know this** — it is carried into that dispatch. |
| DL-48 | 2026-07-26 | WU-2 | 8 | ACCEPTED: `ParagraphAlignment`, not `Alignment` | REQUIREMENTS.md's sketch names the *field* `alignment`, which is preserved; only the type name differs. `SwiftUI.Alignment` owns the obvious name and Sortie 12 brings a file importing SwiftUI into this target. A public type that collides there is a rename waiting to happen, and renaming public API after 1.0 is a major release under this package's own semver commitments. Cheap now, expensive later. |
| DL-49 | 2026-07-26 | WU-2 | 8 | ACCEPTED: geometry is measured against the **line's own** `baseStyle` font, at the line's scaled size | Kind and emphasis stages skipped; base family and traits at `sizeScale(for:element,depth:)`. A heading set 1.8× larger with margins measured at body size sits at the wrong column, and the error grows with the scale. Consistent with DL-33: size is a per-line quantity, so the thing margins are measured against is a per-line quantity too. |
| DL-50 | 2026-07-26 | WU-2 | 8 | ACCEPTED: the family chain uses `PlatformFont(name:size:)`, not `CTFontCreateWithName` — and the reasoning matters more than the call | Plan task 4 says the chain goes "through CoreText". `CTFontCreateWithName` **never fails**: handed an unknown name it substitutes silently. A chain built on it would always succeed at its first entry, so Courier New, Courier, and the `.monospacedSystemFont` fallback would all be unreachable — D-4's entire purpose defeated, and defeated in a way no test could observe, because the substituted font is a real font. CoreText does the **measuring** here (advance width, line height); it must not do the **choosing**. This is precisely the class of local-passes/CI-misleads defect D-4 exists to prevent. |
| DL-51 | 2026-07-26 | — | — | PROCESS NOTE for the brief: a killed `xcodebuild` orphans an `xctest` agent that blocks the next run | The Sortie 8 agent hit this and so did the supervisor — one probe run timed out at 10 minutes with no output. The harness does not recover on its own. Symptom: `make test` hangs indefinitely with no test output. Fix: check `pgrep -fl 'xcodebuild\|xctest'` and kill survivors before re-running. Not a code defect; worth one line in the brief so the next mission does not diagnose it twice. |
| DL-52 | 2026-07-26 | WU-2 | 9 | Model: opus | Complexity 24 (8 turns-band + 2 file-count + 10 foundation/dependents + 4 risk); override applies. The coordinator is adopted unchanged by both Representables — the plan states plainly that an AppKit-shaped seam here does not retrofit to UIKit — and it must land DL-44 correctly or the whole geometry layer renders as though switched off. |
| DL-53 | 2026-07-26 | WU-2 | 9 | Supervisor probed the DL-44 hazard directly, because it is the one defect in this mission that would have shipped silently | **Probe A** moved the paragraph-style pass *before* the span pass — the exact bug DL-44 predicted. Four tests went red: `A styled line carries both its span attributes and its paragraph style`, `A line's paragraph style covers its terminator, not just its content`, `Marker spans are dimmed but keep the line's size and geometry`, and `Switching language builds a new scanner and restyles everything`. The composed-result assertion DL-44 demanded now exists and works. **Probe B** neutered the marked-text guard; `With marked text active, a storage edit makes zero calls into the styler` and `Edits dropped during a composition are recovered by a full rescan afterwards` both went red. Both reverted; tree clean; green at 62/11 + 98/11. **Method note against my own error:** the first attempt at Probe B used `sed` and silently failed to substitute, producing an all-green run that looked like a weak test. It was not a weak test; it was a probe that never applied. A probe that reports no failures must be checked for having actually landed before any conclusion is drawn from it. |
| DL-54 | 2026-07-26 | WU-2 | 9 | **ACCEPTED, and this is the best structural answer to platform-neutrality the mission has produced: `EditorTextStorage` is a protocol whose conformance is empty** | `extension NSTextStorage: EditorTextStorage {}` has no body, because all five members the coordinator uses are inherited from `NSMutableAttributedString` — Foundation, not AppKit or UIKit. The coordinator therefore depends on a **subset** of the real text system rather than a wrapper over it: there is no adapter to drift, and tests exercise the real object. The rejected alternative, a `PlatformTextStorage` typealias, would have satisfied the import grep by trickery while leaving the coordinator typed against a UI-framework class. The protocol also makes it impossible for `apply` to express a character mutation or a whole-string assignment, which is `setAttributedString`'s prohibition enforced by the type system rather than by a grep. |
| DL-55 | 2026-07-26 | WU-2 | 9 | ACCEPTED: `hasMarkedText` is a **stored closure the view binds**, not a protocol requirement | AppKit spells it `hasMarkedText()` (a method on `NSTextInputClient`); UIKit spells it `markedTextRange` (a property on `UITextInput`). No single protocol requirement is directly satisfiable by both, so whichever platform were written first would have won and the other would have needed an adapter — and macOS is written first, in Sortie 10. One line to bind on either platform. **The policy stays in the coordinator** (the guard, the skip counter, the rescan flag), so Sortie 11 cannot forget it; only the question is delegated. |
| DL-56 | 2026-07-26 | WU-2 | 9 | ACCEPTED with a measurement obligation for Sortie 28: after a composition ends, the next edit **full-scans** | Edits skipped during marked text leave the line index describing a document that no longer exists, which is not recoverable incrementally. A full scan is the only correct recovery, and it makes a "composition ended" callback unnecessary — Sorties 10 and 11 need no extra wiring. **The cost is real and unmeasured:** CJK and other IME input composes constantly, so this is a full document scan every few keystrokes for those users, on a document that may be 120 KB. REQUIREMENTS.md budgets a cold full scan at ≤ 50 ms with a 10 ms target, so it should fit — but "should fit" is not a measurement. **Sortie 28 must add a composition-recovery case to the pathological sequence** it already measures. |
| DL-57 | 2026-07-26 | WU-2 | 9 | ACCEPTED: `EditorCoordinator` is **not** `@MainActor` | It is a plain non-`Sendable` `final class: NSObject`, matching `EscriboScanner` (DL-28) and `EscriboStyler`. `NSTextStorageDelegate` is nonisolated in the SDK, so annotating the coordinator would have forced `MainActor.assumeIsolated` — **a trap** — onto the hot path of a text-view delegate callback, in a package whose requirements say the scan path has no error path and no precondition. Main-thread ownership is a documented contract here, not an annotation. The test suites *are* `@MainActor`, which is consistent: the contract is asserted where it can be, without putting a trap in shipping code. |
| DL-58 | 2026-07-26 | WU-2 | 9 | ACCEPTED: two protocol-extension helpers, and genericity **rejected on purpose** | Swift will not pass `any EditorTextStorage` to a `some UTF16TextSource` parameter, and a protocol extension is where `Self` is concrete. The obvious alternative — making the coordinator generic over its storage type — was rejected because **Sortie 11's exit criterion requires both Representables to drive the same *declared* type**, and a generic coordinator makes that criterion unsatisfiable as written. Deciding this in Sortie 9 rather than discovering it in Sortie 11 is the whole reason the plan puts the coordinator first. `EditorCoordinator` is non-generic and unconditionally declared; Sortie 11's criterion is satisfiable. |
| DL-59 | 2026-07-26 | WU-2 | 9 | **NOTED as a second instance of the DL-46 class, for the brief: a literal-grep exit criterion punishes documenting the thing it forbids** | The agent had to reword two doc comments so its prose explaining *why* `setAttributedString` is forbidden did not itself trip `grep -rn 'setAttributedString' Sources/SwiftEscribo/`. The prohibition is still documented, spelled out longhand. No call exists — verified independently. This is not misconduct and the criterion's intent is met; it is a **plan-authoring lesson**: a bare literal grep over a whole source tree cannot distinguish a call from a warning about the call, and the sortie that most deserves to explain the rule is the one penalised for doing so. Pair such criteria with a scope (`grep` excluding comment lines) or assert the absence of the *call* rather than the *token*. Same family as DL-46. |
| DL-61 | 2026-07-26 | — | — | **ENVIRONMENTAL, pre-existing, and a real CI risk: `make test` intermittently HANGS in font resolution — it does not fail** | Every test worker blocks in `+[NSFont fontWithName:size:]` awaiting a synchronous XPC reply from an idle `fontd`. The Sortie 9 agent reproduced it on the **clean tree at `9a04922`**, before writing any code, so it is not caused by this mission; the supervisor independently lost a 10-minute probe run to it during Sortie 8 verification. Local recovery: `pgrep -fl 'xcodebuild\|xctest'`, kill survivors, re-run — the next run succeeds. **Why it matters beyond this machine:** `.github/workflows/tests.yml` declares no `timeout-minutes` on either job, so a hang there consumes the GitHub Actions default of **six hours** per job instead of failing fast. A hang is strictly worse than a failure in a gating job. **Sortie 28 and Sortie 29 must declare `timeout-minutes` on every workflow job they create, and Sortie 29 should add it to the existing `tests.yml` jobs while it is in that file.** The supervisor does not edit workflow config during execution; this is carried into both dispatch prompts. |
| DL-60 | 2026-07-26 | WU-2 | 10 | **Model: sonnet — the first non-opus dispatch of this mission, and deliberately so** | Complexity **9**: 3 turns-band + 2 file-count + 0 foundation + 2 dependency-depth + 2 risk. Sorties 1–9 all scored ≥ 20 because each owned an algorithm, a seam, or a vocabulary that later sorties are built on. **Sortie 10 owns none of those.** Sortie 9 already built and proved the seam; per its own report the macOS wiring is three lines. What remains is constructing an `NSTextView` on a TextKit 2 stack inside an `NSScrollView`, setting four substitution flags to `false`, and leaving continuous spell checking `true` — a clear spec with machine-checkable property assertions and no ambiguity to resolve. Sending opus at 30× cost for that would be ignoring the model-selection rules the mission is supposed to follow. The known trap — `NSTextView` falling back to TextKit 1 depending on how it is constructed — is precisely what the `textLayoutManager` non-nil criterion catches, so a wrong answer fails loudly rather than silently. If it fails, the retry rule upgrades attempt 2 to opus; that path costs one sortie, and taking it is cheaper than pre-paying opus on every remaining sortie. |
| DL-32 | 2026-07-26 | WU-2 | 7 | Model: opus | Complexity 25 (8 turns-band + 4 file-count + 10 foundation/dependents + 3 risk + 0 ambiguity). Override also applies: foundation_score 1 with 23 dependents. The theme lookup table and the styler cache are the second half of the scanner→editor seam and are consumed by all three Representables; the composition order and the single invalidation path are exactly the shape that does not retrofit. |

---

## Overall Status

- Sorties completed: **9 / 30** (Sorties 1–9 — all supervisor-verified)
- Sorties in flight: 1 (Sortie 10, WU-2)
- Work units completed: **1 / 7** (WU-1 COMPLETE; WU-2 RUNNING at 10 of 12; WU-3…WU-7 gated)
- Blocked: none
