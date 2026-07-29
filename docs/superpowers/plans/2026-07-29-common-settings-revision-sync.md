# Common Settings Revision Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Track common-settings revisions, ask before opening an older work, and either apply all current common settings or preserve that work's settings according to the user's choice.

**Architecture:** Persist one monotonically increasing revision on `AppData` and the last reviewed revision on each `ManuscriptDocument`, both decoding legacy data as zero. Keep user decisions atomic in `DocumentStore`, while `WorkListView` owns only the pending native alert and forwards whether the selected work requires the full-format coordinator from the live-formatting plan.

**Tech Stack:** Swift 6, SwiftUI, Foundation Codable, Combine, XCTest, Xcode 26

## Global Constraints

- This plan runs after `2026-07-29-live-and-deferred-formatting.md`; it consumes `ManuscriptFormattingCoordinator`.
- Minimum deployment target remains iOS 26.2.
- Do not add third-party dependencies or a UI-test target.
- `AppData.userDefaultSettingsRevision` decodes missing data as `0`.
- `ManuscriptDocument.reviewedUserDefaultSettingsRevision` decodes missing data as `0`.
- Legacy data with both revisions at `0` must not show an immediate review alert.
- A default-settings sheet session increments the revision at most once, when the sheet closes and the validated full `EditorSettings` value changed.
- The default publisher-information sheet follows the same one-increment-per-session rule.
- Editing several values in one open sheet must not increment several times.
- A new work uses the existing new-work initialization rules and records the current common revision.
- The initial sample and empty-library fallback record the current common revision.
- `適用して開く` copies the complete validated `EditorSettings`, including editor, print, format, and colophon values.
- `適用せず開く` changes only the work's reviewed revision and active selection.
- `キャンセル` changes no persisted state and does not navigate.
- Production preview and PDF output use the work's stored colophon snapshot; they do not overlay the latest common publisher information after a keep/cancel decision.
- The native alert copy uses exactly `適用して開く`, `適用せず開く`, and `キャンセル`.
- Applying common settings requests full formatting only when the applied `enableAutoFormat` is on.
- Preserve unrelated and currently untracked documents and scripts.
- New Swift files are automatically included by File System Synchronized Groups; do not edit `project.pbxproj`.
- Do not run the all-paper-size or all-font-size sample PDF batches.
- Use RED/GREEN test cycles and commit every independently reviewable task.

---

### Task 1: Persist common and per-work revision fields

**Files:**

- Modify: `Honkumi/Shared/Models/AppData.swift`
- Modify: `Honkumi/Shared/Models/ManuscriptDocument.swift`
- Create: `HonkumiTests/CommonSettingsRevisionCodingTests.swift`

**Interfaces:**

- Produces: `AppData.userDefaultSettingsRevision: Int`.
- Produces: `ManuscriptDocument.reviewedUserDefaultSettingsRevision: Int`.
- Changes: `AppData.currentVersion` from `1` to `2`.

- [ ] **Step 1: Write failing Codable migration tests**

Create `HonkumiTests/CommonSettingsRevisionCodingTests.swift`:

```swift
@testable import Honkumi
import XCTest

final class CommonSettingsRevisionCodingTests: XCTestCase {
    func testLegacyAppDataWithoutRevisionDecodesAsZero() throws {
        let document = ManuscriptDocument(title: "Legacy", body: "本文")
        let appData = AppData(
            version: 1,
            categories: [.uncategorized],
            works: [document],
            userDefaultSettings: .default,
            activeWorkId: document.id,
            subscriptionStatus: .free
        )
        let legacyData = try removingKeys(
            ["userDefaultSettingsRevision"],
            from: JSONEncoder().encode(appData)
        )

        let decoded = try JSONDecoder().decode(AppData.self, from: legacyData)

        XCTAssertEqual(decoded.userDefaultSettingsRevision, 0)
    }

    func testLegacyWorkWithoutReviewedRevisionDecodesAsZero() throws {
        let document = ManuscriptDocument(title: "Legacy", body: "本文")
        let legacyData = try removingKeys(
            ["reviewedUserDefaultSettingsRevision"],
            from: JSONEncoder().encode(document)
        )

        let decoded = try JSONDecoder().decode(
            ManuscriptDocument.self,
            from: legacyData
        )

        XCTAssertEqual(decoded.reviewedUserDefaultSettingsRevision, 0)
    }

    func testRevisionFieldsRoundTrip() throws {
        let document = ManuscriptDocument(
            title: "Current",
            body: "本文",
            reviewedUserDefaultSettingsRevision: 7
        )
        let appData = AppData(
            version: AppData.currentVersion,
            categories: [.uncategorized],
            works: [document],
            userDefaultSettings: .default,
            activeWorkId: document.id,
            subscriptionStatus: .free,
            userDefaultSettingsRevision: 9
        )

        let decoded = try JSONDecoder().decode(
            AppData.self,
            from: JSONEncoder().encode(appData)
        )

        XCTAssertEqual(decoded.userDefaultSettingsRevision, 9)
        XCTAssertEqual(
            decoded.works.first?.reviewedUserDefaultSettingsRevision,
            7
        )
    }

    private func removingKeys(_ keys: [String], from data: Data) throws -> Data {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        for key in keys {
            object.removeValue(forKey: key)
        }
        if var works = object["works"] as? [[String: Any]] {
            for index in works.indices {
                for key in keys {
                    works[index].removeValue(forKey: key)
                }
            }
            object["works"] = works
        }
        return try JSONSerialization.data(withJSONObject: object)
    }
}
```

- [ ] **Step 2: Run the coding tests and verify RED**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/CommonSettingsRevisionCodingTests test
```

Expected: compilation fails because both revision properties and the initializer parameters are missing.

- [ ] **Step 3: Add AppData revision coding**

In `AppData`:

```swift
static let currentVersion = 2

var version: Int
var categories: [WorkCategory]
var works: [ManuscriptDocument]
var userDefaultSettings: EditorSettings
var activeWorkId: UUID?
var subscriptionStatus: SubscriptionStatus
var userDefaultSettingsRevision: Int = 0
```

Add `.userDefaultSettingsRevision` to `CodingKeys` and decode it with:

```swift
userDefaultSettingsRevision:
    try container.decodeIfPresent(
        Int.self,
        forKey: .userDefaultSettingsRevision
    ) ?? 0
```

Clamp negative values to zero in `DocumentStore.normalized` later; the model decoder only supplies the legacy default.

- [ ] **Step 4: Add per-work revision coding**

Add this stored property and initializer parameter to `ManuscriptDocument`:

```swift
var reviewedUserDefaultSettingsRevision: Int

init(
    id: UUID = UUID(),
    categoryId: UUID = WorkCategory.uncategorizedId,
    title: String = "無題の原稿",
    body: String = ManuscriptDocument.sampleBody,
    settings: EditorSettings = .default,
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    reviewedUserDefaultSettingsRevision: Int = 0
) {
    self.id = id
    self.categoryId = categoryId
    self.title = title
    self.body = body
    self.settings = settings
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.reviewedUserDefaultSettingsRevision =
        reviewedUserDefaultSettingsRevision
}
```

Add the field to `CodingKeys` and decode:

```swift
reviewedUserDefaultSettingsRevision:
    try container.decodeIfPresent(
        Int.self,
        forKey: .reviewedUserDefaultSettingsRevision
    ) ?? 0
```

- [ ] **Step 5: Run coding tests and existing persistence tests**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/CommonSettingsRevisionCodingTests \
  -only-testing:HonkumiTests/DocumentStorePersistenceTests test
```

Expected: all selected tests pass.

- [ ] **Step 6: Commit Task 1**

```bash
git add Honkumi/Shared/Models/AppData.swift \
  Honkumi/Shared/Models/ManuscriptDocument.swift \
  HonkumiTests/CommonSettingsRevisionCodingTests.swift
git commit -m "Persist common settings revisions"
```

---

### Task 2: Increment the common revision once per completed settings session

**Files:**

- Modify: `Honkumi/Shared/Services/DocumentStore.swift`
- Create: `HonkumiTests/CommonSettingsSessionTests.swift`

**Interfaces:**

- Produces: `DocumentStore.finishUserDefaultSettingsSession(startingFrom:) -> Bool`.
- Preserves: `updateUserDefaultSettings(_:)` as an immediate value update without a revision increment.

- [ ] **Step 1: Write failing session tests**

Create `HonkumiTests/CommonSettingsSessionTests.swift`:

```swift
@testable import Honkumi
import XCTest

@MainActor
final class CommonSettingsSessionTests: XCTestCase {
    func testMultipleChangesIncrementRevisionOnceWhenSessionFinishes() {
        let store = makeStore()
        let initial = store.userDefaultSettings
        var first = initial
        first.editorFontSize = 16
        store.updateUserDefaultSettings(first)
        var second = first
        second.marginInner = 22
        store.updateUserDefaultSettings(second)

        XCTAssertEqual(store.userDefaultSettingsRevision, 0)
        XCTAssertTrue(
            store.finishUserDefaultSettingsSession(startingFrom: initial)
        )
        XCTAssertEqual(store.userDefaultSettingsRevision, 1)
    }

    func testUnchangedSessionDoesNotIncrementRevision() {
        let store = makeStore()

        XCTAssertFalse(
            store.finishUserDefaultSettingsSession(
                startingFrom: store.userDefaultSettings
            )
        )
        XCTAssertEqual(store.userDefaultSettingsRevision, 0)
    }

    func testSecondDistinctSessionIncrementsAgain() {
        let store = makeStore()
        let firstStart = store.userDefaultSettings
        var first = firstStart
        first.editorFontSize = 16
        store.updateUserDefaultSettings(first)
        XCTAssertTrue(
            store.finishUserDefaultSettingsSession(startingFrom: firstStart)
        )

        let secondStart = store.userDefaultSettings
        var second = secondStart
        second.colophon.authorName = "作者"
        store.updateUserDefaultSettings(second)
        XCTAssertTrue(
            store.finishUserDefaultSettingsSession(startingFrom: secondStart)
        )

        XCTAssertEqual(store.userDefaultSettingsRevision, 2)
    }

    private func makeStore() -> DocumentStore {
        DocumentStore(appData: .initial)
    }
}
```

- [ ] **Step 2: Run the session tests and verify RED**

Run the new test class and expect undefined-property/method failures.

- [ ] **Step 3: Add normalized revision access and session completion**

In `DocumentStore` add:

```swift
var userDefaultSettingsRevision: Int {
    appData.userDefaultSettingsRevision
}

@discardableResult
func finishUserDefaultSettingsSession(
    startingFrom initialSettings: EditorSettings
) -> Bool {
    guard initialSettings.validated != appData.userDefaultSettings.validated else {
        return false
    }
    updateAppData { data in
        data.userDefaultSettingsRevision += 1
    }
    return true
}
```

In `normalized` add:

```swift
normalizedData.userDefaultSettingsRevision =
    max(normalizedData.userDefaultSettingsRevision, 0)
```

For every work, also clamp:

```swift
normalizedData.works[index].reviewedUserDefaultSettingsRevision = max(
    normalizedData.works[index].reviewedUserDefaultSettingsRevision,
    0
)
```

- [ ] **Step 4: Run the session tests**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/CommonSettingsSessionTests test
```

Expected: all three tests pass.

- [ ] **Step 5: Commit Task 2**

```bash
git add Honkumi/Shared/Services/DocumentStore.swift \
  HonkumiTests/CommonSettingsSessionTests.swift
git commit -m "Version completed common settings sessions"
```

---

### Task 3: Initialize new and fallback works at the current revision

**Files:**

- Modify: `Honkumi/Shared/Services/DocumentStore.swift`
- Modify: `Honkumi/Shared/Services/InitialSampleWork.swift`
- Modify: `HonkumiTests/CommonSettingsSessionTests.swift`
- Modify: `HonkumiTests/DocumentStorePersistenceTests.swift`

**Interfaces:**

- Consumes: Task 1's revision fields.
- Produces: new work, empty-library fallback, and first sample with the current reviewed revision.

- [ ] **Step 1: Add failing creation tests**

Add to `CommonSettingsSessionTests`:

```swift
func testNewWorkUsesExistingInitializationRulesAndCurrentRevision() {
    var data = AppData.initial
    data.userDefaultSettingsRevision = 4
    data.userDefaultSettings.useRecommendedTypography = false
    data.userDefaultSettings.useRecommendedMargins = false
    data.userDefaultSettings.editorFontSize = 17
    let store = DocumentStore(appData: data)

    let work = store.createWork(title: "新作")

    XCTAssertEqual(work.reviewedUserDefaultSettingsRevision, 4)
    XCTAssertEqual(work.settings.editorFontSize, 17)
    XCTAssertTrue(work.settings.useRecommendedTypography)
    XCTAssertTrue(work.settings.useRecommendedMargins)
}

func testDeleteLastWorkCreatesReviewedFallback() {
    var data = AppData.initial
    data.userDefaultSettingsRevision = 3
    let store = DocumentStore(appData: data)
    let onlyID = store.document.id

    store.deleteWork(id: onlyID)

    XCTAssertEqual(
        store.document.reviewedUserDefaultSettingsRevision,
        3
    )
}
```

Add this `InitialSampleWork` test to `CommonSettingsSessionTests`:

```swift
func testInitialSampleRecordsCurrentRevision() {
    var data = AppData.emptyLibrary
    data.userDefaultSettingsRevision = 5

    let result = InitialSampleWork.seedIfNeeded(
        in: data,
        hasCreatedInitialSample: false,
        settings: data.userDefaultSettings
    )

    XCTAssertEqual(
        result.data.works.first?.reviewedUserDefaultSettingsRevision,
        5
    )
}
```

- [ ] **Step 2: Run the creation tests and verify RED**

Run `CommonSettingsSessionTests`; expect the created work and sample revisions to remain zero.

- [ ] **Step 3: Pass current revision to every generated work**

Update `DocumentStore.createWork`:

```swift
createdWork = ManuscriptDocument(
    categoryId: categoryExists
        ? targetCategoryId
        : WorkCategory.uncategorizedId,
    title: trimmedTitle.isEmpty ? "無題の作品" : trimmedTitle,
    body: "",
    settings: Self.settingsForNewWork(from: data.userDefaultSettings),
    reviewedUserDefaultSettingsRevision:
        data.userDefaultSettingsRevision
)
```

Update both the last-work deletion fallback and the empty-library fallback in `normalized` to:

```swift
let work = ManuscriptDocument(
    title: "無題の作品",
    settings: Self.settingsForNewWork(
        from: data.userDefaultSettings
    ),
    reviewedUserDefaultSettingsRevision:
        data.userDefaultSettingsRevision
)
```

In `normalized`, replace `data` in that snippet with `normalizedData`.

Update `InitialSampleWork.document`:

```swift
static func document(
    settings: EditorSettings,
    reviewedUserDefaultSettingsRevision: Int = 0,
    createdAt: Date = Date()
) -> ManuscriptDocument
```

Pass `data.userDefaultSettingsRevision` from `seedIfNeeded` into that parameter.

- [ ] **Step 4: Run creation, sample, and persistence regressions**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/CommonSettingsSessionTests \
  -only-testing:HonkumiTests/DocumentStorePersistenceTests test
```

Expected: all selected tests pass.

- [ ] **Step 5: Commit Task 3**

```bash
git add Honkumi/Shared/Services/DocumentStore.swift \
  Honkumi/Shared/Services/InitialSampleWork.swift \
  HonkumiTests/CommonSettingsSessionTests.swift \
  HonkumiTests/DocumentStorePersistenceTests.swift
git commit -m "Initialize works at the current common revision"
```

---

### Task 4: Make common-settings review decisions atomic

**Files:**

- Create: `Honkumi/Shared/Services/UserDefaultSettingsReview.swift`
- Modify: `Honkumi/Shared/Services/DocumentStore.swift`
- Create: `HonkumiTests/UserDefaultSettingsReviewTests.swift`

**Interfaces:**

- Produces: `UserDefaultSettingsReviewRequest(workID:revision:)`.
- Produces: `UserDefaultSettingsReviewDecision.apply` and `.keepCurrent`.
- Produces: `WorkSelectionResult(didSelect:shouldFormat:)`.
- Produces: `DocumentStore.userDefaultSettingsReviewRequest(for:)`.
- Produces: `DocumentStore.resolveUserDefaultSettingsReview(_:decision:)`.

- [ ] **Step 1: Write failing decision tests**

Create `HonkumiTests/UserDefaultSettingsReviewTests.swift`:

```swift
@testable import Honkumi
import XCTest

@MainActor
final class UserDefaultSettingsReviewTests: XCTestCase {
    func testLegacyZeroRevisionDoesNotRequestImmediateReview() {
        let store = makeStore(commonRevision: 0, reviewedRevision: 0)

        XCTAssertNil(
            store.userDefaultSettingsReviewRequest(for: store.document.id)
        )
    }

    func testOlderWorkRequestsReviewAfterCommonRevisionAdvances() {
        let store = makeStore(commonRevision: 2, reviewedRevision: 1)

        XCTAssertEqual(
            store.userDefaultSettingsReviewRequest(for: store.document.id),
            UserDefaultSettingsReviewRequest(
                workID: store.document.id,
                revision: 2
            )
        )
    }

    func testApplyCopiesEverySettingsGroupAndRequestsFormatting() throws {
        let store = makeStore(commonRevision: 3, reviewedRevision: 1)
        var defaults = store.userDefaultSettings
        defaults.editorFontSize = 18
        defaults.pageSize = .b6
        defaults.marginInner = 24
        defaults.formatSettings.enableAutoFormat = true
        defaults.formatSettings.enableNormalizePunctuation = true
        defaults.colophon.authorName = "共通作者"
        store.updateUserDefaultSettings(defaults)
        let request = try XCTUnwrap(
            store.userDefaultSettingsReviewRequest(for: store.document.id)
        )

        let result = store.resolveUserDefaultSettingsReview(
            request,
            decision: .apply
        )

        XCTAssertTrue(result.didSelect)
        XCTAssertTrue(result.shouldFormat)
        XCTAssertEqual(store.document.settings, defaults.validated)
        XCTAssertEqual(
            store.document.reviewedUserDefaultSettingsRevision,
            3
        )
    }

    func testKeepCurrentPreservesSettingsAndBodyButReviewsRevision() throws {
        let store = makeStore(commonRevision: 3, reviewedRevision: 1)
        let original = store.document
        let request = try XCTUnwrap(
            store.userDefaultSettingsReviewRequest(for: original.id)
        )

        let result = store.resolveUserDefaultSettingsReview(
            request,
            decision: .keepCurrent
        )

        XCTAssertTrue(result.didSelect)
        XCTAssertFalse(result.shouldFormat)
        XCTAssertEqual(store.document.settings, original.settings)
        XCTAssertEqual(store.document.body, original.body)
        XCTAssertEqual(store.document.updatedAt, original.updatedAt)
        XCTAssertEqual(
            store.document.reviewedUserDefaultSettingsRevision,
            3
        )
    }

    func testStaleRequestChangesNothing() {
        let store = makeStore(commonRevision: 3, reviewedRevision: 1)
        let request = UserDefaultSettingsReviewRequest(
            workID: store.document.id,
            revision: 2
        )
        let before = store.appData

        let result = store.resolveUserDefaultSettingsReview(
            request,
            decision: .apply
        )

        XCTAssertFalse(result.didSelect)
        XCTAssertFalse(result.shouldFormat)
        XCTAssertEqual(store.appData, before)
    }

    private func makeStore(
        commonRevision: Int,
        reviewedRevision: Int
    ) -> DocumentStore {
        var work = ManuscriptDocument(
            title: "作品",
            body: "A,B.",
            reviewedUserDefaultSettingsRevision: reviewedRevision
        )
        work.settings.editorFontSize = 11
        return DocumentStore(
            appData: AppData(
                version: AppData.currentVersion,
                categories: [.uncategorized],
                works: [work],
                userDefaultSettings: .default,
                activeWorkId: work.id,
                subscriptionStatus: .paid,
                userDefaultSettingsRevision: commonRevision
            )
        )
    }
}
```

- [ ] **Step 2: Run the review tests and verify RED**

Run the new test class; expect undefined review types and store methods.

- [ ] **Step 3: Add review request and result value types**

Create `UserDefaultSettingsReview.swift`:

```swift
import Foundation

nonisolated struct UserDefaultSettingsReviewRequest:
    Identifiable,
    Equatable {
    let workID: UUID
    let revision: Int
    var id: UUID { workID }
}

nonisolated enum UserDefaultSettingsReviewDecision: Equatable {
    case apply
    case keepCurrent
}

nonisolated struct WorkSelectionResult: Equatable {
    let didSelect: Bool
    let shouldFormat: Bool

    static let unchanged = WorkSelectionResult(
        didSelect: false,
        shouldFormat: false
    )
}
```

- [ ] **Step 4: Add request lookup and atomic resolution**

Add to `DocumentStore`:

```swift
func userDefaultSettingsReviewRequest(
    for workID: UUID
) -> UserDefaultSettingsReviewRequest? {
    guard let work = appData.works.first(where: { $0.id == workID }),
          work.reviewedUserDefaultSettingsRevision <
            appData.userDefaultSettingsRevision else {
        return nil
    }
    return UserDefaultSettingsReviewRequest(
        workID: workID,
        revision: appData.userDefaultSettingsRevision
    )
}
```

Implement resolution in one `updateAppData` mutation:

```swift
@discardableResult
func resolveUserDefaultSettingsReview(
    _ request: UserDefaultSettingsReviewRequest,
    decision: UserDefaultSettingsReviewDecision
) -> WorkSelectionResult {
    guard request.revision == appData.userDefaultSettingsRevision,
          appData.works.contains(where: { $0.id == request.workID }) else {
        return .unchanged
    }

    var result = WorkSelectionResult.unchanged
    updateAppData { data in
        guard let index = data.works.firstIndex(
            where: { $0.id == request.workID }
        ) else { return }

        switch decision {
        case .apply:
            data.works[index].settings =
                data.userDefaultSettings.validated
            data.works[index].updatedAt = Date()
            result = WorkSelectionResult(
                didSelect: true,
                shouldFormat: data.works[index]
                    .settings.formatSettings.enableAutoFormat
            )
        case .keepCurrent:
            result = WorkSelectionResult(
                didSelect: true,
                shouldFormat: false
            )
        }

        data.works[index].reviewedUserDefaultSettingsRevision =
            data.userDefaultSettingsRevision
        data.activeWorkId = request.workID
    }
    return result
}
```

- [ ] **Step 5: Run review tests**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/UserDefaultSettingsReviewTests test
```

Expected: all decision tests pass.

- [ ] **Step 6: Commit Task 4**

```bash
git add Honkumi/Shared/Services/UserDefaultSettingsReview.swift \
  Honkumi/Shared/Services/DocumentStore.swift \
  HonkumiTests/UserDefaultSettingsReviewTests.swift
git commit -m "Resolve common settings review atomically"
```

---

### Task 5: Stop production output from bypassing the review decision

**Files:**

- Modify: `Honkumi/Features/Preview/PreviewViewModel.swift`
- Modify: `Honkumi/ContentView.swift`
- Modify: `HonkumiTests/PreviewViewModelSuspensionTests.swift`

**Interfaces:**

- Consumes: each work's persisted `EditorSettings.colophon`.
- Removes: automatic common publisher-info overlay from production preview and PDF export.
- Preserves: explicit publisher-info composition in `VerticalTypesettingSamplePDFExporter`.

- [ ] **Step 1: Write a failing preview-isolation test**

Add to `PreviewViewModelSuspensionTests`:

```swift
func testCommonPublisherChangeDoesNotOverwriteOrRegenerateUnappliedWork() async throws {
    var work = ManuscriptDocument(title: "Preview", body: "本文")
    work.settings.colophon.authorName = "作品の作者"
    var defaults = EditorSettings.default
    defaults.colophon.authorName = "変更前の共通作者"
    let store = DocumentStore(
        appData: AppData(
            version: AppData.currentVersion,
            categories: [.uncategorized],
            works: [work],
            userDefaultSettings: defaults,
            activeWorkId: work.id,
            subscriptionStatus: .free,
            userDefaultSettingsRevision: 1
        )
    )
    let exporter = FakePreviewPDFExporter()
    let viewModel = PreviewViewModel(
        documentStore: store,
        pdfExporter: exporter
    )
    viewModel.setPreviewActive(true, kind: .normal)
    try await waitUntil {
        exporter.documents.count == 1 &&
            !viewModel.isGeneratingPDF
    }
    var changedDefaults = defaults
    changedDefaults.colophon.authorName = "新しい共通作者"

    store.updateUserDefaultSettings(changedDefaults)
    try await Task.sleep(for: .milliseconds(450))

    XCTAssertEqual(
        viewModel.document.settings.colophon.authorName,
        "作品の作者"
    )
    XCTAssertEqual(exporter.documents.count, 1)
}
```

- [ ] **Step 2: Run the preview test and verify RED**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/PreviewViewModelSuspensionTests test
```

Expected: the new test fails because `PreviewViewModel` overlays the latest common publisher information.

- [ ] **Step 3: Use the stored work directly in PreviewViewModel**

Change initialization to:

```swift
self.document = documentStore.document
```

In the document publisher, replace:

```swift
let previewDocument = self.previewDocument(from: document)
```

with:

```swift
let previewDocument = document
```

Add `.removeDuplicates()` before that publisher's `.sink` so an `AppData` update that reassigns an equal active document does not regenerate preview:

```swift
documentStore.$document
    .removeDuplicates()
    .sink { [weak self] document in
        guard let self else { return }
        self.document = document
        if self.isPreviewActive && !self.isGenerationSuspended {
            self.preparePreview(
                for: document,
                kind: self.activePreviewKind,
                debounceMilliseconds: 350
            )
        } else {
            self.cancelInactiveGeneration()
        }
    }
    .store(in: &cancellables)
```

Change the app-data subscription to observe entitlement only:

```swift
documentStore.$appData
    .map(\.subscriptionStatus)
    .removeDuplicates()
    .dropFirst()
    .sink { [weak self] _ in
        guard let self else { return }
        let previewDocument = self.documentStore.document
        self.document = previewDocument
        guard self.isPreviewActive,
              !self.isGenerationSuspended else { return }
        self.preparePreview(
            for: previewDocument,
            kind: self.activePreviewKind,
            debounceMilliseconds: 0
        )
    }
    .store(in: &cancellables)
```

Delete `previewDocument(from:)`. A common settings edit alone no longer invalidates or regenerates the active work preview.

- [ ] **Step 4: Use the stored work directly for preflight and PDF output**

Change `WorkspaceView.outputDocument` to:

```swift
private func outputDocument(
    from document: ManuscriptDocument? = nil
) -> ManuscriptDocument {
    document ?? documentStore.document
}
```

Do not change `ManuscriptDocument.applyingPublisherInfo(from:)` or `VerticalTypesettingSamplePDFExporter`; the sample exporter deliberately supplies separate publisher settings and is outside the production work-review flow.

- [ ] **Step 5: Run preview, review, and Debug build checks**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/PreviewViewModelSuspensionTests \
  -only-testing:HonkumiTests/UserDefaultSettingsReviewTests test

xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build
```

Expected: tests pass, Debug builds, and production `ContentView`/`PreviewViewModel` no longer call `applyingPublisherInfo`.

- [ ] **Step 6: Commit Task 6**

```bash
git add Honkumi/Features/Preview/PreviewViewModel.swift \
  Honkumi/ContentView.swift \
  HonkumiTests/PreviewViewModelSuspensionTests.swift
git commit -m "Keep publisher settings isolated per work"
```

---

### Task 6: Present the apply/keep/cancel alert before work navigation

**Files:**

- Modify: `Honkumi/Features/Library/WorkListView.swift`
- Modify: `Honkumi/ContentView.swift`
- Modify: `HonkumiTests/UserDefaultSettingsReviewTests.swift`

**Interfaces:**

- Changes: `WorkListView.onSelectWork` from `() -> Void` to `(Bool) -> Void`, where the argument is `shouldFormat`.
- Consumes: Task 4's request/decision/result types.
- Consumes: `ManuscriptFormattingCoordinator.requestFormatting()` from the formatting plan.

- [ ] **Step 1: Add a direct-selection regression test**

Add to `UserDefaultSettingsReviewTests`:

```swift
func testAlreadyReviewedWorkCanBeSelectedWithoutARequest() {
    let first = ManuscriptDocument(
        title: "First",
        body: "本文",
        reviewedUserDefaultSettingsRevision: 2
    )
    let second = ManuscriptDocument(
        title: "Second",
        body: "本文",
        reviewedUserDefaultSettingsRevision: 2
    )
    let store = DocumentStore(
        appData: AppData(
            version: AppData.currentVersion,
            categories: [.uncategorized],
            works: [first, second],
            userDefaultSettings: .default,
            activeWorkId: first.id,
            subscriptionStatus: .free,
            userDefaultSettingsRevision: 2
        )
    )

    XCTAssertNil(store.userDefaultSettingsReviewRequest(for: second.id))
    store.selectWork(id: second.id)
    XCTAssertEqual(store.document.id, second.id)
}
```

Run `UserDefaultSettingsReviewTests` and expect PASS, preserving the direct path for reviewed works.

- [ ] **Step 2: Hold a pending request in WorkListView**

Add:

```swift
@State private var pendingSettingsReview:
    UserDefaultSettingsReviewRequest?
```

Change the callback:

```swift
let onSelectWork: (_ shouldFormat: Bool) -> Void
```

Replace the work button action with:

```swift
if let request = documentStore.userDefaultSettingsReviewRequest(
    for: work.id
) {
    pendingSettingsReview = request
} else {
    documentStore.selectWork(id: work.id)
    onSelectWork(false)
}
```

- [ ] **Step 3: Add the centered native alert**

Attach to the list:

```swift
.alert(
    "共通設定が変更されています",
    isPresented: Binding(
        get: { pendingSettingsReview != nil },
        set: { isPresented in
            if !isPresented {
                pendingSettingsReview = nil
            }
        }
    )
) {
    Button("適用して開く") {
        resolvePendingSettingsReview(.apply)
    }
    Button("適用せず開く") {
        resolvePendingSettingsReview(.keepCurrent)
    }
    Button("キャンセル", role: .cancel) {
        pendingSettingsReview = nil
    }
} message: {
    Text("現在の共通設定をこの作品に適用しますか？")
}
```

Add:

```swift
private func resolvePendingSettingsReview(
    _ decision: UserDefaultSettingsReviewDecision
) {
    guard let request = pendingSettingsReview else { return }
    pendingSettingsReview = nil
    let result = documentStore.resolveUserDefaultSettingsReview(
        request,
        decision: decision
    )
    guard result.didSelect else { return }
    onSelectWork(result.shouldFormat)
}
```

- [ ] **Step 4: Route applied auto-format through the coordinator**

In `ContentView`, change the `WorkListView` callback:

```swift
onSelectWork: { shouldFormat in
    showsWorkspace = true
    if shouldFormat {
        manuscriptFormattingCoordinator.requestFormatting()
    }
}
```

Do not call the coordinator for direct selection, `適用せず開く`, or `キャンセル`.

- [ ] **Step 5: Build and run store regressions**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/UserDefaultSettingsReviewTests \
  -only-testing:HonkumiTests/ManuscriptFormattingCoordinatorTests test

xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build
```

Expected: selected tests pass and the changed callback compiles.

- [ ] **Step 6: Commit Task 5**

```bash
git add Honkumi/Features/Library/WorkListView.swift \
  Honkumi/ContentView.swift \
  HonkumiTests/UserDefaultSettingsReviewTests.swift
git commit -m "Review common settings before opening works"
```

---

### Task 7: Finish default-settings and publisher-information sessions on close

**Files:**

- Modify: `Honkumi/ContentView.swift`
- Modify: `HonkumiTests/CommonSettingsSessionTests.swift`

**Interfaces:**

- Consumes: Task 2's `finishUserDefaultSettingsSession(startingFrom:)`.
- Produces: independent open-time snapshots for the default settings sheet and default publisher-information sheet.

- [ ] **Step 1: Add publisher-session equivalence test**

Add to `CommonSettingsSessionTests`:

```swift
func testPublisherInformationChangeUsesTheSameFullSettingsSessionBoundary() {
    let store = makeStore()
    let initial = store.userDefaultSettings
    var changed = initial
    changed.colophon.authorName = "作者"
    changed.colophon.circleName = "サークル"
    store.updateUserDefaultSettings(changed)

    XCTAssertTrue(
        store.finishUserDefaultSettingsSession(startingFrom: initial)
    )
    XCTAssertEqual(store.userDefaultSettingsRevision, 1)
}
```

Run the test and expect PASS, proving that the store compares the complete settings value rather than the visible tab.

- [ ] **Step 2: Capture the default settings sheet session**

Add to `ContentView`:

```swift
@State private var defaultSettingsSessionStart: EditorSettings?
@State private var defaultColophonSessionStart: EditorSettings?
```

Extend the existing `presentedSettingsScope?.id` change handler:

```swift
if newScopeID == SettingsViewModel.Scope.userDefault.id {
    defaultSettingsSessionStart = documentStore.userDefaultSettings
}
if oldScopeID == SettingsViewModel.Scope.userDefault.id,
   newScopeID == nil,
   let initial = defaultSettingsSessionStart {
    defaultSettingsSessionStart = nil
    documentStore.finishUserDefaultSettingsSession(
        startingFrom: initial
    )
}
```

Keep the active-work formatting snapshot logic from the formatting plan in the same handler; the two scopes are mutually exclusive.

- [ ] **Step 3: Capture the default publisher-information session**

Add:

```swift
.onChange(of: presentedColophonScope?.id) { oldScopeID, newScopeID in
    if newScopeID == SettingsViewModel.Scope.userDefault.id {
        defaultColophonSessionStart = documentStore.userDefaultSettings
    }
    if oldScopeID == SettingsViewModel.Scope.userDefault.id,
       newScopeID == nil,
       let initial = defaultColophonSessionStart {
        defaultColophonSessionStart = nil
        documentStore.finishUserDefaultSettingsSession(
            startingFrom: initial
        )
    }
}
```

Active-work colophon settings must not change the common revision.

- [ ] **Step 4: Run session, review, and Debug build checks**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/CommonSettingsSessionTests \
  -only-testing:HonkumiTests/CommonSettingsRevisionCodingTests \
  -only-testing:HonkumiTests/UserDefaultSettingsReviewTests test

xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build
```

Expected: all selected tests pass and Debug builds.

- [ ] **Step 5: Commit Task 7**

```bash
git add Honkumi/ContentView.swift \
  HonkumiTests/CommonSettingsSessionTests.swift
git commit -m "Version common settings when sheets close"
```

---

### Task 8: Verify migration, decisions, and all build configurations

**Files:**

- No source changes expected.
- Modify only files from Tasks 1–7 if a reproducible regression is found.

**Interfaces:**

- Verifies the complete persistence and user-decision flow.

- [ ] **Step 1: Run the complete XCTest suite**

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO test
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 2: Build Debug, Staging, and Release**

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build

xcodebuild -project Honkumi.xcodeproj -scheme 'Honkumi Staging' \
  -configuration Staging \
  -destination 'generic/platform=iOS Simulator' build

xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -configuration Release \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: all builds succeed.

- [ ] **Step 3: Manually verify one revision per sheet session**

1. Open default settings, change editor, print, and format values several times, then close.
2. Reopen the same sheet without changing anything and close.
3. Open publisher information, change author and circle values, then close.
4. Confirm through the next work-open prompts that the first and third sessions each created one new review boundary, while the unchanged second session did not.

- [ ] **Step 4: Manually verify all three work-open decisions**

1. For an older work, choose `キャンセル`; verify the current selection and body remain unchanged.
2. Open it again and choose `適用せず開く`; verify it opens with its original editor, print, format, colophon settings, and body, and does not ask again for that revision.
3. Change common settings once more, open the work, and choose `適用して開く`; verify all setting groups match the common settings.
4. With applied auto-format on, verify centered `フォーマット中` appears and the latest body is formatted.
5. Create a new work and verify it opens without a review alert and uses the existing recommendation-on initialization rules.

- [ ] **Step 5: Record final evidence**

Include focused tests, complete-suite output, the three configuration builds, legacy migration result, and all manual decision outcomes in the implementation handoff.
