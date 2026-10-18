---
type: project
---

# TODO — Display-only uppercasing of sluglines

## Status: withdrawn, not deferred (2026-09-12)

Escribir renders sluglines as typed. The bold + underline treatment this document wanted
already ships host-side, through the theme's public tables (Escribir `5d66275`). The
remaining piece analyzed below — forcing an ALL CAPS *display* without touching the
document byte for byte — is withdrawn, not deferred: it should not be re-proposed from
this file without a new product decision. The analysis below is kept for the record, not
as a live plan.

## The ask

Escribir renders Fountain scene headings bold + underlined + spaced (host-side, through
the theme's public tables — shipped in Escribir `5d66275`). The remaining piece of the
slugline treatment cannot be expressed from outside the package: **sluglines should
*display* in ALL CAPS however the source spells them, without changing a single document
byte.** `EXT. Granville — Beaver Hole Park — Mid-Afternoon` in the file must render as
`EXT. GRANVILLE — BEAVER HOLE PARK — MID-AFTERNOON` in the live editor, and save back
byte-identical.

## Why no theme entry can do it

A `TokenStyle` contributes *attributes*; it cannot replace characters, and neither
`NSAttributedString` nor TextKit has a "render as uppercase" attribute. Escribir's
`ScriptPreview` (read-only, typesets a copy) already uppercases; the live editor's string
**is** the document (Architecture §1), so the transform has to happen between the backing
store and layout.

## The mechanism: TextKit 2 content layer

`EscriboNativeTextView` is guaranteed TextKit 2 (`init(usingTextLayoutManager: true)`),
so the sanctioned seam exists: set the `NSTextContentStorage`'s delegate and implement

```swift
textContentStorage(_:textParagraphWith range:) -> NSTextParagraph?
```

returning a **display-only** paragraph whose attributed string is the backing paragraph
uppercased run-by-run (attributes preserved on the characters they styled). The backing
`NSTextStorage` — and therefore the document, undo, find, and byte identity — is never
touched.

## Proposed API (additive → minor bump to 0.4.0)

- `EscriboTheme.uppercasedElements: Set<ElementKind>` — default `[]`, new init parameter
  with default so every existing call site compiles.
- Built-in themes **unchanged** (no behavior change for existing consumers); hosts opt in.
  Escribir's `SluglineStyle` will insert `.sceneHeading`.
- `strippedToSource()` empties it like every other table: source mode shows the raw file,
  exactly as typed. (This also gives live/source toggling the right behavior for free.)

## Wiring

- Classification must come from the scan, not a second reading of Fountain:
  `EditorCoordinator.lastLineRecords` / `elementKind(atUTF16Offset:)` is the existing
  seam (DL-108). The delegate asks the coordinator what element the paragraph's line is.
- `MacTextView` and `IOSTextView` both set the content-storage delegate; the transform
  itself lives in platform-neutral code beside the coordinator.

## Guards (each one is a test)

1. **Length preservation.** Only substitute when uppercasing preserves UTF-16 length —
   `ß → SS` (and friends) would desynchronize caret/selection mapping between display
   and backing text. A paragraph whose uppercased form changes length renders untransformed.
2. **Marked text.** Never substitute the paragraph hosting an IME composition
   (Architecture §8's reasoning applied to layout: tearing the composition's display
   breaks CJK input). The coordinator's `hasMarkedText` closure is already the seam.
3. **Byte identity.** After any amount of typing into a transformed slugline, the backing
   store equals what was typed; save round-trips byte-identical.
4. **Invalidation.** When a line *becomes* or *stops being* a scene heading mid-typing,
   the content storage must re-ask the delegate for that paragraph. Verify the restyle
   pass's attribute edits trigger it; if not, invalidate the paragraph range explicitly
   from the coordinator's apply path.
5. **Find / replace / go-to-line** operate on backing-store ranges and still land
   correctly inside transformed paragraphs (1:1 mapping is guaranteed by guard 1).
6. **Caret round-trip.** Click at every character of a mixed-case slugline; insertion
   point maps to the same backing offset it would without the transform.

## Downstream (Escribir)

- Pin is `upToNextMajor(from: 0.3.0)`, so 0.4.0 is picked up on resolve — no project edit.
- `SluglineStyle.apply(to:language:)` adds `.sceneHeading` to `uppercasedElements` and
  its doc comment's "uppercasing cannot be here" paragraph gets rewritten.
- `ScriptPreview` keeps its own uppercasing (it renders a copy; no editor involved).

## Release path

Feature branch → development → main per the usual flow; `ship-swift-library minor`.
