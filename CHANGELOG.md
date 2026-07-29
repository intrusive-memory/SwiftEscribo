---
type: doc
title: SwiftEscribo Changelog
updated: 2026-07-29
---

# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] — 2026-07-29

A **minor** bump, per the same `0.x` rule restated in every entry so far: below `1.0`
the minor is the breaking axis, so a consumer pinned with
`.upToNextMinor(from: "0.2.0")` will **not** pick this up automatically and must move
the pin to `0.3.0`. Nothing existing was removed or renamed; both additions are new,
defaulted parameters on `EscriboEditor.init`, so every pre-existing call site keeps
compiling unchanged.

### Added

#### `findBar:` on `EscriboEditor.init`

`EscriboEditor.init` grows a fifth parameter, `findBar: Bool = false`, threaded
through `EscriboEditorRepresentable` and `EscriboEditorBridge` to the macOS text view,
where it sets `usesFindBar` and `isIncrementalSearchingEnabled` alongside the
existing text-system hygiene flags.

This is the find **bar** — the accessory inside the editor's own `NSScrollView` — not
the floating find panel, which is a separate window that covers the document.
`isIncrementalSearchingEnabled` is what makes it search as the user types rather than
only on Return. Both flags are written explicitly in both directions rather than only
when the parameter is on, so an editor asked for no find bar actually has none rather
than inheriting whatever AppKit defaults to.

Platform-neutral in the public signature and honoured on macOS only — `UITextView`
has no find bar, so a cross-platform host still writes one call site; the parameter
is accepted and ignored on iOS.

#### `focusOnAppear:` on `EscriboEditor.init`

`EscriboEditor.init` grows a sixth parameter, `focusOnAppear: Bool = false`, threaded
the same way to `EscriboNativeTextView.focusesOnAppear` on macOS. The mechanism is an
override of `viewDidMoveToWindow()` on the text view this package already ships — the
moment AppKit tells the view it now has a window, which is exactly the "the
representable's view is installed" moment. It fires once, latched, so a window the
user had already clicked into elsewhere does not have its selection yanked back on a
later re-attachment.

This removes a view-hierarchy walk that was previously a consumer's own problem: an
`NSViewRepresentable`'s view is unreachable from SwiftUI's focus system, so a host
that wanted focus-on-open had to hunt the content view for the first `NSTextView`
itself. This package owns the view it is focusing, so that walk collapses to `self`.

Platform-neutral in the public signature; honoured on macOS only. The iOS no-op is a
deliberate decision rather than a gap — `becomeFirstResponder()` on a `UITextView`
raises the software keyboard, and doing that the instant a document opens is an
interruption, not a convenience.

Resulting public signature:

```swift
public init(
  text: Binding<String>,
  language: Language,
  mode: EditorMode = .live,
  theme: EscriboTheme? = nil,
  findBar: Bool = false,
  focusOnAppear: Bool = false
)
```

## [0.2.0] — 2026-07-28

A **minor** bump, and under the `0.x` rules stated in the `0.1.0` entry's § Stability
that is the breaking axis: a consumer pinned with `.upToNextMinor(from: "0.1.0")` —
which is what README recommends — will **not** pick this up automatically and must
move the pin to `0.2.0`. Nothing in the public surface was removed or renamed; the
minor is spent on new behavior in the Fountain scanner, which changes how a document
opening with `---` is classified.

### Added

#### YAML frontmatter in Fountain

A screenplay may now open with a `---`-fenced YAML frontmatter region, the same construct
Markdown has carried since Sortie 20 and with the same span vocabulary —
`SpanKind.frontmatterDelimiter`, `.frontmatterKey`, `.frontmatterValue`, and the
`ElementKind.frontmatterDelimiter` / `.frontmatter` line classifications. No new public
member: this is existing vocabulary reaching a second language.

The line rules now live in one place (`FrontmatterScanning`) and are shared verbatim by
both grammars, so `key: value` splits at the same colon in a `.fountain` file as in a `.md`
one. Markdown's behavior is unchanged, byte for byte.

Three rules are Fountain's own, and all three are stated as deviations 12, 12a, and 12b on
`FountainGrammar`:

- The region opens where the title page may open — the first line of a screenplay, or the
  first line of a ` ```fountain ` fence — and nowhere else.
- **The opening `---` requires corroboration**: the line below it must look like a
  frontmatter entry. Markdown's does not. An unterminated region runs to the end of the
  document, so in a screenplay an uncorroborated rule would turn a scene separator typed at
  the top of the file into a document-wide YAML block; in Markdown the same mistake costs a
  paragraph, and every static-site generator already reads the bare form.
- **A title page may still open below a closed region**, across blank lines. A file that
  writes `---` metadata and then `Title:` has written both leading regions.

`FountainWriter` re-emits the whole region verbatim — indentation is significant in YAML and
this package parses none of it.

### Changed

- The built-in Markdown themes now render frontmatter in a **monospaced** face. Their base is
  proportional, so a `key: value` block previously lost the column alignment that makes it
  readable as metadata. The built-in Fountain themes declare the same for frontmatter and for
  the title page; their base was already monospaced, so nothing there changes on screen.

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
