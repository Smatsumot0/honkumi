# Editor Move-to-Bottom Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 「一番下へ移動」で本文末尾へカーソルを移し、長文でも画面を最大スクロール位置まで確実に追従させる。

**Architecture:** SwiftUIの選択範囲更新だけではなく、`ManuscriptTextEditorCommand`としてUIKitコーディネータへ末尾移動を渡す。UTF-16末尾と安全な最大Yオフセットの計算は純粋なヘルパーに分離して単体テストし、UITextViewではレイアウト確定後に選択・スクロール・Binding同期を一括して行う。

**Tech Stack:** Swift 5、SwiftUI、UIKit、XCTest、XcodeBuild

## Global Constraints

- 既存の未コミット変更を保持し、この計画に記載したファイルだけを変更する。
- `ManuscriptTextEditor`の既存のキーボード遷移、自動選択スクロール抑制、スクロール方向検出を壊さない。
- 文字位置はSwiftの`String.count`ではなくUTF-16長を使う。
- 新しいSwiftファイルは既存のFile System Synchronized Groupでターゲットへ自動追加される。`project.pbxproj`は変更しない。
- 各タスクを完了するたびに対象テストを実行し、最後にSimulator上で手動確認する。

---

## Task 1: 末尾選択範囲と最大スクロール位置を純粋関数にする

**Files:**

- Create: `Honkumi/Shared/Components/ManuscriptTextEditorNavigation.swift`
- Create: `HonkumiTests/ManuscriptTextEditorNavigationTests.swift`

**Produces:**

- `ManuscriptTextEditorNavigation.bottomSelectionRange(for:)`
- `ManuscriptTextEditorNavigation.maximumContentOffsetY(contentHeight:viewportHeight:adjustedInsetTop:adjustedInsetBottom:)`

### Steps

- [ ] 1. 先に次の失敗テストを作成する。

```swift
import CoreGraphics
@testable import Honkumi
import XCTest

final class ManuscriptTextEditorNavigationTests: XCTestCase {
    func testBottomSelectionUsesUTF16Length() {
        XCTAssertEqual(
            ManuscriptTextEditorNavigation.bottomSelectionRange(for: "本文😀"),
            NSRange(location: 4, length: 0)
        )
    }

    func testEmptyTextBottomSelectionIsZero() {
        XCTAssertEqual(
            ManuscriptTextEditorNavigation.bottomSelectionRange(for: ""),
            NSRange(location: 0, length: 0)
        )
    }

    func testMaximumOffsetIncludesBottomInset() {
        XCTAssertEqual(
            ManuscriptTextEditorNavigation.maximumContentOffsetY(
                contentHeight: 1_200,
                viewportHeight: 600,
                adjustedInsetTop: 10,
                adjustedInsetBottom: 96
            ),
            696,
            accuracy: 0.001
        )
    }

    func testMaximumOffsetDoesNotScrollShortContentBelowTop() {
        XCTAssertEqual(
            ManuscriptTextEditorNavigation.maximumContentOffsetY(
                contentHeight: 300,
                viewportHeight: 600,
                adjustedInsetTop: 10,
                adjustedInsetBottom: 96
            ),
            -10,
            accuracy: 0.001
        )
    }
}
```

- [ ] 2. テストを実行し、型が未定義で失敗することを確認する。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test -only-testing:HonkumiTests/ManuscriptTextEditorNavigationTests
```

Expected: `Cannot find 'ManuscriptTextEditorNavigation' in scope`

- [ ] 3. 最小実装を追加する。

```swift
import CoreGraphics
import Foundation

nonisolated enum ManuscriptTextEditorNavigation {
    static func bottomSelectionRange(for text: String) -> NSRange {
        NSRange(location: (text as NSString).length, length: 0)
    }

    static func maximumContentOffsetY(
        contentHeight: CGFloat,
        viewportHeight: CGFloat,
        adjustedInsetTop: CGFloat,
        adjustedInsetBottom: CGFloat
    ) -> CGFloat {
        max(
            -adjustedInsetTop,
            contentHeight - viewportHeight + adjustedInsetBottom
        )
    }
}
```

- [ ] 4. 同じテストを再実行し、4件すべて成功することを確認する。

- [ ] 5. このタスクだけをコミットする。

```bash
git add Honkumi/Shared/Components/ManuscriptTextEditorNavigation.swift \
  HonkumiTests/ManuscriptTextEditorNavigationTests.swift
git commit -m "Add editor bottom navigation geometry"
```

---

## Task 2: UIKitコマンドとして末尾移動を実行する

**Files:**

- Modify: `Honkumi/Shared/Components/ManuscriptTextEditor.swift`
- Modify: `Honkumi/Features/Editor/EditorView.swift`
- Modify: `Honkumi/Features/Editor/EditorViewModel.swift`
- Modify: `HonkumiTests/ManuscriptTextEditorNavigationTests.swift`

**Consumes:**

- Task 1の`ManuscriptTextEditorNavigation`

**Produces:**

- `ManuscriptTextEditorCommand.moveToBottom(UUID)`
- レイアウト確定後の末尾選択・最大Y追従・Binding同期

### Steps

- [ ] 1. `EditorViewModel.rangeForMovingToBottom()`が共通ヘルパーを使うことを守る回帰テストを追加する。テスト用`DocumentStore`は一意なUserDefaults suiteを使い、本文を`本文😀`へ更新してから`NSRange(location: 4, length: 0)`を期待する。

```swift
@MainActor
func testEditorViewModelBottomRangeUsesUTF16End() {
    let suite = "jp.honkumi.tests.editor-bottom-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = DocumentStore(userDefaults: defaults)
    store.updateBody("本文😀")
    let viewModel = EditorViewModel(documentStore: store)

    XCTAssertEqual(
        viewModel.rangeForMovingToBottom(),
        NSRange(location: 4, length: 0)
    )
}
```

- [ ] 2. `ManuscriptTextEditorCommand`へ`case moveToBottom(UUID)`を追加する前にビルドし、既存コードがまだ新コマンドを扱っていない基準状態を確認する。

- [ ] 3. `EditorView.moveToBottom()`を次の形へ変更する。UIKitコマンドを唯一のスクロール開始点とし、SwiftUI側のrangeはコーディネータから同期させる。

```swift
private func moveToBottom() {
    editorCommand = .moveToBottom(UUID())
}
```

- [ ] 4. `ManuscriptTextEditor.Coordinator.perform(_:in:)`へ末尾移動分岐を追加する。

```swift
case .moveToBottom:
    moveToBottom(in: textView)
```

- [ ] 5. コーディネータへ次の責務を持つ`moveToBottom(in:)`を実装する。

```swift
private func moveToBottom(in textView: ManuscriptUIKitTextView) {
    textView.unmarkText()
    textView.layoutIfNeeded()

    let range = ManuscriptTextEditorNavigation.bottomSelectionRange(for: textView.text)
    textView.allowsAutomaticSelectionScrolling = true
    textView.selectedRange = range
    textView.allowsAutomaticSelectionScrolling = false

    DispatchQueue.main.async { [weak self, weak textView] in
        guard let self, let textView else { return }
        textView.layoutIfNeeded()
        let y = ManuscriptTextEditorNavigation.maximumContentOffsetY(
            contentHeight: textView.contentSize.height,
            viewportHeight: textView.bounds.height,
            adjustedInsetTop: textView.adjustedContentInset.top,
            adjustedInsetBottom: textView.adjustedContentInset.bottom
        )
        let target = CGPoint(x: textView.contentOffset.x, y: y)
        textView.setContentOffset(target, animated: false)
        self.parent.selectedRange = range
        self.parent.requestedSelectedRange = nil
        self.parent.contentOffset = target
        self.lastScrollOffsetY = target.y
    }
}
```

既存`clampedContentOffset`の`maxY`計算もTask 1のヘルパーへ置換し、末尾移動と通常のselection revealが同じ下端境界を使う。

```swift
let maxY = ManuscriptTextEditorNavigation.maximumContentOffsetY(
    contentHeight: textView.contentSize.height,
    viewportHeight: textView.bounds.height,
    adjustedInsetTop: inset.top,
    adjustedInsetBottom: inset.bottom
)
```

- [ ] 6. `EditorViewModel.rangeForMovingToBottom()`を共通ヘルパーへ委譲する。

```swift
func rangeForMovingToBottom() -> NSRange {
    ManuscriptTextEditorNavigation.bottomSelectionRange(for: document.body)
}
```

- [ ] 7. 既存の`updateUIView`が同じ更新サイクルで古い`requestedSelectedRange`を再適用しないことを確認する。コマンド処理後は既存どおり`command = nil`へ戻し、末尾移動側では`requestedSelectedRange`をnilにする。

- [ ] 8. 対象テストとDebugビルドを実行する。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test -only-testing:HonkumiTests/ManuscriptTextEditorNavigationTests
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi -configuration Debug \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' build
```

Expected: tests pass and `** BUILD SUCCEEDED **`.

- [ ] 9. このタスクだけをコミットする。

```bash
git add Honkumi/Shared/Components/ManuscriptTextEditor.swift \
  Honkumi/Features/Editor/EditorView.swift \
  Honkumi/Features/Editor/EditorViewModel.swift \
  HonkumiTests/ManuscriptTextEditorNavigationTests.swift
git commit -m "Make editor bottom navigation follow the cursor"
```

---

## Task 3: Simulatorでキーボード遷移を含む挙動を確認する

**Files:**

- No source changes expected
- Modify only if a reproducible defect is found: files from Task 2

### Steps

- [ ] 1. SimulatorへDebugアプリをインストールして起動する。

```bash
xcrun simctl install 6C9E009C-5004-4C8D-8627-753D6CE09EBF \
  ~/Library/Developer/Xcode/DerivedData/Honkumi-*/Build/Products/Debug-iphonesimulator/Honkumi.app
xcrun simctl launch 6C9E009C-5004-4C8D-8627-753D6CE09EBF jp.honkumi.app
```

- [ ] 2. 十分に長い本文を開き、先頭付近から「一番下へ移動」を押す。次を目視確認する。

  - カーソルが本文末尾にある。
  - 最終行と下部インセットが見える。
  - ボタンを連続で押しても位置が上へ戻らない。

- [ ] 3. キーボードを閉じた状態と開いた状態で同じ操作を行い、キーボード表示切替後も以前のスクロール位置へ戻らないことを確認する。

- [ ] 4. 空本文で操作し、先頭位置のままクラッシュしないことを確認する。

- [ ] 5. 問題が見つかった場合だけ、再現条件を単体テストへ追加してから最小修正する。手動確認だけを理由にテストを省略しない。

- [ ] 6. 最終対象テストを再実行する。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test -only-testing:HonkumiTests/ManuscriptTextEditorNavigationTests
```

## Completion Evidence

- UTF-16終端・空本文・短文/長文の最大Y計算テストが成功している。
- Simulatorで長文、空本文、キーボード開閉後の最下移動を確認している。
- 既存のスクロール位置保存とスクロール方向UIに回帰がない。
