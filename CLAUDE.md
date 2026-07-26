---
type: doc
title: SwiftEscribo — Claude Code guidance
updated: 2026-07-25
---

# CLAUDE.md

Guidance for Claude Code working in this repository.

Full project documentation, architecture, and constraints live in
**[AGENTS.md](AGENTS.md)**. Read it before changing the scanners.

## Quick reference

**Project**: SwiftEscribo — stylized Markdown/Fountain editor, and the org's
canonical Fountain parser

**Platforms**: macOS 26.0+, iOS 26.0+ · **Swift** 6.2+ · **Dependencies**: none

## The three rules most easily broken

1. **No regex in the scanners.** Hand-written line scanning only. Replacing the old
   regex parser is the reason this package exists.
2. **`EscriboCore` imports Foundation only** — no SwiftUI, AppKit, or UIKit.
3. **Use `make`, never `swift build` / `swift test`.** Run `make help` for targets;
   `make test-core` is the fast loop.

## Layout

- `Sources/EscriboCore/` — tokens, line index, incremental scanner, Markdown and
  Fountain scanners. Pure Foundation.
- `Sources/SwiftEscribo/` — theme, styler, TextKit 2 Representables, SwiftUI view.
- `Tests/EscriboCoreTests/` — scanner correctness, including the
  incremental-equals-full property test that gates scanner changes.
