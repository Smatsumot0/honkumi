# Debug Print-Setting Samples and Regression Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Debug環境変数から、推奨設定15 PDFと7.0〜20.0ptの文字サイズ27 PDFを個別に生成できるようにし、全改修の自動・目視回帰を完了する。

**Architecture:** サンプルの組合せ、本文、実効設定、ファイル名を`PrintSettingSampleManifest`という純粋なmanifestへ分離し、件数と設定をPDF生成なしでテストする。既存`VerticalTypesettingSamplePDFExporter`は環境変数のdispatchとファイルcopyだけを担う。新しい2フラグは既存の縦書きフラグなしで単独実行でき、通常起動とReleaseではコードを実行しない。

**Tech Stack:** Swift 5、UIKit PDF Renderer、CoreGraphics/PDFKit、XCTest、xcrun simctl、既存Swift回帰scripts

## Global Constraints

- Depends on all previous plans. 特に用紙候補3種、推奨設定、章タイトル、絵文字置換を最終サンプルへ反映する。
- 新機能は`#if DEBUG`内だけで有効にし、Release起動へ分岐・I/O・メモリ負荷を追加しない。
- `HONKUMI_EXPORT_RECOMMENDED_SETTING_SAMPLES`と`HONKUMI_EXPORT_FONT_SIZE_SAMPLES`はそれぞれ単独で動く。
- 既存`HONKUMI_EXPORT_VERTICAL_TYPESETTING_SAMPLES`、`HONKUMI_EXPORT_COLOPHON_REGRESSION_SAMPLES`、`HONKUMI_EXPORT_ALL_FONT_SAMPLES`の出力内容を変更しない。
- manifest testsでは42 PDFを実生成しない。全生成は明示的なDebug環境変数を与えた手動検証時だけ行う。
- 推奨サンプルの代表ページ数は各帯の下限`1, 49, 97, 161, 241`を使い、明示的改ページで帯を安定させる。

---

## Task 1: 推奨設定サンプル15件のmanifestを定義する

**Files:**

- Create: `Honkumi/Shared/Services/PrintSettingSampleManifest.swift`
- Create: `HonkumiTests/PrintSettingSampleManifestTests.swift`

**Produces:**

- `PrintSettingSampleCase`
- `RecommendedSettingSamplePageBand`
- `PrintSettingSampleManifest.recommendedSettingCases()`

### Steps

- [ ] 1. 期待組合せを先にテストする。

```swift
@testable import Honkumi
import XCTest

final class PrintSettingSampleManifestTests: XCTestCase {
    func testRecommendedManifestContainsThreeSizesByFiveBands() {
        let cases = PrintSettingSampleManifest.recommendedSettingCases()

        XCTAssertEqual(cases.count, 15)
        XCTAssertEqual(Set(cases.map(\.document.settings.pageSize)), Set(PageSize.selectableCases))
        XCTAssertEqual(Set(cases.map(\.requestedPageCount)), Set([1, 49, 97, 161, 241]))
        XCTAssertEqual(Set(cases.map(\.fileName)).count, 15)
    }

    func testRecommendedCasesUseBothRecommendationFlags() {
        for sample in PrintSettingSampleManifest.recommendedSettingCases() {
            XCTAssertTrue(sample.document.settings.useRecommendedTypography)
            XCTAssertTrue(sample.document.settings.useRecommendedMargins)
        }
    }

    func testRecommendedBodiesEstimateIntoTheirRequestedBands() {
        for sample in PrintSettingSampleManifest.recommendedSettingCases() {
            let effective = RecommendedPrintSettings.effectiveSettings(for: sample.document)
            let count = RecommendedPrintSettings.estimatedPageCount(
                body: sample.document.body,
                settings: effective
            )
            XCTAssertEqual(count, sample.requestedPageCount, sample.fileName)
            XCTAssertTrue(sample.pageBand.contains(count), sample.fileName)
        }
    }
}
```

- [ ] 2. 型未定義で失敗することを確認する。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test -only-testing:HonkumiTests/PrintSettingSampleManifestTests
```

- [ ] 3. 値型を`#if DEBUG`内へ追加する。

```swift
#if DEBUG
nonisolated struct PrintSettingSampleCase {
    let fileName: String
    let outputDirectoryName: String
    let document: ManuscriptDocument
}

nonisolated struct RecommendedPrintSettingSampleCase {
    let output: PrintSettingSampleCase
    let requestedPageCount: Int
    let pageBand: RecommendedSettingSamplePageBand

    var fileName: String { output.fileName }
    var document: ManuscriptDocument { output.document }
}

nonisolated enum RecommendedSettingSamplePageBand: CaseIterable {
    case pages1Through48
    case pages49Through96
    case pages97Through160
    case pages161Through240
    case pages241AndOver

    var representativePageCount: Int {
        switch self {
        case .pages1Through48: 1
        case .pages49Through96: 49
        case .pages97Through160: 97
        case .pages161Through240: 161
        case .pages241AndOver: 241
        }
    }

    func contains(_ pageCount: Int) -> Bool {
        switch self {
        case .pages1Through48:
            (1...48).contains(pageCount)
        case .pages49Through96:
            (49...96).contains(pageCount)
        case .pages97Through160:
            (97...160).contains(pageCount)
        case .pages161Through240:
            (161...240).contains(pageCount)
        case .pages241AndOver:
            pageCount >= 241
        }
    }

    var fileComponent: String {
        switch self {
        case .pages1Through48: "001-048p"
        case .pages49Through96: "049-096p"
        case .pages97Through160: "097-160p"
        case .pages161Through240: "161-240p"
        case .pages241AndOver: "241p以上"
        }
    }
}
#endif
```

`contains`と`fileComponent`は上記のexhaustive switchをそのまま使う。

- [ ] 4. 明示的改ページ本文を実装する。

```swift
private static func fixedPageCountBody(_ pageCount: Int) -> String {
    (1...pageCount)
        .map { "推奨設定確認ページ \($0)\n句読点。、英数字PDF123、絵文字😀" }
        .joined(separator: "\n\(ManuscriptMarkupParser.pageBreakTag)\n")
}
```

settingsは目次off、奥付off、章タイトル上部off、crop marks offにして、追加ページ要因を除く。

- [ ] 5. `PageSize.selectableCases × RecommendedSettingSamplePageBand.allCases`をflatMapし、各documentへpage sizeとrecommendation flagsを設定する。ファイル名に入れる実効設定は必ず次から計算する。

```swift
let effective = RecommendedPrintSettings.effectiveSettings(for: document)
```

- [ ] 6. ファイル名を次の固定順で組み立てる。

```text
<用紙>_<帯>_実<ページ数>p_<fontSize 1桁小数>pt_<charactersPerLine>字_<linesPerPage>行_天<1桁小数>_地<1桁小数>_小口<1桁小数>_ノド<1桁小数>.pdf
```

例:

```text
A6_001-048p_実1p_9.0pt_38字_16行_天16.0_地16.0_小口13.0_ノド15.0.pdf
```

`PageSize`用の短いfile componentは次のexhaustive switchにする。A5/B5の分岐は型の網羅性と既存互換のためだけに残し、manifestへは入れない。

```swift
private static func pageSizeFileComponent(_ pageSize: PageSize) -> String {
    switch pageSize {
    case .a6: "A6"
    case .shinsho: "新書"
    case .b6: "B6"
    case .a5: "A5"
    case .b5: "B5"
    }
}
```

- [ ] 7. テストへ、各file nameが実効9項目をすべて含むassertを追加する。

- [ ] 8. 対象テストを成功させてコミットする。

```bash
git add Honkumi/Shared/Services/PrintSettingSampleManifest.swift \
  HonkumiTests/PrintSettingSampleManifestTests.swift
git commit -m "Define recommended print sample manifest"
```

---

## Task 2: 文字サイズ7.0〜20.0ptの27件manifestを追加する

**Files:**

- Modify: `Honkumi/Shared/Services/PrintSettingSampleManifest.swift`
- Modify: `HonkumiTests/PrintSettingSampleManifestTests.swift`

**Produces:**

- `PrintSettingSampleManifest.fontSizeCases()`

### Steps

- [ ] 1. 次の失敗テストを追加する。

```swift
func testFontSizeManifestContainsEveryHalfPoint() {
    let cases = PrintSettingSampleManifest.fontSizeCases()
    let sizes = cases.map(\.document.settings.fontSize)

    XCTAssertEqual(cases.count, 27)
    XCTAssertEqual(sizes, (14...40).map { CGFloat($0) / 2 })
    XCTAssertEqual(Set(cases.map(\.fileName)).count, 27)
}

func testFontSizeCasesUseManualA6Settings() {
    for sample in PrintSettingSampleManifest.fontSizeCases() {
        XCTAssertEqual(sample.document.settings.pageSize, .a6)
        XCTAssertFalse(sample.document.settings.useRecommendedTypography)
        XCTAssertFalse(sample.document.settings.useRecommendedMargins)
        XCTAssertTrue(sample.fileName.contains(
            String(format: "%.1fpt", Double(sample.document.settings.fontSize))
        ))
    }
}
```

- [ ] 2. `fontSizeCases`未定義で失敗することを確認する。

- [ ] 3. half-point列をfloating strideではなく整数から作る。

```swift
let fontSizes = (14...40).map { CGFloat($0) / 2 }
```

- [ ] 4. 各documentは`EditorSettings.default.validated`を起点に次を設定する。

```swift
settings.pageSize = .a6
settings.fontSize = fontSize
settings.useRecommendedTypography = false
settings.useRecommendedMargins = false
settings.showTableOfContents = false
settings.showChapterTitle = true
settings.isPageNumberEnabled = true
settings.pageNumberPosition = .outside
settings.colophon.isEnabled = false
```

characters/lines/marginsはdefaultの固定手動値を維持する。

- [ ] 5. 共通本文へ次をすべて含める。

```text
[[CHAPTER: 文字サイズ・章タイトル確認]]
本文の句読点。、縦書き括弧「」と三点リーダー……を確認します。
英数字 PDF 123 Next.js とノンブルを確認します。
未対応絵文字😀は白い四角一文字になります。
[[PAGE_BREAK]]
章タイトル上部、本文、ノンブルの大きさを比較する二ページ目です。
```

- [ ] 6. file nameは`文字サイズ_07.0pt_A6.pdf`から`文字サイズ_20.0pt_A6.pdf`まで1桁小数で作る。

- [ ] 7. 27件すべてのeffective settingsが指定font sizeを保持することをテストする。

```swift
XCTAssertEqual(
    RecommendedPrintSettings.effectiveSettings(for: sample.document).fontSize,
    sample.document.settings.fontSize
)
```

- [ ] 8. testsを成功させてコミットする。

```bash
git add Honkumi/Shared/Services/PrintSettingSampleManifest.swift \
  HonkumiTests/PrintSettingSampleManifestTests.swift
git commit -m "Define half-point font size sample manifest"
```

---

## Task 3: 2つのDebug環境変数を既存exporterへ接続する

**Files:**

- Modify: `Honkumi/Shared/Services/VerticalTypesettingSamplePDFExporter.swift`
- Modify: `HonkumiTests/PrintSettingSampleManifestTests.swift`

**Consumes:**

- Tasks 1–2のmanifest

### Steps

- [ ] 1. `exportIfRequested()`冒頭の単一guardを、次の3つのboolへ分解する。

```swift
let exportsVerticalSamples =
    environment["HONKUMI_EXPORT_VERTICAL_TYPESETTING_SAMPLES"] == "1"
let exportsRecommendedSamples =
    environment["HONKUMI_EXPORT_RECOMMENDED_SETTING_SAMPLES"] == "1"
let exportsFontSizeSamples =
    environment["HONKUMI_EXPORT_FONT_SIZE_SAMPLES"] == "1"

guard exportsVerticalSamples || exportsRecommendedSamples || exportsFontSizeSamples else {
    return
}
```

- [ ] 2. 既存`sampleDocuments`、colophon regression、all-font exportは`if exportsVerticalSamples { ... }`内へそのまま移し、既存の環境変数組合せと出力先を変えない。

- [ ] 3. manifest caseをexportする共通helperを追加する。

```swift
private static func export(
    _ samples: [PrintSettingSampleCase],
    exporter: BodyPDFExportService
) throws {
    for sample in samples {
        let directory = try outputDirectory(named: sample.outputDirectoryName)
        let temporaryURL = try exporter.export(
            document: sample.document,
            subscriptionStatus: .free
        )
        let outputURL = directory.appendingPathComponent(sample.fileName)
        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.copyItem(at: temporaryURL, to: outputURL)
        print("Exported print-setting sample PDF:", outputURL.path)
    }
}
```

- [ ] 4. 推奨サンプルは`Documents/RecommendedSettingSamples`、文字サイズは`Documents/FontSizeSamples`へ分離する。

- [ ] 5. 各flagだけがtrueのとき、対応manifest以外を呼ばない分岐を追加する。

```swift
if exportsRecommendedSamples {
    try export(
        PrintSettingSampleManifest.recommendedSettingCases().map(\.output),
        exporter: exporter
    )
}
if exportsFontSizeSamples {
    try export(PrintSettingSampleManifest.fontSizeCases(), exporter: exporter)
}
```

- [ ] 6. `HONKUMI_EXPORT_VERTICAL_TYPESETTING_EXIT=1`の終了処理は、選択された新サンプルの全copy完了後にだけ実行する。1ファイル途中でexitしない。

- [ ] 7. Debug buildとmanifest testsを実行する。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test -only-testing:HonkumiTests/PrintSettingSampleManifestTests
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi -configuration Debug \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' build
```

- [ ] 8. コミットする。

```bash
git add Honkumi/Shared/Services/VerticalTypesettingSamplePDFExporter.swift \
  HonkumiTests/PrintSettingSampleManifestTests.swift
git commit -m "Export print setting samples on debug flags"
```

---

## Task 4: 代表PDFのMediaBoxと埋め込み設定を自動検証する

**Files:**

- Create: `HonkumiTests/PrintSettingSamplePDFTests.swift`

### Steps

- [ ] 1. manifestからA6・新書・B6を1件ずつ、font 7.0/20.0ptを1件ずつ選び、`BodyPDFExportService.export`する統合テストを作る。

- [ ] 2. `CGPDFDocument`で各PDFのpage 1 media boxを読み、次のpoint寸法と0.5pt以内で一致することをassertする。

```swift
let expectedWidth = LayoutCalculator.millimetersToPoints(
    CGFloat(sample.document.settings.pageSize.widthMillimeters)
)
let expectedHeight = LayoutCalculator.millimetersToPoints(
    CGFloat(sample.document.settings.pageSize.heightMillimeters)
)
XCTAssertEqual(mediaBox.width, expectedWidth, accuracy: 0.5)
XCTAssertEqual(mediaBox.height, expectedHeight, accuracy: 0.5)
```

crop marksはoffなのでMediaBoxは用紙寸法そのものを期待する。

- [ ] 3. PDFKitのpage stringで、font sample共通本文の句読点、`PDF 123`、章タイトル、`□`が抽出でき、`😀`と`×`が含まれないことを確認する。

- [ ] 4. 推奨3サンプルについて、manifest file nameの実効設定と`RecommendedPrintSettings.effectiveSettings`を再parseせず直接比較する。ファイル名formatterをmanifest内の1関数に集約し、testも同じ出力を期待する。

- [ ] 5. 対象テストを実行する。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test -only-testing:HonkumiTests/PrintSettingSampleManifestTests \
  -only-testing:HonkumiTests/PrintSettingSamplePDFTests
```

- [ ] 6. コミットする。

```bash
git add HonkumiTests/PrintSettingSamplePDFTests.swift
git commit -m "Verify print setting sample PDFs"
```

---

## Task 5: Simulatorで全42ファイルを明示生成して確認する

**Files:**

- No source changes expected

### Steps

- [ ] 1. Debug appをbuild/installする。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi -configuration Debug \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -derivedDataPath /tmp/honkumi-sample-build build
xcrun simctl install 6C9E009C-5004-4C8D-8627-753D6CE09EBF \
  /tmp/honkumi-sample-build/Build/Products/Debug-iphonesimulator/Honkumi.app
```

- [ ] 2. 推奨設定サンプルだけを生成する。

```bash
SIMCTL_CHILD_HONKUMI_EXPORT_RECOMMENDED_SETTING_SAMPLES=1 \
SIMCTL_CHILD_HONKUMI_EXPORT_VERTICAL_TYPESETTING_EXIT=1 \
xcrun simctl launch --terminate-running-process \
  6C9E009C-5004-4C8D-8627-753D6CE09EBF jp.honkumi.Honkumi
```

- [ ] 3. 文字サイズサンプルだけを生成する。

```bash
SIMCTL_CHILD_HONKUMI_EXPORT_FONT_SIZE_SAMPLES=1 \
SIMCTL_CHILD_HONKUMI_EXPORT_VERTICAL_TYPESETTING_EXIT=1 \
xcrun simctl launch --terminate-running-process \
  6C9E009C-5004-4C8D-8627-753D6CE09EBF jp.honkumi.Honkumi
```

- [ ] 4. app containerを取得し、件数を確認する。

```bash
xcrun simctl get_app_container \
  6C9E009C-5004-4C8D-8627-753D6CE09EBF jp.honkumi.Honkumi data
```

返された絶対pathの`Documents/RecommendedSettingSamples`が15 PDF、`Documents/FontSizeSamples`が27 PDFであることを`find <exact-directory> -maxdepth 1 -name '*.pdf'`で確認する。件数確認時に他フォルダを再帰走査しない。

- [ ] 5. 各用紙・各ページ帯から少なくとも1ファイル、font 7.0/13.5/20.0ptをrenderし、次を目視確認する。

  - 用紙寸法、本文密度、余白がfile nameと一致。
  - font sizeが段階的に変化。
  - 章タイトル、本文、ノンブル、句読点、英数字が欠けない。
  - 未対応絵文字が白い四角1文字で、`×`が付かない。

- [ ] 6. この生成が重い場合でも通常起動には影響しないことを、環境変数なしで再起動して確認する。サンプル生成を自動テストや通常schemeのpre-actionへ追加しない。

---

## Task 6: リポジトリ全体の回帰と最終差分を検証する

**Files:**

- No planned source changes

### Steps

- [ ] 1. 既存の軽量回帰scriptsをすべて実行する。

```bash
swift scripts/check-initial-sample-work.swift
swift scripts/check-print-recommendations-and-page-numbers.swift
swift scripts/check-vertical-typesetting-regression.swift
```

- [ ] 2. 全XCTestを実行する。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' test
```

- [ ] 3. Debug、Staging、Release buildを実行する。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Honkumi.xcodeproj -scheme 'Honkumi Staging' -configuration Staging \
  -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi -configuration Release \
  -destination 'generic/platform=iOS Simulator' build
```

- [ ] 4. placeholder/TODOと要件漏れを検索する。

```bash
rg -n "TODO|FIXME|0000000000000000|□×|10 \\* 60|UserDefaultsPDFExportAdCooldownStore" \
  Honkumi HonkumiTests
```

Expected: 今回変更領域にmatchなし。既存無関係matchがある場合はpathと理由を記録し、勝手に変更しない。

- [ ] 5. 変更ファイルだけのdiffを確認し、ユーザーの既存変更を誤って削除していないことを確認する。

```bash
git status --short
git diff --check
git diff -- Honkumi HonkumiTests docs/superpowers
```

- [ ] 6. 完了前に`superpowers:verification-before-completion`を読み、最新のtest/build出力を根拠に完了判定する。

## Completion Evidence

- manifestは推奨15件、font size 27件を正確に返し、各新flagは単独実行できる。
- 代表PDFのMediaBox、text normalization、実効設定テストが成功している。
- 明示実行時に42 PDFを生成でき、通常起動とReleaseには生成負荷がない。
- 全tests、3 configuration builds、既存3 regression scriptsが成功している。
