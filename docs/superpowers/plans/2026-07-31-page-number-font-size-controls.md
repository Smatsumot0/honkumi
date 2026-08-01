# Page Number Font Size Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove all font-specific size adjustments from footer and table-of-contents page numbers, and add a persisted table-of-contents page-number size control that is visible only when table-of-contents output is enabled.

**Architecture:** Add an independent `tableOfContentsPageNumberSize` value to `EditorSettings`, migrate missing values from the document's body size, and resolve paid/free effective sizes in `PageLayout`. Keep font selection and fallback in `AppFontCatalog`, but make the requested effective size the final `UIFont` point size with no font-specific delta. Drive the conditional SwiftUI row through a small `SettingsViewModel` presentation property so visibility and mutation are testable without a UI inspection dependency.

**Tech Stack:** Swift, SwiftUI, UIKit, Core Graphics, Codable, XCTest, Xcode

## Global Constraints

- Treat `docs/superpowers/specs/2026-07-31-page-number-font-size-controls-design.md` as the source of truth.
- Footer and table-of-contents page-number sizes must not vary by body font or dedicated page-number font.
- The table-of-contents page-number setting range is 6pt through 18pt with 0.5pt UI steps.
- New documents default the table-of-contents page-number size to 9pt.
- Existing documents without the new key migrate from their stored body font size, clamped to 6pt through 18pt.
- The table-of-contents size row is visible only while `showTableOfContents` is true.
- The new size control uses the same paid-lock behavior as the existing footer `ノンブルサイズ` control.
- Preserve table-of-contents body, punctuation, long-vowel, leader-character, font-selection, fallback, numbering, and visibility behavior.
- Preserve unrelated working-tree changes and untracked files; stage only files named by the current task.

---

### Task 1: Persist and Migrate the Table-of-Contents Page-Number Size

**Files:**

- Create: `HonkumiTests/PageNumberSizeSettingsTests.swift`
- Modify: `Honkumi/Shared/Models/EditorSettings.swift:4-318`
- Modify: `Honkumi/Shared/Services/UserDefaultSettingsApplication.swift:25-54`
- Modify: `HonkumiTests/UserDefaultSettingsReviewTests.swift:208-305`

**Interfaces:**

- Consumes: `EditorSettings.fontSize`, `EditorSettings.validated`, `EditorSettings` Codable implementation
- Produces: `EditorSettings.tableOfContentsPageNumberSize: CGFloat`
- Produces: `EditorSettings.tableOfContentsPageNumberSizeRange: ClosedRange<CGFloat>` equal to `6...18`
- Preserves: all existing initializer call sites by giving the new initializer parameter a default of `9`

- [ ] **Step 1: Write failing settings and migration tests**

Create `HonkumiTests/PageNumberSizeSettingsTests.swift`:

```swift
import CoreGraphics
import Foundation
@testable import Honkumi
import XCTest

final class PageNumberSizeSettingsTests: XCTestCase {
    func testTableOfContentsPageNumberSizeRoundTripsAndValidates() throws {
        var settings = EditorSettings.default
        settings.tableOfContentsPageNumberSize = 10.5

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(EditorSettings.self, from: encoded)

        XCTAssertEqual(decoded.tableOfContentsPageNumberSize, 10.5)

        settings.tableOfContentsPageNumberSize = 99
        XCTAssertEqual(settings.validated.tableOfContentsPageNumberSize, 18)

        settings.tableOfContentsPageNumberSize = 1
        XCTAssertEqual(settings.validated.tableOfContentsPageNumberSize, 6)
    }

    func testMissingTableOfContentsPageNumberSizeMigratesFromBodySize() throws {
        var legacySettings = EditorSettings.default
        legacySettings.fontSize = 12.5
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(legacySettings)
            ) as? [String: Any]
        )
        object.removeValue(forKey: "tableOfContentsPageNumberSize")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let migrated = try JSONDecoder().decode(EditorSettings.self, from: legacyData)

        XCTAssertEqual(migrated.tableOfContentsPageNumberSize, 12.5)
    }

    func testMigratedBodySizeIsClampedToTableOfContentsRange() throws {
        var legacySettings = EditorSettings.default
        legacySettings.fontSize = 20
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(legacySettings)
            ) as? [String: Any]
        )
        object.removeValue(forKey: "tableOfContentsPageNumberSize")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let migrated = try JSONDecoder().decode(EditorSettings.self, from: legacyData)

        XCTAssertEqual(migrated.tableOfContentsPageNumberSize, 18)
    }
}
```

In `testPrintSelectionChangesOnlyPrintSettingsAndPreservesWorkColophon()` in `HonkumiTests/UserDefaultSettingsReviewTests.swift`, add:

```swift
defaults.tableOfContentsPageNumberSize = 12.5
```

and, after the existing `pageNumberSize` assertion:

```swift
XCTAssertEqual(store.document.settings.tableOfContentsPageNumberSize, 12.5)
```

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -only-testing:HonkumiTests/PageNumberSizeSettingsTests \
  -only-testing:HonkumiTests/UserDefaultSettingsReviewTests/testPrintSelectionChangesOnlyPrintSettingsAndPreservesWorkColophon \
  test
```

Expected: build fails because `EditorSettings` does not yet define `tableOfContentsPageNumberSize`. This is the expected missing-interface failure; do not change the tests to use an existing field.

- [ ] **Step 3: Add the persisted setting and legacy migration**

In `EditorSettings.swift`:

```swift
static let tableOfContentsPageNumberSizeRange: ClosedRange<CGFloat> = 6...18
```

Add the stored property adjacent to `pageNumberSize`:

```swift
var tableOfContentsPageNumberSize: CGFloat
```

Add the initializer parameter adjacent to `pageNumberSize`:

```swift
tableOfContentsPageNumberSize: CGFloat = 9,
```

Assign it in the initializer:

```swift
self.tableOfContentsPageNumberSize = tableOfContentsPageNumberSize
```

Set the explicit default next to `pageNumberSize: 7`:

```swift
tableOfContentsPageNumberSize: 9,
```

Pass the validated value from `validated`:

```swift
tableOfContentsPageNumberSize: tableOfContentsPageNumberSize.clamped(
    to: Self.tableOfContentsPageNumberSizeRange
),
```

Add `tableOfContentsPageNumberSize` to `CodingKeys`. In `init(from:)`, decode `fontSize` once before `self.init` so the migration uses the saved body size:

```swift
let decodedFontSize = try container.decodeIfPresent(CGFloat.self, forKey: .fontSize)
    ?? defaults.fontSize
let decodedTableOfContentsPageNumberSize = try container.decodeIfPresent(
    CGFloat.self,
    forKey: .tableOfContentsPageNumberSize
) ?? decodedFontSize.clamped(to: Self.tableOfContentsPageNumberSizeRange)
```

Use `decodedFontSize` for `fontSize:` and pass:

```swift
tableOfContentsPageNumberSize: decodedTableOfContentsPageNumberSize,
```

Encode the new property adjacent to `pageNumberSize`:

```swift
try container.encode(
    tableOfContentsPageNumberSize,
    forKey: .tableOfContentsPageNumberSize
)
```

In `UserDefaultSettingsApplication.swift`, copy the property in the `selection.print` branch:

```swift
applied.tableOfContentsPageNumberSize = defaults.tableOfContentsPageNumberSize
```

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the Step 2 command again.

Expected: all selected tests pass, including round-trip, legacy migration, clamping, and user-default print-setting application.

- [ ] **Step 5: Review and commit Task 1 only**

Run:

```bash
git diff --check -- \
  Honkumi/Shared/Models/EditorSettings.swift \
  Honkumi/Shared/Services/UserDefaultSettingsApplication.swift \
  HonkumiTests/PageNumberSizeSettingsTests.swift \
  HonkumiTests/UserDefaultSettingsReviewTests.swift
git add \
  Honkumi/Shared/Models/EditorSettings.swift \
  Honkumi/Shared/Services/UserDefaultSettingsApplication.swift \
  HonkumiTests/PageNumberSizeSettingsTests.swift \
  HonkumiTests/UserDefaultSettingsReviewTests.swift
git commit -m "Add table of contents page number size setting"
```

Expected: only the four listed files are committed.

---

### Task 2: Remove Font-Specific Page-Number Size Adjustments

**Files:**

- Create: `HonkumiTests/PageNumberFontSizeTests.swift`
- Modify: `Honkumi/Shared/Models/AppFont.swift:93-195,364-493`
- Modify: `Honkumi/Shared/Models/PageLayout.swift:25-37`
- Modify: `Honkumi/Shared/Services/PDFExportService.swift:1193-1215,2140-2160,2297-2310`

**Interfaces:**

- Consumes: `EditorSettings.pageNumberSize`, `EditorSettings.tableOfContentsPageNumberSize`, paid/free page-number-font entitlement
- Produces: `PageLayout.effectiveTableOfContentsPageNumberFontSize(isPageNumberFontUnlocked:) -> CGFloat`
- Produces: footer and table-of-contents page-number `UIFont.pointSize` equal to the effective requested size
- Preserves: dedicated font selection, body-font fallback, table-of-contents leader selection, and body glyph adjustments

- [ ] **Step 1: Write failing no-adjustment tests against the current font factories**

Create `HonkumiTests/PageNumberFontSizeTests.swift`:

```swift
import CoreGraphics
@testable import Honkumi
import XCTest

final class PageNumberFontSizeTests: XCTestCase {
    func testFooterSizeDoesNotVaryByBodyOrDedicatedFont() {
        let requestedSize: CGFloat = 11.5

        for bodyFont in AppFontCatalog.all {
            XCTAssertEqual(
                AppFontCatalog.pdfPageNumberUIFont(
                    pageNumberFontId: nil,
                    bodyFontId: bodyFont.id,
                    size: requestedSize,
                    isPageNumberFontUnlocked: false
                ).pointSize,
                requestedSize,
                accuracy: 0.001
            )
        }

        for pageNumberFont in AppFontCatalog.pageNumberFonts {
            XCTAssertEqual(
                AppFontCatalog.pdfPageNumberUIFont(
                    pageNumberFontId: pageNumberFont.id,
                    bodyFontId: AppFontCatalog.defaultFontId,
                    size: requestedSize,
                    isPageNumberFontUnlocked: true
                ).pointSize,
                requestedSize,
                accuracy: 0.001
            )
        }
    }

    func testTableOfContentsSizeDoesNotVaryByBodyOrDedicatedFont() {
        let requestedSize: CGFloat = 10.5

        for bodyFont in AppFontCatalog.all {
            XCTAssertEqual(
                AppFontCatalog.pdfTableOfContentsPageNumberUIFont(
                    pageNumberFontId: nil,
                    bodyFontId: bodyFont.id,
                    bodyFontSize: requestedSize,
                    glyphScale: 1,
                    isPageNumberFontUnlocked: false
                ).pointSize,
                requestedSize,
                accuracy: 0.001
            )
        }

        for pageNumberFont in AppFontCatalog.pageNumberFonts {
            XCTAssertEqual(
                AppFontCatalog.pdfTableOfContentsPageNumberUIFont(
                    pageNumberFontId: pageNumberFont.id,
                    bodyFontId: AppFontCatalog.defaultFontId,
                    bodyFontSize: requestedSize,
                    glyphScale: 1,
                    isPageNumberFontUnlocked: true
                ).pointSize,
                requestedSize,
                accuracy: 0.001
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
  -only-testing:HonkumiTests/PageNumberFontSizeTests \
  test
```

Expected: assertions fail because current body-font and dedicated-font deltas change both requested sizes.

- [ ] **Step 3: Make the smallest behavior change to remove deltas**

Temporarily keep the current function signatures so the red tests continue to compile, but change their bodies to:

```swift
static func pdfPageNumberFontSize(
    pageNumberFontId: String?,
    bodyFontId: String,
    baseSize: CGFloat,
    isPageNumberFontUnlocked: Bool
) -> CGFloat {
    max(baseSize, 6)
}

static func pdfTableOfContentsPageNumberFontSize(
    pageNumberFontId: String?,
    bodyFontId: String,
    baseSize: CGFloat,
    glyphScale: CGFloat,
    isPageNumberFontUnlocked: Bool
) -> CGFloat {
    max(baseSize, 1)
}
```

Do not alter `pdfVerticalGlyphFontSize`, `pdfVerticalGlyphPositionOffset`, or `usesDotLeaderInTableOfContents`.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the Step 2 command again.

Expected: both no-adjustment tests pass for all five body fonts and all eight dedicated page-number fonts.

- [ ] **Step 5: Add a failing effective-size test to the green suite**

Append to `PageNumberFontSizeTests`:

```swift
func testPageLayoutResolvesPaidAndFreeTableOfContentsSizes() {
    var settings = EditorSettings.default
    settings.tableOfContentsPageNumberSize = 12.5
    let layout = LayoutCalculator.layout(for: settings, pageNumber: 1)

    XCTAssertEqual(
        layout.effectiveTableOfContentsPageNumberFontSize(
            isPageNumberFontUnlocked: true
        ),
        12.5
    )
    XCTAssertEqual(
        layout.effectiveTableOfContentsPageNumberFontSize(
            isPageNumberFontUnlocked: false
        ),
        EditorSettings.default.tableOfContentsPageNumberSize
    )
}
```

Run the Step 2 command.

Expected: build fails because `PageLayout` does not yet provide `effectiveTableOfContentsPageNumberFontSize`.

- [ ] **Step 6: Add effective size resolution and route PDF drawing through it**

In `PageLayout.swift`, add next to `effectivePageNumberFontSize`:

```swift
func effectiveTableOfContentsPageNumberFontSize(
    isPageNumberFontUnlocked: Bool
) -> CGFloat {
    if isPageNumberFontUnlocked {
        return max(settings.tableOfContentsPageNumberSize, 6)
    }

    return max(EditorSettings.default.tableOfContentsPageNumberSize, 6)
}
```

In the table-of-contents page-number branch of `PDFExportService.pdfAttributes`, pass that effective value as the final size. During the later signature cleanup this call becomes:

```swift
attributes[.font] = AppFontCatalog.pdfTableOfContentsPageNumberUIFont(
    pageNumberFontId: layout.settings.pageNumberFontId,
    bodyFontId: layout.settings.selectedFontId,
    size: layout.effectiveTableOfContentsPageNumberFontSize(
        isPageNumberFontUnlocked: isAdditionalFontPackUnlocked
    ),
    isPageNumberFontUnlocked: isAdditionalFontPackUnlocked
)
```

The two footer call sites already pass `layout.effectivePageNumberFontSize`; retain them.

- [ ] **Step 7: Refactor away obsolete adjustment data and misleading parameters**

With the suite green, perform a behavior-preserving cleanup:

- Remove `pageNumberDelta` from `PDFBodyFontSizeAdjustment` and from every body-font adjustment entry.
- Delete `PDFPageNumberFontSizeAdjustment`.
- Delete `pageNumberPDFFontSizeAdjustments` and `pageNumberPDFFontSizeAdjustment(pageNumberFontId:)`.
- Replace `pdfPageNumberFontSize(...)` with `pdfPageNumberFontSize(baseSize:)` returning `max(baseSize, 6)`.
- Replace `pdfTableOfContentsPageNumberFontSize(...)` with `pdfTableOfContentsPageNumberFontSize(baseSize:)` returning `max(baseSize, 1)`.
- Change `pdfTableOfContentsPageNumberUIFont` to accept `size:` rather than `bodyFontSize:` and remove `glyphScale:`.
- Update `pdfPageNumberUIFont` to call the simplified footer size function.
- Leave `PDFBodyFontSizeAdjustment.tableOfContentsDelta` and `pdfTableOfContentsBodyFontSize` intact because they describe table-of-contents body text, not page numbers.

The final size resolution inside the two font factories is:

```swift
let adjustedSize = pdfPageNumberFontSize(baseSize: size)
```

and:

```swift
let adjustedSize = pdfTableOfContentsPageNumberFontSize(baseSize: size)
```

Update both calls to `pdfTableOfContentsPageNumberUIFont` in
`testTableOfContentsSizeDoesNotVaryByBodyOrDedicatedFont` to the final labels:

```swift
AppFontCatalog.pdfTableOfContentsPageNumberUIFont(
    pageNumberFontId: nil,
    bodyFontId: bodyFont.id,
    size: requestedSize,
    isPageNumberFontUnlocked: false
).pointSize
```

and:

```swift
AppFontCatalog.pdfTableOfContentsPageNumberUIFont(
    pageNumberFontId: pageNumberFont.id,
    bodyFontId: AppFontCatalog.defaultFontId,
    size: requestedSize,
    isPageNumberFontUnlocked: true
).pointSize
```

- [ ] **Step 8: Run focused tests and verify the refactor remains GREEN**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -only-testing:HonkumiTests/PageNumberFontSizeTests \
  -only-testing:HonkumiTests/PageNumberSizeSettingsTests \
  test
```

Expected: all tests pass after updating the test calls to the simplified signatures.

- [ ] **Step 9: Review and commit Task 2 only**

Run:

```bash
git diff --check -- \
  Honkumi/Shared/Models/AppFont.swift \
  Honkumi/Shared/Models/PageLayout.swift \
  Honkumi/Shared/Services/PDFExportService.swift \
  HonkumiTests/PageNumberFontSizeTests.swift
git add \
  Honkumi/Shared/Models/AppFont.swift \
  Honkumi/Shared/Models/PageLayout.swift \
  Honkumi/Shared/Services/PDFExportService.swift \
  HonkumiTests/PageNumberFontSizeTests.swift
git commit -m "Remove page number font size adjustments"
```

Expected: only the four listed files are committed.

---

### Task 3: Add the Conditional Table-of-Contents Size Control

**Files:**

- Modify: `HonkumiTests/SettingsPrintSnapshotTests.swift:1-100`
- Modify: `Honkumi/Features/Settings/SettingsViewModel.swift:115-145,325-385`
- Modify: `Honkumi/Features/Settings/SettingsView.swift:271-278`

**Interfaces:**

- Consumes: `EditorSettings.showTableOfContents`, `EditorSettings.tableOfContentsPageNumberSize`, `SettingsViewModel.isPageNumberFontUnlocked`
- Produces: `SettingsViewModel.showsTableOfContentsPageNumberSizeSetting: Bool`
- Produces: `SettingsViewModel.updateTableOfContentsPageNumberSize(_ value: CGFloat)`
- Produces: SwiftUI row titled `目次ページ番号サイズ`

- [ ] **Step 1: Write failing view-model behavior tests**

Add to `SettingsPrintSnapshotTests`:

```swift
func testTableOfContentsPageNumberSizeControlTracksOutputAndUpdatesPaidSetting() {
    let store = makeStore(
        document: ManuscriptDocument(title: "Print", body: "本文"),
        subscriptionStatus: .paid
    )
    let viewModel = SettingsViewModel(documentStore: store)

    XCTAssertFalse(viewModel.showsTableOfContentsPageNumberSizeSetting)

    viewModel.updateShowTableOfContents(true)

    XCTAssertTrue(viewModel.showsTableOfContentsPageNumberSizeSetting)
    var expected = viewModel.settings
    expected.tableOfContentsPageNumberSize = 10.5

    viewModel.updateTableOfContentsPageNumberSize(10.5)

    XCTAssertEqual(viewModel.settings, expected)
}

func testFreeUserCannotChangeTableOfContentsPageNumberSize() {
    let store = makeStore(
        document: ManuscriptDocument(title: "Print", body: "本文"),
        subscriptionStatus: .free
    )
    let viewModel = SettingsViewModel(documentStore: store)
    let originalSize = viewModel.settings.tableOfContentsPageNumberSize

    viewModel.updateTableOfContentsPageNumberSize(10.5)

    XCTAssertEqual(
        viewModel.settings.tableOfContentsPageNumberSize,
        originalSize
    )
}
```

Change the test helper signature and its `AppData` construction to:

```swift
private func makeStore(
    document: ManuscriptDocument,
    subscriptionStatus: SubscriptionStatus = .free
) -> DocumentStore {
    DocumentStore(
        appData: AppData(
            version: AppData.currentVersion,
            categories: [.uncategorized],
            works: [document],
            userDefaultSettings: .default,
            activeWorkId: document.id,
            subscriptionStatus: subscriptionStatus
        )
    )
}
```

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -only-testing:HonkumiTests/SettingsPrintSnapshotTests \
  test
```

Expected: build fails because the view model does not yet expose the visibility property or update method.

- [ ] **Step 3: Add the minimal view-model interface**

In `SettingsViewModel.swift`, add:

```swift
var showsTableOfContentsPageNumberSizeSetting: Bool {
    settings.showTableOfContents
}
```

Add near the other page-number updates:

```swift
func updateTableOfContentsPageNumberSize(_ value: CGFloat) {
    guard isPageNumberFontUnlocked else { return }
    var updated = settings
    updated.tableOfContentsPageNumberSize = value
    settings = updated
}
```

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the Step 2 command again.

Expected: both new tests and the existing snapshot ordering test pass.

- [ ] **Step 5: Add the conditional SwiftUI row**

In the existing `Section("目次")`, immediately after the `目次を出力` toggle, add:

```swift
if viewModel.showsTableOfContentsPageNumberSizeSetting {
    valueStepper(
        title: "目次ページ番号サイズ",
        value: viewModel.settings.tableOfContentsPageNumberSize,
        range: EditorSettings.tableOfContentsPageNumberSizeRange,
        step: 0.5,
        format: "%.1f pt",
        update: viewModel.updateTableOfContentsPageNumberSize
    )
    .disabled(!viewModel.isPageNumberFontUnlocked)
}
```

Do not move or change the existing footer `ノンブルサイズ` row.

- [ ] **Step 6: Build the app and re-run focused settings tests**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -only-testing:HonkumiTests/SettingsPrintSnapshotTests \
  test
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  build
```

Expected: focused tests pass and the SwiftUI view builds successfully.

- [ ] **Step 7: Review and commit Task 3 only**

Run:

```bash
git diff --check -- \
  Honkumi/Features/Settings/SettingsView.swift \
  Honkumi/Features/Settings/SettingsViewModel.swift \
  HonkumiTests/SettingsPrintSnapshotTests.swift
git add \
  Honkumi/Features/Settings/SettingsView.swift \
  Honkumi/Features/Settings/SettingsViewModel.swift \
  HonkumiTests/SettingsPrintSnapshotTests.swift
git commit -m "Add table of contents page number size control"
```

Expected: only the three listed files are committed.

---

### Task 4: Run Page-Number and Full Regression Verification

**Files:**

- Verify: `Honkumi/Shared/Models/EditorSettings.swift`
- Verify: `Honkumi/Shared/Models/AppFont.swift`
- Verify: `Honkumi/Shared/Models/PageLayout.swift`
- Verify: `Honkumi/Shared/Services/PDFExportService.swift`
- Verify: `Honkumi/Shared/Services/UserDefaultSettingsApplication.swift`
- Verify: `Honkumi/Features/Settings/SettingsViewModel.swift`
- Verify: `Honkumi/Features/Settings/SettingsView.swift`
- Verify: `HonkumiTests/PageNumberSizeSettingsTests.swift`
- Verify: `HonkumiTests/PageNumberFontSizeTests.swift`
- Verify: `HonkumiTests/UserDefaultSettingsReviewTests.swift`
- Verify: `HonkumiTests/SettingsPrintSnapshotTests.swift`

**Interfaces:**

- Consumes: the complete implementation from Tasks 1-3
- Produces: evidence that focused tests, related regression tests, the full suite, and the simulator build pass

- [ ] **Step 1: Run all focused and adjacent tests together**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -only-testing:HonkumiTests/PageNumberSizeSettingsTests \
  -only-testing:HonkumiTests/PageNumberFontSizeTests \
  -only-testing:HonkumiTests/SettingsPrintSnapshotTests \
  -only-testing:HonkumiTests/UserDefaultSettingsReviewTests \
  -only-testing:HonkumiTests/PrintSettingSamplePDFTests \
  -only-testing:HonkumiTests/PrintSettingSampleManifestTests \
  test
```

Expected: all selected tests pass with no failures.

- [ ] **Step 2: Run the full XCTest suite**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test
```

Expected: the full suite passes with no test failures.

- [ ] **Step 3: Run final simulator build verification**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  build
```

Expected: `BUILD SUCCEEDED` with no new warnings caused by unused adjustment types or parameters.

- [ ] **Step 4: Audit the final scoped diff**

Run:

```bash
git diff --check HEAD~3 -- \
  Honkumi/Shared/Models/EditorSettings.swift \
  Honkumi/Shared/Models/AppFont.swift \
  Honkumi/Shared/Models/PageLayout.swift \
  Honkumi/Shared/Services/PDFExportService.swift \
  Honkumi/Shared/Services/UserDefaultSettingsApplication.swift \
  Honkumi/Features/Settings/SettingsViewModel.swift \
  Honkumi/Features/Settings/SettingsView.swift \
  HonkumiTests/PageNumberSizeSettingsTests.swift \
  HonkumiTests/PageNumberFontSizeTests.swift \
  HonkumiTests/UserDefaultSettingsReviewTests.swift \
  HonkumiTests/SettingsPrintSnapshotTests.swift
```

Expected: no whitespace errors. Confirm the scoped diff contains no changes to chapter-title, colophon, body-glyph, leader, page-number visibility, or numbering behavior.
