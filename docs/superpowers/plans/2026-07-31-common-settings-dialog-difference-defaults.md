# Common Settings Dialog Difference Defaults Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 共通設定適用ダイアログを、対象作品と現在の共通設定が異なる分類だけオンの状態で開き、アップデート前から未確認の既存作品だけは最初の確認を全分類オンにする。

**Architecture:** `EditorSettings` の既存選択適用処理を分類ごとの差分判定にも再利用し、UIではなく `DocumentStore` が確認要求へ初期選択を格納する。`AppData` には分類履歴ではなく移行時点のリビジョン境界だけを保存し、境界より古い作品に限って従来の全選択を維持する。

**Tech Stack:** Swift 5、SwiftUI、Foundation `Codable`、XCTest、Xcode 26

## Global Constraints

- 比較単位は「エディタ設定」「サークル設定」「フォーマット設定」「印刷設定」の4分類とする。
- 各分類は、共通設定をその分類だけ作品へ適用した結果が変わる場合だけオンにする。
- 作品側で独自に変更したため共通設定と異なる分類もオンにする。
- 共通設定の分類別変更履歴は保存せず、未確認だった複数セッションの変更を累積しない。
- アップデート前から未確認の既存作品は、最初の確認だけ全分類オンにする。
- 既存作品が移行時点の変更を確認した後は、通常の差分初期選択へ切り替える。
- サークル設定の差分範囲は、既存の選択適用がコピーする発行者情報だけとし、作品固有の奥付項目は含めない。
- 全分類が一致していても既存のリビジョン確認ダイアログは表示し、全分類オフで開始する。
- 全分類オフでは既存どおり「適用して開く」を無効にする。
- ダイアログの文言、レイアウト、操作方法、背景操作防止、アクセシビリティ、確認解決処理は変更しない。
- 既存の未コミット変更を取り込まず、各コミットではこの計画に記載したファイルだけを明示的にステージする。

## File Structure

- `Honkumi/Shared/Models/AppData.swift`: 既存データの全選択フォールバックに使う移行リビジョン境界を保存・復元する。
- `Honkumi/Shared/Services/UserDefaultSettingsApplication.swift`: 選択適用と同じ範囲を使い、作品設定と共通設定の差分分類を算出する。
- `Honkumi/Shared/Services/UserDefaultSettingsReview.swift`: 確認要求が初期選択を値として保持する。
- `Honkumi/Shared/Services/DocumentStore.swift`: 移行境界または現在値の差分から確認要求の初期選択を決定する。
- `Honkumi/Features/Library/CommonSettingsReviewDialog.swift`: 確認要求の初期選択で表示状態を初期化する。
- `HonkumiTests/CommonSettingsRevisionCodingTests.swift`: 移行境界の欠落時復元とラウンドトリップを検証する。
- `HonkumiTests/UserDefaultSettingsReviewTests.swift`: 4分類の差分、移行フォールバック、確認要求を検証する。
- `HonkumiTests/CommonSettingsReviewPresentationTests.swift`: 確認要求からダイアログ初期選択への受け渡しを検証する。

---

### Task 1: 既存データ用の全選択リビジョン境界を保存する

**Files:**
- Modify: `Honkumi/Shared/Models/AppData.swift:3-73`
- Modify: `Honkumi/Shared/Services/DocumentStore.swift:406-414`
- Test: `HonkumiTests/CommonSettingsRevisionCodingTests.swift:4-66`

**Interfaces:**
- Consumes: 既存の `AppData.userDefaultSettingsRevision: Int` とカスタム `Decodable` 実装
- Produces: `AppData.legacyFullSelectionRevision: Int`。新規データでは `0`、フィールドを持たない既存データでは復号時点の `userDefaultSettingsRevision`

- [ ] **Step 1: 欠落フィールドと明示フィールドの復号テストを書く**

`HonkumiTests/CommonSettingsRevisionCodingTests.swift` のテストクラスへ次を追加する。

```swift
func testLegacyAppDataUsesCurrentRevisionAsFullSelectionBoundary() throws {
    let document = ManuscriptDocument(
        title: "Legacy",
        reviewedUserDefaultSettingsRevision: 3
    )
    let appData = AppData(
        version: AppData.currentVersion,
        categories: [.uncategorized],
        works: [document],
        userDefaultSettings: .default,
        activeWorkId: document.id,
        subscriptionStatus: .free,
        userDefaultSettingsRevision: 7
    )
    let legacyData = try removingKeys(
        ["legacyFullSelectionRevision"],
        from: JSONEncoder().encode(appData)
    )

    let decoded = try JSONDecoder().decode(AppData.self, from: legacyData)

    XCTAssertEqual(decoded.legacyFullSelectionRevision, 7)
}

func testFullSelectionBoundaryRoundTripsWithoutAdvancing() throws {
    let appData = AppData(
        version: AppData.currentVersion,
        categories: [.uncategorized],
        works: [],
        userDefaultSettings: .default,
        activeWorkId: nil,
        subscriptionStatus: .free,
        userDefaultSettingsRevision: 9,
        legacyFullSelectionRevision: 4
    )

    let decoded = try JSONDecoder().decode(
        AppData.self,
        from: JSONEncoder().encode(appData)
    )

    XCTAssertEqual(decoded.userDefaultSettingsRevision, 9)
    XCTAssertEqual(decoded.legacyFullSelectionRevision, 4)
}
```

- [ ] **Step 2: 復号テストがコンパイルに失敗することを確認する**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -only-testing:HonkumiTests/CommonSettingsRevisionCodingTests \
  test
```

Expected: FAIL。`AppData` に `legacyFullSelectionRevision` が存在しないため、追加したテストがコンパイルエラーになる。

- [ ] **Step 3: `AppData` に移行境界を追加して欠落時だけ現在リビジョンを採用する**

`Honkumi/Shared/Models/AppData.swift` へフィールドとCodingKeyを追加し、復号処理でリビジョンを先に読み取る。

```swift
var userDefaultSettingsRevision: Int = 0
var legacyFullSelectionRevision: Int = 0
```

```swift
private enum CodingKeys: String, CodingKey {
    case version
    case categories
    case works
    case userDefaultSettings
    case activeWorkId
    case subscriptionStatus
    case userDefaultSettingsRevision
    case legacyFullSelectionRevision
}
```

`init(from:)` は次の形へ置き換える。既存キーが存在しない場合だけ、保存されていた現在リビジョンを境界にする。

```swift
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let revision = try container.decodeIfPresent(
        Int.self,
        forKey: .userDefaultSettingsRevision
    ) ?? 0
    let legacyBoundary = try container.decodeIfPresent(
        Int.self,
        forKey: .legacyFullSelectionRevision
    ) ?? revision

    self.init(
        version: try container.decodeIfPresent(
            Int.self,
            forKey: .version
        ) ?? Self.currentVersion,
        categories: try container.decodeIfPresent(
            [WorkCategory].self,
            forKey: .categories
        ) ?? [.uncategorized],
        works: try container.decodeIfPresent(
            [ManuscriptDocument].self,
            forKey: .works
        ) ?? [],
        userDefaultSettings: try container.decodeIfPresent(
            EditorSettings.self,
            forKey: .userDefaultSettings
        ) ?? .default,
        activeWorkId: try container.decodeIfPresent(
            UUID.self,
            forKey: .activeWorkId
        ),
        subscriptionStatus: try container.decodeIfPresent(
            SubscriptionStatus.self,
            forKey: .subscriptionStatus
        ) ?? .free,
        userDefaultSettingsRevision: revision,
        legacyFullSelectionRevision: legacyBoundary
    )
}
```

`AppData.emptyLibrary`、`AppData.initial`、通常のmemberwise initializer利用箇所は、デフォルト値`0`を使うため変更しない。`AppData.currentVersion`も変更しない。

- [ ] **Step 4: 正規化時に境界を有効なリビジョン範囲へ収める**

`DocumentStore.normalized(_:)` で共通設定リビジョンを正規化した直後へ次を追加する。

```swift
normalizedData.legacyFullSelectionRevision = min(
    max(normalizedData.legacyFullSelectionRevision, 0),
    normalizedData.userDefaultSettingsRevision
)
```

これにより壊れた負数や現在リビジョンより未来の境界を、`0...userDefaultSettingsRevision`へ収める。

- [ ] **Step 5: 復号・正規化テストを実行してGREENを確認する**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -only-testing:HonkumiTests/CommonSettingsRevisionCodingTests \
  -only-testing:HonkumiTests/CommonSettingsSessionTests \
  test
```

Expected: PASS。既存のリビジョン互換性テストを含め、失敗0。

- [ ] **Step 6: Task 1のファイルだけをコミットする**

```bash
git add \
  Honkumi/Shared/Models/AppData.swift \
  Honkumi/Shared/Services/DocumentStore.swift \
  HonkumiTests/CommonSettingsRevisionCodingTests.swift
git diff --cached --check
git commit -m "Persist common settings review migration boundary"
```

Expected: 3ファイルだけがコミットされ、既存の未コミット変更はステージされない。

---

### Task 2: 作品と共通設定の差分分類を確認要求へ格納する

**Files:**
- Modify: `Honkumi/Shared/Services/UserDefaultSettingsApplication.swift:3-57`
- Modify: `Honkumi/Shared/Services/UserDefaultSettingsReview.swift:3-12`
- Modify: `Honkumi/Shared/Services/DocumentStore.swift:135-147`
- Test: `HonkumiTests/UserDefaultSettingsReviewTests.swift:6-492`

**Interfaces:**
- Consumes: `EditorSettings.applyingUserDefaults(_:selection:) -> EditorSettings`、Task 1の `AppData.legacyFullSelectionRevision: Int`
- Produces: `EditorSettings.userDefaultSettingsSelection(differingFrom:) -> UserDefaultSettingsSelection`、`UserDefaultSettingsReviewRequest.initialSelection: UserDefaultSettingsSelection`

- [ ] **Step 1: 4分類と作品固有奥付を対象にした差分判定テストを書く**

`HonkumiTests/UserDefaultSettingsReviewTests.swift` へ次を追加する。

```swift
func testDifferenceSelectionIncludesOnlyEditorChanges() {
    let work = EditorSettings.default
    var defaults = work
    defaults.editorFontSize = 18

    XCTAssertEqual(
        work.userDefaultSettingsSelection(differingFrom: defaults),
        UserDefaultSettingsSelection(editor: true)
    )
}

func testDifferenceSelectionIncludesOnlyCircleChanges() {
    let work = EditorSettings.default
    var defaults = work
    defaults.colophon.authorName = "共通作者"

    XCTAssertEqual(
        work.userDefaultSettingsSelection(differingFrom: defaults),
        UserDefaultSettingsSelection(circle: true)
    )
}

func testDifferenceSelectionIncludesOnlyFormatChanges() {
    let work = EditorSettings.default
    var defaults = work
    defaults.formatSettings.enableAutoFormat = true

    XCTAssertEqual(
        work.userDefaultSettingsSelection(differingFrom: defaults),
        UserDefaultSettingsSelection(format: true)
    )
}

func testDifferenceSelectionIncludesOnlyPrintChanges() {
    let work = EditorSettings.default
    var defaults = work
    defaults.pageSize = .b6

    XCTAssertEqual(
        work.userDefaultSettingsSelection(differingFrom: defaults),
        UserDefaultSettingsSelection(print: true)
    )
}

func testDifferenceSelectionIgnoresWorkSpecificColophonChanges() {
    var work = EditorSettings.default
    work.colophon.isEnabled = true
    work.colophon.workTitle = "作品固有タイトル"
    work.colophon.publicationDate = Date(timeIntervalSince1970: 1_700_000_000)
    work.colophon.printerName = "作品の印刷所"

    XCTAssertEqual(
        work.userDefaultSettingsSelection(differingFrom: .default),
        UserDefaultSettingsSelection()
    )
}

func testDifferenceSelectionCombinesCurrentDifferences() {
    let work = EditorSettings.default
    var defaults = work
    defaults.editorFontSize = 18
    defaults.formatSettings.enableIndent = true
    defaults.marginInner = 24

    XCTAssertEqual(
        work.userDefaultSettingsSelection(differingFrom: defaults),
        UserDefaultSettingsSelection(
            editor: true,
            format: true,
            print: true
        )
    )
}
```

- [ ] **Step 2: 確認要求の差分選択と既存データフォールバックのテストを書く**

既存の `testOlderWorkRequestsReviewAfterCommonRevisionAdvances` では、期待値へ現在差分のエディタ選択を追加する。

```swift
XCTAssertEqual(
    store.userDefaultSettingsReviewRequest(for: store.document.id),
    UserDefaultSettingsReviewRequest(
        workID: store.document.id,
        revision: 2,
        initialSelection: UserDefaultSettingsSelection(editor: true)
    )
)
```

さらに次の2テストを追加する。

```swift
func testLegacyPendingWorkRequestsAllGroups() throws {
    var work = ManuscriptDocument(
        title: "既存作品",
        reviewedUserDefaultSettingsRevision: 1
    )
    work.settings = .default
    let store = DocumentStore(
        appData: AppData(
            version: AppData.currentVersion,
            categories: [.uncategorized],
            works: [work],
            userDefaultSettings: .default,
            activeWorkId: work.id,
            subscriptionStatus: .free,
            userDefaultSettingsRevision: 2,
            legacyFullSelectionRevision: 2
        )
    )

    let request = try XCTUnwrap(
        store.userDefaultSettingsReviewRequest(for: work.id)
    )

    XCTAssertEqual(request.initialSelection, .all)
}

func testReviewedLegacyBoundaryUsesDifferencesForNextRevision() throws {
    let work = ManuscriptDocument(
        title: "既存作品",
        settings: .default,
        reviewedUserDefaultSettingsRevision: 1
    )
    let store = DocumentStore(
        appData: AppData(
            version: AppData.currentVersion,
            categories: [.uncategorized],
            works: [work],
            userDefaultSettings: .default,
            activeWorkId: work.id,
            subscriptionStatus: .free,
            userDefaultSettingsRevision: 2,
            legacyFullSelectionRevision: 2
        )
    )
    let legacyRequest = try XCTUnwrap(
        store.userDefaultSettingsReviewRequest(for: work.id)
    )
    _ = store.resolveUserDefaultSettingsReview(
        legacyRequest,
        decision: .keepCurrent
    )
    let sessionStart = store.userDefaultSettings
    var changed = sessionStart
    changed.pageSize = .b6
    store.updateUserDefaultSettings(changed)
    XCTAssertTrue(
        store.finishUserDefaultSettingsSession(startingFrom: sessionStart)
    )

    let nextRequest = try XCTUnwrap(
        store.userDefaultSettingsReviewRequest(for: work.id)
    )

    XCTAssertEqual(
        nextRequest.initialSelection,
        UserDefaultSettingsSelection(print: true)
    )
}
```

- [ ] **Step 3: 新しい差分APIがないためテストが失敗することを確認する**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -only-testing:HonkumiTests/UserDefaultSettingsReviewTests \
  test
```

Expected: FAIL。`userDefaultSettingsSelection(differingFrom:)` と `initialSelection` が未定義のためコンパイルに失敗する。

- [ ] **Step 4: 選択適用と同じ範囲から差分分類を算出する**

`Honkumi/Shared/Services/UserDefaultSettingsApplication.swift` の既存extensionへ次を追加する。

```swift
func userDefaultSettingsSelection(
    differingFrom userDefaults: EditorSettings
) -> UserDefaultSettingsSelection {
    let current = validated

    func differs(_ selection: UserDefaultSettingsSelection) -> Bool {
        current.applyingUserDefaults(
            userDefaults,
            selection: selection
        ) != current
    }

    return UserDefaultSettingsSelection(
        editor: differs(UserDefaultSettingsSelection(editor: true)),
        circle: differs(UserDefaultSettingsSelection(circle: true)),
        format: differs(UserDefaultSettingsSelection(format: true)),
        print: differs(UserDefaultSettingsSelection(print: true))
    )
}
```

各分類のフィールドを再列挙しない。`applyingPublisherInfo(from:)`を通るため、サークル設定の作品固有奥付は比較対象外になる。

- [ ] **Step 5: 確認要求に初期選択を追加する**

`Honkumi/Shared/Services/UserDefaultSettingsReview.swift` の `UserDefaultSettingsReviewRequest` を次へ変更する。デフォルト`.all`は既存のテストや直接生成するstale requestの意味を維持する。

```swift
nonisolated struct UserDefaultSettingsReviewRequest:
    Identifiable,
    Equatable {
    let workID: UUID
    let revision: Int
    let initialSelection: UserDefaultSettingsSelection

    init(
        workID: UUID,
        revision: Int,
        initialSelection: UserDefaultSettingsSelection = .all
    ) {
        self.workID = workID
        self.revision = revision
        self.initialSelection = initialSelection
    }

    var id: UUID {
        workID
    }
}
```

- [ ] **Step 6: `DocumentStore` が移行境界または現在差分を選ぶようにする**

`DocumentStore.userDefaultSettingsReviewRequest(for:)` のguard後を次へ変更する。

```swift
let initialSelection: UserDefaultSettingsSelection
if work.reviewedUserDefaultSettingsRevision <
    appData.legacyFullSelectionRevision {
    initialSelection = .all
} else {
    initialSelection = work.settings.userDefaultSettingsSelection(
        differingFrom: appData.userDefaultSettings
    )
}

return UserDefaultSettingsReviewRequest(
    workID: workID,
    revision: appData.userDefaultSettingsRevision,
    initialSelection: initialSelection
)
```

`resolveUserDefaultSettingsReview` の適用・見送り・リビジョン更新処理は変更しない。

- [ ] **Step 7: 差分、移行境界、既存の選択適用テストを実行してGREENを確認する**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -only-testing:HonkumiTests/UserDefaultSettingsReviewTests \
  test
```

Expected: PASS。4分類、複合差分、作品固有奥付の除外、既存データ全選択、境界確認後の差分切替、既存の選択適用がすべて成功する。

- [ ] **Step 8: Task 2のファイルだけをコミットする**

```bash
git add \
  Honkumi/Shared/Services/UserDefaultSettingsApplication.swift \
  Honkumi/Shared/Services/UserDefaultSettingsReview.swift \
  Honkumi/Shared/Services/DocumentStore.swift \
  HonkumiTests/UserDefaultSettingsReviewTests.swift
git diff --cached --check
git commit -m "Select differing common settings by default"
```

Expected: 4ファイルだけがコミットされる。

---

### Task 3: 確認要求の初期選択をダイアログ表示へ引き継ぐ

**Files:**
- Modify: `Honkumi/Features/Library/CommonSettingsReviewDialog.swift:15-23`
- Test: `HonkumiTests/CommonSettingsReviewPresentationTests.swift:7-33`

**Interfaces:**
- Consumes: Task 2の `UserDefaultSettingsReviewRequest.initialSelection: UserDefaultSettingsSelection`
- Produces: `CommonSettingsReviewPresentation.init(request:)`。`selection`を要求の初期選択で初期化し、その後は従来どおりUIから変更可能

- [ ] **Step 1: 確認要求の選択がプレゼンテーションへ渡るテストを書く**

`CommonSettingsReviewPresentationTests.testNewPresentationSelectsEveryGroup` を次のテストへ置き換える。

```swift
func testNewPresentationUsesRequestInitialSelection() {
    let initialSelection = UserDefaultSettingsSelection(
        circle: true,
        print: true
    )
    let request = UserDefaultSettingsReviewRequest(
        workID: UUID(),
        revision: 4,
        initialSelection: initialSelection
    )

    let presentation = CommonSettingsReviewPresentation(
        request: request
    )

    XCTAssertEqual(presentation.selection, initialSelection)
    XCTAssertTrue(presentation.canApply)
}
```

既存の `testApplyIsDisabledWhenEveryGroupIsOff` は維持する。request initializerのデフォルト `.all` によりセットアップは変更不要である。

- [ ] **Step 2: プレゼンテーションがまだ`.all`を使うためテストが失敗することを確認する**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -only-testing:HonkumiTests/CommonSettingsReviewPresentationTests/testNewPresentationUsesRequestInitialSelection \
  test
```

Expected: FAIL。実際の `presentation.selection` が `.all` のため、要求の `circle + print` と一致しない。

- [ ] **Step 3: プレゼンテーションを要求の初期選択で初期化する**

`Honkumi/Features/Library/CommonSettingsReviewDialog.swift` の `CommonSettingsReviewPresentation` を次へ変更する。

```swift
nonisolated struct CommonSettingsReviewPresentation:
    Identifiable,
    Equatable {
    let request: UserDefaultSettingsReviewRequest
    var selection: UserDefaultSettingsSelection

    init(request: UserDefaultSettingsReviewRequest) {
        self.request = request
        self.selection = request.initialSelection
    }

    var id: UUID { request.workID }
    var canApply: Bool { !selection.isEmpty }
}
```

`WorkListView` は既に `CommonSettingsReviewPresentation(request:)` を使うため変更しない。ダイアログ本体、binding、ボタン、レイアウトも変更しない。

- [ ] **Step 4: プレゼンテーションと関連フローのテストを実行してGREENを確認する**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -only-testing:HonkumiTests/CommonSettingsReviewPresentationTests \
  -only-testing:HonkumiTests/UserDefaultSettingsReviewTests \
  -only-testing:HonkumiTests/CommonSettingsRevisionCodingTests \
  -only-testing:HonkumiTests/CommonSettingsSessionTests \
  test
```

Expected: PASS。初期選択の受け渡し、全解除時のApply無効化、確認解決、移行境界、ダイアログ高さとモーダル状態がすべて成功する。

- [ ] **Step 5: 全XCTestを実行する**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test
```

Expected: 全テストPASS、失敗0。

- [ ] **Step 6: Debug、Staging、Releaseをビルドする**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  build

xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme 'Honkumi Staging' \
  -configuration Staging \
  -destination 'generic/platform=iOS Simulator' \
  build

xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Expected: 3コマンドすべて終了コード0。新しい永続フィールドやinitializer変更による構成別のコンパイルエラーがない。

- [ ] **Step 7: 差分と作業ツリーを確認する**

```bash
git diff --check
git status --short
git diff -- \
  Honkumi/Shared/Models/AppData.swift \
  Honkumi/Shared/Services/UserDefaultSettingsApplication.swift \
  Honkumi/Shared/Services/UserDefaultSettingsReview.swift \
  Honkumi/Shared/Services/DocumentStore.swift \
  Honkumi/Features/Library/CommonSettingsReviewDialog.swift \
  HonkumiTests/CommonSettingsRevisionCodingTests.swift \
  HonkumiTests/UserDefaultSettingsReviewTests.swift \
  HonkumiTests/CommonSettingsReviewPresentationTests.swift
```

Expected: 空白エラーなし。表示される実装差分は承認済み設計の対象だけで、既存の無関係な変更はそのまま未ステージで残る。

- [ ] **Step 8: Task 3のファイルだけをコミットする**

```bash
git add \
  Honkumi/Features/Library/CommonSettingsReviewDialog.swift \
  HonkumiTests/CommonSettingsReviewPresentationTests.swift
git diff --cached --check
git commit -m "Initialize common settings dialog from differences"
```

Expected: 2ファイルだけがコミットされる。最終コミット後も利用者の既存変更は失われない。
