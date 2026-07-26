---
type: execution-plan
title: SwiftEscribo — Execution Plan
updated: 2026-07-25
---

# EXECUTION_PLAN.md — SwiftEscribo

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

---

## Source

Generated from [REQUIREMENTS.md](REQUIREMENTS.md) (2026-07-25). Supporting context:
[AGENTS.md](AGENTS.md), `Package.swift`, `Makefile`, `.swiftlint.yml`,
`.github/workflows/tests.yml`.

**Starting state**: the package is scaffolded but has **zero source files** —
`Sources/` and `Tests/` do not exist, so `Package.swift` cannot currently resolve
its declared targets. This is a greenfield 1.0.

**Sequencing is not a choice this plan makes.** REQUIREMENTS.md § Open questions
settles it: substrate + a deliberately tiny grammar wired end-to-end through *both*
Representables first (a vertical slice for risk, not a demo), then Fountain depth,
then Markdown breadth, then the writer. The layer assignments below encode that.

---

## Work Units

| Work Unit | Directory | Sorties | Range | Layer | Dependencies |
|-----------|-----------|---------|-------|-------|-------------|
| WU-1 Core Substrate | `Sources/EscriboCore` | 6 | 1–6 | 0 | none |
| WU-2 Editor Substrate | `Sources/SwiftEscribo` | 6 | 7–12 | 1 | WU-1 |
| WU-3 Fountain Depth | `Sources/EscriboCore/Fountain` | 5 | 13–17 | 2 | WU-1, WU-2 |
| WU-4 Markdown Breadth | `Sources/EscriboCore/Markdown` | 5 | 18–22 | 2 | WU-1, WU-2 (S21 also WU-3) |
| WU-5 Writer | `Sources/EscriboCore/Writer` | 2 | 23–24 | 3 | WU-3 |
| WU-6 Editor Behavior | `Sources/SwiftEscribo` | 3 | 25–27 | 3 | WU-2, WU-3, WU-4 |
| WU-7 Verification & Hardening | repo root, `.github/` | 3 | 28–30 | 4 | WU-1…WU-6 |

---

## WU-1 — Core Substrate

The scanner→editor seam. REQUIREMENTS.md is explicit that every line of grammar
written against a wrong answer here is rework.

### Sortie 1: Target scaffolding and the primitive kind vocabulary

**Priority**: 91 — Blocks all 29 remaining sorties. Establishes the kind vocabulary every scanner and the styler key off.

**Entry criteria**:
- [ ] First sortie — no prerequisites

**Tasks**:
1. Create `Sources/EscriboCore/`, `Sources/SwiftEscribo/`, `Tests/EscriboCoreTests/`,
   `Tests/SwiftEscriboTests/`, `Tests/EscriboPerformanceTests/` so all five declared
   targets in `Package.swift` have source directories. All three test targets use
   **swift-testing** (`import Testing`, `@Test`, `#expect`) — see D-1. No test target
   imports XCTest.
2. Define `SpanKind`, `ElementKind`, and `Language` as `Hashable, Sendable` **structs
   with a `rawValue: String` and static members** — never enums (REQUIREMENTS.md
   § Core API: a public enum is source-breaking to extend). Populate only the members
   the minimal grammar needs; later sorties register their own.
3. Define `StyleSet` as an `OptionSet, Sendable` over `UInt16` with `.strong`,
   `.emphasis`, `.strikethrough`, `.inlineCode`, `.underline` at fixed bit positions.
4. Define `SpanRole` (`.content`, `.marker`) as `Equatable, Sendable`.

**Exit criteria**:
- [ ] `make build` exits 0
- [ ] `make test-core` exits 0
- [ ] All five target directories exist and `swift package describe` lists five targets
- [ ] `grep -rE '^\s*import (SwiftUI|AppKit|UIKit)' Sources/EscriboCore/` returns no matches
- [ ] `grep -rE 'public enum (SpanKind|ElementKind|Language)' Sources/EscriboCore/` returns no matches
- [ ] `grep -rn 'import XCTest' Tests/` returns no matches
- [ ] A test constructs `SpanKind`, `ElementKind`, `Language`, `StyleSet`, and `SpanRole`
      and asserts `Sendable` + `Hashable`/`Equatable` conformance compiles
- [ ] A test asserts `StyleSet` bit positions are stable — each member's `rawValue` is
      asserted against its literal expected value

### Sortie 2: The span and record model

**Priority**: 88 — Blocks 28. The span/record model is the scanner→editor seam — a wrong answer here is rework in every later sortie.

**Entry criteria**:
- [ ] Sortie 1 exit criteria met

**Tasks**:
1. Define `EscriboSpan` (`range: Range<Int>` UTF-16, `kind`, `style`, `role`) as
   `Equatable, Sendable`.
2. Define `LineState` as a **public but opaque** `Equatable, Sendable` type — no
   public cases, no public properties, no public initializer.
3. Define `LineRecord` (`index`, `range`, `contentRange`, `element`, `startState`,
   `depth`) as `Equatable, Sendable`.
4. Define `ScanResult` (`dirtyRange`, `spans`, `lines`, `lineRecords`) as
   `Equatable, Sendable`.
5. Define `TextEdit` expressed in **old-text coordinates** (range replaced +
   replacement length). Document the coordinate convention in a doc comment — every
   later sortie depends on reading it the same way.

**Exit criteria**:
- [ ] `make build` exits 0
- [ ] `make test-core` exits 0
- [ ] `grep -rE '^\s*import (SwiftUI|AppKit|UIKit)' Sources/EscriboCore/` returns no matches
- [ ] A test constructs `EscriboSpan`, `LineRecord`, `ScanResult`, and `TextEdit` and
      asserts `Sendable` + `Equatable` conformance compiles
- [ ] No public member of `LineState` is reachable from a non-`@testable` import
      (asserted by a test file that imports `EscriboCore` without `@testable`)
- [ ] `TextEdit`'s doc comment states the old-text-coordinate convention, verified by
      `grep -n 'old-text' Sources/EscriboCore/`

### Sortie 3: UTF-16 text access and `LineIndex`

**Priority**: 86 — Blocks 27. Line ranges and terminator handling underpin every scan and every dirty-range assertion.

**Entry criteria**:
- [ ] Sortie 2 exit criteria met

**Tasks**:
1. Define the UTF-16 text-source abstraction in `EscriboCore` — reads code units and
   **yields whole lines, not single code units**, so dispatch is per line. Conform
   `String` to it here; `NSTextStorage` conformance lives in `SwiftEscribo` (Sortie 10),
   because `NSTextStorage` is an AppKit/UIKit type.
2. Implement `LineIndex`: line ranges where `range` **includes the terminator**.
3. Handle `\n`, `\r\n`, and lone `\r` as terminators, mixable within one document, and
   **never normalized**. `\r\n` is one terminator of two code units.
4. Implement the trailing-terminator rule: `"a\n"` is two lines (`"a\n"` and `""`);
   `"a"` is one; `""` is one empty line.
5. Implement incremental line-range adjustment for a `TextEdit` without rebuilding the
   whole index.

**Exit criteria**:
- [ ] `make test-core` exits 0
- [ ] Tests cover, each as a named case: LF-only, CRLF-only, lone-CR, mixed-terminator,
      trailing terminator, no trailing terminator, empty document
- [ ] A test asserts that for every line, `line.range` includes its terminator and
      that summing all line ranges reconstructs the source **byte for byte**
- [ ] A test asserts a 1 MB single-line document yields exactly one `LineRecord` whose
      range covers every code unit (structural check — the wall-clock linearity check
      lives in `EscriboPerformanceTests`, Sortie 28, because timing assertions in the
      PR-gated target are the flakiness class `test-cleanup` exists to delete)

### Sortie 4: Incremental scanner seam and convergence engine

**Priority**: 84.5 — Blocks 26. The convergence engine is the highest-risk algorithm in the package; every grammar depends on its lookahead contract.

**Entry criteria**:
- [ ] Sortie 3 exit criteria met

**Tasks**:
1. Implement the two grammar-agnostic entry points: a full scan over a document, and
   an incremental scan taking a `TextEdit` in old-text coordinates.
2. Implement **backward widening**: rescanning starts at least one line before the
   first edited line (REQUIREMENTS.md Architecture §5).
3. Implement **forward convergence**: stop when a recomputed `startState == ` its
   previous value **and** the edit is behind us **and** the grammar's declared
   lookahead is satisfied. Lookahead is a property the grammar declares, not a constant.
4. Assemble `dirtyRange` line-aligned at both ends and containing the edited range.
5. Assemble `spans` so they exactly tile `dirtyRange` — ordered, non-overlapping,
   contiguous, plain text emitted as a `.text` span rather than a gap.
6. Make scanning total: no `throws`, no optional result, no error path. Malformed and
   unterminated constructs degrade to `.text`.

**Exit criteria**:
- [ ] `make test-core` exits 0
- [ ] `grep -rE 'func (fullScan|incrementalScan)[^{]*(throws|async|-> *ScanResult\?)' Sources/EscriboCore/`
      returns no matches — no scanner entry point throws, is async, or returns an
      optional `ScanResult`
- [ ] A test asserts `dirtyRange.lowerBound` and `dirtyRange.upperBound` both fall on
      line boundaries, for ≥20 distinct edits
- [ ] A test asserts `dirtyRange` contains the edited range for those same edits
- [ ] A test asserts the first span begins at `dirtyRange.lowerBound` and the last ends
      at `dirtyRange.upperBound`, with no gap or overlap between consecutive spans
- [ ] A test asserts `lineRecords.count == lines.count` with strictly increasing,
      gapless `index` values

### Sortie 5: Minimal grammar — ATX headings and fenced code

**Priority**: 78 — Blocks 25. First grammar through the seam — proves the substrate before depth is built on it.

**Entry criteria**:
- [ ] Sortie 4 exit criteria met

**Tasks**:
1. Implement ATX heading scanning (`#` … `######`) emitting a `.marker` span for the
   hashes and the space, and a content span for the rest — **same `kind` and `style`
   on both**, differing only in `role`.
2. Implement fenced code blocks (```` ``` ```` and `~~~`) with the in-fence flag
   carried in `LineState`, so it participates in convergence.
3. Emit `LineRecord.contentRange` excluding markers, indent, and terminator.
4. Handle an unterminated fence by scanning to end of document without failing.
5. Wire this grammar behind `Language.markdown` dispatch.

**Exit criteria**:
- [ ] `make test-core` exits 0
- [ ] A test asserts `**source.utf16.count** == sum of all span lengths` for a document
      containing headings and fences (total tiling, no hidden characters)
- [ ] A test asserts a marker span and its adjacent content span carry identical
      `kind` and `style` and differ only in `role`
- [ ] A test asserts an unterminated fence produces spans to the last code unit of the
      document and returns normally
- [ ] A test asserts opening a fence on line 1 of a 500-line document produces a
      `dirtyRange` extending to end of document

### Sortie 6: Gate property test and the always-on span invariant harness

**Priority**: 77.5 — Blocks 24. The invariant helper and gate property are reused by every subsequent scanner sortie.

**Entry criteria**:
- [ ] Sortie 5 exit criteria met

**Tasks**:
1. Write a shared assertion helper that checks every `ScanResult` invariant
   (ordering, non-overlap, exact tiling of `dirtyRange`, line alignment,
   edit containment, `lineRecords` gapless, no span boundary splitting a surrogate
   pair) and call it from **every** scan in the suite, not as its own test case.
2. Write a **seeded, deterministic** edit-sequence generator. Seeds are fixed
   constants in the source — never `Date`, never unseeded `random`. Drive the seeds
   through `@Test(arguments:)` so individual seeds are selectable in isolation (D-1).
3. The generator MUST emit the adversarial cases, not uniform typing: editing the line
   *after* an ALL-CAPS line, opening and closing fences, pasting and deleting
   multi-line blocks, editing at offset 0, and editing at EOF.
4. Assert the gate property: `incrementalScan(edits) == fullScan(finalText)` —
   comparing `spans` and `lineRecords` as arrays.
5. Seed the generator over a corpus of at least 5 documents including CRLF and
   astral-plane characters.

**Exit criteria**:
- [ ] `make test-core` exits 0
- [ ] The gate test runs ≥200 edit sequences and passes
- [ ] `grep -rn 'import XCTest' Tests/` returns no matches
- [ ] `grep -rE 'Date\(\)|\.random\(in:.*\)(?!.*using: *&?generator)' Tests/EscriboCoreTests/`
      finds no unseeded randomness in the generator
- [ ] Deliberately breaking convergence (temporarily returning after one converged line
      with no lookahead) turns the gate test **red** — recorded in the sortie report as
      proof the test can fail
- [ ] The invariant helper is invoked from every test that produces a `ScanResult`

---

## WU-2 — Editor Substrate

The vertical slice. Both Representables ship together (Architecture §10); a
coordinator shaped around AppKit does not retrofit to UIKit cheaply.

### Sortie 7: Theme value types and the caching styler

**Priority**: 74 — Blocks 23. Theme and styler cache are the second half of the seam, consumed by all three Representables.

**Entry criteria**:
- [ ] Sortie 6 exit criteria met

**Tasks**:
1. Define `EscriboTheme` as a **value type holding a lookup table** — not a protocol
   with an `attributes(for:)` method.
2. Define `TokenStyle` and `EditorMode`. Put `markerOpacity` on the theme as a
   **single scalar** — no per-kind marker style, no marker `TokenStyle`.
3. Implement the styler cache keyed by `(SpanKind, StyleSet, SpanRole)`, invalidated by
   exactly four triggers: theme change, mode change, appearance change, font-metric
   change. One invalidation path.
4. Implement the normative composition order: base → kind → style → role. Within a
   stage, **traits union and everything else overrides**. Role stage multiplies
   foreground alpha and does nothing else.
5. Resolve an unrecognized `SpanKind` to the base style — never a crash, never a blank,
   never a `fatalError` in a `default:`.
6. Ship built-in light and dark themes for both languages, plus the built-in **source
   theme** that maps every kind, style, and role to base attributes.

**Exit criteria**:
- [ ] `make test` exits 0
- [ ] A test asserts that under the source theme, **every span in a mixed document
      resolves to an identical attribute dictionary** regardless of kind, style, or role
- [ ] A test asserts an unrecognized `SpanKind` (constructed from an unknown raw value)
      resolves to the base style rather than trapping
- [ ] A test asserts a `.marker` span and its `.content` sibling resolve to attributes
      that differ **only** in foreground alpha — same font, same point size
- [ ] A test asserts each of the four invalidation triggers empties the cache, and that
      a repeated lookup with no trigger is a cache hit
- [ ] `grep -rE 'protocol .*Theme' Sources/SwiftEscribo/` returns no matches

### Sortie 8: Paragraph geometry layer — characters to points

**Priority**: 72 — Blocks 22. Geometry conversion touches CoreText and is reused by both language rule sets.

**Entry criteria**:
- [ ] Sortie 7 exit criteria met

**Tasks**:
1. Define `ParagraphMetrics` (`leftIndentChars`, `rightIndentChars`,
   `firstLineIndentChars`, `spaceBeforeLines`, `alignment`) as `Equatable, Sendable`.
2. Store geometry in **characters and multiples of line height, never points**, looked
   up by `(ElementKind, depth)`.
3. Convert to points at style time against the **resolved font's advance width**.
4. Implement the font resolution chain Courier Prime → Courier New → Courier →
   `.monospacedSystemFont` through CoreText (D-4). The final fallback is not optional:
   none of the three Courier faces is guaranteed present on a CI runner or an iOS
   device. **No test may assert a resolved family name**, and no font is bundled as a
   package resource.
5. Produce `NSParagraphStyle` from `ParagraphMetrics` on the line ranges of
   `lineRecords`.
6. Expose geometry as theme-controlled and switchable off (REQUIREMENTS.md Editor §6).

**Exit criteria**:
- [ ] `make test` exits 0 and `make test-ios` exits 0
- [ ] `grep -rE '(leftIndent|headIndent|firstLineHeadIndent)[A-Za-z]*: *[0-9.]+' Sources/SwiftEscribo/`
      finds no hardcoded point constants in the theme tables
- [ ] A test asserts that doubling the resolved font size **doubles** the computed
      point indent for the same `ParagraphMetrics`
- [ ] A test asserts the resolved face is monospaced (equal advance width for `i` and
      `W`) — **not** that it is any named family
- [ ] A test asserts resolution still yields a monospaced face when all three Courier
      names are unavailable (simulated by resolving from a name list of bogus families)
- [ ] `grep -rniE '"Courier( Prime| New)?"' Tests/` returns no matches — no test names a
      family
- [ ] `Package.swift` declares no font file in any `resources:` block
- [ ] A test asserts geometry-off produces the default `NSParagraphStyle` for every
      `ElementKind`

### Sortie 9: Platform-neutral TextKit 2 coordinator

**Priority**: 69.5 — Blocks 21. The coordinator is adopted unchanged by both Representables — an AppKit-shaped seam here does not retrofit to UIKit.

**Entry criteria**:
- [ ] Sortie 8 exit criteria met

**Tasks**:
1. Build the platform-neutral coordinator: it owns the scanner, the styler, and edit
   translation. It must contain **no AppKit-only seam** that UIKit cannot adopt.
   Name the file `EditorCoordinator.swift` so the import-hygiene grep below can target
   it precisely.
2. Conform `NSTextStorage` to the UTF-16 text-source abstraction from Sortie 3, so the
   scanner never bridges the document to a Swift `String` per edit. Put this
   conformance in its own file — it is the one piece that must import a UI framework.
3. Translate `textStorage(_:didProcessEditing:range:changeInLength:)` into a `TextEdit`
   in **old-text coordinates**.
4. Apply attributes with `beginEditing()` / `setAttributes(_:range:)` / `endEditing()`
   over the rescanned range only. **Never `setAttributedString`.**
5. Skip restyling entirely while `hasMarkedText` is true.

**Exit criteria**:
- [ ] `make test` exits 0
- [ ] `grep -rn 'setAttributedString' Sources/SwiftEscribo/` returns no matches
- [ ] `grep -rn 'hasMarkedText' Sources/SwiftEscribo/` shows the restyle path guarded
- [ ] `grep -cE '^\s*import (AppKit|Cocoa|UIKit)' Sources/SwiftEscribo/EditorCoordinator.swift`
      returns 0 — the coordinator file itself imports no UI framework
- [ ] A test asserts a single-character insertion mid-paragraph produces a `TextEdit`
      whose range is in old-text coordinates and whose replacement length is 1
- [ ] A test asserts a multi-character replacement (select 5, type 1) produces a
      `TextEdit` with the 5-unit range and replacement length 1
- [ ] A test asserts that with marked text active, a storage edit produces **zero**
      calls into the styler

### Sortie 10: macOS `NSTextView` Representable

**Priority**: 64 — Blocks 20. First end-to-end vertical slice on macOS.

**Entry criteria**:
- [ ] Sortie 9 exit criteria met

**Tasks**:
1. Build the macOS Representable: `NSTextView` in an `NSScrollView`, TextKit 2, bound to
   the Sortie 9 coordinator.
2. Disable smart quotes, smart dashes, automatic text replacement, and automatic
   spelling correction. Leave spell **checking** enabled.

**Exit criteria**:
- [ ] `make test` exits 0
- [ ] A test asserts the view sets `isAutomaticQuoteSubstitutionEnabled`,
      `isAutomaticDashSubstitutionEnabled`, `isAutomaticTextReplacementEnabled`, and
      `isAutomaticSpellingCorrectionEnabled` to `false`
- [ ] A test asserts `isContinuousSpellCheckingEnabled` remains `true`
- [ ] A test asserts the text view's layout stack is TextKit 2 — `textLayoutManager`
      is non-nil
- [ ] Typing a heading into the view produces styled attributes over the heading range
      (asserted by reading back attributes from the text storage)

### Sortie 11: iOS `UITextView` Representable on the same coordinator

**Priority**: 61 — Blocks 19. Proves the coordinator is genuinely platform-neutral. Deferring this is how the seam silently becomes AppKit-only.

**Entry criteria**:
- [ ] Sortie 10 exit criteria met

**Tasks**:
1. Build the iOS Representable: self-scrolling `UITextView`, TextKit 2, bound to the
   **same** coordinator instance type as macOS — no parallel iOS coordinator.
2. Disable smart quotes, smart dashes, and autocorrect by default; expose a host opt-in
   for autocorrect only.
3. Skip restyling while `markedTextRange != nil`.
4. Accept UIKit's native undo granularity. Do **not** add an undo seam here
   (REQUIREMENTS.md Known limitations §1) — and do not shape the macOS seam so UIKit
   cannot later adopt it.

**Exit criteria**:
- [ ] `make test-ios` exits 0
- [ ] `make test` exits 0 (macOS not regressed)
- [ ] The coordinator type used by both Representables is the same declared type
      (asserted by a test that instantiates it under both `#if os(macOS)` and
      `#if os(iOS)`)
- [ ] A test asserts `autocorrectionType == .no` and `smartQuotesType == .no` and
      `smartDashesType == .no` by default
- [ ] `grep -rn 'markedTextRange' Sources/SwiftEscribo/` shows the restyle path guarded

### Sortie 12: SwiftUI `EscriboEditor` view, binding hygiene, and mode switching

**Priority**: 58 — Blocks 18. Completes WU-2 and is the fork point for both layer-2 work units.

**Entry criteria**:
- [ ] Sortie 11 exit criteria met

**Tasks**:
1. Build the SwiftUI view bound to `@Binding var text: String` with a `Language`
   selection and an `EditorMode`.
2. Implement external-replacement rule 1: **if the incoming string equals current
   storage contents, do nothing.** This is correctness, not optimization — without it
   SwiftUI feeds the editor its own output.
3. Implement rules 2–4: replace the full range with `replaceCharacters(in:with:)`
   inside `beginEditing()`/`endEditing()`, then full-scan and restyle; clamp selection
   to the new length rather than dropping it to zero; register as a single undo action.
4. Implement live↔source mode switching as a **theme swap only** — no content
   transformation, no branch on mode inside the styler.

**Exit criteria**:
- [ ] `make test` exits 0 and `make test-ios` exits 0
- [ ] A test asserts setting the binding to a string equal to current storage performs
      **zero** text-storage mutations
- [ ] A test asserts setting the binding to a shorter string clamps a previously
      out-of-range selection to the new length
- [ ] A test asserts switching live→source→live leaves `text` **byte-identical**
- [ ] `grep -rE 'EditorMode|\.source|\.live' Sources/SwiftEscribo/*Styler*` shows no
      mode branch inside the styler

---

## WU-3 — Fountain Depth

### Sortie 13: Fountain block elements

**Priority**: 43 — Blocks 13. Registers the Fountain element vocabulary the rest of WU-3 and the writer consume.

**Entry criteria**:
- [ ] Sortie 12 exit criteria met

**Tasks**:
1. Scene headings, including the forced `.` prefix, with the `.` emitted as a `.marker`
   span and preserved in the `LineRecord`.
2. Action, transitions (including forced `>`), and centered text (`>text<`).
3. Sections (`#`) with `depth`, synopses (`=`), page breaks (`===`), lyrics (`~`).
4. Preserve every forced-element marker in the line record — the writer needs them
   (Architecture §9), and discarding them is not recoverable later.
5. Register `ElementKind` static members for each, and `SpanKind` members for their
   markers and content.

**Exit criteria**:
- [ ] `make test-core` exits 0
- [ ] The Sortie 6 invariant helper passes on every Fountain scan
- [ ] A test asserts `.INT. HOUSE` (forced) and `INT. HOUSE` (natural) produce the same
      `ElementKind` but distinguishable line records
- [ ] A test asserts `===` scans as a page break and `==` does not
- [ ] A test asserts `>CENTERED<` and `> TRANSITION` produce different `ElementKind`s

### Sortie 14: Dialogue block — cues, extensions, parentheticals, dual dialogue

**Priority**: 42.5 — Blocks 12. The lookahead declaration is the single most likely source of correct-on-full-parse / wrong-while-typing.

**Entry criteria**:
- [ ] Sortie 13 exit criteria met

**Tasks**:
1. Implement character-cue detection: an ALL-CAPS line recognized **only by what
   follows it** — one line of lookahead.
2. Declare that lookahead to the convergence engine so rescanning extends **one line
   past the match point** (Fountain §4 — the single most likely source of
   "correct on full parse, wrong while typing").
3. Implement forced cues (`@`), cue extensions (`(V.O.)`, `(CONT'D)`), parentheticals,
   and dialogue lines.
4. Implement dual dialogue (`^`), preserving the caret in the line record.
5. Carry in-dialogue-block state in `LineState`.

**Exit criteria**:
- [ ] `make test-core` exits 0
- [ ] The gate test from Sortie 6 is extended with Fountain seed documents and passes
      ≥200 sequences
- [ ] A test asserts typing a word on the line **after** `BOB` retroactively
      reclassifies `BOB` from action to character cue, **and** that the incremental
      result equals the full-scan result for that edit
- [ ] A test asserts deleting that following word reclassifies `BOB` back to action
- [ ] A test asserts an ALL-CAPS line at EOF is action, not a cue
- [ ] A test asserts `@McAvoy` is a cue despite not being ALL-CAPS

### Sortie 15: Notes, boneyard, and title page

**Priority**: 23 — Blocks 6. Multi-line state (boneyard, title page) the writer must round-trip losslessly.

**Entry criteria**:
- [ ] Sortie 14 exit criteria met

**Tasks**:
1. Implement notes `[[ ]]`, including notes spanning multiple lines.
2. Implement boneyard `/* */` as multi-line state carried in `LineState`; unterminated
   boneyard scans to end of document without failing.
3. Implement the title page as a distinct leading region with **arbitrary keys**.
4. Preserve non-standard title-page keys **verbatim** — spelling, casing, and order.
   `verbsCovered:` and `Abstract:` are real keys in this org's documents.
5. Carry title-page key/value ranges in the line record so the writer can round-trip
   them (Architecture §9).

**Exit criteria**:
- [ ] `make test-core` exits 0
- [ ] A test asserts `verbsCovered:` and `Abstract:` survive a scan with byte-identical
      key text and original ordering
- [ ] A test asserts an unterminated `/*` scans to the last code unit and returns
      normally
- [ ] A test asserts a `[[note]]` inside dialogue does not terminate the dialogue block
- [ ] The gate test includes fence/boneyard open-and-close edit sequences and passes

### Sortie 16: GLOSA structural tokens inside notes

**Priority**: 18 — Blocks 5. GLOSA span structure, additive over notes.

**Entry criteria**:
- [ ] Sortie 15 exit criteria met

**Tasks**:
1. Inside a note, scan GLOSA directives **structurally**: tag name, attribute names,
   attribute values, and punctuation each get their own `SpanKind`.
2. Support the tag forms in use: `<breath>`, `<pause>`, `<shot/>`, `<include/>`,
   `<SceneContext>`, `<Intent>`, `<Constraint>`.
3. Add **no semantic validation** — whether `breath` is a legal tag and `4s` a legal
   length is `GlosaCore`'s business, and duplicating that spec here is a non-goal.
4. Degrade malformed GLOSA to `.text` rather than failing.

**Exit criteria**:
- [ ] `make test-core` exits 0
- [ ] A test asserts `[[<breath length="4s" strength="strong"/>]]` yields distinct spans
      for tag name, each attribute name, each attribute value, and the punctuation
- [ ] A test asserts `[[<breath length=>]]` (malformed) produces spans that still tile
      the range and contains no crash
- [ ] `grep -riE '(valid|legal|allowed)(Tag|Attribute)' Sources/EscriboCore/` returns no
      matches — no tag or attribute whitelist exists

### Sortie 17: Fountain golden fixture corpus, including hostile input

**Priority**: 17 — Blocks 4. The fixture corpus gates the writer, the differential oracle, and the performance suite.

**Entry criteria**:
- [ ] Sortie 16 exit criteria met

**Tasks**:
1. Create `Tests/EscriboCoreTests/Fixtures/Fountain/` and **vendor** fixture files into
   the repository (D-3). No test may reference a path outside the repo.
2. Vendor these three real screenplays from `~/Projects/apps/Produciesta/fixtures/`,
   copying them in as a one-time import — the source path is never referenced at
   test time:
   - `episode_10.fountain` (9.3 KB)
   - `spanish.fountain` (6.9 KB) — non-ASCII dialogue
   - the Fountain body of `episode_01.highland` (27.3 KB, 885 lines), extracted from
     `episode_01.textbundle/text.md` inside the archive and saved as
     `episode_01.fountain`. A `.highland` file is a zip; extract it during the sortie
     and commit the extracted Fountain, not the archive.
3. Author hostile fixtures: an ALL-CAPS line at EOF, malformed GLOSA tags, unterminated
   boneyard, CRLF line endings, mixed terminators, and astral-plane characters in
   dialogue.
4. Load fixtures through `Bundle.module` — never an absolute path, never `#filePath`
   arithmetic that escapes the package. `Package.swift` currently declares **no**
   `resources:` on any test target; add it to `EscriboCoreTests`.
5. Add golden span/record snapshots and assert the Sortie 6 invariant helper on each.
   Drive the corpus through `@Test(arguments:)` so one failing fixture names itself.

**Exit criteria**:
- [ ] `make test-core` exits 0
- [ ] `grep -rE '/Users/|~/Projects|#filePath' Tests/` returns no matches
- [ ] `Package.swift` declares `resources:` for the fixture directory and `make build`
      exits 0
- [ ] All three vendored screenplays load via `Bundle.module` and scan without error
- [ ] Every fixture is scanned by both full scan and incremental scan and the results
      are asserted equal
- [ ] The corpus contains ≥8 fixture files

---

## WU-4 — Markdown Breadth

### Sortie 18: CommonMark block structure

**Priority**: 35 — Blocks 10. On the critical path — ahead of all Fountain depth past Sortie 14.

**Entry criteria**:
- [ ] Sortie 12 exit criteria met (WU-2 complete)

**Tasks**:
1. Extend beyond Sortie 5: indented code blocks using the CommonMark **4-column tab
   stop**, not a tab width of 1.
2. Ordered and unordered lists with nesting, populating `LineRecord.depth`.
3. Blockquotes (nested), thematic breaks (`---`, `***`, `___`).
4. Ensure all column arithmetic counts **UTF-16 code units**, and any place meaning
   "visual column" says so explicitly in its name or a comment.

**Exit criteria**:
- [ ] `make test-core` exits 0
- [ ] A test asserts a tab at column 0 advances to column 4, and a tab at column 2
      advances to column 4
- [ ] A test asserts a three-level nested list yields `depth` 0, 1, 2
- [ ] A test asserts `---` after a paragraph line is a setext heading, not a thematic
      break
- [ ] A test asserts an emoji before an indent marker does not shift the computed
      column by 1 (code units, not characters)

### Sortie 19: CommonMark inline structure

**Priority**: 30.5 — Blocks 9. Inline flattening is the hardest Markdown algorithm.

**Entry criteria**:
- [ ] Sortie 18 exit criteria met

**Tasks**:
1. Emphasis, strong, and their combination, flattened at scan time into consecutive
   tiling spans carrying the **union** of covering styles — never a tree.
2. Code spans (backtick runs of arbitrary length), links, images, hard breaks.
3. Emit `.marker` spans for every delimiter, carrying the same `kind` and `style` as
   the content they wrap.
4. Emit `.linkURL` and related `SpanKind`s so a URL can be styled distinctly from link
   text.
5. Guarantee no span boundary splits a surrogate pair.

**Exit criteria**:
- [ ] `make test-core` exits 0
- [ ] A test asserts `` **bold `code` bold** `` produces consecutive spans where the
      code span carries `[.strong, .inlineCode]`
- [ ] A test asserts deleting one `*` from `**bold**` produces a `dirtyRange` covering
      the whole former bold run, so no stale attribute can survive
- [ ] A test asserts every span boundary in an emoji-dense fixture falls between
      surrogate pairs
- [ ] The invariant helper passes on all inline tests

### Sortie 20: GFM extensions and YAML frontmatter

**Priority**: 27 — Blocks 8. Frontmatter state must exist before list continuation reads it.

**Entry criteria**:
- [ ] Sortie 19 exit criteria met

**Tasks**:
1. Tables (delimiter row, alignment cells), task-list checkboxes, strikethrough,
   autolinks.
2. YAML frontmatter as a **distinct leading region** with key and value spans — not a
   thematic break followed by garbage.
3. Frontmatter only at document start, delimited by `---`; carried in `LineState` so
   convergence works across it.
4. Unterminated frontmatter degrades to `.text` and scans to end of document.

**Exit criteria**:
- [ ] `make test-core` exits 0
- [ ] A test asserts a document opening with `---\ntype: docs\n---` produces frontmatter
      key/value spans and **not** a thematic break
- [ ] A test asserts `---` on line 5 (not line 1) is a thematic break
- [ ] A test asserts `- [ ]` and `- [x]` produce distinguishable checkbox spans
- [ ] A test asserts a table alignment row `|:---|---:|` produces alignment-bearing line
      records

### Sortie 21: Fountain inside Markdown

**Priority**: 7.5 — Blocks 1. The nested-scanner offset case, gated on both language scanners being complete.

**Entry criteria**:
- [ ] Sortie 20 exit criteria met
- [ ] Sortie 17 exit criteria met (Fountain scanner complete)

**Tasks**:
1. A fence tagged `fountain` scans its contents with the Fountain scanner.
2. The inner scan is **offset, not separate** — spans come back in outer-document
   coordinates. The inner scanner is **never handed a substring**; that would allocate
   per keystroke and lose the offset.
3. The inner Fountain state is part of the outer `startState`. A `startState` that only
   records "we are in a fence" converges early inside the block.
4. One level, no recursion: Markdown may host Fountain; Fountain hosts nothing.
5. An unterminated `fountain` fence scans to end of document, does not fail, and does
   **not** fall back to Markdown.

**Exit criteria**:
- [ ] `make test-core` exits 0
- [ ] A test asserts every span inside a `fountain` fence has offsets that index
      correctly into the **outer** document string
- [ ] A test asserts editing a dialogue line inside a fenced Fountain block yields
      `incrementalScan == fullScan` (this is the convergence-across-boundary case)
- [ ] A test asserts an unterminated ```` ```fountain ```` fence produces Fountain spans
      to EOD, not Markdown spans
- [ ] The gate test corpus includes a Fountain-in-Markdown document and passes

### Sortie 22: `swift-markdown` differential oracle

**Priority**: 3 — Terminal. The differential oracle validates the Markdown scanner but nothing depends on it.

**Entry criteria**:
- [ ] Sortie 21 exit criteria met

**Tasks**:
1. Add `swift-markdown` to `Package.swift` as a dependency of **`EscriboCoreTests`
   only**. No shipping target may reference it. Declare it
   `.upToNextMajor(from: "<latest published release>")` per collection convention —
   resolve the floor from the package's GitHub releases when the sortie runs; do not
   copy a version number from this plan.
2. Write the differential test: for each Markdown fixture, assert block-structure
   agreement between `EscriboCore`'s line records and `swift-markdown`'s parse. Drive
   it through `@Test(arguments:)` over the fixture list.
3. Add a `no_markdown_import_in_sources` custom rule to `.swiftlint.yml`, matching the
   two rules already defined there (`no_regex_in_scanners`, `no_ui_imports_in_core`).
   It fires on any `import Markdown` under `Sources/`. **Defining** the rule is this
   sortie's job; **enforcing** it in CI is Sortie 30's, which creates the lint job.
4. Document in a `.swiftlint.yml` comment *why* the rule exists: SwiftPM prunes
   test-only dependencies as a graph property, not a declaration
   ([SPM#7007](https://github.com/swiftlang/swift-package-manager/issues/7007)), so the
   day a shipping target imports `Markdown` it silently becomes a dependency of every
   consumer with no error. See D-2.

**Exit criteria**:
- [ ] `make test-core` exits 0
- [ ] `grep -rn 'import Markdown' Sources/` returns no matches
- [ ] `grep -n 'no_markdown_import_in_sources' .swiftlint.yml` matches
- [ ] `grep -rn 'swift-markdown' Package.swift` shows it reachable only from
      `EscriboCoreTests` — no shipping target lists it in `dependencies:`
- [ ] The differential test covers ≥6 Markdown fixtures

---

## WU-5 — Writer

Built after the scanner, which is only cheap because Architecture §9 (lossless line
records) has held since Sortie 13.

### Sortie 23: Canonical Fountain writer — body elements

**Priority**: 8 — Blocks 1. The writer's body path, which title-page writing extends.

**Entry criteria**:
- [ ] Sortie 17 exit criteria met

**Tasks**:
1. Emit well-formed Fountain from `[LineRecord]` for scene headings, action,
   transitions, centered text, sections, synopses, page breaks, and lyrics.
2. Emit dialogue blocks: cues (including forced `@` and extensions), parentheticals,
   dialogue, and dual dialogue carets.
3. Preserve every forced-element marker that the record carries.
4. Preserve line terminators as recorded — `\r\n` stays `\r\n` (Text model).
5. Emit notes and boneyard verbatim, including their GLOSA contents.

**Exit criteria**:
- [ ] `make test-core` exits 0
- [ ] A test asserts a CRLF document written from its records still contains `\r\n` and
      zero bare `\n`
- [ ] A test asserts a forced scene heading `.HOUSE` writes back with its leading `.`
- [ ] A test asserts a dual-dialogue caret survives the write
- [ ] `grep -rE '^\s*import (SwiftUI|AppKit|UIKit)' Sources/EscriboCore/` still returns
      no matches

### Sortie 24: Title-page writing and the idempotence gate

**Priority**: 3 — Terminal. The idempotence gate.

**Entry criteria**:
- [ ] Sortie 23 exit criteria met

**Tasks**:
1. Write the title page with **arbitrary keys preserved verbatim** — spelling, casing,
   and original order.
2. Implement the idempotence test: `parse(write(parse(x))) == parse(x)`.
3. Do **not** assert `write(parse(x)) == x` — writing normalizes, so that assertion
   fails on any non-canonical input and is the wrong formulation.
4. Run idempotence across the full Sortie 17 fixture corpus, hostile fixtures included.

**Exit criteria**:
- [ ] `make test-core` exits 0
- [ ] The idempotence assertion passes on **every** fixture in the corpus
- [ ] A test asserts `verbsCovered:` writes back with that exact casing and in its
      original position relative to other keys
- [ ] `grep -rn 'write(parse(' Tests/ | grep -v 'parse(write(parse('` returns no
      matches — the wrong formulation is not present anywhere
- [ ] A test asserts idempotence holds for a document whose title page has a duplicate
      key

---

## WU-6 — Editor Behavior

### Sortie 25: Markdown list continuation with coalesced undo

**Priority**: 19.5 — Blocks 5. Undo coalescing through the input path — the pattern Sortie 26 reuses.

**Entry criteria**:
- [ ] Sortie 20 exit criteria met
- [ ] Sortie 12 exit criteria met

**Tasks**:
1. Implement continuation, **not conversion** — markers are never hidden, so typing
   `# ` needs no shortcut. Return at end of `- item` inserts `\n- `; at end of
   `3. item` inserts `\n4. `; at end of `- [ ] item` inserts `\n- [ ] ` always
   unchecked; at end of an indented nested item continues at the same indent.
2. Return on an item empty apart from its marker **deletes the marker**, leaving an
   empty line, and does not insert another.
3. Route every rewrite through the text view's own input path **in the same transaction
   as the user's keystroke** — mutating text storage after the fact registers a second
   undo group that no amount of `NSUndoManager` grouping reliably merges.
4. Do **not** implement ordered-list renumbering of following items — explicitly
   deferred.
5. Paste inserts verbatim, no transformation, as a single undo action, rescanned as an
   ordinary edit.

**Exit criteria**:
- [ ] `make test` exits 0
- [ ] A test asserts Return-then-Cmd-Z on `- item` returns the document to **exactly**
      its prior state in **one** undo, not character by character
- [ ] A test asserts Return on `- ` (marker only) yields an empty line with no marker
- [ ] A test asserts Return at end of `3. item` inserts `4. `
- [ ] A test asserts pasting a 10-line block is a single undo action
- [ ] `grep -rniE 'renumber' Sources/SwiftEscribo/` returns no matches

### Sortie 26: Fountain smart Tab and Return

**Priority**: 16.5 — Blocks 4. Fountain affordances built on the Sortie 25 undo pattern.

**Entry criteria**:
- [ ] Sortie 25 exit criteria met
- [ ] Sortie 14 exit criteria met

**Tasks**:
1. Tab on an empty line whose previous block is dialogue or blank begins a character
   cue; on a cue moves to the next line as dialogue; on a dialogue line wraps the line
   in `()` as a parenthetical; on a parenthetical moves to the next line as dialogue.
2. Return on a cue moves to the next line as dialogue with **no blank line between**;
   on a parenthetical or dialogue line continues dialogue.
3. **When context is ambiguous, insert a literal tab or newline.** An affordance that
   guesses is worse than no affordance.
4. Route through the input path as one coalesced undo action, as in Sortie 25.
5. Apply the same affordances on iOS, accepting UIKit's native undo granularity
   (Known limitations §1).

**Exit criteria**:
- [ ] `make test` exits 0 and `make test-ios` exits 0
- [ ] A test enumerates all five rows of the Tab column in REQUIREMENTS.md
      § Fountain Tab and Return (lines 472–478) and asserts the resulting document text
      for each, driven by `@Test(arguments:)` so a failing row names itself
- [ ] A test asserts Tab in an ambiguous context inserts exactly one `\t` and nothing
      else
- [ ] A test asserts Tab-then-Cmd-Z on macOS restores the prior state in one undo
- [ ] A test asserts Return on a character cue produces a dialogue line with no
      intervening blank line

### Sortie 27: Fountain and Markdown paragraph geometry rule sets

**Priority**: 12 — Blocks 3. Populates both geometry rule sets against the Sortie 8 layer.

**Entry criteria**:
- [ ] Sortie 26 exit criteria met
- [ ] Sortie 8 exit criteria met

**Tasks**:
1. Populate the Fountain geometry table: character-cue, dialogue, and parenthetical
   margins in characters at 10 CPI; right-aligned transitions; centered text.
2. Populate the Markdown geometry table: heading size scale, list and blockquote
   indents via `firstLineHeadIndent` / `headIndent`, keyed by `(ElementKind, depth)`.
3. One geometry layer, two rule sets — no second code path.
4. Size varies **per line, never within a line**: markers are never resized
   (Architecture §3).
5. Fountain paragraph geometry is LTR-only; Markdown uses natural alignment and works
   in RTL. This is a scope statement, not a defect — assert it rather than fixing it.

**Exit criteria**:
- [ ] `make test` exits 0 and `make test-ios` exits 0
- [ ] A test asserts a character cue and a dialogue line receive different
      `headIndent` values, both derived from the resolved advance width
- [ ] A test asserts a heading's marker span and its content span resolve to the
      **same point size** despite the heading's size scale
- [ ] A test asserts a Markdown list at depth 2 has exactly twice the indent of depth 1
- [ ] A test asserts Fountain geometry uses `.natural` nowhere and Markdown geometry
      uses it for paragraphs

---

## WU-7 — Verification and Release Hardening

### Sortie 28: Performance suite

**Priority**: 9 — Blocks 2. Performance gate before release hardening.

**Entry criteria**:
- [ ] Sortie 27 exit criteria met
- [ ] Sortie 17 exit criteria met (the three vendored screenplays exist — this sortie
      assembles its fixture from them)
- [ ] Sortie 22 exit criteria met (Markdown scanner complete)

**Tasks**:
1. Populate `Tests/EscriboPerformanceTests/` with a ~120 KB screenplay fixture
   (~120 pages), vendored into the repo. **Assemble it** by concatenating the three
   screenplays vendored in Sortie 17 (`episode_10`, `spanish`, `episode_01` — ~44 KB
   combined) and repeating the sequence until it reaches ~120 KB (D-3). Repetition is
   acceptable here because this measures scan throughput, not narrative structure — the
   scanner does not care that scene 40 duplicates scene 12. Commit the assembled file
   as a fixture; do not generate it at test time.
2. Assert **scan time only** — the scanner returning a dirty range and its spans,
   measured in `EscriboCore` with no UI. Do not assert end-to-end frame time; observe
   and report it instead.
3. Measure over the pathological sequence, not average typing: an edit at line 1 of the
   long document, an edit inside an unterminated fence, an edit inside an unterminated
   boneyard, and a 10 KB paste.
4. Assert the budgets: typical in-line edit with unchanged state ≤ 1 ms; cold full scan
   ≤ 50 ms with a 10 ms target reported.
5. Add a separate GitHub Actions workflow for the performance suite, **not** triggered
   on pull request, on `runs-on: macos-26`, pinning `arch=arm64` and `ARCHS=arm64`.

**Exit criteria**:
- [ ] `make test-performance` exits 0
- [ ] `make test` still exits 0 with performance excluded
- [ ] The assembled fixture is ≥110 KB and loads via `Bundle.module`
- [ ] `.github/workflows/` contains a performance workflow whose triggers do **not**
      include `pull_request`
- [ ] That workflow declares `runs-on: macos-26`
- [ ] Every `xcodebuild` invocation in that workflow contains both
      `arch=arm64` and `ARCHS=arm64`
- [ ] The suite prints a line matching `cold-scan: <N> ms` to stdout, verified by
      grepping the test output — the 10 ms target is reported, not asserted, so a 5×
      regression is visible before the 50 ms ceiling is hit
- [ ] A `LineIndex` linearity case asserts a 1 MB single line indexes within 4× the time
      of a 250 KB single line (moved here from Sortie 3)

### Sortie 29: SwiftLint enforcement in CI

**Priority**: 6 — Blocks 1. The custom lint rules are documentation until this job runs them.

**Entry criteria**:
- [ ] Sortie 28 exit criteria met

**Tasks**:
1. Add a SwiftLint CI job on `runs-on: macos-26`. `.swiftlint.yml` defines
   `no_regex_in_scanners` and `no_ui_imports_in_core`, and Sortie 22 adds
   `no_markdown_import_in_sources`, but **no CI job currently runs any of them** — all
   three are documentation until this exists.
2. Prove all three custom rules can fail: add `NSRegularExpression` to a scanner, an
   `import UIKit` to `EscriboCore`, and an `import Markdown` to `EscriboCore` on a
   scratch branch; confirm red for each; revert. Record evidence. A rule that has never
   failed is indistinguishable from one that cannot.
3. Make the job's exit status gate the workflow — a lint job that reports without
   failing is the same as no job.

**Exit criteria**:
- [ ] `make build`, `make test`, and `make lint` all exit 0
- [ ] The CI job invokes the existing `make lint` target rather than calling `swiftlint`
      directly, so local and CI enforcement cannot drift
- [ ] `.github/workflows/` contains a lint job declaring `runs-on: macos-26`
- [ ] The SwiftLint job passes on the mission branch and its exit status gates the
      workflow (no `continue-on-error`, no `|| true`)
- [ ] The sortie report contains evidence of **all three** custom rules failing when
      deliberately violated — log excerpts or run URLs, not claims
- [ ] `grep -n 'no_markdown_import_in_sources\|no_regex_in_scanners\|no_ui_imports_in_core' .swiftlint.yml`
      returns all three rule names

### Sortie 30: Public API surface audit and 1.0 documentation

**Priority**: 2 — Terminal. API surface audit and 1.0 documentation.

**Entry criteria**:
- [ ] Sortie 29 exit criteria met
- [ ] Sortie 24 exit criteria met (writer complete — the audit must see the full public
      surface, and the writer is the last thing to add to it)

**Tasks**:
1. Audit the public surface against REQUIREMENTS.md § What is public in 1.0. Anything
   not in that list, and not consumed by `SwiftEscribo` or a test, becomes `internal`.
2. Confirm `LineState` exposes no public cases, properties, or initializers.
3. Update `CHANGELOG.md` and `README.md` to describe the shipped 1.0 surface.

**Exit criteria**:
- [ ] `make build`, `make test`, `make test-ios`, and `make test-performance` all exit 0
- [ ] Every `public` declaration in `Sources/EscriboCore/` appears in the
      REQUIREMENTS.md § What is public in 1.0 list, or is justified in the report
- [ ] The sortie report lists every declaration demoted to `internal`, with a count
- [ ] A test file importing `EscriboCore` **without** `@testable` still compiles and
      exercises every documented 1.0 entry point
- [ ] `CHANGELOG.md` has a 1.0 entry
- [ ] `README.md` documents the `EscriboCore` / `SwiftEscribo` split and the zero-
      dependency charter

---

## Parallelism Structure

**Critical path** (21 of 30 sorties):

```
S1 → S2 → S3 → S4 → S5 → S6 → S7 → S8 → S9 → S10 → S11 → S12
   → S18 → S19 → S20 → S25 → S26 → S27 → S28 → S29 → S30
```

**Parallel execution groups**:

| Group | Sorties | Concurrency | Notes |
|-------|---------|-------------|-------|
| **A** — layers 0–1 | S1 → S12 | **1** (strictly serial) | 12 sorties, 40% of the mission, no parallelism available. Each sortie's exit criteria are the next's entry criteria. |
| **B** — layer 2, forks at S12 | B1: S13→S14→S15→S16→S17 (Fountain)<br>B2: S18→S19→S20 (Markdown) | **2** | The two scanners touch disjoint files and share only the Sortie 4 seam and the Sortie 6 invariant helper, both frozen by then. |
| **C** — layer 3, needs S17 + S20 | C1: S21→S22<br>C2: S23→S24<br>C3: S25→S26→S27 | **3** | Highest concurrency in the plan. C2 (writer) is `EscriboCore`; C3 (editor behavior) is `SwiftEscribo`; C1 straddles both scanners but adds no files they own. |
| **D** — layer 4 | S28 → S29 → S30 | **1** | Sequential hardening. |

**Maximum theoretical parallelism**: 3 concurrent branches (Group C).

**Agent constraints — the binding limit here**:

Every sortie in this plan writes Swift and carries a `make build`, `make test`, or
`make test-core` exit criterion. Under the supervisor rule that **only the supervising
agent runs builds**, **all 30 sorties are supervising-agent-only**. Sub-agents can take
only the build-free slices of a sortie, dispatched as helper work alongside the
supervising agent's build loop:

| Sub-agent task | Sortie | Why it needs no build |
|----------------|--------|----------------------|
| Author the hostile Fountain fixtures (ALL-CAPS at EOF, malformed GLOSA, unterminated boneyard, CRLF, mixed terminators, astral-plane dialogue) | S17 task 3 | Pure text authoring |
| Assemble the ~120 KB performance fixture from the three vendored screenplays | S28 task 1 | File concatenation |
| Draft the performance workflow YAML | S28 task 5 | Config authoring; validated by the supervising agent |
| Draft the SwiftLint workflow YAML | S29 task 1 | Same |
| Draft `CHANGELOG.md` and `README.md` 1.0 prose | S30 task 3 | Documentation |

**Recommended allocation**: 1 supervising agent + **2 sub-agents**. A larger sub-agent
pool has nothing to do — the build-free work above totals roughly one sortie's worth of
effort spread across five sorties.

**Missed opportunity — worth considering before `start`**:

Sorties 7 and 8 (theme, styler, paragraph geometry) are placed after Sortie 6 (the gate
property test), but they do **not** depend on it. Their real dependencies are the kind
vocabulary (S1) and the span model (S2). They could fork from S2 and run concurrently
with S3–S6, shortening the critical path by up to 4 sorties.

The reason the plan does **not** do this: Sortie 7's exit criteria assert styling
behavior over "every span in a mixed document", which presumes a working scanner (S5).
Forking early would require rewriting those criteria to hand-construct spans instead of
scanning for them — which is a weaker test, because hand-built spans cannot catch a
styler that mishandles a span shape the scanner actually emits. **Trading a real
integration assertion for 4 sorties of wall clock is a bad trade on a package whose
entire risk is the scanner→styler seam.** Left serial deliberately; revisit only if the
critical path becomes the binding constraint.

---

## Settled Decisions

<!-- Resolved by Pass 1 of refine (`refine-blockers`) on 2026-07-25. No blocking open
     questions remain. Recorded here because sorties reference them by ID. -->

REQUIREMENTS.md § Open questions declares "**None**", and that holds for the *design*
questions. The four below were **execution** decisions the requirements document either
explicitly left untested or never had reason to address. All four are now settled.

### D-1: Test framework — swift-testing

**Affects**: Sortie 2, and every sortie that writes tests
**Decision**: **swift-testing** (`import Testing`, `@Test`, `#expect`). No test target
imports XCTest. Use `@Test(arguments:)` for the seeded gate test (Sortie 6), the fixture
corpus (Sortie 17), and the differential oracle (Sortie 22).
**Rationale**: Verified against the collection — SwiftAcervo 107 files / 0 XCTest,
SwiftSecuencia 45/0, SwiftVoxAlta 35/0, SwiftCompartido 85/9; only the older SwiftBruja
is XCTest-only. `Package.swift` is already `swift-tools-version: 6.2` with
`swiftLanguageModes: [.v6]`, so parameterized tests need no new dependency.
Parameterized cases map directly onto the "≥200 seeded edit sequences" and "every
fixture in the corpus" exit criteria that five sorties here depend on.

### D-2: `swift-markdown` containment — lint rule, not a consumer package

**Affects**: Sortie 22, Sortie 30
**Decision**: **No throwaway consumer package, and no CI resolution guard.** Containment
is enforced by a `no_markdown_import_in_sources` SwiftLint custom rule (defined in
Sortie 22, enforced by the lint job in Sortie 30) plus
`grep -rn 'import Markdown' Sources/`. `swift-markdown` itself is declared
`.upToNextMajor(from: "<latest published release>")` on `EscriboCoreTests` only, per
collection convention.
**Rationale**: The failure mode is exactly one thing — a shipping target referencing
`Markdown` — and this package graph is two shipping targets and three test targets, all
visible in one screen of `Package.swift`. There is no indirect path to a product that a
grep of `Sources/` plus `Package.swift` would miss. `.swiftlint.yml` already defines two
custom rules of this exact shape, so the mechanism exists and Sortie 30 must build the
job that runs them regardless. The consumer-package approach additionally **cannot work
before 1.0 is published**: with no released version to depend on, a version-floor
dependency resolves nothing, and a guard that cannot run is indistinguishable from one
that cannot fail. The measured pruning property (REQUIREMENTS.md § Test-only
dependencies) still holds and is still the reason the rule exists — it is simply
asserted at the import site rather than at the resolution site.

### D-3: Fixture provenance — vendor from Produciesta

**Affects**: Sortie 17, Sortie 28
**Decision**: **Vendor into the repo** under `Tests/EscriboCoreTests/Fixtures/Fountain/`,
loaded via `Bundle.module`, with a `resources:` declaration added to `EscriboCoreTests`
(currently absent). Sources, all from `~/Projects/apps/Produciesta/fixtures/`:
`episode_10.fountain` (9.3 KB), `spanish.fountain` (6.9 KB), and the Fountain body of
`episode_01.highland` (27.3 KB, extracted from `episode_01.textbundle/text.md`).
The ~120 KB performance fixture (Sortie 28) is **assembled** by concatenating and
repeating those three to reach target size. A grep exit criterion forbids `/Users/`,
`~/Projects`, and `#filePath` anywhere under `Tests/`.
**Rationale**: An absolute path under `~/Projects` does not exist on a GitHub Actions
runner, and CI is the primary build mechanism — a locally-gated test is exactly the
class this mission's `test-cleanup` phase would delete afterward. All three files are the
user's own podcast content, so there is no licensing obstacle to committing them. The
folder holds ~44 KB of Fountain total, short of Sortie 28's ~120 KB target; repetition
closes the gap and is sound for a scan-throughput benchmark, which is insensitive to
narrative uniqueness.

### D-4: Screenplay font resolution — monospaced system fallback

**Affects**: Sortie 8, Sortie 27
**Decision**: **Extend the chain to a final `.monospacedSystemFont` fallback**, and
forbid any test from asserting a resolved family name. Tests assert the *property* that
makes 10 CPI geometry correct — the face is monospaced (equal advance for `i` and `W`),
and indents scale linearly with the resolved advance width. **No font is bundled** as a
package resource.
**Rationale**: Courier Prime is installed on this development machine but is a
user-installed font, not a system font; none of the three Courier faces is guaranteed on
a CI runner or an iOS device. A geometry test asserting Courier Prime's advance width
passes locally and fails in CI — a flaky test authored on day one and diagnosed on day
thirty. REQUIREMENTS.md § Theme already stores geometry in characters and converts
against "the resolved font's advance width", so correctness depends on the face being
monospaced, not on which monospaced face it is. Bundling Courier Prime would add a
licensed binary resource to a package whose charter is zero dependencies, for a property
the design does not need.

---

## Summary

| Metric | Value |
|--------|-------|
| Work units | 7 |
| Total sorties | 30 |
| Open questions | 0 — all 4 settled (D-1…D-4) |
| Dependency structure | 5 layers (0 → 4), with WU-3 and WU-4 parallel at layer 2 and WU-5 and WU-6 parallel at layer 3 |
| Critical path | 21 of 30 sorties |
| Max parallelism | 3 concurrent branches (layer 3) |
| Agent allocation | 1 supervising + 2 sub-agents (build-free slices only) |
| Refined | Passes 1–5 complete, 2026-07-25 |
