/// The multi-line grammar state a line begins in — the convergence key.
///
/// **This type is public but opaque.** It has no public cases, no public properties,
/// and no public initializer. It appears in the API at all only because
/// ``LineRecord`` carries it; a caller's entire legitimate use is comparing two of
/// them. Exposing its shape would freeze the scanner's internals at 1.0 and turn every
/// convergence improvement into a breaking change, so the shape stays inside
/// `EscriboCore` where it can keep changing.
///
/// `Equatable` is the one conformance that *must* be public: the incremental scanner
/// stops rescanning at the first line whose recomputed start state equals the state
/// already recorded there, and a consumer holding two ``LineRecord`` values has to be
/// able to make the same comparison. That equality is real, total equality — never an
/// approximation, never a fast path. A state that omits one field converges early and
/// produces exactly the class of bug the incremental-equals-full gate test exists to
/// catch, which is why this type is deliberately cheap to extend: adding a field is an
/// internal change with no API consequence.
///
/// Fields arrive as the grammars that need them do — in-fence, in-boneyard,
/// in-dialogue-block, in-frontmatter, and the inner Fountain state of a `fountain`
/// fence. They are added here as `internal` stored properties; `EscriboCore` reads and
/// writes them freely, and nothing outside can see that they exist.
///
/// Deliberately **not** `Hashable`: `hashValue` would be a public member, and the
/// scanner compares states rather than keying anything by them.
public struct LineState: Equatable, Sendable {

  /// The multi-line construct open at the start of this line, as a **grammar-defined
  /// tag**. Zero means nothing is open.
  ///
  /// The scanner never interprets this value; it only compares it, which is the entire
  /// contract a convergence key has to satisfy. Ownership of the meaning sits with the
  /// grammar precisely so that adding a construct — a fence, a boneyard, a frontmatter
  /// block — is a change inside one grammar rather than a change to the type every
  /// grammar shares.
  ///
  /// A scalar rather than a stack or a set on purpose: one `LineState` is stored per
  /// line for the whole document, so a field that allocates would put one allocation per
  /// line on the cheapest thing the scanner does. When a grammar needs richer state than
  /// a tag — a fence's marker character and length, an inner Fountain state inside a
  /// `fountain` fence — it adds its own `internal` stored property here rather than
  /// encoding it into this one. That is a source change with no API consequence, which
  /// is the whole reason this type is opaque.
  var openConstruct: UInt16

  /// Creates the state a line begins in.
  ///
  /// `internal` on purpose — see the type's documentation. External code obtains a
  /// `LineState` only by reading ``LineRecord/startState`` from a scan.
  init(openConstruct: UInt16 = 0) {
    self.openConstruct = openConstruct
  }

  /// The state the first line of a document begins in: nothing open, nothing carried.
  ///
  /// Every full scan starts here, and a scan that converges has proved that some later
  /// line's state matches what a scan from here would have produced.
  static let documentStart = LineState()
}
