# Logo, Pro Formatting, Chapter Header, and Emoji Follow-up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide one circle-logo selection entry point, make every approved Pro formatting rule work after runtime entitlement refresh, remove chapter-header spread splitting, and separate heart warnings from other emoji warnings.

**Architecture:** Keep `DocumentStore` as the Pro entitlement source of truth and publish its entitlement changes through `SettingsViewModel` so SwiftUI and background formatting use the same snapshot. Use one small presentation state machine for mutually exclusive logo modals, keep text transformations inside `ManuscriptFormatter`, simplify chapter-header planning to per-page measurement, and construct two independent preflight warnings from the existing normalization report.

**Tech Stack:** Swift 6, SwiftUI, PhotosUI, UniformTypeIdentifiers, Combine, UIKit, PDFKit, XCTest, Xcode 26

## Global Constraints

- Minimum deployment target remains iOS 26.2.
- Do not add third-party dependencies or a new UI-test target.
- `DocumentStore` remains the Pro entitlement source of truth.
- Circle-logo settings show one visible selection button; the next modal offers `写真から選択`, `ファイルから選択`, and cancellation.
- Failed or cancelled logo imports preserve the currently stored `circleImageData`.
- Existing-body formatting runs off the MainActor and only the newest body/settings/work/entitlement snapshot may be applied.
- `,`, `､`, and `，` become `、`; `.` becomes `。`.
- Two or more consecutive characters drawn from `─`, `━`, `―`, and `ー` become exactly `――`; a single character remains unchanged.
- Chapter headers never split across pages. Every eligible page independently receives the complete title when it fits.
- A title that exceeds any eligible page's header width creates one blocking error per chapter occurrence.
- Heart replacements and unsupported-emoji replacements produce separate continuable warnings.
- Preserve all unrelated and currently untracked documents and scripts.
- Do not run the all-paper-size or all-font-size sample PDF batches.
- Use test-first RED/GREEN cycles and commit each independently reviewable task.

---

### Task 1: Route one circle-logo button to Photos or Files

**Files:**
- Create: `Honkumi/Features/Settings/CircleLogoImportPresentation.swift`
- Modify: `Honkumi/Features/Settings/ColophonSettingsView.swift:16-40,148-190`
- Create: `HonkumiTests/CircleLogoImportPresentationTests.swift`
- Verify: `HonkumiTests/CircleLogoImageImporterTests.swift`

**Interfaces:**
- Consumes: `PhotosPickerItem`, the existing `CircleLogoImageImporter`, and the existing file-import result handler.
- Produces: `CircleLogoImportPresentation`, with nested `Destination`, `present(_:)`, `dismiss(_:)`, and `isPresented(_:)`.
- Produces: one visible `サークルロゴを選択` button followed by a native `confirmationDialog`.

- [ ] **Step 1: Write the failing presentation-state test**

Create `HonkumiTests/CircleLogoImportPresentationTests.swift`:

```swift
@testable import Honkumi
import XCTest

final class CircleLogoImportPresentationTests: XCTestCase {
    func testReplacingSourceChooserWithPhotoPickerSurvivesStaleDialogDismissal() {
        var presentation = CircleLogoImportPresentation()

        presentation.present(.sourceChooser)
        presentation.present(.photoLibrary)
        presentation.dismiss(.sourceChooser)

        XCTAssertTrue(presentation.isPresented(.photoLibrary))
        XCTAssertFalse(presentation.isPresented(.sourceChooser))
    }

    func testDismissingCurrentDestinationClearsPresentation() {
        var presentation = CircleLogoImportPresentation()

        presentation.present(.fileImporter)
        presentation.dismiss(.fileImporter)

        XCTAssertNil(presentation.destination)
    }
}
```

The first test catches a real modal race: the confirmation dialog can report its own dismissal after the selected picker has replaced it.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/CircleLogoImportPresentationTests test
```

Expected: compilation fails because `CircleLogoImportPresentation` does not exist.

- [ ] **Step 3: Implement the minimal presentation state machine**

Create `Honkumi/Features/Settings/CircleLogoImportPresentation.swift`:

```swift
import Foundation

nonisolated struct CircleLogoImportPresentation: Equatable {
    enum Destination: Equatable {
        case sourceChooser
        case photoLibrary
        case fileImporter
    }

    private(set) var destination: Destination?

    mutating func present(_ destination: Destination) {
        self.destination = destination
    }

    mutating func dismiss(_ destination: Destination) {
        guard self.destination == destination else { return }
        self.destination = nil
    }

    func isPresented(_ destination: Destination) -> Bool {
        self.destination == destination
    }
}
```

- [ ] **Step 4: Verify the state machine is GREEN**

Run the Step 2 command again.

Expected: both `CircleLogoImportPresentationTests` pass.

- [ ] **Step 5: Replace the two visible controls with one button and a source dialog**

In `ColophonSettingsView`, replace `isCircleImageFileImporterPresented` with:

```swift
@State private var circleLogoImportPresentation = CircleLogoImportPresentation()
```

Add a binding helper that prevents an old presentation from clearing the new one:

```swift
private func circleLogoPresentationBinding(
    for destination: CircleLogoImportPresentation.Destination
) -> Binding<Bool> {
    Binding(
        get: { circleLogoImportPresentation.isPresented(destination) },
        set: { isPresented in
            if isPresented {
                circleLogoImportPresentation.present(destination)
            } else {
                circleLogoImportPresentation.dismiss(destination)
            }
        }
    )
}
```

Attach the three presentation modifiers to the `Form`:

```swift
.confirmationDialog(
    "サークルロゴの選択方法",
    isPresented: circleLogoPresentationBinding(for: .sourceChooser)
) {
    Button("写真から選択") {
        circleLogoImportPresentation.present(.photoLibrary)
    }
    Button("ファイルから選択") {
        circleLogoImportPresentation.present(.fileImporter)
    }
    Button("キャンセル", role: .cancel) {}
}
.photosPicker(
    isPresented: circleLogoPresentationBinding(for: .photoLibrary),
    selection: $selectedCircleImageItem,
    matching: .images
)
.fileImporter(
    isPresented: circleLogoPresentationBinding(for: .fileImporter),
    allowedContentTypes: [.image],
    allowsMultipleSelection: false,
    onCompletion: handleCircleImageFileImport
)
```

Replace the paid import-row `VStack` containing `PhotosPicker` and the Files button with:

```swift
Button {
    circleLogoImportPresentation.present(.sourceChooser)
} label: {
    Label("サークルロゴを選択", systemImage: "photo.on.rectangle")
}
.accessibilityIdentifier("colophon.circleLogo.select")
```

Keep the existing preview, delete button, image validation, error alert, and unpaid purchase route unchanged.

- [ ] **Step 6: Run logo regressions and build**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/CircleLogoImportPresentationTests \
  -only-testing:HonkumiTests/CircleLogoImageImporterTests test

xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build
```

Expected: all focused tests pass and Debug builds without a second visible source-selection button.

- [ ] **Step 7: Commit Task 1**

```bash
git add Honkumi/Features/Settings/CircleLogoImportPresentation.swift \
  Honkumi/Features/Settings/ColophonSettingsView.swift \
  HonkumiTests/CircleLogoImportPresentationTests.swift
git commit -m "Unify circle logo selection"
```

---

### Task 2: Implement every approved Pro text transformation

**Files:**
- Modify: `Honkumi/Shared/Services/ManuscriptFormatter.swift:38-74,231-269`
- Create: `HonkumiTests/ManuscriptFormatterTests.swift`

**Interfaces:**
- Consumes: `ManuscriptFormatter.formatManuscriptText(_:settings:options:)`.
- Produces: punctuation normalization for `,`, `､`, `，`, and `.`.
- Produces: dash normalization for mixed or identical runs matching `[─━―ー]{2,}`.
- Preserves: all existing free-rule behavior and the Pro authorization guard.

- [ ] **Step 1: Write failing tests from the approved examples**

Create `HonkumiTests/ManuscriptFormatterTests.swift`:

```swift
@testable import Honkumi
import XCTest

final class ManuscriptFormatterTests: XCTestCase {
    func testPaidRulesTransformApprovedExamples() {
        let input = """
        「てすと。」
        「てすと！てすと」
        (てすと)
        「てすと,」
        「てすと､」
        「てすと，」
        「てすと...」
        「てすと…」
        """
        let expected = """
        「てすと」
        「てすと！　てすと」
        （てすと）
        「てすと、」
        「てすと、」
        「てすと、」
        「てすと……」
        「てすと……」
        """

        XCTAssertEqual(
            ManuscriptFormatter.formatManuscriptText(
                input,
                settings: allPaidRulesEnabled,
                options: FormatOptions(isPremiumUser: true)
            ),
            expected
        )
    }

    func testTwoOrMoreMixedDashCharactersBecomeExactlyTwoHorizontalBars() {
        XCTAssertEqual(
            ManuscriptFormatter.formatManuscriptText(
                "単独―／二つ──／混在━―／三つーーー",
                settings: dashRuleEnabled,
                options: FormatOptions(isPremiumUser: true)
            ),
            "単独―／二つ――／混在――／三つ――"
        )
    }

    func testPaidRulesRemainInactiveForFreeUser() {
        XCTAssertEqual(
            ManuscriptFormatter.formatManuscriptText(
                "「てすと，」とーー",
                settings: allPaidRulesEnabled,
                options: FormatOptions(isPremiumUser: false)
            ),
            "「てすと，」とーー"
        )
    }

    private var allPaidRulesEnabled: FormatSettings {
        var settings = FormatSettings.default
        settings.enableAutoFormat = true
        settings.enableNormalizeEllipsis = true
        settings.enableNormalizeDash = true
        settings.enableSpaceAfterExclamationQuestion = true
        settings.enableNormalizePunctuation = true
        settings.enableNormalizeBrackets = true
        settings.enableRemovePeriodsBeforeClosingBrackets = true
        return settings
    }

    private var dashRuleEnabled: FormatSettings {
        var settings = FormatSettings.default
        settings.enableAutoFormat = true
        settings.enableNormalizeDash = true
        return settings
    }
}
```

- [ ] **Step 2: Run the formatter tests and verify RED**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/ManuscriptFormatterTests test
```

Expected: `testPaidRulesTransformApprovedExamples` fails for `､` and `，`; the dash test fails because the original run is returned unchanged.

- [ ] **Step 3: Implement punctuation and dash normalization**

Update the dash rule copy:

```swift
FormatRule(
    id: \.enableNormalizeDash,
    label: "連続ダッシュの統一",
    description: "─、━、―、ー が2文字以上続く箇所を ―― に整えます。",
    premium: true
)
```

Update the punctuation rule description so the three accepted comma variants are visible:

```swift
description: ",、､、，を読点へ、.を句点へ整えます。",
```

Implement the two helpers:

```swift
private static func normalizeDash(_ text: String) -> String {
    text.replacingOccurrences(
        of: #"[─━―ー]{2,}"#,
        with: "――",
        options: .regularExpression
    )
}

private static func normalizePunctuation(_ text: String) -> String {
    text
        .replacingOccurrences(of: ",", with: "、")
        .replacingOccurrences(of: "､", with: "、")
        .replacingOccurrences(of: "，", with: "、")
        .replacingOccurrences(of: ".", with: "。")
}
```

Do not change transformation order: ellipsis and dash normalization remain before punctuation normalization, and period-before-closing-bracket removal remains last.

- [ ] **Step 4: Verify formatter tests are GREEN**

Run the Step 2 command again.

Expected: all approved examples, mixed dash runs, and the free-user guard pass.

- [ ] **Step 5: Commit Task 2**

```bash
git add Honkumi/Shared/Services/ManuscriptFormatter.swift \
  HonkumiTests/ManuscriptFormatterTests.swift
git commit -m "Fix paid manuscript formatting rules"
```

---

### Task 3: Publish runtime Pro entitlement and apply enabled rules

**Files:**
- Modify: `Honkumi/Features/Settings/SettingsViewModel.swift:21-130,399-460`
- Modify: `HonkumiTests/SettingsFormatApplicationTests.swift`

**Interfaces:**
- Consumes: `DocumentStore.$appData`, `AppData.subscriptionStatus`, current `settings`, and the existing `FormatOperation`.
- Produces: `@Published private(set) var subscriptionStatus: SubscriptionStatus`.
- Produces: entitlement-aware cancellation and runtime free-to-paid application of already enabled premium rules.
- Preserves: `SettingsView` reads `viewModel.isPremiumUser`; the new published property supplies its invalidation signal.

- [ ] **Step 1: Write the failing runtime-entitlement tests**

Add `import Combine` to `SettingsFormatApplicationTests.swift`, then add:

```swift
func testUnlockingProPublishesStatusAndAppliesEnabledPaidRule() async throws {
    var document = ManuscriptDocument(title: "Formatting", body: "A,B.")
    document.settings.formatSettings.enableAutoFormat = true
    document.settings.formatSettings.enableNormalizePunctuation = true
    let store = makeStore(document: document, subscriptionStatus: .free)
    let viewModel = SettingsViewModel(documentStore: store)
    var receivedStatuses: [SubscriptionStatus] = []
    let cancellable = viewModel.$subscriptionStatus.sink {
        receivedStatuses.append($0)
    }

    store.setProUnlocked(true)

    try await waitUntil {
        viewModel.document.body == "A、B。"
    }
    XCTAssertEqual(receivedStatuses, [.free, .paid])
    XCTAssertTrue(viewModel.isPremiumUser)
    withExtendedLifetime(cancellable) {}
}

func testRelockingProRejectsInFlightPaidFormattingResult() async throws {
    var document = ManuscriptDocument(title: "Formatting", body: "original")
    document.settings.formatSettings.enableAutoFormat = true
    document.settings.formatSettings.enableNormalizePunctuation = true
    let store = makeStore(document: document, subscriptionStatus: .free)
    let formatter = ControlledFormatter()
    let viewModel = SettingsViewModel(
        documentStore: store,
        formatOperation: { text, _, _ in
            await formatter.format(text)
        }
    )

    store.setProUnlocked(true)
    try await waitUntil {
        await formatter.requestCount == 1
    }

    store.setProUnlocked(false)
    await formatter.resolveRequest(at: 0, with: "stale paid result")
    try await Task.sleep(for: .milliseconds(30))

    XCTAssertEqual(viewModel.document.body, "original")
    XCTAssertFalse(viewModel.isPremiumUser)
    XCTAssertFalse(viewModel.isApplyingFormat)
}
```

These tests exercise the real `DocumentStore` entitlement mutation. The injected operation only controls completion timing for the stale-result boundary.

- [ ] **Step 2: Run the settings tests and verify RED**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/SettingsFormatApplicationTests test
```

Expected: compilation fails because `SettingsViewModel` has no `$subscriptionStatus` publisher.

- [ ] **Step 3: Publish and observe entitlement changes**

Replace the computed `subscriptionStatus` with:

```swift
@Published private(set) var subscriptionStatus: SubscriptionStatus
```

Initialize it with the same source as the rest of the application:

```swift
self.subscriptionStatus = documentStore.subscriptionStatus
```

Add a second `appData` subscription in `init`:

```swift
documentStore.$appData
    .map(\.subscriptionStatus)
    .removeDuplicates()
    .dropFirst()
    .sink { [weak self] subscriptionStatus in
        self?.handleSubscriptionStatusChange(subscriptionStatus)
    }
    .store(in: &cancellables)
```

Make the derived unlock flags use the published snapshot:

```swift
var isPremiumUser: Bool {
    subscriptionStatus == .paid
}

var isAdditionalFontPackUnlocked: Bool {
    isPremiumUser
}

var isPageNumberFontUnlocked: Bool {
    isPremiumUser
}
```

- [ ] **Step 4: Split format scheduling from change detection**

Keep the existing public update methods. Refactor the private scheduling boundary to:

```swift
private func scheduleFormatApplication(
    previousSettings: EditorSettings,
    updatedSettings: EditorSettings
) {
    guard previousSettings.formatSettings != updatedSettings.formatSettings else { return }
    scheduleFormatApplication(using: updatedSettings)
}

private func scheduleFormatApplication(using updatedSettings: EditorSettings) {
    guard scope == .activeWork else { return }

    invalidateFormatApplication()
    let generation = formatGeneration

    guard updatedSettings.formatSettings.enableAutoFormat else { return }

    let sourceDocument = documentStore.document
    let sourceFormatSettings = updatedSettings.validated.formatSettings
    let sourceOptions = FormatOptions(isPremiumUser: isPremiumUser)
    let operation = formatOperation
    isApplyingFormat = true

    formatTask = Task { [weak self] in
        let formattedBody = await operation(
            sourceDocument.body,
            sourceFormatSettings,
            sourceOptions
        )
        guard let self else { return }
        guard !Task.isCancelled,
              formatGeneration == generation,
              documentStore.document.id == sourceDocument.id,
              documentStore.document.body == sourceDocument.body,
              settings.formatSettings.validated == sourceFormatSettings,
              FormatOptions(isPremiumUser: isPremiumUser) == sourceOptions else {
            if formatGeneration == generation {
                isApplyingFormat = false
            }
            return
        }

        if formattedBody != sourceDocument.body {
            documentStore.updateBody(formattedBody)
        }
        isApplyingFormat = false
    }
}

private func invalidateFormatApplication() {
    formatTask?.cancel()
    formatGeneration += 1
    isApplyingFormat = false
}
```

- [ ] **Step 5: Apply enabled paid rules when Pro becomes available**

Add:

```swift
private func handleSubscriptionStatusChange(_ updatedStatus: SubscriptionStatus) {
    let previousStatus = subscriptionStatus
    guard previousStatus != updatedStatus else { return }

    subscriptionStatus = updatedStatus

    guard previousStatus == .free,
          updatedStatus == .paid,
          scope == .activeWork,
          settings.formatSettings.enableAutoFormat,
          hasEnabledPremiumRule(in: settings.formatSettings) else {
        invalidateFormatApplication()
        return
    }

    scheduleFormatApplication(using: settings)
}

private func hasEnabledPremiumRule(in settings: FormatSettings) -> Bool {
    ManuscriptFormatter.premiumRules.contains { rule in
        settings[keyPath: rule.id]
    }
}
```

This also invalidates a paid task when the entitlement changes back to free. Do not reformat user-default scope because it has no editable work body.

- [ ] **Step 6: Verify entitlement and formatter integration**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/SettingsFormatApplicationTests \
  -only-testing:HonkumiTests/ManuscriptFormatterTests test
```

Expected: runtime status publication, free-to-paid existing-body formatting, stale-result rejection, approved transformations, and the existing superseded-request test all pass.

- [ ] **Step 7: Commit Task 3**

```bash
git add Honkumi/Features/Settings/SettingsViewModel.swift \
  HonkumiTests/SettingsFormatApplicationTests.swift
git commit -m "Sync Pro formatting entitlement"
```

---

### Task 4: Split heart and unsupported-emoji preflight warnings

**Files:**
- Modify: `Honkumi/Shared/Services/PDFPreflightService.swift:96-117`
- Modify: `HonkumiTests/PDFPreflightEmojiWarningTests.swift`
- Verify: `HonkumiTests/PrintTextNormalizerTests.swift`

**Interfaces:**
- Consumes: `PrintTextNormalizationReport.heartReplacementCount` and `.unsupportedEmojiReplacementCount`.
- Produces: warning ID `print.textNormalization.heart` for `♡` replacements.
- Produces: warning ID `print.textNormalization.unsupportedEmoji` for `□` replacements.
- Preserves: both warnings have severity `.warning` and do not prevent PDF generation.

- [ ] **Step 1: Replace the combined-warning test with failing separated-warning tests**

Replace the first test in `PDFPreflightEmojiWarningTests` and update the other ID checks:

```swift
func testEmojiAndHeartsProduceSeparateWarningsWithIndependentCounts() throws {
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
    let heart = try XCTUnwrap(result.issues.first {
        $0.id == "print.textNormalization.heart"
    })
    let unsupported = try XCTUnwrap(result.issues.first {
        $0.id == "print.textNormalization.unsupportedEmoji"
    })

    XCTAssertEqual(heart.severity, .warning)
    XCTAssertTrue(heart.message.contains("1件"))
    XCTAssertTrue(heart.message.contains("♡"))
    XCTAssertEqual(unsupported.severity, .warning)
    XCTAssertTrue(unsupported.message.contains("2件"))
    XCTAssertTrue(unsupported.message.contains("□"))
    XCTAssertTrue(result.canContinue)
}

func testHeartOnlyProducesOnlyHeartWarning() {
    let document = ManuscriptDocument(title: "題", body: "本文❤️")

    let result = PDFPreflightService().check(
        document: document,
        subscriptionStatus: .free
    )

    XCTAssertTrue(result.issues.contains {
        $0.id == "print.textNormalization.heart"
    })
    XCTAssertFalse(result.issues.contains {
        $0.id == "print.textNormalization.unsupportedEmoji"
    })
}

func testUnsupportedEmojiOnlyProducesOnlyUnsupportedWarning() {
    let document = ManuscriptDocument(title: "題", body: "本文😀")

    let result = PDFPreflightService().check(
        document: document,
        subscriptionStatus: .free
    )

    XCTAssertFalse(result.issues.contains {
        $0.id == "print.textNormalization.heart"
    })
    XCTAssertTrue(result.issues.contains {
        $0.id == "print.textNormalization.unsupportedEmoji"
    })
}
```

Replace the existing no-emoji and hidden-colophon assertions with:

```swift
func testNoEmojiAddsNoReplacementWarning() {
    let document = ManuscriptDocument(title: "題", body: "本文")

    let result = PDFPreflightService().check(
        document: document,
        subscriptionStatus: .free
    )

    XCTAssertTrue(result.issues.filter {
        replacementWarningIDs.contains($0.id)
    }.isEmpty)
}

func testHiddenColophonEmojiIsNotCounted() {
    var settings = EditorSettings.default
    settings.colophon.isEnabled = true
    settings.colophon.showsCircleName = false
    settings.colophon.circleName = "非表示😀"
    let document = ManuscriptDocument(
        title: "題",
        body: "本文",
        settings: settings
    )

    let result = PDFPreflightService().check(
        document: document,
        subscriptionStatus: .free
    )

    XCTAssertTrue(result.issues.filter {
        replacementWarningIDs.contains($0.id)
    }.isEmpty)
}

private var replacementWarningIDs: Set<String> {
    [
        "print.textNormalization.heart",
        "print.textNormalization.unsupportedEmoji"
    ]
}
```

- [ ] **Step 2: Run the emoji tests and verify RED**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/PDFPreflightEmojiWarningTests test
```

Expected: the new IDs are absent because the implementation still creates only `print.textNormalization.emoji`.

- [ ] **Step 3: Construct the two warnings independently**

Replace the combined `totalReplacementCount` branch with:

```swift
if normalizationReport.heartReplacementCount > 0 {
    issues.append(warning(
        id: "print.textNormalization.heart",
        title: "ハートを印刷用文字に置換します",
        message: "ハート\(normalizationReport.heartReplacementCount)件を♡へ置換してPDFを生成します。",
        location: .init(
            type: .text,
            pageNumber: nil,
            characterRange: nil,
            settingKey: nil
        )
    ))
}

if normalizationReport.unsupportedEmojiReplacementCount > 0 {
    issues.append(warning(
        id: "print.textNormalization.unsupportedEmoji",
        title: "絵文字を印刷用文字に置換します",
        message: "未対応絵文字\(normalizationReport.unsupportedEmojiReplacementCount)件を□へ置換してPDFを生成します。",
        location: .init(
            type: .text,
            pageNumber: nil,
            characterRange: nil,
            settingKey: nil
        )
    ))
}
```

Do not change `PrintTextNormalizer`; it already classifies hearts and unsupported emoji separately and applies `♡` and `□`.

- [ ] **Step 4: Verify warnings and replacement behavior**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/PDFPreflightEmojiWarningTests \
  -only-testing:HonkumiTests/PrintTextNormalizerTests test
```

Expected: two warnings for mixed input, one warning for single-category input, no warning for printable text or hidden fields, and all replacement tests pass.

- [ ] **Step 5: Commit Task 4**

```bash
git add Honkumi/Shared/Services/PDFPreflightService.swift \
  HonkumiTests/PDFPreflightEmojiWarningTests.swift
git commit -m "Separate heart and emoji warnings"
```

---

### Task 5: Remove chapter-header spread splitting

**Files:**
- Modify: `Honkumi/Shared/Services/ChapterHeaderLayoutPlanner.swift`
- Modify: `Honkumi/Shared/Services/PDFPreflightService.swift:468-509`
- Modify: `HonkumiTests/ChapterHeaderLayoutPlannerTests.swift`
- Modify: `HonkumiTests/PDFPreflightChapterHeaderTests.swift`
- Modify: `HonkumiTests/ChapterHeaderPDFRenderingTests.swift`

**Interfaces:**
- Removes: `ChapterHeaderSplitResult`, `ChapterHeaderLayoutIssueKind`, `split(...)`, and all `.spread` behavior.
- Produces: `ChapterHeaderLayoutIssue(chapterIndex:title:pageNumbers:)`, representing page overflow only.
- Preserves: `ChapterHeaderFragment`, per-page left/right alignment, normalized titles, and chapter-occurrence indexing.
- Produces: one preflight error ID `pdf.chapterHeader.overflow.chapter.<index>` per overflowing chapter occurrence.

- [ ] **Step 1: Replace split tests with failing per-page layout tests**

In `ChapterHeaderLayoutPlannerTests`, remove tests of `split(...)` and spread-fragment recombination. Add:

```swift
func testSameChapterTitleCreatesCompleteFragmentOnEachEligiblePage() {
    var settings = chapterSettings
    settings.pageNumberStart = 2
    let pages = [
        bodyPage(title: "短い章題"),
        bodyPage(title: "短い章題")
    ]

    let plan = ChapterHeaderLayoutPlanner.makePlan(
        pages: pages,
        settings: settings,
        subscriptionStatus: .free,
        measureWidth: measure
    )

    XCTAssertEqual(plan.fragmentsByPageID[pages[0].id]?.text, "短い章題")
    XCTAssertEqual(plan.fragmentsByPageID[pages[1].id]?.text, "短い章題")
    XCTAssertEqual(plan.fragmentsByPageID[pages[0].id]?.alignment, .trailing)
    XCTAssertEqual(plan.fragmentsByPageID[pages[1].id]?.alignment, .leading)
    XCTAssertTrue(plan.issues.isEmpty)
}

func testTitleExceedingOnePageCreatesOneChapterIssueWithoutFragments() {
    var settings = chapterSettings
    settings.pageNumberStart = 2
    let width = LayoutCalculator.layout(for: settings, pageNumber: 2).bodyFrame.width
    let title = String(repeating: "A", count: Int(width) + 1)
    let pages = [
        bodyPage(title: title),
        bodyPage(title: title)
    ]

    let plan = ChapterHeaderLayoutPlanner.makePlan(
        pages: pages,
        settings: settings,
        subscriptionStatus: .free,
        measureWidth: measure
    )

    XCTAssertTrue(plan.fragmentsByPageID.isEmpty)
    XCTAssertEqual(plan.issues, [
        ChapterHeaderLayoutIssue(
            chapterIndex: 0,
            title: title,
            pageNumbers: [2, 3]
        )
    ])
}

func testSameLongTitleInSeparateChapterOccurrencesKeepsTwoIssues() {
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

Retain the existing single-page fit test and chapter-occurrence fixtures.

- [ ] **Step 2: Replace preflight expectations with a page-local blocking error**

In `PDFPreflightChapterHeaderTests`, remove the spread-warning and companion-page tests. Add or update:

```swift
func testTitleExceedingPageWidthAddsBlockingError() throws {
    let title = makeTitle(exceedingBodyWidths: 1)
    let document = makeDocument(title: title, bodyCharacterCount: 700)

    let result = PDFPreflightService().check(
        document: document,
        subscriptionStatus: .free
    )

    let issue = try XCTUnwrap(result.issues.first {
        $0.id.hasPrefix("pdf.chapterHeader.overflow.chapter.")
    })
    XCTAssertEqual(issue.severity, .error)
    XCTAssertEqual(issue.title, "章タイトルがページ内に収まりません")
    XCTAssertFalse(issue.message.contains("見開き"))
    XCTAssertFalse(result.canContinue)
}

func testOneLongChapterAcrossManyPagesProducesOneBlockingHeaderError() {
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
    XCTAssertEqual(chapterIssues.first?.severity, .error)
    XCTAssertFalse(result.canContinue)
}
```

- [ ] **Step 3: Run planner and preflight tests and verify RED**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/ChapterHeaderLayoutPlannerTests \
  -only-testing:HonkumiTests/PDFPreflightChapterHeaderTests test
```

Expected: tests fail because long titles are still split across the physical spread and a continuable spread warning is still emitted.

- [ ] **Step 4: Simplify the planner to measure every page independently**

Replace the issue type with:

```swift
nonisolated struct ChapterHeaderLayoutIssue: Equatable {
    let chapterIndex: Int
    let title: String
    let pageNumbers: [Int]
}
```

Delete `ChapterHeaderSplitResult`, `ChapterHeaderLayoutIssueKind`, `split(...)`, `spreadLeftPageNumber(containing:)`, the spread dictionary, and issue precedence.

After the existing candidate construction, use a single page-order loop:

```swift
var fragments: [UUID: ChapterHeaderFragment] = [:]
var issuesByChapter: [Int: ChapterHeaderLayoutIssue] = [:]

for candidate in candidates {
    guard let title = candidate.title,
          let chapterIndex = candidate.chapterIndex else {
        continue
    }

    let font = font(for: candidate.layout, subscriptionStatus: subscriptionStatus)
    if measureWidth(title, font) <= candidate.layout.bodyFrame.width {
        fragments[candidate.page.id] = singleFragment(for: candidate, title: title)
    } else {
        recordOverflow(
            chapterIndex: chapterIndex,
            title: title,
            pageNumber: candidate.physicalPageNumber,
            in: &issuesByChapter
        )
    }
}
```

Aggregate page numbers without duplicating the chapter issue:

```swift
private static func recordOverflow(
    chapterIndex: Int,
    title: String,
    pageNumber: Int,
    in issuesByChapter: inout [Int: ChapterHeaderLayoutIssue]
) {
    let existingPages = issuesByChapter[chapterIndex]?.pageNumbers ?? []
    let pageNumbers = existingPages.contains(pageNumber)
        ? existingPages
        : existingPages + [pageNumber]
    issuesByChapter[chapterIndex] = ChapterHeaderLayoutIssue(
        chapterIndex: chapterIndex,
        title: title,
        pageNumbers: pageNumbers
    )
}
```

Return issues sorted by `chapterIndex`. Keep `singleFragment(for:title:)` unchanged so odd and even eligible pages retain their original alignment while each receives the full title.

- [ ] **Step 5: Replace spread messaging with one blocking page error**

Replace the `switch issue.kind` block in `PDFPreflightService` with:

```swift
for issue in plan.issues {
    let pageNumbersText = issue.pageNumbers.map(String.init).joined(separator: "・")
    issues.append(error(
        id: "pdf.chapterHeader.overflow.chapter.\(issue.chapterIndex)",
        title: "章タイトルがページ内に収まりません",
        message: "「\(issue.title)」は \(pageNumbersText) ページの上部に収まりません。章タイトルを短くしてください。",
        location: .init(
            type: .page,
            pageNumber: issue.pageNumbers.first,
            characterRange: nil,
            settingKey: "showChapterTitle"
        )
    ))
}
```

No `pdf.chapterHeader.spread` issue may remain.

- [ ] **Step 6: Update the PDF rendering regression**

Replace the spread-fragment test in `ChapterHeaderPDFRenderingTests` with a fitting-title document and assert full-title rendering:

```swift
func testNormalAndSpreadPreviewRenderFullTitleOnEveryEligiblePage() async throws {
    let document = makeFittingTitleDocument()
    let pagination = ManuscriptRenderPipeline.paginationResult(
        for: document,
        subscriptionStatus: .free
    )
    let plan = ChapterHeaderLayoutPlanner.makePlan(
        pages: pagination.pages,
        settings: pagination.document.settings,
        subscriptionStatus: .free
    )
    let fragments = pagination.pages.enumerated().compactMap { index, page in
        plan.fragmentsByPageID[page.id].map { (index, $0) }
    }

    XCTAssertGreaterThanOrEqual(fragments.count, 2)
    XCTAssertTrue(plan.issues.isEmpty)
    XCTAssertTrue(fragments.allSatisfy { $0.1.text == "短い章タイトル" })

    let exporter = PDFExportService()
    let normalURL = try await exporter.export(
        document: document,
        subscriptionStatus: .free
    )
    let spreadURL = try await exporter.exportPreviewPDF(
        document: document,
        subscriptionStatus: .free,
        previewKind: .spread,
        generationID: UUID()
    )
    defer {
        try? FileManager.default.removeItem(at: normalURL)
        try? FileManager.default.removeItem(at: spreadURL)
    }

    let normalPDF = try XCTUnwrap(PDFDocument(url: normalURL))
    for (pageIndex, fragment) in fragments {
        let pageText = try XCTUnwrap(normalPDF.page(at: pageIndex)?.string)
        XCTAssertTrue(pageText.contains(fragment.text))
    }

    let spreadPDF = try XCTUnwrap(PDFDocument(url: spreadURL))
    let spreadText = (0..<spreadPDF.pageCount)
        .compactMap { spreadPDF.page(at: $0)?.string }
        .joined()
    XCTAssertTrue(spreadText.contains("短い章タイトル"))
}
```

Replace the old spread-document helper with:

```swift
private func makeFittingTitleDocument() -> ManuscriptDocument {
    var settings = EditorSettings.default
    settings.showChapterTitle = true
    settings.showTableOfContents = false
    settings.colophon.isEnabled = false
    settings.useRecommendedTypography = false
    settings.useRecommendedMargins = false
    settings.charactersPerLine = 25
    settings.linesPerPage = 10
    settings.pageNumberStart = 1

    return ManuscriptDocument(
        title: "Chapter Header Rendering",
        body: "\(ManuscriptMarkupParser.chapterTag(for: "短い章タイトル"))\n"
            + String(repeating: "本", count: 700),
        settings: settings
    )
}
```

Do not measure or generate a spread-length title.

- [ ] **Step 7: Verify every chapter test is GREEN**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/ChapterHeaderLayoutPlannerTests \
  -only-testing:HonkumiTests/PDFPreflightChapterHeaderTests \
  -only-testing:HonkumiTests/ChapterHeaderPDFRenderingTests test
```

Expected: eligible pages contain full titles, over-width titles create one blocking error per chapter occurrence, same-name chapters remain separate, and no spread issue exists.

- [ ] **Step 8: Commit Task 5**

```bash
git add Honkumi/Shared/Services/ChapterHeaderLayoutPlanner.swift \
  Honkumi/Shared/Services/PDFPreflightService.swift \
  HonkumiTests/ChapterHeaderLayoutPlannerTests.swift \
  HonkumiTests/PDFPreflightChapterHeaderTests.swift \
  HonkumiTests/ChapterHeaderPDFRenderingTests.swift
git commit -m "Remove chapter header spread layout"
```

---

### Task 6: Verify the integrated behavior without heavy sample generation

**Files:**
- Verify: all files changed in Tasks 1-5
- Preserve without modification: unrelated untracked documents and scripts

**Interfaces:**
- Consumes: all task-level commits and the `Honkumi` / `Honkumi Staging` schemes.
- Produces: focused tests, full XCTest, Debug/Staging/Release builds, and a concise simulator checklist result.

- [ ] **Step 1: Run all focused regression suites together**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/CircleLogoImportPresentationTests \
  -only-testing:HonkumiTests/CircleLogoImageImporterTests \
  -only-testing:HonkumiTests/ManuscriptFormatterTests \
  -only-testing:HonkumiTests/SettingsFormatApplicationTests \
  -only-testing:HonkumiTests/PDFPreflightEmojiWarningTests \
  -only-testing:HonkumiTests/PrintTextNormalizerTests \
  -only-testing:HonkumiTests/ChapterHeaderLayoutPlannerTests \
  -only-testing:HonkumiTests/PDFPreflightChapterHeaderTests \
  -only-testing:HonkumiTests/ChapterHeaderPDFRenderingTests test
```

Expected: every listed suite passes with no test failure.

- [ ] **Step 2: Run the complete XCTest suite**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -parallel-testing-enabled NO test
```

Expected: the entire `HonkumiTests` target passes.

- [ ] **Step 3: Build every configuration**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/honkumi-logo-format-debug build

xcodebuild -project Honkumi.xcodeproj -scheme 'Honkumi Staging' \
  -configuration Staging \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/honkumi-logo-format-staging build

xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/honkumi-logo-format-release build
```

Expected: all three builds exit successfully. Do not run either sample-PDF batch.

- [ ] **Step 4: Perform a lightweight simulator interaction check**

Use the Debug app and verify:

1. The paid circle-logo row contains one `サークルロゴを選択` button.
2. Tapping it shows `写真から選択`, `ファイルから選択`, and cancellation.
3. Choosing each source opens the corresponding system picker.
4. After runtime Pro entitlement is active, switching auto-format off and on converts the approved example text.
5. A document containing both `❤️` and `😀` shows two continuable preflight warnings with the correct replacement destination.
6. A chapter title longer than one page-header width shows one blocking error and no spread warning.

If a system picker cannot be automated, record the visible source-dialog result and verify its state-machine and importer boundaries through the passing tests.

- [ ] **Step 5: Inspect the final diff and repository state**

Run:

```bash
git diff --check
git status --short
git log --oneline --decorate -8
```

Expected:

- No whitespace errors.
- Only intended code/test changes and the implementation plan are committed.
- Unrelated untracked documents and scripts remain unmodified and uncommitted.
- No sample PDFs or DerivedData are added to the repository.

- [ ] **Step 6: Prepare the handoff**

Report:

- Exact focused and full test counts.
- Debug, Staging, and Release build results.
- Simulator interaction result and any system-picker limitation.
- Commit hashes for each task.
- Current branch and whether it is ahead of its remote.

Do not push until the user explicitly authorizes the external Git destination for this completed batch.
