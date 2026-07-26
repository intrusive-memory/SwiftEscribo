import Testing

@testable import EscriboCore

/// Accepts anything `Sendable`. Passing a value here is a compile-time proof of
/// conformance — under Swift 6 language mode a non-`Sendable` argument is an error,
/// not a warning, so the assertion is the call itself.
private func requireSendable<T: Sendable>(_ value: T) -> T { value }

/// Accepts anything `Equatable`, and exercises the conformance so it is not merely
/// declared.
private func requireEquatable<T: Equatable>(_ lhs: T, _ rhs: T) -> Bool { lhs == rhs }

/// The scanner→editor seam. These types are compared wholesale by the
/// incremental-equals-full gate test, so every field must participate in `==` and
/// every one of them must cross an isolation boundary — hence the conformance proofs
/// below rather than a bare `: Equatable, Sendable` in the declaration and nothing
/// checking it.
@Suite("Span and record model")
struct SpanModelTests {

  // MARK: - Fixtures

  private static let span = EscriboSpan(
    range: 0..<3,
    kind: .heading,
    style: [.strong],
    role: .marker
  )

  private static let record = LineRecord(
    index: 0,
    range: 0..<12,
    contentRange: 3..<11,
    element: .heading,
    startState: .documentStart,
    depth: 1
  )

  private static let result = ScanResult(
    dirtyRange: 0..<12,
    spans: [span],
    lines: 0..<1,
    lineRecords: [record]
  )

  private static let edit = TextEdit(range: 6..<11, replacementLength: 5)

  // MARK: - Conformance

  @Test("Every seam type is Sendable")
  func seamTypesAreSendable() {
    // The scanner is synchronous and single-threaded, but its results are held by the
    // editor across the main actor boundary. A non-`Sendable` leg here would be a
    // compile error at the first real call site rather than at the definition, which
    // is far too late to change the shape.
    #expect(requireSendable(Self.span) == Self.span)
    #expect(requireSendable(Self.record) == Self.record)
    #expect(requireSendable(Self.result) == Self.result)
    #expect(requireSendable(Self.edit) == Self.edit)
    #expect(requireSendable(LineState.documentStart) == LineState.documentStart)
  }

  @Test("Every seam type is Equatable")
  func seamTypesAreEquatable() {
    #expect(requireEquatable(Self.span, Self.span))
    #expect(requireEquatable(Self.record, Self.record))
    #expect(requireEquatable(Self.result, Self.result))
    #expect(requireEquatable(Self.edit, Self.edit))
    #expect(requireEquatable(LineState.documentStart, LineState.documentStart))
  }

  // MARK: - Field wiring

  @Test("A span stores exactly what it was given")
  func spanStoresItsFields() {
    #expect(Self.span.range == 0..<3)
    #expect(Self.span.kind == .heading)
    #expect(Self.span.style == [.strong])
    #expect(Self.span.role == .marker)
  }

  @Test("A span defaults to unstyled content")
  func spanDefaults() {
    // A run the grammar recognized nothing special about is content, not a marker, and
    // carries no emphasis. Making that the default is what keeps the tiling `.text`
    // spans — the majority of every scan — cheap to write and impossible to get wrong.
    let plain = EscriboSpan(range: 0..<4, kind: .text)
    #expect(plain.style == [])
    #expect(plain.role == .content)
    #expect(plain == EscriboSpan(range: 0..<4, kind: .text, style: [], role: .content))
  }

  @Test("A line record stores exactly what it was given")
  func recordStoresItsFields() {
    #expect(Self.record.index == 0)
    #expect(Self.record.range == 0..<12)
    #expect(Self.record.contentRange == 3..<11)
    #expect(Self.record.element == .heading)
    #expect(Self.record.depth == 1)
    #expect(Self.record.startState == .documentStart)
  }

  @Test("A scan result stores exactly what it was given")
  func resultStoresItsFields() {
    #expect(Self.result.dirtyRange == 0..<12)
    #expect(Self.result.spans == [Self.span])
    #expect(Self.result.lines == 0..<1)
    #expect(Self.result.lineRecords == [Self.record])
  }

  // MARK: - Every field participates in equality

  @Test("Changing any span field breaks equality")
  func everySpanFieldParticipatesInEquality() {
    // The gate test compares whole span arrays. A field silently omitted from `==`
    // would make `incrementalScan == fullScan` pass while the two disagreed, which is
    // the precise failure the gate exists to prevent.
    #expect(Self.span != EscriboSpan(range: 0..<4, kind: .heading, style: [.strong], role: .marker))
    #expect(Self.span != EscriboSpan(range: 0..<3, kind: .text, style: [.strong], role: .marker))
    #expect(Self.span != EscriboSpan(range: 0..<3, kind: .heading, style: [], role: .marker))
    #expect(
      Self.span != EscriboSpan(range: 0..<3, kind: .heading, style: [.strong], role: .content))
  }

  @Test("Changing any line record field breaks equality")
  func everyRecordFieldParticipatesInEquality() {
    func varying(
      index: Int = 0,
      range: Range<Int> = 0..<12,
      contentRange: Range<Int> = 3..<11,
      element: ElementKind = .heading,
      depth: Int = 1
    ) -> LineRecord {
      LineRecord(
        index: index,
        range: range,
        contentRange: contentRange,
        element: element,
        startState: .documentStart,
        depth: depth
      )
    }

    #expect(Self.record != varying(index: 1))
    #expect(Self.record != varying(range: 0..<13))
    #expect(Self.record != varying(contentRange: 3..<12))
    #expect(Self.record != varying(element: .paragraph))
    #expect(Self.record != varying(depth: 2))
  }

  @Test("Changing any scan result field breaks equality")
  func everyResultFieldParticipatesInEquality() {
    #expect(
      Self.result
        != ScanResult(
          dirtyRange: 0..<13, spans: [Self.span], lines: 0..<1, lineRecords: [Self.record]))
    #expect(
      Self.result
        != ScanResult(dirtyRange: 0..<12, spans: [], lines: 0..<1, lineRecords: [Self.record]))
    #expect(
      Self.result
        != ScanResult(
          dirtyRange: 0..<12, spans: [Self.span], lines: 0..<2, lineRecords: [Self.record]))
    #expect(
      Self.result
        != ScanResult(dirtyRange: 0..<12, spans: [Self.span], lines: 0..<1, lineRecords: []))
  }

  // MARK: - LineState

  @Test("Line states compare, and comparing is the whole contract")
  func lineStatesCompare() {
    // Sortie 4's convergence engine stops rescanning the moment a recomputed start
    // state equals the one already recorded. That comparison is the only operation the
    // type owes anyone, and it must be real equality rather than an approximation: a
    // state that compares equal when it is not converges early and mis-scans the rest
    // of the document.
    #expect(LineState.documentStart == LineState.documentStart)
    #expect(LineState() == LineState.documentStart)
    #expect(Self.record.startState == LineState.documentStart)
  }

  // MARK: - TextEdit

  @Test("An edit reads in old-text coordinates")
  func editUsesOldTextCoordinates() {
    // `"Hello world"`, selecting `world` (old offsets 6..<11) and typing `there`.
    // If this were ever read as *new*-text coordinates the range would be 6..<11 only
    // by coincidence of equal lengths — which is exactly why the convention is pinned
    // by the asymmetric cases below rather than by this one.
    #expect(Self.edit.range == 6..<11)
    #expect(Self.edit.replacementLength == 5)
    #expect(Self.edit.changeInLength == 0)
  }

  @Test(
    "changeInLength is replacementLength minus the old range's length",
    arguments: [
      // (range, replacementLength, changeInLength) against `"Hello world"`.
      (6..<11, 5, 0),  // replace `world` with `there`
      (5..<11, 0, -6),  // delete ` world`
      (11..<11, 1, 1),  // append `!` — an empty range in OLD coordinates
      (0..<11, 1, -10),  // type `x` over the whole document
      (0..<0, 3, 3),  // insert `abc` at the head
    ]
  )
  func changeInLength(range: Range<Int>, replacementLength: Int, expected: Int) {
    #expect(TextEdit(range: range, replacementLength: replacementLength).changeInLength == expected)
  }

  @Test("An insertion is an empty old-text range, not a position")
  func insertionIsAnEmptyRange() {
    // Stated as its own case because "insert at 11" and "replace 11..<11" are the same
    // edit, while "insert at 11" and "replace 11..<12" are not. Every later sortie that
    // translates an edit — convergence, NSTextStorage bridging, external replacement —
    // has to agree on this or offsets drift by the length of the insertion.
    let insertion = TextEdit(range: 11..<11, replacementLength: 1)
    #expect(insertion.range.isEmpty)
    #expect(insertion.changeInLength == 1)
    #expect(insertion != TextEdit(range: 11..<12, replacementLength: 1))
  }

  @Test("Changing any edit field breaks equality")
  func everyEditFieldParticipatesInEquality() {
    #expect(Self.edit != TextEdit(range: 6..<10, replacementLength: 5))
    #expect(Self.edit != TextEdit(range: 6..<11, replacementLength: 4))
  }
}
