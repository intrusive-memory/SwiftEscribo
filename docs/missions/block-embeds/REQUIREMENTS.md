---
type: project
title: SwiftEscribo — block embeds, notice well slot, and JSON in notes (minor release)
updated: 2026-10-20
state: draft
depends_on: docs/missions/embed-spike (go on both platforms, accepted by the user)
---

# SwiftEscribo — block embeds

A host can ask the editor to draw any block as an **embed**: one atomic row with a
glyph, title, subtitle and badge, while the block's characters stay in the document. A
screenplay host uses it to show a structured directive note as a compact object instead
of its markup. The package knows nothing about what an embed means.

Also in this release: a **notice** slot in the paragraph well, and **JSON scanning
inside Fountain notes** so GLOSA notation 2.0 block directives (a JSON object in a
note, defined by glosa-av 0.9.0) are syntax-coloured.

**Gate in:** the embed spike (`docs/missions/embed-spike/`) reports go on macOS and iOS
and the user accepts it. If it does not, this document is rewritten around the
well-slot fallback before any breakdown.

## 1. Embeds

1. **API.**
   - `public protocol EscriboEmbedProvider` — asked for each block in `EditorMode.live`
     only: `func embed(for block: EscriboBlock, in text: String) -> EscriboEmbed?`.
     `nil` draws the text as today.
   - `public struct EscriboEmbed: Equatable, Sendable` — `symbolName`, `title`,
     `subtitle`, `badge: Badge?` (`symbolName`, `word`, `tint` as an `EscriboColor`),
     `accessibilityLabel`, `accessibilityValue`, `accessibilityIdentifier`,
     `actions: [Action]` (`id`, `title`). Equatable for the same SwiftUI-diffing reason
     as `EscriboWell` (`EscriboWell.swift`).
   - `EscriboEditor` gains `embedProvider: (any EscriboEmbedProvider)? = nil`,
     `onEmbedActivate: (EscriboBlock) -> Void`, `onEmbedAction: (EscriboBlock, String)
     -> Void`, and (macOS) `onFindMatchInEmbed: (EscriboBlock) -> Void`. All defaulted,
     so existing call sites compile unchanged.
   - **No expanded-set parameter.** `EscriboBlock.ID` is not stable across edits
     (`EscriboBlock.swift:26–33`), so a host-held `Set<EscriboBlock.ID>` would go stale
     after any edit above the block. *Edit as Text* is expressed by the provider itself
     returning `nil` for that block; the host keys its own expanded state on something
     stable to it (for a directive note, its content or an id inside it).
2. **Drawing** by the mechanism the spike proved: a fixed-height row (two lines of the
   current font) at the block's indent, at most the text column's width; scales with
   zoom; uses the theme's colours.
3. **Behaviour** (the spike's table, now required): caret never inside; arrows step
   over; selection extends to the whole block; Delete/Backspace removes the block plus
   one adjacent blank line as one undo step; Copy yields the source; typing with it
   selected is ignored; click selects it and calls `onEmbedActivate`; `⌥↩` with it
   selected calls the *Edit as Text* action; Find expands the embed holding the current
   match — **macOS only**, since the find bar is macOS-only — by calling
   `onFindMatchInEmbed`; the host then stops returning an embed for that block. The find
   bar has no current-match hook today, so this needs one (new work, named here).
4. **Accessibility:** one element per embed, button role, the host's label / value /
   identifier, default action = activate, custom actions = `actions`.
5. **Off by default:** no provider → no change to layout, insets or behaviour; the
   existing UI tests pass untouched.

## 2. Notice well slot

`EscriboWellItem.notice` (a new static member — additive, per the type's own
forward-compatibility rule) with a host-supplied glyph and help text per block, and a
click callback through the existing `onWellAction`.

## 3. JSON inside notes

Today `GlosaScanner` (`EscriboCore/GlosaScanner.swift`) subdivides tag directives inside
notes into `glosaTag` / `glosaAttributeName` / `glosaAttributeValue` /
`glosaPunctuation` spans (`SpanKind.swift:294–331`). It sees **one line at a time** and
carries no state between lines (`GlosaScanner.swift:58–66`, `FountainGrammar.swift:1024`),
so it cannot know that line 2 of a note is inside JSON. Add: a note whose trimmed content
starts with `{` is scanned as JSON —

- new span kinds `glosaJSONKey`, `glosaJSONString`, `glosaJSONNumber`,
  `glosaJSONLiteral` (`true`/`false`/`null`), reusing `glosaPunctuation` for braces,
  brackets, colons and commas;
- malformed JSON stops subdividing at the first error and leaves the rest as `note`
  (no exception, no trap — the scanner's totality rule);
- **multi-line JSON notes are scanned across lines.** This is real work, named here:
  the line state the scanner carries (`LineState`) gains a "inside a JSON note" context
  (string/escape state and nesting depth), and the incremental scanner re-scans
  following lines when that context changes. The existing performance budgets
  (`make test-performance`) must still pass. A note's lines remain one `.note` block
  only when it stands alone between blank lines — a note flush against action or
  dialogue merges into that block, and consecutive notes merge into one block;
- **colours**: none of the four built-in themes colours any `glosa*` kind or `.note`
  today, so "same as the tag kinds" would mean uncoloured. Add colours for all `glosa*`
  kinds — existing and new — to all four built-in themes.

## 4. Tests

- Core: JSON span tiling over valid, multi-line, escaped (`]\u005d`) and malformed
  notes; block grouping of a multi-line note as one `.note` block.
- macOS and iOS: the spike's behaviour table as **unit tests** (the package has no UI
  test target); no-provider behaviour checked by unit assertions on insets and layout
  geometry (there is no snapshot-testing setup). Existing `SwiftEscriboTests` pass.
- `make lint`, `make test`, `make test-ios` green.

## 5. Release

Minor release (`0.5.0`). Note in the CHANGELOG that hosts pinned `upToNextMinor` from
any 0.x (0.3.x and 0.4.x pins both exist downstream) must raise their pin to receive
it.

## Non-goals

- Anything about what an embed represents (storyboards, images, render state).
- Inline (mid-line) embeds; only whole blocks.
- Embeds in `EditorMode.source`.
