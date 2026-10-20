---
type: recon-report
state: current
requirements_file: REQUIREMENTS.md
requirements_sha256: 4ba413e6ccb445323e8edd4df3f862b29354ffaf7e4d540db518628c355fe014
project_head: 92e997b803bdf699a5d379a67a3bb37d1e6defa9
search_root: ~/Projects
generated: 2026-10-20
verdict: BLOCKED
---

# Recon Report: block embeds, notice well slot, JSON in notes

## Terminology

> **Mission**: a definable, testable scope of work.
> **Sortie**: an atomic, testable unit of work that one agent executes in one dispatch.
> **Work Unit**: a grouping of sorties.

## Verdict

**BLOCKED.** 21 assumptions checked: 14 confirmed, 6 blocking, 1 unverifiable.

- **(a) Expected upstream gate (1):** A-20. The embed spike has not run.
- **(b) Genuine requirement errors (5):** A-10, A-12, A-17, A-18, A-19.

The hub verified everything read-only, with no spokes, against the `development` working tree at `92e997b`. The only untracked path is `docs/missions/`. Nothing was built, resolved or fetched.

Scope note: everything the document asks to *add* is a deliverable, not an assumption. That covers `EscriboEmbedProvider`, `EscriboEmbed`, the new editor parameters, `.notice`, the JSON span kinds and the CHANGELOG entry. Recon audits only what those deliverables presuppose about existing code.

## Assumption Findings

| ID | Kind | Claim | Locus | Verdict | Evidence |
|----|------|-------|-------|---------|----------|
| A-01 | A-API | `EscriboWell` is `Equatable, Sendable` for SwiftUI-diffing reasons | repo | CONFIRMED | `Sources/SwiftEscribo/EscriboWell.swift:68-71` |
| A-02 | A-INVARIANT | `EscriboWellItem` is a struct with static members, and adding one is a *minor* change (its forward-compat rule) | repo | CONFIRMED | `EscriboWell.swift:16-29`; only member `.readAloud` at `:46` |
| A-03 | A-API | `onWellAction` exists and can carry a click on a new slot | repo | CONFIRMED | `EscriboEditor.swift:73,151`, signature `(EscriboWellItem, EscriboBlock) -> Void`; threaded through `EscriboEditorRepresentable.swift:103,150,261,323` |
| A-04 | A-API | `EscriboEditor.init` has only defaulted optional parameters after `text`/`language`, so new defaulted parameters keep call sites compiling | repo | CONFIRMED | `EscriboEditor.swift:142-152` |
| A-05 | A-API | `EditorMode` has `.live` and `.source` | repo | CONFIRMED | `EditorMode.swift:11,22,27` |
| A-06 | A-API | `EscriboBlock` and `EscriboBlock.ID` exist; `ID` is `Hashable` (usable in `Set`) | repo | CONFIRMED | `EscriboCore/EscriboBlock.swift:24,34` (see note N-1 on stability) |
| A-07 | A-API | `EscriboColor` is a public type usable for a badge tint | repo | CONFIRMED | `EscriboColor.swift:27,42,50` |
| A-08 | A-API | `GlosaScanner` (`EscriboCore/GlosaScanner.swift`) subdivides note content into `glosaTag` / `glosaAttributeName` / `glosaAttributeValue` / `glosaPunctuation` | repo | CONFIRMED | `GlosaScanner.swift:42-48,94-96`; kinds `SpanKind.swift:303,310,318,331` (cited range `294–312` runs short: `glosaPunctuation` is at `:331`) |
| A-09 | A-INVARIANT | The scanner's totality rule: spans tile the range exactly, no throw, no trap | repo | CONFIRMED | `GlosaScanner.swift:68-74`. Malformed tags today degrade to `.text` (`:62-65`); the requirement wants malformed JSON left as `.note`, which is new work, not a conflict |
| A-10 | A-BEHAVIOR | The scanner sees a note's whole content, so "trimmed content starts with `{`" can be judged and JSON spans can cover "every line it crosses" | repo | **REFUTED** | `GlosaScanner.swift:58-66`: "one content chunk, no cross-line state … adds none to `LineState`". Called per line chunk at `FountainGrammar.swift:1024-1025` |
| A-11 | A-BEHAVIOR | A multi-line note (no blank line) is one `.note` block | repo | CONFIRMED (standalone only, code path, untested) | `EscriboBlockGrouper.swift:278-284` (`sameDepthRun`); same finding as the spike recon (embed-spike `RECON_REPORT.md` § Row 10). Caveats in N-2 |
| A-12 | A-BEHAVIOR | Built-in themes give the GLOSA tag kinds colours, so the JSON kinds can get "the same colours" | repo | **REFUTED** | `grep -ri glosa Sources/SwiftEscribo` → no hits. `fountainLight.kindStyles` (`BuiltInThemes.swift:140-164`) has no `.note` or `glosa*` entry; unknown kinds fall back to earlier stages (`EscriboTheme.swift:21-23`) |
| A-13 | A-CONFIG | `make lint`, `make test` and `make test-ios` exist | repo | CONFIRMED | `Makefile:103,29,43`; iOS destination `Makefile:17` |
| A-14 | A-FILE | `CHANGELOG.md` exists with an `[Unreleased]` section | repo | CONFIRMED | `CHANGELOG.md:13` |
| A-15 | A-INVARIANT | Hosts pin `upToNextMinor` from 0.4.x | external hosts | CONFIRMED (with a gap) | One host app's Xcode project: `kind = upToNextMinorVersion; minimumVersion = 0.4.4`. A second host package pins `.upToNextMinor(from: "0.3.0")`, so it is still on 0.3.x. The CHANGELOG has used this convention since 0.1.0 (`CHANGELOG.md:49,132,773`) |
| A-16 | A-CONFIG | Current release line is 0.4.x, so the next minor is 0.5.0 | repo | CONFIRMED | `git tag` → latest `v0.4.5`; `CHANGELOG.md:15` |
| A-17 | A-FILE | "the existing UI tests pass untouched" (UI tests exist) | repo | **REFUTED** | `Tests/` holds only `EscriboCoreTests`, `EscriboPerformanceTests`, `EscriboProjectTests`, `SwiftEscriboTests`; no `XCUIApplication` anywhere. The package has no UI test target |
| A-18 | A-CONFIG | "no-provider layout snapshot unchanged" (layout snapshot testing exists) | repo | **REFUTED** | No snapshot library in `Package.swift`; `SwiftEscriboTests` hits for "snapshot" are attribute/value snapshots (`EditorCoordinatorTests.swift:109`, `StylerCacheTests.swift:91`). Only scan goldens exist (`Tests/EscriboCoreTests/Fixtures/Golden`) |
| A-19 | A-BEHAVIOR | Find exists on both platforms, so "Find expands the embed holding the current match" applies to macOS and iOS | repo | **REFUTED** (iOS) | `EscriboEditor.swift:59-60`: "find bar. macOS only; a no-op on iOS". macOS uses the system find bar (`MacTextView.swift:189-205`), and no current-match hook is exposed |
| A-20 | A-BEHAVIOR | Gate in: the embed spike reported go on macOS and iOS, and the user accepted it | upstream mission B | **REFUTED** (not yet run) | `docs/missions/embed-spike/` has only `REQUIREMENTS.md` and `RECON_REPORT.md` (verdict CLEAR); no `spike/*` branch exists; no spike outcome is recorded |
| A-21 | A-DEP | GLOSA notation 2.0 block directives are "defined by glosa-av 0.9.0" | dep:intrusive-memory/glosa-av | UNVERIFIABLE | Local `glosa-av` is on `development` at `518ff02`; latest tag `v0.8.1`; 0.9.0 is unreleased. SwiftEscribo does not and must not depend on it (`Package.swift:4-19`) |

## Blocking findings

### (a) Expected upstream gate

#### A-20: embed spike not yet run
**Claim**: "Gate in: the embed spike … reports go on macOS and iOS and the user accepts it." (REQUIREMENTS.md front matter `depends_on`, § intro)
**Found**: The spike's recon is CLEAR, but the spike has not executed. § 1.2 ("by the mechanism the spike proved") and § 1.3 ("the spike's table") have no source yet.
**Options**:
1. Run mission B, then re-run this recon after the user accepts go *(recommended)*.
2. If B returns no-go, rewrite this document around the well-slot fallback before any breakdown, as it already says.

### (b) Genuine requirement errors

#### A-10: GlosaScanner has no cross-line state
**Claim**: a note "whose trimmed content starts with `{` is scanned as JSON", and a multi-line note's "every line it crosses carries the spans" (§ 3).
**Found**: The scanner sees one line's chunk at a time and adds nothing to `LineState` (`GlosaScanner.swift:58-66`, `FountainGrammar.swift:1024-1025`). On line 2 or later of a note, the chunk does not start with `{`, and the scanner has no record of being inside JSON.
**Impact**: Multi-line JSON needs new cross-line state: a JSON nesting/string state in `LineState`, which is the incremental scanner's convergence key (`LineState.swift:1`). That changes `IncrementalScanner` convergence and touches the performance budgets. The requirements treat it as a scanner addition.
**Options**:
1. Amend § 3 to name the work: carry JSON state across lines in `LineState`, with incremental-rescan convergence tests and a `make test-performance` check *(recommended if multi-line directives are needed)*.
2. Limit JSON subdivision to single-line notes and leave continuation lines as `.note`.

#### A-12: built-in themes don't colour GLOSA kinds
**Claim**: "built-in themes give the new kinds the same colours as the corresponding tag kinds" (§ 3), and directives "are syntax-coloured" (intro).
**Found**: No built-in theme styles any `glosa*` kind, or `.note`. Taken literally, the new kinds would get no colour either, so nothing would be syntax-coloured.
**Options**:
1. Add `kindStyles` entries for all GLOSA kinds, old and new, to the four built-in themes, and state the colours in the requirements *(recommended; the intro's stated goal)*.
2. Drop the theme clause: the new kinds fall back like the tag kinds do, and hosts colour them.

#### A-17: no UI test target
**Claim**: "the existing UI tests pass untouched" (§ 1.5); "the spike's behaviour table as UI or unit tests" (§ 4).
**Options**:
1. Reword as "the existing `SwiftEscriboTests` pass untouched", and require unit tests for the behaviour table *(recommended)*.
2. Add a UI test host and target to scope as its own work unit.

#### A-18: no layout snapshot infrastructure
**Claim**: "no-provider layout snapshot unchanged" (§ 4).
**Options**:
1. Replace it with unit assertions on text-container inset and layout-fragment frames with no provider, in the style of `ParagraphGeometryTests` and `EscriboWellTests` *(recommended)*.
2. Add a snapshot-testing dependency. This is test-only, but it conflicts with the package's no-dependency charter spirit (`Package.swift:4-19`).

#### A-19: Find is macOS-only and has no match hook
**Claim**: "Find expands the embed holding the current match (by reporting it to the host …)" (§ 1.3), tested on macOS and iOS (§ 4).
**Found**: iOS has no find UI in the package. On macOS, the system find bar exposes no current-match callback. Also, none of the listed API surface (§ 1.1) can report a match to the host.
**Options**:
1. Scope the rule to macOS, and add a named callback to § 1.1 (for example, `onEmbedRevealRequest: (EscriboBlock) -> Void`) *(recommended)*.
2. Drop Find expansion from this release.

## Notes (non-blocking)

- **N-1, `expandedEmbeds` keyed by an unstable ID.** `EscriboBlock.ID` is `(line, offset)`. Its docs say it is "deliberately *not* stable across an edit that moves a block" (`EscriboBlock.swift:26-33`). A host's `Set<EscriboBlock.ID>` goes stale after any edit above the block: the expanded embed collapses, or a different block expands. Breakdown should settle the identity scheme. Options: the package remaps the set across edits, or the host keys on content.
- **N-2, the note grouping caveats carry over from the spike recon.** A note is its own block only when it bridges nothing. `action / note / action` absorbs it (`EscriboBlockGrouper.swift:186-202`), so a directive written flush against action has no `.note` block to embed. Two consecutive notes merge into one `.note` block (`sameDepthRun`), which gives one embed for two directives. No test covers a standalone multi-line `.note` block.
- **N-3, the live-only provider becomes a mode branch.** `EditorMode` documents mode switching as "a theme swap, not … a code path" (`EditorMode.swift:3-8`). Asking the provider "in `EditorMode.live` only" adds the first mode-conditioned code path. That is acceptable, but the doc comment should change with it.
- **N-4, `]]` inside JSON.** Notes close at the first `]]` (`FountainGrammar.swift:176-180`). The `]]` test case in § 4 accounts for this. Authors and glosa-av need to escape it the same way.
- **N-5, a second host is behind.** One host package pins `.upToNextMinor(from: "0.3.0")`. It will not receive 0.4.x or 0.5.0 without a manual pin raise, and the CHANGELOG note covers only 0.4.x pins.

## Local Dependency Map

| Dependency | Declared | Resolved | Local checkout | Local HEAD | Status |
|------------|----------|----------|----------------|-----------|--------|
| swiftlang/swift-markdown (test-only) | `upToNextMajor(from: "0.8.0")` | `0.8.0` (`3c6f9523da3a`) | none | none | NO_LOCAL_CHECKOUT |
| swiftlang/swift-cmark (transitive, test-only) | n/a | `0.8.0` (`924936d0427c`) | none | none | NO_LOCAL_CHECKOUT |
| intrusive-memory/glosa-av (not a dependency; spec source only) | n/a | n/a | `~/Projects/package-collection/pkg/glosa-av` | `518ff02` (`development`, tag `v0.8.1`) | n/a |

No shipping dependencies, and no sibling pattern in `Package.swift`. No assumption rests on dependency source.

## Unverifiable

| ID | Claim | Why | What would settle it |
|----|-------|-----|----------------------|
| A-21 | Notation 2.0's JSON block shape is defined by glosa-av 0.9.0 | 0.9.0 is unreleased (campaign mission A) | glosa-av 0.9.0 released. Until then, write test fixtures against glosa-av `docs/missions/notation-2` and treat the scanner as structural JSON only |

## Handoff to breakdown

- Do not run breakdown yet. First run mission B and get the user's go. Then amend § 1.3, § 1.5, § 3 and § 4 for A-10, A-12, A-17, A-18 and A-19, and re-run recon.
- CONFIRMED facts (A-01 to A-09, A-11, A-13 to A-16) are safe as sortie entry criteria.
- N-1 and N-2 should become Open Questions in the plan.
