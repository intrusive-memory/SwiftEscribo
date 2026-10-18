---
type: requirements
title: SwiftEscribo 0.5.0 — the well shows work
updated: 2026-10-18
state: incomplete
consumer: Escribir 1.2.0
---

# SwiftEscribo 0.5.0 — the well shows work

0.4.0's well has two things it can say about a block: it is playing, or it is not. That was
enough while every voice was `AVSpeechSynthesizer` and speech began in the same frame as the
click.

Escribir 1.2.0 introduces a neural voice that takes **seconds** to produce a paragraph. The well
needs a state between "not playing" and "playing", and a state for "that did not work." This
release adds exactly those two and nothing else.

**Consumer:** Escribir 1.2.0, `docs/REQUIREMENTS-1.2.0.md` § 4 in
`~/Projects/apps/Escribir`. Where that document and this one disagree about the well's
behaviour, that one wins and this one is amended — it owns the feature; this package owns the
drawing.

## Status — not started (checked 2026-10-18 against `v0.4.4`)

None of this document's API exists in the package: no `EscriboWellItemState`, no
`itemStates`, `WellTracker.Role` still has its four 0.4.0 cases, and
`symbolName(for:isPlaying:)` is unchanged. The design below is intact and its decisions still
hold. Two things have moved since it was written:

- **The consumer's version number is gone.** What ships as Escribir 1.2.0 is dossiers, the
  control bar and the paged preview; the generated-voices feature that needs these states was
  never scheduled. Retitle the consumer document when it is.
- **The line numbers below were validated against `v0.4.0`** (`f3addc3af035`). Four patch
  releases have landed since (`v0.4.1`–`v0.4.4`, including the spoken-word highlight in
  0.4.2 that reworked `WellOverlay`). Re-resolve every citation in a recon pass before
  breakdown.

## What exists today (validated 2026-09-20 against `f3addc3af035`, tag `v0.4.0`)

- **`EscriboWellItem`** — `public struct … Hashable, Sendable` with a `rawValue: String`
  (`Sources/SwiftEscribo/EscriboWell.swift:29`). Its own doc says why it is not an enum: *"a
  public enum is source-breaking to extend."* That reasoning governs this release too.
- **`EscriboWell`** — `public struct … Equatable, Sendable`
  (`EscriboWell.swift:71-117`) with public stored properties `items: [EscriboWellItem]`,
  `activeBlock: EscriboBlock.ID?`, `progress: Double?`, `spokenRange: NSRange?`,
  `eligibleKinds: Set<BlockKind>?`, and a single memberwise initializer with defaults for every
  parameter.
- **`progress` is the span bar's fill, not a ring.** Its doc comment (`EscriboWell.swift:79`)
  reads: *"`0…1` for the span bar's fill while `activeBlock` plays, or `nil`."* This release must
  not overload it.
- **`WellTracker`** and its nested **`Role`** are **internal**, not public
  (`WellTracker.swift:78-90`). `Role` is an enum with exactly four cases: `hover`, `caret`,
  `playing`, `finished`.
- **`WellPlacement.symbolName(for:isPlaying:)`** — `static func symbolName(for item:
  EscriboWellItem, isPlaying: Bool) -> String?` at `WellOverlay.swift:373`, inside
  `enum WellPlacement` (opens `:266`). **Internal.** Note the owning type: it is *not* on
  `WellTracker`, and Escribir's requirements document names it incorrectly.
- **Rendering** — `WellOverlay` (`WellOverlay.swift:105`, internal, `@MainActor`) reconciles
  tracker state into subviews. `WellButton` draws the glyph; `WellSpanBar` draws the bar. Both
  exist twice, once per platform: macOS at `:487` / `:443`, iOS at `:593` / `:558`. Glyph
  selection call sites are `:513-514` (macOS) and `:613-614` (iOS).
- **`WellTiming`** (`WellTracker.swift:11-35`, internal) — `progressStep: TimeInterval = 0.2`,
  `leaveHysteresis = 0.15` (the 150 ms rule), `finishedHold = 0.4` (the 400 ms rule),
  `fadeIn = 0.12`.
- **No `EscriboWellItemState` exists.** Verified by grep across the package.
- **The package links no speech framework, no networking framework, and no MLX.** Verified: the
  complete import set across `Sources/` is `Combine`, `CoreGraphics`, `CoreText`, `EscriboCore`,
  `Foundation`, `SwiftUI`, plus platform-conditional `AppKit`/`UIKit`.

## Scope

1. A public per-item state vocabulary on `EscriboWell` (§ 1).
2. Two new internal `WellTracker.Role` cases and the glyph/ring rules that follow (§ 2).
3. An indeterminate ring drawn inside the existing button geometry, on both platforms (§ 3).
4. Reduce Motion behaviour for the ring (§ 4).

---

## 1. The public API

```swift
public struct EscriboWellItemState: Hashable, Sendable {
  public let rawValue: String
  public init(rawValue: String)

  public static let idle   = EscriboWellItemState(rawValue: "idle")
  public static let busy   = EscriboWellItemState(rawValue: "busy")
  public static let active = EscriboWellItemState(rawValue: "active")
  public static let failed = EscriboWellItemState(rawValue: "failed")
}
```

A `RawRepresentable`-shaped struct rather than an enum, for the reason `EscriboWellItem` already
gives: an enum makes the next state a major release.

`EscriboWell` gains exactly one stored property:

```swift
public var itemStates: [EscriboWellItem: EscriboWellItemState]
```

**It defaults to empty, and an absent entry means `.idle`.** That default is what keeps 0.5.0 a
*minor* release: every existing adopter compiles and behaves identically without touching a line.
The memberwise initializer gains a defaulted parameter in the same position-independent way the
others have.

**R-1.1.** `EscriboWell()` with no `itemStates` argument MUST be `==` to a 0.4.0 `EscriboWell()`
in observable behaviour, and MUST render identically.

**R-1.2.** The vocabulary is deliberately generic — `busy`, not `generating`. The package draws
and tracks; it does not know what the app is busy doing. Naming the state after the consumer's
feature would be the first time this package assumed one.

## 2. The two new roles

`WellTracker.Role` gains `.generating` and `.failed`. Both are **internal**, so this is not a
source-breaking change to the package's public API.

| State | Glyph | Ring | Span bar |
|---|---|---|---|
| Rest | — | — | — |
| Hover / Caret | `play.fill` | — | — |
| **Generating** | `stop.fill`, inset | indeterminate, accent | — |
| Playing | `stop.fill` | — | filling |
| Finished | `play.fill` | — | full, 400 ms |
| **Failed** | `play.fill` at 38%, badged | — | — |

**R-2.1.** `WellPlacement.symbolName(for:isPlaying:)` becomes
`symbolName(for:state:)`, taking the item and an `EscriboWellItemState`. This is the **only**
source-breaking signature in this release, and it is internal. Both call sites
(`WellOverlay.swift:513-514` macOS, `:613-614` iOS) update with it.

**R-2.2.** A block in `.busy` is **pinned** exactly as a playing block is — the existing rule at
Escribir 1.1.0 § 5.2 rule 3 — so the ring stays visible while the pointer wanders off the block.

**R-2.3.** `.failed` clears on pointer-leave. An error must not outlive the hover that produced
it.

**R-2.4.** No lane width, glyph size, span-bar geometry, or timing constant from 0.4.0 changes.
`leaveHysteresis`, `finishedHold`, `progressStep` and `fadeIn` keep their current values.

## 3. The ring

**R-3.1.** The ring is drawn **inside** the existing 20 pt square. The button does not grow.

**R-3.2.** The ring is **indeterminate** — a rotating arc. No fraction, no percentage, no label,
no time remaining. The package has no progress input for it and must not invent one.

**R-3.3.** `EscriboWell.progress` MUST NOT drive the ring. It is the span bar's fill
(`EscriboWell.swift:79`) and the two are different quantities on different surfaces. A block that
is `.busy` has no span-bar fill and no ring fraction.

**R-3.4.** The ring is implemented on **both** platforms — macOS `WellButton` (`:487`) and iOS
`WellButton` (`:593`). The consuming app's iOS feature is deferred, but this package ships both
platforms and must not regress or stub one.

## 4. Reduce Motion

**R-4.1.** Under Reduce Motion the ring does not rotate. It is drawn whole and static at 35%
accent — still distinct from Rest and from Playing, still no motion. This is the same bargain
0.4.0 already makes for the fades and the animated span-bar fill.

---

## The invariant this release must not break

**Nothing in this package links a speech framework, a networking framework, or MLX.** The package
draws and tracks; the consuming app generates, caches and speaks.

This is the test of whether the API is right. If shipping the ring requires importing AVFoundation
here, the seam is in the wrong place and the design is wrong — not the invariant.

**R-5.1.** A test MUST assert the import set. It is currently `Combine`, `CoreGraphics`,
`CoreText`, `EscriboCore`, `Foundation`, `SwiftUI`, `AppKit`/`UIKit`. Adding to that set is a
deliberate act that must fail a gate first.

## Tests

- `EscriboWellItemState` and the `itemStates` default are pure and table-tested.
- **R-1.1 gets an explicit regression test**: a default-constructed `EscriboWell` behaves as
  0.4.0. This is the claim that makes the release a minor.
- The role→glyph mapping is table-tested through `symbolName(for:state:)`, including every state
  in § 2's table.
- Per the package's carried-forward rules: **no test forces TextKit layout**, and **every numeric
  literal in an `#expect` is typed** — an untyped literal compared against a `CGFloat` reports
  `56.0` vs `56` and reads as a rounding bug when it is a type mismatch.
- `WellTracker`'s explicit-timestamp discipline is preserved: nothing reads a clock, and no test
  sleeps. The two new roles step time by hand like the existing four.
- `make lint` first, as in CI.

## Non-goals

- A determinate ring. It requires a progress input this package does not have and will not
  invent. It returns if and when the consumer can supply a real fraction — with no change to
  § 1's API.
- Well slots beyond Read Aloud.
- Any change to `progress`, `spokenRange`, `eligibleKinds`, or the span bar.
- Making `WellTracker` or `Role` public.
- Knowing what "busy" means.

## Acceptance

1. `EscriboWell()` with no `itemStates` is behaviourally identical to 0.4.0, and renders
   identically.
2. Every state in § 2's table produces its stated glyph via `symbolName(for:state:)`.
3. A `.busy` block draws an indeterminate ring inside the 20 pt square; no geometry from 0.4.0
   moves.
4. A `.busy` block stays pinned while the pointer leaves it.
5. `.failed` clears on pointer-leave.
6. Under Reduce Motion the ring is static, whole, 35% accent.
7. The ring is present on macOS and iOS.
8. The package's import set is unchanged but for nothing — no speech, no networking, no MLX —
   and a test asserts it.
9. The version is this package's next **minor** release.
