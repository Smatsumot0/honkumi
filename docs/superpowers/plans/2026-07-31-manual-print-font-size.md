# Manual Print Font Size Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure manually selected print font sizes from 7pt through 20pt render unchanged in preview and PDF output.

**Architecture:** Keep half-point rounding and supported-range validation in `EditorSettings.validated`, and keep readable automatic density decisions in `RecommendedPrintSettings`. Remove the second geometry-derived font-size rewrite from `LayoutCalculator` so `PageLayout.fontSize` receives the accepted setting directly.

**Tech Stack:** Swift, Core Graphics, XCTest, Xcode

## Global Constraints

- Treat `docs/superpowers/specs/2026-07-31-manual-print-font-size-design.md` as the source of truth.
- A manually selected print font size from 7pt through 20pt must be used as the rendered body font size in preview and PDF output.
- Manual `charactersPerLine` and `linesPerPage` values must not be changed automatically.
- Recommended typography must continue to choose readable font-size, character-count, and line-count combinations.
- Print font sizes must remain rounded to 0.5pt and clamped to the supported 7pt through 20pt range.
- Do not change settings UI, persistence, pagination, or recommendation presets.
- Preserve unrelated working-tree changes and untracked files.

---

### Task 1: Preserve Manual Font Size Through Layout

**Files:**

- Create: `HonkumiTests/LayoutCalculatorTests.swift`
- Modify: `Honkumi/Shared/Services/LayoutCalculator.swift:24-31`
- Modify: `Honkumi/Shared/Services/LayoutCalculator.swift:50-61`

**Interfaces:**

- Consumes: `EditorSettings.validated`, `LayoutCalculator.layout(for:pageNumber:)`
- Produces: `PageLayout.fontSize` equal to the validated `EditorSettings.fontSize`
- Preserves: `RecommendedPrintSettings` as the only automatic readable-density decision point

- [ ] **Step 1: Add the failing layout regression test**

Create `HonkumiTests/LayoutCalculatorTests.swift` with a real
`LayoutCalculator` test. The production mutation this catches is restoring any
geometry-derived ceiling that makes 12.5pt and 20pt render at the same smaller
size.

```swift
import CoreGraphics
@testable import Honkumi
import XCTest

final class LayoutCalculatorTests: XCTestCase {
    func testManualFontSizesAboveNaturalAdvanceRemainUnchanged() {
        for requestedFontSize in [CGFloat(12.5), CGFloat(20)] {
            var settings = EditorSettings.default
            settings.pageSize = .a6
            settings.fontSize = requestedFontSize
            settings.useRecommendedTypography = false
            settings.useRecommendedMargins = false

            let layout = LayoutCalculator.layout(for: settings, pageNumber: 1)

            XCTAssertEqual(
                layout.fontSize,
                requestedFontSize,
                accuracy: 0.001,
                "\(requestedFontSize)pt should remain unchanged"
            )
        }
    }
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -only-testing:HonkumiTests/LayoutCalculatorTests \
  test
```

Expected: FAIL because the existing `validatedFontSize` calculation reduces
both requested values to the geometry-derived maximum of about 12pt. Confirm
the failure is an assertion mismatch, not a build or test-discovery error.

- [ ] **Step 3: Remove the hidden layout-time font-size ceiling**

In `LayoutCalculator.layout(for:pageNumber:)`, remove the call to
`validatedFontSize(requestedFontSize:lineAdvance:characterAdvance:)` and pass
the already validated setting into `PageLayout`:

```swift
return PageLayout(
    pageNumber: pageNumber,
    pageSize: validatedSettings.pageSize,
    pageWidth: pageWidth,
    pageHeight: pageHeight,
    bodyFrame: bodyFrame,
    marginTop: marginTop,
    marginBottom: marginBottom,
    marginInner: marginInner,
    marginOuter: marginOuter,
    lineAdvance: lineAdvance,
    characterAdvance: characterAdvance,
    fontSize: validatedSettings.fontSize,
    settings: validatedSettings
)
```

Delete the now-unused private
`validatedFontSize(requestedFontSize:lineAdvance:characterAdvance:)` function.
Do not change line advance, character advance, or any settings values.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the Step 2 command again.

Expected: PASS for both 12.5pt and 20pt.

- [ ] **Step 5: Verify recommended typography remains readable**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -only-testing:HonkumiTests/RecommendedPrintSettingsTests \
  test
```

Expected: PASS, including the character-advance and line-advance readability
ratios for every recommendation band.

- [ ] **Step 6: Run the full XCTest suite**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test
```

Expected: PASS with no test failures.

- [ ] **Step 7: Run simulator build verification**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 8: Review and commit only the implementation**

Run:

```bash
git diff --check -- \
  Honkumi/Shared/Services/LayoutCalculator.swift \
  HonkumiTests/LayoutCalculatorTests.swift
git diff -- \
  Honkumi/Shared/Services/LayoutCalculator.swift \
  HonkumiTests/LayoutCalculatorTests.swift
git add \
  Honkumi/Shared/Services/LayoutCalculator.swift \
  HonkumiTests/LayoutCalculatorTests.swift
git commit -m "Fix manual print font size rendering"
```

Expected: the commit contains only the layout change and its regression test;
unrelated deletions and untracked files remain untouched.
