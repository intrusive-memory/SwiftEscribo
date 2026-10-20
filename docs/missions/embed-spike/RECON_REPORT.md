---
type: recon-report
state: current
requirements_file: REQUIREMENTS.md
requirements_sha256: fcf8fab5b99382d0189d5468b771d63a3b6864b5d1794920dce6b1e860545648
project_head: 92e997b803bdf699a5d379a67a3bb37d1e6defa9
search_root: ~/Projects
generated: 2026-10-20
verdict: CLEAR
---

# Recon Report: atomic block embeds spike

> **Terminology**: A *mission* is the definable scope of work (here, the spike). A *sortie* is one atomic task a single agent does within that mission. Recon checks what the requirements assume about code that already exists. It runs before any sortie is planned.

**Verdict: CLEAR.** 13 assumptions extracted, 13 confirmed, 0 stale or refuted, 0 unverifiable.

Verified read-only by the hub (no spokes dispatched) against the `development` working tree at `92e997b`. The only untracked path is `docs/missions/`. Nothing was built, resolved, or fetched.

Scope note: rows 1 to 11 of "What to prove" are **deliverables**, not assumptions. Only what they presuppose about existing code is audited here. The branch `spike/block-embeds` does not exist yet. It is the mission's first deliverable, not a premise.

## Summary

| ID | Kind | Claim | Locus | Verdict | Evidence |
|----|------|-------|-------|---------|----------|
| A-01 | A-API | `MacTextView.swift` builds an `NSTextView` on TextKit 2 via `init(usingTextLayoutManager:)` | repo | CONFIRMED | `Sources/SwiftEscribo/MacTextView.swift:164`; subclass `Sources/SwiftEscribo/EditorInputPath.swift:93` |
| A-02 | A-FILE | iOS uses `IOSTextView` (TextKit 2) | repo | CONFIRMED | `Sources/SwiftEscribo/IOSTextView.swift:1,58,173`; subclass `EditorInputPath.swift:234` |
| A-03 | A-API | `EscriboEditorBridge` is the text view's delegate on both platforms | repo | CONFIRMED | `Sources/SwiftEscribo/EscriboEditorRepresentable.swift:50,121,181,189` |
| A-04 | A-API | iOS bridge implements `textViewDidChangeSelection` | repo | CONFIRMED | `EscriboEditorRepresentable.swift:201` |
| A-05 | A-API | `EditorMode` is a struct with `.live` and `.source` | repo | CONFIRMED | `Sources/SwiftEscribo/EditorMode.swift:11,22,27` |
| A-06 | A-API | `EscriboWell`, `WellOverlay`, `WellTracker` exist and map blocks to on-screen geometry | repo | CONFIRMED | `EscriboWell.swift:71`, `WellOverlay.swift:105`, `WellTracker.swift:78`; geometry `WellOverlay.swift:41-66` |
| A-07 | A-API | `EscriboBlock` carries a UTF-16 range | repo | CONFIRMED | `Sources/EscriboCore/EscriboBlock.swift:15-16,24,55` |
| A-08 | A-BEHAVIOR | A standalone note is its own `.note` block | repo | CONFIRMED | `Sources/EscriboCore/EscriboBlockGrouper.swift:278-284`; test `Tests/EscriboCoreTests/FountainBlockGroupingTests.swift:132-137` |
| A-09 | A-BEHAVIOR | (row 10 premise) A standalone note spanning several lines with no blank line is **one** `.note` block | repo | CONFIRMED (code path; untested) | see § Row 10 |
| A-10 | A-CONFIG | `make build`, `make test`, `make test-ios` exist | repo | CONFIRMED | `Makefile:26,29,43`; iOS destination `Makefile:17` |
| A-11 | A-FILE | An editor test target with per-platform text-view tests exists | repo | CONFIRMED | `Package.swift:115`; `Tests/SwiftEscriboTests/MacTextViewTests.swift`, `IOSTextViewTests.swift` |
| A-12 | A-CONFIG | Package targets macOS 26 and iOS 26 | toolchain | CONFIRMED | `Package.swift:23-24` |
| A-13 | A-CONFIG | Swift tools 6.2 | toolchain | CONFIRMED | `Package.swift:1` |

### Notes on confirmed items

- **A-01 / A-02 naming.** `MacTextView` and `IOSTextView` are *file* names. The type in both files is `EscriboTextView` (`MacTextView.swift:32`, `IOSTextView.swift:58`). It wraps `EscriboNativeTextView`, which is the `NSTextView`/`UITextView` subclass (`EditorInputPath.swift:93,234`). The requirements cite the file, so this is not stale, but sorties should name the types.
- **A-03/A-04, macOS selection hook.** The macOS bridge implements only `textDidChange` (`EscriboEditorRepresentable.swift:184`). No macOS selection-change delegate method exists yet, so constraining selection on macOS (for example `textView(_:willChangeSelectionFromCharacterRanges:toCharacterRanges:)`) is new work.
- **No TextKit 2 layout or content-storage delegate is installed anywhere.** A grep for `NSTextLayoutManagerDelegate`, `NSTextContentStorageDelegate`, `NSTextLayoutFragment` and `textLayoutManager…delegate` under `Sources/` found nothing. The spike's custom-fragment path will not collide with an existing delegate.
- **A-06 geometry.** `WellGeometry.lineFragmentRects` walks `enumerateTextLayoutFragments(from:options: [.ensuresLayout])` and reads `layoutFragmentFrame` (`WellOverlay.swift:49-66`). Its comment states that "a hard-wrapped block is several layout fragments" (`WellOverlay.swift:41-45`).

## Row 10: is a multi-line note one `.note` block today?

**Yes, when the note stands alone.** The path through the code:

1. **Every line of a multi-line note is classified `.note`.** Region scanning runs before any block rule and carries an open `[[` across lines (`FountainGrammar.swift:307-318`). A line made only of region text becomes the region's element (`coversWholeLine`, `FountainGrammar.swift:981`; `regionLine`, `FountainGrammar.swift:1093-1097` → `.note`). `[[a note` opens at the start of a line and runs to its end. Middle lines start inside the region. `still the note]]` ends at the close. All three lines are whole-line region.
2. **All those lines share a depth.** `regionLine` passes no depth, so it gets `LineScan`'s default of `0` (`LineGrammar.swift:139`).
3. **The grouper takes them as one run.** The standalone neutral arm groups by `sameDepthRun(…, of: .note)` (`EscriboBlockGrouper.swift:278-284`), which extends while element and depth match (`EscriboBlockGrouper.swift:404-413`). The result is one `.note` block.
4. **Existing test evidence that the lines are `.note`:** "a note spanning two lines still does not end the speech" (`FountainBlockGroupingTests.swift:118-120`) only passes if both lines are neutral.

**Caveats the spike should know:**

- **No test covers a *standalone* multi-line `.note` block.** The verdict rests on the code path above. The spike should add the case or check it at runtime.
- **A note is only its own block when it bridges nothing.** `action / note / action` and `cue / dialogue / note / dialogue` absorb the note into the surrounding block (`EscriboBlockGrouper.swift:186-202`, `neutralBridge` `:386-393`; test `FountainBlockGroupingTests.swift:110-130`). In that case there is no `.note` block to embed.
- **Adjacent separate notes merge.** `[[a]]` and `[[b]]` on consecutive lines form one `.note` block, because the run is keyed by element and depth, not by note boundaries.
- **A blank line does not close a note** (deviation 9, `FountainGrammar.swift:191-195`). A whitespace-only line inside an open note stays in the region (`FountainGrammar.swift:977-981`), so a note containing blank lines is still one block.
- **Text before `[[` changes the classification.** `Bob waits. [[note` is action with a note span (deviation 8, `FountainGrammar.swift:183-186`). Only the following lines are `.note`.
- **Rendering consequence.** A multi-line block is several TextKit 2 layout fragments, one per paragraph (`WellOverlay.swift:41-45`). Drawing it "as one row" therefore means collapsing N fragments into one: either one tall fragment followed by zero-height fragments, or an equivalent. That is the hardest part of row 10 and should be proved explicitly.

## Local Dependency Map

| Dependency | Declared | Resolved | Local checkout | Local HEAD | Status |
|------------|----------|----------|----------------|-----------|--------|
| swiftlang/swift-markdown | `upToNextMajor(from: "0.8.0")`, used by `EscriboCoreTests` only | `0.8.0` (`3c6f9523da3a`) | none | — | NO_LOCAL_CHECKOUT |
| swiftlang/swift-cmark (transitive) | — | `0.8.0` (`924936d0427c`) | none | — | NO_LOCAL_CHECKOUT |

- No `.build/checkouts` exists in the package. No assumption rests on a dependency. Every claim is about `repo` or `toolchain`, so this map does not affect the gate.
- No `intrusive-memory/*` dependencies, and no sibling-path resolution (`Package.swift` dependencies block).

## Unverifiable

None.

## Handoff to breakdown

- Confirmed facts can be used as sortie entry criteria without re-checking. Use the type names `EscriboTextView` and `EscriboNativeTextView`, not the file names.
- Plan a macOS selection-constraint hook as new work. Only iOS has a selection delegate today.
- Row 10: include a check that a standalone multi-line note is one `.note` block (no test covers it today). The proof fixture must be a note that bridges nothing, for example one with a blank line or a scene heading after it.
- Build and test through `make build`, `make test` and `make test-ios`. Never use `swift build` or `swift test`.
