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
   frontmatter). On edit, rescan a window that is widened in **both** directions:
   - **Backward.** Rescanning starts at least one line *before* the first edited line.
     Fountain classification is backward-dependent: `BOB` followed by a blank line is
     action, but type a word on the following line and `BOB` retroactively becomes a
     character cue. Starting at the edited line cannot see that and will leave the
     previous line misclassified. The backward extent is a property of the language,
     not a constant.
   - **Forward.** Rescanning stops when a recomputed `startState` equals its previous
     value *and* the edit is behind us *and* the language's lookahead is satisfied —
     one line past the match for Fountain (§4 under Fountain).

   Work is O(edited lines), not O(document). Both directions are load-bearing; the
   forward rule alone is the most likely source of "correct on full parse, wrong while
   typing" bugs, and the backward rule is the one most likely to be forgotten because
   nothing about the edit itself points at it.
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

## Core API

The seam between scanner and editor. Sequencing exists to settle this first: every
other decision in 1.0 is written against it, and it is the one thing that cannot be
discovered by writing more grammar.

Types below are a specification of shape and invariants, not final signatures.

### Two axes, not one enum

A span carries **what the text is** and **how it is emphasized** separately.

```swift
public struct SpanKind: Hashable, Sendable {   // .text, .sceneHeading, .character,
  public let rawValue: String                  // .dialogue, .codeSpan, .linkURL,
}                                              // .glosaTagName, .glosaAttributeValue…

public struct StyleSet: OptionSet, Sendable {  // .strong, .emphasis, .strikethrough,
  public let rawValue: UInt16                  // .inlineCode, .underline
}
```

Collapsing these into one enum produces `.boldItalicDialogue` and a combinatorial
explosion that grows every time a grammar gains a feature. Keeping them orthogonal
means `***bold italic***` inside dialogue is `kind: .dialogue, style: [.strong,
.emphasis]` — one span, no new cases.

`SpanKind` and `ElementKind` are **structs with static members**, not enums.
A public enum is source-breaking to extend: every consumer's exhaustive `switch`
fails to compile when a case is added, which would make adding a Fountain construct a
major version bump. Static members on a struct still pattern-match in a `switch` and
still require a `default`, which is exactly the forward-compatibility wanted.

### Spans — the styling output

```swift
public struct EscriboSpan: Equatable, Sendable {
  public let range: Range<Int>   // UTF-16 code units
  public let kind: SpanKind
  public let style: StyleSet
  public let role: SpanRole      // .content or .marker
}
```

**Flat, non-overlapping, ordered, and totally tiling.** Not a tree. Every UTF-16
offset in the scanned range belongs to exactly one span; plain text is a `.text` span
rather than a gap. This is not a simplification of the model, it is the model:

1. It maps 1:1 onto `setAttributes(_:range:)`, which replaces every attribute on a
   range. Total tiling therefore makes stale attributes **structurally impossible** —
   no clear-then-restyle pass, no leftover bold after deleting a `*`. A model with
   gaps requires that extra pass and is where "the styling is haunted" bugs come from.
2. Styling becomes a linear walk with no recursion, no accumulation stack, and no
   allocation per nesting level, on the one path that has a per-keystroke budget.
3. Equality is array equality, which is what the gate test compares.

Nesting is flattened at scan time, not resolved at style time. `**bold `code`
bold**` becomes consecutive spans carrying the union of the styles that cover them.

**`role` is how Architecture §2 and §3 are enforced rather than merely intended.**
A marker span carries the *same* `kind` and `style` as the content it delimits and
differs only in `role`, so the styler is: resolve attributes from `kind` + `style`,
then if `role == .marker`, multiply the foreground alpha. That yields "the asterisks
show, dimmed, while the word renders bold" as a direct consequence of the data model,
and makes "dim the marker but keep its metrics" the path of least resistance.

Spans are produced for a requested range on demand and are **not retained for the
whole document**. The editor only ever needs the range it is about to restyle.

### Line records — the semantic output

```swift
public struct LineRecord: Equatable, Sendable {
  public let index: Int
  public let range: Range<Int>         // includes the line terminator
  public let contentRange: Range<Int>  // excludes markers, indent, and terminator
  public let element: ElementKind
  public let startState: LineState
  public let depth: Int                // list nesting, section depth
}
```

`range` includes the terminator and `contentRange` excludes it. Stated explicitly
because leaving it ambiguous guarantees off-by-one bugs at every call site.

`startState` is the convergence key, so it must be **exact and total**: it carries
everything that affects how the following line scans, and its `==` is real equality,
never an approximation or a fast path. A state that omits one field converges early
and produces exactly the class of bug the gate test exists to catch.

### The scan interface

```swift
public struct ScanResult: Sendable {
  public let dirtyRange: Range<Int>     // reapply character attributes here
  public let spans: [EscriboSpan]       // exactly tile dirtyRange
  public let lines: Range<Int>          // line indices rescanned
  public let lineRecords: [LineRecord]  // one per line in `lines`
}
```

Invariants, all of them testable and each one a bug that would otherwise ship:

1. `spans` are ordered, non-overlapping, contiguous, and exactly tile `dirtyRange` —
   the first begins at `dirtyRange.lowerBound`, the last ends at its `upperBound`.
2. `dirtyRange` **contains the edited range** and is **line-aligned** at both ends.
   Line alignment is required because paragraph attributes are per-paragraph;
   applying them to a partial paragraph produces layout that depends on where the
   range happened to start.
3. `dirtyRange` may be much larger than the edit (Architecture §5) and is never
   smaller.
4. `lineRecords` covers `lines` completely, in order, with no gaps.

**The two outputs drive two different application paths**, and the split is the
answer to "who owns geometry": `spans` become character attributes; `lineRecords`
become `NSParagraphStyle` on their line ranges. An edit that changes only emphasis
touches the first; an edit that turns action into a character cue touches both.

### Edits and text access

An edit is expressed in **old-text coordinates** — the range replaced and the length
of the replacement — which is unambiguous and derivable from
`textStorage(_:didProcessEditing:range:changeInLength:)`. The reverse convention
(new coordinates plus a delta) is not, and mixing the two silently corrupts offsets.

The scanner **must not require the document as a Swift `String` per edit.**
`NSTextStorage` is `NSString`-backed; bridging 120 KB on every keystroke would exceed
the whole budget before scanning began. The scanner reads UTF-16 through an
abstraction that both `String` and `NSTextStorage` satisfy, and reads it a line at a
time rather than a code unit at a time, so dispatch is per line and not per character.

### Concurrency and failure

- **The scanner is synchronous and single-threaded.** No `async`, no actors, no
  background queue. At the budgets in Performance budget it is fast enough to run on
  the main actor, and introducing concurrency would add ordering hazards against
  `NSTextStorage` mutation for no measurable gain.
- **Scanning never fails.** No `throws`, no optional result. Every input, including
  malformed and hostile input, produces a total tokenization; unterminated and
  malformed constructs degrade to `.text` rather than propagating an error. Hostile
  input is a fixture case (Verification §6), not an error path — the scanner has no
  error path.

## Text model

Architecture §1 says the raw string is the value, byte for byte. That has consequences
that must be stated, because every one of them is an off-by-one waiting to happen.

### Line termination

- `\n`, `\r\n`, and a lone `\r` are all line terminators. A document may mix them.
- Terminators are **never normalized**. `\r\n` stays `\r\n` through scan, style, and
  write. Normalizing would violate Architecture §1 and would make the writer's
  idempotence test pass for the wrong reason.
- `LineRecord.range` includes the whole terminator, so it is 2 code units for `\r\n`.
  A scanner that assumes 1 breaks every offset after the first CRLF.
- **A trailing terminator produces a final empty line.** `"a\n"` is two lines: `"a\n"`
  and `""`. `"a"` is one. This matches where a text view lets the caret go, and
  disagreeing with the text view about line count is unrecoverable.
- The empty document is one empty line, zero spans, and an empty `dirtyRange` at 0.

### Unicode

- Span boundaries **never split a surrogate pair**. This is a hard guarantee and a
  cheap one to check.
- All syntax markers in both grammars are ASCII, so boundaries fall on grapheme
  cluster boundaries in practice; the scanner does not do cluster segmentation on the
  hot path and does not need to.
- Astral-plane characters (emoji, and the ones that appear in real screenplays more
  often than you would guess) occupy 2 code units. Column arithmetic — Markdown
  indentation, Fountain centering — counts **code units, not characters**, and any
  place that means "visual column" must say so.

### Degenerate input

- **No document-size limit and no assumption one exists.** Budgets are stated for
  120 KB (Performance budget); correctness is unbounded.
- **No algorithm may be worse than linear in line length.** A one-megabyte single
  line must scan in time proportional to its length. Quadratic line handling is the
  classic way a scanner that benchmarks well hangs on a minified file.
- A tab is a legal indent character. Column computation for indented code uses the
  CommonMark 4-column tab stop, not a width of 1.

## Language and dispatch

```swift
public struct Language: Hashable, Sendable {  // .markdown, .fountain
  public let rawValue: String
}
```

A struct with static members for the same reason as `SpanKind` (Core API) — adding a
language must not break a consumer's exhaustive `switch`.

### Fountain inside Markdown

A fence tagged `fountain` scans its contents with the Fountain scanner (Markdown §4).
Three requirements make that work rather than merely sound reasonable:

1. **The inner scan is offset, not separate.** Spans come back in outer-document
   coordinates. The inner scanner is never handed a substring — that would allocate
   per keystroke and lose the offset, which is how ranges end up subtly wrong only
   inside fenced blocks.
2. **The inner state is part of the outer `startState`.** Convergence (Architecture
   §5) must work across the boundary, so a line inside a fenced Fountain block has a
   `startState` that carries the Fountain scanner's state as well as the Markdown
   scanner's. A `startState` that only tracks "we are in a fence" converges early
   inside the block and produces the exact bug the gate test exists to catch.
3. **One level, no recursion.** Markdown may host Fountain. Fountain hosts nothing —
   it has no fence syntax — so there is no nesting beyond depth one and no reentrancy
   to reason about.

An unterminated `fountain` fence scans to end of document. It does not fail, and it
does not fall back to Markdown (Core API: scanning never fails).

## Theme and styling

Lives in `SwiftEscribo`, never in `EscriboCore` — colors and fonts are AppKit/UIKit
types, and requirement 6 forbids importing them into the core. The core emits spans
and line records; the theme is the only thing that decides how they look.

### The theme declares intent; the styler resolves and caches it

A theme is a **value type holding a lookup table**, not a protocol with a
`attributes(for:)` method. A protocol call per span allocates an attribute dictionary
per span — tolerable for a three-span keystroke, wasteful across the ~10⁴ spans of a
cold 120 KB document, and awkward to make `Sendable`.

Instead the styler owns a cache keyed by `(SpanKind, StyleSet, SpanRole)`. The number
of distinct combinations actually occurring in a document is in the tens, so after the
first few lines every lookup is a hit and the hot path is a dictionary read rather
than a computation.

**The cache is invalidated by exactly four things**: theme change, mode change,
appearance change (light/dark), and font-metric change (user font size, Dynamic Type).
One invalidation path, four triggers — a fifth trigger that forgets to invalidate is
how an editor ends up with dark-mode text on a light background.

### Composition order

Attributes resolve in four stages, and the order is normative:

1. **Base** — family, size, foreground, background.
2. **Kind** — per-`SpanKind` overrides: color, font traits, size scale.
3. **Style** — `StyleSet` flags applied additively: `.strong` adds the bold trait,
   `.emphasis` italic, `.inlineCode` swaps to the mono family, `.strikethrough` and
   `.underline` set their attributes.
4. **Role** — if `role == .marker`, multiply the foreground alpha by `markerOpacity`.
   Nothing else.

Within a stage, **traits union and everything else overrides**. Stating this matters:
it is the difference between a code span inside a bold heading rendering bold-mono
and rendering mono-only, and it is not the kind of thing two implementers guess the
same way.

### Marker dimming is unfalsifiable by construction

`markerOpacity` is a **single scalar on the theme**, not a `TokenStyle` for markers
and not a per-kind value. There is therefore no way to express "markers in a different
font" or "markers a size smaller" — the type system refuses. Combined with a marker
span carrying the same `kind` and `style` as its content (Core API), Architecture §3
stops being a rule someone has to remember and becomes a property that cannot be
violated without changing the theme type itself.

Note that Architecture §3 constrains markers **relative to their content**, not
content relative to other content. A Markdown code span legitimately swaps to a mono
family and changes advance width; that is the feature working. What is forbidden is a
`*` rendering at a different size from the word it wraps.

### Geometry is declared in characters, not points

```swift
public struct ParagraphMetrics: Equatable, Sendable {
  var leftIndentChars: Double
  var rightIndentChars: Double
  var firstLineIndentChars: Double
  var spaceBeforeLines: Double    // multiples of line height
  var alignment: Alignment
}
```

Screenplay margins are defined in characters at 10 CPI (Editor §3), so the theme
stores characters and the styler converts to points against the resolved font's
advance width. Storing points would silently break every margin the moment a user
changes font size — and would make the Courier requirement a hidden coupling instead
of an explicit one.

Geometry is looked up by `(ElementKind, depth)`, because Markdown list indentation is
a function of nesting depth, which is exactly why `LineRecord` carries `depth`.

### Source mode is a theme, not a code path

Editor §2 requires that switching between live and source mode is a theme swap rather
than a content transformation. That is a real constraint on this API: **the theme type
must be able to express "no styling at all."** A built-in source theme maps every kind
and every style combination to the base attributes and every element to default
metrics.

This is testable, and it is worth testing, because it is the cheapest possible proof
that the abstraction did not leak: **for the source theme, every span in a document
resolves to identical attributes regardless of kind, style, or role.** If that test
cannot be written, mode switching has grown a code path it was not supposed to have.

### Unknown kinds fall back, never fail

A theme is not required to have an entry for every `SpanKind`. An unrecognized kind
resolves to the base style — never a crash, never a blank, never a fatal `default:`.
This pairs with kinds being structs rather than enums (Core API): a theme written
against 1.0 must keep working when 1.1 adds a Fountain construct, rendering the new
kind as plain text until the theme opts into styling it.

### Built-ins and what is deferred

Built-in themes: light and dark, for both languages (Editor §5).

Explicitly **not** in 1.0, listed so they are not mistaken for oversights:

- **Computed styling** — a closure or protocol that colors a span by its *content*
  rather than its kind, e.g. a distinct color per character name in a screenplay.
  This is a genuinely wanted feature and the value-table design does not preclude
  adding it later, but it changes the caching story and is not free.
- **Consumer-defined kinds.** Themes restyle the kinds the scanners emit; they cannot
  introduce new ones, because nothing would ever produce them.

## Editing behavior

### "Input shortcuts" is the wrong frame

Editor §4 lists Markdown input shortcuts as `# `, `- `, `1. `, `- [ ] `. In an editor
that **hides** markers, those are conversions: you type `# ` and it disappears into a
heading style. Here markers are never hidden (Architecture §2), so typing `# ` needs
no shortcut at all — the characters are the syntax and they are already correct.

What is actually wanted is **continuation**, not conversion:

| Trigger | Behavior |
|---|---|
| Return at end of `- item` | Insert `\n- ` |
| Return at end of `3. item` | Insert `\n4. ` |
| Return at end of `- [ ] item` | Insert `\n- [ ] ` (always unchecked) |
| Return on an item that is empty apart from its marker | Delete the marker, leaving an empty line — do not insert another |
| Return at end of an indented nested item | Continue at the same indent |

Ordered-list **renumbering** of following items is deferred. It is a document-wide
rewrite triggered by a single keystroke, which fights coalesced undo and the
line-local edit model for a cosmetic gain — `1. 1. 1.` renders as 1, 2, 3 in every
CommonMark implementation anyway.

### Fountain Tab and Return

Fountain structure is positional — blank lines and capitalization — so these
affordances insert scaffolding rather than markup:

| Context | Tab | Return |
|---|---|---|
| Empty line, previous block is dialogue or blank | Begin a character cue | — |
| On a character cue | Move to the next line as dialogue | Next line as dialogue, no blank line between |
| On a dialogue line | Wrap the line in `()` as a parenthetical | Continue dialogue |
| On a parenthetical | Move to the next line as dialogue | Next line as dialogue |
| Anywhere ambiguous | Insert a literal tab | Insert a newline |

**The last row is the important one.** When context is ambiguous, an affordance does
the boring thing. An affordance that guesses is worse than no affordance, because the
user cannot predict it and the correction costs more keystrokes than it saved.

### Undo

**Every affordance-driven rewrite is one undo action, together with the keystroke that
triggered it.** Pressing Return once and Cmd-Z once must return to exactly the prior
state — not to a half-inserted list marker.

The binding constraint: the rewrite must go through the text view's own input path, in
the same transaction as the user's input. Mutating text storage after the fact
registers a second undo group, and no amount of `NSUndoManager` grouping reliably
merges it afterward. This is a design constraint, not an implementation detail — it
determines the shape of the coordinator.

On iOS, undo is deferred (Known limitations §1). The affordances still apply; their
undo granularity is whatever UIKit provides until that work is done.

Paste inserts verbatim with no transformation, as a single undo action, and rescans as
an ordinary edit.

### Text-system hygiene

The following **must be disabled**, on both platforms, and this is not a preference:

- Smart quotes. `"` becoming `"` corrupts Markdown link titles and Fountain notes.
- Smart dashes. `--` becoming `—` silently destroys `---` thematic breaks, and the
  user cannot see why their document stopped parsing.
- Automatic text replacement, and automatic spelling correction on macOS.
- Autocorrect on iOS, by default. A host may opt in; it mutates text and can eat
  markers.

Every one of these is a system feature that rewrites the user's source behind their
back. In a plain-text editor whose entire premise is that the string is the value
(Architecture §1), they are corruption, not convenience.

Spell **checking** is permitted and encouraged — it draws with temporary attributes,
which do not participate in `setAttributes(_:range:)` and therefore survive restyling
untouched.

### External text replacement

Setting the `@Binding` from outside is a reset, not an edit:

1. If the incoming string equals the current storage contents, **do nothing.** Not an
   optimization — without this check, SwiftUI's update cycle feeds the editor its own
   output and the view fights the user's typing.
2. Otherwise replace the full range with `replaceCharacters(in:with:)` inside
   `beginEditing()`/`endEditing()` — never `setAttributedString` (Architecture §8) —
   then full-scan and restyle.
3. Clamp the selection to the new length rather than dropping it to zero.
4. Register as a single undo action.

## API surface and stability

### What is public in 1.0

`EscriboCore`: `Language`, `EscriboSpan`, `SpanKind`, `StyleSet`, `SpanRole`,
`LineRecord`, `ElementKind`, `ScanResult`, `TextEdit`, the scanner entry points, and
the writer. `SwiftEscribo`: the editor view, `EscriboTheme`, `TokenStyle`,
`ParagraphMetrics`, `EditorMode`.

The editor view's initializer is
`EscriboEditor(text:language:mode:theme:findBar:focusOnAppear:)`. `mode`, `theme`,
`findBar`, and `focusOnAppear` are all defaulted, so every call form that predates a
parameter keeps compiling — adding a defaulted parameter to this initializer is a
**minor** release.

`findBar` is a `Bool`, defaulting to `false`. It asks for the system find **bar** —
the accessory inside the editor's own scroll view, with incremental searching on — never
the floating find panel, which is a separate window. It is platform-neutral in the
signature and honoured on macOS only; `UITextView` has no equivalent, so on iOS it is
accepted and ignored rather than fenced out, and a cross-platform host writes one call
site instead of two. The menu items and their key equivalents stay the host's job
(Non-goals §8).

`focusOnAppear` is a `Bool`, defaulting to `false`. When on, the editor's text view
becomes the window's **first responder** the moment it is installed, so the first
keystroke into a freshly-opened document reaches the document instead of nowhere. It
fires **once**, on the first window the view is given; a re-attachment is not an
appearance, and re-focusing on every layout pass would drag the caret back from wherever
the user put it.

It is a hook rather than a convenience. A `NSViewRepresentable`'s view is unreachable
from SwiftUI's focus system, so a host that wants the caret in the editor has no option
but a sibling probe that walks the window's content view hunting for an `NSTextView`.
This package owns the view it is focusing and performs **no view-hierarchy walk**: the
answer is stored at construction and spent in the shipped text view's
`viewDidMoveToWindow()`, where the object to focus is `self`. Consumers may delete their
focus probes.

Platform-neutral in the signature and honoured on macOS only, like `findBar` — but the
iOS no-op is a decision rather than a gap: `becomeFirstResponder()` on a `UITextView`
raises the software keyboard, and doing that the instant a document opens is an
interruption rather than a convenience.

`LineState` is public but **opaque** — no public cases, no public properties. It
exists in the API only because `LineRecord` carries it. Exposing its shape would
freeze the scanner's internals at 1.0 and make every convergence improvement a
breaking change.

Everything else is `internal`. Nothing becomes `public` speculatively: if neither
`SwiftEscribo` nor a test consumes it, it stays internal until something does.
Removing public API is expensive; never having added it is free.

### Semver commitments

- Adding a `SpanKind` or `ElementKind` static member is a **minor** release. This is
  the entire reason they are structs rather than enums (Core API), and it is what
  makes "we found another Fountain construct" a routine event.
- Adding a `StyleSet` case is **minor**; raw values are stable, so existing bit
  positions never move.
- Changing what an existing kind is emitted for is **major**, even though it does not
  break compilation. It silently changes how every existing theme renders, which is
  worse than a compile error.
- Reordering or renumbering anything with a raw value is **major**.
- Deprecation runs one minor release with `@available(*, deprecated)` before removal.

## Scope boundaries

### Accessibility

Because display text is character-identical to source (Architecture §2), VoiceOver
reads the source directly and needs no custom mapping — that is a real benefit of the
visible-marker design and it comes for free.

The honest tradeoff: a screen-reader user hears the markers. `**bold**` is read with
its asterisks. 1.0 accepts this rather than adding an accessibility text mapping,
because such a mapping is exactly the source↔display index map that Architecture §2
exists to avoid, and half of one is worse than none.

### Writing direction

Markdown uses natural paragraph alignment and works in RTL text. **Fountain paragraph
geometry is LTR-only** — screenplay margins are defined in characters from a left
margin at 10 CPI, and a mirrored screenplay layout is not a format that exists. This
is a scope statement, not a defect.

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
4. Editing affordances: Markdown list continuation and outdent-on-empty-Return;
   Fountain smart Tab (cue → dialogue → parenthetical) and Return. **Every rewrite
   must register as a single coalesced undo action**, or Cmd-Z unwinds character by
   character. Specified in Editing behavior, which also explains why "input
   shortcuts" is the wrong frame for an editor with visible markers, and which
   text-system features must be disabled to keep the source intact.
5. Themeable: fonts, colors, and marker opacity, with built-in light and dark themes.
   See Theme and styling for the API and its constraints.
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

   The generated edits must include the cases that break convergence rather than
   uniform random typing: editing the line *after* an ALL-CAPS line (the backward
   dependency in Architecture §5), opening and closing fences and boneyards,
   pasting and deleting multi-line blocks, and editing at offset 0 and at EOF.
   A generator that only types single characters mid-paragraph passes against a
   scanner that is wrong.
3. **Span invariant test**, asserted on every scan in the whole suite, not as its own
   case: spans are ordered, non-overlapping, and exactly tile `dirtyRange`, and
   `dirtyRange` is line-aligned and contains the edit (Core API). These are cheap
   enough to check unconditionally, and a violation means the styler will leave stale
   attributes on screen — a symptom that is miserable to diagnose from the UI and
   trivial to catch here.

   Two theme assertions belong here for the same reason (Theme and styling):
   under the source theme every span resolves to identical attributes regardless of
   kind, style, or role; and an unrecognized `SpanKind` resolves to the base style
   rather than failing.
4. **Round-trip test** for the writer, correctly formulated as idempotence:
   `parse(write(parse(x))) == parse(x)`. Note that `write(parse(x)) == x` is *not* a
   valid assertion — writing normalizes, so it fails on any non-canonical input.
5. **Differential test** against `swift-markdown` (test-only) for CommonMark block
   structure agreement.
6. Golden fixture corpus of `.md` and `.fountain`, including hostile input:
   unterminated fences, nested emphasis, CRLF line endings, an ALL-CAPS line at EOF,
   malformed GLOSA tags, and real org screenplays
   (`~/Projects/apps/Produciesta/fixtures/episode_10.fountain`).
7. Performance assertions live in `EscriboPerformanceTests`, excluded from the
   PR-blocking job — wall-clock budgets are too machine-dependent to gate a merge.
8. **Only scan time is asserted.** The budget covers the scanner returning a dirty
   range and its tokens, measured in `EscriboCore` with no UI. End-to-end frame time
   (TextKit 2 attribute application and relayout) is observed and reported, never
   asserted — it is not controllable by this package and would make the suite a flake
   generator.
9. Budgets are measured over an edit sequence that includes the pathological cases,
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

All figures on a 120-page screenplay (~120 KB), scan time only (Verification §8),
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

Two things the guard must get right, or it will pass while proving nothing:

- **Depend the way real consumers do.** The measurement above used a *versioned git*
  dependency. Whether pruning behaves identically for a `path:` dependency was not
  tested, and a guard built on an untested code path is not evidence. Either use a
  git dependency on the commit under test, or verify the path-dependency case
  explicitly before relying on it.
- **Prove the guard can fail.** Once, deliberately, add `import Markdown` to a
  shipping target and confirm the job goes red. A guard that has never failed is
  indistinguishable from a guard that cannot fail, and the second kind is worse than
  none because it is trusted.

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
