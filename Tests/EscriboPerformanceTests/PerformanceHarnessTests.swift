import EscriboCore
import Testing

/// The performance suite proper arrives in Sortie 28, with the assembled ~120 KB
/// screenplay fixture and the scan-time budgets. This suite exists now only so the
/// target compiles and `make test-performance` has something to run — deliberately
/// with **no timing assertion**, since a wall-clock assertion with nothing to measure
/// is exactly the flaky-test class this target is quarantined from the PR gate for.
@Suite("Performance harness")
struct PerformanceHarnessTests {

  @Test("The performance target links EscriboCore")
  func targetLinksCore() {
    #expect(Language.fountain.rawValue == "fountain")
    #expect(SpanKind.text.rawValue == "text")
    #expect(ElementKind.paragraph.rawValue == "paragraph")
  }
}
