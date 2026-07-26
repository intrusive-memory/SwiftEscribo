import EscriboCore
import Testing

@testable import SwiftEscribo

/// Sortie 11 exit criterion: "The coordinator type used by both Representables is the
/// same declared type."
///
/// DL-58 makes ``EditorCoordinator`` deliberately non-generic so this is a fact the type
/// checker can enforce rather than a convention two files happen to follow. This file
/// proves it the way the plan asks: one test, compiled with both `#if os(macOS)` and
/// `#if os(iOS)` branches, each building the platform's real `EscriboTextView` and binding
/// its `coordinator` to a `let` explicitly typed ``EditorCoordinator`` — if either
/// Representable ever exposed a different type (a generic specialization, a subclass, a
/// protocol existential), this file would fail to compile on that platform rather than
/// merely fail to run.
///
/// Only one branch is ever compiled in a given build, exactly as `MacTextViewTests.swift`
/// and `IOSTextViewTests.swift` are each compiled on one platform only — the criterion is
/// discharged by the same source file existing unchanged across both `make test` and
/// `make test-ios`, not by both branches running in the same process.
@MainActor
@Suite("Coordinator parity across Representables")
struct PlatformCoordinatorParityTests {

  @Test("Both platforms drive the identical declared EditorCoordinator type")
  func sameCoordinatorTypeOnBothPlatforms() {
    #if os(macOS)
      let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    #elseif os(iOS)
      let editor = EscriboTextView(language: .markdown, theme: .markdownLight)
    #endif

    // The type annotation is the assertion: this would not compile if `coordinator` were
    // anything other than exactly `EditorCoordinator` on this platform.
    let coordinator: EditorCoordinator = editor.coordinator
    #expect(coordinator.language == .markdown)
    #expect(type(of: coordinator) == EditorCoordinator.self)
  }
}
