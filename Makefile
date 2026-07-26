SCHEME = SwiftEscribo
DESTINATION = 'platform=macOS,arch=arm64'
IOS_DESTINATION = 'platform=iOS Simulator,name=iPhone 17,OS=26.1'

# Apple Silicon only. Intel and Rosetta are out of scope, and an accidental
# x86_64 or universal build makes the performance suite report numbers for a
# machine nobody ships on. Pin the arch on every invocation, never infer it.
ARCH = ARCHS=arm64 ONLY_ACTIVE_ARCH=YES

.PHONY: build test test-core test-ios test-performance clean resolve lint help

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
test-performance:
	xcodebuild test -scheme $(SCHEME) \
	  -destination $(DESTINATION) \
	  -only-testing:EscriboPerformanceTests \
	  $(ARCH)

clean:
	xcodebuild clean -scheme $(SCHEME) -destination $(DESTINATION)
	rm -rf .build

resolve:
	swift package resolve

lint:
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
	@echo "  lint              - Format all Swift source files"
	@echo "  help              - Show this help message"
	@echo ""
	@echo "All targets build arm64 only. Apple Silicon is the only supported arch."
