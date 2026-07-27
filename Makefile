# SwiftPM's auto-generated per-product scheme (`SwiftEscribo`) has no test action —
# `xcodebuild test -scheme SwiftEscribo` fails with "not currently configured for the
# test action". The `-Package` scheme is the one that contains every target,
# including the three test targets, so it is the only usable scheme here.
SCHEME = SwiftEscribo-Package
DESTINATION = 'platform=macOS,arch=arm64'
IOS_DESTINATION = 'platform=iOS Simulator,name=iPhone 17,OS=26.1'

# Apple Silicon only. Intel and Rosetta are out of scope, and an accidental
# x86_64 or universal build makes the performance suite report numbers for a
# machine nobody ships on. Pin the arch on every invocation, never infer it.
ARCH = ARCHS=arm64 ONLY_ACTIVE_ARCH=YES

.PHONY: build test test-core test-ios test-performance clean resolve lint format help

build:
	xcodebuild build -scheme $(SCHEME) -destination $(DESTINATION) $(ARCH)

test:
	xcodebuild test -scheme $(SCHEME) \
	  -destination $(DESTINATION) \
	  -skip-testing:EscriboPerformanceTests \
	  $(ARCH)

# The parser core has no UI and no fixtures to stage, so this is the fast
# inner loop while working on scanners.
test-core:
	xcodebuild test -scheme $(SCHEME) \
	  -destination $(DESTINATION) \
	  -only-testing:EscriboCoreTests \
	  $(ARCH)

test-ios:
	xcodebuild test -scheme $(SCHEME) \
	  -destination $(IOS_DESTINATION) \
	  -skip-testing:EscriboPerformanceTests \
	  -skipPackagePluginValidation \
	  COMPILER_INDEX_STORE_ENABLE=NO \
	  $(ARCH)

# Budgets are arm64 budgets. Never read a number from this suite that was not
# produced by a native arm64 build.
#
# And never one that was not produced by an **optimized** build. The other targets
# here run Debug, which is `-Onone`: measured on this machine, the same cold scan
# costs 48 ms at -Onone and 3 ms at -O, so a Debug run of this suite reports a
# 16x pessimism that has nothing to do with what ships and would either fail the
# budgets outright or force them to be set sixteen times too loose. `-configuration
# Release` with `ENABLE_TESTABILITY=YES` is the combination that gives an optimized
# build the `@testable import` the LineIndex linearity case needs.
test-performance:
	xcodebuild test -scheme $(SCHEME) \
	  -destination $(DESTINATION) \
	  -only-testing:EscriboPerformanceTests \
	  -configuration Release \
	  ENABLE_TESTABILITY=YES \
	  $(ARCH)

clean:
	xcodebuild clean -scheme $(SCHEME) -destination $(DESTINATION)
	rm -rf .build

resolve:
	swift package resolve

# DL-4. This target used to be `swift format -i -r .` — an in-place formatter that
# rewrote every Swift file in the repo and ran none of the six custom rules in
# `.swiftlint.yml`. Two things were wrong with that, and both are why this target
# changed rather than gaining a sibling:
#
#   1. A lint target is a *gate*, and a gate must not write to the tree it is
#      checking. Wired into CI as it stood, `make lint` would have reformatted the
#      checkout and then reported success on whatever it had just rewritten. Measured
#      on a clean checkout of this commit it rewrites 18 files (68 findings), so a
#      developer who ran it got a dirty worktree and no lint signal at all.
#   2. The three structural rules this package actually depends on —
#      `no_regex_in_scanners`, `no_ui_imports_in_core`, `no_markdown_import_in_sources`
#      — live in `.swiftlint.yml` and were never executed by anything, locally or in
#      CI. `no_markdown_import_in_sources` in particular is the only mechanism keeping
#      `swift-markdown` out of every downstream consumer's dependency graph
#      (EXECUTION_PLAN.md § D-2); SwiftPM prunes a test-only dependency as a graph
#      property and emits no diagnostic when that property stops holding.
#
# The formatter did not go away — it is `make format` below. `make lint` is now
# read-only and its exit status is meaningful, which is what lets
# `.github/workflows/lint.yml` invoke this exact target instead of spelling out
# `swiftlint` itself and drifting from what developers run.
#
# Deliberately not `--strict`: `--strict` promotes SwiftLint's default *style*
# warnings to errors, and this tree has 66 of them (`opening_brace`,
# `inclusive_language`). Those are Sortie 30's to triage. The custom rules that
# matter here all declare `severity: error`, so they fail the build without it.
lint:
	@command -v swiftlint >/dev/null 2>&1 || { \
	  echo "error: swiftlint not found on PATH. Install it with: brew install swiftlint"; \
	  echo "       A missing linter must fail loudly — a skipped gate is not a passed gate."; \
	  exit 1; \
	}
	swiftlint version
	swiftlint lint --quiet

# The formatter that `make lint` used to be. Rewrites files in place, so it is
# never what CI runs.
format:
	swift format -i -r .

help:
	@echo "Available targets:"
	@echo "  build             - Build the SwiftEscribo scheme for macOS (arm64)"
	@echo "  test              - Run macOS tests (excludes performance)"
	@echo "  test-core         - Run only the parser core tests (fast inner loop)"
	@echo "  test-ios          - Run iOS tests on iPhone 17 simulator"
	@echo "  test-performance  - Run only the performance suite (arm64 native)"
	@echo "  clean             - Clean build artifacts"
	@echo "  resolve           - Resolve Swift package dependencies"
	@echo "  lint              - Run SwiftLint (read-only gate; what CI runs)"
	@echo "  format            - Reformat all Swift source files in place"
	@echo "  help              - Show this help message"
	@echo ""
	@echo "All targets build arm64 only. Apple Silicon is the only supported arch."
