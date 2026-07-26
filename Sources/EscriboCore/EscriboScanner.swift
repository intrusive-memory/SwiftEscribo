/// The public scanner entry point: a document, a language, and a stream of edits in,
/// ``ScanResult`` values out.
///
/// ## Why this exists rather than exposing ``IncrementalScanner``
///
/// ``IncrementalScanner`` is generic over ``LineGrammar``, and `LineGrammar` cannot be
/// public: a conformer has to produce a ``LineState``, whose initializer is `internal`
/// precisely so the type stays opaque (REQUIREMENTS.md § What is public in 1.0). A
/// public generic scanner therefore forces `LineState`'s shape into the public API and
/// freezes the scanner's internals at 1.0 — the exact outcome the opacity exists to
/// prevent.
///
/// So the public surface is this: **non-generic over the grammar**, taking a
/// ``Language`` and owning the grammar behind it. A caller names a language;
/// `EscriboCore` owns everything else. `LineGrammar`, `IncrementalScanner`,
/// ``LineIndex``, and `LineState`'s initializer all stay internal, and adding a grammar
/// or changing how one works is a minor release with no API consequence.
///
/// The two methods are generic over ``UTF16TextSource`` only, which is public and must
/// be: `SwiftEscribo` conforms `NSTextStorage` to it so the scanner can read a document
/// without bridging 120 KB to a Swift `String` on every keystroke.
///
/// ## Totality
///
/// Neither method throws, is `async`, or returns an optional, and neither has a
/// `precondition` on the scan path. An unterminated construct scans to the end of the
/// document; a stale or nonsensical ``TextEdit`` is clamped; an unrecognized `Language`
/// scans as plain text. There is no error path because there is nothing an error could
/// mean — every sequence of code units is a document.
///
/// ## Usage
///
/// ```swift
/// var scanner = EscriboScanner(language: .markdown)
/// var result = scanner.fullScan(text)                      // once, up front
/// result = scanner.incrementalScan(edit, in: newText)      // per keystroke
/// ```
///
/// Call ``fullScan(_:)`` before the first ``incrementalScan(_:in:)``. Skipping it is not
/// a trap: the scanner simply believes the document was empty and produces a well-formed
/// result for a document it has wrong, which the next keystroke corrects. A
/// `precondition` here would turn a caller's sequencing bug into a crash inside a
/// text-view delegate callback.
///
/// The scanner is a value type holding mutable scan state, and it is **synchronous and
/// single-threaded** by design: no `async`, no actor, no background queue. Hold one per
/// document, on the main actor, alongside the text storage it reads.
public struct EscriboScanner {

  /// The language this scanner reads its document as. Fixed at initialization —
  /// switching languages means making a new scanner and scanning in full, because every
  /// line's state would be meaningless under a different grammar anyway.
  public let language: Language

  /// The engine, instantiated at exactly one concrete grammar type. Private, and it is
  /// the private-ness that keeps the generic machinery from leaking into the API.
  private var scanner: IncrementalScanner<ResolvedGrammar>

  /// Creates a scanner for `language` over an empty document.
  ///
  /// An unrecognized language is not an error — see ``ResolvedGrammar`` — so this is
  /// total for every `Language` value that exists or ever will.
  public init(language: Language) {
    self.language = language
    self.scanner = IncrementalScanner(grammar: ResolvedGrammar(language: language))
  }

  /// Scans `source` in full, from the start of the document.
  ///
  /// Resets everything the scanner carries. The returned result covers every line and
  /// its ``ScanResult/dirtyRange`` is the whole document.
  @discardableResult
  public mutating func fullScan(_ source: some UTF16TextSource) -> ScanResult {
    scanner.fullScan(source)
  }

  /// Applies `edit` and rescans the smallest window that can be proved sufficient.
  ///
  /// - Parameters:
  ///   - edit: The mutation, in **old-text coordinates** — see ``TextEdit``. Its range
  ///     indexes the document as this scanner currently describes it.
  ///   - source: The document **after** the edit.
  /// - Returns: A result whose ``ScanResult/dirtyRange`` is line-aligned at both ends and
  ///   contains the edited range, and whose spans exactly tile it. The range may be far
  ///   larger than the edit — opening a fenced code block on line 1 legitimately dirties
  ///   the rest of the document — and is never smaller.
  @discardableResult
  public mutating func incrementalScan(
    _ edit: TextEdit, in source: some UTF16TextSource
  ) -> ScanResult {
    scanner.incrementalScan(edit, in: source)
  }
}

/// The grammar a ``Language`` resolves to, as one concrete type.
///
/// An enum rather than an existential or a second generic parameter, for one reason:
/// ``EscriboScanner`` must be non-generic, so the engine inside it has to be
/// instantiated at a single type — and that type has to be able to *be* any grammar.
/// Boxing the choice in an enum that itself conforms to ``LineGrammar`` gives exactly
/// that, with a `switch` per line instead of a witness-table call per line, and with no
/// allocation anywhere.
enum ResolvedGrammar: LineGrammar {
  case markdown(MarkdownGrammar)
  case fountain(FountainGrammar)
  case text(TextGrammar)

  /// Resolves `language` to the grammar that scans it.
  ///
  /// Total by construction, including for a `Language` this version has never heard of:
  /// `Language` is a struct with static members precisely so a consumer can name one
  /// with `Language(rawValue:)`, and an unknown language scans as plain text rather than
  /// trapping (REQUIREMENTS.md § Unknown kinds fall back, never fail).
  init(language: Language) {
    switch language {
    case .markdown:
      self = .markdown(MarkdownGrammar())
    case .fountain:
      // Block elements, the dialogue block, notes, boneyard, and the title page, with
      // GLOSA directives inside notes subdivided structurally by `GlosaScanner`. Every
      // line classifies and every scan tiles.
      self = .fountain(FountainGrammar())
    default:
      self = .text(TextGrammar())
    }
  }

  var lookahead: Int {
    switch self {
    case .markdown(let grammar): grammar.lookahead
    case .fountain(let grammar): grammar.lookahead
    case .text(let grammar): grammar.lookahead
    }
  }

  var backwardExtent: Int {
    switch self {
    case .markdown(let grammar): grammar.backwardExtent
    case .fountain(let grammar): grammar.backwardExtent
    case .text(let grammar): grammar.backwardExtent
    }
  }

  func scanLine(_ window: LineWindow, state: LineState) -> LineScan {
    switch self {
    case .markdown(let grammar): grammar.scanLine(window, state: state)
    case .fountain(let grammar): grammar.scanLine(window, state: state)
    case .text(let grammar): grammar.scanLine(window, state: state)
    }
  }
}
