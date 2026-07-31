# Common Settings Dialog Intrinsic Height Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 共通設定適用ダイアログを通常時は内容に合う高さで表示し、内容が収まらない場合だけ最大高内でスクロールさせる。

**Architecture:** `ViewThatFits(in: .vertical)`の通常候補へ固有高のカード内容を、フォールバック候補へ最大高制約付き`ScrollView`を置く。角丸背景を付ける外側コンテナから垂直方向の`frame(maxHeight:)`を外し、選択された候補の実寸へ背景を追従させる。

**Tech Stack:** Swift 5、SwiftUI、UIKit `UIHostingController`、XCTest、Xcode 26

## Global Constraints

- 通常の画面高では、カードの高さを表示内容と上下20ptの内側余白に合わせる。
- カードは画面中央へ表示する。
- 小さい画面、横向き、大きなDynamic Typeなどで内容が収まらない場合だけ、カードを安全領域内の最大高へ制限する。
- 内容が収まらない場合は、カード内部を縦方向へスクロールできるようにする。
- 背景の操作防止、背景のアクセシビリティ非表示、ダイアログのモーダル属性を維持する。
- チェック項目、文言、ボタン動作、初期選択状態は変更しない。
- `WorkListView`が行う最大高の計算と受け渡しは変更しない。
- 他の設定適用処理、作品データ、PDF生成処理は変更しない。

---

### Task 1: カードを固有高で表示し、小画面だけスクロールさせる

**Files:**
- Modify: `Honkumi/Features/Library/CommonSettingsReviewDialog.swift:89-104`
- Test: `HonkumiTests/CommonSettingsReviewPresentationTests.swift:1-81`

**Interfaces:**
- Consumes: `CommonSettingsReviewDialog(selection:maximumHeight:onApply:onKeepCurrent:onCancel:)`と、`WorkListView`から渡されるカード全体の最大高`maximumHeight: CGFloat`
- Produces: 同じinitializerと操作コールバックを維持したまま、通常候補は固有高、スクロール候補だけは`maximumHeight`以下になる`CommonSettingsReviewDialog`

- [ ] **Step 1: 実際のSwiftUIカードが最大高まで伸びる回帰テストを書く**

`HonkumiTests/CommonSettingsReviewPresentationTests.swift`へ`SwiftUI`と`UIKit`をimportし、テストクラスへ次を追加する。

```swift
import SwiftUI
import UIKit

@MainActor
func testTallContainerKeepsDialogAtIntrinsicHeight() {
    let maximumHeight: CGFloat = 652
    let controller = UIHostingController(
        rootView: CommonSettingsReviewDialog(
            selection: .constant(.all),
            maximumHeight: maximumHeight,
            onApply: {},
            onKeepCurrent: {},
            onCancel: {}
        )
    )

    let measuredSize = controller.sizeThatFits(
        in: CGSize(width: 390, height: 700)
    )

    XCTAssertGreaterThan(measuredSize.height, 300)
    XCTAssertLessThan(measuredSize.height, maximumHeight - 100)
}

@MainActor
func testCompactContainerKeepsDialogWithinMaximumHeight() {
    let maximumHeight: CGFloat = 232
    let controller = UIHostingController(
        rootView: CommonSettingsReviewDialog(
            selection: .constant(.all),
            maximumHeight: maximumHeight,
            onApply: {},
            onKeepCurrent: {},
            onCancel: {}
        )
    )

    let measuredSize = controller.sizeThatFits(
        in: CGSize(width: 390, height: 280)
    )

    XCTAssertGreaterThan(measuredSize.height, 0)
    XCTAssertLessThanOrEqual(
        measuredSize.height,
        maximumHeight + 0.5
    )
}
```

- [ ] **Step 2: 回帰テストを実行し、現在のカードが最大高まで伸びることを確認する**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -only-testing:HonkumiTests/CommonSettingsReviewPresentationTests/testTallContainerKeepsDialogAtIntrinsicHeight \
  test
```

Expected: FAIL。`measuredSize.height`が`maximumHeight - 100`以上になり、角丸カード全体に付いた`.frame(maxHeight: maximumHeight)`がカードを引き伸ばすことを示す。

- [ ] **Step 3: 高さ制約をスクロール候補だけへ移す**

`CommonSettingsReviewDialog.body`を次の構造へ変更する。通常候補とスクロール候補の両方へ同じ20ptの内側余白を付け、外側コンテナから垂直方向の最大高フレームを削除する。

```swift
var body: some View {
    ViewThatFits(in: .vertical) {
        dialogContent
            .padding(20)
            .fixedSize(horizontal: false, vertical: true)

        ScrollView(.vertical) {
            dialogContent
        }
        .scrollBounceBehavior(.basedOnSize)
        .padding(20)
        .frame(maxHeight: maximumHeight)
    }
    .frame(maxWidth: 360)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    .shadow(radius: 24, y: 8)
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isModal)
}
```

`CommonSettingsReviewCopy`、`dialogContent`、チェック項目のBinding、各ボタンのaction、アクセシビリティ属性は変更しない。

- [ ] **Step 4: ダイアログ表示テストを実行してGREENを確認する**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -only-testing:HonkumiTests/CommonSettingsReviewPresentationTests \
  test
```

Expected: PASS。通常高ではカードが最大高より100pt以上小さく、小画面では232ptを超えない。既存の初期選択、Apply無効化、背景モーダル状態、中央配置計算もすべて成功する。

- [ ] **Step 5: 全XCTestを実行する**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test
```

Expected: 全テストPASS、失敗0、スキップ0。

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

Expected: 3コマンドすべて終了コード0。

- [ ] **Step 7: 差分を確認して実装をコミットする**

Run:

```bash
git diff --check
git diff -- \
  Honkumi/Features/Library/CommonSettingsReviewDialog.swift \
  HonkumiTests/CommonSettingsReviewPresentationTests.swift
git status --short
```

Expected: 空白エラーなし。製品コード1ファイルとテスト1ファイルだけが今回の未コミット差分で、既存のPDF削除・未追跡資料・`output/`・`tmp/`は変更されていない。

Commit:

```bash
git add \
  Honkumi/Features/Library/CommonSettingsReviewDialog.swift \
  HonkumiTests/CommonSettingsReviewPresentationTests.swift
git commit -m "Fix common settings dialog height"
```
