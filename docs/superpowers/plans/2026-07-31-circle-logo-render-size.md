# サークルロゴ表示サイズ変更 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 奥付のサークルロゴを、縦横比を保ったまま本文領域幅の50%・奥付4行分の両方を上限として最大表示する。

**Architecture:** `PDFExportService.swift`内に、画像サイズと本文領域から描画矩形を返す純粋な`CircleLogoRenderPlacement`を追加する。奥付の高さ計算と実描画の両方を同じ配置計算へ接続し、表示サイズと後続項目の配置を一致させる。

**Tech Stack:** Swift 6、UIKit、Core Graphics、PDFKit、XCTest、Xcode 26.5

## Global Constraints

- 設計書は`docs/superpowers/specs/2026-07-31-circle-logo-render-size-design.md`を正とする。
- 最大幅は余白を除いた`layout.bodyFrame.width`の50%とする。
- 最大高さは横書き奥付の`lineHeight`の4行分とする。
- 画像の縦横比を維持し、本文領域の水平方向中央へ配置する。
- 描画矩形を本文領域内へ収め、左右の余白へはみ出させない。
- ロゴの実描画高を奥付項目の高さへ反映し、最低1行分の高さは維持する。
- ロゴ保存形式、アップロード処理、設定UI、作者・サークル行の表示条件は変更しない。
- 現在未コミットの`Honkumi.xcodeproj/project.pbxproj`、`Honkumi/Features/Settings/`配下、および無関係な削除・未追跡ファイルには触れない。

## File Structure

- 変更: `Honkumi/Shared/Services/PDFExportService.swift`
  - `CircleLogoRenderPlacement`の純粋なサイズ・中央配置計算を保持する。
  - 奥付項目高とPDF描画を同じ配置結果へ接続する。
- 変更: `HonkumiTests/ColophonCreatorVisibilityTests.swift`
  - 横長、縦長、正方形、無効寸法、および最低行高を検証する。
- 変更しない: `Honkumi.xcodeproj/project.pbxproj`
  - 新規Swiftファイルを増やさず、現在のユーザー変更との競合を避ける。

---

### Task 1: アスペクトフィット配置と奥付描画の統合

**Files:**

- Modify: `Honkumi/Shared/Services/PDFExportService.swift:37-58, 1283-1294, 1415-1426, 1923-1960`
- Test: `HonkumiTests/ColophonCreatorVisibilityTests.swift:5-154`

**Interfaces:**

- Consumes: `CGSize imageSize`、`CGRect bodyFrame`、`CGFloat lineHeight`、`CGFloat y`
- Produces: `CircleLogoRenderPlacement.make(imageSize:bodyFrame:lineHeight:y:) -> CircleLogoRenderPlacement?`
- Produces: `CircleLogoRenderPlacement.rect: CGRect`
- Produces: `CircleLogoRenderPlacement.blockHeight(minimumLineHeight:) -> CGFloat`
- Consumes: `ColophonSettings.circleImageData`を`UIImage(data:)`で読み込んだ画像寸法

- [ ] **Step 1: 実行前状態と対象ファイルが競合していないことを確認する**

Run:

```bash
git status --short
git diff -- Honkumi/Shared/Services/PDFExportService.swift HonkumiTests/ColophonCreatorVisibilityTests.swift
```

Expected: 対象2ファイルに今回以前の差分がない。差分がある場合は上書きせず、内容を確認して計画を調整する。

- [ ] **Step 2: テスト作成前にテスト品質ルールを読む**

Run:

```bash
sed -n '1,320p' /Users/orca/.codex/plugins/cache/openai-curated-remote/superpowers/6.2.0/skills/test-driven-development/writing-good-tests.md
```

Expected: 各テストが実装の定数・アスペクト計算・中央配置のいずれを壊す変更で失敗するか説明できる。

- [ ] **Step 3: 配置計算の失敗テストを書く**

`HonkumiTests/ColophonCreatorVisibilityTests.swift`へ次を追加する。

```swift
func testWideCircleLogoUsesHalfBodyWidthAndKeepsAspectRatio() throws {
    let bodyFrame = CGRect(x: 20, y: 40, width: 200, height: 300)

    let placement = try XCTUnwrap(
        CircleLogoRenderPlacement.make(
            imageSize: CGSize(width: 400, height: 100),
            bodyFrame: bodyFrame,
            lineHeight: 20,
            y: 60
        )
    )

    XCTAssertEqual(placement.rect.width, 100, accuracy: 0.001)
    XCTAssertEqual(placement.rect.height, 25, accuracy: 0.001)
    XCTAssertEqual(placement.rect.minX, 70, accuracy: 0.001)
    XCTAssertEqual(placement.rect.minY, 60, accuracy: 0.001)
    XCTAssertGreaterThanOrEqual(placement.rect.minX, bodyFrame.minX)
    XCTAssertLessThanOrEqual(placement.rect.maxX, bodyFrame.maxX)
}

func testTallCircleLogoUsesFourLineHeightAndKeepsAspectRatio() throws {
    let placement = try XCTUnwrap(
        CircleLogoRenderPlacement.make(
            imageSize: CGSize(width: 100, height: 400),
            bodyFrame: CGRect(x: 20, y: 40, width: 200, height: 300),
            lineHeight: 20,
            y: 60
        )
    )

    XCTAssertEqual(placement.rect.width, 20, accuracy: 0.001)
    XCTAssertEqual(placement.rect.height, 80, accuracy: 0.001)
    XCTAssertEqual(placement.rect.minX, 110, accuracy: 0.001)
}

func testSquareCircleLogoUsesLargestSizeWithinBothLimits() throws {
    let placement = try XCTUnwrap(
        CircleLogoRenderPlacement.make(
            imageSize: CGSize(width: 100, height: 100),
            bodyFrame: CGRect(x: 20, y: 40, width: 200, height: 300),
            lineHeight: 20,
            y: 60
        )
    )

    XCTAssertEqual(placement.rect.width, 80, accuracy: 0.001)
    XCTAssertEqual(placement.rect.height, 80, accuracy: 0.001)
    XCTAssertEqual(placement.rect.minX, 80, accuracy: 0.001)
}

func testCircleLogoBlockHeightUsesRenderedHeightWithOneLineMinimum() throws {
    let bodyFrame = CGRect(x: 0, y: 0, width: 200, height: 300)
    let widePlacement = try XCTUnwrap(
        CircleLogoRenderPlacement.make(
            imageSize: CGSize(width: 400, height: 20),
            bodyFrame: bodyFrame,
            lineHeight: 20,
            y: 0
        )
    )
    let tallPlacement = try XCTUnwrap(
        CircleLogoRenderPlacement.make(
            imageSize: CGSize(width: 100, height: 400),
            bodyFrame: bodyFrame,
            lineHeight: 20,
            y: 0
        )
    )

    XCTAssertEqual(
        widePlacement.blockHeight(minimumLineHeight: 20),
        20,
        accuracy: 0.001
    )
    XCTAssertEqual(
        tallPlacement.blockHeight(minimumLineHeight: 20),
        80,
        accuracy: 0.001
    )
}

func testCircleLogoPlacementRejectsInvalidDimensions() {
    let bodyFrame = CGRect(x: 0, y: 0, width: 200, height: 300)

    XCTAssertNil(
        CircleLogoRenderPlacement.make(
            imageSize: CGSize(width: 0, height: 100),
            bodyFrame: bodyFrame,
            lineHeight: 20,
            y: 0
        )
    )
    XCTAssertNil(
        CircleLogoRenderPlacement.make(
            imageSize: CGSize(width: 100, height: CGFloat.infinity),
            bodyFrame: bodyFrame,
            lineHeight: 20,
            y: 0
        )
    )
}
```

- [ ] **Step 4: 対象テストを実行し、期待どおり失敗することを確認する**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -only-testing:HonkumiTests/ColophonCreatorVisibilityTests \
  test
```

Expected: FAIL with `cannot find 'CircleLogoRenderPlacement' in scope`。テスト構文や既存コードの別エラーで失敗した場合は、そのエラーを修正して再実行する。

- [ ] **Step 5: 最小の配置計算を追加する**

`Honkumi/Shared/Services/PDFExportService.swift`のトップレベル補助型群へ次を追加する。

```swift
nonisolated struct CircleLogoRenderPlacement: Equatable {
    let rect: CGRect

    static func make(
        imageSize: CGSize,
        bodyFrame: CGRect,
        lineHeight: CGFloat,
        y: CGFloat
    ) -> CircleLogoRenderPlacement? {
        guard imageSize.width.isFinite,
              imageSize.height.isFinite,
              bodyFrame.minX.isFinite,
              bodyFrame.width.isFinite,
              lineHeight.isFinite,
              y.isFinite,
              imageSize.width > 0,
              imageSize.height > 0,
              bodyFrame.width > 0,
              lineHeight > 0 else { return nil }

        let maximumSize = CGSize(
            width: bodyFrame.width * 0.5,
            height: lineHeight * 4
        )
        let scale = min(
            maximumSize.width / imageSize.width,
            maximumSize.height / imageSize.height
        )
        guard scale.isFinite, scale > 0 else { return nil }

        let size = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        let rect = CGRect(
            x: bodyFrame.midX - size.width / 2,
            y: y,
            width: size.width,
            height: size.height
        )
        return CircleLogoRenderPlacement(rect: rect)
    }

    func blockHeight(minimumLineHeight: CGFloat) -> CGFloat {
        max(minimumLineHeight, rect.height)
    }
}
```

- [ ] **Step 6: 奥付の高さ計算と描画を同じ配置へ接続する**

`drawHorizontalCircleLogoCreator`へ`lineHeight`を渡す。画像解決と配置を共通化し、旧`creatorImageHeight`と`creatorImageBlockHeight`を削除する。

```swift
private func circleLogoRenderResult(
    _ colophon: ColophonSettings,
    y: CGFloat,
    lineHeight: CGFloat,
    in layout: PageLayout
) -> (image: UIImage, placement: CircleLogoRenderPlacement)? {
    guard let data = colophon.circleImageData,
          let image = UIImage(data: data),
          let placement = CircleLogoRenderPlacement.make(
            imageSize: image.size,
            bodyFrame: layout.bodyFrame,
            lineHeight: lineHeight,
            y: y
          ) else { return nil }

    return (image, placement)
}

@discardableResult
private func drawHorizontalCircleLogoCreator(
    _ colophon: ColophonSettings,
    y: CGFloat,
    lineHeight: CGFloat,
    in layout: PageLayout
) -> Bool {
    guard let result = circleLogoRenderResult(
        colophon,
        y: y,
        lineHeight: lineHeight,
        in: layout
    ) else { return false }

    drawHighQualityImage(result.image, in: result.placement.rect)
    return true
}
```

描画呼び出しは次の形にする。

```swift
drawHorizontalCircleLogoCreator(
    colophon,
    y: cursorY,
    lineHeight: lineHeight,
    in: layout
)
```

`horizontalColophonEntryHeight`の`creator`分岐は次の形にする。無効画像は描画されず、項目位置の回帰を避けるため最低1行だけ確保する。

```swift
if entry.id == "creator",
   CircleLogoCreatorAccess(
    colophon: colophon,
    isPaid: subscriptionStatus == .paid
   ).isCreatorLogoActive {
    return circleLogoRenderResult(
        colophon,
        y: 0,
        lineHeight: lineHeight,
        in: layout
    )?.placement.blockHeight(minimumLineHeight: lineHeight) ?? lineHeight
}
```

- [ ] **Step 7: 対象テストを再実行して成功を確認する**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -only-testing:HonkumiTests/ColophonCreatorVisibilityTests \
  test
```

Expected: `ColophonCreatorVisibilityTests`がすべてPASSし、警告やエラーが増えない。

- [ ] **Step 8: 関連するロゴ・奥付テストを実行する**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -only-testing:HonkumiTests/ColophonCreatorVisibilityTests \
  -only-testing:HonkumiTests/CircleLogoImageImporterTests \
  -only-testing:HonkumiTests/CircleLogoImportPresentationTests \
  test
```

Expected: 指定した3テストクラスがすべてPASSする。

- [ ] **Step 9: アプリをビルドする**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'generic/platform=iOS Simulator' \
  build
```

Expected: `BUILD SUCCEEDED`相当で終了し、新しいコンパイルエラーや警告がない。

- [ ] **Step 10: 差分と空白エラーを確認する**

Run:

```bash
git diff --check
git diff -- Honkumi/Shared/Services/PDFExportService.swift HonkumiTests/ColophonCreatorVisibilityTests.swift
git status --short
```

Expected: 今回の実装差分は対象2ファイルだけで、既存の未コミット変更はそのまま残っている。`git diff --check`は出力なし。

- [ ] **Step 11: 実装ファイルだけをコミットする**

Run:

```bash
git add Honkumi/Shared/Services/PDFExportService.swift HonkumiTests/ColophonCreatorVisibilityTests.swift
git commit -m "fix: enlarge colophon circle logo"
```

Expected: コミットには対象2ファイルだけが含まれ、既存のユーザー変更は含まれない。
