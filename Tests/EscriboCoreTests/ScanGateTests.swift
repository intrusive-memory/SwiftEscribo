import Testing

@testable import EscriboCore

// MARK: - Determinism

/// SplitMix64: a deterministic generator with a fixed, explicit seed.
///
/// The suite must be reproducible. `SystemRandomNumberGenerator` is not, and a
/// property test whose failing input cannot be reproduced is a flake report rather
/// than a bug report. Every draw in this file goes through one of these, and every seed
/// is a compile-time constant in ``gateSeeds`` — no wall clock, no system entropy, and
/// no `random` call anywhere in this file that does not pass `using: &generator`.
///
/// SplitMix64 rather than a linear congruential generator because a weak low bit is
/// exactly what would make `offset % lineCount` degenerate and quietly stop exploring.
struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) {
    self.state = seed
  }

  mutating func next() -> UInt64 {
    state = state &+ 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

/// The seeds, as fixed constants.
///
/// Thirty-two of them, chosen once and never regenerated. Each is a distinct
/// parameterized case, so a failure names its seed and the case can be re-run on its own
/// from the Xcode test navigator — or from the command line by narrowing this array to
/// the one constant the failure reported. A seeded generator whose seed is not
/// selectable is a generator nobody can debug.
let gateSeeds: [UInt64] = [
  0x0000_0000_0000_0001, 0x0000_0000_0000_0002, 0x0000_0000_0000_0003, 0x0000_0000_0000_0005,
  0x0000_0000_0000_0008, 0x0000_0000_0000_000D, 0x0000_0000_0000_0015, 0x0000_0000_0000_0022,
  0x0123_4567_89AB_CDEF, 0xFEDC_BA98_7654_3210, 0xDEAD_BEEF_CAFE_BABE, 0x5555_5555_5555_5555,
  0xAAAA_AAAA_AAAA_AAAA, 0x0F0F_0F0F_0F0F_0F0F, 0xF0F0_F0F0_F0F0_F0F0, 0x1234_1234_1234_1234,
  0x2718_2818_2845_9045, 0x3141_5926_5358_9793, 0x1618_0339_8874_9895, 0x1414_2135_6237_3095,
  0x0000_0000_FFFF_FFFF, 0xFFFF_FFFF_0000_0000, 0x8000_0000_0000_0001, 0x7FFF_FFFF_FFFF_FFFF,
  0xC0FF_EE00_C0FF_EE00, 0xBADD_CAFE_0BAD_F00D, 0x1357_9BDF_2468_ACE0, 0x9E37_79B9_7F4A_7C15,
  0x6A09_E667_F3BC_C908, 0xBB67_AE85_84CA_A73B, 0x3C6E_F372_FE94_F82B, 0xA54F_F53A_5F1D_36F1,
]

// MARK: - The corpus

/// A document the seeded generator edits.
///
/// Unlike `IncrementalScannerTests`'s sweep corpus, these are **not** ASCII-only. The
/// sweep splices every UTF-16 offset in range and would corrupt an astral-plane document
/// by splitting a surrogate pair — a defect in the test, not in the scanner. The seeded
/// generator chooses its offsets through
/// ``ScanInvariants/isCharacterBoundary(_:in:)`` instead, so astral-plane text can be in
/// the corpus where it belongs.
struct GateDocument: Sendable, CustomTestStringConvertible {
  let name: String
  let text: String

  var testDescription: String { name }
}

/// Nine documents. Every one of them contains at least one line of pure ASCII capitals,
/// because that is what `CueGrammar`'s lookahead rule keys on and the "edit the line
/// after an ALL-CAPS line" shape needs a caps line to sit after.
///
/// - `lf markdown` is LF-terminated throughout.
/// - `crlf markdown` is **CRLF** throughout and ends without a terminator.
/// - `mixed terminators` carries LF, CRLF, and a lone CR in one document.
/// - `astral plane` carries **astral-plane characters** — emoji and a Deseret capital —
///   whose UTF-16 representation is a surrogate pair.
/// - `screenplay cues` is fence-free and cue-shaped, so the lookahead grammar has
///   something to look ahead at.
/// - `unterminated fence` opens a fence that never closes.
/// - `one line` is a single line with no terminator at all.
/// - `fountain dialogue` is a real dialogue block — cue, extension, parenthetical,
///   speech, and a dual-dialogue caret — added by Sortie 14 so `FountainGrammar`'s own
///   multi-line state has something to converge across. Note what this buys and what it
///   does not: it is a **convergence** check, and the property below cannot fail on a
///   wrong cue rule no matter how many Fountain documents are in this array.
/// - `fountain forced markers` is the same in CRLF, with one of every forcing marker in
///   it, so the "any non-dialogue element closes the block" rule is crossed repeatedly by
///   edits that move lines in and out of a block.
let gateCorpus: [GateDocument] = [
  GateDocument(
    name: "lf markdown",
    text: """
      # Title
      prose about things
      SHOUTING
      more prose

      ```swift
      let x = 1
      ```
      tail
      """),
  GateDocument(
    name: "crlf markdown",
    text: "## Heading\r\nCRLF line\r\nLOUD\r\n\r\n~~~\r\ncode here\r\n~~~\r\nafter"),
  GateDocument(
    name: "mixed terminators",
    text: "AAA\nbbb\r\nCCC\rddd\n\r\n# heading\r\n```\ncode\n```\rEND"),
  GateDocument(
    name: "astral plane",
    text: """
      # 😀 Title 𐐷
      prose with a 😀 in it
      EMOJI
      𐐷𐐷𐐷 line of astral text
      ```swift
      let smile = "😀"
      ```
      𐐷 tail 😀
      """),
  GateDocument(
    name: "screenplay cues",
    text: """
      BOB
      Hello there.

      JANE

      ACTION
      and some action text
      MORE
      dialogue follows
      """),
  GateDocument(
    name: "unterminated fence",
    text: """
      intro
      ```swift
      let y = 2
      NEVER
      closed
      """),
  GateDocument(name: "one line", text: "ONELINE"),
  GateDocument(
    name: "fountain dialogue",
    text: """
      INT. HOUSE - DAY

      BOB
      (beat)
      Hello there.

      JANE ^
      And hello to you.

      CUT TO:
      """),
  GateDocument(
    name: "fountain forced markers",
    text: "@McAvoy\r\nSomething muttered.\r\n\r\n.SNIPER SCOPE POV\r\n!forced action\r\n"
      + "~a lyric line\r\n===\r\n> CUT TO:\r\nBOB"),
]

// MARK: - Adversarial edit shapes

/// The seven edit shapes the plan requires, and the whole reason the generator is not a
/// uniform typing simulator.
///
/// Uniform typing finds nothing: it lands one character in the middle of a paragraph,
/// converges after two lines, and agrees with a full scan for the same reason a broken
/// clock agrees with itself. Every shape below is one where the rescan window has to be
/// something other than "the edited line".
enum EditShape: String, CaseIterable, Sendable {
  /// An edit on the line **after** an ALL-CAPS line. Backward widening — the classified
  /// line is above the edit and nothing about the edit points at it.
  case afterAllCapsLine

  /// An edit that opens a fence. State propagates to the end of the document.
  case openFence

  /// An edit that closes an open fence, by deleting the opener or inserting a matching
  /// closer. The inverse propagation.
  case closeFence

  /// A multi-line paste. The index gains lines and the old-to-new line mapping moves.
  case pasteMultiLineBlock

  /// A multi-line deletion. The index loses lines, which is the sign the mapping most
  /// often gets wrong.
  case deleteMultiLineBlock

  /// An edit at offset zero. Backward widening has nowhere to widen to.
  case atOffsetZero

  /// An edit at the end of the document. Forward convergence has nowhere to converge to,
  /// and the final line may have no terminator.
  case atEndOfFile
}

/// One generated edit, plus the document it produces.
struct GateStep: Sendable {
  /// The replaced range, in the **old** text's coordinates.
  let range: Range<Int>

  /// The replacement text.
  let replacement: String

  /// The document after this edit.
  let text: String

  /// The shape the generator was asked for.
  let requested: EditShape

  /// Whether the document could actually host that shape. `false` means the generator
  /// substituted a setup edit — inserting a fence line into a document with none, say —
  /// and the step should not be counted as coverage of ``requested``.
  let emitted: Bool

  /// Whether both ends of ``range`` sat **between characters** in the document this edit
  /// was computed against.
  ///
  /// Checked at generation time, against the old text, because that is the only moment
  /// it can be checked: splicing through a surrogate pair orphans it,
  /// `String(decoding:as:)` substitutes U+FFFD, and the resulting document is perfectly
  /// well-formed — there is nothing left downstream to detect. A `false` here is a bug in
  /// the generator masquerading as a bug in the scanner.
  let boundsWereCharacterAligned: Bool

  /// The edited range in **new** text coordinates.
  var editedRange: Range<Int> {
    range.lowerBound..<(range.lowerBound + replacement.utf16.count)
  }

  /// The edit as the scanner takes it.
  var edit: TextEdit {
    TextEdit(range: range, replacementLength: replacement.utf16.count)
  }
}

// MARK: - The generator

/// Turns a seed and a document into a sequence of adversarial edits.
///
/// Every sequence is a **permutation of all seven shapes**, drawn with the seeded
/// generator. That is deliberate: drawing shapes independently would leave some
/// sequences with no fence in them at all, and the shapes are the only reason this test
/// finds anything. A permutation guarantees each sequence exercises every shape exactly
/// once, in an order the seed decides — and the order matters, because "delete a
/// multi-line block, then open a fence at offset zero" is a different scanner state from
/// the reverse.
enum GateEditGenerator {

  /// Blocks pasted by ``EditShape/pasteMultiLineBlock``. Mixed terminators and an
  /// astral-plane character on purpose.
  static let multiLineBlocks: [String] = [
    "alpha\nBETA\ngamma\n",
    "```\nfenced\npaste\n```\n",
    "one\r\ntwo\r\nthree\r\n",
    "😀 SMILE\nnext line\n",
    "\n\nPARA\n\n",
  ]

  /// Fence openers. Both characters and both a bare and an info-string form, because the
  /// grammars disagree about which of them is a fence and that disagreement is fine.
  static let fenceOpeners: [String] = ["~~~\n", "```\n", "```swift\n", "````\n"]

  /// Short insertions used by the offset-zero and end-of-file shapes.
  static let smallInsertions: [String] = ["#", "X", "# ", "\r\n", "😀", " word"]

  /// Generates one sequence: seven edits, one per shape.
  static func sequence(seed: UInt64, from document: String) -> [GateStep] {
    var generator = SeededGenerator(seed: seed)
    let order = EditShape.allCases.shuffled(using: &generator)
    var text = document
    var steps: [GateStep] = []

    for shape in order {
      let units = Array(text.utf16)
      let produced = edit(for: shape, in: units, using: &generator)
      let aligned =
        ScanInvariants.isCharacterBoundary(produced.range.lowerBound, in: units)
        && ScanInvariants.isCharacterBoundary(produced.range.upperBound, in: units)
      let next = ScanInvariants.splice(text, produced.range, produced.replacement)
      steps.append(
        GateStep(
          range: produced.range,
          replacement: produced.replacement,
          text: next,
          requested: shape,
          emitted: produced.emitted,
          boundsWereCharacterAligned: aligned))
      text = next
    }
    return steps
  }

  // MARK: Shape emitters

  private static func edit(
    for shape: EditShape,
    in units: [UInt16],
    using generator: inout SeededGenerator
  ) -> (range: Range<Int>, replacement: String, emitted: Bool) {
    switch shape {
    case .atOffsetZero: atOffsetZero(units, &generator)
    case .atEndOfFile: atEndOfFile(units, &generator)
    case .afterAllCapsLine: afterAllCapsLine(units, &generator)
    case .openFence: openFence(units, &generator)
    case .closeFence: closeFence(units, &generator)
    case .pasteMultiLineBlock: pasteMultiLineBlock(units, &generator)
    case .deleteMultiLineBlock: deleteMultiLineBlock(units, &generator)
    }
  }

  /// Insert at zero, or delete the document's first character.
  private static func atOffsetZero(
    _ units: [UInt16], _ generator: inout SeededGenerator
  ) -> (Range<Int>, String, Bool) {
    if !units.isEmpty, Bool.random(using: &generator) {
      // A whole character, never half a surrogate pair.
      let width = isHighSurrogate(units[0]) && units.count > 1 ? 2 : 1
      return (0..<width, "", true)
    }
    let choice = Int.random(in: 0..<(smallInsertions.count + fenceOpeners.count), using: &generator)
    let text =
      choice < smallInsertions.count
      ? smallInsertions[choice] : fenceOpeners[choice - smallInsertions.count]
    return (0..<0, text, true)
  }

  /// Insert at EOF, or delete the document's last character.
  private static func atEndOfFile(
    _ units: [UInt16], _ generator: inout SeededGenerator
  ) -> (Range<Int>, String, Bool) {
    let end = units.count
    if end > 0, Bool.random(using: &generator) {
      let width = isLowSurrogate(units[end - 1]) && end > 1 ? 2 : 1
      return ((end - width)..<end, "", true)
    }
    let tails = ["\n", "tail", "\r\nEND", "😀", "\n~~~\n", ""]
    return (end..<end, tails[Int.random(in: 0..<tails.count, using: &generator)], true)
  }

  /// Edit the line **after** an ALL-CAPS line — the Fountain cue shape, which no Fountain
  /// grammar exists to exercise until Sortie 13 and which `CueGrammar` models exactly.
  ///
  /// When the caps line is the last line, the edit appends a following line, which is the
  /// same rule from the other side: an ALL-CAPS line with nothing after it is not a cue,
  /// and typing a line under it makes it one.
  private static func afterAllCapsLine(
    _ units: [UInt16], _ generator: inout SeededGenerator
  ) -> (Range<Int>, String, Bool) {
    let starts = lineStarts(units)
    let capsLines = (0..<starts.count).filter { isAllCapsLine(units, starts, $0) }
    guard !capsLines.isEmpty else {
      // The document has no ALL-CAPS line to sit after. Seed one instead, and do not
      // claim the shape was covered.
      let at = starts[Int.random(in: 0..<starts.count, using: &generator)]
      return (at..<at, "BOB\n", false)
    }

    let line = capsLines[Int.random(in: 0..<capsLines.count, using: &generator)]
    guard line + 1 < starts.count else {
      // The caps line is last: give it a following line.
      return (units.count..<units.count, "\nHello there.", true)
    }

    let start = starts[line + 1]
    let end = line + 2 < starts.count ? starts[line + 2] : units.count
    let content = contentEnd(units, from: start, lineEnd: end)
    let width = content > start && isHighSurrogate(units[start]) ? 2 : 1
    if start + width <= content, Bool.random(using: &generator) {
      // Delete the following line's first character — enough to blank a one-character
      // line, which un-cues the caps line above it. A whole character, never half a
      // surrogate pair.
      return (start..<(start + width), "", true)
    }
    return (start..<start, "Hello", true)
  }

  /// Open a fence at some line start.
  private static func openFence(
    _ units: [UInt16], _ generator: inout SeededGenerator
  ) -> (Range<Int>, String, Bool) {
    let starts = lineStarts(units)
    let at = starts[Int.random(in: 0..<starts.count, using: &generator)]
    let opener = fenceOpeners[Int.random(in: 0..<fenceOpeners.count, using: &generator)]
    return (at..<at, opener, true)
  }

  /// Close an open fence — by deleting the opening line, or by inserting a matching
  /// closing marker further down.
  private static func closeFence(
    _ units: [UInt16], _ generator: inout SeededGenerator
  ) -> (Range<Int>, String, Bool) {
    let starts = lineStarts(units)
    let fences = (0..<starts.count).compactMap { line -> (line: Int, marker: String)? in
      guard let run = fenceRun(units, starts, line) else { return nil }
      return (line, run)
    }
    guard !fences.isEmpty else {
      // Nothing to close. Open one, and do not claim the shape was covered.
      let at = starts[Int.random(in: 0..<starts.count, using: &generator)]
      return (at..<at, "~~~\n", false)
    }

    let picked = fences[Int.random(in: 0..<fences.count, using: &generator)]
    if Bool.random(using: &generator) {
      // Delete the fence line outright.
      let start = starts[picked.line]
      let end = picked.line + 1 < starts.count ? starts[picked.line + 1] : units.count
      return (start..<end, "", true)
    }
    // Insert a matching closer at a later line start, or at EOF if there is none.
    let later = starts.filter { $0 > starts[picked.line] }
    let at = later.isEmpty ? units.count : later[Int.random(in: 0..<later.count, using: &generator)]
    return (at..<at, picked.marker + "\n", true)
  }

  /// Paste a multi-line block at a character boundary.
  private static func pasteMultiLineBlock(
    _ units: [UInt16], _ generator: inout SeededGenerator
  ) -> (Range<Int>, String, Bool) {
    let at = safeOffset(units, &generator)
    return (
      at..<at, multiLineBlocks[Int.random(in: 0..<multiLineBlocks.count, using: &generator)],
      true
    )
  }

  /// Delete a range covering at least two whole lines.
  private static func deleteMultiLineBlock(
    _ units: [UInt16], _ generator: inout SeededGenerator
  ) -> (Range<Int>, String, Bool) {
    var bounds = lineStarts(units)
    if bounds.last != units.count { bounds.append(units.count) }
    guard bounds.count >= 3 else {
      // Fewer than two lines to delete. Paste one instead, and do not claim coverage.
      let at = safeOffset(units, &generator)
      return (at..<at, "alpha\nBETA\n", false)
    }
    let lower = Int.random(in: 0..<(bounds.count - 2), using: &generator)
    let upper = Int.random(in: (lower + 2)..<bounds.count, using: &generator)
    return (bounds[lower]..<bounds[upper], "", true)
  }

  // MARK: Line arithmetic — hand-written, and deliberately not `LineIndex`

  /// The offset every line begins at. See ``ScanInvariants/lineStarts(_:)`` — one
  /// hand-written line oracle in the target, not two.
  static func lineStarts(_ units: [UInt16]) -> [Int] {
    ScanInvariants.lineStarts(units)
  }

  /// Where line `line`'s content ends — its extent minus its terminator.
  private static func contentEnd(_ units: [UInt16], from start: Int, lineEnd: Int) -> Int {
    var end = lineEnd
    if end > start, units[end - 1] == 0x0A { end -= 1 }
    if end > start, units[end - 1] == 0x0D { end -= 1 }
    return end
  }

  /// Whether line `line` is one or more ASCII capitals and nothing else — `CueGrammar`'s
  /// rule, restated here so the generator does not have to ask a grammar anything.
  private static func isAllCapsLine(_ units: [UInt16], _ starts: [Int], _ line: Int) -> Bool {
    let start = starts[line]
    let end = contentEnd(
      units, from: start, lineEnd: line + 1 < starts.count ? starts[line + 1] : units.count)
    guard end > start else { return false }
    for offset in start..<end where units[offset] < 0x41 || units[offset] > 0x5A {
      return false
    }
    return true
  }

  /// The marker run of a fence line — three or more backticks or tildes after at most
  /// three columns of indent — or `nil` if the line is not one.
  private static func fenceRun(_ units: [UInt16], _ starts: [Int], _ line: Int) -> String? {
    let start = starts[line]
    let end = contentEnd(
      units, from: start, lineEnd: line + 1 < starts.count ? starts[line + 1] : units.count)
    var cursor = start
    var indent = 0
    while cursor < end, units[cursor] == 0x20 || units[cursor] == 0x09 {
      indent += 1
      cursor += 1
    }
    guard indent <= 3, cursor < end else { return nil }
    let character = units[cursor]
    guard character == 0x60 || character == 0x7E else { return nil }
    var run = 0
    while cursor < end, units[cursor] == character {
      run += 1
      cursor += 1
    }
    guard run >= 3 else { return nil }
    return String(repeating: character == 0x60 ? "`" : "~", count: run)
  }

  /// A random offset that sits **between characters**.
  ///
  /// Splicing through a surrogate pair produces a string the test corrupted —
  /// `String(decoding:as:)` substitutes U+FFFD for the orphan and every offset after it
  /// moves — which would look exactly like a scanner bug and be nothing of the kind.
  private static func safeOffset(_ units: [UInt16], _ generator: inout SeededGenerator) -> Int {
    var offset = Int.random(in: 0...units.count, using: &generator)
    while offset > 0, ScanInvariants.splitsSurrogatePair(at: offset, in: units) {
      offset -= 1
    }
    return offset
  }

  private static func isHighSurrogate(_ unit: UInt16) -> Bool { (0xD800...0xDBFF).contains(unit) }
  private static func isLowSurrogate(_ unit: UInt16) -> Bool { (0xDC00...0xDFFF).contains(unit) }
}

// MARK: - The gate

@Suite("Scan gate — seeded convergence property and the invariant harness")
struct ScanGateTests {

  /// Replays one generated sequence through one grammar, asserting the gate at every
  /// step.
  ///
  /// Comparing only after the last edit would find the divergence but not the edit that
  /// caused it, and on a seven-edit sequence that is the difference between a bug report
  /// and a shrug. Every step therefore compares against a full scan of the same text.
  ///
  /// The comparison has two halves and **both** are necessary:
  ///
  /// - The returned window against the matching slice of a full scan: "is what you
  ///   repainted correct?"
  /// - The accumulated ``ScanInvariants/PaintedDocument`` against the whole full scan:
  ///   "did you repaint everything that changed?"
  ///
  /// The first half alone cannot fail when the rescan window is too small, because the
  /// lines wrongly left unpainted are outside the window it compares. The second half is
  /// the one that catches it.
  static func replay<Grammar: LineGrammar>(
    _ grammar: Grammar,
    steps: [GateStep],
    from document: String,
    seed: UInt64,
    documentName: String
  ) {
    var incremental = IncrementalScanner(grammar: grammar)
    let first = incremental.fullScan(document)
    ScanInvariants.check(
      first, text: document, editedRange: nil,
      "seed 0x\(String(seed, radix: 16)) \(documentName) — initial full scan of \(Grammar.self)")
    var painted = ScanInvariants.PaintedDocument(first)

    for (number, step) in steps.enumerated() {
      let note = """
        seed 0x\(String(seed, radix: 16)), document "\(documentName)", grammar \(Grammar.self), \
        step \(number) (\(step.requested.rawValue)\(step.emitted ? "" : ", substituted")), \
        edit \(step.range) -> \(step.replacement.debugDescription), \
        text \(step.text.debugDescription)
        """

      // The generator's own contract, asserted before anything is blamed on the scanner:
      // an edit boundary inside a surrogate pair produces a document the *test*
      // corrupted, and a corrupted document is indistinguishable from a scanner bug.
      #expect(step.boundsWereCharacterAligned, "the generator spliced a surrogate — \(note)")

      let result = incremental.incrementalScan(step.edit, in: step.text)
      ScanInvariants.check(result, text: step.text, editedRange: step.editedRange, note)

      var fresh = IncrementalScanner(grammar: grammar)
      let full = fresh.fullScan(step.text)
      ScanInvariants.check(full, text: step.text, editedRange: nil, "full scan — \(note)")

      // Half one: what was repainted is right. `lineRecords` and `spans` compared as
      // arrays, per the plan, over the window the scan claims to cover.
      ScanInvariants.expectSameElements(
        result.lineRecords,
        full.lineRecords.filter { result.lines.contains($0.index) },
        "lineRecords", note)
      ScanInvariants.expectSameElements(
        result.spans,
        full.spans.filter {
          $0.range.lowerBound >= result.dirtyRange.lowerBound
            && $0.range.upperBound <= result.dirtyRange.upperBound
        },
        "spans", note)
      ScanInvariants.expectSameElements(
        incremental.startStates, fresh.startStates, "startStates", note)

      // Half two, and the one that can fail when the window is too small: the whole
      // document, as the editor would now have it painted, against a full scan of the
      // same text. This is `incrementalScan(edits) == fullScan(finalText)` stated over
      // the document rather than over the window.
      painted.apply(result, newLineCount: ScanInvariants.lineCount(of: step.text))
      ScanInvariants.expectSameElements(
        painted.lines, ScanInvariants.paintedLines(of: full), "painted document", note)
    }
  }

  // MARK: The gate property

  /// **`incrementalScan(edits) == fullScan(finalText)`** over a seeded sequence of
  /// adversarial edits.
  ///
  /// ## Read this before you cite a green run of this test as evidence of anything
  ///
  /// This test **cannot catch a bug in a grammar.** Not "is unlikely to" — cannot, for a
  /// structural reason: *both sides of the comparison run the same grammar.* If a grammar
  /// forgets to carry some piece of its state from one line to the next, the incremental
  /// scan is wrong in exactly the same way the full scan is wrong, the two agree
  /// perfectly, and this test passes. Self-consistency is invariant to grammar defects.
  /// Nothing about how thorough the comparison is changes that — the whole-document
  /// painted comparison added here is strictly stronger than a window comparison and is
  /// just as blind, because strength and blindness are about different axes.
  ///
  /// Sortie 5 demonstrated this against its own interest: deliberately breaking the
  /// Markdown grammar's in-fence flag — computing it and then not carrying it across
  /// lines — turned **six direct classification tests red and left this comparison
  /// green**.
  ///
  /// So, stated as plainly as it can be stated:
  ///
  /// - This test catches convergence bugs in the **engine**: a rescan window that starts
  ///   too late, stops too early, or maps old line numbers to new ones wrongly. Both
  ///   documented breaks — treating state equality alone as convergence, and stopping
  ///   unconditionally after one line — turn it red.
  /// - This test catches **nothing at all** about whether a grammar classifies lines
  ///   correctly, carries the state it needs, or emits the right spans.
  ///
  /// One engine break it also does **not** catch, measured rather than assumed: deleting
  /// the `lookahead`-line extension past the convergence point changes only the *size* of
  /// the rescan window and not a single painted line, for every grammar in the target.
  /// That extension is conservative padding — a converged line's own lookahead reaches
  /// only forward, into text the edit is already behind — so no output can differ. The
  /// exact-window assertion in `IncrementalScannerTests` is what holds it; do not delete
  /// that test on the grounds that this one covers it.
  ///
  /// If you are writing a grammar — Fountain scene headings, cues, dialogue, dual
  /// dialogue, Markdown lists, emphasis, links, tables, or the nested `fountain` fence —
  /// "the gate test passes" is **not** evidence your grammar is right, and several
  /// sorties list it among their exit criteria in a way that invites exactly that
  /// mistake. The only thing that catches a state-omission bug in a grammar is an
  /// assertion whose expected value was **written out by a human** and did not come from
  /// running the grammar: an explicit list of `ElementKind`s per line, an explicit span
  /// range, an explicit depth. Write those. This test will not write them for you, and it
  /// will smile at you while you do not.
  ///
  /// ``fenceStateMustBeCarriedAcrossLines`` and ``cueLookaheadMustBeCarriedAcrossLines``
  /// below are the cheap, non-self-referential counterweights to this one. They are what
  /// go red when a grammar loses state.
  @Test(
    "Incremental scanning equals full scanning across a seeded adversarial edit sequence",
    arguments: gateSeeds, gateCorpus)
  func incrementalScanEqualsFullScan(seed: UInt64, document: GateDocument) {
    let steps = GateEditGenerator.sequence(seed: seed, from: document.text)
    #expect(steps.count == EditShape.allCases.count, "the sequence must cover every shape")

    // Four grammars over the same generated sequence: stateless, stateful, one that looks
    // ahead, and — since Sortie 14 — one shipping grammar that does both at once. The
    // sequence is grammar-independent by construction — it is a function of the text
    // alone — so a divergence can be attributed to the grammar's shape rather than to a
    // different set of edits.
    Self.replay(
      MarkdownGrammar(), steps: steps, from: document.text, seed: seed,
      documentName: document.name)
    Self.replay(
      FenceGrammar(), steps: steps, from: document.text, seed: seed, documentName: document.name)
    Self.replay(
      CueGrammar(lookahead: 1), steps: steps, from: document.text, seed: seed,
      documentName: document.name)
    // `FountainGrammar` is the first *shipping* grammar with a non-zero lookahead, so it
    // is the first one whose rescan window is widened backward as well as forward on every
    // edit. What that proves is convergence and nothing else: read the warning above
    // before citing a green run of this as evidence the cue rule is right. The
    // hand-written expectations in `FountainGrammarTests` are what hold that.
    Self.replay(
      FountainGrammar(), steps: steps, from: document.text, seed: seed,
      documentName: document.name)
  }

  // MARK: Coverage of the adversarial shapes

  /// Every one of the seven shapes is actually produced, on real documents, by real
  /// seeds.
  ///
  /// A generator that quietly degrades — finding no fence and inserting a plain line
  /// instead, say — still produces a green gate while testing nothing the plan asked
  /// for. This is the test that would notice. It runs the generator only; it scans
  /// nothing, so it costs the suite almost nothing.
  @Test("The generator genuinely emits all seven adversarial shapes")
  func generatorEmitsEveryAdversarialShape() {
    var emitted: [EditShape: Int] = [:]
    var substituted = 0
    var sequences = 0

    for seed in gateSeeds {
      for document in gateCorpus {
        sequences += 1
        for step in GateEditGenerator.sequence(seed: seed, from: document.text) {
          if step.emitted {
            emitted[step.requested, default: 0] += 1
          } else {
            substituted += 1
          }
        }
      }
    }

    #expect(sequences == gateSeeds.count * gateCorpus.count)
    #expect(sequences >= 200, "the gate must run at least 200 edit sequences, ran \(sequences)")
    for shape in EditShape.allCases {
      #expect(
        (emitted[shape] ?? 0) > 0,
        "the generator never actually produced \(shape.rawValue) on any seed or document")
    }
    // Substitutions are legal — a one-line document cannot host a two-line deletion —
    // but they must stay a rounding error rather than the bulk of the run.
    let total = sequences * EditShape.allCases.count
    #expect(substituted * 5 < total, "\(substituted) of \(total) steps degraded to a substitute")
  }

  /// The generator is a pure function of its seed and its input.
  @Test("The same seed produces the same sequence, every time", arguments: gateSeeds.prefix(4))
  func generatorIsDeterministic(seed: UInt64) {
    for document in gateCorpus {
      let first = GateEditGenerator.sequence(seed: seed, from: document.text)
      let second = GateEditGenerator.sequence(seed: seed, from: document.text)
      #expect(first.map(\.text) == second.map(\.text), "seed 0x\(String(seed, radix: 16))")
      #expect(first.map(\.range) == second.map(\.range))
      #expect(first.map(\.requested) == second.map(\.requested))
    }
  }

  // MARK: Non-self-referential counterweights
  //
  // Expected values here were written by hand and did not come from running the grammar.
  // That is the only property that makes them able to catch a state-losing grammar, and
  // it is the property the gate property above structurally cannot have.

  /// A grammar that computes its in-fence flag and forgets to carry it fails this, and
  /// the gate property above does not notice.
  @Test("Markdown carries the in-fence flag across every line of a block")
  func fenceStateMustBeCarriedAcrossLines() {
    var scanner = IncrementalScanner(grammar: MarkdownGrammar())

    // Six lines, and every one after the opener is inside the block — including a line
    // that would be a heading anywhere else. Written out, not derived.
    let unterminated = "```\nalpha\n# not a heading\nbeta\nSHOUT\ndelta"
    let open = scanner.fullScan(unterminated)
    ScanInvariants.check(open, text: unterminated, editedRange: nil, "unterminated block")
    #expect(
      open.lineRecords.map(\.element) == [
        .codeFence, .codeBlock, .codeBlock, .codeBlock, .codeBlock, .codeBlock,
      ])
    #expect(open.lineRecords[2].depth == 0, "a `#` inside a fence is not a heading of any level")

    // And the same document with the block closed: the lines after it are ordinary again.
    let closed = "```\nalpha\n```\n# yes a heading\nbeta"
    var second = IncrementalScanner(grammar: MarkdownGrammar())
    let result = second.fullScan(closed)
    ScanInvariants.check(result, text: closed, editedRange: nil, "closed block")
    #expect(
      result.lineRecords.map(\.element) == [
        .codeFence, .codeBlock, .codeFence, .heading, .paragraph,
      ])
    #expect(result.lineRecords[3].depth == 1)
  }

  /// A grammar that classifies a line without consulting the line after it fails this,
  /// and the gate property above does not notice.
  @Test("The cue grammar's classification depends on the line that follows")
  func cueLookaheadMustBeCarriedAcrossLines() {
    // `BOB` is a cue because a non-empty line follows. `JANE` is not, because a blank one
    // does. `ACTION` is not, because nothing does. Written out, not derived.
    let text = "BOB\nHello there.\n\nJANE\n\nACTION"
    var scanner = IncrementalScanner(grammar: CueGrammar(lookahead: 1))
    let result = scanner.fullScan(text)
    ScanInvariants.check(result, text: text, editedRange: nil, "cue shapes")

    #expect(
      result.lineRecords.map(\.element) == [
        .testCue, .paragraph, .blank, .paragraph, .blank, .paragraph,
      ])
    #expect(result.spans.first?.kind == .testCue)
    #expect(result.spans.first?.range == 0..<3)

    // The same grammar with its lookahead switched off classifies nothing as a cue —
    // which is what makes the assertion above about lookahead rather than about capitals.
    var blind = IncrementalScanner(grammar: CueGrammar(lookahead: 0))
    let blindResult = blind.fullScan(text)
    ScanInvariants.check(blindResult, text: text, editedRange: nil, "cue shapes, no lookahead")
    #expect(blindResult.lineRecords.allSatisfy { $0.element != .testCue })
  }
}
