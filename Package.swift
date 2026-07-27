// swift-tools-version: 6.2
import PackageDescription

// SwiftEscribo has no *shipping* dependencies, by charter. It is the org's
// canonical Fountain parser as well as a Markdown/Fountain editor, so anything
// that can parse must be reachable without linking a UI framework.
//
// `EscriboCore` is pure Foundation: scanners, tokens, line index. `SwiftEscribo`
// adds the SwiftUI/TextKit editor on top. A CLI, a server, or SwiftCompartido
// can depend on the former alone.
//
// The single entry in `dependencies:` below is `swift-markdown`, and it is
// reachable from **`EscriboCoreTests` only** — see the comment on that target and
// on the `no_markdown_import_in_sources` rule in `.swiftlint.yml`. SwiftPM prunes
// a test-only dependency out of every downstream consumer's graph, but it does so
// as a *graph* property rather than a declaration: nothing here marks the
// dependency test-only, and nothing errors the day a shipping target imports it
// (swiftlang/swift-package-manager#7007). The charter therefore holds only as long
// as no target under `Sources/` says `import Markdown`.
let package = Package(
  name: "SwiftEscribo",
  platforms: [
    .macOS(.v26),
    .iOS(.v26),
  ],
  products: [
    .library(
      name: "EscriboCore",
      targets: ["EscriboCore"]
    ),
    .library(
      name: "SwiftEscribo",
      targets: ["SwiftEscribo"]
    ),
    // The project-metadata model (PROJECT.md front matter and the cast list).
    // Shipped separately so a CLI or a server can read project metadata without
    // linking the editor, and so the scanner's 1.0 public surface stays exactly
    // what the scanner declares.
    .library(
      name: "EscriboProject",
      targets: ["EscriboProject"]
    ),
  ],
  dependencies: [
    // The CommonMark/GFM differential oracle for `MarkdownGrammar`. Version floor
    // resolved from the package's GitHub releases on 2026-07-26: 0.8.0 is the
    // latest published release (`gh release list --repo swiftlang/swift-markdown`).
    //
    // TEST-ONLY. Referenced by `EscriboCoreTests` and by nothing else, ever.
    .package(url: "https://github.com/swiftlang/swift-markdown.git", .upToNextMajor(from: "0.8.0"))
  ],
  targets: [
    .target(
      name: "EscriboCore",
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
    .target(
      name: "SwiftEscribo",
      dependencies: ["EscriboCore"],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
    // `PROJECT.md` front matter and the cast list — the org's project-metadata
    // model, vendored here so there is one canonical definition of the structure
    // rather than one per app. Foundation only, like `EscriboCore`: this is a data
    // model, and a data model that needs AppKit cannot be read by a CLI.
    //
    // Deliberately *not* folded into `EscriboCore`. `EscriboCore` is the scanner
    // layer, and its public surface is audited line by line against the 1.0 list;
    // podcast project metadata is not part of that surface and must not enlarge it.
    .target(
      name: "EscriboProject",
      dependencies: ["EscriboCore"],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
    .testTarget(
      name: "EscriboCoreTests",
      dependencies: [
        "EscriboCore",
        // The differential oracle, and the **only** place in this package graph that
        // may name it. `EscriboCore`, `SwiftEscribo`, and `EscriboProject` are
        // shipping targets and list nothing here; a single `import Markdown` under
        // `Sources/` would make CommonMark a transitive dependency of every consumer
        // of the Fountain parser, silently and with no build error. The
        // `no_markdown_import_in_sources` SwiftLint rule is what catches that.
        .product(name: "Markdown", package: "swift-markdown"),
      ],
      // The Fountain fixture corpus — three vendored screenplays and the hostile
      // documents authored alongside them — plus their golden snapshots. `.copy` rather
      // than `.process` so the bytes reach the bundle **unaltered**: several fixtures
      // exist precisely to carry CRLF, a lone CR, or a missing final terminator, and a
      // resource rule entitled to transform them would launder away the thing under test.
      //
      // `Fixtures/Markdown` holds the differential-oracle corpus and is `.markdown`
      // rather than `.md` on purpose — a repo-wide policy hook requires every `.md` file
      // to open with a YAML `type:` frontmatter block, and prefixing every fixture with
      // the same five lines would make line 0 of the whole corpus uniform. Line 0 is
      // where frontmatter, setext underlines, and thematic breaks are decided.
      //
      // The directory structure is preserved, so the loader reaches them at
      // `Fixtures/Fountain`, `Fixtures/Golden`, and `Fixtures/Markdown` through
      // `Bundle.module`. No test may
      // name a path outside the package.
      resources: [.copy("Fixtures")],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
    .testTarget(
      name: "SwiftEscriboTests",
      dependencies: ["SwiftEscribo"],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
    .testTarget(
      name: "EscriboProjectTests",
      dependencies: ["EscriboProject"],
      // Real `PROJECT.md` files, vendored (D-3), plus the mechanically-derived JSON
      // transcription of each one's front matter. `.copy` rather than `.process` for
      // the same reason as above: the point of a provenance fixture is that the bytes
      // in the bundle are the bytes that were committed. Reached through
      // `Bundle.module` at `Fixtures`; no test may name a path outside the package.
      resources: [.copy("Fixtures")],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
    // Kept out of the PR-blocking job; timing assertions are too machine
    // dependent to gate a merge on.
    .testTarget(
      name: "EscriboPerformanceTests",
      dependencies: ["EscriboCore"],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
