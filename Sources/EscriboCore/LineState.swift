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

  /// The delimiter character of the fenced code block open at the start of this line —
  /// `` ` `` or `~` as a UTF-16 code unit. Zero when no fence is open.
  ///
  /// A fence closes only with the character it opened with, so this has to be carried:
  /// a `~~~` inside a ```` ``` ```` block is code, not a closing fence. It lives here
  /// rather than being folded into ``openConstruct`` because ``openConstruct`` is a
  /// *tag* the scanner only ever compares, and packing a character into it would make a
  /// grammar's private encoding the shared type's business.
  var fenceCharacter: UInt16

  /// The length of the opening fence's delimiter run.
  ///
  /// CommonMark requires a closing fence to be **at least as long** as the one that
  /// opened the block, so the opening length is state in the same sense the character
  /// is. Carried as a `UInt16` for the same reason ``openConstruct`` is a scalar: one
  /// `LineState` is stored per line for the whole document.
  var fenceLength: UInt16

  /// Whether the line **before** this one had anything on it but whitespace.
  ///
  /// Fountain's two *natural* — unforced — block elements are recognized only at the
  /// start of a block: `INT. HOUSE` is a scene heading and `CUT TO:` a transition when a
  /// blank line precedes them, and action when one does not. That is backward-looking
  /// information, so it is state rather than lookahead, and it belongs here for exactly
  /// the reason the fence character does: a grammar that recomputed it per line could not
  /// converge, and a grammar that computed it and failed to carry it would converge one
  /// line early.
  ///
  /// Phrased as "follows a non-blank line" rather than "is at a block boundary" so that
  /// the default — ``documentStart`` — is correct without an exception: the first line of
  /// a document follows nothing, so it opens a block, and a scene heading may sit on it.
  ///
  /// The Markdown grammar neither reads nor writes this, and CommonMark's own
  /// blank-line rules are decided from the line's own text, so leaving it `false`
  /// throughout a Markdown document changes nothing there.
  var followsNonBlankLine: Bool

  /// The Markdown block-container context this line begins in: whether a paragraph is
  /// open above it, and which list items enclose it.
  ///
  /// Two scalars inside ``MarkdownBlockState``, for the reason ``openConstruct`` is a
  /// scalar: one `LineState` is stored per line for the whole document, so a list stack
  /// held in an array would cost one allocation per line. It sits here rather than being
  /// folded into ``openConstruct`` because ``openConstruct`` is a *tag* the scanner only
  /// ever compares, and a list nesting stack is not a tag.
  ///
  /// `MarkdownGrammar`'s alone. Every other grammar leaves it at its default, where it is
  /// a `Bool` and a `UInt64` of zeroes that compare equal to themselves forever.
  var markdownBlocks: MarkdownBlockState

  /// Creates the state a line begins in.
  ///
  /// `internal` on purpose — see the type's documentation. External code obtains a
  /// `LineState` only by reading ``LineRecord/startState`` from a scan.
  init(
    openConstruct: UInt16 = 0,
    fenceCharacter: UInt16 = 0,
    fenceLength: UInt16 = 0,
    followsNonBlankLine: Bool = false,
    markdownBlocks: MarkdownBlockState = MarkdownBlockState()
  ) {
    self.openConstruct = openConstruct
    self.fenceCharacter = fenceCharacter
    self.fenceLength = fenceLength
    self.followsNonBlankLine = followsNonBlankLine
    self.markdownBlocks = markdownBlocks
  }

  /// The state the first line of a document begins in: nothing open, nothing carried.
  ///
  /// Every full scan starts here, and a scan that converges has proved that some later
  /// line's state matches what a scan from here would have produced.
  static let documentStart = LineState()
}
