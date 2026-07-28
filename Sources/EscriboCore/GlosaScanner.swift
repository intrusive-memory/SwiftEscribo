/// `<`.
private let lessThan: UInt16 = 0x3C

/// `>`.
private let greaterThan: UInt16 = 0x3E

/// `/`.
private let solidus: UInt16 = 0x2F

/// `=`.
private let equalsSign: UInt16 = 0x3D

/// `"`.
private let doubleQuote: UInt16 = 0x22

/// `'`.
private let singleQuote: UInt16 = 0x27

/// A space.
private let space: UInt16 = 0x20

/// A horizontal tab.
private let tab: UInt16 = 0x09

/// Whether `unit` is a space or a tab — the same two characters ``FountainGrammar``
/// treats as whitespace, and for the same reason: a GLOSA directive's structure is
/// carried by its punctuation, never by any other space character.
private func isSpaceOrTab(_ unit: UInt16) -> Bool { unit == space || unit == tab }

/// Whether `unit` is an ASCII letter, upper or lower case.
///
/// The only character class a tag or attribute name is made of here. No digit, hyphen,
/// or underscore is accepted — the seven tag forms this sortie was asked to support
/// (`breath`, `pause`, `shot`, `include`, `SceneContext`, `Intent`, `Constraint`) are all
/// pure letters, and widening the class is a later sortie's decision to make against a
/// real need, not this one's to guess at.
private func isASCIILetter(_ unit: UInt16) -> Bool {
  (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A)
}

/// Scans GLOSA directives inside a Fountain note's content, structurally.
///
/// ## What this is
///
/// Sortie 15 built the note region and emitted its content as one ``SpanKind/note``
/// span per line-chunk. This subdivides that span — never appends to it, never
/// replaces the ``SpanKind/note`` kind that owns the region — into tag name, attribute
/// name, attribute value, and punctuation spans wherever the content looks like a GLOSA
/// directive, and leaves ordinary note prose exactly as it was.
///
/// ## No semantic validation, anywhere
///
/// This file contains no list of legal tags and no list of legal attributes, and never
/// will (EXECUTION_PLAN.md § Sortie 16, task 3): whether `breath` is a tag ``GlosaCore``
/// recognizes and whether `4s` is a legal length for it is that package's business.
/// Every ASCII-letter run where a tag or attribute name is structurally expected is
/// scanned as one, recognized or not — the same "unknown kinds fall back, never fail"
/// contract every ``SpanKind`` in this package already keeps.
///
/// ## Scope: one content chunk, no cross-line state
///
/// A directive must open and close within the chunk it is handed — this scanner carries
/// no state across lines and adds none to ``LineState``, because Sortie 15 already
/// decided a note's content arrives as one span per line and this sortie only
/// subdivides it. A `<tag` whose `>` never arrives before the chunk ends is exactly the
/// malformed case task 4 describes, and it degrades to ``SpanKind/text`` like every
/// other malformed construct in this scanner — it does not throw, does not return
/// `nil`, and does not leave a gap.
///
/// ## Totality
///
/// ``scan(_:in:base:)`` always returns spans that tile `range` **exactly**: every code
/// unit in `range` is either GLOSA structure, GLOSA punctuation, malformed markup
/// degraded to `.text`, or ordinary note prose. There is no gap for the caller — or the
/// gate's ``SpanTiling`` — to fill, and that matters here specifically: a gap inside a
/// note's content would be filled with `.text`, silently overwriting prose that was
/// never meant to look like markup.
enum GlosaScanner {

  /// One parsed — or malformed-and-recovered — directive, and where the chunk
  /// continues after it.
  private struct DirectiveScan {
    let spans: [EscriboSpan]
    let end: Int
  }

  /// Structurally subdivides `units[range]` — a note's content on one line, in
  /// line-relative coordinates, exactly as ``FountainGrammar`` hands every other span
  /// layout in this package — into GLOSA spans, falling back to ``SpanKind/note`` for
  /// the prose around and between directives.
  ///
  /// - Parameters:
  ///   - units: The line's content code units (line-relative).
  ///   - range: The chunk to scan, indexing `units`. The note's own `[[`/`]]` markers
  ///     are never part of this range — ``FountainGrammar`` has already excluded them.
  ///   - base: The document offset `units[0]` sits at, so every returned span carries
  ///     document coordinates like every other span this package emits.
  /// - Returns: Spans that tile `range` exactly, in ascending order.
  static func scan(_ units: [UInt16], in range: Range<Int>, base: Int) -> [EscriboSpan] {
    guard !range.isEmpty else { return [] }

    var spans: [EscriboSpan] = []
    var cursor = range.lowerBound
    var proseStart = range.lowerBound

    func flushProse(upTo end: Int) {
      guard end > proseStart else { return }
      spans.append(EscriboSpan(range: (base + proseStart)..<(base + end), kind: .note))
    }

    while cursor < range.upperBound {
      guard units[cursor] == lessThan else {
        cursor += 1
        continue
      }
      guard let directive = scanDirective(units, from: cursor, limit: range.upperBound, base: base)
      else {
        // Not a plausible directive start at all — a bare `<` in prose. Leave it for
        // the prose run to pick up and keep looking one code unit further on.
        cursor += 1
        continue
      }
      flushProse(upTo: cursor)
      spans.append(contentsOf: directive.spans)
      cursor = directive.end
      proseStart = cursor
    }
    flushProse(upTo: range.upperBound)
    return spans
  }

  /// Attempts to parse the directive opening at `start`, which must index a `<`.
  ///
  /// Returns `nil` only when `start` cannot plausibly begin a directive — a `<`
  /// followed by whitespace, a digit, or nothing at all — which the caller then folds
  /// into ordinary note prose rather than markup, the same judgment call every other
  /// forcing character in ``FountainGrammar`` makes about what counts as an attempt.
  ///
  /// Anything that clears that bar and then goes wrong is **not** `nil`: it is a
  /// ``DirectiveScan`` whose spans are ``SpanKind/text``, per task 4.
  private static func scanDirective(
    _ units: [UInt16], from start: Int, limit: Int, base: Int
  ) -> DirectiveScan? {
    var offset = start + 1
    var closing = false
    if offset < limit, units[offset] == solidus {
      closing = true
      offset += 1
    }

    let nameStart = offset
    while offset < limit, isASCIILetter(units[offset]) {
      offset += 1
    }
    guard offset > nameStart else { return nil }
    let nameEnd = offset

    var spans: [EscriboSpan] = [
      EscriboSpan(range: (base + start)..<(base + nameStart), kind: .glosaPunctuation, role: .marker),
      EscriboSpan(range: (base + nameStart)..<(base + nameEnd), kind: .glosaTag),
    ]

    if closing {
      return closeClosingTag(units, nameEnd: nameEnd, start: start, limit: limit, base: base, spans: spans)
    }

    // Attributes, zero or more, each `name = "value"` with arbitrary whitespace around
    // the `=`, until the tag's own closer arrives.
    offset = nameEnd
    while true {
      let beforeToken = offset
      while offset < limit, isSpaceOrTab(units[offset]) {
        offset += 1
      }
      guard offset < limit else {
        return malformed(units, from: start, to: limit, base: base)
      }

      if units[offset] == solidus, offset + 1 < limit, units[offset + 1] == greaterThan {
        if offset > beforeToken {
          spans.append(
            EscriboSpan(
              range: (base + beforeToken)..<(base + offset), kind: .glosaPunctuation, role: .marker)
          )
        }
        spans.append(
          EscriboSpan(
            range: (base + offset)..<(base + offset + 2), kind: .glosaPunctuation, role: .marker))
        return DirectiveScan(spans: spans, end: offset + 2)
      }
      if units[offset] == greaterThan {
        if offset > beforeToken {
          spans.append(
            EscriboSpan(
              range: (base + beforeToken)..<(base + offset), kind: .glosaPunctuation, role: .marker)
          )
        }
        spans.append(
          EscriboSpan(
            range: (base + offset)..<(base + offset + 1), kind: .glosaPunctuation, role: .marker))
        return DirectiveScan(spans: spans, end: offset + 1)
      }
      guard isASCIILetter(units[offset]) else {
        return malformed(units, from: start, to: limit, base: base)
      }
      // Whitespace ahead of an attribute is punctuation — it separates the previous
      // token from this one and carries no meaning of its own.
      if offset > beforeToken {
        spans.append(
          EscriboSpan(
            range: (base + beforeToken)..<(base + offset), kind: .glosaPunctuation, role: .marker))
      }

      let attrNameStart = offset
      while offset < limit, isASCIILetter(units[offset]) {
        offset += 1
      }
      let attrNameEnd = offset
      spans.append(
        EscriboSpan(range: (base + attrNameStart)..<(base + attrNameEnd), kind: .glosaAttributeName)
      )

      while offset < limit, isSpaceOrTab(units[offset]) {
        offset += 1
      }
      guard offset < limit, units[offset] == equalsSign else {
        return malformed(units, from: start, to: limit, base: base)
      }
      offset += 1
      while offset < limit, isSpaceOrTab(units[offset]) {
        offset += 1
      }
      guard offset < limit, units[offset] == doubleQuote || units[offset] == singleQuote else {
        return malformed(units, from: start, to: limit, base: base)
      }
      let quote = units[offset]
      // Everything from the end of the attribute name through the opening quote —
      // whitespace, `=`, whitespace, the quote itself — is one punctuation span. None
      // of it belongs to the name or to the value it introduces.
      spans.append(
        EscriboSpan(
          range: (base + attrNameEnd)..<(base + offset + 1), kind: .glosaPunctuation, role: .marker)
      )
      offset += 1

      let valueStart = offset
      while offset < limit, units[offset] != quote {
        offset += 1
      }
      guard offset < limit else {
        return malformed(units, from: start, to: limit, base: base)
      }
      if offset > valueStart {
        spans.append(
          EscriboSpan(range: (base + valueStart)..<(base + offset), kind: .glosaAttributeValue))
      }
      spans.append(
        EscriboSpan(
          range: (base + offset)..<(base + offset + 1), kind: .glosaPunctuation, role: .marker))
      offset += 1
    }
  }

  /// Finishes parsing a closing tag — `</tag>` — once its name has been read. Only
  /// whitespace and the closing `>` may follow: a closing tag carries no attributes.
  private static func closeClosingTag(
    _ units: [UInt16], nameEnd: Int, start: Int, limit: Int, base: Int, spans: [EscriboSpan]
  ) -> DirectiveScan {
    var spans = spans
    var offset = nameEnd
    let beforeClose = offset
    while offset < limit, isSpaceOrTab(units[offset]) {
      offset += 1
    }
    guard offset < limit, units[offset] == greaterThan else {
      return malformed(units, from: start, to: limit, base: base)
    }
    if offset > beforeClose {
      spans.append(
        EscriboSpan(
          range: (base + beforeClose)..<(base + offset), kind: .glosaPunctuation, role: .marker))
    }
    spans.append(
      EscriboSpan(range: (base + offset)..<(base + offset + 1), kind: .glosaPunctuation, role: .marker)
    )
    return DirectiveScan(spans: spans, end: offset + 1)
  }

  /// The malformed-recovery span: everything from `start` to the next `>` in range
  /// (inclusive of it), or to `limit` if there is none, collapsed to a single
  /// ``SpanKind/text`` span.
  ///
  /// Task 4: malformed GLOSA degrades to `.text` rather than failing. Recovering at the
  /// next `>` — rather than at `limit` unconditionally — is what keeps one broken
  /// directive from swallowing the rest of the note; running to `limit` when no `>`
  /// exists at all is the same "unterminated construct runs to the end" rule
  /// ``FountainGrammar`` already applies to an unterminated note or boneyard.
  private static func malformed(
    _ units: [UInt16], from start: Int, to limit: Int, base: Int
  ) -> DirectiveScan {
    var end = start
    while end < limit, units[end] != greaterThan {
      end += 1
    }
    if end < limit { end += 1 }
    return DirectiveScan(
      spans: [EscriboSpan(range: (base + start)..<(base + end), kind: .text)], end: end)
  }
}
