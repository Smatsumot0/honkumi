# サークルロゴ・奥付不具合修正 実装計画

> **エージェント作業者向け:** 必須サブスキルとして`superpowers:subagent-driven-development`（推奨）または`superpowers:executing-plans`を使用し、この計画をタスク単位で実行する。各手順はチェックボックス（`- [ ]`）で進捗を管理する。

**目的:** SVGアップロード、サークルロゴ使用時の作者・サークル非表示、共通設定の選択適用、作品固有奥付の保持、QRコードとURLの配置を修正する。

**構成:** 共通設定の4分類を値型として定義し、作品設定への適用処理をUIから分離する。SVG寸法解析、奥付項目生成、QR座標計算も独立してテスト可能な境界に置き、SwiftUI画面とPDF描画はそれらの結果だけを使用する。

**技術:** Swift 6、SwiftUI、UIKit、WebKit、Core Graphics、XCTest、Xcode 26.5

## 全体制約

- 設計書は`docs/superpowers/specs/2026-07-30-circle-logo-colophon-regression-design.md`を正とする。
- SVG変換はアップロード時に1回だけ実行し、プレビュー・PDF生成時にSVG処理を追加しない。
- 提供された`logo.svg`と`title.svg`の`width="100%" height="100%"`を有効な`viewBox`へフォールバックさせる。
- サークルロゴ使用中も作者名・サークル名・表示フラグの保存値を削除しない。
- 共通設定ダイアログは「エディタ設定」「サークル設定」「フォーマット設定」「印刷設定」を毎回すべてチェック済みで開く。
- 全分類が未選択の場合は「適用して開く」を無効にする。
- 「適用せず開く」は設定を保持して確認済みにし、「キャンセル」は確認済みリビジョンも選択作品も変更しない。
- 印刷設定・サークル設定を適用しても、作品固有の奥付オン／オフ、発行日、印刷所は保持する。
- フォーマット設定を選択し、適用後の自動フォーマットが有効な場合だけ、作品を開くときにフォーマットする。
- 既存の未追跡ファイルおよび今回と無関係な削除状態には触れない。

---

## 実行前準備

- [ ] **手順1: 隔離ワークツリーを作成する**

`superpowers:using-git-worktrees`を読み、現在の`codex/print-preview-colophon-fixes`から次を作成する。

```bash
git worktree add .worktrees/circle-logo-colophon-regressions -b codex/circle-logo-colophon-regressions
```

以後のすべてのコマンドは`.worktrees/circle-logo-colophon-regressions`で実行する。

- [ ] **手順2: 基準テストを実行する**

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test
```

期待結果: 既存テストがすべて成功する。失敗した場合は実装せず、基準状態の問題として調査する。

---

### タスク1: 共通設定の4分類と選択適用

**ファイル:**

- 変更: `Honkumi/Shared/Services/UserDefaultSettingsReview.swift`
- 新規: `Honkumi/Shared/Services/UserDefaultSettingsApplication.swift`
- 変更: `Honkumi/Shared/Services/DocumentStore.swift`
- 変更: `HonkumiTests/UserDefaultSettingsReviewTests.swift`

**インターフェース:**

- 入力: 現在の`EditorSettings`、共通`EditorSettings`、`UserDefaultSettingsSelection`
- 出力: `EditorSettings.applyingUserDefaults(_:selection:) -> EditorSettings`
- 出力: `UserDefaultSettingsReviewDecision.apply(UserDefaultSettingsSelection)`

- [ ] **手順1: 4分類の失敗テストを書く**

`HonkumiTests/UserDefaultSettingsReviewTests.swift`へ、各分類を単独で適用する4テストと、全解除を拒否するテストを追加する。各テストでは分類ごとに異なる値を設定し、選択分類だけが変わることを比較する。

```swift
func testEditorSelectionChangesOnlyEditorSettings() throws {
    let store = makeStore(commonRevision: 3, reviewedRevision: 1)
    let before = store.document.settings
    var defaults = store.userDefaultSettings
    defaults.editorFontId = "NotoSansJP-Regular"
    defaults.editorFontSize = 18
    defaults.pageSize = .b6
    defaults.formatSettings.enableAutoFormat = true
    defaults.colophon.authorName = "共通作者"
    store.updateUserDefaultSettings(defaults)
    let request = try XCTUnwrap(
        store.userDefaultSettingsReviewRequest(for: store.document.id)
    )

    let result = store.resolveUserDefaultSettingsReview(
        request,
        decision: .apply(
            UserDefaultSettingsSelection(editor: true)
        )
    )

    XCTAssertTrue(result.didSelect)
    XCTAssertFalse(result.shouldFormat)
    XCTAssertEqual(store.document.settings.editorFontId, defaults.validated.editorFontId)
    XCTAssertEqual(store.document.settings.editorFontSize, 18)
    XCTAssertEqual(store.document.settings.pageSize, before.pageSize)
    XCTAssertEqual(store.document.settings.formatSettings, before.formatSettings)
    XCTAssertEqual(store.document.settings.colophon, before.colophon)
}
```

```swift
func testCircleSelectionChangesOnlyPublisherInformation() throws {
    let store = makeStore(commonRevision: 3, reviewedRevision: 1)
    var workSettings = store.document.settings
    workSettings.colophon.isEnabled = true
    workSettings.colophon.publicationDate = Date(timeIntervalSince1970: 1_700_000_000)
    workSettings.colophon.printerName = "作品の印刷所"
    store.updateSettings(workSettings)
    let before = store.document.settings

    var defaults = store.userDefaultSettings
    defaults.colophon.publisherName = "共通発行者"
    defaults.colophon.authorName = "共通作者"
    defaults.colophon.circleName = "共通サークル"
    defaults.colophon.circleImageData = Data([0x01])
    defaults.colophon.usesCircleImageForCreator = true
    defaults.colophon.websiteURL = "https://example.com"
    defaults.colophon.isEnabled = false
    defaults.colophon.publicationDate = nil
    defaults.colophon.printerName = "共通の印刷所"
    defaults.pageSize = .b6
    defaults.editorFontSize = 18
    defaults.formatSettings.enableAutoFormat = true
    store.updateUserDefaultSettings(defaults)
    let request = try XCTUnwrap(
        store.userDefaultSettingsReviewRequest(for: store.document.id)
    )

    let result = store.resolveUserDefaultSettingsReview(
        request,
        decision: .apply(
            UserDefaultSettingsSelection(circle: true)
        )
    )

    XCTAssertTrue(result.didSelect)
    XCTAssertFalse(result.shouldFormat)
    XCTAssertEqual(
        store.document.settings.colophon,
        before.colophon.applyingPublisherInfo(from: defaults.colophon)
    )
    XCTAssertTrue(store.document.settings.colophon.isEnabled)
    XCTAssertEqual(
        store.document.settings.colophon.publicationDate,
        before.colophon.publicationDate
    )
    XCTAssertEqual(
        store.document.settings.colophon.printerName,
        "作品の印刷所"
    )
    XCTAssertEqual(store.document.settings.pageSize, before.pageSize)
    XCTAssertEqual(
        store.document.settings.editorFontSize,
        before.editorFontSize
    )
    XCTAssertEqual(
        store.document.settings.formatSettings,
        before.formatSettings
    )
}

func testFormatSelectionChangesOnlyFormatSettingsAndRequestsFormatting()
throws {
    let store = makeStore(commonRevision: 3, reviewedRevision: 1)
    let before = store.document.settings
    var defaults = store.userDefaultSettings
    defaults.formatSettings.enableAutoFormat = true
    defaults.formatSettings.enableNormalizePunctuation = true
    defaults.pageSize = .b6
    defaults.editorFontSize = 18
    defaults.colophon.authorName = "共通作者"
    store.updateUserDefaultSettings(defaults)
    let request = try XCTUnwrap(
        store.userDefaultSettingsReviewRequest(for: store.document.id)
    )

    let result = store.resolveUserDefaultSettingsReview(
        request,
        decision: .apply(
            UserDefaultSettingsSelection(format: true)
        )
    )

    XCTAssertTrue(result.didSelect)
    XCTAssertTrue(result.shouldFormat)
    XCTAssertEqual(
        store.document.settings.formatSettings,
        defaults.validated.formatSettings
    )
    XCTAssertEqual(store.document.settings.pageSize, before.pageSize)
    XCTAssertEqual(
        store.document.settings.editorFontSize,
        before.editorFontSize
    )
    XCTAssertEqual(store.document.settings.colophon, before.colophon)
}

func testFormatSelectionDoesNotRequestFormattingWhenAutoFormatIsOff()
throws {
    let store = makeStore(commonRevision: 3, reviewedRevision: 1)
    var defaults = store.userDefaultSettings
    defaults.formatSettings.enableAutoFormat = false
    defaults.formatSettings.enableNormalizePunctuation = true
    store.updateUserDefaultSettings(defaults)
    let request = try XCTUnwrap(
        store.userDefaultSettingsReviewRequest(for: store.document.id)
    )

    let result = store.resolveUserDefaultSettingsReview(
        request,
        decision: .apply(
            UserDefaultSettingsSelection(format: true)
        )
    )

    XCTAssertTrue(result.didSelect)
    XCTAssertFalse(result.shouldFormat)
    XCTAssertEqual(
        store.document.settings.formatSettings,
        defaults.validated.formatSettings
    )
}

func testPrintSelectionChangesOnlyPrintSettingsAndPreservesWorkColophon()
throws {
    let store = makeStore(commonRevision: 3, reviewedRevision: 1)
    var workSettings = store.document.settings
    workSettings.colophon.isEnabled = true
    workSettings.colophon.publicationDate = Date(timeIntervalSince1970: 1_700_000_000)
    workSettings.colophon.showsPublicationDate = true
    workSettings.colophon.printerName = "作品の印刷所"
    workSettings.colophon.showsPrinterName = true
    store.updateSettings(workSettings)
    let before = store.document.settings

    var defaults = store.userDefaultSettings
    defaults.pageSize = .b6
    defaults.marginInner = 24
    defaults.showTableOfContents = true
    defaults.colophon.isEnabled = false
    defaults.colophon.publicationDate = nil
    defaults.colophon.showsPublicationDate = false
    defaults.colophon.printerName = "共通の印刷所"
    defaults.colophon.showsPrinterName = false
    defaults.editorFontSize = 18
    defaults.formatSettings.enableAutoFormat = true
    store.updateUserDefaultSettings(defaults)
    let request = try XCTUnwrap(
        store.userDefaultSettingsReviewRequest(for: store.document.id)
    )

    let result = store.resolveUserDefaultSettingsReview(
        request,
        decision: .apply(
            UserDefaultSettingsSelection(print: true)
        )
    )

    XCTAssertTrue(result.didSelect)
    XCTAssertFalse(result.shouldFormat)
    XCTAssertEqual(store.document.settings.pageSize, .b6)
    XCTAssertEqual(store.document.settings.marginInner, 24)
    XCTAssertTrue(store.document.settings.showTableOfContents)
    XCTAssertEqual(store.document.settings.colophon, before.colophon)
    XCTAssertEqual(
        store.document.settings.editorFontSize,
        before.editorFontSize
    )
    XCTAssertEqual(
        store.document.settings.formatSettings,
        before.formatSettings
    )
}

func testEmptySelectionDoesNotApplySelectOrReview() throws {
    let store = makeStore(commonRevision: 3, reviewedRevision: 1)
    let request = try XCTUnwrap(
        store.userDefaultSettingsReviewRequest(for: store.document.id)
    )
    let before = store.appData

    let result = store.resolveUserDefaultSettingsReview(
        request,
        decision: .apply(UserDefaultSettingsSelection())
    )

    XCTAssertEqual(result, .unchanged)
    XCTAssertEqual(store.appData, before)
}

func testCombinedSelectionAppliesOnlySelectedGroups() throws {
    let store = makeStore(commonRevision: 3, reviewedRevision: 1)
    let before = store.document.settings
    var defaults = store.userDefaultSettings
    defaults.editorFontSize = 18
    defaults.colophon.authorName = "共通作者"
    defaults.pageSize = .b6
    defaults.formatSettings.enableAutoFormat = true
    store.updateUserDefaultSettings(defaults)
    let request = try XCTUnwrap(
        store.userDefaultSettingsReviewRequest(for: store.document.id)
    )

    let result = store.resolveUserDefaultSettingsReview(
        request,
        decision: .apply(
            UserDefaultSettingsSelection(editor: true, circle: true)
        )
    )

    XCTAssertTrue(result.didSelect)
    XCTAssertFalse(result.shouldFormat)
    XCTAssertEqual(store.document.settings.editorFontSize, 18)
    XCTAssertEqual(
        store.document.settings.colophon.authorName,
        "共通作者"
    )
    XCTAssertEqual(store.document.settings.pageSize, before.pageSize)
    XCTAssertEqual(
        store.document.settings.formatSettings,
        before.formatSettings
    )
}
```

既存の`testApplyCopiesEverySettingsGroupAndRequestsFormatting`は次へ
置き換え、全選択でも作品固有奥付だけは保持されることを固定する。

```swift
func testApplyAllCopiesEveryGroupExceptWorkSpecificColophon()
throws {
    let store = makeStore(commonRevision: 3, reviewedRevision: 1)
    var workSettings = store.document.settings
    workSettings.colophon.isEnabled = true
    workSettings.colophon.publicationDate =
        Date(timeIntervalSince1970: 1_700_000_000)
    workSettings.colophon.showsPublicationDate = true
    workSettings.colophon.printerName = "作品の印刷所"
    workSettings.colophon.showsPrinterName = true
    store.updateSettings(workSettings)
    let before = store.document.settings

    var defaults = store.userDefaultSettings
    defaults.editorFontSize = 18
    defaults.pageSize = .b6
    defaults.marginInner = 24
    defaults.formatSettings.enableAutoFormat = true
    defaults.formatSettings.enableNormalizePunctuation = true
    defaults.colophon.authorName = "共通作者"
    defaults.colophon.isEnabled = false
    defaults.colophon.publicationDate = nil
    defaults.colophon.showsPublicationDate = false
    defaults.colophon.printerName = "共通の印刷所"
    defaults.colophon.showsPrinterName = false
    store.updateUserDefaultSettings(defaults)
    let request = try XCTUnwrap(
        store.userDefaultSettingsReviewRequest(for: store.document.id)
    )

    let result = store.resolveUserDefaultSettingsReview(
        request,
        decision: .apply(.all)
    )

    XCTAssertTrue(result.didSelect)
    XCTAssertTrue(result.shouldFormat)
    XCTAssertEqual(
        store.document.settings,
        before.applyingUserDefaults(defaults, selection: .all)
    )
    XCTAssertTrue(store.document.settings.colophon.isEnabled)
    XCTAssertEqual(
        store.document.settings.colophon.publicationDate,
        before.colophon.publicationDate
    )
    XCTAssertTrue(
        store.document.settings.colophon.showsPublicationDate
    )
    XCTAssertEqual(
        store.document.settings.colophon.printerName,
        "作品の印刷所"
    )
    XCTAssertTrue(store.document.settings.colophon.showsPrinterName)
    XCTAssertEqual(
        store.document.reviewedUserDefaultSettingsRevision,
        3
    )
}
```

- [ ] **手順2: 新規テストが意図どおり失敗することを確認する**

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -only-testing:HonkumiTests/UserDefaultSettingsReviewTests \
  test
```

期待結果: `UserDefaultSettingsSelection`または`.apply(selection)`が未定義のためコンパイルに失敗する。

- [ ] **手順3: 選択値型と決定型を実装する**

`Honkumi/Shared/Services/UserDefaultSettingsReview.swift`へ追加する。

```swift
nonisolated struct UserDefaultSettingsSelection: Equatable {
    var editor: Bool
    var circle: Bool
    var format: Bool
    var print: Bool

    init(
        editor: Bool = false,
        circle: Bool = false,
        format: Bool = false,
        print: Bool = false
    ) {
        self.editor = editor
        self.circle = circle
        self.format = format
        self.print = print
    }

    static let all = UserDefaultSettingsSelection(
        editor: true,
        circle: true,
        format: true,
        print: true
    )

    var isEmpty: Bool {
        !editor && !circle && !format && !print
    }
}

nonisolated enum UserDefaultSettingsReviewDecision: Equatable {
    case apply(UserDefaultSettingsSelection)
    case keepCurrent
}
```

- [ ] **手順4: 分類ごとのコピー処理を実装する**

`Honkumi/Shared/Services/UserDefaultSettingsApplication.swift`を作成する。

```swift
import Foundation

nonisolated extension EditorSettings {
    func applyingUserDefaults(
        _ userDefaults: EditorSettings,
        selection: UserDefaultSettingsSelection
    ) -> EditorSettings {
        var applied = validated
        let defaults = userDefaults.validated

        if selection.editor {
            applied.editorFontId = defaults.editorFontId
            applied.editorFontSize = defaults.editorFontSize
        }

        if selection.circle {
            applied.colophon = applied.colophon.applyingPublisherInfo(
                from: defaults.colophon
            )
        }

        if selection.format {
            applied.formatSettings = defaults.formatSettings
        }

        if selection.print {
            applied.pageSize = defaults.pageSize
            applied.selectedFontId = defaults.selectedFontId
            applied.fontSize = defaults.fontSize
            applied.lineSpacing = defaults.lineSpacing
            applied.characterSpacing = defaults.characterSpacing
            applied.charactersPerLine = defaults.charactersPerLine
            applied.linesPerPage = defaults.linesPerPage
            applied.marginTop = defaults.marginTop
            applied.marginBottom = defaults.marginBottom
            applied.marginInner = defaults.marginInner
            applied.marginOuter = defaults.marginOuter
            applied.isPageNumberEnabled = defaults.isPageNumberEnabled
            applied.pageNumberFontId = defaults.pageNumberFontId
            applied.pageNumberSize = defaults.pageNumberSize
            applied.pageNumberStart = defaults.pageNumberStart
            applied.pageNumberPosition = defaults.pageNumberPosition
            applied.showPageNumberOnToc = defaults.showPageNumberOnToc
            applied.showPageNumberOnColophon = defaults.showPageNumberOnColophon
            applied.showTableOfContents = defaults.showTableOfContents
            applied.showChapterTitle = defaults.showChapterTitle
            applied.chapterTitleStyle = defaults.chapterTitleStyle
            applied.startsChapterOnNewPage = defaults.startsChapterOnNewPage
            applied.alphanumericOrientation = defaults.alphanumericOrientation
            applied.useRecommendedTypography = defaults.useRecommendedTypography
            applied.useRecommendedMargins = defaults.useRecommendedMargins
            applied.showsCropMarks = defaults.showsCropMarks
        }

        return applied.validated
    }
}
```

- [ ] **手順5: DocumentStoreを選択適用へ変更する**

`resolveUserDefaultSettingsReview`の先頭で空選択を拒否し、`.apply`分岐を次へ変更する。

```swift
if case let .apply(selection) = decision, selection.isEmpty {
    return .unchanged
}
```

```swift
case let .apply(selection):
    data.works[index].settings =
        data.works[index].settings.applyingUserDefaults(
            data.userDefaultSettings,
            selection: selection
        )
    data.works[index].updatedAt = Date()
    result = WorkSelectionResult(
        didSelect: true,
        shouldFormat:
            selection.format
            && data.works[index].settings.formatSettings.enableAutoFormat
    )
```

既存テストの`.apply`は`.apply(.all)`へ変更する。

- [ ] **手順6: 選択適用テストを成功させる**

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -only-testing:HonkumiTests/UserDefaultSettingsReviewTests \
  test
```

期待結果: 追加・既存テストがすべて成功する。

- [ ] **手順7: タスク1をコミットする**

```bash
git add \
  Honkumi/Shared/Services/UserDefaultSettingsReview.swift \
  Honkumi/Shared/Services/UserDefaultSettingsApplication.swift \
  Honkumi/Shared/Services/DocumentStore.swift \
  HonkumiTests/UserDefaultSettingsReviewTests.swift
git commit -m "Apply selected common settings groups"
```

---

### タスク2: チェックボックス付き中央ダイアログ

**ファイル:**

- 新規: `Honkumi/Features/Library/CommonSettingsReviewDialog.swift`
- 変更: `Honkumi/Features/Library/WorkListView.swift`
- 新規: `HonkumiTests/CommonSettingsReviewPresentationTests.swift`

**インターフェース:**

- 入力: `UserDefaultSettingsReviewRequest`
- 出力: `CommonSettingsReviewPresentation(request:selection:)`
- 出力: `CommonSettingsReviewDialog(selection:onApply:onKeepCurrent:onCancel:)`

- [ ] **手順1: ダイアログ状態の失敗テストを書く**

`HonkumiTests/CommonSettingsReviewPresentationTests.swift`を作成する。

```swift
@testable import Honkumi
import PDFKit
import XCTest

final class CommonSettingsReviewPresentationTests: XCTestCase {
    func testNewPresentationSelectsEveryGroup() {
        let request = UserDefaultSettingsReviewRequest(
            workID: UUID(),
            revision: 4
        )

        let presentation = CommonSettingsReviewPresentation(
            request: request
        )

        XCTAssertEqual(presentation.selection, .all)
        XCTAssertTrue(presentation.canApply)
    }

    func testApplyIsDisabledWhenEveryGroupIsOff() {
        var presentation = CommonSettingsReviewPresentation(
            request: UserDefaultSettingsReviewRequest(
                workID: UUID(),
                revision: 4
            )
        )

        presentation.selection = UserDefaultSettingsSelection()

        XCTAssertFalse(presentation.canApply)
    }
}
```

- [ ] **手順2: 新規テストが未定義型で失敗することを確認する**

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -only-testing:HonkumiTests/CommonSettingsReviewPresentationTests \
  test
```

期待結果: `CommonSettingsReviewPresentation`が未定義で失敗する。

- [ ] **手順3: 状態型と表示文言を実装する**

`Honkumi/Features/Library/CommonSettingsReviewDialog.swift`へ定義する。

```swift
import SwiftUI

nonisolated enum CommonSettingsReviewCopy {
    static let title = "共通設定が変更されています"
    static let message = "この作品に適用する設定を選択してください。"
    static let editor = "エディタ設定"
    static let circle = "サークル設定"
    static let format = "フォーマット設定"
    static let print = "印刷設定"
    static let apply = "適用して開く"
    static let keepCurrent = "適用せず開く"
    static let cancel = "キャンセル"
}

nonisolated struct CommonSettingsReviewPresentation:
    Identifiable,
    Equatable {
    let request: UserDefaultSettingsReviewRequest
    var selection: UserDefaultSettingsSelection = .all

    var id: UUID { request.workID }
    var canApply: Bool { !selection.isEmpty }
}
```

- [ ] **手順4: 中央ダイアログViewを実装する**

同じファイルへ`CommonSettingsReviewDialog`を追加する。4行は`Button`と`checkmark.square.fill`／`square`で表示し、行全体をタップ可能にする。

```swift
struct CommonSettingsReviewDialog: View {
    @Binding var selection: UserDefaultSettingsSelection
    let onApply: () -> Void
    let onKeepCurrent: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(CommonSettingsReviewCopy.title)
                .font(.headline)
            Text(CommonSettingsReviewCopy.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            selectionRow(
                CommonSettingsReviewCopy.editor,
                isOn: binding(\.editor)
            )
            selectionRow(
                CommonSettingsReviewCopy.circle,
                isOn: binding(\.circle)
            )
            selectionRow(
                CommonSettingsReviewCopy.format,
                isOn: binding(\.format)
            )
            selectionRow(
                CommonSettingsReviewCopy.print,
                isOn: binding(\.print)
            )

            Button(CommonSettingsReviewCopy.apply, action: onApply)
                .buttonStyle(.borderedProminent)
                .disabled(selection.isEmpty)
                .frame(maxWidth: .infinity)

            Button(CommonSettingsReviewCopy.keepCurrent, action: onKeepCurrent)
                .frame(maxWidth: .infinity)

            Button(
                CommonSettingsReviewCopy.cancel,
                role: .cancel,
                action: onCancel
            )
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 24, y: 8)
    }
}
```

同じViewへ、行全体の操作と選択値へのBindingを追加する。

```swift
private func selectionRow(
    _ title: String,
    isOn: Binding<Bool>
) -> some View {
    Button {
        isOn.wrappedValue.toggle()
    } label: {
        HStack(spacing: 12) {
            Image(
                systemName: isOn.wrappedValue
                    ? "checkmark.square.fill"
                    : "square"
            )
            .foregroundStyle(
                isOn.wrappedValue ? Color.accentColor : Color.secondary
            )
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
    .accessibilityValue(
        isOn.wrappedValue ? "選択済み" : "未選択"
    )
    .accessibilityAddTraits(.isButton)
}

private func binding(
    _ keyPath: WritableKeyPath<UserDefaultSettingsSelection, Bool>
) -> Binding<Bool> {
    Binding(
        get: { selection[keyPath: keyPath] },
        set: { selection[keyPath: keyPath] = $0 }
    )
}
```

- [ ] **手順5: WorkListViewの標準アラートを置き換える**

状態を次へ変更する。

```swift
@State private var pendingSettingsReview:
    CommonSettingsReviewPresentation?
```

作品選択時は毎回全選択で初期化する。

```swift
pendingSettingsReview = CommonSettingsReviewPresentation(
    request: request
)
```

既存の共通設定`.alert`を削除し、リストへ次の`.overlay`を追加する。

```swift
.overlay {
    if pendingSettingsReview != nil {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}

            CommonSettingsReviewDialog(
                selection: pendingSelectionBinding,
                onApply: applyPendingSettingsReview,
                onKeepCurrent: keepCurrentPendingSettingsReview,
                onCancel: { pendingSettingsReview = nil }
            )
            .padding(24)
        }
        .transition(.opacity)
        .zIndex(10)
    }
}
```

選択Bindingと3つのボタン処理を次のように追加する。キャンセルは
`pendingSettingsReview`だけを破棄するため、設定、確認済みリビジョン、
現在作品を変更しない。

```swift
private var pendingSelectionBinding:
    Binding<UserDefaultSettingsSelection> {
    Binding(
        get: { pendingSettingsReview?.selection ?? .all },
        set: { newSelection in
            pendingSettingsReview?.selection = newSelection
        }
    )
}

private func applyPendingSettingsReview() {
    guard let presentation = pendingSettingsReview,
          presentation.canApply else {
        return
    }
    resolvePendingSettingsReview(
        presentation.request,
        decision: .apply(presentation.selection)
    )
}

private func keepCurrentPendingSettingsReview() {
    guard let presentation = pendingSettingsReview else { return }
    resolvePendingSettingsReview(
        presentation.request,
        decision: .keepCurrent
    )
}

private func resolvePendingSettingsReview(
    _ request: UserDefaultSettingsReviewRequest,
    decision: UserDefaultSettingsReviewDecision
) {
    pendingSettingsReview = nil
    let result = documentStore.resolveUserDefaultSettingsReview(
        request,
        decision: decision
    )
    guard result.didSelect else { return }
    onSelectWork(result.shouldFormat)
}
```

- [ ] **手順6: ダイアログ状態テストと関連テストを成功させる**

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -only-testing:HonkumiTests/CommonSettingsReviewPresentationTests \
  -only-testing:HonkumiTests/UserDefaultSettingsReviewTests \
  test
```

期待結果: 全テスト成功。

- [ ] **手順7: タスク2をコミットする**

```bash
git add \
  Honkumi/Features/Library/CommonSettingsReviewDialog.swift \
  Honkumi/Features/Library/WorkListView.swift \
  HonkumiTests/CommonSettingsReviewPresentationTests.swift
git commit -m "Select common settings before opening works"
```

---

### タスク3: パーセント寸法SVGの読み込み

**ファイル:**

- 変更: `Honkumi/Shared/Services/CircleLogoImageImporter.swift`
- 変更: `HonkumiTests/CircleLogoImageImporterTests.swift`

**インターフェース:**

- 入力: SVGのルート`width`、`height`、`viewBox`
- 出力: 長辺最大2048ピクセルのPNGデータ

- [ ] **手順1: 提供ファイルと同じ寸法指定の失敗テストを書く**

```swift
func testPercentageDimensionsUseSquareViewBox() async throws {
    let data = Data("""
    <svg xmlns="http://www.w3.org/2000/svg"
         width="100%" height="100%" viewBox="0 0 1024 1024">
      <rect width="1024" height="1024" fill="#000"/>
    </svg>
    """.utf8)

    let png = try await CircleLogoImageImporter.importedImageData(
        data,
        contentType: .svg
    )
    let image = try XCTUnwrap(UIImage(data: png)?.cgImage)

    XCTAssertEqual(image.width, 2048)
    XCTAssertEqual(image.height, 2048)
}

func testPercentageDimensionsUseWideViewBox() async throws {
    let data = Data("""
    <svg xmlns="http://www.w3.org/2000/svg"
         width="100%" height="100%" viewBox="0 0 2400 1000">
      <rect width="2400" height="1000" fill="#000"/>
    </svg>
    """.utf8)

    let png = try await CircleLogoImageImporter.importedImageData(
        data,
        contentType: .svg
    )
    let image = try XCTUnwrap(UIImage(data: png)?.cgImage)

    XCTAssertEqual(image.width, 2048)
    XCTAssertEqual(image.height, 853)
}

func testPercentageDimensionsWithoutViewBoxRemainInvalid() async {
    do {
        _ = try await CircleLogoImageImporter.importedImageData(
            Data("""
            <svg xmlns="http://www.w3.org/2000/svg"
                 width="100%" height="100%"></svg>
            """.utf8),
            contentType: .svg
        )
        XCTFail("Expected invalid SVG")
    } catch {
        XCTAssertEqual(error as? CircleLogoImageImportError, .invalidSVG)
    }
}
```

- [ ] **手順2: パーセント指定テストが`invalidSVG`で失敗することを確認する**

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -only-testing:HonkumiTests/CircleLogoImageImporterTests \
  test
```

期待結果: 正方形と横長の2テストが`invalidSVG`で失敗し、`viewBox`なしのテストは成功する。

- [ ] **手順3: ルート寸法を絶対・相対・未指定・不正に分類する**

`CircleLogoSVGSizeParser`へ追加する。

```swift
private enum RootDimension: Equatable {
    case absolute(CGFloat)
    case relative
    case unspecified
    case invalid

    var absoluteValue: CGFloat? {
        guard case let .absolute(value) = self else { return nil }
        return value
    }
}
```

`length(_:)`を次の`rootDimension(_:)`へ置き換える。正の有限数に
`%`が続く場合は`.relative`、対応済み単位は`.absolute`、値なしは
`.unspecified`、それ以外は`.invalid`を返す。

```swift
private static func rootDimension(
    _ value: String?
) -> RootDimension {
    guard let value else { return .unspecified }
    let scanner = Scanner(string: value)
    scanner.locale = Locale(identifier: "en_US_POSIX")
    guard let number = scanner.scanDouble(),
          number.isFinite,
          number > 0 else {
        return .invalid
    }
    let suffix = value[scanner.currentIndex...]
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    if suffix == "%" {
        return .relative
    }

    let multiplier: Double
    switch suffix {
    case "", "px":
        multiplier = 1
    case "pt":
        multiplier = 96 / 72
    case "pc":
        multiplier = 16
    case "in":
        multiplier = 96
    case "cm":
        multiplier = 96 / 2.54
    case "mm":
        multiplier = 96 / 25.4
    case "q":
        multiplier = 96 / 101.6
    default:
        return .invalid
    }

    let result = number * multiplier
    guard result.isFinite, result > 0 else { return .invalid }
    return .absolute(CGFloat(result))
}
```

ルート解析は`.invalid`だけを即時拒否し、`.relative`と`.unspecified`は`viewBox`へフォールバックする。

```swift
let width = Self.rootDimension(attributeDict["width"])
let height = Self.rootDimension(attributeDict["height"])
guard width != .invalid, height != .invalid else { return }

switch (width.absoluteValue, height.absoluteValue, viewBoxSize) {
case let (.some(width), .some(height), _):
    rootSize = CGSize(width: width, height: height)
case let (.some(width), nil, .some(viewBox)):
    rootSize = CGSize(
        width: width,
        height: width * viewBox.height / viewBox.width
    )
case let (nil, .some(height), .some(viewBox)):
    rootSize = CGSize(
        width: height * viewBox.width / viewBox.height,
        height: height
    )
case let (nil, nil, .some(viewBox)):
    rootSize = viewBox
default:
    break
}
```

- [ ] **手順4: SVG単体テストを成功させる**

手順2と同じコマンドを実行する。

期待結果: `CircleLogoImageImporterTests`がすべて成功する。

- [ ] **手順5: タスク3をコミットする**

```bash
git add \
  Honkumi/Shared/Services/CircleLogoImageImporter.swift \
  HonkumiTests/CircleLogoImageImporterTests.swift
git commit -m "Accept percentage-sized SVG logos"
```

---

### タスク4: ロゴ使用中の作者・サークル非表示

**ファイル:**

- 変更: `Honkumi/Features/Settings/CircleLogoImportPresentation.swift`
- 変更: `Honkumi/Features/Settings/ColophonSettingsView.swift`
- 変更: `Honkumi/Features/Preview/PreviewViewModel.swift`
- 変更: `Honkumi/Shared/Services/PDFExportService.swift`
- 変更: `HonkumiTests/CircleLogoImportPresentationTests.swift`
- 新規: `HonkumiTests/ColophonCreatorVisibilityTests.swift`

**インターフェース:**

- 入力: `ColophonSettings.hasCreatorImage`
- 出力: 作者・サークルを除外した`ManuscriptPaginator.colophonEntries(from:)`
- 出力: ロゴだけを描画するPDF作成者ブロック

- [ ] **手順1: 奥付項目の失敗テストを書く**

```swift
@testable import Honkumi
import XCTest

final class ColophonCreatorVisibilityTests: XCTestCase {
    func testActiveLogoOmitsAuthorAndCircleWithoutDeletingValues() {
        var colophon = ColophonSettings.default
        colophon.authorName = "保持する作者"
        colophon.circleName = "保持するサークル"
        colophon.showsAuthorName = true
        colophon.showsCircleName = true
        colophon.usesCircleImageForCreator = true
        colophon.circleImageData = Data([0x01])

        let entries = ManuscriptPaginator.colophonEntries(from: colophon)

        XCTAssertFalse(entries.contains { $0.id == "author" })
        XCTAssertFalse(entries.contains { $0.id == "circle" })
        XCTAssertEqual(colophon.authorName, "保持する作者")
        XCTAssertEqual(colophon.circleName, "保持するサークル")
        XCTAssertTrue(colophon.showsAuthorName)
        XCTAssertTrue(colophon.showsCircleName)
    }

    func testDisablingLogoRestoresAuthorAndCircleEntries() {
        var colophon = ColophonSettings.default
        colophon.authorName = "作者"
        colophon.circleName = "サークル"
        colophon.usesCircleImageForCreator = false
        colophon.circleImageData = Data([0x01])

        let entries = ManuscriptPaginator.colophonEntries(from: colophon)

        XCTAssertTrue(entries.contains { $0.id == "author" })
        XCTAssertTrue(entries.contains { $0.id == "circle" })
    }

    func testExportedPDFDoesNotDrawAuthorOrCircleBesideActiveLogo()
    async throws {
        var document = ManuscriptDocument(title: "ロゴ作品", body: "本文")
        var colophon = document.settings.colophon
        colophon.isEnabled = true
        colophon.authorName = "PDFに出さない作者"
        colophon.circleName = "PDFに出さないサークル"
        colophon.showsAuthorName = true
        colophon.showsCircleName = true
        colophon.usesCircleImageForCreator = true
        colophon.circleImageData = Data(
            base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC"
                + "AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )
        document.settings.colophon = colophon

        let url = try await PDFExportService().export(
            document: document,
            subscriptionStatus: .paid
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        let text = (0..<pdf.pageCount)
            .compactMap { pdf.page(at: $0)?.string }
            .joined(separator: "\n")

        XCTAssertFalse(text.contains("PDFに出さない作者"))
        XCTAssertFalse(text.contains("PDFに出さないサークル"))
    }
}
```

- [ ] **手順2: 作者・サークル項目テストが失敗することを確認する**

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -only-testing:HonkumiTests/ColophonCreatorVisibilityTests \
  test
```

期待結果: ロゴ使用中にも`author`と`circle`が残るため失敗する。

- [ ] **手順3: 奥付項目生成と設定UIをロゴ状態へ連動させる**

`ManuscriptPaginator.colophonEntries(from:)`で、`hasCreatorImage`が`true`の場合は`author`と`circle`を除外する。

```swift
return entries.filter { entry in
    if entry.id == "creator" {
        return colophon.hasCreatorImage
    }
    if colophon.hasCreatorImage,
       entry.id == "author" || entry.id == "circle" {
        return false
    }
    return !entry.value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty
}
```

`ColophonSettingsView.colophonIdentityFields`は作者・サークル部分だけを
次の条件で囲み、保存値を変更しない。`circleLogoControls`は条件の外に
残す。

```swift
private var colophonIdentityFields: some View {
    Group {
        if !viewModel.settings.colophon.hasCreatorImage {
            Toggle(
                "作者名を表示",
                isOn: colophonBinding(\.showsAuthorName)
            )
            if viewModel.settings.colophon.showsAuthorName {
                TextField(
                    "作者名",
                    text: colophonBinding(\.authorName)
                )
            }

            Toggle(
                "サークル名を表示",
                isOn: colophonBinding(\.showsCircleName)
            )
            if viewModel.settings.colophon.showsCircleName {
                TextField(
                    "サークル名",
                    text: colophonBinding(\.circleName)
                )
            }
        }

        circleLogoControls

        Toggle(
            "URLを表示",
            isOn: colophonBinding(\.showsWebsiteURL)
        )
        Toggle(
            "QRコードを表示",
            isOn: colophonBinding(\.showsQRCode)
        )
        TextField("HP", text: colophonBinding(\.websiteURL))
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .disabled(
                !viewModel.settings.colophon.showsWebsiteURL
                && !viewModel.settings.colophon.showsQRCode
            )
        TextField(
            "x（旧Twitter）",
            text: colophonBinding(\.xURL)
        )
        .keyboardType(.URL)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        TextField("pixiv", text: colophonBinding(\.pixivURL))
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        TextField("連絡先", text: colophonBinding(\.contact))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        TextField(
            "その他",
            text: colophonBinding(\.notes),
            axis: .vertical
        )
        .lineLimit(3...6)
    }
}
```

- [ ] **手順4: モノクロ推奨文とロゴ下の作者描画を削除する**

`CircleLogoImportCopy`を次の形にし、
`monochromeRecommendation`を完全に削除する。

```swift
nonisolated enum CircleLogoImportCopy {
    static let sourceTitle = "サークルロゴの選択方法"
    static let sourceMessage = "アップロード元を選択してください。"
    static let uploadButton = "アップロード"
    static let photoSource = "写真から選択"
    static let fileSource = "ファイルから選択"
    static let cancel = "キャンセル"
}
```

`circleLogoImportRow`の有料版側は、アップロードボタンを単独で置き、
推奨文の`Text`を残さない。

```swift
HStack {
    imagePreview(data: imageData)

    Button {
        circleLogoImportPresentation.present(.sourceChooser)
    } label: {
        Label(
            CircleLogoImportCopy.uploadButton,
            systemImage: "photo.on.rectangle"
        )
    }
    .accessibilityIdentifier("colophon.circleLogo.select")

    Spacer()

    if imageData != nil {
        Button(role: .destructive) {
            clearImage(\.circleImageData)
        } label: {
            Image(systemName: "xmark.circle")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("サークルロゴ画像を削除")
    }
}
```

`drawHorizontalCircleLogoCreator`から作者名の描画を削除し、引数も画像描画に
必要なものだけへ絞る。

```swift
@discardableResult
private func drawHorizontalCircleLogoCreator(
    _ colophon: ColophonSettings,
    y: CGFloat,
    in layout: PageLayout
) -> Bool {
    guard let data = colophon.circleImageData,
          let image = UIImage(data: data) else {
        return false
    }

    let height = creatorImageHeight(in: layout)
    let maxImageWidth = layout.bodyFrame.width * 0.36
    let aspect = image.size.width / max(image.size.height, 1)
    let imageSize = CGSize(
        width: min(height * aspect, maxImageWidth),
        height: height
    )
    let x = layout.bodyFrame.midX - imageSize.width / 2
    drawHighQualityImage(
        image,
        in: CGRect(
            x: x,
            y: y,
            width: imageSize.width,
            height: imageSize.height
        )
    )
    return true
}

private func creatorImageBlockHeight(
    in layout: PageLayout
) -> CGFloat {
    creatorImageHeight(in: layout)
}
```

描画側の呼び出しは
`drawHorizontalCircleLogoCreator(colophon, y: cursorY, in: layout)`、
高さ計算側は`creatorImageBlockHeight(in: layout)`へ変更する。

`CircleLogoImportPresentationTests.testApprovedCircleLogoCopy`から
モノクロ推奨文の期待値を削除し、`CircleLogoImportCopy`にその文言が
存在しないことをソースと画面の両方で確認する。

- [ ] **手順5: ロゴ表示関連テストを成功させる**

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -only-testing:HonkumiTests/ColophonCreatorVisibilityTests \
  -only-testing:HonkumiTests/CircleLogoImportPresentationTests \
  test
```

期待結果: 全テスト成功。

- [ ] **手順6: タスク4をコミットする**

```bash
git add \
  Honkumi/Features/Settings/CircleLogoImportPresentation.swift \
  Honkumi/Features/Settings/ColophonSettingsView.swift \
  Honkumi/Features/Preview/PreviewViewModel.swift \
  Honkumi/Shared/Services/PDFExportService.swift \
  HonkumiTests/CircleLogoImportPresentationTests.swift \
  HonkumiTests/ColophonCreatorVisibilityTests.swift
git commit -m "Hide creator text while using a circle logo"
```

---

### タスク5: URL頭揃えとQRコード中央配置

**ファイル:**

- 新規: `Honkumi/Shared/Services/HorizontalColophonHPPlacement.swift`
- 変更: `Honkumi/Shared/Services/PDFExportService.swift`
- 新規: `HonkumiTests/HorizontalColophonHPPlacementTests.swift`

**インターフェース:**

- 入力: `valueX`、値欄幅、URL描画幅、QRサイズ、URL表示有無、本文領域
- 出力: `HorizontalColophonHPPlacement(urlX:qrX:)`

- [ ] **手順1: 座標の失敗テストを書く**

```swift
@testable import Honkumi
import XCTest

final class HorizontalColophonHPPlacementTests: XCTestCase {
    func testVisibleURLStartsAtValueOriginAndCentersQROverURL() {
        let placement = HorizontalColophonHPPlacement.make(
            valueX: 100,
            availableWidth: 220,
            urlWidth: 140,
            qrSize: 44,
            showsURL: true,
            bodyMinX: 20,
            bodyMaxX: 340
        )

        XCTAssertEqual(placement.urlX, 100, accuracy: 0.001)
        XCTAssertEqual(placement.qrX, 148, accuracy: 0.001)
        XCTAssertEqual(placement.qrX + 22, placement.urlX + 70, accuracy: 0.001)
    }

    func testQROnlyCentersInValueColumn() {
        let placement = HorizontalColophonHPPlacement.make(
            valueX: 100,
            availableWidth: 220,
            urlWidth: 0,
            qrSize: 44,
            showsURL: false,
            bodyMinX: 20,
            bodyMaxX: 340
        )

        XCTAssertEqual(placement.urlX, 100, accuracy: 0.001)
        XCTAssertEqual(placement.qrX, 188, accuracy: 0.001)
    }

    func testCenteredQRIsClampedInsideBodyFrame() {
        let placement = HorizontalColophonHPPlacement.make(
            valueX: 30,
            availableWidth: 30,
            urlWidth: 4,
            qrSize: 44,
            showsURL: true,
            bodyMinX: 20,
            bodyMaxX: 340
        )

        XCTAssertEqual(placement.qrX, 20, accuracy: 0.001)
    }
}
```

- [ ] **手順2: 未定義型でテストが失敗することを確認する**

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -only-testing:HonkumiTests/HorizontalColophonHPPlacementTests \
  test
```

期待結果: `HorizontalColophonHPPlacement`が未定義で失敗する。

- [ ] **手順3: 座標ヘルパーを実装する**

`Honkumi/Shared/Services/HorizontalColophonHPPlacement.swift`を作成する。

```swift
import CoreGraphics

nonisolated struct HorizontalColophonHPPlacement: Equatable {
    let urlX: CGFloat
    let qrX: CGFloat

    static func make(
        valueX: CGFloat,
        availableWidth: CGFloat,
        urlWidth: CGFloat,
        qrSize: CGFloat,
        showsURL: Bool,
        bodyMinX: CGFloat,
        bodyMaxX: CGFloat
    ) -> HorizontalColophonHPPlacement {
        let rawQRX: CGFloat
        if showsURL {
            rawQRX = valueX + (max(urlWidth, 0) - qrSize) / 2
        } else {
            rawQRX = valueX + (max(availableWidth, 0) - qrSize) / 2
        }
        let maximumQRX = max(bodyMaxX - qrSize, bodyMinX)
        return HorizontalColophonHPPlacement(
            urlX: valueX,
            qrX: rawQRX.clamped(to: bodyMinX...maximumQRX)
        )
    }
}
```

- [ ] **手順4: PDF描画を座標ヘルパーへ接続する**

`drawHorizontalColophonHPEntry`から`blockWidth`、`blockX`、中央寄せした`urlX`を削除する。`valueLayout`計算後に次を使用する。

```swift
let placement = HorizontalColophonHPPlacement.make(
    valueX: valueX,
    availableWidth: availableValueWidth,
    urlWidth: valueLayout.frameWidth,
    qrSize: qrSize,
    showsURL: colophon.showsWebsiteURL,
    bodyMinX: layout.bodyFrame.minX,
    bodyMaxX: layout.bodyFrame.maxX
)

drawQRCode(
    qrCode,
    in: CGRect(
        x: placement.qrX,
        y: y,
        width: qrSize,
        height: qrSize
    )
)
```

URL描画の`x`は`placement.urlX`、`maxWidth`は`availableValueWidth`を使用する。`precomputedLayout`は従来の`valueLayout`を渡す。

- [ ] **手順5: QR配置テストを成功させる**

手順2と同じコマンドを実行する。

期待結果: 3テストすべて成功する。

- [ ] **手順6: タスク5をコミットする**

```bash
git add \
  Honkumi/Shared/Services/HorizontalColophonHPPlacement.swift \
  Honkumi/Shared/Services/PDFExportService.swift \
  HonkumiTests/HorizontalColophonHPPlacementTests.swift
git commit -m "Align colophon URL and QR code"
```

---

### タスク6: 実入力・全体・実機検証

**ファイル:**

- 一時変更後に復元: `HonkumiTests/CircleLogoImageImporterTests.swift`
- 検証のみ: 全ソースとテスト

**インターフェース:**

- 入力: 提供された`logo.svg`と`title.svg`
- 出力: 期待する縦横比のPNG、全テスト成功、3構成ビルド成功、実機インストール成功

- [ ] **手順1: 提供SVGを読む一時テストを追加する**

このテストはローカル統合確認だけに使い、コミット前に削除する。

```swift
func testLocallySuppliedSVGFilesConvert() async throws {
    let cases = [
        (
            "/Users/orca/Library/Mobile Documents/com~apple~CloudDocs/Pictures/Honkumi/logo.svg",
            1.0
        ),
        (
            "/Users/orca/Library/Mobile Documents/com~apple~CloudDocs/Pictures/Honkumi/title.svg",
            2.4
        )
    ]

    for (path, expectedRatio) in cases {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let png = try await CircleLogoImageImporter.importedImageData(
            data,
            contentType: .svg
        )
        let image = try XCTUnwrap(UIImage(data: png)?.cgImage)
        XCTAssertEqual(
            Double(image.width) / Double(image.height),
            expectedRatio,
            accuracy: 0.01,
            path
        )
    }
}
```

- [ ] **手順2: 提供SVGの変換を確認する**

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -only-testing:HonkumiTests/CircleLogoImageImporterTests/testLocallySuppliedSVGFilesConvert \
  test
```

期待結果: `logo.svg`は1:1、`title.svg`は2.4:1のPNGとして成功する。

- [ ] **手順3: 一時テストを削除する**

`testLocallySuppliedSVGFilesConvert`だけを削除し、次でローカル絶対パスが残っていないことを確認する。

```bash
rg -n '/Users/orca|Mobile Documents|logo\.svg|title\.svg' \
  Honkumi HonkumiTests
```

期待結果: 今回追加したローカル絶対パスは0件。

- [ ] **手順4: 全XCTestを実行する**

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test
```

期待結果: 失敗0件、スキップ0件。

- [ ] **手順5: Debug・Staging・Releaseをビルドする**

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  build
```

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme 'Honkumi Staging' \
  -configuration Staging \
  -destination 'generic/platform=iOS Simulator' \
  build
```

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

期待結果: 3コマンドとも終了コード0。

- [ ] **手順6: 差分とコミット状態を確認する**

```bash
git diff --check
git status --short
git log --oneline --decorate -8
```

期待結果: 一時テストとローカル絶対パスがなく、意図したソース・テストだけがコミット済み。未コミット差分0件。

- [ ] **手順7: ブランチをプッシュする**

```bash
git push -u origin codex/circle-logo-colophon-regressions
```

期待結果: ローカルとリモートの差分が0/0。

- [ ] **手順8: 実機ビルド元へfast-forwardする**

通常フォルダ`/Users/orca/Projects/Honkumi`で、履歴が直線であることを確認してから実行する。

```bash
git merge-base --is-ancestor \
  codex/print-preview-colophon-fixes \
  codex/circle-logo-colophon-regressions
git merge --ff-only codex/circle-logo-colophon-regressions
git push origin codex/print-preview-colophon-fixes
```

期待結果: 通常フォルダのHEADが作業ブランチと同じコミットになる。既存の未追跡ファイルと無関係な削除状態は変更しない。

- [ ] **手順9: 接続実機へ再インストールする**

通常フォルダ`/Users/orca/Projects/Honkumi`で実行する。

```bash
scripts/install-on-device.sh
```

期待結果: `BUILD SUCCEEDED`と`Installed Honkumi on device`が表示される。

- [ ] **手順10: 端末上のインストールを確認する**

手順9で表示された端末IDを使用する。

```bash
xcrun devicectl device info apps \
  --device 067B2967-DB86-568D-8C25-96C10E3F3504 \
  --bundle-id jp.honkumi.Honkumi \
  --columns '*'
```

期待結果: `jp.honkumi.Honkumi`がDeveloper Appとして表示される。
