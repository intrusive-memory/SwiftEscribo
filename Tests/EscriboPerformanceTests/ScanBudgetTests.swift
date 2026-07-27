import Foundation
import Testing

@testable import EscriboCore

/// The scan-time budgets, and the observations this package owes itself but will not
/// gate on.
///
/// ## What is asserted, and what is only printed
///
/// Asserted:
///
/// - **A typical in-line edit with unchanged state: ≤ 1 ms.** Measured at 0.026 ms on the
///   development machine — about 40× under the ceiling, with the *worst* of forty samples
///   still 18× under it. A threshold with that much headroom cannot fire on scheduler
///   noise or on a slower runner; it fires on an algorithmic regression, which is an
///   order-of-magnitude event because it means an edit stopped converging.
/// - **A cold full scan of ~128 KB: ≤ 50 ms**, measured at 5.2 ms. The 10 ms *target* is
///   printed on every run rather than asserted: 5 ms on this laptop is close enough to
///   10 ms that a shared `macos-26` runner could cross it while nothing regressed at all,
///   and a gate that goes red because of which host GitHub handed out is a gate that gets
///   ignored and then deleted. A number in the log a human can read is worth more.
/// - **Every timed scan's output**, in ``ScanFacts`` — spans present, spans exactly tiling
///   the dirty range, the dirty range the size the case is about, and the rescan window
///   the size the case is about. A budget with no output assertion is satisfied by a
///   scanner that returns nothing quickly, which is the cheapest unfalsifiable test in
///   reach; deleting the span emission from `IncrementalScanner` turns six of these tests
///   red on the output assertions alone.
///
/// Reported only:
///
/// - The four pathological edits' **times**. Their **window sizes** are asserted, because
///   the window is the property a regression breaks and the clock is only its consequence:
///   all four converge (2, 3, 3, and 471 lines against a 6 033-line document), so all four
///   land two orders of magnitude under the ceiling and a wall-clock bound on them would
///   catch nothing that the window bound does not catch first and harder.
/// - The whole-document `NSString` → `String` bridge (DL-75) and the post-IME full rescan
///   (DL-56), which live in `SwiftEscribo` rather than here — this target links
///   `EscriboCore` only, so both are measured through their Foundation twins.
///
/// ## Why this suite is `.serialized`
///
/// swift-testing runs tests in parallel by default. Two timing tests on two cores of a
/// two-core runner measure each other. Serialization is not a nicety here; it is the
/// difference between a measurement and a race.
@Suite("EscriboCore performance", .serialized)
struct PerformanceSuite {

  // MARK: - The fixture

  @Suite("Assembled fixture")
  struct FixtureTests {

    @Test("The assembled screenplay is committed, ≥110 KB, and loads via Bundle.module")
    func fixtureLoads() {
      #expect(PerfFixture.loaded, "long_screenplay.fountain did not load from Bundle.module")
      #expect(
        PerfFixture.byteCount >= 110 * 1024,
        "fixture is \(PerfFixture.byteCount) bytes; the sortie requires ≥110 KB")
      observe("fixture-bytes", "\(PerfFixture.byteCount)")
      observe("fixture-utf16", "\(PerfFixture.screenplay.utf16Count)")
      observe("fixture-lines", "\(PerfFixture.screenplay.lineCount)")
    }

    /// The prologue technique in ``PerfFixture`` is only sound if the committed text
    /// contains no fence and no boneyard of its own — otherwise the "unterminated"
    /// construct would terminate somewhere in the middle and the pathological case would
    /// quietly become an ordinary one.
    @Test("The fixture contains no fence and no boneyard, so the prologues stay unterminated")
    func fixtureHasNoTerminators() {
      #expect(!PerfFixture.screenplay.text.contains("```"))
      #expect(!PerfFixture.screenplay.text.contains("/*"))
      #expect(!PerfFixture.screenplay.text.contains("*/"))
      // Non-ASCII dialogue survives assembly: `spanish.fountain` is in there, and a
      // fixture laundered to ASCII would measure a scanner that never meets a surrogate
      // or a multi-byte code point.
      #expect(PerfFixture.screenplay.text.unicodeScalars.contains { $0.value > 127 })
    }
  }

  // MARK: - The budgets

  @Suite("Scan-time budgets")
  struct ScanBudgetTests {

    /// The line an "ordinary keystroke" lands on: prose, roughly halfway down.
    static let editLine = PerfFixture.screenplay.prosaicLine(atOrAfter: 3000)

    @Test("Cold full scan of ~128 KB stays under the 50 ms ceiling")
    func coldFullScan() {
      let document = PerfFixture.screenplay
      let (timing, result) = repeated(count: 12) {
        var scanner = EscriboScanner(language: .fountain)
        let run = timed { scanner.fullScan(document.text) }
        return (run.value, run.seconds)
      }
      let facts = ScanFacts(result)

      report("cold-scan", timing)
      observe(
        "cold-scan-vs-10ms-target",
        String(format: "%.3f ms measured, %.1f%% of the 10 ms target", timing.bestMS,
          timing.bestMS / 10.0 * 100))
      observe(
        "cold-scan-throughput",
        String(format: "%.1f MB/s", Double(document.utf16Count * 2) / timing.best / 1_000_000))

      // The scan actually scanned the whole document.
      #expect(facts.dirtyRange == 0..<document.utf16Count)
      #expect(facts.tilesExactly)
      #expect(facts.coveredUnits == document.utf16Count)
      #expect(facts.recordCount == document.lineCount)
      #expect(facts.lineCount == document.lineCount)
      #expect(facts.spanCount > document.lineCount)
      // …and classified it, rather than calling 6 000 lines "text".
      #expect(facts.elementKinds.count >= 5)
      #expect(facts.elementKinds.contains(ElementKind.character.rawValue))
      #expect(facts.elementKinds.contains(ElementKind.dialogue.rawValue))
      #expect(facts.elementKinds.contains(ElementKind.sceneHeading.rawValue))

      #expect(timing.bestMS <= 50.0, "cold full scan took \(timing.bestMS) ms; ceiling is 50 ms")
    }

    @Test("A typical in-line edit with unchanged state stays under 1 ms")
    func typicalInlineEdit() {
      let document = PerfFixture.screenplay
      let at = document.midpoint(ofLine: Self.editLine)
      let (edited, edit) = document.applying("s", over: at..<at)

      let (timing, result) = repeated(count: 40) {
        var scanner = EscriboScanner(language: .fountain)
        scanner.fullScan(document.text)
        let run = timed { scanner.incrementalScan(edit, in: edited.text) }
        return (run.value, run.seconds)
      }
      let facts = ScanFacts(result)

      report("inline-edit", timing)
      observe("inline-edit-lines-rescanned", "\(facts.lineCount)")

      // Converged: the window is a handful of lines, not the document. This is the
      // assertion with teeth — a regression that broke convergence would still be fast
      // enough to pass a 1 ms budget on a small window and would blow this instead.
      #expect(facts.lineCount <= 8, "rescanned \(facts.lineCount) lines; expected convergence")
      #expect(facts.dirtyRange.lowerBound <= at)
      #expect(facts.dirtyRange.upperBound >= at + 1)
      #expect(facts.tilesExactly)
      #expect(facts.coveredUnits == facts.dirtyRange.count)
      #expect(facts.spanCount > 0)

      #expect(timing.bestMS <= 1.0, "in-line edit took \(timing.bestMS) ms; budget is 1 ms")
    }

    // MARK: The pathological sequence

    @Test("Pathological: an edit on line 1 of the long document")
    func editAtLineOne() {
      let document = PerfFixture.screenplay
      let at = document.midpoint(ofLine: 0)
      let (edited, edit) = document.applying("s", over: at..<at)

      let (timing, result) = repeated(count: 25) {
        var scanner = EscriboScanner(language: .fountain)
        scanner.fullScan(document.text)
        let run = timed { scanner.incrementalScan(edit, in: edited.text) }
        return (run.value, run.seconds)
      }
      let facts = ScanFacts(result)

      report("edit-line-1", timing)
      observe("edit-line-1-lines-rescanned", "\(facts.lineCount)")

      #expect(facts.dirtyRange.lowerBound == 0)
      #expect(facts.dirtyRange.upperBound >= at + 1)
      #expect(facts.tilesExactly)
      #expect(facts.coveredUnits == facts.dirtyRange.count)
      // Teeth: the title page converges within a couple of lines, so this stays a
      // per-keystroke cost rather than a document-length one. A convergence regression
      // shows up here as 6 033, long before it shows up as a wall-clock number — the whole
      // document scans in ~5 ms, which is comfortably inside a 50 ms ceiling.
      #expect(facts.lineCount <= 8, "rescanned \(facts.lineCount) lines from line 1")
      // An edit on the title page cannot be cheaper than a whole-document rescan, and it
      // is bounded by one: the ceiling here is the cold-scan ceiling, not the 1 ms one.
      #expect(timing.bestMS <= 50.0)
    }

    @Test("Pathological: an edit inside an unterminated fenced code block")
    func editInsideUnterminatedFence() {
      let document = PerfFixture.fenced
      let line = document.prosaicLine(atOrAfter: 3000)
      let at = document.midpoint(ofLine: line)
      let (edited, edit) = document.applying("s", over: at..<at)

      // The document really is inside a fence at the edit site — if the fence had closed,
      // this case would be measuring an ordinary paragraph edit under a pathological name.
      var probe = EscriboScanner(language: .markdown)
      let cold = probe.fullScan(document.text)
      #expect(cold.lineRecords[line].element == .codeBlock)
      #expect(cold.lineRecords[document.lineCount - 1].element == .codeBlock)

      let (timing, result) = repeated(count: 25) {
        var scanner = EscriboScanner(language: .markdown)
        scanner.fullScan(document.text)
        let run = timed { scanner.incrementalScan(edit, in: edited.text) }
        return (run.value, run.seconds)
      }
      let facts = ScanFacts(result)

      report("edit-in-unterminated-fence", timing)
      observe("edit-in-unterminated-fence-lines-rescanned", "\(facts.lineCount)")

      #expect(facts.dirtyRange.lowerBound <= at)
      #expect(facts.dirtyRange.upperBound >= at + 1)
      #expect(facts.tilesExactly)
      #expect(facts.coveredUnits == facts.dirtyRange.count)
      #expect(facts.spanCount > 0)
      // Teeth: inside an unterminated construct the line state is uniform, so convergence
      // is immediate and the window is a few lines even though every line to the end of
      // the document is in the same construct. That is the property worth pinning; the
      // time it takes is only the consequence.
      #expect(facts.lineCount <= 8, "rescanned \(facts.lineCount) lines")
      #expect(timing.bestMS <= 50.0)
    }

    @Test("Pathological: an edit inside an unterminated boneyard")
    func editInsideUnterminatedBoneyard() {
      let document = PerfFixture.boneyarded
      let line = document.prosaicLine(atOrAfter: 3000)
      let at = document.midpoint(ofLine: line)
      let (edited, edit) = document.applying("s", over: at..<at)

      var probe = EscriboScanner(language: .fountain)
      let cold = probe.fullScan(document.text)
      #expect(cold.lineRecords[line].element == .boneyard)
      #expect(cold.lineRecords[document.lineCount - 1].element == .boneyard)

      let (timing, result) = repeated(count: 25) {
        var scanner = EscriboScanner(language: .fountain)
        scanner.fullScan(document.text)
        let run = timed { scanner.incrementalScan(edit, in: edited.text) }
        return (run.value, run.seconds)
      }
      let facts = ScanFacts(result)

      report("edit-in-unterminated-boneyard", timing)
      observe("edit-in-unterminated-boneyard-lines-rescanned", "\(facts.lineCount)")

      #expect(facts.dirtyRange.lowerBound <= at)
      #expect(facts.dirtyRange.upperBound >= at + 1)
      #expect(facts.tilesExactly)
      #expect(facts.coveredUnits == facts.dirtyRange.count)
      #expect(facts.spanCount > 0)
      // Teeth: inside an unterminated construct the line state is uniform, so convergence
      // is immediate and the window is a few lines even though every line to the end of
      // the document is in the same construct. That is the property worth pinning; the
      // time it takes is only the consequence.
      #expect(facts.lineCount <= 8, "rescanned \(facts.lineCount) lines")
      #expect(timing.bestMS <= 50.0)
    }

    @Test("Pathological: a 10 KB paste into the middle of the document")
    func tenKilobytePaste() {
      let document = PerfFixture.screenplay
      let at = document.lineStarts[Self.editLine]
      let payload = PerfFixture.pastePayload
      let (edited, edit) = document.applying(payload, over: at..<at)

      let (timing, result) = repeated(count: 25) {
        var scanner = EscriboScanner(language: .fountain)
        scanner.fullScan(document.text)
        let run = timed { scanner.incrementalScan(edit, in: edited.text) }
        return (run.value, run.seconds)
      }
      let facts = ScanFacts(result)

      report("paste-10kb", timing)
      observe("paste-10kb-payload-utf16", "\(payload.utf16.count)")
      observe("paste-10kb-lines-rescanned", "\(facts.lineCount)")

      // The whole paste is inside the dirty range — a rescan that stopped short of it
      // would leave pasted text unstyled, and would also be fast.
      #expect(facts.dirtyRange.lowerBound <= at)
      #expect(facts.dirtyRange.upperBound >= at + payload.utf16.count)
      #expect(facts.tilesExactly)
      #expect(facts.coveredUnits == facts.dirtyRange.count)
      #expect(facts.lineCount >= 100, "a 10 KB screenplay paste is hundreds of lines")
      // …and it converges shortly after the paste rather than repainting the 6 000 lines
      // below it. Both bounds together are what make this a measurement of "rescan the
      // paste" instead of a measurement of whatever the scanner felt like doing.
      #expect(
        facts.lineCount <= 600,
        "rescanned \(facts.lineCount) lines for a ~470-line paste; expected convergence")
      #expect(timing.bestMS <= 50.0)
    }
  }

  // MARK: - Measured, not assumed

  @Suite("Measured observations")
  struct ObservationTests {

    /// DL-138 — Sortie 21 raised `MarkdownGrammar.lookahead` from 0 to 1, so the forward
    /// rescan now runs one line past convergence for **every** Markdown document, not only
    /// fenced ones. This measures that against the 1 ms in-line-edit budget rather than
    /// assuming it is free.
    ///
    /// The comparison is against a grammar whose lookahead is 0 — an unrecognized
    /// `Language`, which resolves to `TextGrammar` — over the same document and the same
    /// edit. The *line-count* delta is the lookahead's effect; the time delta between two
    /// different grammars is not, so the cost is priced as
    /// `extra lines × Markdown's own marginal per-line scan cost`, taken from a Markdown
    /// full scan of the same document.
    @Test("DL-138: one line of Markdown lookahead, priced against the 1 ms budget")
    func markdownLookaheadCost() {
      let document = PerfFixture.screenplay
      let line = document.prosaicLine(atOrAfter: 3000)
      let at = document.midpoint(ofLine: line)
      let (edited, edit) = document.applying("s", over: at..<at)

      let (markdownTiming, markdownResult) = repeated(count: 30) {
        var scanner = EscriboScanner(language: .markdown)
        scanner.fullScan(document.text)
        let run = timed { scanner.incrementalScan(edit, in: edited.text) }
        return (run.value, run.seconds)
      }
      let (plainTiming, plainResult) = repeated(count: 30) {
        var scanner = EscriboScanner(language: Language(rawValue: "plain-text-no-lookahead"))
        scanner.fullScan(document.text)
        let run = timed { scanner.incrementalScan(edit, in: edited.text) }
        return (run.value, run.seconds)
      }
      let (fullTiming, fullResult) = repeated(count: 8) {
        var scanner = EscriboScanner(language: .markdown)
        let run = timed { scanner.fullScan(document.text) }
        return (run.value, run.seconds)
      }

      let markdownLines = markdownResult.lines.count
      let plainLines = plainResult.lines.count
      let extraLines = markdownLines - plainLines
      let perLineMS = fullTiming.bestMS / Double(fullResult.lines.count)

      report("markdown-inline-edit", markdownTiming)
      report("lookahead-0-inline-edit", plainTiming)
      observe("dl138-lines-rescanned-markdown", "\(markdownLines)")
      observe("dl138-lines-rescanned-lookahead-0", "\(plainLines)")
      observe("dl138-extra-lines", "\(extraLines)")
      observe(
        "dl138-marginal-cost-per-line",
        String(format: "%.5f ms (%.2f µs)", perLineMS, perLineMS * 1000))
      observe(
        "dl138-estimated-cost",
        String(
          format: "%.5f ms — %.4f%% of the 1 ms in-line-edit budget",
          Double(extraLines) * perLineMS, Double(extraLines) * perLineMS / 1.0 * 100))

      // The lookahead is one line, and it shows up as one line of rescan window.
      #expect(markdownLines >= plainLines)
      #expect(extraLines <= 2, "a lookahead of 1 must not widen the window by more than a line")
      // And the Markdown in-line edit is still inside the budget the raise put at risk.
      #expect(
        markdownTiming.bestMS <= 1.0,
        "Markdown in-line edit took \(markdownTiming.bestMS) ms; budget is 1 ms")
    }

    /// DL-75 — the per-change `NSTextStorage.string` → Swift `String` bridge in
    /// `ExternalTextReplacement.currentText`, read once per change notification on the way
    /// out to the SwiftUI binding. It is in `SwiftEscribo`, which this target does not and
    /// must not link, so it is measured here against its Foundation twin: the same
    /// `NSMutableAttributedString.string` access over the same 128 KB document. Reported,
    /// never asserted.
    @Test("DL-75: the whole-document String bridge on the binding push, observed")
    func documentStringBridge() {
      let storage = NSMutableAttributedString(string: PerfFixture.screenplay.text)

      let (bridgeTiming, bridgedCount) = repeated(count: 30) {
        let run = timed { storage.string.utf16.count }
        return (run.value, run.seconds)
      }
      // Bridging an `NSString` can hand back a `String` that still wraps the original
      // storage; the copy is paid when something forces a native buffer — a comparison,
      // a hash, or any UTF-8 traversal, all of which SwiftUI does to a `@Binding var
      // text: String` on the next update pass.
      let (materializedTiming, materializedCount) = repeated(count: 30) {
        let run = timed { storage.string.utf8.count }
        return (run.value, run.seconds)
      }

      // The scan the bridge accompanies, measured in the same test so the two numbers are
      // comparable without crossing a suite boundary.
      let document = PerfFixture.screenplay
      let line = document.prosaicLine(atOrAfter: 3000)
      let at = document.midpoint(ofLine: line)
      let (edited, edit) = document.applying("s", over: at..<at)
      let (scanTiming, _) = repeated(count: 20) {
        var scanner = EscriboScanner(language: .fountain)
        scanner.fullScan(document.text)
        let run = timed { scanner.incrementalScan(edit, in: edited.text) }
        return (run.value, run.seconds)
      }

      report("dl75-bridge", bridgeTiming)
      report("dl75-bridge-materialized", materializedTiming)
      report("dl75-accompanying-scan", scanTiming)
      observe(
        "dl75-verdict",
        String(
          format:
            "%.3f ms per keystroke — %.0f%% of the 1 ms in-line-edit budget, and %.0f× the "
            + "cost of the incremental scan it accompanies",
          bridgeTiming.bestMS, bridgeTiming.bestMS * 100,
          bridgeTiming.best / max(scanTiming.best, .leastNonzeroMagnitude)))

      #expect(bridgedCount == PerfFixture.screenplay.utf16Count)
      #expect(materializedCount >= PerfFixture.screenplay.utf16Count)
    }

    /// DL-56 — `EditorCoordinator` skips scanning entirely while an IME composition is in
    /// flight and sets `needsFullRescan`, so the first edit after the composition ends runs
    /// `restyleEverything()` — a **full** scan of the document plus a full restyle. The
    /// scan half of that cost is exactly the cold-scan number; this restates it as what a
    /// CJK or Japanese typist pays per committed composition. Reported, never asserted.
    @Test("DL-56: the post-IME-composition full rescan, observed")
    func postCompositionFullRescan() {
      let document = PerfFixture.screenplay
      let (timing, result) = repeated(count: 10) {
        var scanner = EscriboScanner(language: .fountain)
        scanner.fullScan(document.text)
        // The composition ended; the coordinator's recovery path is a full scan, not an
        // incremental one, because it has no edit it can trust.
        let run = timed { scanner.fullScan(document.text) }
        return (run.value, run.seconds)
      }

      report("dl56-post-ime-full-rescan", timing)
      observe(
        "dl56-verdict",
        String(
          format: "%.3f ms per committed composition — %.0f× the 1 ms in-line-edit budget",
          timing.bestMS, timing.bestMS))

      #expect(result.lines.count == document.lineCount)
      #expect(result.dirtyRange == 0..<document.utf16Count)
    }
  }

  // MARK: - LineIndex linearity

  /// Moved here from Sortie 3: line indexing must stay linear in document length, and a
  /// degenerate single-line document — one line, no terminators, a megabyte long — is
  /// where a hidden quadratic hides. `LineIndex` reads in 4 096-unit chunks, so a
  /// per-chunk cost that were itself O(offset) would turn the whole index quadratic and
  /// nothing about the line count would show it.
  ///
  /// ## The tolerance on the ratio, and why it is not a quiet widening
  ///
  /// The criterion is "1 MB indexes within **4×** the time of 250 KB", over exactly 4× the
  /// data. A perfectly linear algorithm therefore sits at exactly 4.000, which makes a
  /// bare `ratio <= 4.0` a coin flip rather than a gate — and it has already landed on
  /// both sides: this same test measured **4.005** against an unoptimized build and
  /// **3.948** against an optimized one. Neither number is a regression; they are the same
  /// linear algorithm read twice.
  ///
  /// So the assertion carries an explicit 10% measurement tolerance — `ratio <= 4.4` — and
  /// the raw ratio is printed on every run. This is deliberately *not* a threshold chosen
  /// to make a red test go green: the failure it exists to catch is superlinearity, which
  /// over a 4× length step reads **16×**, and a 4.4 ceiling still rejects that by a factor
  /// of 3.6. What a 4.0 ceiling would add over a 4.4 one is not sensitivity to quadratic
  /// behaviour; it is a 50% chance of a red build per run.
  @Suite("LineIndex linearity")
  struct LineIndexLinearityTests {

    /// 4× the data, plus 10% for measurement noise. See the suite comment.
    static let ratioCeiling = 4.0 * 1.10

    @Test("A 1 MB single line indexes within 4× the time of a 250 KB single line")
    func singleLineLinearity() {
      let short = String(repeating: "a", count: 250_000)
      let long = String(repeating: "a", count: 1_000_000)

      let (shortTiming, shortIndex) = repeated(count: 12) {
        let run = timed { LineIndex(short) }
        return (run.value, run.seconds)
      }
      let (longTiming, longIndex) = repeated(count: 12) {
        let run = timed { LineIndex(long) }
        return (run.value, run.seconds)
      }

      // Both really indexed a one-line document of the stated length. A `LineIndex` that
      // gave up early would be fast and would also be wrong.
      #expect(shortIndex.lineCount == 1)
      #expect(shortIndex.utf16Count == 250_000)
      #expect(longIndex.lineCount == 1)
      #expect(longIndex.utf16Count == 1_000_000)

      let ratio = longTiming.best / max(shortTiming.best, .leastNonzeroMagnitude)
      report("lineindex-250kb", shortTiming)
      report("lineindex-1mb", longTiming)
      observe(
        "lineindex-ratio",
        String(
          format: "%.3f× for 4× the code units (linear = 4.000, quadratic = 16.000)", ratio))

      #expect(
        ratio <= Self.ratioCeiling,
        """
        1 MB indexed \(ratio)× slower than 250 KB for 4× the data. Linear reads 4.0 and \
        quadratic reads 16.0; anything above \(Self.ratioCeiling) is superlinear, not noise.
        """)
    }
  }
}
