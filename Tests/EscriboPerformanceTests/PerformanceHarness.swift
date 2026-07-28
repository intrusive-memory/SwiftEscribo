import Foundation

import EscriboCore

// MARK: - The document under measurement

/// A document plus the geometry a measurement needs to aim an edit at a line.
///
/// The *text* is vendored (see ``PerfFixture``); the line-start table is computed here
/// because it is measurement scaffolding, not fixture content — recomputing where the
/// newlines are does not synthesize a screenplay, it locates one that was committed.
struct PerfDocument: Sendable {

  /// The document, exactly as loaded (possibly with a documented prologue prepended —
  /// see ``PerfFixture/fenced`` and ``PerfFixture/boneyarded``).
  let text: String

  /// Length in UTF-16 code units. Every offset in this target is a UTF-16 offset, which
  /// is the only coordinate space ``EscriboScanner`` speaks.
  let utf16Count: Int

  /// The UTF-16 offset each line starts at, ascending. `lineStarts.count` is the line
  /// count under the same terminator rules ``LineIndex`` uses for `\n` documents — the
  /// fixture contains no CR, which `PerfFixtureTests` asserts, so the two agree.
  let lineStarts: [Int]

  /// The UTF-16 offset one past the last non-terminator code unit of each line.
  let lineEnds: [Int]

  init(_ text: String) {
    self.text = text
    let units = Array(text.utf16)
    self.utf16Count = units.count

    var starts: [Int] = [0]
    var ends: [Int] = []
    var offset = 0
    while offset < units.count {
      if units[offset] == 0x0A {
        ends.append(offset)
        starts.append(offset + 1)
      }
      offset += 1
    }
    ends.append(units.count)
    self.lineStarts = starts
    self.lineEnds = ends
  }

  var lineCount: Int { lineStarts.count }

  /// The first line at or after `line` whose content is ordinary prose: long enough to
  /// edit in the middle of, and neither blank nor an ALL-CAPS character cue.
  ///
  /// Aiming an edit at "whatever line 3000 happens to be" is how a measurement quietly
  /// becomes a measurement of something else when the fixture changes; this picks a line
  /// by a property the measurement actually depends on.
  func prosaicLine(atOrAfter line: Int) -> Int {
    let units = Array(text.utf16)
    var candidate = min(max(line, 0), lineCount - 1)
    while candidate < lineCount {
      let start = lineStarts[candidate]
      let end = lineEnds[candidate]
      if end - start >= 24 {
        var hasLowercase = false
        for offset in start..<end where units[offset] >= 0x61 && units[offset] <= 0x7A {
          hasLowercase = true
          break
        }
        if hasLowercase { return candidate }
      }
      candidate += 1
    }
    return min(max(line, 0), lineCount - 1)
  }

  /// The middle of `line`, as a UTF-16 offset, never inside a surrogate pair.
  ///
  /// The fixture is UTF-8 with non-ASCII in dialogue; splitting a surrogate pair would
  /// make the edit a different edit than the one the budget is stated for.
  func midpoint(ofLine line: Int) -> Int {
    let start = lineStarts[line]
    let end = lineEnds[line]
    var offset = start + (end - start) / 2
    let units = Array(text.utf16)
    if offset > 0, offset < units.count, units[offset] >= 0xDC00, units[offset] <= 0xDFFF {
      offset -= 1
    }
    return offset
  }

  /// This document with `replacement` spliced in over `range`, plus the matching edit.
  func applying(_ replacement: String, over range: Range<Int>) -> (
    document: PerfDocument, edit: TextEdit
  ) {
    let units = Array(text.utf16)
    var newUnits = Array(units[0..<range.lowerBound])
    newUnits.append(contentsOf: Array(replacement.utf16))
    newUnits.append(contentsOf: Array(units[range.upperBound...]))
    let newText = String(decoding: newUnits, as: UTF16.self)
    return (
      PerfDocument(newText),
      TextEdit(range: range, replacementLength: replacement.utf16.count)
    )
  }
}

// MARK: - The vendored fixture

/// The ~128 KB assembled screenplay, and the two variants that carry an unterminated
/// construct.
///
/// ## Provenance (D-3)
///
/// `Fixtures/long_screenplay.fountain` is **committed**, not generated at test time. It is
/// `episode_10.fountain` + `spanish.fountain` + `episode_01.fountain` — the three
/// screenplays vendored in Sortie 17 — concatenated in that order, three times, joined by
/// a blank line. 130 739 bytes, 6 032 lines, ~128 KB. Repetition is sound here because
/// this target measures scan *throughput*: the scanner has no memory that scene 40
/// duplicates scene 12, and every line it re-reads it re-classifies from scratch.
///
/// It is loaded through `Bundle.module` and nothing else. A path outside the package does
/// not exist on a CI runner, and `Package.swift` declares `.copy("Fixtures")` on this
/// target for exactly this reason — `.copy` rather than `.process` so the committed bytes
/// are the measured bytes.
///
/// ## Why the two unterminated variants are a prologue rather than two more fixtures
///
/// "An edit inside an unterminated fence" needs a long document whose *first* line opens a
/// fence that nothing ever closes; likewise a boneyard. Committing two more 128 KB files
/// that differ from this one by three characters would put 260 KB of near-duplicate bytes
/// in the repository and make it possible for the three copies to drift apart. So the
/// prologue — `` ``` `` or `/*` — is prepended to the committed text, and the fixture
/// itself is asserted to contain neither construct anywhere, which is what makes the
/// prologue provably unterminated for the entire remaining 128 KB.
enum PerfFixture {

  static let resourceName = "long_screenplay"
  static let resourceSubdirectory = "Fixtures"

  /// The committed bytes, undecoded. `nil` when the resource is missing, which every
  /// measurement below turns into a failure rather than into a zero-length document that
  /// passes every budget vacuously.
  static let data: Data? = {
    guard
      let url = Bundle.module.url(
        forResource: resourceName, withExtension: "fountain",
        subdirectory: resourceSubdirectory)
    else { return nil }
    return try? Data(contentsOf: url)
  }()

  static let byteCount: Int = data?.count ?? 0

  static let loaded: Bool = data != nil

  /// The screenplay as committed.
  static let screenplay = PerfDocument(String(decoding: data ?? Data(), as: UTF8.self))

  /// The screenplay under an unterminated fenced code block opened on line 0.
  static let fenced = PerfDocument("```\n" + screenplay.text)

  /// The screenplay under an unterminated boneyard opened on line 0.
  static let boneyarded = PerfDocument("/*\n" + screenplay.text)

  /// A 10 KB paste payload: ASCII, multi-line, and shaped like screenplay body so the
  /// grammar has real classification work to do on every pasted line rather than
  /// 10 240 copies of one character.
  static let pastePayload: String = {
    let stanza = """
      INT. A ROOM - NIGHT

      She crosses to the window and does not open it.

      MARGARET
      We have been here before, and we will be here again.

      """
    var text = ""
    while text.utf16.count < 10240 {
      text += stanza
    }
    // Whole stanzas only — truncating mid-line would paste a half-written cue and change
    // what the grammar has to do with the last line of the paste.
    return text
  }()
}

// MARK: - Timing

/// One measurement: every sample, in seconds, in the order they were taken.
///
/// ## Why the assertions read `min`, not `mean`
///
/// Wall-clock noise on a shared CI runner is one-sided. A scheduler preemption, a
/// competing process, or a thermal excursion can only make a sample *slower* than the
/// machine's actual capability; nothing can make it faster than the work takes. The
/// minimum over N samples is therefore the least noisy estimator available of "how long
/// this code takes on this machine", and it is the only one whose distribution does not
/// grow a tail as the runner gets busier. A mean or a p95 turns every noisy neighbour
/// into a red build, which is precisely the flaky-gate failure mode this target is
/// quarantined out of the PR job to avoid — and a flaky gate gets deleted, which leaves
/// no gate at all.
///
/// The cost of using `min` is that a regression which slows down *some* runs is invisible
/// until it slows down *every* run. That is what the reported (not asserted) 10 ms target
/// is for: `cold-scan:` is printed on every run, so a 5× regression is legible in the log
/// long before it reaches the 50 ms ceiling.
struct Timing: Sendable {
  let samples: [Double]

  var first: Double { samples.first ?? 0 }
  var best: Double { samples.min() ?? 0 }
  var median: Double {
    guard !samples.isEmpty else { return 0 }
    let sorted = samples.sorted()
    return sorted[sorted.count / 2]
  }
  var worst: Double { samples.max() ?? 0 }

  var bestMS: Double { best * 1000 }
  var medianMS: Double { median * 1000 }
  var firstMS: Double { first * 1000 }
  var worstMS: Double { worst * 1000 }
}

/// Times `body` once, returning both its value and the elapsed time.
///
/// `@inline(never)`, and the caller always inspects the returned value, so neither the
/// optimizer nor a release build can delete the work being measured — a budget assertion
/// over a scan that was optimized away is the most trivially unfalsifiable test in this
/// package's reach.
@inline(never)
func timed<R>(_ body: () -> R) -> (value: R, seconds: Double) {
  let clock = ContinuousClock()
  let start = clock.now
  let value = body()
  let elapsed = clock.now - start
  let components = elapsed.components
  return (value, Double(components.seconds) + Double(components.attoseconds) * 1e-18)
}

/// Runs `iteration` `warmup + count` times, discarding the warmups, and returns the
/// timing plus the **last** value produced — which every caller then asserts on, so the
/// thing that was timed is also the thing that is pinned.
func repeated<R>(
  warmup: Int = 3,
  count: Int,
  _ iteration: () -> (value: R, seconds: Double)
) -> (timing: Timing, value: R) {
  var last: R?
  for _ in 0..<warmup {
    last = iteration().value
  }
  var samples: [Double] = []
  samples.reserveCapacity(count)
  for _ in 0..<count {
    let run = iteration()
    samples.append(run.seconds)
    last = run.value
  }
  return (Timing(samples: samples), last!)
}

// MARK: - Build configuration

/// Whether this target was compiled with optimization on (`-O`) rather than `-Onone`.
///
/// ## DL-177 — why this exists, and why it is an assertion rather than a comment
///
/// Every budget in this target is an arm64 **optimized-build** budget, and the Makefile
/// says so at length. Nothing enforced it. Measured on the development machine at
/// `-configuration Debug`, the cold-scan number is 46.98 ms against a 50 ms ceiling: the
/// suite goes **green** while every number it reports is roughly ten times wrong, and a
/// reader of that log has no way to tell. The only assertion that noticed the difference
/// at all was the 1 ms in-line-edit budget, and it noticed by 5% — one busy runner away
/// from not noticing.
///
/// A budget that fails to defend its own build configuration is not a slow gate, it is an
/// unfalsifiable one: it can be satisfied by a run that measured something else entirely.
/// So the configuration is asserted directly, first, before any clock is read.
///
/// ## Why `_isDebugAssertConfiguration()` and not `#if DEBUG`
///
/// `#if DEBUG` tests whether the `DEBUG` *compilation condition* was defined, which is a
/// convention xcodebuild happens to follow for the Debug configuration — it is a proxy for
/// a proxy, and `xcodebuild -Onone -DDEBUG` and `xcodebuild -Onone` are indistinguishable
/// to it in one direction and `-O -DDEBUG` in the other. `_isDebugAssertConfiguration()` is
/// the stdlib's own read of `-Onone` vs `-O` — it is what `assert` is built on — so it
/// answers the question the budgets actually depend on. Verified directly, both ways:
/// `swiftc -Onone` yields `true`, `swiftc -Onone -DDEBUG` yields `true`, and `swiftc -O`
/// yields `false`.
///
/// ## What this proves, and what it does not
///
/// It reads *this target's* compile mode, not `EscriboCore`'s. That is exact rather than
/// approximate for every way this suite can actually be run: `xcodebuild -configuration`
/// applies to every target in the scheme, so there is no invocation of `make
/// test-performance` — or of a hand-typed `xcodebuild test -only-testing` — that builds
/// this target optimized and its dependency `-Onone`. It would stop being exact only if
/// someone set `SWIFT_OPTIMIZATION_LEVEL` on a single target, which is not a drift mode
/// that has a reason to happen.
var isOptimizedBuild: Bool { !_isDebugAssertConfiguration() }

// MARK: - Reporting

/// Prints one measurement in the fixed `name: <N> ms` shape the sortie's exit criteria
/// grep for. Kept in one place so the format cannot drift between call sites.
func report(_ name: String, _ timing: Timing) {
  print(
    String(
      format: "%@: %.3f ms  (median %.3f, first %.3f, worst %.3f, n=%d)",
      name, timing.bestMS, timing.medianMS, timing.firstMS, timing.worstMS,
      timing.samples.count))
}

/// Prints a bare observation — a number this suite reports but does not assert.
func observe(_ name: String, _ value: String) {
  print("\(name): \(value)")
}

// MARK: - Pinning what the scan produced

/// What a ``ScanResult`` actually contains, reduced to the handful of facts a budget
/// assertion has to pin.
///
/// A wall-clock budget passes trivially if the scan it timed did no work: a scanner that
/// returned an empty span array in 40 ns would satisfy every threshold in this file. Each
/// measurement therefore also asserts these — that the spans exist, that they exactly tile
/// the dirty range with no gap, no overlap, and no empty span, and that the dirty range is
/// the size the case is *about*.
struct ScanFacts {
  let dirtyRange: Range<Int>
  let spanCount: Int
  let lineCount: Int
  let recordCount: Int
  /// Sum of every span's length. Equal to `dirtyRange.count` exactly when the spans tile.
  let coveredUnits: Int
  /// Whether the spans are ordered, non-overlapping, non-empty, and contiguous from
  /// `dirtyRange.lowerBound` to `dirtyRange.upperBound`.
  let tilesExactly: Bool
  /// The distinct element kinds the scan classified. A scan that classified everything as
  /// one kind did not do the work this fixture exists to make it do.
  let elementKinds: Set<String>

  init(_ result: ScanResult) {
    self.dirtyRange = result.dirtyRange
    self.spanCount = result.spans.count
    self.lineCount = result.lines.count
    self.recordCount = result.lineRecords.count
    self.coveredUnits = result.spans.reduce(0) { $0 + $1.range.count }

    var tiles = !result.spans.isEmpty
    var cursor = result.dirtyRange.lowerBound
    for span in result.spans {
      if span.range.lowerBound != cursor || span.range.isEmpty {
        tiles = false
        break
      }
      cursor = span.range.upperBound
    }
    if cursor != result.dirtyRange.upperBound { tiles = false }
    self.tilesExactly = tiles

    self.elementKinds = Set(result.lineRecords.map(\.element.rawValue))
  }
}
