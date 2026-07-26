---
type: supervisor-state
title: OPERATION FOUNTAIN SURGEON — Supervisor State
updated: 2026-07-25
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
- Work unit state: RUNNING
- Current sortie: 5 of 6
- Sortie state: RUNNING — dispatched 23:12 by supervisor session `d1a5e802` as agent
  `a064d745fdbce6c8a`, confirmed live and growing at 23:14:30. **Not** dispatched by
  session `8380d2fe`, which stood down instead — see DL-22.
- Sortie type: code
- Model: opus
- Complexity score: 20
- Attempt: 1 of 3 (Sortie 4 closed at attempt 1; the redundant re-dispatch was NOT an attempt)
- Last verified: Sortie 4 COMPLETED, commit `26ad85f` (+1,436 / −54 across 8 files).
  Supervisor independently re-ran every exit criterion: `make test-core` **TEST
  SUCCEEDED**, 73 tests / 8 suites; the EC2 grep returns no match and both entry points
  read `-> ScanResult` with no `throws`/`async`; EC3–EC6 are asserted by a shared
  `expectInvariants` helper driven over 8 corpus documents × every start offset ×
  deletion length × replacement × 3 grammars — thousands of distinct edits against a
  floor of 20. Charter re-checked: no regex, `EscriboCore` still imports nothing at all.
  DL-14 discharged — `provisionalRecord` returns zero hits across `Sources/` and
  `Tests/`. Bonus: `expectIncrementalMatchesFull` already asserts incremental ≡ full,
  pre-empting Sortie 6's gate one layer up.
- Previously verified: Sortie 3 COMPLETED — supervisor re-ran `make build` (exit 0) and
  `make test-core` (exit 0, 57 tests / 7 suites), confirmed `LineIndex` is internal
  and `UTF16TextSource` public, confirmed no `fullScan`/`incrementalScan` identifier
  leaked into Sources, no timing API anywhere under Tests, `EscriboCore` still
  imports nothing at all, and all seven required terminator fixtures are present by
  name. Commit `224a248`.
- Notes: Sortie 1 also fixed a latent scheme defect (DL-5). Sortie 5 must honor the
  `ElementKind.heading` + `depth` decision (DL-7). Sorties 7 and 9 must honor the
  internal-initializer consequence (DL-12).

#### Sortie history — WU-1
| Sortie | State | Model | Attempts | Commit | Verified by supervisor |
|--------|-------|-------|----------|--------|------------------------|
| 1 | COMPLETED | opus | 1 | `6a3c8ae` | build 0, test-core 0 (13 tests), 4/4 greps clean, 5 targets |
| 2 | COMPLETED | opus | 1 | `c30ede2` | build 0, test-core 0 (32 tests), greps clean, opacity negative reproduced by supervisor probe |
| 3 | COMPLETED | opus | 1 | `224a248` | build 0, test-core 0 (57 tests), 7/7 terminator fixtures, access levels correct, no timing API, ~2,200-edit incremental sweep |
| 4 | COMPLETED | opus | 1 | `26ad85f` | test-core 0 (73 tests / 8 suites), EC2 grep clean, DL-14 fully discharged, thousands-of-edits sweep asserts all four invariants, no regex, still imports nothing |

### WU-2 Editor Substrate
- Work unit state: NOT_STARTED
- Current sortie: 7 of 30
- Sortie state: PENDING
- Notes: Gated on WU-1 (Sortie 6).

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
| WU-1 | 5 | RUNNING | 1/3 | opus | 20 | (dispatched this session) | — | 2026-07-25 |


---

## Decisions Log

| ID | Timestamp | Work Unit | Sortie | Decision | Rationale |
|----|-----------|-----------|--------|----------|-----------|
| DL-1 | 2026-07-25 | — | — | Pre-build dependency purge SKIPPED | `Package.swift` declares zero dependencies (charter), there is no `Package.resolved`, and no DerivedData exists for this project. The purge's stated value — bumping `intrusive-memory/*` floors and forcing a clean resolve — is nil here, while clearing the *global* SPM cache would force every other Swift project on this machine to re-download. Zero benefit, real cost. |
| DL-2 | 2026-07-25 | — | — | Operation named OPERATION FOUNTAIN SURGEON (haiku) | THE RITUAL. Branch slug `fountain-surgeon`. |
| DL-3 | 2026-07-25 | WU-1 | 1 | Model: opus | Complexity 21 (5 turns-band + 4 file-count + 10 foundation + 2 risk). Override also forces opus: foundation_score 1 with 29 dependents. The kind vocabulary is source-breaking to get wrong. |
| DL-4 | 2026-07-25 | WU-7 | 29 | FLAGGED, not resolved | Sortie 29 exit criteria require the CI lint job to invoke `make lint`, but the existing `make lint` target runs `swift format -i -r .`, not SwiftLint. Sortie 29's agent must reconcile the Makefile target with the SwiftLint requirement. Recorded now so it is not discovered at sortie time as a surprise. |
| DL-5 | 2026-07-25 | WU-1 | 1 | ACCEPTED: Makefile + CI scheme changed to `SwiftEscribo-Package` | SwiftPM's per-product `SwiftEscribo` scheme has no test action, so **every** `xcodebuild test` in the repo — local and CI — was broken from scaffolding and could not surface until test targets existed. Supervisor confirmed the diff and re-ran both targets. Out of the sortie's literal scope but required to satisfy its exit criteria; fixing it is strictly correct. |
| DL-6 | 2026-07-25 | WU-1 | 1 | RULING: `SpanRole` stays a `Hashable, Sendable` struct | The agent asked for a ruling. The plan required only `Equatable, Sendable`; `Hashable` is a superset and Sortie 7's cache key `(SpanKind, StyleSet, SpanRole)` needs it. The styler must not exhaustively switch on role anyway — it multiplies alpha for `.marker` and does nothing otherwise, a single comparison. Consistency with the rest of the vocabulary beats exhaustive switching. |
| DL-7 | 2026-07-25 | WU-1 | 1 | RULING: `ElementKind.heading` carries level in `LineRecord.depth` | Not `.heading1…heading6`. REQUIREMENTS.md keys geometry by `(ElementKind, depth)`, so one entry shape covers all six levels. Sorties 5 and 27 must honor this; carried forward in their dispatch prompts. |
| DL-9 | 2026-07-25 | WU-1 | 2 | KEPT: `TextEdit.changeInLength` (public computed) | Not in the plan's field list; the agent added it and flagged it. Kept: it is derived (`replacementLength - range.count`), it names the same quantity `NSTextStorage` names — which is what makes the translation formula legible — and Sorties 3, 4, 9, and 12 would each otherwise recompute it, with a sign error being exactly the bug the coordinate convention exists to prevent. **Pre-authorized for Sortie 30's API audit**; it does not need re-litigating there. |
| DL-10 | 2026-07-25 | WU-1 | 2 | KEPT: `ScanResult: Equatable` | The plan says `Equatable`; REQUIREMENTS.md line 211 declares only `Sendable`. Followed the plan. Sortie 6's gate test asserts `incrementalScan(edits) == fullScan(finalText)` by comparing results wholesale, which needs it. Strictly additive. |
| DL-11 | 2026-07-25 | WU-1 | 2 | Supervisor independently reproduced the opacity negative | The committed test can only assert the positive half — a test that must *fail to compile* cannot live in a passing suite. So the supervisor wrote its own throwaway non-`@testable` probe, confirmed all three expected `inaccessible` errors, and deleted it. The exit criterion is met in substance, not just in claim. |
| DL-12 | 2026-07-25 | WU-1 | 2 | CONSEQUENCE, carried forward: `LineRecord`/`ScanResult` inits are internal | Forced by `LineState` opacity — a public memberwise init for `LineRecord` would require a publicly-constructible `startState`. `SwiftEscriboTests` (Sortie 7 styler, Sortie 9 edit translation) must therefore `@testable import EscriboCore` or drive a real scanner. **If a later sortie "fixes" this by making those inits public, the opacity guarantee is gone.** Carried into Sorties 7 and 9 dispatch prompts. |
| DL-13 | 2026-07-25 | WU-1 | 3 | Model: opus | Complexity 20. Terminator handling (`\r\n` as one two-code-unit terminator, lone `\r`, mixed, never normalized) plus incremental range adjustment is algorithmic, and it blocks 27 sorties. |
| DL-14 | 2026-07-25 | WU-1 | 3 | ACCEPTED with a follow-up obligation: `LineIndex.provisionalRecord(at:)` | It assigns `.blank`/`.paragraph` from the line's *shape* (empty content range or not), which both grammars agree on — that is shape, not grammar, and it is fine. But it sets `startState = .documentStart` for **every** line, which is true only of line zero. That is false data in a real type. Tolerable as an internal Sortie-3 scaffold; **Sortie 4 must delete it or give it a real `startState`.** Carried into Sortie 4's prompt as a hard boundary. |
| DL-15 | 2026-07-25 | WU-1 | 3 | NOTED: two different "one line back" rules | Sortie 3's backward widening is about **code units** (a `\r` can only pair with an `\n` immediately following, so one line back is provably enough). Sortie 4's is about **grammar state**. They are easy to conflate and must stay separate functions. The agent flagged this itself; carried into Sortie 4's prompt. |
| DL-16 | 2026-07-25 | WU-1 | 3 | ACCEPTED: `LineIndex.apply` clamps out-of-range edits rather than trapping | REQUIREMENTS.md says scanning is total — no throws, no error path. An edit arriving from a text view that has already mutated is a real, survivable race. Garbage in, garbage out, but never a crash. |
| DL-17 | 2026-07-25 | WU-1 | 4 | Model: opus | Complexity 23. The convergence engine is the highest-risk algorithm in the package and every grammar depends on its lookahead contract. |
| DL-8 | 2026-07-25 | WU-1 | 2 | Model: opus | Complexity 21. Override also applies. The span/record model is the scanner→editor seam; the plan states plainly that a wrong answer here is rework in every later sortie. |
| DL-18 | 2026-07-25 | WU-1 | 4 | ~~Sortie 4 RE-DISPATCHED at attempt 1~~ **RETRACTED — the liveness verification behind this decision was WRONG. See DL-19.** | Original (incorrect) reasoning, preserved for the brief: "The first supervisor session ended before the Sortie 4 agent returned. On resume: `TaskList` empty, no `claude` process older than the new session, no stranded build, working tree clean at `40e98a9`. The agent produced nothing." Every one of those observations was true and the conclusion drawn from them was still false. |
| DL-X1 | 2026-07-25 | WU-1 | 4 | CLEARED (supervisor's own DL-15 flag withdrawn): `backwardExtent` defaulting to `max(1, lookahead)` is sound, not a conflation | The stand-down agent flagged, and the supervisor repeated, that folding `lookahead` into the backward rule looked like the coupling DL-15 warns about. Inspection says otherwise, and the coupling is *required*: if line L's classification depends on lines L+1…L+n, then an edit at line E can change the classification of lines E−n…E, so correct rescanning **must** start at least `n` lines back. `backwardExtent ≥ lookahead` is a soundness obligation, and the engine's `max(1, backwardExtent, lookahead)` is a defensive floor that repairs an unsound grammar declaration rather than an arbitrary merge. DL-15's actual concern — Sortie 3's **code-unit** widening (`\r\n` pairing) vs Sortie 4's **grammar-state** widening — remains correctly honored: they are separate functions in separate types (`LineIndex` vs `IncrementalScanner.backwardWidening`). No action needed; do not "fix" this in a later sortie. |
| DL-X2 | 2026-07-25 | WU-1 | 5 | Sortie 5 dispatch HELD by session `8380d2fe`, then MOOT — `d1a5e802` dispatched it first | The hold was the right instinct (never dispatch into a tree another live agent is touching) and it is what prevented a second Sortie 5 collision: while `8380d2fe` waited on transcript quiescence, `d1a5e802` dispatched Sortie 5 at 23:12. Had this session dispatched instead of waiting, two Sortie 5 agents would have been in one tree. See DL-X3. |
| DL-X3 | 2026-07-25 | — | — | **SPLIT BRAIN: two live supervisor sessions on one mission. Session `8380d2fe` STANDS DOWN. `d1a5e802` has the con.** | Root cause of everything from DL-18 onward — not "an agent died" but *two supervisors resumed the same mission in parallel*. Timeline: `a448d579` dispatched Sortie 4 at 22:47, ended 22:51:49. `d1a5e802` started 22:51:50 and **inherited the running agent's handle**, so it kept receiving that agent's notifications. `8380d2fe` started 22:52 with no handle, saw an empty task list plus a clean tree, and wrongly concluded the agent was dead (DL-18). Both then drove one branch: `27552ab`/`587bf80`/`17da8a6` are `8380d2fe`'s, `7aebb73` is `d1a5e802`'s, interleaved. Both also wrote this file concurrently, producing duplicate DL-20/DL-21 IDs — this session's are renamed to the `DL-X*` namespace so `d1a5e802`'s numbering stays authoritative. **Why `d1a5e802` keeps the con:** it holds live agent handles, so it polls via `TaskOutput` and gets completion notifications; `8380d2fe` can only infer from transcript mtimes. Handles beat inference. **Two supervisors are far more dangerous than two agents:** agents collide on files and one notices, whereas supervisors collide on state and dispatch decisions — and a duplicate dispatch into the WU-3/WU-4 parallel layer would put four agents in one tree with nobody aware. |
| DL-19 | 2026-07-25 | WU-1 | 4 | CORRECTION: the original Sortie 4 agent was ALIVE the whole time. Redundant re-dispatch stood down with zero footprint. | The incumbent is `agent-ade45006d96f0f850` in session `a448d579`, dispatched 22:47 (the Sortie 4 dispatch minute), transcript still being written at 23:02:51 and growing past 458 KB. It had simply read for ~12 minutes before its first write — EXECUTION_PLAN.md is 58 KB and REQUIREMENTS.md 45 KB. **Why the check failed:** (a) `TaskList` is per-session and cannot see another session's agents; (b) `ps` cannot see an agent that is between tool calls, because there is no long-lived per-agent process to find; (c) "clean tree at the dispatch commit" is satisfied identically by a dead agent and by a live one that has read but not yet written. Three independent signals, all consistent with death, none capable of detecting life. The re-dispatched agent caught this itself — its first `Write` was rejected because the incumbent had created that exact file seconds earlier — and it stood down without writing a single line rather than corrupt the tree. Correct call; it is credited with the catch, not charged with the redundancy. **Reliable liveness signal, adopted going forward:** mtime of the agent's own transcript at `~/.claude/projects/<project>/<session>/subagents/agent-<id>.jsonl`, cross-checked against source-tree mtimes. Never `ps`, never task lists across sessions, never a clean tree alone. |

---

| DL-20 | 2026-07-25 | WU-1 | 4 | ACCEPTED with a follow-up obligation: scanner entry points are **internal**, not public | REQUIREMENTS.md § What is public in 1.0 lists "the scanner entry points", so this appears to violate it. The agent's reasoning is sound and I checked it: `IncrementalScanner` is generic over `LineGrammar`, so making it public makes `LineGrammar` public, which requires an external conformer to construct a `LineState` — whose initializer is internal by design. Public scanner ⇒ public `LineState` ⇒ opacity gone. The correct public surface is a **non-generic `Language`-dispatching facade over an internal grammar**. **Sortie 5 must create it** — otherwise Sortie 30's audit finds no public scanner entry point at all and REQUIREMENTS.md goes unmet. Carried into Sortie 5's prompt as a hard exit obligation. |
| DL-21 | 2026-07-25 | WU-1 | 4 | ACCEPTED: `LineState` gained one internal field, `openConstruct: UInt16` | A grammar-defined tag; zero means nothing open. Without at least one field every `LineState` equals every other and a stateful test grammar is impossible. A scalar rather than a stack because one state is stored per line for the whole document, and an allocating field would put an allocation per line on the cheapest thing the scanner does. Sortie 5 may add named fields beside it. |
| DL-22 | 2026-07-25 | WU-1 | 4 | NOTED for Sortie 28: one `[UInt16]` allocation per line scanned | `GrammarLine` owns its content units. The bulk-read contract holds (one `copyUTF16CodeUnits` per line, never per code unit), but the array is a real allocation on the hot path. The agent chose clarity over a pooled ring buffer on the highest-risk algorithm in the package — the right call at this stage. **Sortie 28 must measure it**; if it bites, the fix is local to `grammarLine(at:in:)` and the window. |
| DL-23 | 2026-07-25 | WU-1 | 4 | RECORDED: convergence condition 3 is weaker than conditions 1 and 2 | The agent reported honestly that it could not construct a case where dropping the lookahead extension produces *wrong output* — only a wrong dirty-range extent — because output at lines ≥ k₀ is a function of `(state(k₀), text from k₀ on)`, both proved unchanged. It implemented the rule as REQUIREMENTS.md §5 and Fountain §4 mandate it anyway, as insurance against a grammar whose lookahead is not fully reflected in its state. Fountain's cue rule (Sortie 14) is the plausible candidate. If Sortie 14 finds a genuine output counterexample, the test to strengthen is `forwardConvergenceHonoursTheDeclaredLookahead`. |
| DL-24 | 2026-07-25 | WU-1 | 5 | Model: opus | Complexity 20; override applies (foundation_score 1, 25 dependents). First grammar through the seam — the marker/content role split and the fence-flag-in-`LineState` pattern set the template every later grammar copies. |

## Overall Status

- Sorties completed: 4 / 30 (Sorties 1–4 — all supervisor-verified)
- Sorties in flight: 0 (Sortie 5 PENDING, held per DL-21)
- Work units completed: 0 / 7 (WU-1 RUNNING at 5 of 6; WU-2…WU-7 gated)
- Blocked: none
