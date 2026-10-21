---
type: test-cleanup-report
state: complete
---

# Test Cleanup Report: OPERATION PRESSED FLOWER

Scope: 22 test files added or modified since 42ff695 (about 150 tests). Scanned for hardcoded local paths, network calls, env-var gates, unseeded randomness, sleeps, Date()/now, Dictionary/Set order, skips, empty tests and duplicates.

## Removed

None (N = 0). No test matched a high-confidence CI-failure pattern.

## Flagged for Review

| file:test | concern | recommended action |
|---|---|---|
| Tests/SwiftEscriboTests/MacFindHookTests.swift: all 4 tests (via `searchForThe`, ⌘E / `.setSearchString`) | Writes the search string to the system find pasteboard (shared system state); can disturb a developer's local find buffer and race other apps. Suite is `.serialized`, which only protects within the process. | Keep for CI (passes on runners). If it bites locally, inject a named NSPasteboard as MacEmbedBehaviourTests already does. |
| Tests/EscriboPerformanceTests/ScanBudgetTests.swift: budget tests (`bestMS <= 1.0` in-line edit; `<= 50.0` cold/full scans) | Wall-clock assertions. The 1 ms in-line budget is the tightest and the most exposed to a loaded runner; it uses best-of timing, which mitigates this. Suite also self-checks for -Onone builds. | Keep; they are outside `make test` (`make test-performance`). Widen the 1 ms ceiling if it ever flakes. |
| Tests/EscriboPerformanceTests/BlockAlignedEditTests.swift | Same wall-clock class as above. | Same. |
| Tests/SwiftEscriboTests/EmbedLayoutTests.swift lines ~286, 294 | `Task.sleep(50ms)` to let deferred re-vend settle, then asserts. Under the 100 ms threshold but a settle-wait rather than a timing assertion; slow runner could in theory under-wait. | Replace with a deterministic wait on `deferredRevendCount` if it ever flakes. |
| Tests/SwiftEscriboTests/IOSEmbedInputTests.swift line ~64 | `CFRunLoopRunInMode(..., 0.05)` run-loop pump (50 ms). | Same as above. |
| Tests/EscriboCoreTests/ScanGateTests.swift (6 parameterized tests, 1037 lines) | Randomized edit generators, but every draw uses `SeededGenerator` with fixed seeds, so deterministic. File is over 200 lines. | None; verified seeded. |
| Tests/EscriboPerformanceTests/ScanBudgetTests.swift, Tests/SwiftEscriboTests/MacEmbedBehaviourTests.swift, IOSEmbedInputTests.swift (730 / 468 / 471 lines) | Long files; individual tests not over 200 lines on inspection of structure. | None. |
| Tests/EscriboCoreTests/ScanGateTests.swift line 214 | `https://example.com` appears only as fixture text, no network. | None. |

Pasteboard use in MacEmbedBehaviourTests uses uniquely named pasteboards (`escribo.embed.*.<UUID>`), so it is isolated. No env-var gates, skips, hardcoded paths, Date()/now, or unsorted Dictionary/Set assertions were found.

## Build Verification

`make test`: TEST SUCCEEDED (407 tests in 38 suites passed). `make test-performance` not run (no performance test files touched).
