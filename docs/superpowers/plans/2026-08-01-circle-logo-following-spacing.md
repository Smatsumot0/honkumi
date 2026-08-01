# サークルロゴ下余白 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 横書き奥付PDFで、有効なサークルロゴの描画下端から次の奥付項目まで、奥付行高2行分の空白を確保する。

**Architecture:** `PDFExportService.swift`にテスト可能な純粋な項目間隔計算を追加し、ロゴ直後だけ`lineHeight * 2`、それ以外は8ptを返す。描画カーソルと奥付全体の高さ計算を同じ判定メソッドへ接続し、ロゴ画像を描画できない場合は通常間隔へフォールバックする。

**Tech Stack:** Swift 6、UIKit PDF描画、XCTest、Xcode 26

## Global Constraints

- 対象は横書き奥付PDFのサークルロゴ直後の項目間隔だけとする。
- ロゴの表示サイズ、縦横比、中央配置、保存形式、設定UIは変更しない。
- ロゴ以外の奥付項目間隔は8ptを維持する。
- ロゴ下端から次の奥付項目までの正味余白を`lineHeight * 2`にし、既存の8ptを重ねない。
- 描画カーソルと奥付全体の高さ計算は同じ間隔計算を使用する。
- ロゴ画像を描画できない場合は8ptへフォールバックする。

---

## File Structure

- `Honkumi/Shared/Services/PDFExportService.swift`: 純粋な項目間隔計算と、実際のロゴ描画可否を反映するPDFレイアウト接続を保持する。
- `HonkumiTests/ColophonCreatorVisibilityTests.swift`: ロゴ直後、通常項目直後、描画不能ロゴ直後の間隔ルールを単体テストする。

### Task 1: ロゴ直後の2行余白を描画と高さ計算へ適用する

**Files:**
- Modify: `Honkumi/Shared/Services/PDFExportService.swift:66-121,1314-1442`
- Test: `HonkumiTests/ColophonCreatorVisibilityTests.swift:1-113`

**Interfaces:**
- Consumes: `ColophonEntry.id`、`circleLogoRenderResult(_:y:lineHeight:in:)`、横書き奥付の`lineHeight`
- Produces: `HorizontalColophonInterEntrySpacing.value(after:renderedCircleLogo:lineHeight:) -> CGFloat`
- Produces: `PDFExportService.horizontalColophonInterEntrySpacing(after:colophon:lineHeight:in:) -> CGFloat`

- [ ] **Step 1: 純粋な間隔ルールの失敗テストを書く**

`HonkumiTests/ColophonCreatorVisibilityTests.swift`の`ColophonCreatorVisibilityTests`へ追加する。

```swift
func testRenderedCircleLogoUsesTwoLineFollowingSpacing() {
    XCTAssertEqual(
        HorizontalColophonInterEntrySpacing.value(
            after: "creator",
            renderedCircleLogo: true,
            lineHeight: 20
        ),
        40,
        accuracy: 0.001
    )
}

func testRegularColophonEntryKeepsStandardFollowingSpacing() {
    XCTAssertEqual(
        HorizontalColophonInterEntrySpacing.value(
            after: "workTitle",
            renderedCircleLogo: false,
            lineHeight: 20
        ),
        8,
        accuracy: 0.001
    )
}

func testUnavailableCircleLogoKeepsStandardFollowingSpacing() {
    XCTAssertEqual(
        HorizontalColophonInterEntrySpacing.value(
            after: "creator",
            renderedCircleLogo: false,
            lineHeight: 20
        ),
        8,
        accuracy: 0.001
    )
}
```

- [ ] **Step 2: 対象テストを実行して未実装による失敗を確認する**

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -parallel-testing-enabled NO \
  -derivedDataPath /tmp/honkumi-circle-logo-spacing-red \
  -only-testing:HonkumiTests/ColophonCreatorVisibilityTests test
```

Expected: `cannot find 'HorizontalColophonInterEntrySpacing' in scope`で失敗する。

- [ ] **Step 3: 純粋な項目間隔計算を追加する**

`CircleLogoRenderPlacement`の直後へ追加する。

```swift
nonisolated struct HorizontalColophonInterEntrySpacing {
    static let standard: CGFloat = 8

    static func value(
        after previousEntryID: String,
        renderedCircleLogo: Bool,
        lineHeight: CGFloat
    ) -> CGFloat {
        guard previousEntryID == "creator", renderedCircleLogo else {
            return standard
        }
        return lineHeight * 2
    }
}
```

- [ ] **Step 4: 実際のロゴ描画可否を間隔ルールへ接続する**

`PDFExportService`へ追加する。画像のデコードと配置計算が成功した場合だけ2行余白を選ぶ。

```swift
private func horizontalColophonInterEntrySpacing(
    after previousEntry: ColophonEntry,
    colophon: ColophonSettings,
    lineHeight: CGFloat,
    in layout: PageLayout
) -> CGFloat {
    let renderedCircleLogo = previousEntry.id == "creator"
        && circleLogoRenderResult(
            colophon,
            y: 0,
            lineHeight: lineHeight,
            in: layout
        ) != nil

    return HorizontalColophonInterEntrySpacing.value(
        after: previousEntry.id,
        renderedCircleLogo: renderedCircleLogo,
        lineHeight: lineHeight
    )
}
```

描画ループの一律8pt加算を置き換える。

```swift
if entryIndex > 0 {
    cursorY += horizontalColophonInterEntrySpacing(
        after: entries[entryIndex - 1],
        colophon: colophon,
        lineHeight: lineHeight,
        in: layout
    )
}
```

奥付全体の高さ計算では先頭の一括8pt加算を削除し、同じ計算を各項目の前で加算する。

```swift
var height: CGFloat = 0
for (entryIndex, entry) in entries.enumerated() {
    if entryIndex > 0 {
        height += horizontalColophonInterEntrySpacing(
            after: entries[entryIndex - 1],
            colophon: colophon,
            lineHeight: lineHeight,
            in: layout
        )
    }

    if entry.addsPrecedingSpace {
        height += lineHeight
    }

    height += horizontalColophonEntryHeight(
        entry,
        colophon: colophon,
        subscriptionStatus: subscriptionStatus,
        lineHeight: lineHeight,
        in: layout
    )

    if entry.addsFollowingSpace {
        height += lineHeight
    }
}
```

- [ ] **Step 5: 対象テストを実行して成功を確認する**

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -parallel-testing-enabled NO \
  -derivedDataPath /tmp/honkumi-circle-logo-spacing-green \
  -only-testing:HonkumiTests/ColophonCreatorVisibilityTests test
```

Expected: `ColophonCreatorVisibilityTests`がすべて成功する。

- [ ] **Step 6: PDF回帰テストを実行する**

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -parallel-testing-enabled NO \
  -derivedDataPath /tmp/honkumi-circle-logo-spacing-regression \
  -only-testing:HonkumiTests/ColophonCreatorVisibilityTests \
  -only-testing:HonkumiTests/PDFX4GeneratedPDFTests \
  -only-testing:HonkumiTests/PDFPreflightChapterHeaderTests test
```

Expected: 指定した3テストクラスがすべて成功する。

- [ ] **Step 7: 差分を確認して実装をコミットする**

```bash
git diff --check
git diff -- Honkumi/Shared/Services/PDFExportService.swift HonkumiTests/ColophonCreatorVisibilityTests.swift
git add Honkumi/Shared/Services/PDFExportService.swift HonkumiTests/ColophonCreatorVisibilityTests.swift
git commit -m "fix: add two-line spacing below circle logo"
```
