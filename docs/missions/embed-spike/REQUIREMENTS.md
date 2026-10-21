---
type: project
title: SwiftEscribo — spike: atomic block embeds on TextKit 2
updated: 2026-10-20
state: draft
kind: spike
---

# Spike: atomic block embeds on TextKit 2

**Question:** can SwiftEscribo draw one paragraph of a document as a single atomic row —
an icon, a title, a subtitle and a badge, supplied by the host — while the paragraph's
characters stay in the text storage unchanged, on **both** macOS (`NSTextView`) and iOS
(`UITextView`) on the TextKit 2 stack the package already uses?

This is a **throwaway** branch (`spike/block-embeds`). Its deliverable is a written
report with a go / no-go per platform, not a release. Code from it may be reused by the
release mission (`docs/missions/block-embeds/REQUIREMENTS.md`) but is not reviewed for
merge.

## Why a spike first

Drawing a paragraph differently is what TextKit 2 layout fragments are for. Making it
behave as **one unit** — the caret never inside it, arrow keys stepping over it,
selection taking it whole, delete removing it whole — while it is still ordinary text
is not something the package does anywhere today, and the two platforms expose
selection differently. If either platform cannot do it cleanly, the release design
changes (fallback: keep the text and decorate it from the paragraph well), and that is
a product decision for the user, not a sortie's.

## What exists (to be verified at recon)

- `MacTextView.swift` / `IOSTextView.swift` both define `EscriboTextView`, wrapping
  `EscriboNativeTextView` (`EditorInputPath.swift:93,234`), built on TextKit 2
  (`MacTextView.swift:164`, `IOSTextView.swift:173`).
- `EscriboEditorBridge` is the text view's delegate on both platforms
  (`EscriboEditorRepresentable.swift`). On iOS it has `textViewDidChangeSelection`
  (`:201`); **on macOS it implements only `textDidChange` (`:184`), so a macOS
  selection hook is new work.** No TextKit 2 layout-manager or content-storage
  delegate is installed anywhere, so the spike's delegate collides with nothing.
- `EditorMode` is a struct with `.live` and `.source` (`EditorMode.swift`).
- The paragraph well (`EscriboWell`, `WellOverlay`, `WellTracker`) already maps blocks
  to on-screen geometry — prior art for per-block drawing.
- Blocks come from the scan: `EscriboBlock` with a UTF-16 range; a note standing alone
  is its own `.note` block (`EscriboCore/EscriboBlock.swift`).
- `make build`, `make test`, `make test-ios` exist (`Makefile`).

## What to prove, per platform

| # | Behaviour | Pass when |
|---|---|---|
| 1 | Draw | A chosen block renders as a fixed-height row with a symbol, two text lines and a trailing badge, at the paragraph's indent; the rest of the document lays out normally around it; zoom scales it |
| 2 | Storage untouched | `textStorage.string` is byte-identical with and without the embed; find, copy-all and word count see the original text |
| 3 | Caret step-over | Arrow keys (all four) and click never place the caret inside the block's range; Up/Down from adjacent lines land before/after it |
| 4 | Select whole | Shift-arrow and drag selections that touch the block extend to its full range |
| 5 | Delete whole | Delete/Backspace with it selected removes exactly its range plus one adjacent blank line, as one undo step |
| 6 | Copy source | Copy with it selected puts the original characters on the pasteboard |
| 7 | Typing ignored | A keystroke with it selected changes nothing |
| 8 | Expand / collapse | The host can turn the embed off for one block (*Edit as Text*) and back on; the caret can enter while expanded |
| 9 | Accessibility | VoiceOver reads it as one element with a label and value and activates it with the default action |
| 10 | Multi-line block | A block whose text spans several lines (no blank line) is still one block (it is today, when the note stands alone — recon confirmed) and draws as one row; it is several layout fragments, so the row collapses N fragments |
| 11 | Scroll and edit elsewhere | Typing above the block, and scrolling, keep it drawn correctly; no layout thrash |

## Deliverable

`docs/missions/embed-spike/SPIKE_REPORT.md` with, per platform: the mechanism used
(e.g. `NSTextLayoutManagerDelegate.textLayoutManager(_:textLayoutFragmentFor:in:)` with a
custom fragment; selection constrained in the delegate's selection-change hook), a
pass/fail per row above with evidence (a screen recording or UI-test output), known
limitations, and an estimate for the release mission. Ends with **go / no-go** per
platform.

## Non-goals

- Public API design (that is the release mission).
- Any host app integration.
- Merging the spike branch.
