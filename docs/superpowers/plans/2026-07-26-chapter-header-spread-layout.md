# Chapter Header Spread Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 長い章タイトルを、同じ見開きの2ページ上部へノド余白を空けて一続きに描画し、見開き使用時は警告、見開きにも収まらない場合はPDF出力を止めるエラーにする。

**Architecture:** ページ分割結果、物理ページ番号、実際のPDFフォントと本文幅から、ページIDごとの描画断片と警告/エラーを返す`ChapterHeaderLayoutPlanner`を新設する。プリフライトと通常PDF・見開きプレビューPDFは同じplanを消費し、別々の幅判定を持たない。見開きの表示順は既存PDFと同じ「奇数ページが左、直前の偶数ページが右」とし、Character境界でprefix/suffixへ分割する。

**Tech Stack:** Swift 5、UIKit、CoreGraphics、PDFKit、XCTest、XcodeBuild

## Global Constraints

- Depends on: `2026-07-26-preview-settings-and-paper-options.md`の用紙選択変更は先行してよいが、コード上の必須依存はない。
- 既存の章タイトル表示条件（bodyページ、`showChapterTitle`、そのページで章が開始していない）を維持する。
- ノド余白へ文字を描画しない。各断片は必ず該当ページの`bodyFrame`内に収める。
- 対向ページは同じ物理見開きにあり、bodyページで、同じ章タイトルを上部表示できる場合だけ利用する。
- プリフライトと描画で別の計測・分割を行わない。
- 警告は出力継続可、エラーは`PreflightResult.canContinue == false`とする。

---

## Task 1: Character境界の1ページ/見開き/overflow判定を実装する

**Files:**

- Create: `Honkumi/Shared/Services/ChapterHeaderLayoutPlanner.swift`
- Create: `HonkumiTests/ChapterHeaderLayoutPlannerTests.swift`

**Produces:**

- `ChapterHeaderFragment`
- `ChapterHeaderLayoutIssue`
- `ChapterHeaderLayoutPlan`
- `ChapterHeaderLayoutPlanner.split(...)`

### Steps

- [ ] 1. まず文字幅をCharacter数として扱う計測クロージャで、3結果を固定する失敗テストを書く。

```swift
import UIKit
@testable import Honkumi
import XCTest

final class ChapterHeaderLayoutPlannerTests: XCTestCase {
    private let measure: (String, UIFont) -> CGFloat = {
        CGFloat($0.count)
    }

    func testTitleThatFitsPrimaryPageUsesOneFragment() {
        let result = ChapterHeaderLayoutPlanner.split(
            title: "12345",
            firstAvailableWidth: 5,
            secondAvailableWidth: nil,
            font: .systemFont(ofSize: 10),
            measureWidth: measure
        )
        XCTAssertEqual(result, .single("12345"))
    }

    func testTitleThatNeedsSpreadSplitsOnCharacterBoundary() {
        let result = ChapterHeaderLayoutPlanner.split(
            title: "123456789",
            firstAvailableWidth: 5,
            secondAvailableWidth: 4,
            font: .systemFont(ofSize: 10),
            measureWidth: measure
        )
        XCTAssertEqual(result, .spread(first: "12345", second: "6789"))
    }

    func testTitleThatExceedsSpreadIsOverflow() {
        let result = ChapterHeaderLayoutPlanner.split(
            title: "1234567890",
            firstAvailableWidth: 5,
            secondAvailableWidth: 4,
            font: .systemFont(ofSize: 10),
            measureWidth: measure
        )
        XCTAssertEqual(result, .overflow)
    }
}
```

- [ ] 2. テストを実行し、型が未定義で失敗することを確認する。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test -only-testing:HonkumiTests/ChapterHeaderLayoutPlannerTests
```

- [ ] 3. 公開する値型を実装する。

```swift
nonisolated enum ChapterHeaderSplitResult: Equatable {
    case single(String)
    case spread(first: String, second: String)
    case overflow
}

nonisolated enum ChapterHeaderHorizontalAlignment: Equatable {
    case leading
    case trailing
}

nonisolated struct ChapterHeaderFragment: Equatable {
    let pageID: UUID
    let text: String
    let alignment: ChapterHeaderHorizontalAlignment
}

nonisolated enum ChapterHeaderLayoutIssue: Equatable {
    case spread(title: String, pageNumbers: [Int])
    case overflow(title: String, pageNumbers: [Int])
}

nonisolated struct ChapterHeaderLayoutPlan: Equatable {
    let fragmentsByPageID: [UUID: ChapterHeaderFragment]
    let issues: [ChapterHeaderLayoutIssue]
}
```

- [ ] 4. `split`はまず全文が第1幅に収まるか判定し、収まらない場合だけ`title.indices`のCharacter境界を後ろから走査する。prefixが第1幅以内かつsuffixが第2幅以内となる最長prefixを採用する。UTF-16 offsetで文字列を切らない。

```swift
static func split(
    title: String,
    firstAvailableWidth: CGFloat,
    secondAvailableWidth: CGFloat?,
    font: UIFont,
    measureWidth: (String, UIFont) -> CGFloat = defaultMeasure
) -> ChapterHeaderSplitResult
```

- [ ] 5. 空文字、結合文字列、絵文字を含むケースを追加し、断片を連結すると必ず元文字列になることをテストする。

- [ ] 6. 対象テストを成功させてコミットする。

```bash
git add Honkumi/Shared/Services/ChapterHeaderLayoutPlanner.swift \
  HonkumiTests/ChapterHeaderLayoutPlannerTests.swift
git commit -m "Add chapter header spread splitting"
```

---

## Task 2: PreviewPage列から物理見開き単位の共通planを作る

**Files:**

- Modify: `Honkumi/Shared/Services/ChapterHeaderLayoutPlanner.swift`
- Modify: `HonkumiTests/ChapterHeaderLayoutPlannerTests.swift`

**Consumes:**

- Task 1のsplit結果とplan値型
- `PDFPageNumberPolicy.physicalPageNumbers(forPageCount:settings:)`
- `LayoutCalculator.layout(for:pageNumber:)`

**Produces:**

- `ChapterHeaderLayoutPlanner.makePlan(pages:settings:subscriptionStatus:measureWidth:)`

### Steps

- [ ] 1. テスト用ページfactoryを追加する。

```swift
private func bodyPage(
    title: String?,
    startsTitle: Bool = false
) -> PreviewPage {
    PreviewPage(
        kind: .body,
        columns: ["本文"],
        startsAfterPageBreak: false,
        chapterTitle: title,
        chapterTitlesStartingOnPage: startsTitle ? [title].compactMap { $0 } : []
    )
}
```

- [ ] 2. 次のplanテストを先に追加する。

  - 1ページに収まるタイトルは、そのページIDの1断片だけでissueなし。
  - 1ページを超えるタイトルは、同じ見開きの奇数ページへprefix、偶数ページへsuffixを置き、`.spread` issueが1件。
  - prefix側は`.trailing`、suffix側は`.leading`でノドの両側に接する。
  - 合計幅超過は断片なしで`.overflow`。
  - 対向ページがない、別章、章開始ページ、TOC、colophonのいずれも`.overflow`。
  - 同じ章の長いタイトルが次の見開きでも続く場合は、見開きごとに一度だけsplitする。

- [ ] 3. `makePlan`未定義で失敗することを確認する。

- [ ] 4. plannerの候補条件を一箇所に実装する。

```swift
private static func eligibleTitle(on page: PreviewPage, settings: EditorSettings) -> String? {
    guard settings.showChapterTitle,
          page.kind == .body,
          let title = page.chapterTitle,
          !title.isEmpty,
          !page.chapterTitlesStartingOnPage.contains(title) else {
        return nil
    }
    return PrintTextNormalizer.normalize(title, location: .title).text
}
```

実際の正規化API名は現行`PrintTextNormalizer`に合わせ、Task 4の絵文字変更前でも既存の同一APIを使う。

- [ ] 5. 物理ページ番号は`PDFPageNumberPolicy.physicalPageNumbers`から取得する。見開きキーと表示順を次で統一する。

```swift
private static func spreadLeftPageNumber(containing physicalPageNumber: Int) -> Int {
    physicalPageNumber.isMultiple(of: 2)
        ? physicalPageNumber + 1
        : physicalPageNumber
}
```

同じキーのページを「奇数（左）→偶数（右）」で並べる。blank相当の物理ページは対向ページなしとして扱う。

- [ ] 6. 各ページの使用可能幅は、その物理ページと同じ偶奇を持つ`PageLayout.bodyFrame.width`を使用する。フォントは現行`drawChapterTitle`と同じ次の定義をplanner内の共通関数に移す。

```swift
let fontSize = max(layout.fontSize * 0.8, 6)
let font = AppFontCatalog.uiFont(
    selectedFontId: settings.selectedFontId,
    size: fontSize,
    isAdditionalFontPackUnlocked: subscriptionStatus == .paid
)
```

既存`BodyPDFExportService.pdfFont`と同じ呼び出しであり、このフォント生成をplannerの`font(for:settings:subscriptionStatus:)`へ移し、rendererも同じ関数を使う。plannerとrendererへ別々のfallbackを残さない。

- [ ] 7. 片側で全文が収まる場合は従来どおり各対象ページに全文を置く。片側で収まらない最初の対象を見つけた場合は同じ見開きの2ページをclaimし、左prefix/右suffixを1組だけ置く。claim済みページは同じ見開きで再処理しない。

- [ ] 8. 実フォントで`fragment width <= bodyFrame.width`を確認する境界テストを追加する。

- [ ] 9. 対象テストを実行してコミットする。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test -only-testing:HonkumiTests/ChapterHeaderLayoutPlannerTests
git add Honkumi/Shared/Services/ChapterHeaderLayoutPlanner.swift \
  HonkumiTests/ChapterHeaderLayoutPlannerTests.swift
git commit -m "Plan chapter headers by physical spread"
```

---

## Task 3: 通常PDFと見開きプレビューを共通planで描画する

**Files:**

- Modify: `Honkumi/Shared/Services/PDFExportService.swift`
- Modify: `HonkumiTests/ChapterHeaderLayoutPlannerTests.swift`
- Create: `HonkumiTests/ChapterHeaderPDFRenderingTests.swift`

**Consumes:**

- Task 2の`ChapterHeaderLayoutPlan`

### Steps

- [ ] 1. `BodyPDFExportService`が出力したPDFをPDFKitで読み、短いタイトルは1ページ、長いタイトルは同じ見開きの2ページから断片として抽出できる統合テストを先に追加する。テスト用本文は明示的な改ページタグを使い、目次・奥付をoffにして物理ページを安定させる。

- [ ] 2. 現在のrendererは長いタイトル全文を各ページへ描くため、長いタイトルの抽出期待またはplanner一致期待が失敗することを確認する。

- [ ] 3. `BodyPDFExportService.export`と`exportPreviewPDF`でpagination後に一度だけplanを作る。

```swift
let chapterHeaderPlan = ChapterHeaderLayoutPlanner.makePlan(
    pages: pages,
    settings: settings,
    subscriptionStatus: subscriptionStatus
)
```

- [ ] 4. normal/spreadの両描画経路へ同じplanを引き回す。`draw`の引数を次の形へ変える。

```swift
private func draw(
    _ page: PreviewPage,
    displayedPageNumber: Int?,
    showsPoweredByHonkumi: Bool,
    subscriptionStatus: SubscriptionStatus,
    chapterHeaderPlan: ChapterHeaderLayoutPlan,
    in layout: PageLayout
)
```

- [ ] 5. 既存の章タイトル条件判定と`drawChapterTitle(chapterTitle, ...)`を削除し、page IDのfragmentだけを描く。

```swift
if let fragment = chapterHeaderPlan.fragmentsByPageID[page.id] {
    drawChapterTitle(
        fragment,
        isAdditionalFontPackUnlocked: subscriptionStatus == .paid,
        in: layout
    )
}
```

- [ ] 6. 描画関数は必ずbodyFrame内へ収め、alignmentを次のように適用する。

```swift
let x: CGFloat
switch fragment.alignment {
case .leading:
    x = layout.bodyFrame.minX
case .trailing:
    x = layout.bodyFrame.maxX - size.width
}
let boundedX = min(max(x, layout.bodyFrame.minX), layout.bodyFrame.maxX - size.width)
```

単一ページfragmentのalignmentは従来の偶奇配置をplannerが設定する。見開きの左断片はtrailing、右断片はleadingとし、bodyFrame間のノド余白には描かない。Y座標とfontはplannerの共通typographyから取得する。

- [ ] 7. `ChapterHeaderPDFRenderingTests`で次を確認する。

  - PDFページ数が期待どおり。
  - 長いtitleの2断片を連結すると正規化済みtitleに一致。
  - 両断片が別々の同一見開きページから抽出される。
  - 通常PDFとspread preview PDFが同じfragment文字列を持つ。

- [ ] 8. 対象テストと既存縦書き回帰テストを実行する。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test -only-testing:HonkumiTests/ChapterHeaderLayoutPlannerTests \
  -only-testing:HonkumiTests/ChapterHeaderPDFRenderingTests
swift scripts/check-vertical-typesetting-regression.swift
```

- [ ] 9. コミットする。

```bash
git add Honkumi/Shared/Services/PDFExportService.swift \
  HonkumiTests/ChapterHeaderLayoutPlannerTests.swift \
  HonkumiTests/ChapterHeaderPDFRenderingTests.swift
git commit -m "Render chapter headers across one spread"
```

---

## Task 4: 共通planの警告とエラーをプリフライトへ追加する

**Files:**

- Modify: `Honkumi/Shared/Services/PDFPreflightService.swift`
- Create: `HonkumiTests/PDFPreflightChapterHeaderTests.swift`

**Consumes:**

- Task 2の`ChapterHeaderLayoutPlanner.makePlan`

### Steps

- [ ] 1. 短いタイトル、見開きタイトル、overflow、対向ページなしの4種類を作るプリフライトテストを先に追加する。

```swift
func testSinglePageChapterHeaderAddsNoSpreadIssue()
func testSpreadChapterHeaderAddsContinuableWarning()
func testOverflowChapterHeaderAddsBlockingError()
func testMissingCompanionPageAddsBlockingError()
```

警告テストの期待値:

```swift
let issue = try XCTUnwrap(result.issues.first {
    $0.id.hasPrefix("pdf.chapterHeader.spread.")
})
XCTAssertEqual(issue.severity, .warning)
XCTAssertEqual(issue.title, "章タイトルが見開きにまたがります")
XCTAssertTrue(issue.message.contains(title))
XCTAssertTrue(issue.message.contains("ページ"))
XCTAssertTrue(result.canContinue)
```

エラーテストではtitleが`章タイトルが見開きに収まりません`、`result.canContinue == false`を期待する。

- [ ] 2. テストを実行し、issueが存在せず失敗することを確認する。

- [ ] 3. `checkChapterHeaderLayout`を独立メソッドとして追加し、`check(...)`から呼ぶ。

```swift
checkChapterHeaderLayout(
    settings: effectiveSettings,
    pages: pages,
    subscriptionStatus: subscriptionStatus,
    into: &issues
)
```

- [ ] 4. `ChapterHeaderLayoutPlan.issues`を1件ずつ`PreflightIssue`へ変換する。

```swift
case let .spread(title, pageNumbers):
    issues.append(warning(
        id: stableChapterHeaderIssueID(kind: "spread", title: title, pages: pageNumbers),
        title: "章タイトルが見開きにまたがります",
        message: "「\(title)」を見開き \(pageNumbersText) ページに分けて表示します。",
        location: .init(type: .page, pageNumber: pageNumbers.first, characterRange: nil, settingKey: "showChapterTitle")
    ))
case let .overflow(title, pageNumbers):
    issues.append(error(
        id: stableChapterHeaderIssueID(kind: "overflow", title: title, pages: pageNumbers),
        title: "章タイトルが見開きに収まりません",
        message: "「\(title)」は見開き \(pageNumbersText) ページの上部に収まりません。章タイトルを短くしてください。",
        location: .init(type: .page, pageNumber: pageNumbers.first, characterRange: nil, settingKey: "showChapterTitle")
    ))
```

IDは`hashValue`を使わず、ページ番号とページIDまたは順序から毎回同じ文字列を組み立てる。

- [ ] 5. rendererとpreflightが同じplanになることをテストするため、テスト内でpagination結果を取得し、planのissue/fragmentとプリフライトissue/PDF抽出文字列を比較する。

- [ ] 6. 対象テストを実行する。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test -only-testing:HonkumiTests/PDFPreflightChapterHeaderTests \
  -only-testing:HonkumiTests/ChapterHeaderPDFRenderingTests
```

- [ ] 7. コミットする。

```bash
git add Honkumi/Shared/Services/PDFPreflightService.swift \
  HonkumiTests/PDFPreflightChapterHeaderTests.swift
git commit -m "Preflight chapter header spread overflow"
```

---

## Task 5: 境界値と目視回帰を検証する

**Files:**

- Modify only when a test exposes a defect: files from Tasks 1–4

### Steps

- [ ] 1. 実フォントごとに「本文幅と同じ」「0.1pt超える」「見開き合計と同じ」「0.1pt超える」ケースを追加する。無料fallbackフォントと有料フォントを少なくとも1種類ずつ確認する。

- [ ] 2. A6・新書・B6の3用紙で、短い/見開き/overflowの判定をテストする。

- [ ] 3. crop marks on/off、目次on/off、開始ページ番号による物理偶奇変更でも、同じ物理見開きだけを使うことをテストする。

- [ ] 4. 見開き警告を無視してPDFを生成し、次を目視確認する。

  - タイトルが左ページから右ページへ一続きに読める。
  - 中央のノド余白に文字がない。
  - 文字の上端、font、font sizeが左右で一致する。
  - 通常PDFの単ページ表示でも各断片がbodyFrameからはみ出さない。

- [ ] 5. overflowエラーがある状態でPDF出力操作が開始できないことを確認する。

- [ ] 6. 全関連テストとDebugビルドを実行する。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test -only-testing:HonkumiTests/ChapterHeaderLayoutPlannerTests \
  -only-testing:HonkumiTests/ChapterHeaderPDFRenderingTests \
  -only-testing:HonkumiTests/PDFPreflightChapterHeaderTests
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi -configuration Debug \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' build
```

## Completion Evidence

- 共通planの単体テスト、プリフライトテスト、PDF統合テストが成功している。
- 見開き使用時だけ継続可能警告、overflow/対向なしではブロッキングエラーになる。
- 通常PDFと見開きプレビューが同じ断片を描画し、ノド余白を侵食しない。
