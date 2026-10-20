---
type: recon-report
state: current
requirements_file: REQUIREMENTS.md
requirements_sha256: 57bb84673759fb7bec9024dcd253d3f2bec50be0c2429793c876ae238f2d22af
project_head: 16d03e0726609191fdeab0c37f90e2e4baa2909c
search_root: ~/Projects
generated: 2026-10-20
verdict: CLEAR
---

# Recon Report: atomic block embeds spike (re-run)

> **Terminology**: A *mission* is the definable scope of work (here, the spike). A *sortie* is one atomic task a single agent does within that mission. Recon checks what the requirements assume about code that already exists. It runs before any sortie is planned.

**Verdict: CLEAR.** 16 assumptions extracted, 16 confirmed, 0 stale or refuted, 0 unverifiable.

This is a re-run after the requirements' "What exists" section was revised. The hub verified every claim read-only, with no spokes, against `development` at `16d03e0`. Since the previous recon (`92e997b`), the only commits add mission docs (`docs/missions/block-embeds/*`, `docs/missions/embed-spike/*`). No source, manifest or lock file changed. Nothing was built, resolved or fetched.

Scope note: rows 1 to 11 of "What to prove" and the `SPIKE_REPORT.md` deliverable are **deliverables**, not assumptions. Only what they presuppose about existing code is audited here. The branch `spike/block-embeds` does not exist yet. It is the mission's first deliverable, not a premise.

## Summary

| ID | Kind | Claim | Locus | Verdict | Evidence |
|----|------|-------|-------|---------|----------|
| A-01 | A-FILE | `MacTextView.swift` and `IOSTextView.swift` both define `EscriboTextView` | repo | CONFIRMED | `Sources/SwiftEscribo/MacTextView.swift:32`, `Sources/SwiftEscribo/IOSTextView.swift:58` |
| A-02 | A-API | `EscriboTextView` wraps `EscriboNativeTextView` (`NSTextView` / `UITextView` subclass) at `EditorInputPath.swift:93,234` | repo | CONFIRMED | `EditorInputPath.swift:93` (`: NSTextView`), `:234` (`: UITextView`); held at `MacTextView.swift:45`, `IOSTextView.swift:68` |
| A-03 | A-API | Both are built on TextKit 2 at `MacTextView.swift:164`, `IOSTextView.swift:173` | repo | CONFIRMED | both lines: `EscriboNativeTextView(usingTextLayoutManager: true)` |
| A-04 | A-API | `EscriboEditorBridge` is the text view's delegate on both platforms | repo | CONFIRMED | `EscriboEditorRepresentable.swift:50` (class), `:121` (`editor.textView.delegate = self`), `:181` (`NSTextViewDelegate`), `:189` (`UITextViewDelegate`) |
| A-05 | A-API | iOS bridge has `textViewDidChangeSelection` at `:201` | repo | CONFIRMED | `EscriboEditorRepresentable.swift:201` |
| A-06 | A-INVARIANT | macOS bridge implements only `textDidChange` (`:184`) | repo | CONFIRMED | `EscriboEditorRepresentable.swift:181-187` is the whole extension; `grep NSTextViewDelegate\|didChangeSelectionNotification\|func textView(` in `Sources/` finds no other macOS hook (only a doc comment at `EditorInputPath.swift:73`) |
| A-07 | A-INVARIANT | No TextKit 2 layout-manager or content-storage delegate is installed anywhere | repo | CONFIRMED | `grep NSTextLayoutManagerDelegate\|NSTextContentStorageDelegate\|NSTextLayoutFragment` in `Sources/`: 0 hits. The only `.delegate =` assignments are `EscriboEditorRepresentable.swift:121` (view) and `NSTextStorageBridge.swift:153` (`NSTextStorage`) |
| A-08 | A-API | `EditorMode` is a struct with `.live` and `.source` | repo | CONFIRMED | `Sources/SwiftEscribo/EditorMode.swift:11,22,27` |
| A-09 | A-API | `EscriboWell`, `WellOverlay`, `WellTracker` exist and map blocks to geometry | repo | CONFIRMED | `EscriboWell.swift:71`, `WellOverlay.swift:105`, `WellTracker.swift:78`; geometry `WellOverlay.swift:41-66` |
| A-10 | A-API | `EscriboBlock` carries a UTF-16 range | repo | CONFIRMED | `Sources/EscriboCore/EscriboBlock.swift:15-16,24,55` |
| A-11 | A-BEHAVIOR | A standalone note is its own `.note` block | repo | CONFIRMED | `Sources/EscriboCore/EscriboBlockGrouper.swift:278-284` |
| A-12 | A-BEHAVIOR | A standalone multi-line note (no blank line) is one block today | repo | CONFIRMED (code path; untested) | see § Row 10 |
| A-13 | A-BEHAVIOR | A multi-line block is N TextKit 2 layout fragments | repo | CONFIRMED | `WellOverlay.swift:41-45` ("layout fragments — one per source paragraph … a hard-wrapped block is several layout fragments") |
| A-14 | A-CONFIG | `make build`, `make test`, `make test-ios` exist | repo | CONFIRMED | `Makefile:26,29,43`; iOS destination `Makefile:17` |
| A-15 | A-CONFIG | Package targets macOS 26 and iOS 26 | toolchain | CONFIRMED | `Package.swift:23-24` |
| A-16 | A-CONFIG | Swift tools 6.2 | toolchain | CONFIRMED | `Package.swift:1` |

### Notes on confirmed items

- **The revision is accurate.** Every type name and line number added to "What exists" checks out at `16d03e0`.
- **A-04 / A-06, where the macOS selection hook can go.** The bridge already owns `textView.delegate` on both platforms. The spike cannot install a second `NSTextViewDelegate`. It must add the selection method to `EscriboEditorBridge`, or override selection in `EscriboNativeTextView`.
- **A-07 wording.** "No TextKit 2 delegate" is true. An `NSTextStorage` delegate is installed (`NSTextStorageBridge.swift:153`) and drives scanning, so the spike must not take `storage.delegate`. The `NSTextLayoutManager` and `NSTextContentStorage` delegates are free.

## Row 10: is a multi-line note one `.note` block today?

**Yes, when the note stands alone.** The REQUIREMENTS phrase "recon confirmed" is accurate only for the code path. No test covers it.

1. Each line of a multi-line note is `.note`. Region scanning carries an open `[[` across lines (`FountainGrammar.swift:307-318`), and a whole-line region becomes `.note` (`FountainGrammar.swift:1093-1097`).
2. Those lines share depth `0`, the `LineScan` default (`LineGrammar.swift:139`).
3. The standalone neutral arm groups them with `sameDepthRun` (`EscriboBlockGrouper.swift:278-284`), which extends while element and depth match (`:404-413`). The result is one block.

**Caveats:**

- **No test covers a standalone multi-line `.note` block.** The spike should add one or check at runtime.
- **A note that bridges is absorbed.** `action / note / action` and `cue / dialogue / note / dialogue` fold the note into the surrounding block (`EscriboBlockGrouper.swift:186-202`; test `FountainBlockGroupingTests.swift:110-130`). The fixture must bridge nothing, for example a note followed by a blank line or a scene heading.
- **Adjacent separate notes merge.** Consecutive `[[a]]` / `[[b]]` lines form one block.
- **A blank line does not close an open note** (`FountainGrammar.swift:191-195`).
- **Text before `[[` makes the line action** (`FountainGrammar.swift:183-186`).

## Local Dependency Map

| Dependency | Declared | Resolved | Local checkout | Local HEAD | Status |
|------------|----------|----------|----------------|-----------|--------|
| swiftlang/swift-markdown | `upToNextMajor(from: "0.8.0")`, `EscriboCoreTests` only | `0.8.0` (`3c6f9523da3a`) | none | — | NO_LOCAL_CHECKOUT |
| swiftlang/swift-cmark (transitive) | — | `0.8.0` (`924936d0427c`) | none | — | NO_LOCAL_CHECKOUT |

- There is no `.build/checkouts` directory. No assumption rests on a dependency, so the map does not affect the gate.
- There are no `intrusive-memory/*` dependencies and no sibling-path resolution.

## Unverifiable

None.

## Handoff to breakdown

- Confirmed facts can be sortie entry criteria without re-checking. Name the types `EscriboTextView` and `EscriboNativeTextView`.
- The macOS selection constraint is new work and goes on `EscriboEditorBridge` or `EscriboNativeTextView`. The view delegate slot is taken.
- Leave `NSTextStorage.delegate` alone. The layout-manager and content-storage delegates are free.
- Row 10 needs a fixture with a standalone multi-line note that bridges nothing, plus a check that it is one block. Collapsing N layout fragments into one row is the hardest proof in the spike.
- Build and test with `make build`, `make test` and `make test-ios`. Never use `swift build` or `swift test`.
