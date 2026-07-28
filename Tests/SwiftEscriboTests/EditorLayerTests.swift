import EscriboCore
import Testing

@testable import SwiftEscribo

/// The editor layer is built in WU-2. This suite exists now so the target compiles
/// and links `EscriboCore` from the first commit — a test target that is added late
/// hides its own integration breakage until the sortie that needed it is already
/// finished.
@Suite("Editor layer")
struct EditorLayerTests {

  @Test("The editor layer sees the core's language vocabulary")
  func layerSeesCoreVocabulary() {
    #expect(EditorLayer.languages == [.markdown, .fountain])
  }

  @Test("Core value types cross the target boundary intact")
  func coreTypesCrossTheBoundary() {
    // `SwiftEscribo` consumes the vocabulary `EscriboCore` defines; nothing is
    // redeclared on this side of the seam.
    let key = (SpanKind.heading, StyleSet.strong, SpanRole.marker)
    #expect(key.0.rawValue == "heading")
    #expect(key.1.rawValue == 1)
    #expect(key.2 == .marker)
  }
}
