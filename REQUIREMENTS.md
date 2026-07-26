---
type: project
title: SwiftEscribo — Requirements
updated: 2026-07-25
---

# SwiftEscribo

*Escribo* — "I write." A stylized SwiftUI text editor for Markdown and Fountain,
and the canonical Fountain parsing and formatting library for the collection.

Inspired by [writemark](https://github.com/Brostoffed/writemark) — text that renders
as you type rather than sitting in a raw monospace box. Writemark itself is a
`contenteditable` web component and is a reference for *feel*, not architecture.

## Why this exists

This is background on why an existing parser was not reused. It is **not** a plan to
integrate with one — see Non-goals §9.

`SwiftCompartido` already parses Fountain (`FountainParser.swift`,
`FountainRegexes.swift`) and Markdown (`MarkdownParser.swift`), and ships a
`GuionTextEditor`. None of it can back an editor:

1. `GuionTextEditor` is read-only (`isEditable = false`) — a viewer, not an editor.
2. `GuionElement` (`Sources/SwiftCompartido/Sendable/GuionElement.swift:161`) carries
   **no source range, line number, or offset**, and its `elementText` is stripped of
   markup (`FountainParser.swift:330,363`). Highlighting needs the inverse mapping —
   source range → token kind — which that design discards. This is structural, not a
   performance problem.
3. The regexes are buggy and, being `NSRegularExpression` over the whole document
   with cross-line lookbehind, cannot meet a per-keystroke budget.

SwiftEscribo replaces all of it.

## Requirements

1. Swift package, library only — **no CLI target**. Follows the pattern of the other
   `../Swift*` libraries.
2. Platforms: macOS 26.0+, iOS 26.0+. Swift 6.2+, Swift 6 language mode,
   `StrictConcurrency`. **Apple Silicon only — `arm64`.** Intel and Rosetta are out
   of scope, and the arch is pinned explicitly on every `xcodebuild` invocation
   (`arch=arm64` in the destination plus `ARCHS=arm64`) rather than inferred. An
   unpinned destination can resolve to x86_64 or build universal — wasted time on a
   slice nobody ships, and worse, a performance suite reporting numbers from an
   architecture that is not the target. Enforced in the `Makefile` and both CI jobs.
3. **Zero runtime dependencies.** This is what makes the parser adoptable from any
   target — CLI, server, app, or another library.
4. **No regular expressions in the scanners.** Hand-written line scanning only.
   Replacing the regex parser is the reason this package exists; reintroducing regex
   defeats the purpose and cannot meet the performance budget.
5. Two products, so parsing never requires linking a UI framework:
   - `EscriboCore` — Foundation only. Scanners, tokens, line index, writer.
   - `SwiftEscribo` — SwiftUI + TextKit 2 editor. Depends on `EscriboCore`.
6. `EscriboCore` must not import SwiftUI, AppKit, or UIKit. Enforced by a custom
   SwiftLint rule.
7. Never `swift build` / `swift test` — `make` targets only (XcodeBuildMCP locally,
   `xcodebuild` in CI).
8. `swift-markdown` may be used as a **test-only** differential oracle for CommonMark
   conformance. It must not appear in any shipping target. **Verified** — see
   Test-only dependencies below. A CI guard enforces it, because the property holds
   only as long as no shipping target ever references the dependency.

## Architecture

1. **The raw string is always the value.** The editor edits a `String` of source.
   Nothing is derived, round-tripped, or reconstructed — what you set is what you get
   back, byte for byte.
2. **Syntax markers are dimmed, never hidden.** `**bold**` shows its asterisks at
   reduced opacity while the word renders bold. Displayed text stays
   character-identical to source, so `source.count == display.count` and selection,
   undo, find, click-to-position, IME, and accessibility need no source↔display index
   map. Editors that hide markers require that map; it is where most of their bugs
   live.
3. Marker dimming is **alpha-only** on foreground color. Marker font size must not
   change — altering metrics mid-line makes text jitter while typing.
4. Token ranges are **UTF-16 code unit offsets** (`Range<Int>`), not `String.Index`
   and not Character offsets. `NSTextStorage` is UTF-16 natively, so this converts to
   `NSRange` for free on the hot path. `String.Index` helpers exist for consumers;
   the editor never uses them.
5. **Incremental scanning by line-state convergence.** `LineIndex` holds each line's
   range and `startState` (in-code-fence, in-boneyard, in-dialogue-block, in-
   frontmatter). On edit, rescan forward from the first affected line, stopping when a
   recomputed `startState` matches its previous value *and* the edit is behind us.
   Work is O(edited lines), not O(document).
6. **One pass, two outputs**: inline tokens with ranges (for highlighting) *and*
   per-line element records with content ranges (for semantics). A consumer wanting a
   screenplay element list gets it as a `map` over line records, not a second parse.
7. Editor is TextKit 2 via `NSTextView` (macOS, in an `NSScrollView`) and
   `UITextView` (iOS, self-scrolling), wrapped in Representables over a shared
   coordinator.
8. Never call `setAttributedString` on text storage — it destroys selection, undo
   stack, and marked text. Use `beginEditing()` / `setAttributes(_:range:)` /
   `endEditing()` over the rescanned range only. Skip restyling while `hasMarkedText`
   is true, or CJK input breaks.
9. **Line records are lossless with respect to canonical writing.** No lexical
   information the writer needs may be discarded by the scanner: forced-element
   markers (`.`, `@`, `>`), the dual-dialogue caret, title-page key spelling, casing,
   and order. The writer is built after the scanner (see Open questions), and that
   sequencing is only cheap if the record shape is complete from the start.
10. **Platform parity is structural, not a later port.** The coordinator, styler, and
    geometry layer are platform-neutral; `NSTextView` and `UITextView` differ
    precisely on the two hardest requirements — undo coalescing (Editor §4) and
    marked-text handling (§8 above). Both Representables are built in the same slice.
    A coordinator shaped around AppKit does not retrofit to UIKit cheaply.

## Functionality

### Fountain

1. Full Fountain 1.1: scene headings (including forced `.`), action, character cues
   (including forced `@`), extensions, parentheticals, dialogue, dual dialogue (`^`),
   transitions (including forced `>`), centered text (`>text<`), sections (`#`),
   synopses (`=`), notes (`[[ ]]`), boneyard (`/* */`), lyrics (`~`), page breaks
   (`===`), and title pages with arbitrary keys.
2. Non-standard title-page keys must be preserved verbatim. Real documents in this
   org use `verbsCovered:`, `Abstract:`, and others.
3. **GLOSA directives inside notes are scanned structurally**, not semantically.
   `[[<breath length="4s" strength="strong"/>]]` yields tokens for tag name,
   attribute names, attribute values, and punctuation, enabling highlighting, bracket
   matching, and folding. Whether `breath` is a legal tag and `4s` a legal length
   remains `GlosaCore`'s business — that spec knowledge must not be duplicated here.
   Tags in use include `<breath>`, `<pause>`, `<shot/>`, `<include/>`,
   `<SceneContext>`, `<Intent>`, `<Constraint>`.
4. Character-cue detection requires **one line of lookahead** — a cue is an ALL-CAPS
   line recognized only by what follows it. Incremental convergence must therefore
   extend one line past the match point. This is the single most likely source of
   "correct on full parse, wrong while typing" bugs.
5. **Canonical writing**: emit well-formed Fountain from line records. Enables
   reformat and normalize commands.

### Markdown

1. CommonMark core: ATX headings, emphasis, strong, code spans, fenced and indented
   code, lists (ordered/unordered, nested), blockquotes, links, images, thematic
   breaks, hard breaks.
2. GFM extensions: tables, task-list checkboxes, strikethrough, autolinks.
3. **YAML frontmatter** as a distinct leading region with key/value tokens — not a
   thematic break followed by garbage. Used pervasively in this org; every markdown
   file here declares `type:`.
4. **Fountain-in-Markdown**: a fenced block tagged `fountain` has its contents scanned
   by the Fountain scanner, with correct token ranges relative to the outer document.

### Editor

1. SwiftUI view bound to `@Binding var text: String`, with a language selection.
2. Modes: **live** (styled, markers dimmed) and **source** (plain, unstyled). Both
   edit the same string; switching is a theme swap, not a content transformation.
3. Fountain paragraph geometry via `NSParagraphStyle` — character cue, dialogue, and
   parenthetical margins, right-aligned transitions, centered text. Screenplay margins
   are defined in characters at 10 CPI, so a Courier face is required
   (Courier Prime → Courier New → Courier, resolved through CoreText).
4. Editing affordances: Markdown input shortcuts (`# `, `- `, `1. `, `- [ ] `), list
   continuation and outdent-on-empty-Return; Fountain smart Tab (cue → dialogue →
   parenthetical) and Return. **Every rewrite must register as a single coalesced undo
   action** on both platforms, or Cmd-Z unwinds character by character.
5. Themeable: fonts, colors, and marker opacity, with built-in light and dark themes.
6. **Markdown paragraph geometry**: heading size scale and list/blockquote indents
   (`firstLineHeadIndent` / `headIndent`), sharing the geometry layer Fountain
   requires (§3 above). One layer, two rule sets. Size varies per line, never within
   a line — Architecture §3 still forbids resizing markers. Geometry is theme-
   controlled and can be switched off, because changing line height while typing near
   the top of a long document moves the scroll position.
7. macOS and iOS are peers. macOS is the first embed (Produciesta); iOS ships from
   the same coordinator, not from a later port. See Architecture §10.

## Non-goals

1. **No CLI target.**
2. **No container formats.** `.highland` (zip), `.textbundle`, `.textpack` are the
   host app's job — Produciesta and `SwiftCompartido/TextPackReader` already do this.
   Opening them would require a zip dependency and break requirement 3.
3. **No GLOSA semantic validation** — structure only. See Fountain §3.
4. **No hidden syntax markers.** Explicitly rejected; see Architecture §2.
5. **No rich-text/WYSIWYG mode** where an `AttributedString` is the value. The
   `TextEditor(text:selection:)` API was evaluated and rejected: its value is the
   attributed string, so Markdown becomes a lossy derivation, and it offers no control
   over paragraph geometry, putting screenplay layout out of reach.
6. **No PDF/print output.** Pagination and page rendering come from the Produciesta
   preview migration; actual export stays with the host app.
7. **macOS and iOS only.** visionOS and watchOS are out of scope — no Representable,
   no theme work, no test matrix entry.
8. **No document-based support.** No `DocumentGroup`, `NSDocument`, or `FileDocument`;
   the package vends a view bound to a `String`. The host app owns files, URLs, and
   security-scoped access — Produciesta already does this with
   `WindowGroup(for: URL.self)`, and a document type here would both fight that and
   require UTType handling for the container formats §2 rules out.
9. **No `SwiftCompartido` coupling in 1.0.** No dependency in either direction, no
   API shaped to fit `GuionElement`, no coordinated migration, no compatibility
   shim, no shared types. 1.0 ships standalone and is judged on its own. Whether that
   package ever adopts `EscriboCore` is a decision for after 1.0 is released and
   stable, made against the API that exists then — not one designed for in advance.

## Verification

1. `make test-core` is the fast inner loop — pure functions over strings, no UI.
2. **Gate test**: for random edit sequences on seeded documents, assert
   `incrementalScan(edits) == fullScan(finalText)`. This catches the
   state-convergence bug class that example-based tests miss. If it is red, the
   scanner is wrong regardless of how good the fixtures look.
3. **Round-trip test** for the writer, correctly formulated as idempotence:
   `parse(write(parse(x))) == parse(x)`. Note that `write(parse(x)) == x` is *not* a
   valid assertion — writing normalizes, so it fails on any non-canonical input.
4. **Differential test** against `swift-markdown` (test-only) for CommonMark block
   structure agreement.
5. Golden fixture corpus of `.md` and `.fountain`, including hostile input:
   unterminated fences, nested emphasis, CRLF line endings, an ALL-CAPS line at EOF,
   malformed GLOSA tags, and real org screenplays
   (`~/Projects/apps/Produciesta/fixtures/episode_10.fountain`).
6. Performance assertions live in `EscriboPerformanceTests`, excluded from the
   PR-blocking job — wall-clock budgets are too machine-dependent to gate a merge.
7. **Only scan time is asserted.** The budget covers the scanner returning a dirty
   range and its tokens, measured in `EscriboCore` with no UI. End-to-end frame time
   (TextKit 2 attribute application and relayout) is observed and reported, never
   asserted — it is not controllable by this package and would make the suite a flake
   generator.
8. Budgets are measured over an edit sequence that includes the pathological cases,
   not average typing: an edit at line 1 of a long document, an edit inside an
   unterminated fence or boneyard, and a 10 KB paste.

## Beyond 1.0

Not scope, not commitments, and explicitly not constraints on the 1.0 API. Listed only
so they are not mistaken for oversights.

- Produciesta's screenplay preview (`ScreenplayInlineMarkup`, `ScreenplayPagePlan`,
  `ScreenplayPaginator`, `ScreenplayPreviewView`) may migrate here after a release is
  tagged. Three of the four are already zero-dependency.
- Whether other packages in the collection adopt `EscriboCore` is their decision to
  make, later, against a shipped and stable API. Nothing in 1.0 is designed for it.

## Performance budget

All figures on a 120-page screenplay (~120 KB), scan time only (Verification §7),
measured on a native `arm64` build (requirement 2). A number from a Rosetta or
universal build is not a measurement of anything this package ships.

| Case | Ceiling | Target |
|---|---|---|
| Typical edit — insert/delete within a line, state unchanged | 1 ms | ≪ 1 ms |
| State-invalidating edit — opening/closing a fence or boneyard, editing line 1 | collapses to the cold-scan budget by definition | — |
| Cold full scan | 50 ms | 10 ms |

A state-invalidating edit *correctly* rescans the document; asserting 1 ms p99 across
all edits would assert that a correct implementation is a bug. The cold-scan ceiling
of 50 ms is ~2.4 MB/s, very loose for a hand-written line scanner (50–200 MB/s is
ordinary); the 10 ms target exists so a 5× regression is visible before it reaches
the ceiling.

## Test-only dependencies

Requirement 8 rests on a claim that was worth verifying before writing a differential
suite against it: does a dependency used *only* by this package's test targets reach
downstream consumers?

**It does not.** Measured 2026-07-25 on Xcode 27.0 (27A5218g) / Swift 6.4, resolving
through `xcodebuild -resolvePackageDependencies` — the same libSwiftPM path Xcode
projects use, not just the `swift package` CLI:

| Package graph | Resolved and pinned |
|---|---|
| `Inner` as **root** (test target depends on `swift-markdown`) | `swift-markdown` 0.8.0, `cmark-gfm` 0.8.0 |
| `Outer` → `Inner` by version, `Inner` as **dependency** | `Inner` only — no `swift-markdown`, no `cmark-gfm` |

Downstream `Package.resolved` contains one pin. The test-only dependency is neither
fetched nor pinned nor built. Requirement 8 stands.

Two caveats that make this a live constraint rather than a settled fact:

1. **It is a graph property, not a declaration.** SwiftPM prunes because nothing
   reachable from a product references the dependency. The day any shipping target
   imports `Markdown`, it silently becomes a real dependency of every consumer and
   requirement 3 is broken with no error message. There is no `devDependencies` in
   SwiftPM to declare the intent — [swiftlang/swift-package-manager#7007][spm7007]
   has been open since October 2023.
2. **Therefore CI must assert it.** Resolve a throwaway consumer package that depends
   on SwiftEscribo and fail the build if `swift-markdown` or `cmark-gfm` appears in
   its `Package.resolved`. This is the only thing standing between requirement 8 and
   requirement 3.

[spm7007]: https://github.com/swiftlang/swift-package-manager/issues/7007

## Known limitations

1. **Undo on iOS does not work yet.** Deferred deliberately; `UITextView` gives far
   less control over undo grouping than `NSUndoManager` does, and Editor §4 demands
   that multi-character rewrites (`- [ ] `, smart Tab) register as a single coalesced
   action. macOS ships undo; iOS ships without it and gets it as a follow-up. This is
   a scheduling decision, not an architectural one — Architecture §10 still holds, and
   the coordinator must not grow an AppKit-shaped undo seam that UIKit cannot adopt.

## Open questions

**None.** Every question that shaped 1.0 is settled below. Add new ones here rather
than resolving them silently in code.

### On sequencing (settled)

"Fountain first" is right about where depth goes and wrong if read as "all of Fountain
before any editor." The grammar is not the risk — line-state convergence
(Architecture §5), the one-line cue lookahead that complicates it (Fountain §4), and
the TextKit 2 constraints (Architecture §8) are, and none of them are testable in
`EscriboCoreTests`.

The unknown that must be settled first is the **scanner→editor interface**: what the
scanner returns after an edit (a dirty UTF-16 range plus the tokens within it). Every
line of Fountain scanner written against a wrong answer is rework.

So: build `LineIndex`, the token model, the incremental scanner seam, and the gate
property test against a deliberately tiny grammar — Markdown ATX headings plus fenced
code, which exercises both the trivial case and the multi-line state case — and wire
it end-to-end through both Representables once. This is a vertical slice for risk, not
a demo. Fountain depth follows.

## Settled

| Question | Decision | Date |
|---|---|---|
| Which app embeds the editor first? | Produciesta (macOS). iOS is a peer, not a port — both Representables ship in the same slice. visionOS and watchOS are out of scope. | 2026-07-25 |
| Sequencing: what is built first? | Substrate + minimal grammar wired end-to-end, then Fountain depth, then Markdown breadth. See On sequencing above. | 2026-07-25 |
| Writer alongside the scanner or after? | After, conditional on Architecture §9 (lossless records) holding from the start. | 2026-07-25 |
| Does a test-only `swift-markdown` reach consumers? | No — verified empirically. See Test-only dependencies above. Requires a CI guard. | 2026-07-25 |
| Undo on iOS | Deferred. See Known limitations §1. | 2026-07-25 |
| When does `SwiftCompartido` cut over? | Out of scope for 1.0 entirely. No coupling in either direction, and no API designed for it. Now Non-goals §9. | 2026-07-25 |
| Document-based support? | No. Plain view; host owns documents. Now Non-goals §8. | 2026-07-25 |
| Markdown paragraph geometry? | Yes — headings and list indents, on the geometry layer Fountain requires anyway. Now Editor §6. | 2026-07-25 |
| Concrete performance budget | See Performance budget above. | 2026-07-25 |
