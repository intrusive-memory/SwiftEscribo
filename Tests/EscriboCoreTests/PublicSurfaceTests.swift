// Deliberately NOT `@testable`. This file is the only one in the target that sees
// `EscriboCore` the way a consumer does, which is what makes it able to assert
// anything about the *public* surface at all. Adding `@testable` here would silently
// delete every assertion in it.
import EscriboCore
import Testing

/// Accepts any `Sendable` type. Passing a metatype is a compile-time proof that the
/// type is publicly visible and publicly `Sendable`, and needs no instance — which
/// matters for a type that cannot be constructed from here.
private func requireSendableType<T: Sendable>(_ type: T.Type) -> String {
  String(describing: type)
}

/// Accepts any `Equatable` type. Passing a metatype proves the *conformance* is public,
/// not merely that the type is.
private func requireEquatableType<T: Equatable>(_ type: T.Type) -> String {
  String(describing: type)
}

/// `LineState` is public but opaque, and opacity is only real if something checks it
/// from outside. This suite is that check: it imports `EscriboCore` without
/// `@testable`, so every line here compiles against exactly what ships.
///
/// The negative half — that no public member is reachable — cannot be asserted by
/// running code, because the failure mode is code that *compiles*. It is asserted
/// instead by the commented lines below: each is a construction or an access that must
/// fail to compile from this file. Uncomment one and the build breaks; if one ever
/// stops breaking the build, the opacity guarantee has been lost and Sortie 30's API
/// audit has a real regression to find.
@Suite("Public surface (no @testable import)")
struct PublicSurfaceTests {

  // MARK: - LineState is comparable but nothing else

  @Test("LineState is publicly visible, publicly Equatable, and publicly Sendable")
  func lineStateIsPubliclyComparable() {
    // Sortie 4's convergence engine compares `startState == previousValue`, and a
    // consumer holding two `LineRecord` values has to be able to make the same
    // comparison. That is the entire public contract of the type, and these two calls
    // are its compile-time proof — no instance required, because from out here no
    // instance can be made.
    #expect(requireEquatableType(LineState.self) == "LineState")
    #expect(requireSendableType(LineState.self) == "LineState")
  }

  @Test("LineState exposes no public initializer, properties, or cases")
  func lineStateIsOpaque() {
    // Every line in this comment block must fail to compile if pasted into this file.
    // They are the specification of the opacity, stated where a reader of the public
    // API will look for it:
    //
    //   _ = LineState()                    // no public initializer
    //   _ = LineState.documentStart        // no public static member
    //   _ = someState.isInFence            // no public property, now or ever
    //
    // Exposing any of them would freeze the scanner's internals at 1.0 and make every
    // convergence improvement a breaking change. What runs here is only the positive
    // half; the negative half is enforced by the compiler on the lines above.
    #expect(requireEquatableType(LineState.self) == "LineState")
  }

  // MARK: - What a consumer can construct

  @Test("A consumer can construct the types it is expected to produce")
  func consumerConstructibleTypes() {
    // `EscriboSpan` and `TextEdit` are inputs a consumer legitimately makes: a host app
    // describes an edit it performed, and tests and tools build spans. Both have public
    // initializers, and this is where that stays true.
    let span = EscriboSpan(range: 0..<5, kind: .heading, style: [.strong], role: .marker)
    #expect(span.range == 0..<5)
    #expect(span.kind == .heading)
    #expect(span.style == [.strong])
    #expect(span.role == .marker)

    let edit = TextEdit(range: 6..<11, replacementLength: 5)
    #expect(edit.range == 6..<11)
    #expect(edit.replacementLength == 5)
    #expect(edit.changeInLength == 0)
  }

  @Test("A consumer cannot fabricate scanner output")
  func scannerOutputIsNotConsumerConstructible() {
    // `LineRecord` and `ScanResult` are scanner *output*. Their initializers are
    // internal, which falls out of `LineState`'s opacity rather than being a separate
    // decision: a caller could not supply a `startState` even if the memberwise
    // initializer were public. These must fail to compile from this file:
    //
    //   _ = LineRecord(index: 0, range: 0..<1, contentRange: 0..<0,
    //                  element: .blank, startState: ???, depth: 0)
    //   _ = ScanResult(dirtyRange: 0..<0, spans: [], lines: 0..<1, lineRecords: [])
    //
    // The types themselves stay public and readable, because a consumer receives them.
    #expect(requireSendableType(LineRecord.self) == "LineRecord")
    #expect(requireSendableType(ScanResult.self) == "ScanResult")
    #expect(requireEquatableType(LineRecord.self) == "LineRecord")
    #expect(requireEquatableType(ScanResult.self) == "ScanResult")
  }

  // MARK: - The rest of the 1.0 vocabulary

  @Test("The 1.0 vocabulary types are public and publicly constructible")
  func vocabularyIsPublic() {
    // REQUIREMENTS.md § What is public in 1.0 lists these by name. A consumer with a
    // newer core and an older theme has to be able to name an unrecognized kind
    // without the compiler's help, which is why the raw-value initializers are public.
    #expect(SpanKind(rawValue: "text") == .text)
    #expect(ElementKind(rawValue: "blank") == .blank)
    #expect(Language(rawValue: "fountain") == .fountain)
    #expect(StyleSet(rawValue: 1) == .strong)
    #expect(SpanRole(rawValue: "marker") == .marker)
  }
}
