// swift-tools-version: 6.2
import PackageDescription

// SwiftEscribo has no dependencies, by charter. It is the org's canonical
// Fountain parser as well as a Markdown/Fountain editor, so anything that can
// parse must be reachable without linking a UI framework.
//
// `EscriboCore` is pure Foundation: scanners, tokens, line index. `SwiftEscribo`
// adds the SwiftUI/TextKit editor on top. A CLI, a server, or SwiftCompartido
// can depend on the former alone.
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
      dependencies: ["EscriboCore"],
      // The Fountain fixture corpus — three vendored screenplays and the hostile
      // documents authored alongside them — plus their golden snapshots. `.copy` rather
      // than `.process` so the bytes reach the bundle **unaltered**: several fixtures
      // exist precisely to carry CRLF, a lone CR, or a missing final terminator, and a
      // resource rule entitled to transform them would launder away the thing under test.
      // The directory structure is preserved, so the loader reaches them at
      // `Fixtures/Fountain` and `Fixtures/Golden` through `Bundle.module`. No test may
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
