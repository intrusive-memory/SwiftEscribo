---
type: mission-brief
title: OPERATION FOUNTAIN SURGEON — Iteration 01 Brief
operation: OPERATION FOUNTAIN SURGEON
iteration: 1
mission_branch: mission/fountain-surgeon/01
starting_point_commit: 6b8c3ee3d07ad15afe5d6f44fe7c218db334585e
state: completed
updated: 2026-07-27
---

# Iteration 01 Brief — OPERATION FOUNTAIN SURGEON

**Mission:** Build SwiftEscribo's hand-written incremental Markdown/Fountain scanner and
TextKit 2 editor layer — the org's canonical Fountain parser — with no regex, no
dependencies, and a property-tested guarantee that incremental scanning equals full scanning.
**Branch:** `mission/fountain-surgeon/01`
**Starting Point Commit:** `6b8c3ee3d07ad15afe5d6f44fe7c218db334585e`
**Sorties Planned:** 30 (+3 added mid-mission by user amendment = 33)
**Sorties Completed:** 33
**Sorties Failed/Blocked:** 0 — no sortie reached FATAL; no work unit was ever BLOCKED
**Duration:** 8 dispatch rounds, 75 commits (39 sortie, 19 supervisor, 17 other), 49,344
insertions across 158 files — 13,779 lines of source, 33,245 lines of tests
**Outcome:** Complete
**Verdict:** `KEEP` — every work unit COMPLETED and independently re-verified by the
supervisor rather than accepted on report, zero tests pruned, and the mission's principal
weakness (plan-authored criteria that could not fail) is a *planning* defect already
captured in a committed errata document, not a defect in the code that shipped.
**Tests pruned:** 0
**Tests flagged for review:** 3 categories, none actionable today

---

## Terminology

> **Mission** — A definable, testable scope of work. **Sortie** — An atomic agent task within
> it. **Work Unit** — A grouping of sorties.

---

## Section 1: Hard Discoveries

### 1. A property test that compares an implementation against itself is blind to its own omissions

**What happened:** The mission's flagship gate — `incrementalScan == fullScan` over seeded
edit sequences — passed **288 of 288** cases against a Fountain grammar that recognized **no
character cues at all** (DL-96). It was demonstrated blind **seven** times (DL-25, DL-31,
DL-84, DL-96, DL-109, DL-126, DL-129). The same shape reappeared in a different domain: a
decode/encode round trip stayed green while **every voice was dropped from every cast member**
(DL-156).
**What was built to handle it:** A hostile-input fixture corpus with golden snapshots (Sortie
17), a `swift-markdown` differential oracle (Sortie 22), and — the sharpest fix — an oracle
built on `JSONSerialization`, Foundation's *own* parser rather than the model's, which took
the same probe from 3 issues to **38** (DL-161).
**Should we have known this?** **Yes, in principle.** "Both sides share the grammar" is
derivable from the property's own statement before writing a line of code. It was not
derived; it was discovered by breaking things.
**Carry forward:** Every property or round-trip test ships with a **written statement of what
it cannot see**, plus at least one literal-expected-value test covering that blind spot. The
boundary is now mapped precisely (DL-137): such a gate is blind to state **omission**, and
*not* blind to a state **equality** bug, because premature convergence makes incremental
differ from full — which is exactly what it measures.

### 2. Real files from the actual downstream consumer break the parser in ways the spec never suggests

**What happened:** Highland 2 writes an empty title-page value as a line containing **a lone
tab**. `FountainGrammar` read whitespace-only as blank, and blank ended the title page — so in
a genuine Highland export **only 2 of 9 title-page keys survived**, `CREDIT:` scanned as a
**character cue**, and the author, contact info and draft date became its **dialogue**
(DL-130). This is the org's own screenplay format, and Produciesta is the first embed.
**What was built to handle it:** A one-line fix (`isBlank` → `isEmpty`, inside the
title-page branch only), probe-proven in both directions (DL-147, DL-148) — but only after
the user amended three sorties into the plan to own it, because **no sortie did** (DL-144).
**Should we have known this?** **Yes.** Vendoring one real Highland export in the first work
unit would have surfaced it at Sortie 1 instead of Sortie 17. It shipped undetected through
**17 sorties**.
**Carry forward:** **Vendor real files from the real consumer in work unit one**, before any
grammar rule is written. A spec describes the format; a real file describes the exporter.

### 3. Concurrent `xcodebuild test` runs hang at 0% CPU and truncate silently — they do not merely slow down

**What happened:** Two runs against the same scheme and DerivedData produce a **42-minute
hang at 0.0% CPU** that never resolves (DL-134) — it burns an agent's whole budget *while
reading as progress*. Separately, a concurrent run **truncated at 50 of 181 tests with no
recorded issue** (DL-103): it reads as a pass.
**What was built to handle it:** Concurrency dropped 3 → 2 → **1**, and the standing rule
that **every green claim is paired with a test count**.
**Should we have known this?** **No.** This is machine-specific behavior not documented
anywhere; it had to be measured.
**Carry forward:** Start at concurrency 1. Raise only on evidence, never on a dependency
graph. **A truncated *failing* run is worse than a truncated passing one** — it would send a
healthy sortie into a needless retry.

### 4. `make test` hangs in font resolution, on a clean tree, and CI had no timeout

**What happened:** Every test worker blocks in `+[NSFont fontWithName:size:]` awaiting an
idle `fontd`. Reproduced on the **clean tree before any mission code existed**, then twice by
the Sortie 28 agent and **once by the supervisor during verification** — killed at 10 minutes,
green in 14 seconds on the immediate re-run (DL-61 → DL-180). `tests.yml` declared **no
`timeout-minutes`**, so a hang would consume the GitHub Actions default of **six hours per
job** rather than failing.
**What was built to handle it:** `timeout-minutes` on all three CI jobs (15/30/45), Sortie 29.
**Should we have known this?** **No** for the hang; **yes** for the missing timeout, which is
a one-line hygiene item that should be in every workflow from the start.
**Carry forward:** Every CI job declares `timeout-minutes` on day one. **A hang is strictly
worse than a failure in a gating job.**

### 5. SwiftPM prunes a test-only dependency as a graph property, not a declaration

**What happened:** Adding `swift-markdown` for the differential oracle is safe *only* while no
shipping target imports it. The day one does, CommonMark becomes a transitive dependency of
every consumer of the Fountain parser — **silently, with no build error** (D-2, SPM#7007).
**What was built to handle it:** A `no_markdown_import_in_sources` SwiftLint rule — which was
**documentation for seven sorties**, because `make lint` ran a formatter and no CI job ran any
rule (DL-4). Closed at Sortie 29 and proven end to end by the supervisor: `import Markdown` in
a shipping target makes `make lint` exit 2 (DL-184).
**Carry forward:** A charter guarantee enforced by a rule nothing runs is not enforced. **Wire
the enforcement in the same sortie that declares the rule.**

### 6. Debug timings describe the compiler, not the code

**What happened:** The first performance run was Debug: cold scan **48 ms** (squeaking under
the 50 ms ceiling by 4%) and in-line edit **1.08 ms** — *over budget*. A ~10× `-Onone`
pessimism (DL-175). The plan specified budgets but not a configuration.
**Carry forward:** A timing budget without a stated build configuration is not a budget.
Assert the configuration **before reading a clock** — Sortie 30 does this via
`_isDebugAssertConfiguration()`.

### 7. The scanner was never the bottleneck

**What happened:** Measured at Sortie 28 (DL-179): an incremental in-line edit on 128 KB costs
**0.026 ms of a 1 ms budget**; a cold full scan is **5.2 ms against a 50 ms ceiling**. The
`NSAttributedString.string` bridge in the binding push — mandated by REQUIREMENTS.md's
`@Binding var text: String` — costs **0.522 ms per keystroke, 21× the scan and 52% of the
whole budget**.
**Should we have known this?** **Partly.** That a full-document `String` bridge per keystroke
is O(document) is knowable by inspection; nobody priced it until the plan's last-but-two
sortie.
**Carry forward:** This does **not** mean the incremental scanner was wrong to build —
correctness while typing was the requirement, not speed. But **if 1.0 needs headroom, it is
an architecture question about the `String` binding**, not a scanner question. Price the
mandated data flow *before* optimizing the interesting algorithm.

---

## Section 2: Process Discoveries

### What the Agents Did Right

#### 1. Agents caught their own unfalsifiable exit criteria — six times

**What happened:** DL-105, DL-124, DL-128, DL-155, DL-164, and Sortie 24's own four. The
strongest instance: Sortie 23 didn't *argue* that its three criteria were satisfied by the
identity function — it **implemented the copy-the-source writer and ran it** (DL-164). Sortie
30 found that the audit's own criterion was satisfied by a pre-existing file that never named
`FountainWriter`, meaning the package **would have shipped with its second public entry point
marked `internal` and every gate green** (DL-189).
**Right or wrong?** Right, and it is the single most valuable behavior of this mission.
**Evidence:** 17 unfalsifiable criteria found; **6 found by the agent being graded by them**.
**Carry forward:** It happened because dispatch orders explicitly asked for mutation testing
and for honest reporting of probes that *don't* fire. Keep that language verbatim.

#### 2. Sortie-to-sortie handoffs caught things no plan could

**What happened:** Sortie 14 warned Sortie 15 that giving notes their own `ElementKind` would
drop them into `withState`'s "everything else" branch and close the dialogue block — breaking
the very criterion Sortie 15 had to satisfy, **which would otherwise have passed for free**.
Sortie 15 did it deliberately and mutation-tested it (DL-110).
**Carry forward:** A criterion that would have been vacuously satisfied became load-bearing
because one sortie wrote down what the next needed to know. Budget for the handoff note.

#### 3. Agents refused to report measurements they could not trust — twice

**What happened:** One discarded a benchmark taken while the supervisor mutated the tree
underneath it (DL-160); another flagged a contaminated run rather than reporting the number
(DL-140). A third reported honestly that its own mutation **did not fire**, and the finding
turned out to be the opposite of a gap — redundant malformed-recovery worth knowing about
before someone "simplifies" a guard away (DL-119).
**Carry forward:** This is downstream of the same prompt language. Reward the null result.

#### 4. An agent corrected the supervisor, on the supervisor's own probe

**What happened:** DL-173 claimed the one-word DL-170 fix would eat "a transition-led
screenplay", using `FADE OUT:`. Sortie 30 pointed out `FADE OUT:` **is not a transition in
this grammar** — Fountain 1.1 requires a literal `TO:` ending — and pinned `CUT TO:` instead.
The supervisor re-measured: both documents become a title page under the fix, so the
conclusion **stood and was understated**, and the example was wrong (DL-190).
**Carry forward:** The falsification standard has to run in both directions or it is just
supervision.

### What the Agents Did Wrong

#### 5. Very little, and the two real items were environmental or supervisor-caused

**What happened:** One sortie stopped early after backgrounding a `make test` that had hung
(DL-135) — ruled PARTIAL, not FAILURE, because real work existed on disk; it was defeated by
the environment. One sortie ran `make lint`, which is a **repo-wide write**, and its cleanup
destroyed ~227 lines of the supervisor's uncommitted state file (DL-123) — but it **reported
this plainly and unprompted and saved a recoverable stash**, which is the only reason the
audit trail survived at all.
**Evidence:** 0 FATAL sorties, 0 BLOCKED work units, every sortie completed on attempt 1 of 3.
Two PARTIAL→continuation cycles, neither incrementing the retry counter, both correct rulings.
**Carry forward:** Forbid `make lint` (now `make format`) during any dispatch.

### What the Planner Did Wrong

#### 6. Exit criteria were authored against an imagined implementation — 17 of them could not fail

**What happened:** The dominant defect of this mission, at roughly **one per two sorties**.
Root cause named at DL-100 and never contradicted afterwards: *criteria written before the
code they grade*. The family includes bare literal greps that punish documenting the thing
they forbid (DL-46, DL-59), a criterion describing **a document that cannot exist** (DL-86),
one that measured **Foundation rather than this package** (DL-124), one that was outright
**unsatisfiable** and would have read as a writer bug forever (DL-165), and — the last one —
a numeric threshold set at exactly the theoretical value, making it **a coin flip on noise**
(DL-178, the only one that was too *tight*).
**Right or wrong?** Wrong, consistently, and it is the finding that most justifies a different
approach next time.
**Evidence:** 17 instances across 33 sorties. Every one was caught, but by the sortie being
graded, not by the plan.
**Carry forward:** **Pair every exit criterion with the degenerate implementation that would
also satisfy it. If you cannot name one, the criterion is not finished.** Write criteria after
a spike, not before. Never use a bare literal grep over a source tree; assert the absence of
the *call*, not the *token*. Give every numeric threshold a stated tolerance **and** a stated
sensitivity ("what does the broken version read?").

#### 7. The plan's parallelism analysis was theory, and reality overruled it twice

**What happened:** Group C promised 3-way concurrency. Measurement gave hangs and silent
truncation; concurrency ended at **1** (DL-132, DL-134). The plan's dependency *edges* were
right; the *shape* they produced was not — Group B turned out serial in its tail (DL-114).
**Evidence:** Cost of serializing was near zero, because the binding chain was serial anyway.
**Carry forward:** A plan proposes parallelism; the **cap is an operational decision made
against the machine.**

#### 8. Flagged-but-unowned blockers get resolved at the last possible moment, or never

**What happened:** **DL-4** was recorded at **Sortie 1** — `make lint` ran a formatter, not a
linter, while the plan required CI to gate on it — and nothing forced resolution until Sortie
**29**, whose criteria could not be met without it. **DL-130** shipped a real defect for **17
sorties** and was only owned when the *user* amended the plan (DL-144).
**Carry forward:** **Every flag gets an owning sortie the day it is raised**, or it is not a
flag, it is a wish.

#### 9. The supervisor's own rules caused four of its twelve errors

**What happened:** "Stage only files you authored" is **unsatisfiable for a shared
append-only file two sorties must both edit**, and it put **two non-building commits** into
history (DL-98). Allowing `make lint` during parallel dispatch cost the state file (DL-123).
DL-149 was recorded, given a catcher, and then **left out of the dispatch order**, so an opus
agent rediscovered it (DL-172). And one supervisor *suggestion* was wrong and had to be
measured before it became an order (DL-185).
**Carry forward:** **A supervisor rule is a change to the system and needs the same
falsification as a code change.** Also: a file boundary narrow enough to keep sorties disjoint
can be narrow enough to **force the wrong fix** — when a boundary blocks the proportionate
remedy, say "report it and stop" rather than leaving the agent to work around it.

---

## Section 3: Open Decisions

### 1. Does 1.0 fix the empty *first* title-page key? (DL-149 / DL-170 / DL-173)

**Why it matters:** A Highland export whose **TITLE is empty** loses its entire title page —
the same class as DL-130, one row up. Probability is low (Highland writes TITLE first and it
is normally populated) but the failure is total.
**Options:** **(A)** Fix it — one word in `FountainGrammar.opensTitlePage`. **(B)** Ship the
limitation, documented, with the two tripwire tests that already pin it.
**Recommendation:** **Not (A) as-is.** The supervisor measured that the one-word fix makes
`CUT TO:\n\t\nThe end.\n` — a **real transition** at document start — scan as a title page and
swallow the line below it as a title-page value, and **nothing in 318 core tests asserts
that**. If you take (A), the transition-above-whitespace assertion goes in **first**. Given
1.0 timing, (B) with the tripwires is defensible.

### 2. Does `EscriboProject` fix the `episodes:` decode-side data loss? (DL-151)

**Why it matters:** **Live data loss in shipping code**, pre-existing in `SwiftProyecto` and
verified in fixture bytes: a top-level `episodes:` with no `season:` is silently discarded on
decode. `confessions-PROJECT.md` carries `episodes: 69`; the 69 is lost on any write-back.
**Three of four vendored fixtures are in this shape.**
**Options:** **(A)** Synthesize a season on decode. **(B)** Preserve `episodes` as an unknown
key. **(C)** Document and leave.
**Recommendation:** This is a **behavior change, not a bug fix** — a real file could depend on
the current shape — which is why no agent took it. It is now pinned by a test asserting the
loss on all four reachable surfaces. **Your call; (B) is the least surprising.**

### 3. Do the `inclusive_language` renames happen before 1.0?

**Why it matters:** 9 warnings in `EscriboProject`, and **four are public parameter labels**
(`resolvedIntroFile`, `resolvedOutroFile`, `resolvedIntroOutroAssets`). Renaming public API
after 1.0 is a **major release** under this package's semver commitments; renaming before is
free.
**Recommendation:** **Do it now or accept it for the life of 1.x.** There is no cheap third
option later.

### 4. Branch protection does not require the new lint check (DL-188)

**Why it matters:** The `Lint / SwiftLint` job gates its own workflow but is **not** in
`required_status_checks.contexts`, so it does not block a merge. The charter guarantee it
enforces is therefore advisory at the PR level.
**Recommendation:** Add it — `gh api --method PUT repos/OWNER/REPO/branches/BRANCH/protection`.
**No sortie can do this**; it is a repo setting. Do **not** add the performance workflow,
which is deliberately not PR-triggered.

### 5. `swift format` and SwiftLint disagree about `opening_brace`

**Why it matters:** 27 warnings that **cannot be fixed** — `make format` reverts any fix on
the next run. Turning on `--strict` requires clearing 50 warnings first, and this is 27 of
them.
**Recommendation:** Change one tool's config. Until then the warnings are permanent noise, and
permanent noise is how a lint gate stops being read.

---

## Section 4: Sortie Accuracy

Every sortie completed on **attempt 1 of 3**. No FATAL, no BLOCKED. Two PARTIAL→continuation
cycles, neither incrementing a retry counter. Full per-sortie detail is in
`SUPERVISOR_STATE.md`; this table covers only the notable entries.

| Sortie | Task | Model | Attempts | Accurate? | Notes |
|--------|------|-------|----------|-----------|-------|
| 1–6 | Core substrate | opus | 1 | Yes | Established the vocabulary 29 later sorties consumed; none of it was rewritten |
| 10, 11 | macOS/iOS text views | **sonnet** | 1 | Yes | First non-opus dispatches; both held (DL-60, DL-66) |
| 13 | Fountain vocabulary | opus | 1 (PARTIAL→cont.) | Yes | Broke a `SwiftEscriboTests` test its own criteria could not see — origin of the "run all three targets" rule (DL-87) |
| 14 | Cue lookahead | opus | 1 | **Exceptionally** | Produced the mission's headline result (DL-96) *and* the handoff that saved Sortie 15 (DL-110) |
| 16 | GLOSA | **sonnet** | 1 | Yes | Complexity 11; hand-computed expected offsets with an external script rather than pasting scanner output (DL-118) |
| 17 | Hostile corpus | opus | 1 | **Exceptionally** | Vendored the real Highland export that exposed DL-130, the mission's worst defect |
| 19 | Markdown inline | opus | 1 | Yes, with a caveat | Two of its commits **do not build in isolation** — caused by a supervisor rule (DL-98/DL-99) |
| 21 | Fountain-in-Markdown | opus | 1 | Yes | Discharged the longest-standing warning (DL-112) with a real second field, not a packing scheme |
| 23 | Writer body | opus | 1 | **Exceptionally** | Implemented the degenerate writer to *prove* its own criteria were vacuous (DL-164) |
| 24 | Title-page writer | opus | 1 | Yes | Discharged DL-111 without widening `LineRecord`; rediscovered DL-149 because of a supervisor omission (DL-172) |
| 27 | Editor geometry | sonnet | 1 (PARTIAL→cont.) | Yes | Defeated by the environment, not by the task (DL-134/DL-135); one commit carries a probe artifact (DL-143) |
| 28 | Performance | opus | 1 | **Exceptionally** | Caught that Debug numbers are meaningless, and produced the mission's most consequential measurement (DL-179) |
| 30 | API audit | opus | 1 | **Exceptionally** | 0 demotions — and found the audit's own criterion vacuous in a way that would have shipped a broken public surface (DL-189) |
| 31–33 | Title-page repair (user amendment) | opus | 1 | Yes | Fixed DL-130 in **one line**, probe-proven both directions; found DL-151 in live code |

**Zero sorties were inaccurate** by the standard definition — no sortie's output was later
reverted, deleted, or rendered moot. The three commits that do not represent intended state
(`fd34bed`, `632887e`, `57df2a1`) are artifacts of a supervisor rule and a probe, not of
sortie error.

---

## Section 5: Harvest Summary

What we know now that we did not know before: **a test that compares an implementation
against itself certifies nothing about what that implementation never records**, and this
mission proved it seven times in the scanner and once more in an unrelated data model — the
flagship property test would have shipped a Fountain grammar with no character cues at all.
Everything else follows from that: the fixture corpus, the differential oracle, and the
independent-parser oracle exist because the property could not be trusted alone. The second
thing we know is that **the scanner was never the performance bottleneck** — it uses 5% of
the per-keystroke budget while the mandated `String` binding uses 52% — so the next
performance conversation is about the editor's data flow, not the algorithm. **Test cleanup
pruned nothing**: all twelve CI-hazard patterns returned zero across 48 files and 571 test
cases, because the mission's own standing rules (seeded generators, no hardcoded paths, no
bare `Date()`) excluded them by construction rather than after the fact — the one genuine CI
hazard, the `fontd` hang, is invisible to all twelve patterns and was mitigated with a
workflow timeout, not a deletion. **The single most important change for any next iteration
is not in the code: it is that exit criteria must be written against a real implementation and
paired with the degenerate version that would also pass them.** Seventeen could not fail, and
every one was caught by the sortie it was grading rather than by the plan that wrote it.

---

## Section 6: Files

**Preserve (read-only reference for any next iteration):**

| File | Branch | Why |
|------|--------|-----|
| `FOUNTAIN_SURGEON_01_ERRATA.md` | `mission/fountain-surgeon/01` | The disagreement register. Written at the user's request specifically so a re-implementation would not need the branch. **This is the file that makes a rollback survivable.** |
| `SUPERVISOR_STATE.md` | same | 190 Decisions Log entries — the authoritative record every DL number in this brief points into |
| `TEST_CLEANUP_REPORT.md` | same | Evidence for zero prunes, plus the `fontd` hazard analysis |
| `Tests/EscriboCoreTests/Fixtures/` | same | **The vendored Highland exports.** These found DL-130 and DL-151. Re-deriving them means re-exporting from Highland; keeping them costs nothing |
| `EXECUTION_PLAN.md` | same | Its D-sections (design decisions) held up; its *test* wording did not. Both are instructive |

**Discard (would not exist after a rollback):**

| File | Why it's safe to lose |
|------|----------------------|
| — | **Nothing is proposed for discard.** The verdict is `KEEP`; this table is intentionally empty |

---

## Iteration Metadata

**Starting point commit:** `6b8c3ee3d07ad15afe5d6f44fe7c218db334585e` (pre-mission tip)
**Mission branch:** `mission/fountain-surgeon/01`
**Final commit on mission branch:** `d593b28` (test-cleanup report; last code commit `8c85565`)
**Rollback target:** `6b8c3ee3d07ad15afe5d6f44fe7c218db334585e`
**Next iteration branch (if ever needed):** `mission/fountain-surgeon/02`

---

## Rollback Verdict

**Verdict:** `KEEP`

**Reasoning:** Every signal the rubric weighs toward `KEEP` is present and was independently
confirmed rather than reported: **8 of 8 work units COMPLETED**, **0 FATAL**, **0 BLOCKED**,
every sortie done on attempt 1 of 3, and **0 tests pruned** against a threshold of 10%. The
tree is green on six gates at the tip — build, lint, core 318/31, macOS 179/28 + 48/11 +
318/31, iOS 160/25 + 48/11 + 318/31, performance 13/6 — all re-run by the supervisor on a
quiet machine. The rubric's `ROLLBACK` conditions are absent: no work unit was blocked, no
fundamental misunderstanding of the spec emerged, and Section 2's planner-wrong items do not
outweigh Section 2's agents-right items. Section 1 lists **seven** hard discoveries where the
rubric's `KEEP` row expects ≤1 — but each was *found, fixed, and probe-verified inside this
mission*, which is the opposite of accumulating a bad foundation, and the code that resulted
was falsified at every gate by roughly 35 supervisor probes and dozens of agent mutations, all
reverted with the tree clean after each.

**On the skill's honest default** (err toward `ROLLBACK` on iterations 1–2 because bad
foundation is expensive): that default guards against a foundation nobody checked. This
foundation was checked adversarially at every step, including three probes that fired against
work the supervisor had already been told was fine. **The dominant defect of this mission —
17 exit criteria that could not fail — is a defect in how the plan was *written*, not in what
was *built*; the code that shipped was, in every one of those 17 cases, strengthened by the
discovery.** Rolling back would discard 33 verified sorties to re-derive knowledge that is
already written down in `FOUNTAIN_SURGEON_01_ERRATA.md`. **The learnings do not require the
rollback to be applied** — that is precisely what the errata document was built for.

**Recommended action — `KEEP`. Merge the mission branch, with these follow-ups:**

1. **Before merge**, consider `git rebase -i` / squash to repair three commits that do not
   represent intended state (`fd34bed`, `632887e`, `57df2a1` — DL-99, DL-143). `git bisect`
   cannot be trusted across them. Cosmetic; the tip is correct.
2. **Repo setting, no sortie can do it:** add `Lint / SwiftLint` to branch protection's
   `required_status_checks.contexts` (DL-188).
3. **Decide the four open items** in Section 3 — the two data-loss questions (DL-170,
   DL-151) and the `inclusive_language` renames, which are free now and a major release later.
4. **If a future iteration 02 is ever run** (for scope, not for rollback), its `breakdown`
   must take `FOUNTAIN_SURGEON_01_ERRATA.md` § 0 and § 8 as direct input, and its `refine`
   pass must add a gate that no exit criterion ships without a named degenerate
   implementation.

---

*Rendered by the Mission Supervisor. Every DL reference points into `SUPERVISOR_STATE.md`.
Every test count in this brief was produced by the supervisor re-running the gate, not by an
agent reporting it.*
