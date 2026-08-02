# First Launch, Editor, and PDF Ad Gate Stabilization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate first-launch editor and PDF jank while requiring a successfully presented interstitial ad for eligible free-tier PDF exports, except when Google reports no ad inventory.

**Architecture:** Restore the validated editor viewport guard, rely exclusively on `UIAppFonts` for bundled fonts, and replace launch-time interstitial preloading with an explicit export-time gate. The ad service classifies Google errors into app-owned outcomes; the coordinator serializes ad preparation, PDF generation, ad presentation, and sharing; `WorkspaceView` displays the current asynchronous phase.

**Tech Stack:** Swift 6, SwiftUI, UIKit, XCTest, Google Mobile Ads SDK, User Messaging Platform SDK, Xcode 26.5, iOS 26.5 Simulator.

## Global Constraints

- Preserve all existing uncommitted user changes. Do not stash, reset, restore, or stage unrelated files.
- Keep the existing per-document five-minute ad cooldown.
- Pro users never start, load, or present ads.
- Free exports continue without a new ad only for Google `noFill` or an active cooldown.
- Network, timeout, consent, configuration, unknown load, `canPresent`, and presentation failures block sharing.
- Do not start, load, or automatically retry an interstitial during launch or ordinary editor use.
- Do not overlap interstitial loading with PDF generation.
- Keep Google SDK types inside `GooglePDFExportAdAdapters.swift`.
- Preserve the 30-second PDF timeout and add a separate 15-second ad-load timeout.
- Removing redundant launch font registration is a pure deletion. Validate it with the manifest contract and fresh-simulator logs; do not add a source-text assertion or test-only production API.

## File Map

- `ManuscriptTextEditor.swift` and `ManuscriptTextEditorViewportTests.swift`: unchanged-input viewport behavior.
- `HonkumiApp.swift`, `AppFont.swift`, and `BundledFontManifestTests.swift`: declarative font registration.
- `PDFExportAdGate.swift`: SDK-independent ad outcomes and progress phases.
- `GooglePDFExportAdAdapters.swift` and its classifier tests: Google error mapping.
- `PDFExportAdService.swift` and its tests: consent-only launch and bounded export-time loading.
- `PDFExportFlowCoordinator.swift`, `PDFExportTimeout.swift`, and coordinator tests: serialized gate/PDF/ad/share flow.
- `ContentView.swift`: progress and error presentation.

---

### Task 1: Restore the editor viewport regression fix

**Files:**
- Create: `HonkumiTests/ManuscriptTextEditorViewportTests.swift`
- Modify: `Honkumi/Shared/Components/ManuscriptTextEditor.swift:17-22,538-580`

**Interfaces:**
- Consumes: `ManuscriptLiveFormattingResult`.
- Produces: `ManuscriptTextEditorViewportPolicy.shouldAdjustAfterLiveFormatting(originalText:result:) -> Bool`.

- [ ] **Step 1: Add the failing tests from commit `855829b`**

Create the test file from `git show 855829b:HonkumiTests/ManuscriptTextEditorViewportTests.swift`. It contains one real coordinator test using a `UITextView` subclass that counts `setContentOffset`, plus three policy cases: auto-format disabled/unchanged is false, auto-format enabled/unchanged is false, and changed punctuation is true.

The key real-behavior assertion is:

```swift
coordinator.textViewDidChange(textView)
XCTAssertEqual(textView.setContentOffsetCallCount, 0)
XCTAssertEqual(text, "本文")
XCTAssertEqual(selectedRange, NSRange(location: 2, length: 0))
```

Removing the unchanged-text early return must make this test fail.

- [ ] **Step 2: Run RED**

```bash
xcodebuild test -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/HonkumiEditorViewportTests \
  -only-testing:HonkumiTests/ManuscriptTextEditorViewportTests
```

Expected: FAIL because the policy is absent and unchanged input resets the offset.

- [ ] **Step 3: Implement the minimal policy and early return**

```swift
nonisolated enum ManuscriptTextEditorViewportPolicy {
    static func shouldAdjustAfterLiveFormatting(
        originalText: String,
        result: ManuscriptLiveFormattingResult
    ) -> Bool {
        result.text != originalText
    }
}
```

Immediately after formatting in `applyLiveFormatAndCommit`, add:

```swift
guard ManuscriptTextEditorViewportPolicy.shouldAdjustAfterLiveFormatting(
    originalText: originalText,
    result: result
) else {
    parent.text = result.text
    parent.selectedRange = result.selectedRange
    return
}
```

Make the existing replacement block unconditional. Leave explicit navigation and keyboard-transition behavior unchanged.

- [ ] **Step 4: Run GREEN and commit**

Run Step 2 again; expect PASS. Then:

```bash
git add Honkumi/Shared/Components/ManuscriptTextEditor.swift \
  HonkumiTests/ManuscriptTextEditorViewportTests.swift
git commit -m "fix: stabilize editor input viewport"
```

---

### Task 2: Remove duplicate launch font registration

**Files:**
- Create: `HonkumiTests/BundledFontManifestTests.swift`
- Modify: `Honkumi/HonkumiApp.swift:9-13`
- Modify: `Honkumi/Shared/Models/AppFont.swift:1-3,506-519,545-558`

**Interfaces:**
- Consumes: `AppFontCatalog.all`, `AppFontCatalog.pageNumberFonts`, and `UIAppFonts`.
- Produces: one declarative registration contract and no CoreText registration during app initialization.

- [ ] **Step 1: Add the manifest/runtime contract test**

```swift
final class BundledFontManifestTests: XCTestCase {
    func testEveryCatalogFontIsDeclaredAndAvailableWithoutManualRegistration() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Honkumi/Info.plist"))
        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any]
        )
        let declared = Set(try XCTUnwrap(plist["UIAppFonts"] as? [String]))
        let catalog = Set(
            AppFontCatalog.all.compactMap(\.fileName)
                + AppFontCatalog.pageNumberFonts.map(\.fileName)
        )
        XCTAssertEqual(declared, catalog)
        for font in AppFontCatalog.all where font.postScriptName != nil {
            XCTAssertNotNil(UIFont(name: font.postScriptName!, size: 12), font.id)
        }
        for font in AppFontCatalog.pageNumberFonts {
            XCTAssertNotNil(UIFont(name: font.postScriptName, size: 12), font.id)
        }
    }
}
```

This catches missing manifest entries and wrong PostScript names. It is expected to pass before the pure deletion; the observed fresh-launch `file already registered` logs are the RED evidence for the redundant call.

- [ ] **Step 2: Delete procedural registration**

- Remove `AppFontCatalog.registerBundledFonts()` from `HonkumiApp.init`.
- Confirm no other caller with `rg -n 'registerBundledFonts|registerFont\(' Honkumi HonkumiTests`.
- Remove `registerBundledFonts()`, `registerFont(fileName:)`, `registeredFontFiles`, and the unused `CoreText` import.

- [ ] **Step 3: Verify and commit**

```bash
xcodebuild test -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/HonkumiFontManifestTests \
  -only-testing:HonkumiTests/BundledFontManifestTests \
  -only-testing:HonkumiTests/PageNumberFontSizeTests

git add Honkumi/HonkumiApp.swift Honkumi/Shared/Models/AppFont.swift \
  HonkumiTests/BundledFontManifestTests.swift
git commit -m "fix: avoid duplicate launch font registration"
```

Expected: tests PASS; final runtime verification must remove the duplicate-registration log.

---

### Task 3: Add SDK-independent ad outcomes and Google error classification

**Files:**
- Create: `Honkumi/Shared/Services/PDFExportAdGate.swift`
- Modify: `Honkumi/Shared/Services/GooglePDFExportAdAdapters.swift:43-49`
- Create: `HonkumiTests/GooglePDFExportAdErrorClassifierTests.swift`

**Interfaces:**
- Produces: `PDFExportAdPreparationResult`, `PDFExportAdPresentationResult`, `PDFExportAdBlockReason`, `PDFExportInterstitialAdLoadResult`, and `PDFExportProgressPhase`.
- Changes loader signature to `loadInterstitialAd(adUnitID:) async -> PDFExportInterstitialAdLoadResult`.

- [ ] **Step 1: Add failing classifier tests**

Use real Google error domain/code values without a network request:

```swift
func testNoFillIsTheOnlyNonBlockingGoogleLoadFailure() {
    let result = GooglePDFExportAdErrorClassifier.classify(
        NSError(domain: GADErrorDomain, code: RequestError.Code.noFill.rawValue)
    )
    XCTAssertEqual(result.blockingClassification, .noFill)
}

func testNetworkFailureBlocksExport() {
    let result = GooglePDFExportAdErrorClassifier.classify(
        NSError(domain: GADErrorDomain, code: RequestError.Code.networkError.rawValue)
    )
    XCTAssertEqual(result.blockingClassification, .blocked(.networkUnavailable))
}

func testUnknownFailureBlocksExport() {
    let result = GooglePDFExportAdErrorClassifier.classify(
        NSError(domain: "jp.honkumi.tests", code: 999)
    )
    XCTAssertEqual(result.blockingClassification, .blocked(.loadFailed))
}
```

- [ ] **Step 2: Run RED**

```bash
xcodebuild test -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/HonkumiAdClassifierTests \
  -only-testing:HonkumiTests/GooglePDFExportAdErrorClassifierTests
```

Expected: compile failure because the outcomes and classifier do not exist.

- [ ] **Step 3: Create the app-owned contracts**

```swift
nonisolated enum PDFExportAdBlockReason: Equatable {
    case networkUnavailable, timedOut, consentUnavailable
    case invalidConfiguration, loadFailed, presentationFailed
}

nonisolated enum PDFExportAdPreparationResult: Equatable {
    case ready, notRequired, noFill
    case blocked(PDFExportAdBlockReason)
}

nonisolated enum PDFExportAdPresentationResult: Equatable {
    case presented
    case blocked(PDFExportAdBlockReason)
}

enum PDFExportInterstitialAdLoadResult {
    case loaded(PDFExportInterstitialAd)
    case noFill
    case blocked(PDFExportAdBlockReason)

    nonisolated var blockingClassification: PDFExportAdPreparationResult {
        switch self {
        case .loaded: .ready
        case .noFill: .noFill
        case .blocked(let reason): .blocked(reason)
        }
    }
}

nonisolated enum PDFExportProgressPhase: Equatable {
    case preparingAd, generatingPDF
}
```

- [ ] **Step 4: Classify only Google no-fill as non-blocking**

Implement `GooglePDFExportAdErrorClassifier.classify(_:)`. Require `GADErrorDomain`; return `.noFill` only for `RequestError.Code.noFill.rawValue`; map network and Google timeout to `.blocked(.networkUnavailable)`; map every other domain/code to `.blocked(.loadFailed)`. The loader returns `.loaded(ad)` on success and the classifier result on failure, logging original diagnostics.

- [ ] **Step 5: Run GREEN and commit**

Run Step 2 again; expect PASS. Then:

```bash
git add Honkumi/Shared/Services/PDFExportAdGate.swift \
  Honkumi/Shared/Services/GooglePDFExportAdAdapters.swift \
  HonkumiTests/GooglePDFExportAdErrorClassifierTests.swift
git commit -m "feat: classify PDF export ad load outcomes"
```

---

### Task 4: Replace launch preloading with a bounded on-demand ad service

**Files:**
- Modify: `Honkumi/Shared/Services/PDFExportAdService.swift`
- Modify: `HonkumiTests/PDFExportAdServiceTests.swift`

**Interfaces:**
- Produces: `prepareAdForExport(documentID:entitlementState:) async -> PDFExportAdPreparationResult`.
- Produces: `presentPreparedAd(documentID:) async -> PDFExportAdPresentationResult`.
- Removes: `preloadAdIfEligible`, retry scheduling, and post-dismiss preloading.

- [ ] **Step 1: Write failing service tests**

Add or rewrite tests for these exact behaviors:

```swift
func testLaunchPreparationUpdatesConsentWithoutStartingOrLoadingAds() async {
    let consent = SuspendedPDFExportConsentManager(canRequestAds: true)
    let harness = AdServiceHarness(consentManager: consent, loaderResults: [])
    async let preparation: Void = harness.service.prepareForAppLaunch()
    await Task.yield()
    XCTAssertEqual(consent.requestConsentInfoUpdateCount, 1)
    XCTAssertEqual(harness.mobileAdsStarter.startCount, 0)
    XCTAssertEqual(harness.loader.loadCount, 0)
    consent.finishConsentInfoUpdate()
    await preparation
    XCTAssertEqual(consent.loadAndPresentConsentFormCount, 1)
    XCTAssertEqual(harness.mobileAdsStarter.startCount, 0)
    XCTAssertEqual(harness.loader.loadCount, 0)
}

func testNoFillAllowsExportWithoutAutomaticRetry() async {
    let harness = AdServiceHarness(loaderResults: [.noFill])
    let result = await harness.service.prepareAdForExport(
        documentID: UUID(), entitlementState: .free
    )
    XCTAssertEqual(result, .noFill)
    XCTAssertEqual(harness.loader.loadCount, 1)
}

func testNetworkFailureBlocksExport() async {
    let harness = AdServiceHarness(loaderResults: [.blocked(.networkUnavailable)])
    let result = await harness.service.prepareAdForExport(
        documentID: UUID(), entitlementState: .free
    )
    XCTAssertEqual(result, .blocked(.networkUnavailable))
}
```

Also cover: first free export loads and returns `.ready`; Pro/unknown do not start SDK; cooldown does not load; 15-second timeout beats a suspended loader; a late ad is discarded; successful dismissal returns `.presented`; `canPresent` and delegate failure return `.blocked(.presentationFailed)`; duplicate callbacks complete once.

Delete old tests that require background retry or immediate sharing on failure, because the approved design supersedes them.

- [ ] **Step 2: Run RED**

```bash
xcodebuild test -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/HonkumiAdServiceTests \
  -only-testing:HonkumiTests/PDFExportAdServiceTests
```

Expected: FAIL because launch still loads ads and the new methods do not exist.

- [ ] **Step 3: Make launch consent-only**

Keep only this sequence inside `prepareForAppLaunch`:

```swift
let update = PDFExportConsentInfoUpdate()
consentManager.requestConsentInfoUpdate { update.finish() }
await update.wait()
await consentManager.loadAndPresentConsentFormIfRequired()
```

- [ ] **Step 4: Implement bounded export preparation**

Check, in order: entitlement, configuration, consent, cooldown, retained ad, SDK start, bounded load. Return `.notRequired` for Pro/unknown/cooldown, `.blocked(.invalidConfiguration)` for invalid configuration, and `.blocked(.consentUnavailable)` when UMP disallows requests.

Race the loader against an injected `PDFExportTimeoutSleeping` for `.seconds(15)` using two `@MainActor` tasks and a one-shot continuation gate. Cancel both after the first result. Never retain an ad returned after the timeout.

- [ ] **Step 5: Return a presentation outcome**

Change the delegate completion to `(PDFExportAdPresentationResult) -> Void`. Dismissal returns `.presented`; `canPresent` or delegate failure returns `.blocked(.presentationFailed)`. Keep the one-shot guard and record cooldown only from `interstitialAdWillPresent`.

- [ ] **Step 6: Remove retries, run GREEN, and commit**

Remove retry scheduler protocols/state and every background `Task { preload... }`. Run Step 2 again; expect PASS. Then:

```bash
git add Honkumi/Shared/Services/PDFExportAdService.swift \
  HonkumiTests/PDFExportAdServiceTests.swift
git commit -m "fix: gate free PDF exports on ad availability"
```

---

### Task 5: Serialize the coordinator and expose progress

**Files:**
- Modify: `Honkumi/Shared/Services/PDFExportFlowCoordinator.swift`
- Modify: `Honkumi/Shared/Services/PDFExportTimeout.swift`
- Modify: `HonkumiTests/PDFExportFlowCoordinatorTests.swift`

**Interfaces:**
- Changes `PDFExportAdPresenting` to Task 4's prepare/present API.
- Adds `updatePhase: @MainActor (PDFExportProgressPhase?) -> Void` with a default no-op.
- Adds an Equatable ad-unavailable `PDFExportFlowError` case and `alertTitle`.

- [ ] **Step 1: Add failing flow tests**

Require this success order:

```swift
XCTAssertEqual(events.values, [
    "phase-ad", "ad-prepare", "phase-pdf", "pdf-start", "pdf-success",
    "ad-present", "share", "phase-clear"
])
```

Add branches for: no-fill shares without presentation; network block never starts PDF; presentation failure never shares; Pro/not-required skips ad work; PDF timeout after successful preparation never presents; every path clears the phase. Assert consumer-visible share/error outcomes, not merely fake call counts.

- [ ] **Step 2: Run RED**

```bash
xcodebuild test -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/HonkumiAdFlowTests \
  -only-testing:HonkumiTests/PDFExportFlowCoordinatorTests
```

Expected: FAIL because PDF currently precedes ad preparation and failures still share.

- [ ] **Step 3: Implement the exact serialized flow**

```swift
let preparation: PDFExportAdPreparationResult
if entitlementState == .free {
    updatePhase(.preparingAd)
    preparation = await adPresenter.prepareAdForExport(
        documentID: document.id,
        entitlementState: entitlementState
    )
} else {
    preparation = .notRequired
}
if case .blocked(let reason) = preparation {
    throw PDFExportFlowError.adUnavailable(reason)
}

updatePhase(.generatingPDF)
let url = try await exportWithTimeout(...)
if preparation == .ready {
    let presentation = await adPresenter.presentPreparedAd(documentID: document.id)
    guard presentation == .presented else {
        try? fileManager.removeItem(at: url)
        throw PDFExportFlowError.adUnavailable(.presentationFailed)
    }
}
storeGeneratedURL(url)
share(url)
```

Call `updatePhase(nil)` from `defer`. Keep the existing PDF timeout completion gate.

- [ ] **Step 4: Add user-facing errors and phase labels**

Add:

```swift
case .adUnavailable:
    "通信環境を確認して、もう一度PDF出力をお試しください。"
```

`alertTitle` returns `広告を読み込めませんでした` for ad errors and `PDF出力に失敗しました` for PDF errors. `PDFExportProgressPhase.displayText` returns `広告を準備しています…` and `PDFを生成しています…` respectively. Add assertions for these user-visible projections.

- [ ] **Step 5: Run GREEN and commit**

Run Step 2 and Task 4 Step 2; expect PASS. Then:

```bash
git add Honkumi/Shared/Services/PDFExportFlowCoordinator.swift \
  Honkumi/Shared/Services/PDFExportTimeout.swift \
  Honkumi/Shared/Services/PDFExportAdGate.swift \
  HonkumiTests/PDFExportFlowCoordinatorTests.swift
git commit -m "fix: serialize PDF export behind ad gate"
```

---

### Task 6: Connect launch and Workspace UI, then verify first launch

**Files:**
- Modify: `Honkumi/ContentView.swift:133-151,178-188,238-255,304-311,430-460`

**Interfaces:**
- Consumes: `PDFExportProgressPhase` and `PDFExportFlowError.alertTitle`.
- Produces: responsive progress UI and ad-specific retry messaging.

- [ ] **Step 1: Remove launch/editor interstitial triggers**

- Keep `prepareForAppLaunch()` in `.task`; it is now consent-only.
- Remove the entitlement `.onChange` task that calls `preloadAdIfEligible()`.
- Keep `synchronizeProEntitlement`.
- Do not wrap the consent-only main-actor call in `Task(priority: .utility)`.

- [ ] **Step 2: Render phases and errors**

Add `@State private var exportProgressPhase: PDFExportProgressPhase?` and `@State private var exportErrorTitle = "PDF出力に失敗しました"`. Extend the existing material overlay to show `ProgressView` and `phase.displayText`. Pass `updatePhase: { exportProgressPhase = $0 }` to the coordinator. In `handleError`, use `PDFExportFlowError.alertTitle` and `localizedDescription`, and change the alert to use `exportErrorTitle`.

- [ ] **Step 3: Run targeted tests and build**

```bash
xcodebuild test -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/HonkumiFirstLaunchGate \
  -only-testing:HonkumiTests/ManuscriptTextEditorViewportTests \
  -only-testing:HonkumiTests/BundledFontManifestTests \
  -only-testing:HonkumiTests/GooglePDFExportAdErrorClassifierTests \
  -only-testing:HonkumiTests/PDFExportAdServiceTests \
  -only-testing:HonkumiTests/PDFExportFlowCoordinatorTests

xcodebuild build -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/HonkumiFirstLaunchGate
```

Expected: targeted tests PASS and Debug Simulator build succeeds.

- [ ] **Step 4: Commit UI integration**

```bash
git add Honkumi/ContentView.swift
git commit -m "fix: show responsive PDF export progress"
```

- [ ] **Step 5: Run full tests and fresh-simulator diagnostics**

Run the full Honkumi test target on iOS 26.5. Create a new disposable `iPhone 17 Pro / iOS 26.5` simulator, build to `/tmp/HonkumiFirstLaunchVerification`, install, capture launch logs, and verify before PDF export:

- no `file already registered` or `Failed to register font file`;
- no Mobile Ads SDK start log;
- no sustained interstitial WebKit JavaScript activity while editing;
- ordinary input causes no viewport jump.

Then verify the Debug test-ad flow: `広告を準備しています…` → `PDFを生成しています…` → interstitial → one share sheet. Verify deterministic `noFill` through unit tests. With network disabled, verify the ad alert appears and the share sheet does not.

- [ ] **Step 6: Remove only the disposable simulator and review the diff**

Shut down and delete only the simulator created in Step 5. Run:

```bash
git diff --check
git status --short
```

Confirm all unrelated pre-existing modifications and artifact deletions remain unchanged and unstaged. Do not commit generated PDFs, DerivedData, logs, or `/tmp` output.

## Self-Review

- Spec coverage: editor, duplicate fonts, consent-only launch, mandatory first free export, no-fill exception, network blocking, presentation failure, cooldown, progress, timeout, and first-launch measurement each map to a task.
- Placeholder scan: no `TBD`, `TODO`, unspecified error branch, or deferred implementation remains.
- Type consistency: preparation precedes PDF generation; presentation occurs only for `.ready`; sharing occurs only after `.presented`, `.noFill`, or `.notRequired`.
- Scope: no preview, typography, StoreKit, or settings refactor is included.
