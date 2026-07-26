---
type: doc
title: SwiftEscribo
updated: 2026-07-25
---

# SwiftEscribo

A stylized SwiftUI text editor for Markdown and Fountain screenplays, and the
canonical Fountain parser for the Intrusive Memory package collection.

**Platforms**: macOS 26.0+, iOS 26.0+ · **Swift**: 6.2+ · **Dependencies**: none

## Two products

| Product | Imports | Use it when |
|---|---|---|
| `EscriboCore` | Foundation only | You need to parse Markdown or Fountain — CLI tools, servers, document pipelines |
| `SwiftEscribo` | SwiftUI, TextKit 2 | You need the editor view |

Parsing never requires linking a UI framework.

## Design

**The raw string is always the value.** The editor edits a `String` of Markdown or
Fountain source. Nothing is derived, round-tripped, or reconstructed — what you set
is what you get back, byte for byte.

**Syntax markers are dimmed, not hidden.** `**bold**` shows its asterisks at reduced
opacity while the word renders bold. Because displayed text stays character-identical
to source, selection, undo, find, click-to-position, IME composition, and
accessibility all work without a source↔display index map. Editors that hide markers
need that map, and it is where most of their bugs live.

**No regular expressions.** Both scanners are hand-written and line-oriented. This is
a correctness decision before it is a performance one, but it is also why the parser
is fast enough to run on every keystroke.

**Two outputs from one pass.** Scanning yields inline tokens with source ranges (for
highlighting) *and* per-line element classification with content ranges (for
semantics). Consumers that want a screenplay element list get it as a `map` over the
line records rather than a second parse.

## Status

Under construction. See `AGENTS.md` for architecture and the current phase.

## License

MIT
