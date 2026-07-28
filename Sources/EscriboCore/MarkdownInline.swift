/// `\`.
private let backslash: UInt16 = 0x5C

/// `` ` ``.
private let backtick: UInt16 = 0x60

/// `*`.
private let asterisk: UInt16 = 0x2A

/// `_`.
private let underscore: UInt16 = 0x5F

/// `~`.
private let tilde: UInt16 = 0x7E

/// `@`.
private let atSign: UInt16 = 0x40

/// `.`.
private let fullStop: UInt16 = 0x2E

/// `+`.
private let plusSign: UInt16 = 0x2B

/// `-`.
private let hyphen: UInt16 = 0x2D

/// `:`.
private let colon: UInt16 = 0x3A

/// `[`.
private let leftBracket: UInt16 = 0x5B

/// `]`.
private let rightBracket: UInt16 = 0x5D

/// `(`.
private let leftParenthesis: UInt16 = 0x28

/// `)`.
private let rightParenthesis: UInt16 = 0x29

/// `!`.
private let exclamationMark: UInt16 = 0x21

/// `<`.
private let lessThan: UInt16 = 0x3C

/// `>`.
private let greaterThan: UInt16 = 0x3E

/// `"`.
private let quotationMark: UInt16 = 0x22

/// `'`.
private let apostrophe: UInt16 = 0x27

/// A space.
private let space: UInt16 = 0x20

/// A horizontal tab.
private let tab: UInt16 = 0x09

/// The first UTF-16 code unit of the high-surrogate range.
private let highSurrogateFirst: UInt16 = 0xD800

/// The last UTF-16 code unit of the high-surrogate range.
private let highSurrogateLast: UInt16 = 0xDBFF

/// The first UTF-16 code unit of the low-surrogate range.
private let lowSurrogateFirst: UInt16 = 0xDC00

/// The last UTF-16 code unit of the low-surrogate range.
private let lowSurrogateLast: UInt16 = 0xDFFF

private func isSpaceOrTab(_ unit: UInt16) -> Bool { unit == space || unit == tab }

/// Whether `unit` is one of CommonMark's ASCII punctuation characters.
///
/// ASCII only, and deliberately so: deciding Unicode general categories without importing
/// Foundation would mean shipping a category table, and the flanking rules only consult
/// punctuation to break ties around a delimiter. The consequence is stated where it
/// matters — ``MarkdownInline``'s doc comment — rather than hidden here.
private func isASCIIPunctuation(_ unit: UInt16) -> Bool {
  switch unit {
  case 0x21...0x2F, 0x3A...0x40, 0x5B...0x60, 0x7B...0x7E: return true
  default: return false
  }
}

/// Whether `unit` is whitespace for the purposes of the flanking rules.
///
/// ASCII whitespace plus the Unicode space separators a document plausibly contains. A
/// non-breaking space that counted as an ordinary character would make `*x* ` and
/// `*x*\u{00A0}` flank differently, which is the sort of difference nobody debugs.
private func isUnicodeWhitespace(_ unit: UInt16) -> Bool {
  switch unit {
  case 0x09...0x0D, 0x20, 0x00A0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F,
    0x3000:
    return true
  default: return false
  }
}

/// Whether `unit` is an ASCII letter.
private func isASCIILetter(_ unit: UInt16) -> Bool {
  (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A)
}

/// Whether `unit` is an ASCII digit.
private func isASCIIDigit(_ unit: UInt16) -> Bool { unit >= 0x30 && unit <= 0x39 }

private func isHighSurrogate(_ unit: UInt16) -> Bool {
  unit >= highSurrogateFirst && unit <= highSurrogateLast
}

private func isLowSurrogate(_ unit: UInt16) -> Bool {
  unit >= lowSurrogateFirst && unit <= lowSurrogateLast
}

// MARK: - The per-code-unit attribute

/// What one code unit of a line ends up carrying, before the run-length encode.
///
/// The inline scanner is an **attribute painter**, not a tree builder. Every construct it
/// recognizes ORs its style bit over a range and stamps its kind and role over the
/// delimiters, and consecutive code units carrying identical attributes become one span.
/// That is the whole of "flattened at scan time, never a tree": there is no node to
/// flatten, because nesting is expressed as overlapping paint and the union falls out of
/// `|=`.
///
/// Four bytes wide, and it matters: one of these exists per code unit of the line being
/// scanned, allocated only when the line actually contains inline syntax.
private struct InlineAttribute: Equatable {
  /// The ``StyleSet`` bitfield accumulated over this code unit.
  var style: UInt16 = 0

  /// Which ``SpanKind`` this code unit belongs to, as a small code — see
  /// ``InlineKindCode``. Zero means "whatever kind the enclosing block has", which is why
  /// a code span inside a heading stays a heading.
  var kindCode: UInt8 = 0

  /// Whether this code unit is delimiter syntax rather than content.
  var isMarker: Bool = false
}

/// The ``SpanKind`` values the inline scanner can stamp, as one byte.
///
/// A byte rather than a `SpanKind` because a `SpanKind` holds a `String`: one per code
/// unit would put a retain and a release on every character of every line scanned.
private enum InlineKindCode {
  /// Inherit the enclosing block's kind.
  static let inherited: UInt8 = 0
  static let link: UInt8 = 1
  static let linkURL: UInt8 = 2
  static let linkTitle: UInt8 = 3
  static let image: UInt8 = 4

  static func kind(_ code: UInt8, inheriting inherited: SpanKind) -> SpanKind {
    switch code {
    case link: return .link
    case linkURL: return .linkURL
    case linkTitle: return .linkTitle
    case image: return .image
    default: return inherited
    }
  }
}

// MARK: - The entry point

/// CommonMark **inline** structure: emphasis, strong emphasis, code spans, links, images,
/// hard breaks, autolinks, and GFM strikethrough — flattened into consecutive tiling
/// spans.
///
/// ## The output shape, which is the point
///
/// Nesting is resolved here and nowhere else. `` **bold `code` bold** `` comes back as
/// consecutive spans, the middle one carrying `[.strong, .inlineCode]` — the **union** of
/// every construct covering it. There is no tree, no node type, and nothing for the styler
/// to walk: it reads `(kind, style, role)` off a span and resolves attributes once
/// (REQUIREMENTS.md § Two axes).
///
/// Every delimiter is emitted as a ``SpanRole/marker`` span carrying the **same** kind and
/// style as the content it wraps, so "the asterisks show, dimmed, while the word renders
/// bold" is a property of the data rather than a case in the styler.
///
/// ## Hand-written, per the charter
///
/// Every decision is a code-unit comparison. There is no regex here and there never will
/// be (AGENTS.md).
///
/// ## Two axes, and why a code span does not get its own kind
///
/// ``StyleSet/inlineCode`` already exists on the style axis, and the theme's composition
/// order (REQUIREMENTS.md § Composition order) says a style flag swaps the font family
/// while the *kind* supplies color and size scale. A code span therefore keeps the
/// enclosing block's kind and only adds ``StyleSet/inlineCode``, which is exactly what
/// makes "a code span inside a bold heading renders bold-mono **at heading size**" true.
/// Giving it a `.codeSpan` kind would override the heading's size scale and render it at
/// body size — the defect that document names in so many words.
///
/// A link destination has no such flag, and it is the one thing the sortie brief names by
/// hand (`.linkURL`), so ``SpanKind/link``, ``SpanKind/linkURL``, ``SpanKind/linkTitle``,
/// and ``SpanKind/image`` **do** override the enclosing kind. The consequence, stated
/// plainly: a link inside a heading is painted as a link, not as heading-sized text.
/// `depth` and paragraph geometry are per-line and unaffected.
///
/// ## What this deliberately does not do
///
/// - **Emphasis does not cross a line.** This is a line grammar
///   (``LineGrammar``): `(state, line) -> (spans, state)` is what makes "resume from line
///   *n*" meaningful, and CommonMark resolves emphasis over a whole paragraph. A `**` on
///   one line and its partner on the next therefore do not pair. Doing better needs
///   paragraph-wide inline state, which is a change to the *shape* of the grammar seam and
///   not to this file.
/// - **Reference links are not resolved.** `[text][ref]` and `[text]` need the document's
///   link reference definitions, which is document-wide state. They scan as literal text.
/// - **Punctuation is ASCII for the flanking rules.** See ``isASCIIPunctuation(_:)``.
/// - **A hard break is emitted wherever its syntax appears**, including on the last line of
///   a paragraph, where CommonMark says it is not one. Knowing it is the last line is
///   lookahead this grammar does not have.
/// - **Autolinks are the bracketed form only** — `<https://example.com>` and
///   `<user@example.com>`, which is CommonMark's. GFM's *extended* autolink, which turns a
///   bare `www.example.com` or `https://example.com` in running text into a link, is
///   deliberately not here: it needs trailing-punctuation trimming, a parenthesis-balance
///   rule, and a preceding-character rule, each of which changes where a span *ends* on
///   ordinary prose that contains a dot. Adding it is a self-contained piece of work with
///   its own tests, and doing it inside a sortie whose subject is frontmatter would put a
///   whole new failure surface on lines that have no link syntax in them at all.
///
/// ## Strikethrough is emphasis, in the same matcher
///
/// GFM's `~~struck~~` runs through the identical delimiter-run machinery `*` and `_` use,
/// with three differences and no fourth: a `~` run longer than two is literal, an opener
/// and a closer must be the **same length** (`~x~~` is not strikethrough), and the rule of
/// three does not apply — it is CommonMark's tie-breaker for emphasis, and GFM's tildes are
/// not emphasis. Reusing the matcher rather than adding a second pass is what keeps
/// `**~~both~~**` coming back as one span carrying `[.strong, .strikethrough]` for free:
/// the union is already how this file works.
///
/// ## Surrogate pairs
///
/// No span boundary this file emits can fall between a high and a low surrogate. Two
/// independent reasons, and both are deliberate: every construct recognized here is
/// delimited by ASCII, so an attribute change can only occur at an ASCII code unit; and
/// ``encode(base:kind:)`` extends a run past a low surrogate regardless. ``SpanTiling`` is
/// a third backstop. Depending on the tiler alone would make the guarantee somebody else's,
/// which is how it gets lost.
enum MarkdownInline {

  /// Scans `range` of `units` for inline structure.
  ///
  /// - Parameters:
  ///   - units: The **whole line's** content code units. `units[0]` sits at document
  ///     offset `base`.
  ///   - range: The sub-range of `units` to scan — a block's content, with its indent and
  ///     block markers already removed by the caller.
  ///   - base: The document offset `units[0]` sits at.
  ///   - kind: The enclosing block's ``SpanKind``. Every span that is not a link, image, or
  ///     hard break carries it, which is what keeps a heading's content heading-colored
  ///     whatever emphasis is inside it.
  ///   - allowsHardBreak: Whether a trailing two-space run or trailing backslash is a hard
  ///     break. False inside an ATX heading, which CommonMark says has none.
  /// - Returns: Ordered, non-overlapping spans **exactly tiling** `base + range`. Empty
  ///   only when `range` is.
  static func spans(
    in units: [UInt16],
    range: Range<Int>,
    base: Int,
    kind: SpanKind,
    allowsHardBreak: Bool
  ) -> [EscriboSpan] {
    guard !range.isEmpty else { return [] }

    // A hard break is decided before the walk and removed from it, so the walk never has
    // to reason about whether a trailing backslash was itself escaped: an even-length
    // backslash run ends in an escaped backslash and is not a break, and that is settled
    // by counting rather than by unwinding the walk.
    let hardBreak = allowsHardBreak ? hardBreakRange(units, range) : nil
    let body = range.lowerBound..<(hardBreak?.lowerBound ?? range.upperBound)

    var spans: [EscriboSpan] = []
    if !body.isEmpty {
      if containsInlineSyntax(units, body) {
        var walk = InlineWalk(units: units, range: body)
        walk.run()
        spans = walk.encode(base: base, kind: kind)
      } else {
        spans.append(
          EscriboSpan(range: (base + body.lowerBound)..<(base + body.upperBound), kind: kind))
      }
    }
    if let hardBreak {
      spans.append(
        EscriboSpan(
          range: (base + hardBreak.lowerBound)..<(base + hardBreak.upperBound),
          kind: .hardBreak,
          role: .marker))
    }
    return spans
  }

  /// The trailing run that makes this content end in a hard break, or `nil`.
  ///
  /// Two spellings, per CommonMark: two or more trailing spaces, or a single trailing
  /// backslash. Both require something before them — a line of nothing but spaces is a
  /// blank line, never a break.
  private static func hardBreakRange(_ units: [UInt16], _ range: Range<Int>) -> Range<Int>? {
    guard range.count >= 2 else { return nil }

    var runStart = range.upperBound
    while runStart > range.lowerBound, units[runStart - 1] == space {
      runStart -= 1
    }
    if range.upperBound - runStart >= 2, runStart > range.lowerBound {
      return runStart..<range.upperBound
    }

    guard units[range.upperBound - 1] == backslash else { return nil }
    var runStartOfBackslashes = range.upperBound
    while runStartOfBackslashes > range.lowerBound, units[runStartOfBackslashes - 1] == backslash {
      runStartOfBackslashes -= 1
    }
    // An even run is escaped backslashes ending in a literal `\`; an odd one leaves a lone
    // unescaped backslash at the end, which is the break.
    guard (range.upperBound - runStartOfBackslashes) % 2 == 1 else { return nil }
    guard range.upperBound - 1 > range.lowerBound else { return nil }
    return (range.upperBound - 1)..<range.upperBound
  }

  /// Whether `range` contains any character that could begin an inline construct.
  ///
  /// The fast path exists because most lines of most documents contain none, and the walk
  /// allocates one attribute per code unit. Linear, no allocation, and it answers `false`
  /// for the common case before anything is allocated at all.
  private static func containsInlineSyntax(_ units: [UInt16], _ range: Range<Int>) -> Bool {
    for offset in range {
      switch units[offset] {
      case asterisk, underscore, backtick, leftBracket, backslash, tilde, lessThan: return true
      default: continue
      }
    }
    return false
  }
}

// MARK: - Delimiter runs

/// One maximal run of `*`, `_`, or `~`, with the two questions CommonMark asks of it.
private struct DelimiterRun {
  /// Where the run starts, as an index into the line's units.
  let start: Int

  /// How long the run is. Never changes; ``remaining`` is what the matcher spends, and the
  /// **original** length is what the rule of three and GFM's tilde length rule both read.
  let length: Int

  /// `*`, `_`, or `~`.
  let character: UInt16

  /// Whether this run may open emphasis.
  let canOpen: Bool

  /// Whether this run may close emphasis.
  let canClose: Bool

  /// How many of the run's delimiters are still unspent.
  ///
  /// An opener spends from its **right** end and a closer from its **left**, which is why
  /// a count is enough to locate what was spent: the spent delimiters are always the ones
  /// nearest the content.
  var remaining: Int
}

/// A `[` or `![` waiting for its `]`.
private struct BracketOpener {
  /// Where the `[` or `!` sits.
  let start: Int

  /// Where the bracketed text begins — one past `[`, two past `![`.
  let textStart: Int

  /// Whether this opener was `![`.
  let isImage: Bool

  /// How many delimiter runs had been collected when this bracket opened.
  ///
  /// Emphasis inside link text is resolved when the link closes, with this as the stack
  /// bottom, and the delimiters above it are then retired. That is what stops a `*` inside
  /// link text from pairing with one outside it — brackets bound emphasis in CommonMark,
  /// and a flat painter would otherwise happily paint across the boundary.
  let delimiterCount: Int
}

/// A successfully parsed `(destination "title")`.
private struct InlineDestination {
  /// The `(`.
  let open: Int

  /// The `)`.
  let close: Int

  /// The destination text, excluding any `<`…`>`.
  let destination: Range<Int>

  /// The title including its quotes, and the title text inside them.
  let title: (outer: Range<Int>, inner: Range<Int>)?
}

// MARK: - The walk

/// The linear pass plus the emphasis matcher.
///
/// Structured as a value with stored state rather than one long function because the
/// emphasis matcher runs **twice** in the general case — once when a link closes, over the
/// delimiters inside its text, and once at the end over everything else — and both calls
/// paint into the same attribute array.
private struct InlineWalk {
  let units: [UInt16]
  let range: Range<Int>
  var attributes: [InlineAttribute]
  var delimiters: [DelimiterRun] = []
  var brackets: [BracketOpener] = []

  init(units: [UInt16], range: Range<Int>) {
    self.units = units
    self.range = range
    self.attributes = [InlineAttribute](repeating: InlineAttribute(), count: range.count)
  }

  private func slot(_ offset: Int) -> Int { offset - range.lowerBound }

  // MARK: The linear pass

  mutating func run() {
    var cursor = range.lowerBound
    while cursor < range.upperBound {
      let unit = units[cursor]

      if unit == backslash {
        // A backslash escape is two code units and neither is syntax afterwards, which is
        // the whole reason `\*` never opens emphasis: the walk steps over the `*` before
        // the delimiter collector can ever see it.
        if cursor + 1 < range.upperBound, isASCIIPunctuation(units[cursor + 1]) {
          attributes[slot(cursor)].isMarker = true
          cursor += 2
        } else {
          cursor += 1
        }
        continue
      }
      if unit == backtick {
        cursor = scanCodeSpan(from: cursor)
        continue
      }
      if unit == exclamationMark, cursor + 1 < range.upperBound,
        units[cursor + 1] == leftBracket
      {
        brackets.append(
          BracketOpener(
            start: cursor, textStart: cursor + 2, isImage: true,
            delimiterCount: delimiters.count))
        cursor += 2
        continue
      }
      if unit == leftBracket {
        brackets.append(
          BracketOpener(
            start: cursor, textStart: cursor + 1, isImage: false,
            delimiterCount: delimiters.count))
        cursor += 1
        continue
      }
      if unit == rightBracket {
        cursor = closeBracket(at: cursor)
        continue
      }
      if unit == lessThan {
        // An autolink is settled here and painted here; it never reaches the delimiter
        // machinery, and a `<` that does not open one is ordinary text.
        if let end = scanAutolink(from: cursor) {
          cursor = end
          continue
        }
        cursor += 1
        continue
      }
      if unit == asterisk || unit == underscore || unit == tilde {
        cursor = collectDelimiterRun(at: cursor)
        continue
      }
      cursor += 1
    }
    processEmphasis(stackBottom: 0)
  }

  // MARK: Autolinks

  /// Scans `<https://example.com>` or `<user@example.com>` starting at the `<`, painting
  /// it if it is one. Returns where scanning resumes, or `nil` if this `<` opens nothing.
  ///
  /// The angle brackets are ``SpanRole/marker`` and the URI is content, both carrying
  /// ``SpanKind/linkURL`` — the same kind an inline link's destination gets, because what a
  /// theme wants to do to one destination it wants to do to both.
  private mutating func scanAutolink(from start: Int) -> Int? {
    var close = start + 1
    while close < range.upperBound, units[close] != greaterThan {
      let unit = units[close]
      // No whitespace and no `<` inside an autolink, per CommonMark. Control characters
      // are excluded by the same test, which is why it is written as a range.
      if unit == lessThan || unit <= space { return nil }
      close += 1
    }
    guard close < range.upperBound, close > start + 1 else { return nil }

    let inner = (start + 1)..<close
    guard isURIAutolink(inner) || isEmailAutolink(inner) else { return nil }

    for offset in start...close {
      attributes[slot(offset)].kindCode = InlineKindCode.linkURL
      attributes[slot(offset)].isMarker = true
    }
    for offset in inner {
      attributes[slot(offset)].isMarker = false
    }
    return close + 1
  }

  /// Whether `inner` is an absolute URI: a scheme of 2–32 characters starting with a
  /// letter and continuing with letters, digits, `+`, `-`, or `.`, then a `:`.
  ///
  /// Everything after the colon is already known to contain no whitespace and no `<`,
  /// which is the whole of what CommonMark asks of it.
  private func isURIAutolink(_ inner: Range<Int>) -> Bool {
    guard isASCIILetter(units[inner.lowerBound]) else { return false }
    var cursor = inner.lowerBound + 1
    while cursor < inner.upperBound {
      let unit = units[cursor]
      if unit == colon { break }
      guard
        isASCIILetter(unit) || isASCIIDigit(unit) || unit == plusSign || unit == hyphen
          || unit == fullStop
      else { return false }
      cursor += 1
    }
    guard cursor < inner.upperBound, units[cursor] == colon else { return false }
    let schemeLength = cursor - inner.lowerBound
    return schemeLength >= 2 && schemeLength <= 32
  }

  /// Whether `inner` is an email address: a non-empty local part, one `@`, and a domain of
  /// dot-separated labels of letters, digits, and interior hyphens.
  ///
  /// A hand-written approximation of CommonMark's email regex, and approximate on purpose:
  /// the exact grammar exists to reject addresses a mail server would, and this one exists
  /// to decide whether to paint a span. Getting it slightly wide costs a link where a reader
  /// wrote something that looks exactly like an address.
  private func isEmailAutolink(_ inner: Range<Int>) -> Bool {
    var at = -1
    for offset in inner where units[offset] == atSign {
      // More than one `@` is not an address.
      if at >= 0 { return false }
      at = offset
    }
    guard at > inner.lowerBound, at + 1 < inner.upperBound else { return false }

    for offset in inner.lowerBound..<at {
      let unit = units[offset]
      guard isASCIILetter(unit) || isASCIIDigit(unit) || isEmailLocalPunctuation(unit) else {
        return false
      }
    }

    var labelLength = 0
    var cursor = at + 1
    var sawDot = false
    while cursor < inner.upperBound {
      let unit = units[cursor]
      if unit == fullStop {
        guard labelLength > 0, units[cursor - 1] != hyphen else { return false }
        sawDot = true
        labelLength = 0
        cursor += 1
        continue
      }
      if unit == hyphen {
        guard labelLength > 0 else { return false }
      } else {
        guard isASCIILetter(unit) || isASCIIDigit(unit) else { return false }
      }
      labelLength += 1
      guard labelLength <= 63 else { return false }
      cursor += 1
    }
    return sawDot && labelLength > 0 && units[inner.upperBound - 1] != hyphen
  }

  /// The ASCII punctuation CommonMark allows in an email local part.
  private func isEmailLocalPunctuation(_ unit: UInt16) -> Bool {
    switch unit {
    case 0x2E, 0x21, 0x23, 0x24, 0x25, 0x26, 0x27, 0x2A, 0x2B, 0x2F, 0x3D, 0x3F, 0x5E, 0x5F,
      0x60, 0x7B, 0x7C, 0x7D, 0x7E, 0x2D:
      return true
    default: return false
    }
  }

  // MARK: Code spans

  /// Scans a backtick run and, if it has a partner of exactly the same length, the code
  /// span it opens. Returns where scanning resumes.
  ///
  /// "Exactly the same length" is CommonMark and is why backtick runs of arbitrary length
  /// work: `` `` ` `` `` is a code span containing a backtick because the two-backtick
  /// opener is closed only by a two-backtick run, and the lone backtick inside is content.
  private mutating func scanCodeSpan(from start: Int) -> Int {
    var openEnd = start
    while openEnd < range.upperBound, units[openEnd] == backtick {
      openEnd += 1
    }
    let length = openEnd - start

    var probe = openEnd
    while probe < range.upperBound {
      guard units[probe] == backtick else {
        probe += 1
        continue
      }
      var closeEnd = probe
      while closeEnd < range.upperBound, units[closeEnd] == backtick {
        closeEnd += 1
      }
      if closeEnd - probe == length {
        // The delimiters carry the same style as the content, differing only in role —
        // the one rule every marker in this package obeys.
        for offset in start..<closeEnd {
          attributes[slot(offset)].style |= StyleSet.inlineCode.rawValue
        }
        for offset in start..<openEnd {
          attributes[slot(offset)].isMarker = true
        }
        for offset in probe..<closeEnd {
          attributes[slot(offset)].isMarker = true
        }
        return closeEnd
      }
      probe = closeEnd
    }
    // No partner: the run is literal text, and — importantly — the scan resumes *after*
    // it, so the same run is not reconsidered as an opener on the next iteration.
    return openEnd
  }

  // MARK: Links and images

  /// Handles a `]`. Returns where scanning resumes.
  private mutating func closeBracket(at offset: Int) -> Int {
    guard let opener = brackets.popLast() else { return offset + 1 }
    guard offset + 1 < range.upperBound, units[offset + 1] == leftParenthesis,
      let destination = parseDestination(from: offset + 1)
    else {
      // No inline destination. A reference link would be resolved here if this package
      // carried link reference definitions; it does not, so the brackets are literal.
      return offset + 1
    }

    let kindCode = opener.isImage ? InlineKindCode.image : InlineKindCode.link
    for slotOffset in opener.start..<opener.textStart {
      attributes[slot(slotOffset)].kindCode = kindCode
      attributes[slot(slotOffset)].isMarker = true
    }
    for slotOffset in opener.textStart..<offset
    where attributes[slot(slotOffset)].kindCode == InlineKindCode.inherited {
      // Kind only, and only where nothing more specific already sits: the text may already
      // carry emphasis or code-span style, and a nested image's own kinds outrank the
      // enclosing link's. The union is the model; overwriting is not.
      attributes[slot(slotOffset)].kindCode = kindCode
    }
    attributes[slot(offset)].kindCode = kindCode
    attributes[slot(offset)].isMarker = true

    // Everything from `(` to `)` is URL syntax unless it is the destination or the title,
    // so paint it all as marker first and carve the content out of it. That ordering is
    // what keeps the region contiguous — no gap for `SpanTiling` to fill with `.text`.
    for slotOffset in destination.open...destination.close {
      attributes[slot(slotOffset)].kindCode = InlineKindCode.linkURL
      attributes[slot(slotOffset)].isMarker = true
    }
    for slotOffset in destination.destination {
      attributes[slot(slotOffset)].isMarker = false
    }
    if let title = destination.title {
      for slotOffset in title.outer {
        attributes[slot(slotOffset)].kindCode = InlineKindCode.linkTitle
      }
      for slotOffset in title.inner {
        attributes[slot(slotOffset)].isMarker = false
      }
    }

    // Brackets bound emphasis: resolve what is inside this one now, then retire it.
    processEmphasis(stackBottom: opener.delimiterCount)
    if opener.delimiterCount < delimiters.count {
      delimiters.removeSubrange(opener.delimiterCount...)
    }
    return destination.close + 1
  }

  /// Parses `(destination)` or `(destination "title")` starting at the `(`, or returns
  /// `nil` if what follows is not one.
  private func parseDestination(from openParenthesis: Int) -> InlineDestination? {
    var cursor = openParenthesis + 1
    while cursor < range.upperBound, isSpaceOrTab(units[cursor]) {
      cursor += 1
    }

    let destination: Range<Int>
    if cursor < range.upperBound, units[cursor] == lessThan {
      var probe = cursor + 1
      while probe < range.upperBound, units[probe] != greaterThan {
        if units[probe] == lessThan { return nil }
        if units[probe] == backslash, probe + 1 < range.upperBound {
          probe += 2
          continue
        }
        probe += 1
      }
      guard probe < range.upperBound else { return nil }
      destination = (cursor + 1)..<probe
      cursor = probe + 1
    } else {
      let start = cursor
      var depth = 0
      while cursor < range.upperBound {
        let unit = units[cursor]
        if unit == backslash, cursor + 1 < range.upperBound {
          cursor += 2
          continue
        }
        if isSpaceOrTab(unit) { break }
        if unit == leftParenthesis {
          depth += 1
          cursor += 1
          continue
        }
        if unit == rightParenthesis {
          if depth == 0 { break }
          depth -= 1
          cursor += 1
          continue
        }
        cursor += 1
      }
      destination = start..<cursor
    }

    let afterDestination = cursor
    while cursor < range.upperBound, isSpaceOrTab(units[cursor]) {
      cursor += 1
    }

    var title: (outer: Range<Int>, inner: Range<Int>)?
    // A title must be separated from the destination by whitespace; without that rule
    // `[a](b"c")` would parse a title out of the middle of a URL.
    if cursor > afterDestination, cursor < range.upperBound {
      let opening = units[cursor]
      if opening == quotationMark || opening == apostrophe || opening == leftParenthesis {
        let closing = opening == leftParenthesis ? rightParenthesis : opening
        var probe = cursor + 1
        while probe < range.upperBound, units[probe] != closing {
          if units[probe] == backslash, probe + 1 < range.upperBound {
            probe += 2
            continue
          }
          probe += 1
        }
        guard probe < range.upperBound else { return nil }
        title = (outer: cursor..<(probe + 1), inner: (cursor + 1)..<probe)
        cursor = probe + 1
        while cursor < range.upperBound, isSpaceOrTab(units[cursor]) {
          cursor += 1
        }
      }
    }

    guard cursor < range.upperBound, units[cursor] == rightParenthesis else { return nil }
    return InlineDestination(
      open: openParenthesis, close: cursor, destination: destination, title: title)
  }

  // MARK: Emphasis

  /// Collects one maximal run of `*` or `_` and records what it may do. Returns where
  /// scanning resumes.
  ///
  /// The flanking rules are CommonMark's verbatim, and the `_` clauses are the ones worth
  /// keeping: without them `snake_case_name` becomes `snake<em>case</em>name`, which is
  /// the single most complained-about Markdown misrender there is.
  private mutating func collectDelimiterRun(at start: Int) -> Int {
    let character = units[start]
    var end = start
    while end < range.upperBound, units[end] == character {
      end += 1
    }

    // The edges of the block's content count as whitespace, exactly as the beginning and
    // end of a line do in CommonMark.
    let beforeIsWhitespace =
      start == range.lowerBound || isUnicodeWhitespace(units[start - 1])
    let beforeIsPunctuation =
      start > range.lowerBound && isASCIIPunctuation(units[start - 1])
    let afterIsWhitespace = end == range.upperBound || isUnicodeWhitespace(units[end])
    let afterIsPunctuation = end < range.upperBound && isASCIIPunctuation(units[end])

    let leftFlanking =
      !afterIsWhitespace
      && (!afterIsPunctuation || beforeIsWhitespace || beforeIsPunctuation)
    let rightFlanking =
      !beforeIsWhitespace
      && (!beforeIsPunctuation || afterIsWhitespace || afterIsPunctuation)

    let canOpen: Bool
    let canClose: Bool
    if character == asterisk {
      canOpen = leftFlanking
      canClose = rightFlanking
    } else if character == tilde {
      // GFM: a run of three or more tildes is literal text. Recorded rather than skipped so
      // the run is still consumed in one step and cannot be reconsidered delimiter by
      // delimiter on the next iteration.
      let usable = end - start <= 2
      canOpen = usable && leftFlanking
      canClose = usable && rightFlanking
    } else {
      canOpen = leftFlanking && (!rightFlanking || beforeIsPunctuation)
      canClose = rightFlanking && (!leftFlanking || afterIsPunctuation)
    }

    delimiters.append(
      DelimiterRun(
        start: start, length: end - start, character: character, canOpen: canOpen,
        canClose: canClose, remaining: end - start))
    return end
  }

  /// Pairs delimiter runs from `stackBottom` upward and paints the styles they imply.
  ///
  /// CommonMark's `process_emphasis`, with one difference that is the whole reason this
  /// package exists: it produces no nodes. A matched pair ORs its bit over the span from
  /// the opener's spent delimiters to the closer's — **markers included** — so `***x***`
  /// leaves the outer asterisks carrying `[.emphasis]`, the inner pair carrying
  /// `[.emphasis, .strong]`, and `x` carrying `[.emphasis, .strong]`. Reading that layout
  /// off the array afterwards is a linear walk, not a tree traversal.
  private mutating func processEmphasis(stackBottom: Int) {
    // CommonMark's `openers_bottom`, and it is a **correctness-adjacent performance**
    // requirement rather than an optimization: without it, a line of delimiters that never
    // match — `a* a* a* …` repeated — searches the whole stack once per closer, which is
    // quadratic in line length and violates "nothing worse than linear in line length; a
    // one-megabyte line must scan" (REQUIREMENTS.md § Degenerate input). Once a closer of a
    // given shape has failed, no later closer of that shape can succeed below where it
    // failed, so the floor is remembered per shape: delimiter character × whether the
    // closer can also open × run length mod three, which is exactly what the rule of three
    // reads.
    var openersBottom = [Int](repeating: stackBottom, count: 18)

    var closerIndex = stackBottom
    while closerIndex < delimiters.count {
      guard delimiters[closerIndex].canClose, delimiters[closerIndex].remaining > 0 else {
        closerIndex += 1
        continue
      }
      let shape = shapeKey(delimiters[closerIndex])
      let floor = openersBottom[shape]

      var openerIndex = closerIndex - 1
      var found = false
      while openerIndex >= floor {
        let opener = delimiters[openerIndex]
        if opener.character == delimiters[closerIndex].character, opener.canOpen,
          opener.remaining > 0, !ruleOfThreeBlocks(opener, delimiters[closerIndex]),
          !lengthMismatchBlocks(opener, delimiters[closerIndex])
        {
          found = true
          break
        }
        openerIndex -= 1
      }

      guard found else {
        openersBottom[shape] = closerIndex
        // A run that can only close and found nothing is spent for good.
        if !delimiters[closerIndex].canOpen { delimiters[closerIndex].remaining = 0 }
        closerIndex += 1
        continue
      }

      applyPair(openerIndex: openerIndex, closerIndex: closerIndex)
      // Everything strictly between the pair is enclosed and can never match anything
      // outside it.
      for index in (openerIndex + 1)..<closerIndex {
        delimiters[index].remaining = 0
      }
      if delimiters[closerIndex].remaining == 0 { closerIndex += 1 }
    }
  }

  /// The `openersBottom` slot a closer belongs to: its character, whether it can also
  /// open, and its length mod three — the three things the rule of three consults, so two
  /// closers sharing a slot are interchangeable as far as matching is concerned.
  private func shapeKey(_ closer: DelimiterRun) -> Int {
    let character: Int
    switch closer.character {
    case asterisk: character = 0
    case underscore: character = 1
    default: character = 2
    }
    return character * 6 + (closer.canOpen ? 3 : 0) + (closer.length % 3)
  }

  /// CommonMark's "rule of three": when one of the two runs can both open and close, a
  /// pair is forbidden if the sum of the *original* lengths is a multiple of three unless
  /// both lengths are.
  ///
  /// Emphasis only. It is CommonMark's tie-breaker for `*` and `_`, GFM's tildes are not
  /// emphasis, and applying it to them would make `~x~` — two runs of one, summing to two —
  /// behave differently from `~~x~~` for a reason that has nothing to do with tildes.
  private func ruleOfThreeBlocks(_ opener: DelimiterRun, _ closer: DelimiterRun) -> Bool {
    guard opener.character != tilde else { return false }
    guard closer.canOpen || opener.canClose else { return false }
    guard (opener.length + closer.length) % 3 == 0 else { return false }
    return !(opener.length % 3 == 0 && closer.length % 3 == 0)
  }

  /// GFM's strikethrough length rule: a `~` opener pairs only with a closer of the **same**
  /// original length, so `~~x~` and `~x~~` are literal tildes rather than a struck `x`.
  ///
  /// Emphasis has no such rule — `***x*` is legal and pairs one asterisk — which is why
  /// this is a separate predicate rather than a clause inside ``ruleOfThreeBlocks(_:_:)``.
  private func lengthMismatchBlocks(_ opener: DelimiterRun, _ closer: DelimiterRun) -> Bool {
    opener.character == tilde && opener.length != closer.length
  }

  /// Spends one or two delimiters from each side of a matched pair and paints the result.
  private mutating func applyPair(openerIndex: Int, closerIndex: Int) {
    let opener = delimiters[openerIndex]
    let closer = delimiters[closerIndex]
    // Tildes spend the whole run at once: the two runs are the same length by the time
    // this is reached, and GFM has no "one tilde is light strikethrough" reading to make
    // spending one at a time mean anything.
    let use =
      opener.character == tilde
      ? min(opener.remaining, closer.remaining)
      : ((opener.remaining >= 2 && closer.remaining >= 2) ? 2 : 1)

    // An opener spends from its right end and a closer from its left, so the spent
    // delimiters are always the ones nearest the content. That is what makes `***x***`
    // come out as an emphasis span wrapping a strong one rather than the reverse.
    let openerSpentEnd = opener.start + opener.remaining
    let openerSpentStart = openerSpentEnd - use
    let closerSpentStart = closer.start + closer.length - closer.remaining
    let closerSpentEnd = closerSpentStart + use

    let bit: UInt16 =
      opener.character == tilde
      ? StyleSet.strikethrough.rawValue
      : (use == 2 ? StyleSet.strong.rawValue : StyleSet.emphasis.rawValue)
    for offset in openerSpentStart..<closerSpentEnd {
      attributes[slot(offset)].style |= bit
    }
    for offset in openerSpentStart..<openerSpentEnd {
      attributes[slot(offset)].isMarker = true
    }
    for offset in closerSpentStart..<closerSpentEnd {
      attributes[slot(offset)].isMarker = true
    }

    delimiters[openerIndex].remaining -= use
    delimiters[closerIndex].remaining -= use
  }

  // MARK: Encoding

  /// Run-length encodes the attribute array into spans exactly tiling `range`.
  func encode(base: Int, kind: SpanKind) -> [EscriboSpan] {
    var spans: [EscriboSpan] = []
    var start = range.lowerBound
    while start < range.upperBound {
      let attribute = attributes[slot(start)]
      var end = start + 1
      while end < range.upperBound, attributes[slot(end)] == attribute {
        end += 1
      }
      // Never hand `setAttributes(_:range:)` half a character. Every construct here is
      // ASCII-delimited so this cannot bind today; it is written anyway, because the day
      // it can bind is the day somebody adds a non-ASCII delimiter and does not think of
      // it.
      if end < range.upperBound, isHighSurrogate(units[end - 1]), isLowSurrogate(units[end]) {
        end += 1
      }
      spans.append(
        EscriboSpan(
          range: (base + start)..<(base + end),
          kind: InlineKindCode.kind(attribute.kindCode, inheriting: kind),
          style: StyleSet(rawValue: attribute.style),
          role: attribute.isMarker ? .marker : .content))
      start = end
    }
    return spans
  }
}
