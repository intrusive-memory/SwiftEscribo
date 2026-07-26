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

  /// Whether this line begins **inside an open Fountain dialogue block**.
  ///
  /// A dialogue block opens on a character cue and runs until a blank line or until a line
  /// that is neither dialogue, a parenthetical, nor a lyric. Everything non-blank inside
  /// one is dialogue, which is why this has to be state: `Hello there.` is action at the
  /// top of a page and dialogue three lines under `BOB`, and its own text says nothing
  /// about which.
  ///
  /// A plain `Bool`, and deliberately not a tag folded into ``openConstruct``: the two are
  /// independent — a document can be inside a `fountain` fence *and* inside a dialogue
  /// block — and packing them together would make one grammar's private encoding the
  /// shared type's business. It is declared here, in this file, rather than beside the
  /// grammar that reads it, because a field on `LineState` whose type lives in a grammar
  /// file makes this file uncompilable on its own; a `Bool` needs nothing at all.
  ///
  /// `FountainGrammar`'s alone. Every other grammar leaves it `false`, where it compares
  /// equal to itself forever and costs convergence nothing.
  var inDialogueBlock: Bool

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

  /// Where this line sits with respect to a Fountain **title page**.
  ///
  /// Three values rather than a `Bool`, and the third one is the whole reason this field
  /// exists: a title page may begin **only on the document's first line**, and "this is
  /// the first line" is not otherwise derivable from a state. ``followsNonBlankLine`` is
  /// `false` on line 0 *and* after every blank line, so a grammar keying the title page
  /// off it would reopen one in the middle of a screenplay. ``TitlePageRegion/documentStart``
  /// is the default, so the initial state is correct without an exception, and every line
  /// a Fountain scan touches overwrites it with ``TitlePageRegion/open`` or
  /// ``TitlePageRegion/closed`` — which is what makes it reachable exactly once.
  ///
  /// `FountainGrammar`'s alone. Every other grammar leaves it at
  /// ``TitlePageRegion/documentStart``, where it compares equal to itself forever and
  /// costs convergence nothing.
  var titlePage: TitlePageRegion

  /// The Fountain grammar's state **inside** a Markdown fence tagged `fountain`.
  ///
  /// This field exists because ``openConstruct`` is one scalar and a nested scan needs two
  /// constructs open at once. Inside ```` ```fountain ```` the outer construct is *a fence
  /// is open* — ``MarkdownGrammar/fountainFenceTag`` — and the inner construct may
  /// independently be *a boneyard is open* or *a note is open*. Those are not alternatives:
  /// a line can be inside both, and a state that can only say one of them is a state that
  /// **converges early inside the block**. That is the exact defect the incremental design
  /// exists to prevent, and no encoding of two independent facts into one tag avoids it —
  /// packing them would only move the collision from the value into the decoder, and would
  /// hand one grammar's private encoding to another grammar as a shared obligation.
  ///
  /// So: a second field, holding the *whole* Fountain half of a state rather than only its
  /// tag. A dialogue block, the follows-a-non-blank-line bit, and the title-page region are
  /// as much Fountain state as the region tag is, and the fence must carry all four or the
  /// first line of the fence would be the only one scanned as a screenplay.
  ///
  /// Nesting is **one level and non-recursive** (REQUIREMENTS.md § Fountain-in-Markdown):
  /// Markdown may host Fountain, Fountain hosts nothing, and Fountain has no fence syntax
  /// to host anything with. That is what lets this be a fixed-size value rather than a
  /// boxed `LineState` — a self-referential state would need an allocation, and there is
  /// one `LineState` per line for the whole document.
  ///
  /// `MarkdownGrammar`'s alone, and only inside a `fountain` fence. Everywhere else it sits
  /// at its default, where it compares equal to itself forever and costs convergence
  /// nothing.
  var nestedFountain: NestedFountainState

  /// Creates the state a line begins in.
  ///
  /// `internal` on purpose — see the type's documentation. External code obtains a
  /// `LineState` only by reading ``LineRecord/startState`` from a scan.
  init(
    openConstruct: UInt16 = 0,
    fenceCharacter: UInt16 = 0,
    fenceLength: UInt16 = 0,
    followsNonBlankLine: Bool = false,
    inDialogueBlock: Bool = false,
    markdownBlocks: MarkdownBlockState = MarkdownBlockState(),
    titlePage: TitlePageRegion = .documentStart,
    nestedFountain: NestedFountainState = NestedFountainState()
  ) {
    self.openConstruct = openConstruct
    self.fenceCharacter = fenceCharacter
    self.fenceLength = fenceLength
    self.followsNonBlankLine = followsNonBlankLine
    self.inDialogueBlock = inDialogueBlock
    self.markdownBlocks = markdownBlocks
    self.titlePage = titlePage
    self.nestedFountain = nestedFountain
  }

  /// The state the first line of a document begins in: nothing open, nothing carried.
  ///
  /// Every full scan starts here, and a scan that converges has proved that some later
  /// line's state matches what a scan from here would have produced.
  static let documentStart = LineState()
}

/// Where a line sits with respect to a Fountain title page — the leading `Key: Value`
/// region a screenplay may open with.
///
/// Declared **here**, in `LineState.swift`, rather than beside the grammar that reads it,
/// for the reason ``LineState/inDialogueBlock`` is a `Bool` and not a grammar type: a
/// stored property whose type lives in a grammar file makes this file uncompilable on its
/// own. A `UInt8`-backed enum with no dependencies needs nothing at all.
///
/// Raw-value backed so the field costs one byte in a type that is stored once per line for
/// the whole document, and `Equatable` because ``LineState``'s equality — the convergence
/// key — is total and every field has to participate in it.
enum TitlePageRegion: UInt8, Equatable, Sendable {

  /// Nothing has been scanned yet: this is the document's first line, and it is the only
  /// line on which a title page may begin.
  ///
  /// The default, so ``LineState/documentStart`` is right without a special case. It is
  /// also unreachable after line 0 of a Fountain scan, because every line's end state is
  /// assigned either ``open`` or ``closed``.
  case documentStart = 0

  /// The line begins **inside** an open title page. Every non-blank line here is a
  /// title-page key or a continuation of the previous key's value, and no other Fountain
  /// element is recognized.
  case open = 1

  /// The title page is over — or there never was one. Terminal: nothing reopens it.
  case closed = 2
}

/// Every field of a ``LineState`` that the Fountain grammar reads or writes, as one value —
/// the *inner* half of a nested scan.
///
/// Declared **here**, in `LineState.swift`, for the reason ``TitlePageRegion`` is: a stored
/// property whose type lives in a grammar file makes this file uncompilable on its own. It
/// is also the right place on the merits — this is the shape of a `LineState` seen from
/// inside a fence, and nothing about it belongs to either grammar exclusively.
///
/// Four fields and not one tag. The Fountain grammar's multi-line story is a region tag, a
/// dialogue block, a block-boundary bit, and a title-page region, and every one of them
/// decides how the *next* line scans. A nested state that carried only the region tag would
/// scan the second line of a fenced dialogue block as action, and a nested state that
/// carried nothing at all — "we are in a fence" and no more — would converge on the fence's
/// second line and repaint nothing after it.
///
/// All scalars, so this costs nine bytes inside a value stored once per line and allocates
/// nothing. There is deliberately no nested `NestedFountainState` inside it: nesting is one
/// level (``LineState/nestedFountain``), so the type does not need to be recursive and
/// therefore does not need to be boxed.
struct NestedFountainState: Equatable, Sendable {

  /// The Fountain region open at the start of this line — ``FountainGrammar/noteTag``,
  /// ``FountainGrammar/boneyardTag``, or zero. The *inner* construct, independent of the
  /// outer fence.
  var openConstruct: UInt16 = 0

  /// ``LineState/followsNonBlankLine``, inside the fence.
  var followsNonBlankLine: Bool = false

  /// ``LineState/inDialogueBlock``, inside the fence.
  var inDialogueBlock: Bool = false

  /// ``LineState/titlePage``, inside the fence.
  ///
  /// Defaults to ``TitlePageRegion/documentStart``, which is what makes the **first line of
  /// the fence** the one line a nested title page may begin on — the same rule a standalone
  /// screenplay gets from line zero, arrived at by the same route.
  var titlePage: TitlePageRegion = .documentStart
}

extension LineState {

  /// The state the Fountain grammar is handed for a line inside a `fountain` fence.
  ///
  /// Every field the Fountain grammar does not own is at its default, so the nested scan
  /// cannot see — and cannot be perturbed by — the enclosing Markdown document's fence
  /// character, list stack, or open paragraph.
  static func nested(_ inner: NestedFountainState) -> LineState {
    LineState(
      openConstruct: inner.openConstruct,
      followsNonBlankLine: inner.followsNonBlankLine,
      inDialogueBlock: inner.inDialogueBlock,
      titlePage: inner.titlePage)
  }

  /// The Fountain half of this state — what a nested scan's end state contributes back to
  /// the enclosing document's state.
  ///
  /// The inverse of ``nested(_:)``, and it must stay exactly that: a field this property
  /// forgets is a field the fence stops carrying, and a fence that stops carrying the
  /// dialogue bit scans every line after a cue as action.
  var fountainHalf: NestedFountainState {
    NestedFountainState(
      openConstruct: openConstruct,
      followsNonBlankLine: followsNonBlankLine,
      inDialogueBlock: inDialogueBlock,
      titlePage: titlePage)
  }
}
