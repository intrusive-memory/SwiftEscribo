/// `!`, `#`, `.`, `:`, `=`, `>`, `@`, `~`, `^`, `(`, `)`, a space, a tab, `\n`, `\r` — the
/// only code units this file compares against.
///
/// Spelled as constants for the reason ``FountainGrammar``'s are: `EscriboCore` reads
/// documents as UTF-16 code units, and a literal `0x2E` in the middle of a branch is
/// unreadable. There is no regex here and there never will be — the charter (AGENTS.md)
/// forbids one in the scanners, and a writer that re-lexed with one would reintroduce
/// exactly what this package exists to replace.
private let exclamationMark: UInt16 = 0x21
private let numberSign: UInt16 = 0x23
private let period: UInt16 = 0x2E
private let equalsSign: UInt16 = 0x3D
private let greaterThan: UInt16 = 0x3E
private let lessThan: UInt16 = 0x3C
private let atSign: UInt16 = 0x40
private let colon: UInt16 = 0x3A
private let tilde: UInt16 = 0x7E
private let caret: UInt16 = 0x5E
private let space: UInt16 = 0x20
private let tab: UInt16 = 0x09
private let lineFeed: UInt16 = 0x0A
private let carriageReturn: UInt16 = 0x0D

/// Whether `unit` is a space or a tab — the same two characters ``FountainGrammar``
/// treats as whitespace, and deliberately not one more. The writer's idea of what it may
/// trim has to match the scanner's idea of what it trimmed, or a round trip loses a
/// character the scanner was keeping.
private func isSpaceOrTab(_ unit: UInt16) -> Bool { unit == space || unit == tab }

/// The code units that begin a Fountain block element when they are the **first** unit of
/// a line: `=` (page break, synopsis), `#` (section), `~` (lyric), `!` (forced action),
/// `.` (forced scene heading), `>` (centered, forced transition), `@` (forced cue).
///
/// Used in exactly one place — the dialogue rule below — and it is the one piece of
/// grammar knowledge this file duplicates. See ``FountainWriter`` § "The one thing the
/// writer must not do" for why the duplication is deliberate and why the alternative
/// (re-running the grammar inside the writer) is worse.
private let blockMarkerStarts: [UInt16] = [
  equalsSign, numberSign, tilde, exclamationMark, period, greaterThan, atSign,
]

/// Writes canonical Fountain from the line records a scan produced.
///
/// ## What "canonical" means here, and what it does not
///
/// The writer **normalizes**. `=====` comes back as `===`, `#   ACT ONE` as `# ACT ONE`,
/// `BOB   (V.O.)   ^` as `BOB (V.O.) ^`, and a line of trailing spaces after a scene
/// heading is gone. That is the point of having a writer at all: a document that has been
/// through it is spelled one way. It is also why "write a document's parse back out and
/// get the original bytes" is **not** a property of this type and must never be asserted
/// anywhere — it fails on every non-canonical input, which is most real input.
///
/// The correct formulation is that this writer is a **fixed point**: let `y = write(x)`,
/// then `write(y) == y`, compared as text. One pass moves a document to its canonical
/// spelling and every later pass leaves it exactly there (REQUIREMENTS.md § Verification 4).
/// Two nearby formulations are wrong and are asserted nowhere in this package. `write(x)
/// == x` is wrong because writing normalizes. `parse(write(x)) == parse(x)` compared as
/// records is *also* wrong, and less obviously: normalization shortens lines, so every
/// ``LineRecord/range`` after the first normalized line shifts, and record equality then
/// fails for a reason that has nothing to do with data loss. A parse-level comparison has
/// to be over **classifications** — `(element, depth)` per line — which is what
/// `FountainWriterCorpusTests` compares.
///
/// ## What it preserves, and how
///
/// Three things survive normalization untouched, because losing any of them would change
/// what the document *says* rather than how it is spelled:
///
/// 1. **Line terminators, exactly as recorded.** `\r\n` is written back as `\r\n`, a lone
///    `\r` as a lone `\r`, and a document that ended without one still ends without one.
///    The terminator is copied out of the source bytes at the tail of
///    ``LineRecord/range`` — never synthesized, never normalized (REQUIREMENTS.md § Line
///    termination). A writer that emitted `\n` everywhere would make the idempotence test
///    pass for the wrong reason on a CRLF document.
/// 2. **Every forced-element marker.** `.INT. HOUSE` keeps its period, `!action` its bang,
///    `@McAvoy` its at-sign, `>` its angle bracket. The marker is not stored in the record
///    as a flag — it is the gap between `range.lowerBound` and `contentRange.lowerBound`,
///    which is precisely the lossless-record bargain of REQUIREMENTS.md Architecture §9.
///    The writer reads the marker back off the source and re-emits it, so a forced element
///    stays forced and a natural one stays natural.
/// 3. **The dual-dialogue caret**, and the cue extension it sits after. Neither is inside a
///    cue's content range — a cue's content is the character *name* alone
///    (``ElementKind/character``) — so both are re-lexed out of the tail of the line and
///    re-emitted with canonical spacing.
///
/// Notes and boneyard are written **verbatim**, byte for byte, including any GLOSA
/// directive inside a note. See § "Verbatim" below.
///
/// The title page is normalized like everything else — `Title:   Big Fish` comes back as
/// `Title: Big Fish` — with one thing held rigid: the **key** is copied out of the source
/// byte for byte and the keys keep their original order. There is no key list in this
/// package and there must never be one; `verbsCovered` and `Abstract` are as much keys as
/// `Title` is (REQUIREMENTS.md § Fountain 2), so a writer that recognized keys would
/// silently drop this org's own documents' metadata. See § "The title page" below.
///
/// ## The one thing the writer must not do
///
/// It must not turn one element into another. The risk is concrete and it has exactly one
/// shape: inside a dialogue block a line's leading indent is not meaningful, so the
/// canonical form drops it — but `  ~la la la` inside a dialogue block is **dialogue**
/// (``FountainGrammar`` requires a lyric's `~` at the first code unit), and de-indenting it
/// would promote it to a lyric. So a dialogue line whose content begins with a block
/// marker keeps its indent. That is the one place this file knows anything about the
/// grammar, and the duplication is deliberate: the alternative is running the grammar
/// inside the writer and iterating until the classification stops changing, which is a
/// fixed-point loop over a document on every save.
///
/// ## Totality
///
/// No `throws`, no optional, no `precondition`. An element this writer does not recognize
/// — a Markdown record handed to it by mistake, a kind added in a later version — is
/// written verbatim from the source, which is always a defensible answer and never a
/// crash (REQUIREMENTS.md § Unknown kinds fall back, never fail).
public struct FountainWriter {

  /// Creates a writer. It holds no state and one instance may write any number of
  /// documents.
  public init() {}

  /// Writes `records` back out as Fountain, reading their text from `source`.
  ///
  /// - Parameters:
  ///   - records: The records of the document, in ascending line order — normally the
  ///     whole of ``ScanResult/lineRecords`` from a ``EscriboScanner/fullScan(_:)``.
  ///     Passing a subrange writes that subrange, which is meaningful and is not checked:
  ///     the writer has no way to tell "the caller wants three lines" from "the caller
  ///     made a mistake", and trapping on the second would take the first away.
  ///   - source: The document the records were scanned from. Records index it, so passing
  ///     a *different* document produces garbage rather than an error — the same bargain
  ///     every offset-carrying API in this package makes.
  /// - Returns: The written document.
  public func write(_ records: [LineRecord], from source: some UTF16TextSource) -> String {
    var out: [UInt16] = []
    var buffer = UTF16LineBuffer()
    let limit = source.utf16Count

    for record in records {
      // Clamped rather than trusted. A record from a stale scan can outrun a shortened
      // document, and reading past the end of an `NSTextStorage` is a crash, not a wrong
      // answer.
      let lower = min(max(record.range.lowerBound, 0), limit)
      let upper = min(max(record.range.upperBound, lower), limit)
      guard lower < upper else { continue }
      let lineRange = lower..<upper

      buffer.withCodeUnits(of: lineRange, in: source) { units in
        let terminator = terminatorLength(of: units)
        let lineEnd = units.count - terminator
        let content = clamped(record.contentRange, within: lineRange, lineEnd: lineEnd)
        emit(record, units: units, lineEnd: lineEnd, content: content, into: &out)
        for offset in lineEnd..<units.count {
          out.append(units[offset])
        }
      }
    }

    return String(decoding: out, as: UTF16.self)
  }

  // MARK: - The element table

  /// Writes one line's text — everything but its terminator.
  ///
  /// One `switch`, one canonical spelling per element, and a verbatim fallthrough for
  /// everything this writer does not own. Ordered as ``FountainGrammar`` orders its rules
  /// so the two files read side by side.
  ///
  /// - Parameters:
  ///   - units: The line's code units, terminator included.
  ///   - lineEnd: Where the terminator begins, as an offset into `units`.
  ///   - content: The record's content range, as offsets into `units`.
  private func emit(
    _ record: LineRecord,
    units: UnsafeBufferPointer<UInt16>,
    lineEnd: Int,
    content: Range<Int>,
    into out: inout [UInt16]
  ) {
    switch record.element {

    // A blank line is blank. The whitespace a writer left on it is not "two trailing
    // spaces preserve the line" — this grammar does not honor that convention
    // (``FountainGrammar`` deviation 2) — so keeping it would preserve a character that
    // means nothing to anyone downstream.
    case .blank:
      return

    // Pure delimiters. `=====` and `===` are the same page break, and the canonical
    // spelling is the shortest one the grammar accepts.
    case .pageBreak:
      out.append(contentsOf: [equalsSign, equalsSign, equalsSign])

    case .section:
      // `depth` is the number of `#` the scanner counted, and it is the only place the
      // count survives — the marker span is not on the record. A depth of zero would mean
      // a section with no marker, which cannot be scanned and must not be written.
      for _ in 0..<max(record.depth, 1) { out.append(numberSign) }
      appendSpaced(content, of: units, into: &out)

    case .synopsis:
      out.append(equalsSign)
      appendSpaced(content, of: units, into: &out)

    // The marker abuts its text: `~Willy Wonka`, never `~ Willy Wonka`.
    case .lyrics:
      out.append(tilde)
      append(content, of: units, into: &out)

    // The period, when there was one, then the heading. `.HOUSE` stays forced; `INT. HOUSE`
    // stays natural. Nothing else distinguishes the two records.
    case .sceneHeading:
      if marker(units, content: content, is: period) { out.append(period) }
      append(content, of: units, into: &out)

    case .transition:
      if marker(units, content: content, is: greaterThan) {
        out.append(greaterThan)
        appendSpaced(content, of: units, into: &out)
      } else {
        append(content, of: units, into: &out)
      }

    // `>CENTERED<`. Both markers are outside the content range, so both are re-emitted;
    // the closing one is not optional, since without it the line is a transition.
    case .centered:
      out.append(greaterThan)
      append(content, of: units, into: &out)
      out.append(lessThan)

    case .character:
      emitCharacterCue(units: units, lineEnd: lineEnd, content: content, into: &out)

    // The parentheses are content, not markers — they print. Only the indent is dropped,
    // and dropping it cannot reclassify the line: a `(…)` line inside a dialogue block is a
    // parenthetical at any indent, including none.
    case .parenthetical:
      append(content, of: units, into: &out)

    case .dialogue:
      emitDialogue(units: units, content: content, into: &out)

    // Action is the one element whose whitespace is what the writer meant
    // (``FountainGrammar``'s `action(_:)`), and a forced action's `!` is a marker outside
    // its content range. Writing the raw line covers both at once and normalizes nothing,
    // which for this element is the canonical answer rather than a shortcut.
    case .action:
      appendRaw(lineEnd: lineEnd, of: units, into: &out)

    // MARK: The title page

    case .titlePageKey:
      emitTitlePageKey(units: units, lineEnd: lineEnd, content: content, into: &out)

    case .titlePageValue:
      emitTitlePageValue(units: units, content: content, into: &out)

    // MARK: Verbatim
    //
    // A note and a boneyard are not screenplay elements — one is commentary layered over a
    // screenplay and the other is text struck out of one — so there is no canonical
    // spelling to normalize toward, and everything inside them (a GLOSA directive, a
    // half-written tag, an unterminated `/*`) is content that must survive untouched.
    case .note, .boneyard:
      appendRaw(lineEnd: lineEnd, of: units, into: &out)

    // A YAML frontmatter region (``FountainGrammar`` deviation 12) is not a screenplay
    // element either — it is another language's document sitting on top of this one — and
    // this writer knows no YAML. Indentation is significant in it, quoting styles are not
    // interchangeable, and a `-` at the head of a line is a sequence entry rather than
    // anything to canonicalize, so **verbatim is the only correct answer** here and is
    // stated explicitly rather than left to the fallthrough below.
    case .frontmatterDelimiter, .frontmatter:
      appendRaw(lineEnd: lineEnd, of: units, into: &out)

    // Every Markdown element, and anything a later version adds. Verbatim is always
    // defensible and is never a crash.
    default:
      appendRaw(lineEnd: lineEnd, of: units, into: &out)
    }
  }

  // MARK: - The dialogue block

  /// `@BOB (V.O.) ^` — marker, name, extension, caret, with one space between each.
  ///
  /// The name is the record's content (``ElementKind/character``); everything else has to
  /// be re-lexed out of the line, because a cue's content range is deliberately narrower
  /// than "the line minus its markers". The tail after the name holds, in order: optional
  /// whitespace, an optional `(…)` extension, optional whitespace, an optional `^`, and
  /// optional whitespace. Peeling it from the right is unambiguous and needs no
  /// bracket matching — the same reasoning ``FountainGrammar``'s `cueLayout` uses.
  private func emitCharacterCue(
    units: UnsafeBufferPointer<UInt16>,
    lineEnd: Int,
    content: Range<Int>,
    into out: inout [UInt16]
  ) {
    if marker(units, content: content, is: atSign) { out.append(atSign) }
    append(content, of: units, into: &out)

    var tailEnd = lineEnd
    while tailEnd > content.upperBound, isSpaceOrTab(units[tailEnd - 1]) {
      tailEnd -= 1
    }

    // One caret, peeled from the right. `^^` is not a Fountain construct and the grammar
    // peels exactly one, so the writer must too or the second one migrates.
    var dual = false
    if tailEnd > content.upperBound, units[tailEnd - 1] == caret {
      dual = true
      tailEnd -= 1
      while tailEnd > content.upperBound, isSpaceOrTab(units[tailEnd - 1]) {
        tailEnd -= 1
      }
    }

    var extensionStart = content.upperBound
    while extensionStart < tailEnd, isSpaceOrTab(units[extensionStart]) {
      extensionStart += 1
    }
    if extensionStart < tailEnd {
      out.append(space)
      for offset in extensionStart..<tailEnd {
        out.append(units[offset])
      }
    }

    if dual {
      out.append(space)
      out.append(caret)
    }
  }

  /// A line of speech, de-indented — unless de-indenting would make it something else.
  ///
  /// The guard is the whole substance of this method and it is not hypothetical:
  /// `  ~la la la` between a cue and the next blank line is dialogue, because
  /// ``FountainGrammar`` requires a lyric's `~` at the first code unit of the line. Emit it
  /// flush left and the next parse calls it a lyric, which is a writer changing what a
  /// document says. Keeping the indent on exactly those lines costs one comparison and
  /// makes the transformation classification-preserving.
  ///
  /// Trailing whitespace is dropped unconditionally: inside a dialogue block every rule
  /// that could fire keys off the line's *first* code unit, so nothing at the right-hand
  /// end can reclassify anything. (The rules that read the line above — natural cues,
  /// natural scene headings, natural transitions — cannot fire inside a block at all: a
  /// dialogue line always follows a non-blank line, since a blank one closes the block.)
  private func emitDialogue(
    units: UnsafeBufferPointer<UInt16>,
    content: Range<Int>,
    into out: inout [UInt16]
  ) {
    if !content.isEmpty, blockMarkerStarts.contains(units[content.lowerBound]) {
      for offset in 0..<content.lowerBound {
        out.append(units[offset])
      }
    }
    append(content, of: units, into: &out)
  }

  // MARK: - The title page

  /// `Key: value` — the key exactly as it was written, one colon, one space, the value.
  ///
  /// ## Why the key is re-lexed rather than read off the record
  ///
  /// ``LineRecord`` carries the **value** as its ``LineRecord/contentRange`` and does not
  /// carry the key at all: the key ships as a ``SpanKind/titlePageKey`` span, and spans are
  /// not an input to this writer (DL-111). Rather than widen the record with a `keyRange`
  /// that would be empty on every line of every document that is not a title page, the key
  /// is recovered the same way ``FountainGrammar`` found it — everything before the line's
  /// **first** colon — which is the same one-place duplication of grammar knowledge that
  /// `blockMarkerStarts` and the cue tail already are. `FountainWriterTitlePageTests`
  /// cross-checks the two routes against each other and against the source bytes on every
  /// title-page line in the corpus, so the duplication cannot drift silently.
  ///
  /// ## What is held rigid
  ///
  /// Everything up to the colon is copied out verbatim: not trimmed, not case-folded, not
  /// checked against any list. `verbsCovered` stays `verbsCovered` and `CONTACT INFO` keeps
  /// its space. What normalizes is only the run of whitespace *between* the colon and the
  /// value, and a value's trailing whitespace, which the scanner already left outside the
  /// content range.
  ///
  /// A key with an empty value is written as the bare `Key:` — no trailing space, which is
  /// what makes a second pass a no-op — and its value line, if it had one, is written
  /// separately by ``emitTitlePageValue(units:content:into:)``. The two records are
  /// deliberately distinguishable and both survive: `EPISODE:` followed by a lone tab is a
  /// key whose value is empty (DL-130), and `REVISION:` with nothing under it is a key with
  /// no value line at all. Both spellings appear in `episode_01.fountain`.
  private func emitTitlePageKey(
    units: UnsafeBufferPointer<UInt16>,
    lineEnd: Int,
    content: Range<Int>,
    into out: inout [UInt16]
  ) {
    // Totality. A record whose line no longer holds a colon — a stale record against an
    // edited document — is written verbatim rather than trapped or dropped.
    guard let colonAt = keyEnd(units, lineEnd: lineEnd) else {
      appendRaw(lineEnd: lineEnd, of: units, into: &out)
      return
    }
    for offset in 0..<colonAt {
      out.append(units[offset])
    }
    out.append(colon)
    appendSpaced(content, of: units, into: &out)
  }

  /// A continuation line: one tab, then the value.
  ///
  /// The indent is **not optional and is not copied** — it is re-emitted as a single tab,
  /// which is what Highland 2 writes and what Fountain's own examples show. Both halves of
  /// that matter:
  ///
  /// * *Not copied*: three spaces and a tab are the same continuation, so normalizing them
  ///   to one spelling is the writer's job.
  /// * *Not optional*: a continuation whose value is empty must still be written as a line
  ///   with something on it. Emitting nothing would produce a genuinely empty line, and an
  ///   empty line **terminates the title page** (``FountainGrammar`` deviation 10a) — every
  ///   key below it would drop out of the region on the next parse. This is the one place
  ///   in this file where writing fewer bytes would change the document's structure rather
  ///   than its spelling.
  ///
  /// De-indenting is not a risk here the way it is inside a dialogue block: a tab-indented
  /// line cannot be read as a key (``FountainGrammar``'s key must start at the first code
  /// unit), so this spelling classifies as a continuation for every possible value.
  private func emitTitlePageValue(
    units: UnsafeBufferPointer<UInt16>, content: Range<Int>, into out: inout [UInt16]
  ) {
    out.append(tab)
    append(content, of: units, into: &out)
  }

  /// The offset of the colon that ends a title-page key, or `nil` when the line has none.
  ///
  /// Deliberately identical to ``FountainGrammar``'s `titlePageKeyEnd(_:)`: a key begins at
  /// the first code unit — an indented line is a continuation, not a key — must be
  /// non-empty, and ends at the **first** colon, since a key may contain spaces but not a
  /// colon. Reading past the first one would make `Title: Level 1: Simple Sentences` a key
  /// named `Title: Level 1`, which is a real line in `spanish.fountain`.
  private func keyEnd(_ units: UnsafeBufferPointer<UInt16>, lineEnd: Int) -> Int? {
    guard lineEnd > 0, !isSpaceOrTab(units[0]) else { return nil }
    var offset = 0
    while offset < lineEnd, units[offset] != colon {
      offset += 1
    }
    guard offset >= 1, offset < lineEnd else { return nil }
    return offset
  }

  // MARK: - Pieces

  /// Whether the line's marker — everything before its content — begins with `unit`.
  ///
  /// This is how a forced element is recognized at write time. There is no flag on
  /// ``LineRecord`` saying "forced"; the marker's *presence in the source, outside the
  /// content range* is the flag (REQUIREMENTS.md Architecture §9), and reading the
  /// character rather than merely measuring the gap is what keeps an indent from being
  /// mistaken for a marker.
  private func marker(
    _ units: UnsafeBufferPointer<UInt16>, content: Range<Int>, is unit: UInt16
  ) -> Bool {
    content.lowerBound > 0 && units[0] == unit
  }

  /// Appends the content range.
  private func append(
    _ content: Range<Int>, of units: UnsafeBufferPointer<UInt16>, into out: inout [UInt16]
  ) {
    for offset in content {
      out.append(units[offset])
    }
  }

  /// Appends a single separating space and then the content — and neither when the content
  /// is empty, so `#` alone does not acquire a trailing space it would lose again on the
  /// next write.
  private func appendSpaced(
    _ content: Range<Int>, of units: UnsafeBufferPointer<UInt16>, into out: inout [UInt16]
  ) {
    guard !content.isEmpty else { return }
    out.append(space)
    append(content, of: units, into: &out)
  }

  /// Appends the line exactly as it was written, terminator excluded.
  private func appendRaw(
    lineEnd: Int, of units: UnsafeBufferPointer<UInt16>, into out: inout [UInt16]
  ) {
    for offset in 0..<lineEnd {
      out.append(units[offset])
    }
  }

  // MARK: - Terminators

  /// How many code units at the end of `units` are the line's terminator: two for `\r\n`,
  /// one for `\n` or a lone `\r`, zero for a final line that ends without one.
  ///
  /// Measured from the bytes rather than carried on the record, because ``LineRecord``
  /// does not carry it: `contentRange` is the line's *payload*, which for `.HOUSE` starts
  /// after the period, so `range.upperBound - contentRange.upperBound` is not a terminator
  /// length and never was. Reading the tail is exact and costs two comparisons.
  ///
  /// `\r\n` is **one** terminator of **two** code units, and this is the whole reason the
  /// pair is checked before the single (REQUIREMENTS.md § Line termination).
  private func terminatorLength(of units: UnsafeBufferPointer<UInt16>) -> Int {
    guard let last = units.last else { return 0 }
    if last == lineFeed {
      return units.count >= 2 && units[units.count - 2] == carriageReturn ? 2 : 1
    }
    return last == carriageReturn ? 1 : 0
  }

  /// A record's content range as offsets into one line's code units, clamped to that line.
  ///
  /// The clamp is what keeps a stale or hand-assembled record from indexing outside the
  /// buffer. A well-formed record from a current scan is unaffected by every branch here.
  private func clamped(
    _ content: Range<Int>, within line: Range<Int>, lineEnd: Int
  ) -> Range<Int> {
    let lower = min(max(content.lowerBound - line.lowerBound, 0), lineEnd)
    let upper = min(max(content.upperBound - line.lowerBound, lower), lineEnd)
    return lower..<upper
  }
}
