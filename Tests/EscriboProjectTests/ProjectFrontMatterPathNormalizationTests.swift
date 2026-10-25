import Foundation
import Testing

@testable import EscriboProject

/// Pins what `ProjectFrontMatter.makeRelative(_:to:)` returns on macOS and iOS.
///
/// ## Why these exist
///
/// The helper was rewritten from `"/"` string surgery to a path-component comparison so
/// that it gives correct answers on Windows (drive letters, backslashes, case-insensitive
/// volumes). Every expectation below was recorded against the string implementation
/// **before** that rewrite, and the suite must keep passing unchanged: the rewrite is a
/// portability fix, not a behavior change, on the platforms this package ships on.
///
/// The bases are synthetic absolute paths (`/proj/podcast`), not real directories. The
/// helper never touches the file system, and a path anchored under a developer's home
/// directory does not exist on a CI runner. The tilde cases read the home directory at
/// run time for the same reason.
#if !os(Windows)
  @Suite("ProjectFrontMatter.makeRelative — POSIX behavior")
  struct ProjectFrontMatterPathNormalizationTests {

    private let base = URL(fileURLWithPath: "/proj/podcast", isDirectory: true)

    private func rel(_ path: String, _ base: URL? = nil) -> String {
      ProjectFrontMatter.makeRelative(path, to: base ?? self.base)
    }

    // MARK: Pass-through

    @Test("empty string passes through")
    func emptyPassesThrough() {
      #expect(rel("") == "")
    }

    /// The fixture corpus writes exactly these values (`episodes`, `audio`,
    /// `audio/intro.m4a`, `episodes/outro.m4a`).
    @Test(
      "already-relative paths pass through byte for byte",
      arguments: [
        "episodes", "audio", "audio/intro.m4a", "episodes/outro.m4a",
        "./episodes", "../shared/audio", "episodes/", "a//b",
      ])
    func relativePassesThrough(_ path: String) {
      #expect(rel(path) == path)
    }

    @Test("a tilde naming no known user is not absolute and passes through")
    func unknownUserTildePassesThrough() {
      #expect(rel("~no-such-user-escribo/audio") == "~no-such-user-escribo/audio")
    }

    // MARK: Inside the base

    @Test("absolute path inside the base loses the base prefix")
    func insideBase() {
      #expect(rel("/proj/podcast/episodes") == "episodes")
      #expect(rel("/proj/podcast/audio/intro.m4a") == "audio/intro.m4a")
    }

    @Test("trailing slashes on target or base are ignored")
    func trailingSlashes() {
      #expect(rel("/proj/podcast/episodes/") == "episodes")
      let slashed = URL(fileURLWithPath: "/proj/podcast/", isDirectory: true)
      #expect(rel("/proj/podcast/episodes", slashed) == "episodes")
      #expect(rel("/proj/podcast/", slashed) == ".")
    }

    @Test("a path identical to the base is \".\"")
    func identicalPaths() {
      #expect(rel("/proj/podcast") == ".")
      #expect(rel("/proj/podcast/") == ".")
    }

    @Test("dot segments in the target are standardized away")
    func dotSegments() {
      #expect(rel("/proj/podcast/./episodes") == "episodes")
      #expect(rel("/proj/podcast/episodes/../audio") == "audio")
      #expect(rel("/proj/other/../podcast/audio") == "audio")
    }

    // MARK: Outside the base

    @Test("absolute path outside the base is a ../ traversal")
    func outsideBase() {
      #expect(rel("/proj/audio") == "../audio")
      #expect(rel("/proj/audio/intro.m4a") == "../audio/intro.m4a")
      #expect(rel("/elsewhere/media/outro.m4a") == "../../elsewhere/media/outro.m4a")
    }

    @Test("an ancestor of the base is only ../ segments")
    func ancestorOfBase() {
      #expect(rel("/proj") == "..")
      #expect(rel("/") == "../..")
    }

    @Test("a sibling sharing a name prefix is not treated as inside the base")
    func namePrefixSibling() {
      #expect(rel("/proj/podcast-extras/intro.m4a") == "../podcast-extras/intro.m4a")
      #expect(rel("/proj/podcastX") == "../podcastX")
    }

    @Test("components compare case-sensitively on POSIX")
    func caseSensitive() {
      #expect(rel("/proj/Podcast/episodes") == "../Podcast/episodes")
    }

    @Test("root as the base")
    func rootBase() {
      let root = URL(fileURLWithPath: "/", isDirectory: true)
      #expect(rel("/proj/episodes", root) == "proj/episodes")
      #expect(rel("/", root) == ".")
    }

    // MARK: Tilde

    @Test("leading ~ expands to the home directory, then relativizes")
    func tildeExpansion() {
      let home = URL(fileURLWithPath: NSString(string: "~").expandingTildeInPath, isDirectory: true)
      #expect(rel("~/podcast/episodes", home) == "podcast/episodes")
      #expect(rel("~", home) == ".")
      #expect(rel("~/", home) == ".")
      let inside = home.appendingPathComponent("podcast", isDirectory: true)
      #expect(rel("~/audio/intro.m4a", inside) == "../audio/intro.m4a")
    }

    // MARK: Through the public surface

    @Test("normalizingPaths(relativeTo:) relativizes the four path fields only")
    func normalizingPathsFields() {
      let original = ProjectFrontMatter(
        title: "T",
        author: "A",
        episodesDir: "/proj/podcast/episodes",
        audioDir: "/proj/audio",
        filePattern: "/proj/podcast/*.fountain",
        introFile: "audio/intro.m4a",
        outroFile: "/proj/podcast/audio/outro.m4a",
        preGenerateHook: "/usr/bin/true"
      )
      let normalized = original.normalizingPaths(relativeTo: base)
      #expect(normalized.episodesDir == "episodes")
      #expect(normalized.audioDir == "../audio")
      #expect(normalized.introFile == "audio/intro.m4a")
      #expect(normalized.outroFile == "audio/outro.m4a")
      #expect(normalized.filePattern == original.filePattern)
      #expect(normalized.preGenerateHook == original.preGenerateHook)
    }
  }
#endif
