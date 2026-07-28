/// The code units this file recognizes, named once so no rule spells a magic number.
private let numberSign: UInt16 = 0x23
private let hyphen: UInt16 = 0x2D
private let colon: UInt16 = 0x3A
private let space: UInt16 = 0x20
private let tab: UInt16 = 0x09

private func isSpaceOrTab(_ unit: UInt16) -> Bool { unit == space || unit == tab }

/// The line rules for a **YAML frontmatter region** — the `---`-fenced leading block a
/// document may open with — as free functions two grammars share.
///
/// ## Why this is not a method on either grammar
///
/// Markdown and Fountain both let a document open with `---`, and the region means the same
/// thing in both: a leading block of `key: value` metadata that is not the document's own
/// language. The span vocabulary is already shared — ``SpanKind/frontmatterDelimiter``,
/// ``SpanKind/frontmatterKey``, ``SpanKind/frontmatterValue`` are one set of kinds, not two —
/// so two implementations of the rules that produce them could only ever agree by
/// coincidence. A `key:` that splits at a different colon in a `.md` file than in a
/// `.fountain` file is a bug nobody would find quickly, and the only durable fix is for
/// there to be one rule.
///
/// What is deliberately **not** here is *when* a region opens. That is each grammar's own
/// decision and the two answer it differently — Markdown reads
/// ``GrammarLine/index``, Fountain reads its title-page region — so the opening
/// **criterion** stays with the grammar and only the line **shapes** live here.
///
/// ## What this does not do
///
/// It does not parse YAML. `EscriboCore` imports nothing at all, so there is no YAML parser
/// here and deliberately no date, number, or boolean anywhere in this package's output: the
/// scanner says where the value is and the source says what it is. A consumer that wants
/// `type: docs` as a dictionary reads the ranges and does its own parsing, with its own
/// dependencies, outside this package.
enum FrontmatterScanning {

  /// The end offset of a frontmatter fence run, or `nil` if this line is not one.
  ///
  /// No leading whitespace — a fence sits flush left — **exactly three hyphens**, and
  /// nothing but spaces and tabs after them. Three and not "three or more", so that `----`
  /// on line one is still whatever the host grammar calls a run of hyphens: Jekyll, Hugo,
  /// and every other tool that reads this region spell the fence `---`, and widening the
  /// rule would silently swallow the top of a document that opens with a rule.
  static func delimiterEnd(_ units: [UInt16]) -> Int? {
    var runEnd = 0
    while runEnd < units.count, units[runEnd] == hyphen {
      runEnd += 1
    }
    guard runEnd == 3 else { return nil }
    var cursor = runEnd
    while cursor < units.count, isSpaceOrTab(units[cursor]) {
      cursor += 1
    }
    guard cursor == units.count else { return nil }
    return runEnd
  }

  /// The shared shape of an opening and a closing frontmatter fence: one marker span, an
  /// empty content range, and whatever state the caller says the next line begins in.
  ///
  /// `endState` is a parameter rather than a computed value because the two grammars carry
  /// different things across the region — Markdown a tag, Fountain a tag *and* a title-page
  /// region — and a shared rule that decided it for them would be deciding something it
  /// cannot see.
  static func delimiterScan(
    _ line: GrammarLine, runEnd: Int, endState: LineState
  ) -> LineScan {
    let base = line.contentRange.lowerBound
    return LineScan(
      spans: [
        EscriboSpan(range: base..<(base + runEnd), kind: .frontmatterDelimiter, role: .marker)
      ],
      element: .frontmatterDelimiter,
      // Pure delimiter, like a closing code fence: no content, so an empty range where
      // content would have begun.
      contentRange: (base + runEnd)..<(base + runEnd),
      endState: endState
    )
  }

  /// Scans one line inside a frontmatter region into key and value **spans**.
  ///
  /// The key is everything from the first non-whitespace character to the first `:` that is
  /// followed by whitespace or ends the line — YAML's own rule, and the reason
  /// `url: https://example.com` does not split at the scheme's colon. A leading `- ` is
  /// consumed as part of the leading marker so a sequence of mappings still finds its keys.
  ///
  /// A `#` comment, a blank line, and a line with no key all **degrade**: one
  /// ``SpanKind/text`` span over whatever is there, rather than a structure the line does
  /// not have. That degrade path is also what an unterminated region looks like from the
  /// second line down, which is why there is no failure case here and no error path to
  /// return one through.
  static func entryScan(_ line: GrammarLine, endState: LineState) -> LineScan {
    let units = line.units
    let base = line.contentRange.lowerBound

    guard let key = keyRange(units) else {
      // Degrade: one `.text` span over whatever is there.
      return LineScan(
        spans: line.contentRange.isEmpty
          ? [] : [EscriboSpan(range: line.contentRange, kind: .text)],
        element: .frontmatter,
        contentRange: line.contentRange,
        endState: endState
      )
    }

    var valueStart = key.upperBound + 1
    while valueStart < units.count, isSpaceOrTab(units[valueStart]) {
      valueStart += 1
    }
    var spans: [EscriboSpan] = [
      EscriboSpan(range: (base + key.lowerBound)..<(base + key.upperBound), kind: .frontmatterKey),
      // The `:` and the whitespace after it, as a marker carrying the key's own kind — the
      // rule every marker in this package obeys.
      EscriboSpan(
        range: (base + key.upperBound)..<(base + valueStart), kind: .frontmatterKey,
        role: .marker),
    ]
    if valueStart < units.count {
      spans.append(
        EscriboSpan(
          range: (base + valueStart)..<line.contentRange.upperBound, kind: .frontmatterValue))
    }
    return LineScan(
      spans: spans,
      element: .frontmatter,
      contentRange: (base + valueStart)..<line.contentRange.upperBound,
      endState: endState
    )
  }

  /// Whether this line has the shape of something that belongs **inside** a frontmatter
  /// region: a `key:` entry, or a `#` comment.
  ///
  /// Offered so a grammar can ask the line *below* an opening `---` to corroborate it. No
  /// rule here uses it; ``FountainGrammar`` does, for the reason stated at its deviation 12,
  /// and ``MarkdownGrammar`` deliberately does not.
  static func looksLikeEntry(_ units: [UInt16]) -> Bool {
    if keyRange(units) != nil { return true }
    var cursor = 0
    while cursor < units.count, isSpaceOrTab(units[cursor]) {
      cursor += 1
    }
    return cursor < units.count && units[cursor] == numberSign
  }

  /// The key's own range within `units` — first non-whitespace character to the `:` — or
  /// `nil` if this line carries no key.
  ///
  /// The single reader of the two rules that decide what a key is, so
  /// ``entryScan(_:endState:)`` and ``looksLikeEntry(_:)`` cannot drift apart: a line the
  /// second calls an entry is a line the first finds a key on.
  private static func keyRange(_ units: [UInt16]) -> Range<Int>? {
    var keyStart = 0
    while keyStart < units.count, isSpaceOrTab(units[keyStart]) {
      keyStart += 1
    }
    // A YAML sequence entry — `- name: bob`. The dash and its space are marker, and the key
    // search resumes after them.
    if keyStart < units.count, units[keyStart] == hyphen,
      keyStart + 1 < units.count, isSpaceOrTab(units[keyStart + 1])
    {
      keyStart += 2
      while keyStart < units.count, isSpaceOrTab(units[keyStart]) {
        keyStart += 1
      }
    }
    // A `#` comment and a blank line are not entries, and neither is a line with no key.
    guard keyStart < units.count, units[keyStart] != numberSign,
      let colonOffset = keySeparator(units, from: keyStart), colonOffset > keyStart
    else {
      return nil
    }
    return keyStart..<colonOffset
  }

  /// The offset of the `:` separating a frontmatter key from its value, or `nil`.
  ///
  /// YAML's rule: the colon must be followed by whitespace or end the line. Without it
  /// `url: https://example.com` would split at `https:` and the key would be `url: https`.
  private static func keySeparator(_ units: [UInt16], from start: Int) -> Int? {
    var cursor = start
    while cursor < units.count {
      if units[cursor] == colon, cursor + 1 == units.count || isSpaceOrTab(units[cursor + 1]) {
        return cursor
      }
      cursor += 1
    }
    return nil
  }
}
