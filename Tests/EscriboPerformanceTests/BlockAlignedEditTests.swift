import Foundation
import Testing

@testable import EscriboCore

/// The editor's typing path: an incremental scan whose window is widened to the edges of
/// the caller's block cache (`EscriboScanner.incrementalScan(_:in:alignedToBlocks:)`, which
/// `EditorCoordinator` calls on every keystroke).
///
/// The other suites here measure the scanner with no cache, which is the minimal window.
/// These measure what the editor actually pays, and pin the cap
/// (`blockAlignmentLineLimit`): inside a block too long to align within it, the window
/// must be the minimal window exactly — the behaviour before alignment existed.
///
/// The long documents are built in code rather than added to the screenplay fixture,
/// because the fixture is asserted to contain no fence (see `fixtureHasNoTerminators`).
/// What one block-aligned edit case measured.
struct AlignedEditMeasurement {
  let timing: Timing
  let aligned: ScanResult
  let minimalLines: Int
  /// Whether the aligned window begins and ends on block edges of the pre-edit blocks.
  let landsOnBlockEdges: Bool
}

extension PerformanceSuite {

  @Suite("Block-aligned edits")
  struct BlockAlignedEditTests {

    // MARK: - Documents

    /// Markdown with a 2,000-line fenced code block in the middle.
    static let longFence = PerfDocument(
      "# Fence\n\n```swift\n"
        + (0..<2000).map { "let value\($0) = \($0) * 2" }.joined(separator: "\n")
        + "\n```\n\nAfter the fence.\n")

    /// Markdown with one 500-line hard-wrapped paragraph of plain prose.
    static let longParagraph = PerfDocument(
      "# Wall\n\n"
        + (0..<500).map { "plain prose line \($0) of one long hard-wrapped paragraph" }
        .joined(separator: "\n")
        + "\n\nAfter the wall.\n")

    /// Fountain with a 300-line action paragraph and a 300-line speech.
    static let longScreenplay = PerfDocument(
      "INT. HALL - NIGHT\n\n"
        + (0..<300).map { "She walks the length of the hall, step \($0), and stops." }
        .joined(separator: "\n")
        + "\n\nBOB\n"
        + (0..<300).map { "I keep talking, line \($0), and nobody stops me." }
        .joined(separator: "\n")
        + "\n\nJane enters.\n")

    /// Fountain with a 60-line action paragraph: long, but inside the cap, so the window
    /// does align — the case the per-line cost is read from.
    static let alignableScreenplay = PerfDocument(
      "INT. HALL - NIGHT\n\n"
        + (0..<60).map { "She walks the length of the hall, step \($0), and stops." }
        .joined(separator: "\n")
        + "\n\nJane enters.\n")

    // MARK: - Measuring

    /// The lines of the block in `blocks` containing `line` — the coordinator's lookup.
    static func lines(containing line: Int, in blocks: [EscriboBlock]) -> Range<Int>? {
      var low = 0
      var high = blocks.count
      while low < high {
        let mid = (low + high) / 2
        let lines = blocks[mid].lines
        if lines.upperBound <= line {
          low = mid + 1
        } else if lines.lowerBound > line {
          high = mid
        } else {
          return lines
        }
      }
      return nil
    }

    /// Types one character in the middle of `line`, with and without the block hint.
    static func measure(
      _ document: PerfDocument, language: Language, line: Int, count: Int = 40
    ) -> AlignedEditMeasurement {
      let at = document.midpoint(ofLine: line)
      let (edited, edit) = document.applying("s", over: at..<at)

      var plain = EscriboScanner(language: language)
      plain.fullScan(document.text)
      let minimal = plain.incrementalScan(edit, in: edited.text)

      var blocks: [EscriboBlock] = []
      let (timing, result) = repeated(count: count) {
        var scanner = EscriboScanner(language: language)
        blocks = scanner.fullScan(document.text).blocks
        let cache = blocks
        let run = timed {
          scanner.incrementalScan(
            edit, in: edited.text, alignedToBlocks: { lines(containing: $0, in: cache) })
        }
        return (run.value, run.seconds)
      }

      let starts = Set(blocks.map(\.lines.lowerBound))
      let lineDelta = result.documentLineCount - document.lineCount
      let lands =
        starts.contains(result.lines.lowerBound)
        && (result.lines.upperBound == result.documentLineCount
          || starts.contains(result.lines.upperBound - lineDelta))
      return AlignedEditMeasurement(
        timing: timing, aligned: result, minimalLines: minimal.lines.count,
        landsOnBlockEdges: lands)
    }

    /// Prints the case, and asserts what every case must: real work, the cap, the budget.
    static func check(_ name: String, _ measurement: AlignedEditMeasurement) {
      let facts = ScanFacts(measurement.aligned)
      report(name, measurement.timing)
      observe(
        "\(name)-lines-rescanned",
        "\(facts.lineCount) aligned, \(measurement.minimalLines) minimal, "
          + "on block edges: \(measurement.landsOnBlockEdges)")
      #expect(facts.tilesExactly)
      #expect(facts.coveredUnits == facts.dirtyRange.count)
      #expect(
        facts.lineCount <= measurement.minimalLines + blockAlignmentLineLimit,
        "\(name): alignment added \(facts.lineCount - measurement.minimalLines) lines")
      #expect(
        measurement.timing.bestMS <= 1.0,
        "\(name): \(measurement.timing.bestMS) ms; the in-line edit budget is 1 ms")
    }

    // MARK: - Over the cap: the minimal window, exactly

    @Test("A keystroke inside a 2,000-line fence is not aligned and costs the minimal window")
    func insideALongFence() {
      let measurement = Self.measure(Self.longFence, language: .markdown, line: 3 + 1000)
      Self.check("aligned-fence-2000", measurement)
      #expect(!measurement.landsOnBlockEdges, "the cap must decline a 2,000-line block")
      #expect(measurement.aligned.lines.count == measurement.minimalLines)
    }

    @Test("A keystroke inside a 500-line paragraph is not aligned and costs the minimal window")
    func insideALongParagraph() {
      let measurement = Self.measure(Self.longParagraph, language: .markdown, line: 2 + 250)
      Self.check("aligned-paragraph-500", measurement)
      #expect(!measurement.landsOnBlockEdges, "the cap must decline a 500-line block")
      #expect(measurement.aligned.lines.count == measurement.minimalLines)
    }

    @Test("A keystroke inside a 300-line action paragraph or speech costs the minimal window")
    func insideLongFountainBlocks() {
      let action = Self.measure(Self.longScreenplay, language: .fountain, line: 2 + 150)
      Self.check("aligned-action-300", action)
      #expect(!action.landsOnBlockEdges, "the cap must decline a 300-line action")
      #expect(action.aligned.lines.count == action.minimalLines)

      // Speech: the cue is line 303, its 300 dialogue lines follow.
      let speech = Self.measure(Self.longScreenplay, language: .fountain, line: 304 + 150)
      Self.check("aligned-speech-300", speech)
      #expect(!speech.landsOnBlockEdges, "the cap must decline a 301-line speech")
      #expect(speech.aligned.lines.count == speech.minimalLines)
    }

    // MARK: - Within the cap: aligned, and still inside the budget

    @Test("An ordinary keystroke in the screenplay fixture aligns, inside the 1 ms budget")
    func ordinaryKeystrokeInTheFixture() {
      let measurement = Self.measure(
        PerfFixture.screenplay, language: .fountain, line: ScanBudgetTests.editLine)
      Self.check("aligned-inline-edit", measurement)
      #expect(measurement.landsOnBlockEdges, "an ordinary block must align")
    }

    @Test("A keystroke in a 60-line action paragraph aligns; the per-line cost is observed")
    func insideAnAlignableBlock() {
      let measurement = Self.measure(Self.alignableScreenplay, language: .fountain, line: 2 + 30)
      Self.check("aligned-action-60", measurement)
      #expect(measurement.landsOnBlockEdges, "a 60-line block is inside the cap")
      let lines = measurement.aligned.lines.count
      #expect(lines >= 60, "the whole action block is rescanned")
      observe(
        "aligned-per-line-cost",
        String(format: "%.2f µs/line", measurement.timing.best * 1e6 / Double(lines)))
    }
  }
}
