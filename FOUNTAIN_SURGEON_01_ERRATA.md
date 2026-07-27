---
type: mission-errata
title: OPERATION FOUNTAIN SURGEON — Disagreement Register and Errata
operation: OPERATION FOUNTAIN SURGEON
iteration: 1
mission_branch: mission/fountain-surgeon/01
starting_point_commit: 6b8c3ee3d07ad15afe5d6f44fe7c218db334585e
state: in-progress
updated: 2026-07-27
---

# Disagreement Register and Errata — OPERATION FOUNTAIN SURGEON, iteration 1

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria,
> and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous agent in
> one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

## What this document is, and why it exists separately from the brief

The user has asked for every **disagreement** in this mission to be recorded, on the
explicit premise that **the branch may be rolled back to zero and re-implemented with
these learnings**. That premise changes what is worth writing down. A post-mission brief
asks "was this work good?"; this document asks **"if we threw the code away and kept only
this file, what would we need to know?"**

So it is organized by *disagreement*, not by sortie. A disagreement is any place where two
sources of truth said different things: the plan versus the code, one agent versus another,
an agent versus the supervisor, the requirements versus what is buildable, or the plan's
assumptions versus what this machine actually does. Each entry states **what was claimed,
what was true, how it was settled, and what a re-implementation should do instead.**

`SUPERVISOR_STATE.md` remains the authoritative Decisions Log; every `DL-n` here points
into it. This file is the *index of conflicts* and the errata, nothing else.

**Status when written**: 31 of 33 sorties complete, all supervisor-verified. Sortie 28 in
flight; 29 and 30 remain. Tree green at `a72b1f3`: core **314/30**, macOS **179/28 + 44/10
+ 314/30**, iOS **160/25 + 44/10 + 314/30**.

---

## 0. The five findings that would change a re-implementation most

If nothing else survives, these five do.

**1. Exit criteria written before the implementation exists are unfalsifiable at a rate of
roughly one per two sorties.** The mission's own running tally reached **13** by DL-164 and
kept going. Every one has the same root cause, named at DL-100: *criteria authored against
an imagined implementation rather than a real one*. Six were caught by the agent whose work
they graded (DL-105, DL-124, DL-128, DL-155, DL-164 and Sortie 24's own four), which is the
single strongest process signal in this mission — but they were caught **after** the work,
and a criterion that cannot fail cannot steer the work it was written to steer.
**Re-implementation rule: every exit criterion must be paired with the degenerate
implementation that would also satisfy it. If the author cannot name one, they have not
finished writing the criterion.** See §1.

**2. A property test can be green against a completely broken implementation, and this
mission proved it seven times.** The flagship `incrementalScan == fullScan` gate passed
288/288 against a Fountain grammar that recognized **no character cues at all** (DL-96).
The reason is structural and generalizes far beyond this package: **both sides of the
comparison run the same grammar, so a fact the grammar never records is missing from both
and they agree.** The same shape reappeared in a different domain at DL-156 — a
decode/encode round trip is blind to decode-side data loss, because both sides pass through
the same decoder. **A self-consistent wrong answer round-trips perfectly.** The boundary was
finally mapped at DL-137: the gate *is* sensitive to a state **equality** bug (premature
convergence makes incremental differ from full), and blind to state **omission**.
**Re-implementation rule: every property test ships with a stated blind spot and at least
one literal-expected-value test covering it.** See §2.

**3. Two-way parallelism cost more than it bought, on measured evidence, and was withdrawn
twice.** The plan's parallelism analysis was theoretical. Reality: concurrent `xcodebuild
test` runs against one scheme and DerivedData **hang at 0% CPU indefinitely** rather than
slowing down (DL-132, DL-134) — one hang burned 42 minutes and killed a sortie — and
concurrent runs also **truncate silently**, reporting a pass after running 50 of 181 tests
(DL-103). Concurrency went 2 → 1 and stayed there. The measured cost of serializing was
near zero, because the critical chain was serial by construction anyway.
**Re-implementation rule: concurrency 1 unless a specific pair is proven disjoint *and*
does not share a build scheme; pair every green claim with a test count.** See §5.

**4. The supervisor's own bookkeeping was the source of four distinct failures**, three of
which cost real agent budget (DL-82, DL-98, DL-123, DL-140, DL-150, DL-160, DL-172). The
worst was a *rule the supervisor invented* — "stage only files you authored" — which was
**unsatisfiable for a shared append-only file** and put two non-building commits into
history (DL-98). **A supervisor rule is a change to the system and deserves the same
falsification standard as a code change.** See §4.

**5. The single highest-impact defect in the product was found by vendoring a real file,
not by any test written against the specification.** DL-130: Highland 2 writes an empty
title-page value as a line containing **a lone tab**; the scanner read whitespace-only as
blank, blank ended the title page, and so **2 of 9 title-page keys survived** in this org's
own screenplays — `CREDIT:` became a character cue and the author, contact info and draft
date became its dialogue. Nothing in the plan owned it. It was fixed by **one line** once
someone owned it (DL-147). **Re-implementation rule: vendor real files from the actual
downstream consumer in the first work unit, not the third.** See §6.

---

## 1. Disagreements between the plan and reality — unfalsifiable and unsatisfiable criteria

This is the largest class by count and the most portable lesson. Each row is a place where
**the execution plan asserted a test that could not do its job.**

| # | DL | Sortie | The criterion as written | Why it could not fail | Resolution |
|---|----|--------|--------------------------|------------------------|-----------|
| 1 | DL-31 | 6 | "Returning after one converged line with no lookahead turns the gate red" | Output past the converged line is a function of `(state, text)`, both proved unchanged — so the un-repainted lines were *already correct*. A painted-document comparison cannot see it. | Met in substance, not as written. Supervisor proved the gate **is** falsifiable by a different break (`backwardWidening = 0` → 272 issues). |
| 2 | DL-46 | 8 | `grep -rE '(leftIndent\|headIndent\|firstLineHeadIndent)[A-Za-z]*: *[0-9.]+'` | Also matches `leftIndentChars: 10` — a **character** constant, which Sortie 27 is *required* to write. Passed only because the tables were empty. | Recorded as a plan defect; correct standing form identified (assert the only writes to those four `NSParagraphStyle` properties live in one function). Never promoted to an invariant. |
| 3 | DL-59 | 9 | `grep -rn 'setAttributedString' Sources/SwiftEscribo/` | A bare literal grep cannot distinguish a call from a **comment warning about the call**. The agent had to reword the doc comment explaining the prohibition so it did not trip the check on the prohibition. | Intent met. Lesson: assert the absence of the *call*, not the *token*. Same family as #2. |
| 4 | DL-72 | 12 | "Rule 3: selection clamping" | The test credited this package for work **AppKit was doing anyway**. Deleting the clamp entirely left it green. | Ruled PARTIAL; remedy written and then re-probed by the supervisor (DL-78), which fired where it should. |
| 5 | DL-86 | 18 | "An emoji before an indent marker" | Describes **a document that cannot exist** — in CommonMark, indentation precedes content by definition. | Agent said so rather than faking it. Ruled met in substance. |
| 6 | DL-100a | 19 | The `dirtyRange` criterion | Dirty ranges are line-aligned by Sortie 6's invariant, so *any* edit on the line already covers the former bold run. | Assertion with teeth added. |
| 7 | DL-100b | 19 | Half the surrogate-pair criterion | `SpanTiling.align` snaps every boundary off a pair for **any** grammar. Proved by mutation: property test stayed green while the hand-written test went red. | Assertion with teeth added. |
| 8 | DL-105 | 20 | "`---` on line 5 is a thematic break" | Sortie 18 already shipped that behavior, so it stays green **with Sortie 20's implementation deleted**. | Agent flagged its own criterion; replaced with an assertion that no frontmatter span or record exists anywhere. |
| 9 | DL-124 | 25 | "One undo action" asserted as `canUndo == false` after one `undo()` | Measured **Foundation, not this package**. `UndoManager.groupsByEvent` closes its group from a run-loop observer; a unit test never spins the run loop, so everything since `removeAllActions()` was one group. Green for any implementation. | Two fixes, both required: `settleEventGroup()` spins the run loop; assertions count **undo registrations** via a `CountingUndoManager`. |
| 10 | DL-128 | 26 | "Return on a character cue produces a dialogue line with no intervening blank line" | Green against **zero implementation** — a cue opens a dialogue block and a newline does not close it, so plain `insertNewline` satisfies every row. | Documented decline. Mitigation (an explicit switch per row) verified by supervisor probe: falsifiable against a *wrong* implementation even though vacuous against a *no-op*. |
| 11 | DL-152 | 32/33 | `decode(encode(decode(x))) == decode(x)` | `encode(to:)` stamps `schemaVersion: 4` unconditionally, so it is **false for every legacy fixture** for reasons unrelated to data loss. | Criteria amended before Sortie 33 was dispatched. |
| 12 | DL-155 | 33 | A gate written with `==` on `ProjectFrontMatter` | `CastMember.==` compares **character names only**. Two front matters that lost every actor, gender, voice and unknown key compare **equal**. | Caught by the agent in its own draft; field-by-field comparator built, plus a `ComparatorSelfTests` suite that mutates each of seven fields and requires the comparator to notice. |
| 13 | DL-164 | 23 | All three of Sortie 23's exit criteria | **Satisfied by the identity function.** The agent did not argue this — it *implemented the copy-the-source writer and ran it*. | Normalization bundled into each gate document so identity now fails all three; probe fired 23 issues across 8 tests. |
| 14 | DL-165 | 24 | `parse(write(parse(x))) == parse(x)` | **Unsatisfiable.** A normalizing writer shifts every subsequent `range`, so record equality fails on any non-canonical document for reasons that have nothing to do with data loss. Taking it literally looks like a writer bug and is not one. | Amended **before dispatch** to a fixed point of the writer, compared as text. Two missing criteria added at the same time. |
| 15 | Sortie 24 report | 24 | Four of its own six criteria, as worded | Identity-satisfiable — including the fixed point itself, since **identity is trivially a fixed point and no formulation of that property can exclude it.** | Each test carries a companion assertion identity fails (`once != source`, byte-for-byte non-canonical inputs). The *pairing*, not the property, is what makes the gate able to fail. |

### What a re-implementation should do differently

- **Write criteria after a spike, not before.** Nine of the fifteen above are traceable to a
  criterion authored against an imagined API. The plan's own D-sections (design decisions)
  were good; its *test* wording was consistently ahead of the code.
- **Ban bare literal greps over a source tree as exit criteria** (#2, #3). Scope them, or
  assert the absence of the call rather than the token.
- **For every "X is preserved" criterion, name the mutation that would violate X** and
  require the sortie to run it. This is what finally worked — six agents caught their own
  vacuous criteria this way.
- **An idempotence or round-trip criterion needs a companion "the first application actually
  changed something" assertion.** Without it, identity passes (#13, #15).

---

## 2. Disagreements between a test's reputation and its actual reach

The gate blindness thread, in order. This is one long argument the mission had with itself
and eventually resolved precisely.

| DL | Claim under test | Result |
|----|------------------|--------|
| DL-25 | "The scan gate catches grammar bugs" | **False.** Breaking the fence flag reddened six classification tests; the gate stayed green. Both sides ran the same broken grammar. |
| DL-23 → DL-31 | "Convergence condition 3 (forward extension) is load-bearing" | Confirmed *weaker* than conditions 1–2. Dropping it produces a wrong dirty-range extent, not wrong output. Second blind spot. |
| DL-84 | State-omission probe on Sortie 13 | 4 tests red, gate green **224/224**. Third confirmation. |
| DL-96 | **A Fountain grammar recognizing no character cues at all** | **62 issues red, gate green 288/288.** The mission's headline result. The flagship property test would have certified a completely broken dialogue grammar. |
| DL-109 | Title-page region opening on any line | 2 tests red, gate green **352/352**. Fifth. |
| DL-126 | GLOSA attribute values emitted under the wrong span kind | 4 issues, gate green. Sixth. |
| DL-129 | Boneyard dropped from the cross-line state carry | 8 issues — including a **golden snapshot** — gate green. Seventh. **The fixture corpus caught what the gate structurally cannot**, which is the argument for having built it. |
| DL-137 | `NestedFountainState.==` always `true` | **22 issues, and the gate FIRED.** The boundary: blind to state *omission*, **not** blind to a state *equality* bug, because premature convergence makes incremental differ from full — which is exactly what the gate measures. |
| DL-156 | Same class, different domain: dropping every voice from every cast member on **decode** | 3 issues, and the corpus test *"Every field survives the round trip, including every unknown key"* **stayed green**. Only literal-expected-value tests caught it. |
| DL-161 | The fix for DL-156 | Independent oracle (`JSONSerialization` — Foundation's parser, not the model's) + hand-typed literals. Same probe now fires **38 issues across 9 tests**, up from 3 across 2. |
| DL-171 | An **idempotent** mutation against an idempotence gate (alphabetically sorting title-page keys) | Fixed-point gate structurally blind by construction; **38 issues across 11 ordinary assertions**. |

**The generalized rule this mission earned**: *a differential or round-trip test compares two
computations that share a component. It can only see errors in the parts they do not share.*
Write down what the shared component is, and cover it with literal expected values.

---

## 3. Disagreements between agents

Genuine technical conflicts between two sorties' conclusions. All were settled by
measurement, not by seniority.

### 3.1 DL-170 vs DL-149 — "one word" vs "a design decision" — **SETTLED, DL-173**

- **Sortie 31 (DL-149)** found that a document whose *first* title-page key has an empty
  value opens no title page at all, and **declined to fix it**, reasoning that with one line
  of lookahead `Title:` above a lone tab is indistinguishable from a transition above a lone
  tab — so widening the corroboration rule would turn ordinary transition-led screenplays
  into title pages.
- **Sortie 24 (DL-170)** rediscovered the same defect from the writer's side and called the
  fix "one word in `FountainGrammar.opensTitlePage`".
- **Settled by the supervisor, by measurement rather than argument (DL-173).** Applying the
  one word (`!isBlank(ahead.units)` → `!ahead.isEmpty`) fires **5 issues across 3 tests** —
  both tripwires and one gate document — and **no transition test fires, because none
  exists.** A throwaway probe confirmed the hazard is real: under the fix,
  `"FADE OUT:\n\t\nThe end.\n"` classifies line 0 as `titlePageKey`.
- **Verdict: both were right about different things.** It is one word *and* it is a design
  decision. **Errata: whoever fixes DL-170 must add the transition-above-whitespace
  assertion first**, or the fix silently trades a narrow defect for a wider one.

### 3.2 DL-122 vs DL-167 — the unordered-list defect was overstated — **SETTLED**

- **Sortie 25 (DL-122)** reported that tight lists misclassify in both flavors:
  `1. one`⏎`2. two` and `- item`⏎`- `.
- **Sortie 22 (DL-167)**, using an independent parser as oracle, confirmed the **ordered**
  half exactly and narrowed the **unordered** half: a tight bullet list of ordinary items
  classifies correctly; the defect needs an item with **no content**, where a lone `-`
  becomes a setext heading.
- **Verdict: DL-122's shape was inferred from two examples and one generalized further than
  the evidence supported.** Owner unchanged; repro now smaller and exact. **This is what the
  differential oracle was for** — and it is the only defect in the mission narrowed by an
  independent implementation rather than by reasoning.

### 3.3 DL-107 vs DL-166 — the named catcher could not catch — **SETTLED, obligation moved**

- **Sortie 20 (DL-107)** flagged GFM extended autolinks as unimplemented and named
  **Sortie 22's differential oracle** as the catcher, on the reasoning that `swift-markdown`
  implements GFM.
- **Sortie 22 (DL-166)** established that `swift-markdown` 0.8.0 attaches exactly three
  cmark-gfm extensions — table, strikethrough, tasklist — and **not** `autolink`. Both
  implementations share the gap and therefore agree across it.
- **Verdict: the catcher was named on a plausible assumption that turned out false.** The
  agent asserted the fact with a test that goes red if a future `swift-markdown` gains the
  extension, converting a silent blind spot into a dated one. **Errata: DL-107 is still
  open** and moved to Sortie 30 as a 1.0 limitation decision.
- **Generalized**: *"a later test will catch this" is itself a claim requiring verification.*
  Two of this mission's named catchers could not catch (this one, and DL-120→DL-131 where
  the wrapped-GLOSA gap turned out worse than described, not merely unfixed).

### 3.4 DL-33 — the agent contradicted the plan and was right

- Plan task 4 said the kind stage carries "color, font traits, **size scale**". DL-26 (from
  a prior sortie) required size to come from the line's `ElementKind`.
- The agent **resolved for DL-26 and deleted the field** rather than splitting the
  difference, moving size to `elementSizeScales: [ElementKind: [Int: Double]]`.
- **Verdict: the stronger design, and what REQUIREMENTS.md actually wanted.** A size scale
  hung off `SpanKind` is now *unrepresentable*, not merely discouraged — the same property
  the requirements already demanded for marker dimming, extended from markers to every span.
- **Generalized**: when a plan conflicts with an earlier ruling, the agent saying so beats
  the agent compromising. Three sorties did this correctly (DL-33, DL-50, DL-86).

### 3.5 DL-50 — the plan named the wrong API, for a reason no test could catch

- Plan said the font-family chain goes "through CoreText". **`CTFontCreateWithName` never
  fails** — handed an unknown name it substitutes silently, so a chain built on it always
  succeeds at its first entry and every fallback is unreachable.
- The agent used `PlatformFont(name:size:)` instead. **"CoreText does the measuring; it must
  not do the choosing."**
- **Verdict: the plan's instruction would have defeated its own design decision (D-4) in a
  way no test could observe**, because the substituted font is a real font.

---

## 4. Disagreements between the supervisor and reality — my own errors

Recorded against the supervisor, not the agents. Three cost real budget.

| DL | Error | Cost | Rule adopted |
|----|-------|------|--------------|
| DL-18/19 | Declared a sortie dead and re-dispatched it. **The original agent was alive the whole time.** `ps` cannot see an agent between tool calls; a clean tree is satisfied identically by a dead agent and a live one that has read but not written. | One redundant dispatch | Liveness = **mtime of the agent's own transcript**. Never `ps`, never a cross-session task list, never a clean tree alone. |
| DL-82 | Cleared two sorties as file-disjoint on an analysis that was **wrong**; parallel dispatch produced a mixed commit. | Mixed attribution | File-disjointness must be checked against the *shared vocabulary files*, not just the obvious directories. |
| DL-98 | **My own rule caused the worst commit damage in the mission.** "Stage only files you authored" is **unsatisfiable for a shared append-only file two sorties must both edit** — one agent worked around it with `git update-index --cacheinfo`, the next agent's whole-index commit swept the stale blob in, and **two commits do not build in isolation** (DL-99). | 2 unbuildable commits; `git bisect` cannot cross that window | Replacement: **never partially stage; add whole files; a shared vocabulary file may carry the other sortie's members; verify your own commit in a throwaway worktree.** Validated first outing, DL-104. |
| DL-123 | Allowed `make lint` during parallel dispatch. It is `swift format -i -r .` — **a repo-wide write.** An agent ran it, reverted what it did not own with `git checkout --`, and **destroyed ~227 lines of the supervisor's uncommitted state file.** | ~43 DL entries, partially recovered from a dangling stash the agent saved and reported | (1) **Commit `SUPERVISOR_STATE.md` at every gate** — it was the mission's only unversioned artifact and therefore the only one that could be lost. (2) `make lint` is per-sortie scoped or between-rounds only. |
| DL-140 | Dispatched a continuation **while the original agent was still alive**, because a task notification was read as termination. Two agents edited and committed the same sortie in one tree. | Ambiguous attribution (DL-141) | **A task notification means "stopped for now and resumable", not "terminated".** Confirm by process state. |
| DL-141 | Asserted an attribution I could not establish, to rebut an agent whose hypothesis was **most likely correct**. | Retracted | The mission's falsifiability standard binds the supervisor at least as tightly as the agents. |
| DL-150 | Agents cannot see which DL numbers are taken (they are forbidden the state file, correctly), and one collided. | Cosmetic; in-source label reads `DL-136` for what is really DL-149 | **Every dispatch order states the next free DL number.** |
| DL-160 | Applied DL-140's rule before *dispatch* but not before *probing* — mutated the tree while an agent's build was in flight. That agent correctly **discarded its measurement as void**. | One wasted measurement | The rule governs **any supervisor action that mutates the working tree**, not just dispatch. |
| DL-172 | DL-149 was recorded, given a catcher, and then **left out of the dispatch order**. An opus agent spent part of its budget rediscovering it as DL-170. | Partial budget; offset by gaining a pinned test DL-149 never had | **Before dispatching, grep the open-obligations list for the sortie's subject and paste every hit into the order.** |
| DL-142 | Piped a probe's output through `head -8` and read "2 tests fired" as a weak assertion. The true figure was **143 issues across 11 tests**. | Nearly a false finding | **Never truncate a probe's output — a probe measures how much fired.** |
| DL-53 | A probe applied with `sed` **silently failed to substitute**, producing an all-green run that read as a weak test. | Nearly a false finding | **A probe that reports no failures must be checked for having actually landed** before any conclusion is drawn. |

**The meta-lesson**: of eleven supervisor errors, **four were caused by rules the supervisor
itself invented** (DL-82, DL-98, DL-123, DL-172). Process changes are changes. They need the
same falsification discipline as code.

---

## 5. Disagreements between the plan's model of the machine and the machine

The execution plan's parallelism analysis was theoretical and is now **formally superseded
by measurement**.

| DL | The plan's assumption | What was measured |
|----|----------------------|-------------------|
| DL-103 | Concurrent test runs are slower | They **truncate silently** — one run reported a pass after 50 of 181 tests, with no recorded issue. A truncated *failing* run is worse still: it would send a healthy sortie into a needless BACKOFF. **Consequence: pair every green claim with a test count.** |
| DL-132 | 3-way parallelism is available in Group C | Three independent observations of **hangs, not slowdowns**: a 20-minute hang at 0% CPU; a supervisor probe build exceeding a 600 s timeout that finished in seconds on a quiet tree; and a suite failing with 10 then 74 issues purely from reading another sortie's uncommitted edits. 3-way declined. |
| DL-134 | 2-way parallelism is safe | **42-minute hang at 0.0% CPU, killed by the supervisor.** It burns an agent's entire budget *while reading as progress*. Concurrency dropped to **1** for the remainder. The measured cost was near zero — the critical chain was serial by construction. |
| DL-61 | (unstated) | **Pre-existing, environmental, and a real CI risk**: `make test` intermittently hangs in font resolution, every worker blocked in `+[NSFont fontWithName:size:]` awaiting an idle `fontd`. Reproduced on a **clean tree before any mission code was written**. With no `timeout-minutes`, a hang consumes the GitHub Actions default of **six hours** per job instead of failing fast. |
| DL-51 | (unstated) | A killed `xcodebuild` orphans an `xctest` agent that blocks the next run. Symptom: indefinite hang, no output. Fix: `pgrep -fl 'xcodebuild\|xctest'`, kill survivors. |
| DL-114 | Group B is parallel | **Fully gated**: 21 needs 17, 22 needs 21. Parallel for its first three pairs and **serial in its tail**. The plan's dependency graph was right about the edges and wrong about the shape they produce. |

**Re-implementation rule**: a plan may propose parallelism, but the *cap* is an operational
decision made against the machine, not a planning decision made against the graph. Start at
1 and raise it only on evidence.

---

## 6. Disagreements between the requirements and what shipped

Deliberate, documented deviations. None are accidental; all are recorded so a
re-implementation can decide differently on purpose.

**Behavior changed knowingly**
- **DL-27**: `contentRange` inside a fence keeps all leading indentation, deviating from
  CommonMark (which strips to the opening fence's indent) — chosen so the writer stays
  lossless. Correct trade for a package whose writer must round-trip.
- **DL-101**: five stated CommonMark deviations — emphasis does not cross a line; reference
  links scan as literal text (and are asserted so); flanking punctuation is ASCII-only (no
  Foundation for Unicode categories); hard breaks are emitted on a paragraph's last line
  where CommonMark says there is none; code spans deliberately get **no** `ElementKind`,
  because a `.codeSpan` kind would render inline code inside a heading at *body* size.
- **DL-106**: a document that is exactly `---` is now unterminated frontmatter, not a
  thematic break. **Live-editor consequence**: typing `---` as line 1 paints everything
  below as frontmatter until the closer is typed. Inherent to frontmatter support; reads as
  a bug in a demo.
- **DL-37**: static sRGB colors do **not** follow the macOS accent color or the
  increased-contrast accessibility setting the way `NSColor.labelColor` does. Accepted
  knowingly to keep appearance one of four *declared* invalidation triggers rather than an
  invisible mutation inside a dynamic system color.

**Limitations shipped, with owners**
- **DL-88**: setext underlines do not retro-classify the paragraph above them.
- **DL-89**: blockquote and list-item content is not re-scanned — `> # Title` is one
  blockquote line, not a heading inside a quote. Expressing containment needs a container
  axis on `LineRecord`.
- **DL-90**: list nesting saturates at 8 levels by design (the content-column stack is
  packed into one `UInt64` to avoid a per-line allocation).
- **DL-131**: a GLOSA directive **wrapped across a line break is destroyed, not merely
  unpaired** — the opener degrades to plain text and the continuation reads as note prose.
  A screenwriter who wraps a long directive silently loses it. Worse than DL-120 described.

---

## 7. ERRATA — open items a re-implementation or a 1.0 must decide

These are **not resolved**. They are the actionable residue of this mission.

### 7.1 Needs a human decision

| ID | Item | Why it needs a person |
|----|------|----------------------|
| **DL-170 / DL-149** | A title page whose **first** key has a Highland-style empty value opens no title page at all. | The one-word fix is real **and** carries the transition-led-screenplay hazard (DL-173). Requires deciding which failure mode is preferable, and adding the transition guard first either way. Currently **pinned by two tests meant to go red when it is fixed**. |
| **DL-151** | **Live data loss in shipping code**: a top-level `episodes:` with no `season:` is silently discarded on decode. Verified in fixture bytes — `confessions-PROJECT.md` carries `episodes: 69` and no `season:`; the 69 is lost on any write-back. **Three of four vendored fixtures are in this shape.** Pre-existing in `SwiftProyecto`, not introduced here. | Fixing it is a **behavior change**, not a bug fix — a file could rely on the current shape. |
| **DL-157** | `appSections` and `CastMember.extraKeys` are `internal` with **no public accessor**. Unknown keys are round-trippable but unreadable. | Small deliberate API addition; the extension providing typed access stayed in `SwiftProyecto` because the compiler never demanded it. |
| **DL-107** | GFM extended autolinks unimplemented, and the differential oracle **cannot** surface them (DL-166). | 1.0 scope decision. |

### 7.2 Known defects accepted, not repaired

- **DL-99**: commits `fd34bed` and `632887e` **do not build in isolation**; `0aecb21`
  repaired the tip. **`git bisect` cannot cross that window.**
- **DL-143**: `57df2a1` committed a falsification probe still applied (a geometry table
  failing its own doubling test); `26eafc8` removes it. **Third commit that does not
  represent intended state.** Fixed forward rather than amended, correctly, on a shared
  branch. **Squash at PR time if clean bisectability is wanted.**
- **DL-122 / DL-167**: tight-list misclassification in `MarkdownGrammar`, worked around in
  the editor layer. The workaround **self-retires** when the scanner is fixed.
- **DL-153**: `withCast(_:)` erases the last-updated date (omission, not policy).
- **DL-154**: `MergeStrategy.preserveExisting` and `.preferNew` are **line-for-line
  identical** despite being documented as opposites. No input can distinguish them.
- **DL-158**: `lingua-matra/PROJECT.md` **throws on decode** — it writes `languages:` as
  bare strings, which `[LanguageDefinition]` cannot decode. Not vendored, not fixed,
  recorded so it is not rediscovered as a mystery.
- **DL-22**: one `[UInt16]` allocation per line scanned, on the hot path. Sortie 28 is
  measuring it.

### 7.3 Bookkeeping errata

- **DL-150**: Sortie 31 labelled its new defect `DL-136` in source
  (`FountainRegionTests.swift:548,559`); DL-136 was already taken. The true ID is
  **DL-149**. The in-source label was left as-is rather than having the supervisor edit test
  code. **Sortie 30 should reconcile it.**
- **DL-139**: `MarkdownGrammar`'s **type-level** doc still says "lookahead is **Zero**" and
  reasons from that; the property returns `1` since Sortie 21. Behavior unchanged, stated
  reason now false. Exactly the comment a future reader trusts.
- **DL-113**: `KindVocabularyTests` raw-value lists stopped being exhaustive at Sortie 13
  and have drifted since. Nothing asserts completeness, so not a defect — but they were
  presumably written to catch vocabulary drift and no longer do.
- **DL-162**: the unknown-key half of the WU-8 gate has a per-key loop that executes for
  only **2 of 6** fixtures. Inherent to the data, not a test defect — but nobody reading the
  test count would know.
- **DL-4**: `make lint` runs `swift format -i -r .`, **not SwiftLint**, while Sortie 29's
  criteria require the CI lint job to invoke `make lint` to enforce three custom SwiftLint
  rules. **Unreconciled; Sortie 29 owns it.** Until then all three custom rules — including
  the `no_markdown_import_in_sources` rule that is the *only* thing keeping `swift-markdown`
  out of the shipping graph — **are documentation, not enforcement.**

---

## 8. Standing rules earned during execution

If a re-implementation starts from zero, these belong in the plan at Sortie 1 rather than
being discovered at Sortie 13, 19, 25 and 27.

1. **Every grammar sortie runs all three test targets** (DL-87). Core-only exit criteria are
   structurally blind to editor-layer regressions; that is how a sortie shipped one.
2. **Never partially stage; add whole files; verify your own commit in a throwaway worktree**
   (DL-98, validated DL-104). A green working directory is not evidence that what you
   committed builds.
3. **A field added to a shared type must have its type defined in that same file**
   (DL-93 rule 2).
4. **`make lint` is a repo-wide write** — per-sortie scope or between-rounds only (DL-123).
5. **Commit `SUPERVISOR_STATE.md` at every gate** (DL-123).
6. **Pair every green claim with a test count** (DL-103).
7. **Confirm an agent is finished by process state, not by its notification** — and this
   governs any tree-mutating supervisor action, not just dispatch (DL-140, DL-160).
8. **Never truncate a probe's output; verify a probe actually landed before concluding from
   it** (DL-142, DL-53).
9. **Every dispatch order states the next free DL number** (DL-150) **and every open
   obligation matching the sortie's subject** (DL-172).
10. **Every CI job declares `timeout-minutes`** (DL-61). A hang is strictly worse than a
    failure in a gating job.
11. **No grammar claim may rest on a green gate** (DL-25 / DL-31, proven seven times).

---

## 9. What went right, recorded because a rollback would discard it too

A rollback should not throw away the process findings that worked.

- **Agents caught their own unfalsifiable criteria six times** (DL-105, DL-124, DL-128,
  DL-155, DL-164, and Sortie 24's four). The strongest signal in the mission. It happened
  because dispatch orders *asked* for mutation testing and honest reporting of non-firing
  probes.
- **DL-110 — the process win of the mission.** Sortie 14 warned Sortie 15 that giving notes
  their own `ElementKind` would drop them into the "everything else" branch and close the
  dialogue block, breaking the very criterion Sortie 15 had to satisfy — **which would
  otherwise have passed for free.** Sortie 15 did it deliberately and mutation-tested it. *A
  criterion that would have been vacuously satisfied became load-bearing because one sortie
  wrote down what the next needed to know.*
- **DL-119** — an agent reported a mutation that **did not fire**, and the finding was the
  opposite of a gap: a second downstream guard reached the same correct output, i.e.
  redundant malformed-recovery worth knowing before someone "simplifies" a guard away.
- **DL-123** — the agent that destroyed the state file **reported it plainly and unprompted,
  and saved a dangling stash to the scratchpad**, which is the only reason ~43 entries were
  recoverable at all.
- **Two agents refused to report measurements they could not trust** (DL-160, and the
  contaminated-run catch at DL-140). Both were right to.
- **Vendoring real files found the mission's worst defect** (DL-130) and its follow-on
  (DL-151), neither of which any specification-derived test found.
- **The independent-oracle pattern works.** Where a gate compared a model against itself, it
  was blind (DL-156); replacing one side with Foundation's own parser took the same probe
  from 3 issues to 38 (DL-161). The same pattern discharged DL-111 in the writer.

---

*Maintained by the Mission Supervisor. Updated as later sorties land; superseded by nothing.
`SUPERVISOR_STATE.md` remains the authoritative Decisions Log.*
