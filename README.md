---
type: doc
title: SwiftEscribo
updated: 2026-07-27
---

# SwiftEscribo

A stylized SwiftUI text editor for Markdown and Fountain screenplays, and the
canonical Fountain parser for the Intrusive Memory package collection.

**Platforms**: macOS 26.0+, iOS 26.0+ · **Swift**: 6.2+ · **Dependencies**: none

## Three products, and why the split matters

| Product | Imports | Use it when |
|---|---|---|
| `EscriboCore` | Foundation only | You need to parse Markdown or Fountain — CLI tools, servers, document pipelines |
| `SwiftEscribo` | SwiftUI, TextKit 2 | You need the editor view |
| `EscriboProject` | Foundation only | You need to read or write a `PROJECT.md` front-matter block |

**Parsing never requires linking a UI framework.** That is the split's whole
purpose, and it is not a convention — `EscriboCore` imports *nothing*, not even
Foundation, and a SwiftLint rule (`no_ui_imports_in_core`) fails the build on an
`import SwiftUI`, `import AppKit`, or `import UIKit` anywhere under
`Sources/EscriboCore/`.

`EscriboProject` is a peer, not a layer: the org's project-metadata model, shipped
separately so a CLI can read a cast list without linking the editor and so that it
never enlarges the scanner's audited public surface.

### The zero-dependency charter

`Package.swift` declares exactly one dependency, `swift-markdown`, and it is a
**test-only differential oracle** reachable from `EscriboCoreTests` and nowhere else.
Nothing you link ever sees it.

That property is worth stating precisely, because SwiftPM does not enforce it.
SwiftPM prunes a test-only dependency out of a consumer's graph as a *graph
property* — it is pruned because no shipping target happens to reference it, not
because anything declares it test-only. There is no `testOnly:` to write and no
diagnostic when the property stops holding
([swift-package-manager#7007](https://github.com/swiftlang/swift-package-manager/issues/7007)).
So the day a target under `Sources/` says `import Markdown`, swift-markdown and
swift-cmark under it would silently become dependencies of every consumer of the
Fountain parser, and the build would stay green.

The `no_markdown_import_in_sources` SwiftLint rule is what actually holds the
charter, and `make lint` is what runs it, locally and in CI.

## Design

**The raw string is always the value.** The editor edits a `String` of Markdown or
Fountain source. Nothing is derived, round-tripped, or reconstructed — what you set
is what you get back, byte for byte.

**Syntax markers are dimmed, not hidden.** `**bold**` shows its asterisks at reduced
opacity while the word renders bold. Because displayed text stays character-identical
to source, selection, undo, find, click-to-position, IME composition, and
accessibility all work without a source↔display index map. Editors that hide markers
need that map, and it is where most of their bugs live.

**No regular expressions.** Both scanners are hand-written and line-oriented. This is
a correctness decision before it is a performance one, but it is also why the parser
is fast enough to run on every keystroke — a cold scan of a 128 KB screenplay is
about 5 ms and a keystroke is about 0.03 ms, on arm64, optimized.

**Two outputs from one pass.** Scanning yields inline tokens with source ranges (for
highlighting) *and* per-line element classification with content ranges (for
semantics). Consumers that want a screenplay element list get it as a `map` over the
line records rather than a second parse.

**`LineState` is opaque.** It is public only because `LineRecord` carries it, and it
exposes no cases, no properties, and no initializer. Comparing two of them is the
only thing a caller can do and the only thing anyone needs. Exposing its shape would
freeze the scanner's internals at 1.0 and make every convergence improvement a
breaking change.

## Using it

```swift
import EscriboCore

var scanner = EscriboScanner(language: .fountain)
let result = scanner.fullScan(text)

for record in result.lineRecords where record.element == .character {
    print(text[Range(record.contentRange, in: text)!])
}

// …and after an edit, in old-text coordinates:
let next = scanner.incrementalScan(TextEdit(range: 12..<12, replacementLength: 1), in: newText)
```

The full public surface, type by type, is in
[CHANGELOG.md](CHANGELOG.md#escribocore--the-parser-foundation-only).

## Known limitations at 1.0

Every one of these is known, reproduced by a test, and shipped deliberately. They are
here so a user meets them in a README rather than in their own document.

### Markdown

- **GFM extended autolinks are not implemented.** Only the bracketed CommonMark form
  (`<https://example.com>`) is recognized; a bare `https://example.com` in prose is
  plain text. Note that the CommonMark/GFM differential oracle cannot catch this —
  `swift-markdown` 0.8.0 does not attach the autolink extension either, so both
  implementations share the gap and agree across it.
- **A tight *ordered* list's second and third items classify as `paragraph`.** The
  unordered half misclassifies only when an item has no content at all (a lone `-`
  becomes a setext heading). Confirmed against an independent parser. The editor layer
  works around it for list continuation, and that workaround retires itself when the
  scanner is fixed.
- **`---` typed as a document's first line paints everything below it as
  frontmatter** until the closing `---` is typed. A line grammar cannot know at the
  opener whether a closer exists.
- **Blockquote and list-item content is not re-scanned.** `> # Title` is one
  blockquote line, not a heading inside a quote; `- # Title` is one list item.
  Expressing both at once needs a container axis on `LineRecord`, which is public API.
- **List nesting saturates at 8 levels.** Deeper items keep scanning and keep their
  content, but stop gaining depth.
- **A setext underline does not retro-classify the paragraph above it.** The
  underline itself is the `heading` record, with an empty content range; a consumer
  that wants the heading *text* reads the line above it.

### Fountain

- **A GLOSA directive wrapped across a line break is destroyed, not merely
  unpaired.** The opener degrades to plain text and the continuation reads as note
  prose. A screenwriter who wraps a long `<breath …/>` silently loses it. This is the
  one Markdown/Fountain limitation on this page that loses content rather than
  mis-rendering it.
- **A title page whose *first* key has a Highland-style empty value — a lone tab on
  the line below — opens no title page at all.** `Title:` over a tab is genuinely
  indistinguishable, on one line of lookahead, from `CUT TO:` over a tab, and
  widening the rule to catch the first would turn an ordinary transition-led
  screenplay into metadata. Both halves of that ambiguity are pinned by tests that are
  meant to go red when someone decides it; **it needs a user's decision, not a patch.**

### Editor

- **Undo coalescing on iOS is whatever UIKit provides.** macOS registers each
  multi-character rewrite (`- [ ] `, smart Tab) as one coalesced action;
  `UITextView` gives far less control over undo grouping, so iOS ships without the
  guarantee. Deliberate and deferred (`docs/complete/fountain-surgeon-01/REQUIREMENTS.md` § Known limitations §1), and a
  scheduling decision rather than an architectural one — the coordinator has no
  AppKit-shaped undo seam for UIKit to fail to adopt.
- **Fountain paragraph geometry is LTR-only.** Screenplay margins are defined in
  characters from a left margin at 10 CPI and a mirrored screenplay layout is not a
  format that exists. Markdown uses natural alignment and works in RTL text. This is
  a scope statement, not a defect.
- **VoiceOver reads the markers.** `**bold**` is spoken with its asterisks. That
  falls directly out of display text being character-identical to source, which is
  what makes selection, undo, find, and IME work without an index map. Half an
  accessibility text mapping is worse than none, so 1.0 ships none.

### `EscriboProject`

- **A top-level `episodes:` with no `season:` beside it is discarded on decode.** The
  count is read, dropped, and re-emitted as nothing — live data loss, pre-existing,
  and verified in fixture bytes. It is not fixed because there is no fix that is only
  a bug fix: inventing `season: 1` changes what the document means, and preserving the
  orphan as an unknown key changes the encoded output of every v3 file that has one.
- **`withCast(_:)` erases the `updated` date.**
- **Two `MergeStrategy` cases are line-for-line identical** in `CastMember.merge(with:strategy:)`.
- **One real org `PROJECT.md` throws on decode.** The unknown-key preservation gate
  currently rests on 2 of the 6 vendored fixtures.

## Development

Use `make`. Never `swift build` or `swift test`.

| Target | What it does |
|---|---|
| `make build` | Build for macOS, arm64 |
| `make test` | macOS tests, performance excluded |
| `make test-core` | The parser core only — the fast inner loop |
| `make test-ios` | iOS tests, iPhone 17 simulator |
| `make test-performance` | The budgets. Release + testability, arm64; the suite asserts it is optimized before reading a clock |
| `make lint` | SwiftLint. Read-only, and what CI runs |
| `make format` | Rewrites every Swift file in place. Never what CI runs |

## License

MIT
