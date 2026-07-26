---
type: doc
title: SwiftEscribo — Agent Instructions
updated: 2026-07-25
---

# AGENTS.md

Canonical project context for AI agents (Claude, Gemini, Codex) working in
SwiftEscribo.

## What this package is

Two things, in one repo, deliberately:

1. **A Fountain parser** built on ranged tokens, so highlighting is possible at all.
   Existing regex-based parsers in the collection emit no source ranges, which is why
   a new one exists rather than a fix to an old one.
2. **A stylized Markdown/Fountain editor** for SwiftUI.

**1.0 is standalone.** No dependency on, coordination with, or API accommodation for
`SwiftCompartido` or any other package in the collection. If a task seems to call for
one, it is out of scope — say so rather than building a seam for it.

## Hard constraints

- **Zero dependencies.** Not negotiable. It is what lets any target adopt the parser.
- **No regular expressions in the scanners.** Hand-written line scanning only. The
  old parser's regexes are what this package exists to replace; reintroducing them
  defeats the purpose and cannot meet the per-keystroke performance budget.
- **Never `swift build` / `swift test`.** Use `make` targets (XcodeBuildMCP locally,
  `xcodebuild` in CI). Run `make help`.
- **Apple Silicon only — always pass the arch.** Every `xcodebuild` invocation pins
  `arch=arm64` in the destination *and* `ARCHS=arm64`; never let it infer. Intel and
  Rosetta are out of scope. The `Makefile` exposes this as `$(ARCH)` — append it to
  any new target you add. Performance numbers from a non-native build are worthless.
- **`EscriboCore` must not import SwiftUI, AppKit, or UIKit.** Foundation and
  CoreText only. This is enforced by review; breaking it breaks CLI consumers.
- **macOS and iOS are peers; visionOS and watchOS are out of scope.** Produciesta
  (macOS) is the first embed, but the coordinator, styler, and geometry layer stay
  platform-neutral and both Representables are built together. `NSTextView` and
  `UITextView` diverge on exactly the hard parts — undo coalescing and marked text —
  so a coordinator shaped around AppKit does not retrofit to UIKit cheaply.
- **`swift-markdown` is test-only and must stay that way.** It is the CommonMark
  differential oracle. SwiftPM prunes it from downstream consumers *only* because no
  shipping target references it — verified 2026-07-25 on Xcode 27.0 / Swift 6.4. Add
  one `import Markdown` to `EscriboCore` or `SwiftEscribo` and the zero-dependency
  charter breaks silently, with no error. A CI guard resolves a throwaway consumer
  package and fails if the pin appears. Never move it out of the test target.
- **Undo does not work on iOS yet** — deliberate, deferred. macOS has it. Do not
  solve macOS undo with an AppKit-shaped seam UIKit cannot later adopt.
- **Line records must be lossless for the writer.** Never discard forced-element
  markers (`.`, `@`, `>`), the dual-dialogue caret, or title-page key spelling,
  casing, and order. The writer is built after the scanner stabilizes, which is only
  cheap if the record shape was complete from the start.

## Architecture

```
String (raw markdown / fountain)      <- the value; never derived
   |
LineIndex + IncrementalScanner        <- EscriboCore, Foundation only
   |
   +-- [EscriboToken]  (inline spans, ranges)   -> highlighting
   +-- [LineRecord]    (element type, content)  -> semantics
   |
EscriboTheme + TokenStyler
   |
NSTextStorage.setAttributes(_:range:) <- over rescanned range only
   |
NSTextView (AppKit) / UITextView (UIKit), TextKit 2
   |
EscriboEditor (SwiftUI)
```

### Offsets are UTF-16

`EscriboToken.range` is a `Range<Int>` of **UTF-16 code unit offsets**, not
`String.Index` and not Character offsets. `NSTextStorage` is UTF-16 natively, so this
converts to `NSRange` with no work on the hot path. `String.Index` conversion helpers
exist for consumers who want them; the editor never uses them.

### Spans tile, they do not nest

`[EscriboSpan]` is flat, ordered, non-overlapping, and **exactly tiles** the scanned
range — plain text is a `.text` span, never a gap. Nesting is flattened at scan time:
`kind` (what the text is) and `style` (an OptionSet of emphasis flags) are separate
axes, so `***x***` in dialogue is one span, not a tree.

This is load-bearing. `setAttributes(_:range:)` replaces every attribute on a range,
so total tiling makes stale attributes structurally impossible — no clear-then-restyle
pass, no bold left behind after deleting a `*`. Introduce a gap and you have
reintroduced that whole bug class.

A marker span carries the **same** `kind` and `style` as the content it delimits and
differs only in `role`. The styler resolves attributes, then dims alpha if
`role == .marker`. That is how "asterisks visible but dimmed, word still bold" falls
out of the data rather than being special-cased.

`SpanKind` and `ElementKind` are structs with static members, never enums — a public
enum is source-breaking to extend, which would make adding a Fountain construct a
major version bump.

### Incremental scanning

`LineIndex` holds each line's range and its `startState` (in-code-fence,
in-boneyard, in-dialogue-block). On edit, rescan forward from the first affected
line and stop when a line's recomputed `startState` equals its previous value *and*
the edit is behind us. Work is O(edited lines), not O(document).

**The Fountain trap, forward:** a character cue is an ALL-CAPS line recognized only by
what *follows* it. The scanner needs one line of lookahead, and convergence must
extend one line past the match. Get this wrong and highlighting is correct on full
parse but wrong while typing — the hardest bug class here to notice.

**The Fountain trap, backward:** the same rule means an edit can change the
classification of the line *before* it. `BOB` + blank line is action; type a word on
the following line and `BOB` becomes a character cue. So rescanning starts at least
one line *before* the first edited line. Nothing about the edit itself points at this,
which is why it gets forgotten.

The property test below exists specifically to catch both.

### Styling rules

- Marker dimming is **alpha-only** on `foregroundColor`. Never shrink marker font
  size: changing metrics mid-line makes text jitter as you type.
- Never call `setAttributedString` on the text storage — it destroys selection, the
  undo stack, and marked text. Use `beginEditing()` / `setAttributes(_:range:)` /
  `endEditing()`.
- Skip restyling while `hasMarkedText` is true; restyling mid-composition breaks CJK
  input.

## Testing

`make test-core` is the fast inner loop — pure functions over strings, no UI, no
fixtures to stage.

**The gate test:** for random edit sequences on seeded documents, assert
`incrementalScan(edits) == fullScan(finalText)`. This catches the state-convergence
bug class that example-based tests miss. If it is red, the scanner is wrong no matter
how good the fixtures look.

Performance assertions live in `EscriboPerformanceTests`, excluded from the
PR-blocking job because wall-clock budgets are machine dependent.

## Scope

1.0 is a standalone package: the two scanners, the writer, and the editor. Adoption by
anything else in the collection is a later decision made against a shipped API, and
must not influence the design now. Design the public API for its own users.

Related: `CLAUDE.md`, `GEMINI.md`, `README.md`.
