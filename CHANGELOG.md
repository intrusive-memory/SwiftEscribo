---
type: doc
title: SwiftEscribo Changelog
updated: 2026-07-27
---

# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — unreleased

First release. Three products, zero shipping dependencies.

### Added

#### `EscriboCore` — the parser (Foundation only)

Hand-written, line-oriented, incremental scanners for Markdown and Fountain. No
regular expressions anywhere under `Sources/`; a SwiftLint rule enforces it.

The public surface is exactly this, and it is the whole of it:

| Type | What it is |
|---|---|
| `EscriboScanner` | The entry point. `init(language:)`, `fullScan(_:)`, `incrementalScan(_:in:)` |
| `Language` | `.markdown`, `.fountain`, or any raw value — an unknown language scans as plain text rather than trapping |
| `ScanResult` | `dirtyRange`, `spans`, `lines`, `lineRecords` |
| `EscriboSpan` | `range`, `kind`, `style`, `role` — inline tokens, in UTF-16 offsets |
| `LineRecord` | `index`, `range`, `contentRange`, `element`, `depth`, `startState`, `tableAlignments` |
| `SpanKind` | 39 members. A struct, not an enum: adding one is a **minor** release |
| `ElementKind` | 28 members, same contract |
| `StyleSet` | `OptionSet` — strong, emphasis, strikethrough, inline code, underline |
| `SpanRole` | `.content` or `.marker` — what makes dimming markers possible |
| `TableAlignment` | GFM column alignment, carried on the delimiter row's record |
| `TextEdit` | `range`, `replacementLength`, `changeInLength` |
| `FountainWriter` | `write(_:from:)` — canonical Fountain from line records |
| `UTF16TextSource` | The read protocol, so a host can hand the scanner an `NSTextStorage` without bridging to `String` |
| `LineState` | Public but **opaque**: no public cases, properties, or initializers |

`LineState`'s opacity is load-bearing rather than stylistic. It is why
`LineRecord` and `ScanResult` have internal initializers, and it is what keeps every
future convergence improvement out of the "breaking change" column. A consumer can
compare two states and do nothing else with them, which is all anyone needs.

#### `SwiftEscribo` — the editor (SwiftUI + TextKit 2)

`EscriboEditor`, bound to a `@Binding var text: String`. `EscriboTheme` with
built-in light and dark themes for both languages, `TokenStyle`, `ParagraphMetrics`,
and `EditorMode` (`.live` / `.source`). Fountain paragraph geometry at 10 CPI,
Markdown heading scale and list indents, Markdown list continuation, Fountain smart
Tab and Return, each rewrite a single coalesced undo action. macOS and iOS are peers.

`EscriboColor`, `FontFamilyRole`, `FontTraits`, and `ParagraphAlignment` are public
because `TokenStyle` and `ParagraphMetrics` store them and a public struct's stored
properties must have public types. They are not independently supported API.

#### `EscriboProject` — project metadata (Foundation only)

`ProjectFrontMatter`, `CastMember`, `SeasonDefinition`, `LanguageDefinition`,
`VariantReference`, `TTSConfig`, `FilePattern`, `AnyCodable`. The org's `PROJECT.md`
model, shipped as its own product so a CLI can read project metadata without linking
the editor — and so that it never enlarges the scanner's audited 1.0 surface. It is
**not** part of the 1.0 API commitment above.

### Fixed

- `ProjectFrontMatter.appSections` and `CastMember.extraKeys` are now readable from
  outside `EscriboProject` (`public internal(set)`). Unknown keys always round-tripped
  losslessly and the public initializers already accepted them, but nothing could read
  them back — a host app could confirm its own settings section survived a save only by
  diffing the file.

### Known limitations

Documented rather than discovered. The full list, with what each one costs a user, is
in [README.md § Known limitations at 1.0](README.md#known-limitations-at-10). The two
worth naming here because they lose data rather than merely mis-render it:

- A GLOSA directive **wrapped across a line break is destroyed**, not merely unpaired.
- A `PROJECT.md` with a top-level `episodes:` and no `season:` **loses the episode
  count on decode** (pre-existing; fixing it is a behaviour change, not a bug fix).

### Semver commitments

- Adding a `SpanKind` or `ElementKind` member: **minor**. This is why they are structs.
- Adding a `StyleSet` case: **minor**. Raw values are stable, so bit positions never move.
- Changing what an existing kind is emitted *for*: **major**, even though nothing stops
  compiling. It silently changes how every existing theme renders, which is worse.
- Reordering or renumbering anything with a raw value: **major**.
- Deprecation runs one minor release with `@available(*, deprecated)` before removal.
