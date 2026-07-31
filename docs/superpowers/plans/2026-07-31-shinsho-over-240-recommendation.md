# 新書・241ページ以上の推奨組版設定変更 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A6を含む既存設定を維持し、新書・241ページ以上で「推奨設定を使用する」場合の1行あたり文字数だけを42字から45字へ変更する。

**Architecture:** 推奨設定の単一情報源 `RecommendedPrintSettings` の対象プリセットだけを変更する。設定画面の `PrintSettingsDisplaySnapshot` と、プレビュー・PDFが使う `ManuscriptRenderPipeline` は既存どおり同じ実効設定を参照し、専用値や分岐は追加しない。

**Tech Stack:** Swift 5、XCTest、SwiftUI、UIKit PDFレンダリング、Xcode 26

## Global Constraints

- A6の推奨設定は変更しない。
- B6のすべてのページ数区分を変更しない。
- 新書の1〜240ページの推奨設定を変更しない。
- 新書・241ページ以上は8.5pt・45字・14行・天18.0mm・地17.0mm・小口10.0mm・ノド26.0mmとする。
- 字間・行間の自動計算、ノンブル、ページ偶奇によるノド・小口反転を変更しない。
- 推奨設定がオフの場合の手動値を変更しない。
- 既存作品の保存データ移行は追加しない。
- UI、プレビュー、PDFは `RecommendedPrintSettings.effectiveSettings` を共有する。

---

### Task 1: 変更しない推奨設定と手動設定の回帰契約を固定する

**Files:**

- Modify: `HonkumiTests/RecommendedPrintSettingsTests.swift`

**Interfaces:**

- Consumes: `RecommendedPrintSettings.recommendation(for:estimatedPageCount:)`、`RecommendedPrintSettings.effectiveSettings(settings:estimatedPageCount:)`、`LayoutCalculator.layout(for:pageNumber:)`
- Produces: A6・B6の実効値、推奨設定オフ時の値保持、奇数／偶数ページ余白反転を保護する回帰テスト

- [ ] **Step 1: リテラル期待値で回帰テストを追加する**

`RecommendedPrintSettingsTests` へ次のテストを追加する。

```swift
func testA6BoundaryRecommendationsRemainUnchanged() throws {
    try assertRecommendation(
        pageSize: .a6, pageCount: 160,
        fontSize: 9.0, characters: 39, lines: 15,
        top: 16, bottom: 18, outer: 11, inner: 22
    )
    try assertRecommendation(
        pageSize: .a6, pageCount: 161,
        fontSize: 9.0, characters: 40, lines: 14,
        top: 15, bottom: 17, outer: 10, inner: 24
    )
    try assertRecommendation(
        pageSize: .a6, pageCount: 240,
        fontSize: 9.0, characters: 40, lines: 14,
        top: 15, bottom: 17, outer: 10, inner: 24
    )
    try assertRecommendation(
        pageSize: .a6, pageCount: 241,
        fontSize: 8.5, characters: 40, lines: 15,
        top: 15, bottom: 16, outer: 10, inner: 26
    )
}

func testB6RecommendationsRemainUnchangedAcrossAllBands() throws {
    try assertRecommendation(
        pageSize: .b6, pageCount: 1,
        fontSize: 10.0, characters: 42, lines: 15,
        top: 20, bottom: 22, outer: 15, inner: 17
    )
    try assertRecommendation(
        pageSize: .b6, pageCount: 49,
        fontSize: 9.5, characters: 44, lines: 16,
        top: 19, bottom: 21, outer: 14, inner: 19
    )
    try assertRecommendation(
        pageSize: .b6, pageCount: 97,
        fontSize: 9.0, characters: 45, lines: 17,
        top: 18, bottom: 20, outer: 13, inner: 23
    )
    try assertRecommendation(
        pageSize: .b6, pageCount: 161,
        fontSize: 9.0, characters: 46, lines: 17,
        top: 17, bottom: 19, outer: 12, inner: 25
    )
    try assertRecommendation(
        pageSize: .b6, pageCount: 241,
        fontSize: 8.5, characters: 47, lines: 18,
        top: 16, bottom: 18, outer: 12, inner: 27
    )
}

func testManualSettingsRemainUntouchedWhenRecommendationsAreOff() {
    var settings = EditorSettings.default
    settings.pageSize = .shinsho
    settings.useRecommendedTypography = false
    settings.useRecommendedMargins = false
    settings.fontSize = 12.5
    settings.charactersPerLine = 31
    settings.linesPerPage = 12
    settings.marginTop = 21
    settings.marginBottom = 22
    settings.marginOuter = 14
    settings.marginInner = 19

    let effective = RecommendedPrintSettings.effectiveSettings(
        settings: settings,
        estimatedPageCount: 241
    )

    XCTAssertEqual(effective, settings.validated)
}

func testRecommendedMarginsReflectBetweenOddAndEvenPages() {
    var settings = EditorSettings.default
    settings.pageSize = .shinsho
    let effective = RecommendedPrintSettings.effectiveSettings(
        settings: settings,
        estimatedPageCount: 241
    )

    let odd = LayoutCalculator.layout(for: effective, pageNumber: 1)
    let even = LayoutCalculator.layout(for: effective, pageNumber: 2)
    let outer = LayoutCalculator.millimetersToPoints(10)
    let inner = LayoutCalculator.millimetersToPoints(26)

    XCTAssertEqual(odd.bodyFrame.minX, outer, accuracy: 0.001)
    XCTAssertEqual(odd.bodyFrame.maxX, odd.pageWidth - inner, accuracy: 0.001)
    XCTAssertEqual(even.bodyFrame.minX, inner, accuracy: 0.001)
    XCTAssertEqual(even.bodyFrame.maxX, even.pageWidth - outer, accuracy: 0.001)
}
```

同じテストクラスへ、リテラル値を比較する次のヘルパーを追加する。

```swift
private func assertRecommendation(
    pageSize: PageSize,
    pageCount: Int,
    fontSize: CGFloat,
    characters: Int,
    lines: Int,
    top: CGFloat,
    bottom: CGFloat,
    outer: CGFloat,
    inner: CGFloat,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let recommendation = try XCTUnwrap(
        RecommendedPrintSettings.recommendation(
            for: pageSize,
            estimatedPageCount: pageCount
        ),
        file: file,
        line: line
    )

    XCTAssertEqual(recommendation.fontSizePt, fontSize, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(recommendation.charactersPerLine, characters, file: file, line: line)
    XCTAssertEqual(recommendation.linesPerPage, lines, file: file, line: line)
    XCTAssertEqual(recommendation.marginTopMm, top, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(recommendation.marginBottomMm, bottom, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(recommendation.marginOuterMm, outer, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(recommendation.marginInnerMm, inner, accuracy: 0.001, file: file, line: line)
}
```

- [ ] **Step 2: 回帰テストが現在の実装で成功することを確認する**

Run:

```bash
xcodebuild \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -derivedDataPath /private/tmp/honkumi-shinsho-recommendation-derived-data \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/RecommendedPrintSettingsTests \
  test
```

Expected: `RecommendedPrintSettingsTests` がすべて成功する。A6の161・240ページは40字・14行のまま、B6全区分と手動設定、余白反転も成功する。

- [ ] **Step 3: 回帰テストをコミットする**

```bash
git add HonkumiTests/RecommendedPrintSettingsTests.swift
git commit -m "test: preserve unchanged print recommendations"
```

---

### Task 2: 新書241ページ境界をTDDで変更し、共通表示・描画経路を検証する

**Files:**

- Modify: `HonkumiTests/RecommendedPrintSettingsTests.swift`
- Modify: `HonkumiTests/PrintSettingSampleManifestTests.swift`
- Modify: `Honkumi/Shared/Services/RecommendedPrintSettings.swift`

**Interfaces:**

- Consumes: `RecommendedPrintSettings.recommendation(for:estimatedPageCount:)`、`PrintSettingsDisplaySnapshot.calculate(body:settings:)`、`ManuscriptRenderPipeline.preparedDocument(from:subscriptionStatus:)`
- Produces: 新書240ページでは42字、241ページ以上では45字となり、設定画面・プレビュー・PDF準備が同一値を使う実装

- [ ] **Step 1: 新書境界値の失敗テストを追加する**

`RecommendedPrintSettingsTests` へ次を追加する。

```swift
func testShinshoRecommendationSwitchesTo45CharactersAt241Pages() throws {
    try assertRecommendation(
        pageSize: .shinsho, pageCount: 240,
        fontSize: 9.0, characters: 42, lines: 14,
        top: 18, bottom: 18, outer: 10, inner: 24
    )
    try assertRecommendation(
        pageSize: .shinsho, pageCount: 241,
        fontSize: 8.5, characters: 45, lines: 14,
        top: 18, bottom: 17, outer: 10, inner: 26
    )
    try assertRecommendation(
        pageSize: .shinsho, pageCount: 242,
        fontSize: 8.5, characters: 45, lines: 14,
        top: 18, bottom: 17, outer: 10, inner: 26
    )
}
```

- [ ] **Step 2: 設定画面とプレビュー・PDF準備の失敗テストを追加する**

`PrintSettingSampleManifestTests` へ次を追加する。

```swift
func testShinshoOver240Uses45CharactersInDisplayAndRenderPipelines() throws {
    let sample = try XCTUnwrap(
        PrintSettingSampleManifest.recommendedSettingCases().first {
            $0.document.settings.pageSize == .shinsho
                && $0.requestedPageCount == 241
        }
    )

    let displaySnapshot = PrintSettingsDisplaySnapshot.calculate(
        body: sample.document.body,
        settings: sample.document.settings
    )
    let preparedDocument = ManuscriptRenderPipeline.preparedDocument(
        from: sample.document,
        subscriptionStatus: .free
    )

    for effective in [displaySnapshot.settings, preparedDocument.settings] {
        XCTAssertEqual(effective.fontSize, 8.5, accuracy: 0.001)
        XCTAssertEqual(effective.charactersPerLine, 45)
        XCTAssertEqual(effective.linesPerPage, 14)
        XCTAssertEqual(effective.marginTop, 18, accuracy: 0.001)
        XCTAssertEqual(effective.marginBottom, 17, accuracy: 0.001)
        XCTAssertEqual(effective.marginOuter, 10, accuracy: 0.001)
        XCTAssertEqual(effective.marginInner, 26, accuracy: 0.001)
    }
}
```

- [ ] **Step 3: 追加テストが対象値42字により失敗することを確認する**

Run:

```bash
xcodebuild \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -derivedDataPath /private/tmp/honkumi-shinsho-recommendation-derived-data \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/RecommendedPrintSettingsTests \
  -only-testing:HonkumiTests/PrintSettingSampleManifestTests \
  test
```

Expected: 新書241・242ページと表示・描画経路の期待値45に対し、実際値42となって失敗する。A6・B6・新書240ページのテストは成功する。

- [ ] **Step 4: 対象プリセットだけを45字へ変更する**

`RecommendedPrintSettings.presetTable[.shinsho][.over240]` を次の値にする。ほかのフィールドとプリセットは編集しない。

```swift
.over240: RecommendedLayoutSetting(
    charactersPerLine: 45,
    linesPerPage: 18,
    fontSizePt: 8.5,
    marginTopMm: 18,
    marginBottomMm: 17,
    marginInnerMm: 26,
    marginOuterMm: 10
)
```

- [ ] **Step 5: 対象テストがすべて成功することを確認する**

Step 3と同じ `xcodebuild` を実行する。

Expected: `RecommendedPrintSettingsTests` と `PrintSettingSampleManifestTests` がすべて成功する。

- [ ] **Step 6: 全テストを実行する**

Run:

```bash
xcodebuild \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -derivedDataPath /private/tmp/honkumi-shinsho-recommendation-derived-data \
  -parallel-testing-enabled NO \
  test
```

Expected: `** TEST SUCCEEDED **`。失敗テストは0件。

- [ ] **Step 7: 差分を検証して実装をコミットする**

Run:

```bash
git diff --check
git diff --stat HEAD
git status --short
```

Expected: 実装差分は対象プリセット1行と、境界値・共通経路を検証する2テストファイルだけ。Task 1の回帰テストコミットと設計・計画文書以外の差分はない。

```bash
git add \
  Honkumi/Shared/Services/RecommendedPrintSettings.swift \
  HonkumiTests/RecommendedPrintSettingsTests.swift \
  HonkumiTests/PrintSettingSampleManifestTests.swift
git commit -m "fix: increase dense shinsho recommendation"
```
