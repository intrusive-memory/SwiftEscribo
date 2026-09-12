---
type: doc
title: SwiftEscribo Changelog
updated: 2026-07-29
---

# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] — 0.4.0

A **minor** bump, per the same `0.x` rule as every entry before it: below `1.0` the minor
is the breaking axis, so a consumer pinned with `.upToNextMinor(from: "0.3.0")` will
**not** pick this up automatically and must move the pin to `0.4.0`.

Nothing was removed or renamed, and every pre-existing call site keeps compiling. But
this release **changes the spans a scan returns for text that has not changed**, which is
a behaviour change an adopter has to read rather than a feature to opt into. If you cache,
snapshot, or assert on span output, read the section below before you bump the pin.

### Added

#### The paragraph well: `EscriboWell`, `EscriboWellItem`, and its lane

The model and layout reservation for the paragraph well (REQUIREMENTS-1.1.0 § 5). Nothing is
drawn yet; this release reserves the space and carries the host's state.

```swift
public enum EscriboWellItem: Hashable, Sendable { case readAloud }

public struct EscriboWell: Equatable, Sendable {
  public var items: [EscriboWellItem]          // default [.readAloud]
  public var activeBlock: EscriboBlock.ID?
  public var progress: Double?                 // 0…1
  public var spokenRange: NSRange?             // UTF-16, document space
  public var eligibleKinds: Set<BlockKind>?    // nil = every kind
  public init(items:activeBlock:progress:spokenRange:eligibleKinds:)  // all defaulted
  public func isEligible(_ block: EscriboBlock) -> Bool
}
```

- **`well:` and `onWellAction:` on `EscriboEditor.init`**, trailing the parameter list:
  `well: EscriboWell? = nil` and
  `onWellAction: @escaping (EscriboWellItem, EscriboBlock) -> Void = { _, _ in }`. Both are
  defaulted, so every existing call site compiles unchanged. The package draws and tracks;
  the host acts. The package does not import AVFoundation.
- **Eligibility is the host's data.** `eligibleKinds` names the block kinds that get a well;
  its default, `nil`, admits every kind, so the package encodes no language rule. A block
  with no content (an empty `contentRanges` — a blank run, a thematic break) is never
  eligible, whatever the set.
- **The lane is reserved in the text view's text-container inset, and only when a well is
  supplied.** macOS: 28 pt on `NSTextView.textContainerInset.width`, which is symmetric, so
  the usable container width shrinks by 56 pt and the right margin balances the left. iOS:
  44 pt on `UITextView.textContainerInset.left` at a **regular** horizontal size class, and
  **none at compact** (D-5); the size class is read from the SwiftUI environment on every
  update, so crossing compact ↔ regular adds or removes the lane. The lane is added to the
  inset the text view already has, never substituted for it.

**What an adopter must know:** passing no well changes nothing — the insets and layout are
exactly `0.3.0`'s. Passing one moves the text column in by the lane width in both live and
source mode (D-6).

### Changed

#### The inline pass runs over a Markdown block's whole content, not line by line

Through `0.3.0` the inline scanner ran once per line, so an emphasis, strikethrough, or
code-span delimiter had to open and close on the same line to pair. `**bold` on one line
and `text**` on the next produced four literal asterisks on screen — a hard-wrapped
paragraph could not carry emphasis across the wrap at all.

From `0.4.0` the inline pass runs over a **paragraph**, a **blockquote**, or a **list
item**'s joined content, so the pair pairs:

```markdown
**bold
text**
```

now comes back as one strong run rather than as literal delimiters.

**What an adopter must know:**

- **Paragraphs, blockquotes, and list items — the three things a writer hard-wraps.** A
  blockquote joins only across lines **at the same depth**, so a `**` inside `>` cannot
  pair with one inside `>>`. A list item joins the marker line with its own continuation
  lines and never across two items, so a `**` in one bullet cannot pair with a `**` in the
  next. A `>` line with no content after it is a paragraph break inside the quote and is
  not joined across, matching CommonMark.
- **Not joined, and unchanged from `0.3.0`:** ATX and setext headings, table cells, code
  blocks, and frontmatter. Tables are excluded permanently — joining a header row to its
  body rows would pair a delimiter in one cell with one in another, which CommonMark does
  not do. Fountain is excluded permanently: joining a speech would let a `*` in a character
  cue pair with a `*` in the dialogue three lines below it.
- **Block markers are untouched.** A `> `, a `- `, a `1. `, and a task-list checkbox come
  back as exactly the spans they did before, with exactly their previous kinds and no
  emphasis applied to them. Only a line's *content* spans are recomputed.
- **Spans are still strictly line-based.** A run that crosses a hard wrap comes back as
  one span per line, so `LineRecord`, `EscriboSpan`, and any styler driven by them need no
  change. A line terminator is never inside a styled span.
- **A one-line block is byte-identical to `0.3.0`.** The joined pass is skipped for
  single-line blocks specifically so that a document with no hard-wrapped emphasis sees no
  change whatsoever, and so is any block whose content carries no inline delimiter at all.
- **An unmatched delimiter still cannot style past its own block.** A blank line, a
  heading, a fence, a change of blockquote depth, or the start of the next list item all
  bound the pass, and the block's content is the entire input the matcher is given.
- **The dirty range grows, but only where joining can change something.** An edit on any
  line of a block can change how every other line of it pairs, so an incremental scan
  widens to cover the whole block before re-running the pass. `ScanResult.dirtyRange`
  has always been permitted to be much larger than the edit; this makes it so more often.
  Two conditions keep the cost bounded, and both are checked *before* anything is
  rescanned:
  - The block must lie in an unbroken run of at most **200** non-blank lines. A longer
    run falls back to line-scoped scanning, and the window is not widened at all — a wall
    of text with no blank line in it costs exactly what it cost in `0.3.0`.
  - **Some line of the block must carry inline syntax.** A block with no delimiter
    anywhere in it cannot pair anything, so it is neither joined nor widened — ordinary
    prose still rescans a handful of lines per keystroke however long the block is, which
    is what the package's typing-latency budgets require.

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
