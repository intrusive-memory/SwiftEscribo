/// Rewrites formatted text — the runs of a rich-text paste — as the markup a language reads
/// the same formatting from.
///
/// The editor's value is plain text, so a paste from a word processor or a screenwriting app
/// loses its bold, italics and underline (DL-65: paste is verbatim). A host that would rather
/// keep them opts in, and the platform layer hands the pasteboard's attributed runs here:
///
/// | Style | Fountain | Markdown |
/// | --- | --- | --- |
/// | ``StyleSet/strong`` | `**x**` | `**x**` |
/// | ``StyleSet/emphasis`` | `*x*` | `*x*` |
/// | ``StyleSet/underline`` | `_x_` | dropped — Markdown has no underline |
/// | ``StyleSet/strikethrough`` | dropped | `~~x~~` |
///
/// The rules that keep the output readable by the language it is written for:
///
/// - **Per line.** Neither language carries emphasis across a line break, so every marker
///   opened on a line is closed on it, and reopened on the next if the style continues.
/// - **Markers hug text.** A delimiter opens only before a non-space and closes only after
///   one, so whitespace at the edge of a styled run is moved outside its markers, and a run
///   that is only whitespace changes nothing.
/// - **Styles nest instead of restarting.** Adjacent runs are compared flag by flag: a flag
///   that continues stays open, so bold `a` followed by bold-italic `b` is `**a*b***`, not two
///   separate spans whose delimiters would run together.
/// - **Fountain structure is left alone.** A line with no lowercase letters — a scene
///   heading, a character cue, a transition — or one that forces a scene heading with `.` is
///   written without markers, because `_INT. HOUSE - DAY_` is no longer a scene heading.
///   Screenwriting apps routinely underline sluglines; that formatting is the element's, not
///   the text's.
///
/// Text that already contains `*` or `_` is not escaped: unstyled text is still inserted
/// exactly as it was copied.
public enum RichPasteMarkup {

  /// One run of the pasted text and the styles covering all of it.
  public struct Run: Equatable, Sendable {
    public var text: String
    public var styles: StyleSet

    public init(_ text: String, _ styles: StyleSet = []) {
      self.text = text
      self.styles = styles
    }
  }

  /// The styles `language` has markup for, outermost first.
  static func markers(for language: Language) -> [(StyleSet, String)] {
    switch language {
    case .fountain:
      return [(.underline, "_"), (.strong, "**"), (.emphasis, "*")]
    case .markdown:
      return [(.strikethrough, "~~"), (.strong, "**"), (.emphasis, "*")]
    default:
      return []
    }
  }

  /// Whether `runs` carry any style `language` would write — `false` means the plain text is
  /// already the whole answer, and a host can let the platform paste it as usual.
  public static func hasMarkup(_ runs: [Run], language: Language) -> Bool {
    let supported = markers(for: language).reduce(into: StyleSet()) { $0.formUnion($1.0) }
    return runs.contains { !$0.styles.isDisjoint(with: supported) && $0.text.contains { !$0.isWhitespace } }
  }

  /// `runs` as text in `language`, with their styles written as its markup.
  public static func markup(_ runs: [Run], language: Language) -> String {
    let table = markers(for: language)
    let supported = table.reduce(into: StyleSet()) { $0.formUnion($1.0) }

    // Split the runs into lines, keeping each piece's styles.
    var lines: [[Run]] = [[]]
    for run in runs {
      let styles = run.styles.intersection(supported)
      for (index, piece) in run.text.split(separator: "\n", omittingEmptySubsequences: false)
        .enumerated()
      {
        if index > 0 { lines.append([]) }
        if !piece.isEmpty { lines[lines.count - 1].append(Run(String(piece), styles)) }
      }
    }

    return lines.map { line(in: $0, table: table, language: language) }
      .joined(separator: "\n")
  }

  /// One line's runs, with markers opened and closed at style boundaries.
  private static func line(in runs: [Run], table: [(StyleSet, String)], language: Language)
    -> String
  {
    let plain = runs.map(\.text).joined()
    if language == .fountain && isFountainStructure(plain) { return plain }

    var output = ""
    var open: [(StyleSet, String)] = []

    func close(keeping keep: StyleSet) {
      // Close from the innermost out until only flags in `keep` remain open — and close a
      // kept flag too if something inside it has to close first, then reopen it below.
      guard let firstToClose = open.firstIndex(where: { !keep.contains($0.0) }) else { return }
      for marker in open[firstToClose...].reversed() { output += marker.1 }
      open.removeSubrange(firstToClose...)
    }

    for (index, run) in runs.enumerated() {
      let core = run.text.trimmingWhitespace()
      guard !core.isEmpty else {
        output += run.text
        continue
      }
      let leading = run.text.prefix { $0 == " " || $0 == "\t" }
      let trailing = String(run.text.reversed().prefix { $0 == " " || $0 == "\t" }.reversed())

      close(keeping: run.styles)
      output += leading
      let alreadyOpen = open.reduce(into: StyleSet()) { $0.formUnion($1.0) }
      for marker in table where run.styles.contains(marker.0) && !alreadyOpen.contains(marker.0) {
        output += marker.1
        open.append(marker)
      }
      output += core
      if !trailing.isEmpty {
        // Only the styles that do not carry on past the space close before it.
        let next = runs[(index + 1)...].first { !$0.text.trimmingWhitespace().isEmpty }
        close(keeping: next?.styles.intersection(run.styles) ?? [])
        output += trailing
      }
    }
    close(keeping: [])
    return output
  }

  /// A Fountain line whose formatting belongs to its element: a forced scene heading, or a
  /// line with letters and no lowercase ones (scene headings, cues, transitions).
  static func isFountainStructure(_ line: String) -> Bool {
    let trimmed = line.trimmingWhitespace()
    if trimmed.hasPrefix(".") && !trimmed.hasPrefix("..") { return true }
    let letters = trimmed.filter(\.isLetter)
    return !letters.isEmpty && !letters.contains(where: \.isLowercase)
  }
}

extension String {
  /// Without leading and trailing spaces and tabs.
  fileprivate func trimmingWhitespace() -> String {
    var slice = Substring(self)
    while let first = slice.first, first == " " || first == "\t" { slice.removeFirst() }
    while let last = slice.last, last == " " || last == "\t" { slice.removeLast() }
    return String(slice)
  }
}
