---
type: test-cleanup-report
title: OPERATION FOUNTAIN SURGEON — Test Cleanup Report
operation: OPERATION FOUNTAIN SURGEON
iteration: 1
mission_branch: mission/fountain-surgeon/01
starting_point_commit: 6b8c3ee3d07ad15afe5d6f44fe7c218db334585e
head_commit: 8c85565
state: in-progress
updated: 2026-07-27
---

# Test Cleanup Report — OPERATION FOUNTAIN SURGEON, iteration 1

## Summary

- **Tests removed: 0**
- **Tests flagged for review: 3 categories, none actionable today**
- **Build verification: pass** — `make test-core` **318/31**, `make test` **179/28 + 48/11 +
  318/31**, `make test-ios` **160/25 + 48/11 + 318/31**, `make test-performance` **13/6**,
  all exit 0, re-run by the supervisor at `8c85565`.
- **Cleanup sortie dispatched: NO.** Reasoning below — this is a supervisor decision, stated
  rather than buried.

## Scope

`git diff --name-only 6b8c3ee..HEAD -- Tests/` → **48 Swift test files**, **571 `@Test`
cases** across four targets (EscriboCore 319, SwiftEscribo 191, EscriboProject 48,
EscriboPerformance 13). Every one was added or modified during this mission, so the entire
test suite is in scope.

## Why no cleanup sortie was dispatched

The command's own bias is *"leave it and report it, not delete it and hope."* The supervisor
ran all twelve high-confidence delete patterns across the full 48-file scope first, and every
one returned **zero candidates** (evidence below). Dispatching a mechanical pattern-matcher
with delete authority over 571 heavily-probed test cases, for an expected yield of zero,
carries only downside risk: this mission's tests are the product's only guarantee, and a
false-positive deletion would land in the same commit as the "cleanup."

**This is a deviation from the standard flow and it is recorded as one.** If the pre-checks
below are wrong, the remedy is to re-run `/mission-supervisor test-cleanup` and dispatch.

## Removed

*(none)*

| file:test_name | reason | confidence |
|----------------|--------|-----------|
| — | — | — |

## Pattern pre-checks — the evidence for zero removals

| # | Pattern | Command | Result |
|---|---------|---------|--------|
| 1 | Hardcoded local paths | `grep -rlE '/Users/\|/home/\|~/Desktop\|~/Library\|#filePath' Tests/` | **0** |
| 2 | Unmocked network | `grep -rnE 'https?://[a-zA-Z]' Tests/` | 8 hits, **all literal Markdown parser input** (`https://example.com` inside autolink and frontmatter fixtures). **0 network calls.** |
| 3 | Local-only services | `grep -rn 'localhost\|127.0.0.1' Tests/` | 1 hit — `"<user@localhost>"`, an email-autolink **test string**. **0 services.** |
| 4 | Env-var gating | `grep -rn 'ProcessInfo' Tests/` | **0** |
| 5 | User-profile paths | covered by #1 | **0** |
| 6 | Sleep-based timing | `grep -rnE '\bsleep\(\|asyncAfter' Tests/` | **0** |
| 7 | Bare `Date()` | `grep -rn 'Date()' Tests/` | **0** |
| 8 | Unordered-collection iteration order | reviewed during Sorties 6 and 33 | **0** known |
| 9 | Unseeded randomness | `grep -rn 'random(in:' Tests/ \| grep -v 'using: &'` | **0** — every site threads a seeded generator |
| 10 | Rotting skip markers | `grep -rnE 'XCTSkip\|\.disabled\(\|withKnownIssue' Tests/` | **0** |
| 11 | Empty / assertion-free tests | scan for empty `@Test` bodies | **0** |
| 12 | Exact duplicates | not mechanically checkable; no report of duplication in 33 sortie reports | none observed |

Patterns 1, 7 and 9 return zero **by construction, not by luck**: Sortie 17's exit criteria
included `grep -rE '/Users/|~/Projects|#filePath' Tests/` exiting 1, and Sortie 6's seed audit
required every `Int.random(in:)` under `Tests/` to pass `using: &generator`. The supervisor
re-verified both at the mission tip rather than trusting the earlier checks.

## Flagged for Review

| Concern | Detail | Recommended action |
|---------|--------|--------------------|
| **The real CI-safety risk in this suite is not on the pattern list** | **DL-61 / DL-180**: `make test` intermittently **hangs** in font resolution — every worker blocked in `+[NSFont fontWithName:size:]` awaiting an idle `fontd`. Reproduced **three times**: twice by the Sortie 28 agent, once by the supervisor during Sortie 28's verification (killed at 10 minutes; passed in 14 s on the immediate re-run). It is **pre-existing** — reproduced on a clean tree before any mission code was written — and it is a *hang*, not a failure, so no test-level pattern can detect it. Five `SwiftEscriboTests` files touch font resolution. | **Mitigated, not fixed.** Sortie 29 added `timeout-minutes` to all three CI jobs (15/30/45), which converts a six-hour stall into a bounded failure. **Do not delete these tests** — they assert D-4, the font-fallback chain, which exists precisely because the naive version passes locally and misleads in CI. Watch for it in the first real CI runs; if it recurs there, the fix is warming the font cache in a setup step, not removing coverage. |
| **Timing assertions exist, deliberately, in `EscriboPerformanceTests`** | 13 tests assert wall-clock budgets (≤1 ms in-line edit, ≤50 ms cold scan, 4.4× linearity). Pattern 6 would normally flag these. | **Leave.** They are structurally protected in three ways a naive timing test is not: the suite is **excluded from PR CI by design** (its own workflow, `push`/`schedule`/`workflow_dispatch` only), it uses **min-of-N** rather than mean, and Sortie 30 added a **`build-optimized: true`** assertion that fires *before* any clock is read. Measured headroom is ~40× on the in-line budget and ~10× on the cold scan. |
| **Five test files exceed 700 lines** | `ScanGateTests` 967, `FountainGrammarTests` 956, `EditorInputPathTests` 836, `FountainRegionTests` 731, `MarkdownGFMTests` 718. | **Leave.** Size here is table-driven `@Test(arguments:)` corpora — the idiom D-1 mandates so a failing row names itself. Splitting them would not reduce cases, only locality. |

## Build Verification

All four targets re-run by the supervisor on a quiet machine at `8c85565`, after confirming
no `xcodebuild`/`xctest` process was alive:

| Target | Exit | Counts |
|--------|------|--------|
| `make build` | 0 | — |
| `make lint` | 0 | 66 findings, **0 errors** |
| `make test-core` | 0 | **318 / 31** |
| `make test` | 0 | **179/28 + 48/11 + 318/31** |
| `make test-ios` | 0 | **160/25 + 48/11 + 318/31** |
| `make test-performance` | 0 | **13 / 6**, `build-optimized: true`, cold scan 5.088 ms |

## Note for the brief

The absence of removals is itself a finding worth carrying into the verdict: the twelve
patterns this pass exists to catch were **excluded by the mission's own standing rules**
(DL-98, DL-103, and Sorties 6 and 17's exit criteria) rather than cleaned up afterwards.
The one genuine CI hazard in this suite — the `fontd` hang — is invisible to all twelve
patterns, was found by an agent running the suite rather than by inspecting it, and is
mitigated by a workflow timeout rather than by deleting a test.
