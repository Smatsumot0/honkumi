# UMP, AdMob, and Per-Work Cooldown Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** UMP同意画面を起動時に必要な場合だけ自動処理し、Releaseだけ本番AdMob IDへ切り替える。PDF出力広告の5分間隔は作品UUID単位・メモリ内だけで管理し、アプリ再起動後は再表示可能にする。

**Architecture:** 広告presentation APIへ作品UUIDを通し、cooldown storeを`[UUID: Date]`のプロセスメモリ実装へ置換する。広告開始delegateを受け取った瞬間だけ該当UUIDを記録する。UMPは既存の起動時`requestConsentInfoUpdate`→`loadAndPresentIfRequired`経路をテストで固定し、手動privacy options APIを削除する。AdMob IDはxcconfigのReleaseだけを編集し、構成ファイルとbuilt Info.plistの両方を検証する。

**Tech Stack:** Swift Concurrency、Google Mobile Ads SDK、User Messaging Platform、xcconfig、XCTest、XcodeBuild

## Global Constraints

- Depends on: `2026-07-26-pdf-timeout-and-emoji-normalization.md` Task 2。`PDFExportFlowCoordinator`のtimeout処理を保持したままad presenter signatureへ作品IDを追加する。
- Release本番ID:
  - app: `ca-app-pub-5962190341183783~5710900326`
  - interstitial: `ca-app-pub-5962190341183783/4969764372`
- Debug/StagingはGoogle公式テストIDと`ADS_TEST_MODE`を維持する。
- cooldownはUserDefaults、Keychain、fileへ保存しない。
- UMP/広告の全失敗はPDF共有とアプリ起動を妨げない。
- 設定画面へprivacy settingsボタンを追加しない。

---

## Task 1: cooldown storeを作品UUID別のメモリ実装へ変更する

**Files:**

- Modify: `Honkumi/Shared/Services/PDFExportAdCooldownStore.swift`
- Modify: `HonkumiTests/PDFExportAdServiceTests.swift`

**Produces:**

- `InMemoryPDFExportAdCooldownStore`
- `PDFExportAdCooldownPolicy.duration == 300`

### Steps

- [ ] 1. 先にstore/policyテストを次の形へ変更する。

```swift
@MainActor
func testCooldownIsStoredIndependentlyPerDocument() {
    let store = InMemoryPDFExportAdCooldownStore()
    let workA = UUID()
    let workB = UUID()
    let date = Date(timeIntervalSince1970: 1_000)

    store.recordPresentation(at: date, for: workA)

    XCTAssertEqual(store.lastPresentedAt(for: workA), date)
    XCTAssertNil(store.lastPresentedAt(for: workB))
}

func testCooldownDurationIsFiveMinutes() {
    XCTAssertEqual(PDFExportAdCooldownPolicy.duration, 5 * 60)
}

@MainActor
func testNewStoreDoesNotRestorePreviousProcessState() {
    let work = UUID()
    let first = InMemoryPDFExportAdCooldownStore()
    first.recordPresentation(at: Date(), for: work)

    let relaunched = InMemoryPDFExportAdCooldownStore()
    XCTAssertNil(relaunched.lastPresentedAt(for: work))
}
```

既存`testCooldownRestoresFromUserDefaults`は逆要件なので削除し、この再起動相当テストへ置換する。

- [ ] 2. protocolを新APIへ変更する前にテストを実行し、メソッド未定義と10分期待の差で失敗することを確認する。

- [ ] 3. store protocolと実装を置換する。

```swift
@MainActor
protocol PDFExportAdCooldownStoring: AnyObject {
    func lastPresentedAt(for documentID: UUID) -> Date?
    func recordPresentation(at date: Date, for documentID: UUID)
}

@MainActor
final class InMemoryPDFExportAdCooldownStore: PDFExportAdCooldownStoring {
    private var datesByDocumentID: [UUID: Date] = [:]

    func lastPresentedAt(for documentID: UUID) -> Date? {
        datesByDocumentID[documentID]
    }

    func recordPresentation(at date: Date, for documentID: UUID) {
        datesByDocumentID[documentID] = date
    }
}

struct PDFExportAdCooldownPolicy {
    static let duration: TimeInterval = 5 * 60
    // existing isCoolingDown implementation
}
```

- [ ] 4. `UserDefaultsPDFExportAdCooldownStore`、storage key、UserDefaults import/useを削除する。

- [ ] 5. テストharnessは製品の`InMemoryPDFExportAdCooldownStore`を直接使い、テスト内の同名private fakeを削除する。

- [ ] 6. store/policyテストを実行してコミットする。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test -only-testing:HonkumiTests/PDFExportAdServiceTests
git add Honkumi/Shared/Services/PDFExportAdCooldownStore.swift \
  HonkumiTests/PDFExportAdServiceTests.swift
git commit -m "Store PDF ad cooldowns per work in memory"
```

---

## Task 2: 作品UUIDを広告表示境界まで渡す

**Files:**

- Modify: `Honkumi/Shared/Services/PDFExportFlowCoordinator.swift`
- Modify: `Honkumi/Shared/Services/PDFExportAdService.swift`
- Modify: `HonkumiTests/PDFExportFlowCoordinatorTests.swift`
- Modify: `HonkumiTests/PDFExportAdServiceTests.swift`

**Consumes:**

- Task 1のper-work store
- timeout planの`PDFExportFlowCoordinator.exportAndShare`

**Produces:**

- `PDFExportAdPresenting.presentAdIfNeeded(documentID:entitlementState:)`

### Steps

- [ ] 1. flow testのfake presenterに受信値を記録させ、成功時に`document.id`が渡る失敗テストを追加する。

```swift
func presentAdIfNeeded(
    documentID: UUID,
    entitlementState: ProEntitlementState
) async {
    requests.append((documentID, entitlementState))
    events.append("ad")
}
```

- [ ] 2. ad service testsへ次のシナリオを追加する。

  - Aで`willPresent`後、299秒時点のAはskip。
  - Aがcooldown中でもBはloaded adがあれば表示。
  - Aは300秒ちょうどで再表示。
  - Bの表示はAの最終時刻を書き換えない。
  - `canPresent`失敗、no-loaded-ad、`didFailToPresent`のみでは該当UUIDを記録しない。
  - delegateが`willPresent`を重複通知しても1回だけ記録。

- [ ] 3. signature不一致と単一cooldown参照でテストが失敗することを確認する。

- [ ] 4. protocolを変更する。

```swift
@MainActor
protocol PDFExportAdPresenting: AnyObject {
    func presentAdIfNeeded(
        documentID: UUID,
        entitlementState: ProEntitlementState
    ) async
}
```

- [ ] 5. coordinator成功経路で作品IDを渡す。

```swift
await adPresenter.presentAdIfNeeded(
    documentID: document.id,
    entitlementState: entitlementState
)
```

- [ ] 6. `PDFExportAdService.presentAdIfNeeded`のcooldown checkをUUID別へ変える。

```swift
guard !cooldownPolicy.isCoolingDown(
    lastPresentedAt: cooldownStore.lastPresentedAt(for: documentID),
    now: clock.now
) else {
    logSkip("presentation skipped because cooldown is active for \(documentID.uuidString)")
    return
}
```

- [ ] 7. `presentLoadedAd`へ`documentID`を渡し、`PDFExportAdPresentation`が保持する。

```swift
func interstitialAdWillPresent() {
    guard !hasRecordedPresentation else { return }
    hasRecordedPresentation = true
    cooldownStore.recordPresentation(at: clock.now, for: documentID)
}
```

`ad.present()`呼び出し時ではなくdelegate callback時にだけ記録する。

- [ ] 8. harnessのad queueへA/B/A用の3広告を用意し、各dismiss後に`await service.preloadAdIfEligible()`して次のloaded adを確定してから次の作品を検証する。非同期background preloadのタイミングにテストを依存させない。

- [ ] 9. flow/ad testsを実行する。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test -only-testing:HonkumiTests/PDFExportFlowCoordinatorTests \
  -only-testing:HonkumiTests/PDFExportAdServiceTests
```

- [ ] 10. コミットする。

```bash
git add Honkumi/Shared/Services/PDFExportFlowCoordinator.swift \
  Honkumi/Shared/Services/PDFExportAdService.swift \
  HonkumiTests/PDFExportFlowCoordinatorTests.swift \
  HonkumiTests/PDFExportAdServiceTests.swift
git commit -m "Apply PDF ad cooldown per work"
```

---

## Task 3: UMPの自動同意フローだけを残す

**Files:**

- Modify: `Honkumi/Shared/Services/PDFExportAdService.swift`
- Modify: `Honkumi/Shared/Services/GooglePDFExportAdAdapters.swift`
- Modify: `HonkumiTests/PDFExportAdServiceTests.swift`
- Verify: `Honkumi/HonkumiApp.swift`
- Verify: `Honkumi/ContentView.swift`
- Verify: `Honkumi/Features/Settings/SettingsView.swift`

### Steps

- [ ] 1. 起動フローの順序を記録するfake consent managerを作り、次を先にテストする。

  - 起動ごとに`requestConsentInfoUpdate`を1回呼ぶ。
  - update completion前に前回同意の`canRequestAds == true`なら非ブロッキングpreloadを試す。
  - update completion後に`loadAndPresentConsentFormIfRequired`を1回呼ぶ。
  - form完了後に最新の`canRequestAds`でpreloadを再判定する。
  - `canRequestAds == false`ならMobile Ads SDKを開始しない。
  - consent update/formが失敗相当でも`prepareForAppLaunch`が完了し、PDF flowのshareを妨げない。

Google adapterの`ConsentForm.loadAndPresentIfRequired`自体が「必要な場合だけ表示」を判断するため、サービス側で独自の地域・status判定を追加しない。

- [ ] 2. privacy optionsの手動再表示APIを削除する。

```swift
// Remove from PDFExportConsentManaging:
func presentPrivacyOptionsForm() async throws

// Remove from PDFExportAdService:
func presentPrivacyOptionsForm() async

// Remove from GooglePDFExportConsentManager:
func presentPrivacyOptionsForm() async throws
```

fake implementationsからも削除する。

- [ ] 3. `HonkumiApp`/`ContentView`でアプリ起動時に`prepareForAppLaunch()`が呼ばれる既存接続を保持する。重複起動Taskを追加しない。

- [ ] 4. Settings全体を`rg -n "privacy|プライバシー|presentPrivacyOptions"`で確認し、UMP再表示ボタンがないことを確認する。

- [ ] 5. UMP/広告error catchはlogだけに留め、throwをPDF flowへ伝播しない。

- [ ] 6. 対象テストを実行してコミットする。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test -only-testing:HonkumiTests/PDFExportAdServiceTests
git add Honkumi/Shared/Services/PDFExportAdService.swift \
  Honkumi/Shared/Services/GooglePDFExportAdAdapters.swift \
  HonkumiTests/PDFExportAdServiceTests.swift
git commit -m "Keep UMP consent automatic and nonblocking"
```

---

## Task 4: Releaseだけ本番AdMob IDへ置き換える

**Files:**

- Modify: `Honkumi/Config/AdMob-Release.xcconfig`
- Modify: `HonkumiTests/AdMobInfoPlistTests.swift`

### Steps

- [ ] 1. 構成ファイルを直接読むテストhelperを追加し、3 configurationを比較する失敗テストを書く。

`AdMobInfoPlistTests.swift`の先頭へ`@testable import Honkumi`を追加し、公式test ID定数を製品コードと共有する。

```swift
func testReleaseUsesProductionAdMobIDs() throws {
    let release = try loadConfig(named: "AdMob-Release.xcconfig")
    XCTAssertTrue(release.contains(
        "ADMOB_APPLICATION_ID = ca-app-pub-5962190341183783~5710900326"
    ))
    XCTAssertTrue(release.contains(
        "ADMOB_INTERSTITIAL_AD_UNIT_ID = ca-app-pub-5962190341183783/4969764372"
    ))
    XCTAssertFalse(release.contains("ADS_TEST_MODE"))
}

func testDebugAndStagingKeepOfficialTestIDsAndTestMode() throws {
    for name in ["AdMob-Debug.xcconfig", "AdMob-Staging.xcconfig"] {
        let config = try loadConfig(named: name)
        XCTAssertTrue(config.contains(PDFExportAdConfiguration.officialTestApplicationID))
        XCTAssertTrue(config.contains(PDFExportAdConfiguration.officialTestInterstitialAdUnitID))
        XCTAssertTrue(config.contains("-D ADS_TEST_MODE"))
        XCTAssertFalse(config.contains("5962190341183783"))
    }
}
```

- [ ] 2. placeholder Release値でテストが失敗することを確認する。

- [ ] 3. `AdMob-Release.xcconfig`だけを変更する。

```xcconfig
ADMOB_APPLICATION_ID = ca-app-pub-5962190341183783~5710900326
ADMOB_INTERSTITIAL_AD_UNIT_ID = ca-app-pub-5962190341183783/4969764372
```

placeholder用コメントは「Release production IDs」に更新する。Debug/Stagingは編集しない。

- [ ] 4. testsを実行する。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test -only-testing:HonkumiTests/AdMobInfoPlistTests
```

- [ ] 5. Debug、Staging、Releaseをそれぞれbuildし、built Info.plistを確認する。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/honkumi-admob-debug build
xcodebuild -project Honkumi.xcodeproj -scheme 'Honkumi Staging' -configuration Staging \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/honkumi-admob-staging build
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/honkumi-admob-release build
```

次を`plutil -p`で確認する。

```bash
plutil -p /tmp/honkumi-admob-release/Build/Products/Release-iphonesimulator/Honkumi.app/Info.plist
plutil -p /tmp/honkumi-admob-debug/Build/Products/Debug-iphonesimulator/Honkumi.app/Info.plist
plutil -p /tmp/honkumi-admob-staging/Build/Products/Staging-iphonesimulator/Honkumi.app/Info.plist
```

Releaseに本番2 ID、Debug/Stagingに公式test 2 IDが入り、構成間で混在しないことを記録する。

- [ ] 6. コミットする。

```bash
git add Honkumi/Config/AdMob-Release.xcconfig \
  HonkumiTests/AdMobInfoPlistTests.swift
git commit -m "Configure production AdMob IDs for Release"
```

---

## Task 5: 広告不可・失敗時にも共有が継続する統合境界を確認する

**Files:**

- Modify: `HonkumiTests/PDFExportAdServiceTests.swift`
- Modify: `HonkumiTests/PDFExportFlowCoordinatorTests.swift`

### Steps

- [ ] 1. 次の各ケースでPDF success後のshareが正確に1回になるテストを揃える。

  - UMP `canRequestAds == false`
  - config disabled
  - SDK未開始
  - ad未読込
  - `canPresent`失敗
  - `didFailToPresent`
  - 同一作品cooldown中
  - Pro/unknown entitlement

- [ ] 2. timeout/通常PDF errorではad requestとshareが0回である既存flow testsを維持する。

- [ ] 3. A→B→Aの時系列テストを追加する。

```text
t=0    A willPresent → A=0を記録
t=60   B willPresent → B=60を記録
t=299  A skip
t=300  A willPresent
```

- [ ] 4. 新しい`PDFExportAdService`インスタンスと新しいin-memory storeを作ると、t=1でもAが表示可能なことを確認する。これをアプリ終了後再起動相当とする。

- [ ] 5. 全広告関連テストを実行する。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test -only-testing:HonkumiTests/PDFExportAdServiceTests \
  -only-testing:HonkumiTests/PDFExportFlowCoordinatorTests \
  -only-testing:HonkumiTests/AdMobInfoPlistTests
```

- [ ] 6. テスト追加分をコミットする。

```bash
git add HonkumiTests/PDFExportAdServiceTests.swift \
  HonkumiTests/PDFExportFlowCoordinatorTests.swift
git commit -m "Cover nonblocking PDF ad boundaries"
```

## Completion Evidence

- 作品A/Bのcooldownが独立し、durationは300秒、new service/storeで履歴が消える。
- `willPresent`以外の経路で時刻が記録されない。
- UMPは起動時自動処理だけで、広告不可・失敗でもPDF共有できる。
- built Release Info.plistだけが指定本番IDを持ち、Debug/Stagingは公式テストIDのままである。
