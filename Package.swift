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
