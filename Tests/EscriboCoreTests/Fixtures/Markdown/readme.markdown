# SwiftEscribo

A stylized Markdown and Fountain editor, and the org's canonical Fountain
parser.

## Installation

Add the package, then:

```swift
import EscriboCore

var scanner = EscriboScanner(language: .markdown)
let result = scanner.fullScan(text)
```

## Constraints

- Zero shipping dependencies.
- No regular expressions in the scanners.
- `EscriboCore` imports Foundation only.

> The old parser's regexes are what this package exists to replace.

## Status

| Layer     | State    |
|-----------|----------|
| Scanner   | Shipping |
| Writer    | Building |

See [AGENTS.md](AGENTS.md) for the full charter.
