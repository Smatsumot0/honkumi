# Preview Settings and Paper Options Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 設定画面を開いている間のプレビュー再生成を停止し、閉じた時に最新状態を一度だけ生成する。同時にA5/B5の新規選択廃止と、推奨設定解除時の表示値引継ぎを実装する。

**Architecture:** `PreviewViewModel`へ生成停止境界を追加し、`ContentView`が設定sheetの表示状態を伝える。PDF生成サービスはprotocol注入してテスト可能にする。用紙enumと既存描画互換は残したままPicker用配列だけを縮小し、既存A5/B5は現在値専用行で表示する。推奨設定解除は、フラグを落とす直前の`printSettingsForDisplay`を無条件に手動欄へコピーする。

**Tech Stack:** Swift 5、SwiftUI、Combine、XCTest、XcodeBuild

## Global Constraints

- Depends on no other implementation plan.
- A5/B5のenum、Codable、寸法、描画処理を削除しない。
- 設定値の保存は従来どおり即時に行い、停止対象はプレビューPDF生成だけにする。
- 設定sheetが閉じた時にプレビューが非表示なら生成しない。
- キャンセルはユーザー向けエラーへ変換しない。
- 既存の未コミット変更を上書きせず、差分を確認しながら編集する。

---

## Task 1: プレビューPDF生成をprotocolで注入可能にする

**Files:**

- Create: `Honkumi/Shared/Services/PreviewPDFExporting.swift`
- Modify: `Honkumi/Features/Preview/PreviewViewModel.swift`
- Create: `HonkumiTests/PreviewViewModelSuspensionTests.swift`

**Produces:**

- `PreviewPDFExporting`
- `PreviewViewModel.init(documentStore:pdfExporter:)`

### Steps

- [ ] 1. `PreviewViewModelSuspensionTests.swift`へ、呼び出し回数を記録して一時PDF URLを返すfakeを先に記述する。

```swift
@MainActor
private final class FakePreviewPDFExporter: PreviewPDFExporting {
    private(set) var snapshots: [(UUID, PreviewPDFKind)] = []

    func exportPreviewPDF(
        document: ManuscriptDocument,
        subscriptionStatus: SubscriptionStatus,
        previewKind: PreviewPDFKind,
        generationID: UUID
    ) async throws -> URL {
        snapshots.append((document.id, previewKind))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(generationID.uuidString).pdf")
        try Data("%PDF-1.4\n".utf8).write(to: url)
        return url
    }
}
```

- [ ] 2. `PreviewViewModel(documentStore:pdfExporter:)`を使う最小テストを追加し、未定義protocol/initで失敗することを確認する。

```swift
@MainActor
func testInjectedExporterBuildsPreview() async throws {
    let (store, cleanup) = makeIsolatedDocumentStore()
    defer { cleanup() }
    let exporter = FakePreviewPDFExporter()
    let viewModel = PreviewViewModel(documentStore: store, pdfExporter: exporter)

    viewModel.setPreviewActive(true, kind: .normal)
    await waitUntil { exporter.snapshots.count == 1 }

    XCTAssertEqual(exporter.snapshots.count, 1)
}
```

- [ ] 3. 対象テストを実行し、`Cannot find type 'PreviewPDFExporting'`またはinitializer不一致で失敗することを確認する。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test -only-testing:HonkumiTests/PreviewViewModelSuspensionTests
```

- [ ] 4. protocolと実サービス適合を追加する。

```swift
import Foundation

@MainActor
protocol PreviewPDFExporting {
    func exportPreviewPDF(
        document: ManuscriptDocument,
        subscriptionStatus: SubscriptionStatus,
        previewKind: PreviewPDFKind,
        generationID: UUID
    ) async throws -> URL
}

extension PDFExportService: PreviewPDFExporting {}
```

- [ ] 5. `PreviewViewModel`の固定生成器を注入へ変更する。

```swift
private let pdfExporter: PreviewPDFExporting

init(
    documentStore: DocumentStore,
    pdfExporter: PreviewPDFExporting = PDFExportService()
) {
    self.documentStore = documentStore
    self.pdfExporter = pdfExporter
    // existing publisher setup
}
```

- [ ] 6. 既存の`pdfExportService.exportPreviewPDF`呼び出しを`pdfExporter.exportPreviewPDF`へ置換し、テストを成功させる。

- [ ] 7. コミットする。

```bash
git add Honkumi/Shared/Services/PreviewPDFExporting.swift \
  Honkumi/Features/Preview/PreviewViewModel.swift \
  HonkumiTests/PreviewViewModelSuspensionTests.swift
git commit -m "Inject preview PDF generation"
```

---

## Task 2: 設定表示中の生成を停止し、閉じた時に一度だけ再開する

**Files:**

- Modify: `Honkumi/Features/Preview/PreviewViewModel.swift`
- Modify: `HonkumiTests/PreviewViewModelSuspensionTests.swift`

**Consumes:**

- Task 1の`PreviewPDFExporting`

**Produces:**

- `PreviewViewModel.setGenerationSuspended(_:)`

### Steps

- [ ] 1. 次の4テストを先に追加する。

```swift
func testSuspensionCancelsInFlightGeneration()
func testMultipleDocumentChangesWhileSuspendedDoNotGenerate()
func testResumeGeneratesLatestSnapshotExactlyOnce()
func testResumeWhilePreviewInactiveDoesNotGenerate()
```

Fake exporterへ`CheckedContinuation`を持つ保留モードと`withTaskCancellationHandler`を追加し、最初のテストでは`setGenerationSuspended(true)`後にキャンセルを観測する。残りのテストは次の順序を明示する。

```swift
viewModel.setPreviewActive(true, kind: .normal)
await waitUntil { exporter.callCount == 1 }
viewModel.setGenerationSuspended(true)

store.updateSettings(firstSettings)
store.updateSettings(secondSettings)
await Task.yield()
XCTAssertEqual(exporter.callCount, 1)

viewModel.setGenerationSuspended(false)
await waitUntil { exporter.callCount == 2 }
XCTAssertEqual(exporter.documents.last?.settings, secondSettings.validated)
```

- [ ] 2. テストを実行し、`setGenerationSuspended`未定義で失敗することを確認する。

- [ ] 3. `PreviewViewModel`へ状態を追加する。

```swift
private var isGenerationSuspended = false

func setGenerationSuspended(_ isSuspended: Bool) {
    guard isGenerationSuspended != isSuspended else { return }
    isGenerationSuspended = isSuspended

    if isSuspended {
        generationTask?.cancel()
        generationTask = nil
        return
    }

    guard isPreviewActive else { return }
    preparePreviewIfNeeded()
}
```

実際のプロパティ名が`pdfGenerationTask`等の場合は既存名を使う。

- [ ] 4. `$document`と`$appData`の各sink、`preparePreviewIfNeeded()`、debounce後の生成開始点へ`!isGenerationSuspended`のガードを入れる。停止中も最新値は`documentStore`から再開時に読むため、独自の中間スナップショットを蓄積しない。

- [ ] 5. 生成開始直前にも再度停止状態を確認し、設定sheet表示とdebounce発火の競合でPDFを開始しないようにする。

- [ ] 6. `CancellationError`は既存プレビューと同様にエラー表示へ入れないことをテストする。

- [ ] 7. 対象テストを実行する。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test -only-testing:HonkumiTests/PreviewViewModelSuspensionTests
```

Expected: 5 tests pass.

- [ ] 8. コミットする。

```bash
git add Honkumi/Features/Preview/PreviewViewModel.swift \
  HonkumiTests/PreviewViewModelSuspensionTests.swift
git commit -m "Suspend preview generation while settings are open"
```

---

## Task 3: 設定sheetの表示状態をPreviewViewModelへ接続する

**Files:**

- Modify: `Honkumi/ContentView.swift`

**Consumes:**

- Task 2の`setGenerationSuspended(_:)`

### Steps

- [ ] 1. `WorkspaceView`で`presentedSettingsScope`の変化を監視し、sheet表示中だけ停止する。

```swift
.onChange(of: presentedSettingsScope) { _, scope in
    previewViewModel.setGenerationSuspended(scope != nil)
}
```

- [ ] 2. `WorkspaceView.onAppear`または既存初期化経路でも現在値を一度同期し、画面復帰直後にsheetが既に表示されている場合の抜けを防ぐ。

```swift
.onAppear {
    previewViewModel.setGenerationSuspended(presentedSettingsScope != nil)
    // existing onAppear work
}
```

- [ ] 3. rootの`.sheet(item:)`や設定保存処理自体は変更しない。sheetを閉じるBinding更新だけで`false`が伝わることを確認する。

- [ ] 4. ビルドする。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi -configuration Debug \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' build
```

- [ ] 5. コミットする。

```bash
git add Honkumi/ContentView.swift
git commit -m "Connect settings presentation to preview suspension"
```

---

## Task 4: A5/B5を新規選択肢から外し、既存値を保持する

**Files:**

- Modify: `Honkumi/Shared/Constants/PageSize.swift`
- Modify: `Honkumi/Features/Settings/SettingsView.swift`
- Modify: `HonkumiTests/RecommendedPrintSettingsTests.swift`
- Create: `HonkumiTests/PageSizeCompatibilityTests.swift`

**Produces:**

- `PageSize.selectableCases == [.a6, .shinsho, .b6]`
- `PageSize.isLegacySelection`
- Pickerの「既存データ」行

### Steps

- [ ] 1. 次の失敗テストを追加する。

```swift
final class PageSizeCompatibilityTests: XCTestCase {
    func testOnlySupportedPaperSizesAreSelectable() {
        XCTAssertEqual(PageSize.selectableCases, [.a6, .shinsho, .b6])
    }

    func testLegacyA5AndB5StillDecode() throws {
        XCTAssertEqual(
            try JSONDecoder().decode(PageSize.self, from: Data("\"A5\"".utf8)),
            .a5
        )
        XCTAssertEqual(
            try JSONDecoder().decode(PageSize.self, from: Data("\"B5\"".utf8)),
            .b5
        )
    }

    func testLegacySizesRetainDimensions() {
        XCTAssertEqual(PageSize.a5.widthMillimeters, 148)
        XCTAssertEqual(PageSize.b5.heightMillimeters, 257)
    }
}
```

`RecommendedPrintSettingsTests`にはA5/B5で`supportsRecommendations`がfalseの既存または追加テストを置く。

- [ ] 2. テストを実行し、選択肢配列の不一致で失敗することを確認する。

- [ ] 3. `PageSize`を最小変更する。

```swift
static let selectableCases: [PageSize] = [.a6, .shinsho, .b6]

var isLegacySelection: Bool {
    !Self.selectableCases.contains(self)
}
```

enumケース、Codable switch、寸法switchは変更しない。

- [ ] 4. SettingsのサイズPickerへ、現在値がlegacyの場合だけ先頭に現在値専用行を追加する。

```swift
if viewModel.settings.pageSize.isLegacySelection {
    Text("\(viewModel.settings.pageSize.displayName)（既存データ）")
        .tag(viewModel.settings.pageSize)
}
ForEach(PageSize.selectableCases) { pageSize in
    Text(pageSize.displayName).tag(pageSize)
}
```

Pickerのtagは現在値を表示するためだけに存在する。A6等へ変更するとView再評価でlegacy行が消え、A5/B5へ戻せない。

- [ ] 5. 対象テストを実行する。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test -only-testing:HonkumiTests/PageSizeCompatibilityTests \
  -only-testing:HonkumiTests/RecommendedPrintSettingsTests
```

- [ ] 6. コミットする。

```bash
git add Honkumi/Shared/Constants/PageSize.swift \
  Honkumi/Features/Settings/SettingsView.swift \
  HonkumiTests/PageSizeCompatibilityTests.swift \
  HonkumiTests/RecommendedPrintSettingsTests.swift
git commit -m "Keep legacy paper sizes read only"
```

---

## Task 5: 推奨設定解除時に表示中の推奨値を常に引き継ぐ

**Files:**

- Modify: `Honkumi/Features/Settings/SettingsViewModel.swift`
- Create: `HonkumiTests/SettingsRecommendationTransitionTests.swift`

### Steps

- [ ] 1. 非初期値の古い手動値を設定した状態で、推奨組版をon→offにした時の失敗テストを追加する。

```swift
@MainActor
func testTurningOffRecommendedTypographyCopiesDisplayedValuesOverNonDefaultManualValues() {
    var document = ManuscriptDocument(title: "Typography", body: longBody)
    document.settings.pageSize = .a6
    document.settings.useRecommendedTypography = true
    document.settings.fontSize = 19
    document.settings.charactersPerLine = 11
    document.settings.linesPerPage = 12
    let store = makeStore(document: document)
    let viewModel = SettingsViewModel(documentStore: store)
    let displayed = viewModel.printSettingsForDisplay

    viewModel.updateUseRecommendedTypography(false)

    XCTAssertFalse(viewModel.settings.useRecommendedTypography)
    XCTAssertEqual(viewModel.settings.fontSize, displayed.fontSize)
    XCTAssertEqual(viewModel.settings.charactersPerLine, displayed.charactersPerLine)
    XCTAssertEqual(viewModel.settings.linesPerPage, displayed.linesPerPage)
}
```

- [ ] 2. 同様に余白4項目を非初期値から上書きするテストを追加する。

- [ ] 3. A5/B5では推奨値をコピーせずフラグだけoffになるテストを、組版と余白それぞれ追加する。

- [ ] 4. テストを実行し、現在の`hasDefaultManual...`条件により非初期値テストが失敗することを確認する。

- [ ] 5. `printSettingsForDisplay`をフラグ変更前に取得し、利用可能な推奨設定でon→offの場合は無条件にコピーする。

```swift
func updateUseRecommendedTypography(_ value: Bool) {
    let displayed = printSettingsForDisplay
    var updated = settings
    if updated.useRecommendedTypography,
       !value,
       isPrintRecommendationAvailable {
        updated = Self.copyManualTypographyFields(from: displayed, to: updated)
    }
    updated.useRecommendedTypography = value
    settings = updated
}
```

余白も同じ構造にする。`hasDefaultManualTypographyFields`と`hasDefaultManualMarginFields`は呼び出しがなくなるため削除する。

- [ ] 6. on→on、off→off、off→onでは手動値をコピーしない回帰テストを追加する。

- [ ] 7. 対象テストを実行する。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test -only-testing:HonkumiTests/SettingsRecommendationTransitionTests
```

- [ ] 8. コミットする。

```bash
git add Honkumi/Features/Settings/SettingsViewModel.swift \
  HonkumiTests/SettingsRecommendationTransitionTests.swift
git commit -m "Carry recommended values into manual settings"
```

---

## Task 6: 統合確認

**Files:**

- No source changes expected

### Steps

- [ ] 1. プレビューを表示し、設定sheetで複数項目を連続変更する。変更中にプレビューのローディング表示やPDF差替えが繰り返されず、閉じた後に一度だけ最新結果へ変わることを確認する。

- [ ] 2. 設定中にプレビュー画面自体を閉じたケースを確認し、設定sheet終了だけでは生成されず、次回プレビュー表示時に生成されることを確認する。

- [ ] 3. 保存済みA5/B5データを開き、「A5（既存データ）」または「B5（既存データ）」が表示されること、A6へ変更後にA5/B5が候補へ出ないことを確認する。

- [ ] 4. 推奨設定をonにして表示値を記録し、off後の各入力値が同じであることを確認する。

- [ ] 5. 対象テストとDebugビルドをまとめて実行する。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test -only-testing:HonkumiTests/PreviewViewModelSuspensionTests \
  -only-testing:HonkumiTests/PageSizeCompatibilityTests \
  -only-testing:HonkumiTests/SettingsRecommendationTransitionTests \
  -only-testing:HonkumiTests/RecommendedPrintSettingsTests
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi -configuration Debug \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' build
```

## Completion Evidence

- 設定中は0回、閉じた後は最新状態で1回というfake exporterの記録がある。
- A5/B5はdecode・寸法を維持し、Picker通常候補は3種だけである。
- 推奨設定解除時に、以前の手動値に関係なく表示中の値が引き継がれる。
