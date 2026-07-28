/// The grammar that recognizes nothing: every line is one ``SpanKind/text`` span.
///
/// It exists so that dispatch is **total**. A ``Language`` with no grammar behind it yet
/// — or one a consumer invented with `Language(rawValue:)` against a newer core than the
/// one it is linked to — has to scan into a well-formed ``ScanResult`` rather than trap,
/// because scanning never fails (REQUIREMENTS.md § Concurrency and failure). "Degrade to
/// text" needs something to degrade *to*, and this is it.
///
/// Stateless and lookahead-free, so it is also the cheapest possible exercise of the
/// convergence engine: a one-character edit rescans one line.
struct TextGrammar: LineGrammar {
  var lookahead: Int { 0 }

  func scanLine(_ window: LineWindow, state: LineState) -> LineScan {
    let line = window.current
    return LineScan(
      spans: line.contentRange.isEmpty
        ? [] : [EscriboSpan(range: line.contentRange, kind: .text)],
      element: line.isEmpty ? .blank : .paragraph,
      endState: state
    )
  }
}
