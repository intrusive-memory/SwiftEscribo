---
type: recon-report
state: current
requirements_file: REQUIREMENTS.md
requirements_sha256: 9df7bcd68bea3fd05ecbe19d593c93c47651019a966736e712a74ec92d98207d
project_head: 16d03e0726609191fdeab0c37f90e2e4baa2909c
search_root: ~/Projects
generated: 2026-10-20
verdict: BLOCKED
---

# Recon Report: block embeds, notice well slot, JSON in notes (revision 2)

## Terminology

> **Mission**: a definable, testable scope of work.
> **Sortie**: an atomic, testable unit of work that one agent executes in one dispatch.
> **Work Unit**: a grouping of sorties.

## Verdict

**BLOCKED.** I checked 29 assumptions: 26 confirmed, 2 blocking, 1 unverifiable.

- **(a) Expected upstream gate (1):** A-28. The embed spike (mission B) has not run.
- **(b) Requirement errors (1):** A-17. One sentence in § 3 describes note grouping wrongly. The fix is one line.

The revision fixed all five errors from the first recon:

| First recon | Status now |
|---|---|
| A-10: no cross-line scanner state | Fixed. Cross-line JSON state goes in `LineState`, rescans follow it, and the `make test-performance` budgets apply (A-11 to A-14). |
| A-12: themes don't colour GLOSA | Fixed. All `glosa*` kinds get colours in the four language themes (A-18). |
| A-17: no UI test target | Fixed. The tests are now unit tests (A-21, A-22). |
| A-18: no snapshot setup | Fixed. The no-provider checks are now unit assertions (A-21). |
| A-19: Find is macOS-only and has no match hook | Fixed. Find expansion is macOS-only and needs a new hook, `onFindMatchInEmbed` (A-19, A-20). |

The first recon's note N-1, about `expandedEmbeds` using an unstable ID, is also resolved: the set was dropped. The CHANGELOG clause now covers 0.3.x pins as well as 0.4.x (A-25).

The hub verified everything read-only, without spokes, against the `development` working tree at `16d03e0`. The only commits since the first recon (`92e997b`) touch `docs/missions/` and nothing else. Nothing was built, resolved, or fetched. `docs/missions/embed-spike/RECON_REPORT.md` has uncommitted local changes that this recon did not make. It was left untouched.

Scope: everything the document asks to *add* is a deliverable, not an assumption. That includes `EscriboEmbedProvider`, `EscriboEmbed`, the new editor parameters, `onFindMatchInEmbed`, the find-bar hook, `.notice`, the JSON span kinds, the new `LineState` field, the theme colours, and the CHANGELOG entry.

## Assumption Findings

| ID | Kind | Claim | Locus | Verdict | Evidence |
|----|------|-------|-------|---------|----------|
| A-01 | A-API | `EscriboWell` is `Equatable, Sendable` so SwiftUI can diff it | repo | CONFIRMED | `Sources/SwiftEscribo/EscriboWell.swift:68-71` |
| A-02 | A-INVARIANT | `EscriboWellItem` is a struct with static members, so adding one is a minor change | repo | CONFIRMED | `EscriboWell.swift:16-29`; the only member is `.readAloud` (`:46`) |
| A-03 | A-API | The existing `onWellAction` can carry a click on a new slot | repo | CONFIRMED | `EscriboEditor.swift:73,151`, `(EscriboWellItem, EscriboBlock) -> Void`; the overlay forwards any item (`WellOverlay.swift:666`). See N-1 for glyph and visibility |
| A-04 | A-API | New defaulted `EscriboEditor` parameters leave existing call sites compiling | repo | CONFIRMED | `EscriboEditor.swift:142-152`. Every parameter after `language` has a default. See N-5 on ordering |
| A-05 | A-API | `EditorMode` has `.live` and `.source` | repo | CONFIRMED | `EditorMode.swift:11,22,27` |
| A-06 | A-BEHAVIOR | `EscriboBlock.ID` is not stable across edits (`EscriboBlock.swift:26–33`) | repo | CONFIRMED | `EscriboBlock.swift:26-33`: "deliberately *not* stable across an edit that moves a block" |
| A-07 | A-API | `EscriboColor` is a public, `Sendable` value type that can be a badge `tint` inside an `Equatable` struct | repo | CONFIRMED | `EscriboColor.swift:27` (`Hashable, Sendable`) |
| A-08 | A-API | `GlosaScanner` splits note content into `glosaTag`, `glosaAttributeName`, `glosaAttributeValue`, and `glosaPunctuation`, defined at `SpanKind.swift:294–331` | repo | CONFIRMED | `SpanKind.swift:294` (MARK), `:303,310,318,331`; `GlosaScanner.swift:87-99` |
| A-09 | A-BEHAVIOR | The scanner sees one line at a time and carries no state between lines (`GlosaScanner.swift:58–66`, `FountainGrammar.swift:1024`) | repo | CONFIRMED (citation drift) | The prose is at `GlosaScanner.swift:60-68` ("no cross-line state … adds none to `LineState`"), two lines below the cited range. The call is `FountainGrammar.swift:1024-1026` |
| A-10 | A-INVARIANT | Totality rule: spans tile the range exactly, with no throw and no trap | repo | CONFIRMED | `GlosaScanner.swift:70-77` |
| A-11 | A-API | A `LineState` exists. It carries multi-line context and can gain JSON context | repo | CONFIRMED | `LineState.swift:26`. Fields are `internal` stored properties added "as the grammars that need them do" (`:19-22`), at no API cost (`:14-17`). The memberwise `init` has all-default arguments (`:163-181`) |
| A-12 | A-BEHAVIOR | The incremental scanner re-scans following lines when a line's carried state changes | repo | CONFIRMED | Rescanning stops only where the recomputed start state equals the recorded one (`IncrementalScanner.swift:20-31`, `:268-292`). A changed JSON field forces rescans with no scanner change, provided the field is part of `==` (synthesized, `LineState.swift:26`) |
| A-13 | A-BEHAVIOR | A Fountain note is already a multi-line region carried in line state | repo | CONFIRMED | `FountainGrammar.swift:249` (`noteTag`), `:1000`, `:1052`. `scanRegions` takes only the region tag (`:996`), so JSON context needs new plumbing there (work, not a conflict) |
| A-14 | A-CONFIG | `make test-performance` exists and has budgets | repo | CONFIRMED | `Makefile:61-68` (Release, arm64). Budgets: cold full scan ≤ 50 ms (`ScanBudgetTests.swift:150`), in-line edit ≤ 1 ms and ≤ 8 lines (`:173,180`), pathological edits ≤ 50 ms and ≤ 8 lines (`:210-322`). The CI run is manual only (`.github/workflows/performance.yml:3`). See N-3 |
| A-15 | A-BEHAVIOR | A note standing alone between blank lines is one `.note` block | repo | CONFIRMED | `EscriboBlockGrouper.swift:278-284`; test `FountainBlockGroupingTests.swift:132-135` (single-line case only; no multi-line test exists) |
| A-16 | A-BEHAVIOR | Consecutive notes merge into one block | repo | CONFIRMED (code path) | `sameDepthRun` over `.note` (`EscriboBlockGrouper.swift:282-284`) |
| A-17 | A-BEHAVIOR | "a note flush against action or dialogue merges into that block" | repo | **STALE** | Only a **bridging** note merges, meaning the block resumes after it. `action / note / blank` gives an action block **and a separate `.note` block**. Evidence: `EscriboBlockGrouper.swift:198-202`; test `FountainBlockGroupingTests.swift:132-135` ("a note that bridges nothing is its own block") and `:234-245` |
| A-18 | A-BEHAVIOR | None of the four built-in themes colours a `glosa*` kind or `.note` | repo | CONFIRMED | `fountainLight`/`fountainDark` `kindStyles` (`BuiltInThemes.swift:140-165,183-208`) have no such entry. `grep -rn glosa Sources/SwiftEscribo` finds nothing. The code calls these "all four language themes" (`:250-252`). `source` (`:224-232`) has no tables by design |
| A-19 | A-BEHAVIOR | The find bar is macOS-only | repo | CONFIRMED | `EscriboEditor.swift:59` ("macOS only; a no-op on iOS"); `MacTextView.swift:201-202` |
| A-20 | A-BEHAVIOR | The find bar has no current-match hook today | repo | CONFIRMED | Find is AppKit's own `NSTextFinder` bar, enabled through `usesFindBar` / `isIncrementalSearchingEnabled` (`MacTextView.swift:189-202`). `Sources/` contains no `NSTextFinder` subclass, client, or delegate. See N-4 |
| A-21 | A-FILE | No UI test target and no snapshot-testing setup | repo | CONFIRMED | `Tests/` holds only `EscriboCoreTests`, `EscriboPerformanceTests`, `EscriboProjectTests`, `SwiftEscriboTests`. No `XCUIApplication` or snapshot library (`Package.swift:42-50`) |
| A-22 | A-FILE | `SwiftEscriboTests` exists and has inset and geometry tests to model on | repo | CONFIRMED | `Tests/SwiftEscriboTests/ParagraphGeometryTests.swift`, `EscriboWellTests.swift`, `MacTextViewTests.swift`, `IOSTextViewTests.swift` |
| A-23 | A-CONFIG | `make lint`, `make test`, and `make test-ios` exist | repo | CONFIRMED | `Makefile:103,29,43` |
| A-24 | A-CONFIG | The next minor release is `0.5.0` | repo | CONFIRMED | Latest tag `v0.4.5`; `CHANGELOG.md:15` |
| A-25 | A-INVARIANT | `upToNextMinor` pins from 0.3.x and from 0.4.x both exist downstream | external hosts | CONFIRMED | One host package pins `.upToNextMinor(from: "0.3.0")`. One host Xcode project pins `upToNextMinorVersion`, minimum `0.4.4` |
| A-26 | A-FILE | `CHANGELOG.md` has an `[Unreleased]` section | repo | CONFIRMED | `CHANGELOG.md:13` |
| A-27 | A-BEHAVIOR | A note closes at the first `]]`, so the `]]` escape test case is meaningful | repo | CONFIRMED | `FountainGrammar.swift:176-180` |
| A-28 | A-BEHAVIOR | Gate in: the embed spike reported go on macOS and iOS, and the user accepted it | upstream mission B | **REFUTED** (not yet run) | `docs/missions/embed-spike/` holds only `REQUIREMENTS.md` and `RECON_REPORT.md` (`verdict: CLEAR`). No `spike` branch exists, local or remote, and no outcome is recorded |
| A-29 | A-DEP | glosa-av 0.9.0 defines the JSON block directive | dep:intrusive-memory/glosa-av | UNVERIFIABLE | Local `glosa-av` is at `eed3dc9` (`development`). Its latest tag is `v0.8.1`, so 0.9.0 is unreleased. SwiftEscribo does not depend on it (`Package.swift:42-50`) |

## Blocking findings

### (a) Expected upstream gate

#### A-28: embed spike not yet run
**Claim**: "Gate in: the embed spike … reports go on macOS and iOS and the user accepts it."
**Found**: The spike's recon is CLEAR, but the spike has not run. § 1.2 ("the mechanism the spike proved") and § 1.3 ("the spike's table") have no source yet.
**Options**:
1. Run mission B. After the user accepts go, re-run this recon *(recommended)*.
2. If B returns no-go, rewrite this document around the well-slot fallback, as it already says.

### (b) Requirement errors

#### A-17: note grouping is described wrongly
**Claim** (§ 3): "a note flush against action or dialogue merges into that block".
**Found**: A note merges only when it **bridges**, meaning the same block resumes on the line after it (`action / note / action`, or a note inside a speech). A note directly after action and followed by a blank line is its own `.note` block. The tests pin this down (`FountainBlockGroupingTests.swift:132-135`).
**Impact**: Small. The real behaviour is more favourable than the stated one: a trailing directive can be embedded. Left as written, though, a breakdown would plan for, or test, behaviour the code does not have.
**Options**:
1. Reword: "a note that bridges two lines of the same block, such as action/note/action or a note inside a speech, is absorbed into that block. Consecutive notes merge into one block." *(recommended)*

## Notes (non-blocking, for breakdown)

- **N-1: the notice slot has no per-block data path and is shown only on hover.** "A host-supplied glyph and help text per block" fits nothing in the current well. Glyphs are hard-coded per item (`WellTracker.swift:373-378`, `default: return nil`), so a `.notice` item with no mapping is filtered out (`WellOverlay.swift:320-323`). `EscriboWell` has no per-block field (`EscriboWell.swift:71-117`), and a closure would break its `Equatable` (`:68-70`). Slots appear only for the hover, caret, playing, and finished roles (`WellTracker.swift:81-89`), so a notice would not be visible unless the pointer or caret is on its block. Breakdown must decide three things. (1) How the host supplies glyph and help text: an `Equatable` map on `EscriboWell` keyed by `EscriboBlock.ID` (the same ID `activeBlock` already uses, with the same instability as A-06), or a provider like `EscriboEmbedProvider`. (2) Whether a notice is always visible. (3) Whether this changes the `.readAloud`-only symbol table. Make it an Open Question.
- **N-2: JSON context must also go into `NestedFountainState`.** Inside a `fountain` fence in Markdown, the Fountain half of the state is carried by `NestedFountainState`, `nested(_:)`, and `fountainHalf` (`LineState.swift:246-313`). The file warns that any field these forget makes the fence "converge early inside the block". The requirement names only `LineState`. Also, a nesting *depth* is not enough to tell keys from values after a closing `}` or `]`. The scanner needs the container kind at each level, which fits in a bit stack in one scalar, the way `MarkdownBlockState` stores lists (`LineState.swift:102-113`).
- **N-3: the performance budgets never exercise JSON.** The perf fixture is a fixed screenplay with no JSON notes, and the suite asserts that the fixture is unchanged (`ScanBudgetTests.swift:82-97`). "Existing budgets still pass" will be true trivially. Add one pathological case: open a `{` at the top of a long, unterminated multi-line JSON note and measure the rescan. CI runs the suite only on manual dispatch (`performance.yml:3`).
- **N-4: the find hook will collide with the embed selection rules.** `NSTextFinder` reports a match only by setting the text view's selection, which can land inside an embed. § 1.3 also says the caret is never inside an embed and that selection extends to the whole block. Breakdown must order these: detect the find-originated selection, call `onFindMatchInEmbed`, and do not snap that selection to the block. The spike's findings should settle it.
- **N-5: add the new closures after `onWellAction`.** `onWellAction` is currently the last parameter (`EscriboEditor.swift:151`), so call sites may pass it as a trailing closure. New parameters inserted before it could change which parameter a trailing closure binds to. Add them after.
- **N-6: the live-only provider adds a mode branch.** Carried over from the first recon (N-3). `EditorMode.swift:3-8` says that switching modes is "not a code path". The doc comment must change when the provider is asked only in `.live`.

## Local Dependency Map

| Dependency | Declared | Resolved | Local checkout | Local HEAD | Status |
|------------|----------|----------|----------------|-----------|--------|
| swiftlang/swift-markdown (test-only) | `upToNextMajor(from: "0.8.0")` | `0.8.0` (`3c6f9523da3a`) | none | none | NO_LOCAL_CHECKOUT |
| swiftlang/swift-cmark (transitive, test-only) | n/a | `0.8.0` (`924936d0427c`) | none | none | NO_LOCAL_CHECKOUT |
| intrusive-memory/glosa-av (spec source only, not a dependency) | n/a | n/a | `~/Projects/package-collection/pkg/glosa-av` | `eed3dc9` (`development`, tag `v0.8.1`) | n/a |

The package has no shipping dependencies and no sibling pattern. No assumption rests on dependency source.

## Unverifiable

| ID | Claim | Why | What would settle it |
|----|-------|-----|----------------------|
| A-29 | glosa-av 0.9.0 defines the JSON block directive | 0.9.0 is unreleased | Release glosa-av 0.9.0. Until then, scan JSON structurally only and write fixtures against glosa-av's notation-2 mission docs |

## Handoff to breakdown

- Do not run breakdown yet. Run mission B and get the user's go. Fix the A-17 sentence in § 3. Then re-run recon. If nothing else moves, it should come back CLEAR.
- CONFIRMED facts A-01 to A-16 and A-18 to A-27 are safe to use as sortie entry criteria.
- N-1 and N-4 become Open Questions. N-2, N-3, and N-5 become explicit acceptance criteria on the scanner, performance, and API sorties.
