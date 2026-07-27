# Device Follow-up Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make circle-logo import, Pro formatting, large-document settings, emoji preflight, and long chapter-title diagnostics behave correctly on a physical device.

**Architecture:** Keep `DocumentStore`, `SettingsViewModel`, and the PDF render pipeline as the sources of truth, but move expensive derivation and encoding behind cancelable snapshot operations. Add small pure helpers for image validation, print-setting snapshots, emoji issue construction, and chapter issue aggregation so each behavior is directly testable.

**Tech Stack:** Swift 6, SwiftUI, UIKit, UniformTypeIdentifiers, Combine, XCTest, Xcode 26

## Global Constraints

- Settings values must update on the MainActor immediately; formatting, recommendation calculation, pagination estimates, and JSON encoding must not block the UI.
- Only the newest asynchronous result may update the body, settings display, or persisted data.
- Preview PDF regeneration remains suspended while the settings sheet is open and runs once after dismissal.
- Unsupported emoji become `□`; heart emoji become `♡`; the preflight displays one warning containing both counts.
- A chapter occurrence produces at most one long-title issue, and an error replaces a warning for the same occurrence.
- Imported logo bytes are stored in `circleImageData`, so the original file is not required after import.
- Existing untracked documents and scripts outside this plan remain untouched.
- Full sample-PDF batch generation remains opt-in and is not part of normal verification.

---

### Task 1: Import and validate a circle logo from Files

**Files:**
- Create: `Honkumi/Shared/Services/CircleLogoImageImporter.swift`
- Modify: `Honkumi/Features/Settings/ColophonSettingsView.swift`
- Create: `HonkumiTests/CircleLogoImageImporterTests.swift`

**Interfaces:**
- Consumes: `Data`, security-scoped file `URL`, and the existing `ColophonSettings.circleImageData`.
- Produces: `CircleLogoImageImporter.validatedImageData(_:) throws -> Data` and `CircleLogoImageImporter.loadImageData(from:) throws -> Data`.

- [ ] **Step 1: Write failing importer tests**

```swift
import UIKit
@testable import Honkumi
import XCTest

final class CircleLogoImageImporterTests: XCTestCase {
    func testValidatedImageDataAcceptsPNG() throws {
        let data = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
            .image { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            }
            .pngData()!

        XCTAssertEqual(try CircleLogoImageImporter.validatedImageData(data), data)
    }

    func testValidatedImageDataRejectsNonImageBytes() {
        XCTAssertThrowsError(
            try CircleLogoImageImporter.validatedImageData(Data("not-image".utf8))
        ) { error in
            XCTAssertEqual(error as? CircleLogoImageImportError, .invalidImage)
        }
    }

    func testLoadImageDataCopiesBytesFromFileURL() throws {
        let data = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
            .image { _ in UIColor.blue.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 4, height: 4)) }
            .pngData()!
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(try CircleLogoImageImporter.loadImageData(from: url), data)
    }
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -parallel-testing-enabled NO -only-testing:HonkumiTests/CircleLogoImageImporterTests test
```

Expected: build failure because `CircleLogoImageImporter` and `CircleLogoImageImportError` do not exist.

- [ ] **Step 3: Implement image validation and file loading**

```swift
import Foundation
import UIKit

nonisolated enum CircleLogoImageImportError: LocalizedError, Equatable {
    case invalidImage

    var errorDescription: String? {
        "選択したファイルを画像として読み込めませんでした。"
    }
}

nonisolated enum CircleLogoImageImporter {
    static func validatedImageData(_ data: Data) throws -> Data {
        guard !data.isEmpty, UIImage(data: data) != nil else {
            throw CircleLogoImageImportError.invalidImage
        }
        return data
    }

    static func loadImageData(from url: URL) throws -> Data {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try validatedImageData(Data(contentsOf: url, options: .mappedIfSafe))
    }
}
```

- [ ] **Step 4: Add the Files UI and share the validator with Photos**

In `ColophonSettingsView`:

```swift
import UniformTypeIdentifiers

@State private var isCircleLogoFileImporterPresented = false
@State private var circleLogoImportErrorMessage: String?
```

Present a `fileImporter` with `allowedContentTypes: [.image]`, load the selected URL in `Task.detached(priority: .userInitiated)`, and only call `viewModel.updateColophon` after validation succeeds. Replace the single photo label with two buttons, `写真から選択` and `ファイルから選択`. Pass `PhotosPickerItem` bytes through `validatedImageData(_:)` before changing the stored logo. On failure, preserve the existing data and show an alert titled `サークルロゴを読み込めません`.

Use these modifiers and handlers:

```swift
.fileImporter(
    isPresented: $isCircleLogoFileImporterPresented,
    allowedContentTypes: [.image],
    allowsMultipleSelection: false
) { result in
    guard case let .success(urls) = result, let url = urls.first else {
        if case let .failure(error) = result {
            circleLogoImportErrorMessage = error.localizedDescription
        }
        return
    }
    Task {
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                try CircleLogoImageImporter.loadImageData(from: url)
            }.value
            viewModel.updateColophon { $0.circleImageData = data }
        } catch is CancellationError {
            return
        } catch {
            circleLogoImportErrorMessage = error.localizedDescription
        }
    }
}
.alert(
    "サークルロゴを読み込めません",
    isPresented: Binding(
        get: { circleLogoImportErrorMessage != nil },
        set: { if !$0 { circleLogoImportErrorMessage = nil } }
    )
) {
    Button("OK", role: .cancel) {}
} message: {
    Text(circleLogoImportErrorMessage ?? "")
}
```

The paid import row contains:

```swift
PhotosPicker(selection: $selectedCircleImageItem, matching: .images) {
    Label("写真から選択", systemImage: "photo.badge.plus")
}

Button {
    isCircleLogoFileImporterPresented = true
} label: {
    Label("ファイルから選択", systemImage: "folder.badge.plus")
}
```

- [ ] **Step 5: Run the focused tests and build the screen**

Run the Task 1 test command, then:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi -configuration Debug -destination 'generic/platform=iOS Simulator' build
```

Expected: all importer tests pass and the Debug build exits with status 0.

- [ ] **Step 6: Commit Task 1**

```bash
git add Honkumi/Shared/Services/CircleLogoImageImporter.swift Honkumi/Features/Settings/ColophonSettingsView.swift HonkumiTests/CircleLogoImageImporterTests.swift
git commit -m "Add Files import for circle logos"
```

---

### Task 2: Apply Pro formatting immediately and reject stale results

**Files:**
- Modify: `Honkumi/Features/Settings/SettingsViewModel.swift`
- Modify: `Honkumi/Features/Settings/SettingsView.swift`
- Create: `HonkumiTests/SettingsFormatApplicationTests.swift`

**Interfaces:**
- Consumes: `ManuscriptFormatter.formatManuscriptText(_:settings:options:)`, current body, current `FormatSettings`, and `SubscriptionStatus`.
- Produces: `SettingsViewModel.FormatOperation`, `SettingsViewModel.isApplyingFormat`, and generation-checked background application.

- [ ] **Step 1: Write the failing immediate-application test**

```swift
@MainActor
final class SettingsFormatApplicationTests: XCTestCase {
    func testEnablingPaidRuleImmediatelyFormatsExistingBody() async throws {
        var settings = EditorSettings.default
        settings.formatSettings.enableAutoFormat = true
        settings.formatSettings.enableNormalizePunctuation = false
        let document = ManuscriptDocument(title: "Format", body: "A,B.", settings: settings)
        let store = DocumentStore(appData: AppData(
            version: AppData.currentVersion,
            categories: [.uncategorized],
            works: [document],
            userDefaultSettings: .default,
            activeWorkId: document.id,
            subscriptionStatus: .paid
        ))
        let viewModel = SettingsViewModel(documentStore: store)

        viewModel.updateFormatRule(\.enableNormalizePunctuation, isEnabled: true)

        try await waitUntil { store.document.body == "A、B。" }
        XCTAssertFalse(viewModel.isApplyingFormat)
    }
}
```

Add a second test with an injected `FormatOperation` that returns an old request after a newer request:

```swift
func testLateOldFormatResultCannotOverwriteNewResult() async throws {
    let harness = FormatOperationHarness()
    let store = makePaidStore(body: "original", autoFormatEnabled: true)
    let viewModel = SettingsViewModel(
        documentStore: store,
        formatOperation: { body, settings, options in
            await harness.format(body: body, settings: settings, options: options)
        }
    )

    viewModel.updateFormatRule(\.enableNormalizePunctuation, isEnabled: true)
    try await harness.waitForRequestCount(1)
    viewModel.updateFormatRule(\.enableNormalizeBrackets, isEnabled: true)
    try await harness.waitForRequestCount(2)

    await harness.complete(request: 1, result: "new-result")
    try await waitUntil { store.document.body == "new-result" }
    await harness.complete(request: 0, result: "old-result")
    await Task.yield()

    XCTAssertEqual(store.document.body, "new-result")
}
```

The test harness records continuations even when the waiting caller is canceled:

```swift
private actor FormatOperationHarness {
    private var requests: [CheckedContinuation<String, Never>] = []

    func format(
        body: String,
        settings: FormatSettings,
        options: FormatOptions
    ) async -> String {
        await withCheckedContinuation { continuation in
            requests.append(continuation)
        }
    }

    func waitForRequestCount(_ count: Int) async throws {
        while requests.count < count {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func complete(request index: Int, result: String) {
        requests[index].resume(returning: result)
    }
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -parallel-testing-enabled NO -only-testing:HonkumiTests/SettingsFormatApplicationTests test
```

Expected: build failure because `FormatOperation`, the injectable initializer argument, and `isApplyingFormat` do not exist.

- [ ] **Step 3: Add a cancelable formatting operation**

Add to `SettingsViewModel`:

```swift
typealias FormatOperation = @Sendable (
    String,
    FormatSettings,
    FormatOptions
) async -> String

@Published private(set) var isApplyingFormat = false
private let formatOperation: FormatOperation
private var formatTask: Task<Void, Never>?
private var formatGeneration = 0
```

Default the operation to:

```swift
{ body, settings, options in
    await Task.detached(priority: .userInitiated) {
        ManuscriptFormatter.formatManuscriptText(
            body,
            settings: settings,
            options: options
        )
    }.value
}
```

After storing a changed `FormatSettings`, schedule formatting whenever active-work scope has auto-format enabled. Capture document ID, original body, validated settings, premium option, and generation. Apply the result only when all captured inputs and the generation still match. Cancel the previous task but retain the generation guard because injected or system work can complete after cancellation.

- [ ] **Step 4: Show nonblocking formatting progress**

In the format form, add:

```swift
if viewModel.isApplyingFormat {
    HStack {
        ProgressView()
        Text("本文にフォーマットを適用中")
    }
    .font(.footnote)
    .foregroundStyle(.secondary)
}
```

Do not disable the formatting toggles while work is running; a newer change must supersede the current request.

- [ ] **Step 5: Verify GREEN and existing formatter behavior**

Run the Task 2 focused command and:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -parallel-testing-enabled NO -only-testing:HonkumiTests/SettingsFormatApplicationTests -only-testing:HonkumiTests/PrintTextNormalizerTests test
```

Expected: immediate application and stale-result tests pass with no failures.

- [ ] **Step 6: Commit Task 2**

```bash
git add Honkumi/Features/Settings/SettingsViewModel.swift Honkumi/Features/Settings/SettingsView.swift HonkumiTests/SettingsFormatApplicationTests.swift
git commit -m "Apply Pro formatting when settings change"
```

---

### Task 3: Calculate print-setting display snapshots off the MainActor

**Files:**
- Create: `Honkumi/Shared/Services/PrintSettingsDisplaySnapshot.swift`
- Modify: `Honkumi/Features/Settings/SettingsViewModel.swift`
- Modify: `Honkumi/Features/Settings/SettingsView.swift`
- Create: `HonkumiTests/PrintSettingsDisplaySnapshotTests.swift`
- Create: `HonkumiTests/SettingsPrintSnapshotTests.swift`

**Interfaces:**
- Consumes: body and validated `EditorSettings`.
- Produces: `PrintSettingsDisplaySnapshot`, `PrintSettingsDisplaySnapshot.calculate(body:settings:)`, `SettingsViewModel.isCalculatingPrintSettings`, and latest-only publication.

- [ ] **Step 1: Write failing snapshot calculation tests**

```swift
@testable import Honkumi
import XCTest

final class PrintSettingsDisplaySnapshotTests: XCTestCase {
    func testSnapshotUsesOneEffectiveSettingsCalculationForCountAndWideGutter() {
        var settings = EditorSettings.default
        settings.useRecommendedTypography = true
        settings.useRecommendedMargins = true
        let body = String(repeating: "本文です。\n", count: 4_000)

        let snapshot = PrintSettingsDisplaySnapshot.calculate(
            body: body,
            settings: settings
        )

        XCTAssertEqual(
            snapshot.estimatedPageCount,
            RecommendedPrintSettings.estimatedPageCount(
                body: body,
                settings: snapshot.settings
            )
        )
        XCTAssertEqual(snapshot.showsWideGutterNote, snapshot.estimatedPageCount >= 97)
    }
}
```

In `SettingsPrintSnapshotTests`, inject a suspended first calculation and a completed second calculation:

```swift
@MainActor
func testSettingsAreImmediateAndLateSnapshotIsDiscarded() async throws {
    let harness = PrintSnapshotHarness()
    let store = makeStore()
    let viewModel = SettingsViewModel(
        documentStore: store,
        printSnapshotOperation: { body, settings in
            await harness.calculate(body: body, settings: settings)
        }
    )
    try await harness.waitForRequestCount(1)

    viewModel.updatePageSize(.b6)
    XCTAssertEqual(viewModel.settings.pageSize, .b6)
    XCTAssertEqual(viewModel.printSettingsForDisplay.pageSize, .b6)
    try await harness.waitForRequestCount(2)

    var latestSettings = viewModel.settings
    latestSettings.pageSize = .b6
    await harness.complete(
        request: 1,
        result: PrintSettingsDisplaySnapshot(
            settings: latestSettings,
            estimatedPageCount: 99,
            showsWideGutterNote: true
        )
    )
    try await waitUntil { viewModel.estimatedPrintPageCount == 99 }

    await harness.complete(
        request: 0,
        result: PrintSettingsDisplaySnapshot(
            settings: .default,
            estimatedPageCount: 1,
            showsWideGutterNote: false
        )
    )
    await Task.yield()
    XCTAssertEqual(viewModel.estimatedPrintPageCount, 99)
}
```

Use this actor to store
`CheckedContinuation<PrintSettingsDisplaySnapshot, Never>` values:

```swift
private actor PrintSnapshotHarness {
    private var requests: [
        CheckedContinuation<PrintSettingsDisplaySnapshot, Never>
    ] = []

    func calculate(
        body: String,
        settings: EditorSettings
    ) async -> PrintSettingsDisplaySnapshot {
        await withCheckedContinuation { continuation in
            requests.append(continuation)
        }
    }

    func waitForRequestCount(_ count: Int) async throws {
        while requests.count < count {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func complete(
        request index: Int,
        result: PrintSettingsDisplaySnapshot
    ) {
        requests[index].resume(returning: result)
    }
}
```

- [ ] **Step 2: Run the new tests and verify RED**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -parallel-testing-enabled NO -only-testing:HonkumiTests/PrintSettingsDisplaySnapshotTests -only-testing:HonkumiTests/SettingsPrintSnapshotTests test
```

Expected: build failure because `PrintSettingsDisplaySnapshot` and the injected snapshot operation do not exist.

- [ ] **Step 3: Add the pure snapshot type**

```swift
import Foundation

nonisolated struct PrintSettingsDisplaySnapshot: Equatable {
    let settings: EditorSettings
    let estimatedPageCount: Int
    let showsWideGutterNote: Bool

    static func calculate(body: String, settings: EditorSettings) -> Self {
        let effective = RecommendedPrintSettings.effectiveSettings(
            body: body,
            settings: settings
        )
        let count = RecommendedPrintSettings.estimatedPageCount(
            body: body,
            settings: effective
        )
        return Self(
            settings: effective,
            estimatedPageCount: count,
            showsWideGutterNote: effective.useRecommendedMargins && count >= 97
        )
    }
}
```

- [ ] **Step 4: Cache and asynchronously refresh the snapshot**

Add an injectable operation:

```swift
typealias PrintSnapshotOperation = @Sendable (
    String,
    EditorSettings
) async -> PrintSettingsDisplaySnapshot
```

The production operation wraps `PrintSettingsDisplaySnapshot.calculate` in `Task.detached(priority: .utility)`. `SettingsViewModel` keeps the last completed snapshot, a source document/settings token, a generation, and a cancelable task. Replace synchronous calls in these computed properties:

```swift
var printSettingsForDisplay: EditorSettings
var estimatedPrintPageCount: Int
var showsWideGutterRecommendationNote: Bool
```

If the last snapshot does not match current input, return current validated settings immediately for editable controls, keep the last page count for display, set `isCalculatingPrintSettings`, and publish only the latest completed snapshot. Trigger refresh from document and user-default subscriptions rather than from SwiftUI `body`.

- [ ] **Step 5: Add a compact calculation indicator**

Beside `想定ページ数`, show a small `ProgressView` while `isCalculatingPrintSettings` is true. Keep all steppers and toggles enabled.

- [ ] **Step 6: Verify focused and recommendation regression tests**

Run the Task 3 test command and:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -parallel-testing-enabled NO -only-testing:HonkumiTests/RecommendedPrintSettingsTests -only-testing:HonkumiTests/SettingsRecommendationTransitionTests -only-testing:HonkumiTests/ManuscriptRenderPipelinePerformanceTests test
```

Expected: all focused and recommendation tests pass.

- [ ] **Step 7: Commit Task 3**

```bash
git add Honkumi/Shared/Services/PrintSettingsDisplaySnapshot.swift Honkumi/Features/Settings/SettingsViewModel.swift Honkumi/Features/Settings/SettingsView.swift HonkumiTests/PrintSettingsDisplaySnapshotTests.swift HonkumiTests/SettingsPrintSnapshotTests.swift
git commit -m "Move print setting calculations off the UI thread"
```

---

### Task 4: Encode large saved documents in the background

**Files:**
- Create: `Honkumi/Shared/Services/AppDataPersistenceEncoder.swift`
- Modify: `Honkumi/Shared/Services/DocumentStore.swift`
- Create: `HonkumiTests/DocumentStorePersistenceTests.swift`

**Interfaces:**
- Consumes: immutable `AppData` snapshot and monotonically increasing generation.
- Produces: `AppDataPersistenceEncoder.EncodeOperation` and latest-generation-only UserDefaults writes.

- [ ] **Step 1: Write a failing stale-save test**

Create a controlled async encoder in the test. Start save generation 1, mutate settings to start generation 2, let generation 2 finish first, then finish generation 1. Decode `honkumi.appData` and assert that the generation-2 settings remain. Also assert immediately after `updateSettings` that `store.document.settings` has the new value even while encoding is suspended.

```swift
@MainActor
func testLateOldEncodingCannotOverwriteNewSettings() async throws {
    let harness = PersistenceEncoderHarness()
    let store = makeStore(encodeOperation: harness.operation)

    var first = store.document.settings
    first.fontSize = 11
    store.updateSettings(first)
    await harness.waitForRequestCount(1)

    var second = first
    second.fontSize = 12
    store.updateSettings(second)
    XCTAssertEqual(store.document.settings.fontSize, 12)

    await harness.complete(request: 1)
    try await waitUntil { persistedSettings().fontSize == 12 }
    await harness.complete(request: 0)
    await Task.yield()
    try await waitUntil { persistedSettings().fontSize == 12 }
}
```

Use this harness so each completion encodes the snapshot that arrived with
that request:

```swift
private actor PersistenceEncoderHarness {
    struct Request {
        let appData: AppData
        let continuation: CheckedContinuation<Data?, Never>
    }

    private var requests: [Request] = []

    func encode(_ appData: AppData) async -> Data? {
        await withCheckedContinuation { continuation in
            requests.append(Request(
                appData: appData,
                continuation: continuation
            ))
        }
    }

    func waitForRequestCount(_ count: Int) async {
        while requests.count < count {
            await Task.yield()
        }
    }

    func complete(request index: Int) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        requests[index].continuation.resume(
            returning: try? encoder.encode(requests[index].appData)
        )
    }
}
```

`makeStore` creates a unique UserDefaults suite, writes an initial encoded
`AppData` under `honkumi.appData`, and passes both that suite and
the following operation to the injected `DocumentStore` initializer:

```swift
{ appData in await harness.encode(appData) }
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -parallel-testing-enabled NO -only-testing:HonkumiTests/DocumentStorePersistenceTests test
```

Expected: build failure because the encode-operation injection and background encoder do not exist.

- [ ] **Step 3: Add the background encoder**

```swift
import Foundation

nonisolated enum AppDataPersistenceEncoder {
    typealias EncodeOperation = @Sendable (AppData) async -> Data?

    static func encode(_ appData: AppData) async -> Data? {
        await Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try? encoder.encode(appData)
        }.value
    }
}
```

- [ ] **Step 4: Gate persisted results by generation**

Inject `EncodeOperation` into the UserDefaults-backed `DocumentStore` initializer, defaulting to `AppDataPersistenceEncoder.encode`. In `scheduleSave()`:

1. Cancel the prior debounce task.
2. Increment `saveGeneration`.
3. Capture immutable `appData`, generation, storage key, and encoder.
4. Debounce for 350 ms.
5. Await background encoding.
6. Check cancellation and `self.saveGeneration == generation`.
7. Write the encoded bytes to UserDefaults.

Keep the existing synchronous initial migration save, which runs only at store creation, but route repeated editing saves through the background operation.

- [ ] **Step 5: Verify GREEN**

Run the Task 4 test command twice to catch ordering assumptions.

Expected: the newer snapshot remains persisted both times and immediate in-memory state assertions pass.

- [ ] **Step 6: Commit Task 4**

```bash
git add Honkumi/Shared/Services/AppDataPersistenceEncoder.swift Honkumi/Shared/Services/DocumentStore.swift HonkumiTests/DocumentStorePersistenceTests.swift
git commit -m "Encode document saves outside the UI thread"
```

---

### Task 5: Show one aggregated emoji replacement warning

**Files:**
- Modify: `Honkumi/Shared/Services/PrintTextNormalizer.swift`
- Modify: `Honkumi/Shared/Services/PDFPreflightService.swift`
- Create: `HonkumiTests/PDFPreflightEmojiWarningTests.swift`
- Modify: `HonkumiTests/PrintTextNormalizerTests.swift`

**Interfaces:**
- Consumes: `PrintTextNormalizationReport`.
- Produces: exactly one `PreflightIssue` with ID `print.textNormalization.emoji`, severity `.warning`, total count, unsupported count, heart count, and replacement destinations.

- [ ] **Step 1: Write the failing preflight warning tests**

```swift
final class PDFPreflightEmojiWarningTests: XCTestCase {
    func testEmojiAndHeartsProduceOneWarningWithCountsAndReplacements() throws {
        var settings = EditorSettings.default
        settings.colophon.isEnabled = false
        let document = ManuscriptDocument(
            title: "題😀",
            body: "本文💡と❤️",
            settings: settings
        )

        let result = PDFPreflightService().check(
            document: document,
            subscriptionStatus: .free
        )
        let issues = result.issues.filter { $0.id == "print.textNormalization.emoji" }

        let issue = try XCTUnwrap(issues.first)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issue.severity, .warning)
        XCTAssertTrue(issue.message.contains("合計3件"))
        XCTAssertTrue(issue.message.contains("2件を□"))
        XCTAssertTrue(issue.message.contains("1件を♡"))
        XCTAssertTrue(result.canContinue)
    }
}
```

Add a no-emoji test and a test proving hidden colophon fields are not counted:

```swift
func testNoEmojiAddsNoReplacementWarning() {
    let document = ManuscriptDocument(title: "題", body: "本文")
    let result = PDFPreflightService().check(
        document: document,
        subscriptionStatus: .free
    )
    XCTAssertFalse(result.issues.contains {
        $0.id == "print.textNormalization.emoji"
    })
}

func testHiddenColophonEmojiIsNotCounted() throws {
    var settings = EditorSettings.default
    settings.colophon.isEnabled = true
    settings.colophon.showsCircleName = false
    settings.colophon.circleName = "非表示😀"
    let document = ManuscriptDocument(title: "題", body: "本文", settings: settings)

    let result = PDFPreflightService().check(
        document: document,
        subscriptionStatus: .free
    )

    XCTAssertFalse(result.issues.contains {
        $0.id == "print.textNormalization.emoji"
    })
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -parallel-testing-enabled NO -only-testing:HonkumiTests/PDFPreflightEmojiWarningTests test
```

Expected: no issue with ID `print.textNormalization.emoji` exists.

- [ ] **Step 3: Add the warning once per preflight**

At the start of `PDFPreflightService.check`, obtain:

```swift
let normalizationReport = ManuscriptRenderPipeline.printTextNormalizationReport(
    for: checkedDocument,
    subscriptionStatus: subscriptionStatus
)
```

Append one warning when `normalizationReport.totalReplacementCount > 0`:

```swift
issues.append(warning(
    id: "print.textNormalization.emoji",
    title: "絵文字を印刷用文字に置換します",
    message: "対象は合計\(report.totalReplacementCount)件です。"
        + "未対応絵文字\(report.unsupportedEmojiReplacementCount)件を□へ、"
        + "ハート\(report.heartReplacementCount)件を♡へ置換してPDFを生成します。",
    location: .init(
        type: .text,
        pageNumber: nil,
        characterRange: nil,
        settingKey: nil
    )
))
```

Update `colophonTextFields(from:)` so it includes only fields that can be printed under the current colophon visibility flags.

- [ ] **Step 4: Verify GREEN and replacement regression**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -parallel-testing-enabled NO -only-testing:HonkumiTests/PDFPreflightEmojiWarningTests -only-testing:HonkumiTests/PrintTextNormalizerTests test
```

Expected: one warning, correct counts, `□` without `×`, and `♡` replacement tests all pass.

- [ ] **Step 5: Commit Task 5**

```bash
git add Honkumi/Shared/Services/PrintTextNormalizer.swift Honkumi/Shared/Services/PDFPreflightService.swift HonkumiTests/PDFPreflightEmojiWarningTests.swift HonkumiTests/PrintTextNormalizerTests.swift
git commit -m "Aggregate emoji replacements into one warning"
```

---

### Task 6: Aggregate long chapter-title issues by chapter occurrence

**Files:**
- Modify: `Honkumi/Shared/Services/ChapterHeaderLayoutPlanner.swift`
- Modify: `Honkumi/Shared/Services/PDFPreflightService.swift`
- Modify: `HonkumiTests/ChapterHeaderLayoutPlannerTests.swift`
- Modify: `HonkumiTests/PDFPreflightChapterHeaderTests.swift`
- Modify: `HonkumiTests/ChapterHeaderPDFRenderingTests.swift`

**Interfaces:**
- Consumes: page order, `chapterTitlesStartingOnPage`, current `chapterTitle`, and physical page numbers.
- Produces: `ChapterHeaderLayoutIssue` with `chapterIndex`, `kind`, `title`, and `pageNumbers`; one issue per chapter index with `.overflow` taking precedence over `.spread`.

- [ ] **Step 1: Write failing aggregation tests**

Add these tests to `ChapterHeaderLayoutPlannerTests`:

```swift
func testOverflowReplacesSpreadForSameChapterOccurrence() {
    let width = pageBodyWidth
    let title = String(repeating: "A", count: Int(width) + 10)
    let pages = [
        bodyPage(title: title, startsTitle: true),
        bodyPage(title: title),
        bodyPage(title: title),
        bodyPage(title: title)
    ]

    let plan = ChapterHeaderLayoutPlanner.makePlan(
        pages: pages,
        settings: chapterSettings,
        subscriptionStatus: .free,
        measureWidth: measure
    )

    XCTAssertEqual(plan.issues.count, 1)
    XCTAssertEqual(plan.issues.first?.chapterIndex, 0)
    XCTAssertEqual(plan.issues.first?.kind, .overflow)
}

func testSameTitleInSeparateChapterOccurrencesKeepsTwoIssues() {
    let title = String(repeating: "A", count: Int(pageBodyWidth) + 1)
    let pages = [
        bodyPage(title: title, startsTitle: true),
        bodyPage(title: title),
        bodyPage(title: title, startsTitle: true),
        bodyPage(title: title)
    ]

    let plan = ChapterHeaderLayoutPlanner.makePlan(
        pages: pages,
        settings: chapterSettings,
        subscriptionStatus: .free,
        measureWidth: measure
    )

    XCTAssertEqual(plan.issues.map(\.chapterIndex), [0, 1])
}
```

Add this preflight regression:

```swift
func testOneLongChapterAcrossManyPagesProducesOneHeaderIssue() {
    let title = makeTitle(exceedingBodyWidths: 1)
    let document = makeDocument(title: title, bodyCharacterCount: 2_000)

    let result = PDFPreflightService().check(
        document: document,
        subscriptionStatus: .free
    )
    let chapterIssues = result.issues.filter {
        $0.id.hasPrefix("pdf.chapterHeader.")
    }

    XCTAssertEqual(chapterIssues.count, 1)
}
```

- [ ] **Step 2: Run the chapter tests and verify RED**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -parallel-testing-enabled NO -only-testing:HonkumiTests/ChapterHeaderLayoutPlannerTests -only-testing:HonkumiTests/PDFPreflightChapterHeaderTests test
```

Expected: multiple issues remain for one chapter or the new issue shape does not compile.

- [ ] **Step 3: Replace the issue enum with an occurrence-aware value**

```swift
nonisolated enum ChapterHeaderLayoutIssueKind: Equatable {
    case spread
    case overflow
}

nonisolated struct ChapterHeaderLayoutIssue: Equatable {
    let chapterIndex: Int
    let kind: ChapterHeaderLayoutIssueKind
    let title: String
    let pageNumbers: [Int]
}
```

While mapping pages to candidates, track chapter occurrence in document order. Increment the index for every entry in `chapterTitlesStartingOnPage`; when synthetic or legacy page data has no start marker, create a new occurrence when the active title first appears or changes.

- [ ] **Step 4: Aggregate and prioritize**

Store issues in `[Int: ChapterHeaderLayoutIssue]`. Recording rules:

```swift
if let existing = issuesByChapter[issue.chapterIndex] {
    if existing.kind == .overflow {
        return
    }
    if issue.kind == .overflow {
        issuesByChapter[issue.chapterIndex] = issue
    }
} else {
    issuesByChapter[issue.chapterIndex] = issue
}
```

Return issues sorted by `chapterIndex`. Keep `fragmentsByPageID` page-based and unchanged.

- [ ] **Step 5: Generate one stable preflight issue**

Switch on `issue.kind` in `PDFPreflightService`. Build IDs as:

```swift
"pdf.chapterHeader.\(kind).chapter.\(issue.chapterIndex)"
```

Use the pages stored in the winning issue for the message and location. Remove the old enumeration index from IDs.

- [ ] **Step 6: Update rendering and regression assertions**

Update existing tests to assert the new struct shape. The PDF rendering test must still join the two fragments into the exact original title, proving that issue aggregation did not change drawing.

- [ ] **Step 7: Verify all chapter tests**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -parallel-testing-enabled NO -only-testing:HonkumiTests/ChapterHeaderLayoutPlannerTests -only-testing:HonkumiTests/PDFPreflightChapterHeaderTests -only-testing:HonkumiTests/ChapterHeaderPDFRenderingTests test
```

Expected: one issue per occurrence, overflow precedence, separate same-name chapters, and unchanged fragment rendering all pass.

- [ ] **Step 8: Commit Task 6**

```bash
git add Honkumi/Shared/Services/ChapterHeaderLayoutPlanner.swift Honkumi/Shared/Services/PDFPreflightService.swift HonkumiTests/ChapterHeaderLayoutPlannerTests.swift HonkumiTests/PDFPreflightChapterHeaderTests.swift HonkumiTests/ChapterHeaderPDFRenderingTests.swift
git commit -m "Deduplicate chapter title issues per chapter"
```

---

### Task 7: Verify integration, performance, configurations, and release contents

**Files:**
- Verify without a planned edit: `Honkumi/Features/Preview/PreviewView.swift`
- Verify without a planned edit: `Honkumi/Features/Preview/PreviewViewModel.swift`
- Verify without a planned edit: `Honkumi/ContentView.swift`

**Interfaces:**
- Consumes: the completed implementations from Tasks 1–6.
- Produces: full test evidence, three successful configuration builds, and a clean diff ready for the requested commit/push workflow.

- [ ] **Step 1: Verify preview behavior has not regressed**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -parallel-testing-enabled NO -only-testing:HonkumiTests/PreviewViewModelSuspensionTests -only-testing:HonkumiTests/ManuscriptRenderPipelinePerformanceTests test
```

Expected: settings suspension still prevents intermediate generation, dismissal generates one latest snapshot, and pagination instrumentation stays within its asserted count.

- [ ] **Step 2: Run the complete test suite**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -parallel-testing-enabled NO test
```

Expected: exit status 0 and zero XCTest failures.

- [ ] **Step 3: Build Debug, Staging, and Release from fresh DerivedData**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/honkumi-followup-debug build
xcodebuild -project Honkumi.xcodeproj -scheme 'Honkumi Staging' -configuration Staging -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/honkumi-followup-staging build
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/honkumi-followup-release build
```

Expected: each command exits with status 0.

- [ ] **Step 4: Re-check Release-only AdMob IDs**

Read the three built `Info.plist` files with `/usr/libexec/PlistBuddy`. Expected:

- Debug and Staging: `ca-app-pub-3940256099942544~1458002511` and `ca-app-pub-3940256099942544/4411468910`.
- Release: `ca-app-pub-5962190341183783~5710900326` and `ca-app-pub-5962190341183783/4969764372`.

- [ ] **Step 5: Review the final patch**

Run:

```bash
git diff --check
git status --short
git diff --stat 5ae4b55
```

Expected: no whitespace errors; only implementation/test files from this plan plus the pre-existing untracked files are present.

- [ ] **Step 6: Push after confirming the exact external destination**

Confirm that the authorized destination is:

```text
https://github.com/Smatsumot0/honkumi.git
branch: codex/print-preview-colophon-fixes
```

Then push without force:

```bash
git push origin codex/print-preview-colophon-fixes
```
