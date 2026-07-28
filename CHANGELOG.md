---
type: doc
title: SwiftEscribo Changelog
updated: 2026-07-28
---

# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-07-28

First release. Three products, zero shipping dependencies.

Shipped at `0.1.0` rather than `1.0.0` deliberately: the API below is complete and
audited, but it has no external consumers yet, and the first real adopter is the
thing most likely to find a name or a signature that should have been different.
`0.x` is the honest label for that, and it is what the § Semver commitments section
at the bottom of this entry is written against. See § Stability for what a `0.x`
version number does and does not promise.

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
the editor — and so that it never enlarges the scanner's audited public surface. It is
**not** part of the audited API commitment above.

### Fixed

- `ProjectFrontMatter.appSections` and `CastMember.extraKeys` are now readable from
  outside `EscriboProject` (`public internal(set)`). Unknown keys always round-tripped
  losslessly and the public initializers already accepted them, but nothing could read
  them back — a host app could confirm its own settings section survived a save only by
  diffing the file.

### Known limitations

Documented rather than discovered. The full list, with what each one costs a user, is
in [README.md § Known limitations](README.md#known-limitations). The two
worth naming here because they lose data rather than merely mis-render it:

- A GLOSA directive **wrapped across a line break is destroyed**, not merely unpaired.
- A `PROJECT.md` with a top-level `episodes:` and no `season:` **loses the episode
  count on decode** (pre-existing; fixing it is a behaviour change, not a bug fix).

### Stability

**This is a `0.x` release, and the public API is not yet frozen.** Under Semantic
Versioning a leading zero means exactly that, and SwiftPM enforces it: for a `0.x`
version, `.upToNextMajor(from: "0.1.0")` resolves to `>=0.1.0 <0.2.0` — the **minor**
is the breaking axis, not the major. A consumer who pins that way is pinned to the
`0.1` line and will not pick up `0.2.0` automatically. That is the intended behaviour
while the surface settles.

Pin it the way you would pin any pre-1.0 package:

```swift
.package(url: "https://github.com/intrusive-memory/SwiftEscribo.git", .upToNextMinor(from: "0.1.0"))
```

The surface itself is complete and was audited declaration by declaration (134 public
declarations in `EscriboCore`, every one deliberate). What `0.x` reserves is the right
to act on what the first real adopters find, without a major-version ceremony for a
package nobody has integrated yet.

### Semver commitments, once this reaches 1.0

These are the rules the design is *built* for — `SpanKind` and `ElementKind` are
structs rather than enums specifically so the first two can hold. They become binding
promises at `1.0.0`; until then they describe intent, and a `0.x` minor may break any
of them if an adopter surfaces a good enough reason.

- Adding a `SpanKind` or `ElementKind` member: **minor**. This is why they are structs.
- Adding a `StyleSet` case: **minor**. Raw values are stable, so bit positions never move.
- Changing what an existing kind is emitted *for*: **major**, even though nothing stops
  compiling. It silently changes how every existing theme renders, which is worse.
- Reordering or renumbering anything with a raw value: **major**.
- Deprecation runs one minor release with `@available(*, deprecated)` before removal.

### The road to 1.0

`1.0.0` is cut when the surface has survived contact with real consumers. Concretely:
at least one downstream package in the collection integrating `EscriboCore`, and the
two content-losing limitations above either fixed or accepted as permanent with a
user's decision on record.
