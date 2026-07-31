# 全フォント・ノンブル無補正比較PDF Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** アプリ本体の挙動を変えず、フォント別サイズ補正を外した本文9pt・ノンブル8ptの比較PDFを全13フォント分生成し、検証済みZIPとして渡す。

**Architecture:** 現在のワークスペースを固定の一時ディレクトリへコピーし、一時コピー内のノンブルサイズ計算とDebugサンプル設定だけを変更する。iOS Simulatorで既存の全フォントサンプル生成処理を実行し、成果物だけを元ワークスペースの`output/pdf/`へコピーする。

**Tech Stack:** Swift 5、UIKit PDF Renderer、Xcode 26.6、iOS 26.5 Simulator、Poppler、pypdf、Pillow

## Global Constraints

- 元ワークスペースのアプリ本体Swiftコード、設定、既存成果物を変更しない。
- 本文フォント5種類とノンブル用フォント8種類の合計13 PDFを生成する。
- 本文サイズは9pt、本文下部のノンブルは8ptとする。
- 本文フォントとノンブル用フォントのノンブルPDFサイズ補正をすべて外す。
- 目次内ページ番号のフォント別サイズ補正も外す。
- 本文中の約物、長音、目次本文など、ノンブル以外の補正は維持する。
- 最終出力先は`output/pdf/AllFontSamples-NoAdjust-BodyMinus1pt-2026-07-31/`と、その同名ZIPとする。
- 一時ソースは`/private/tmp/honkumi-all-font-comparison-2026-07-31-924d6fc/`に限定する。
- ソース変更を残さない成果物生成作業なので、実装コミットの代わりに生成条件の静的確認、PDF構造検証、全ページ目視確認を完了条件とする。

---

### Task 1: 一時比較ソースを準備する

**Files:**

- Create: `/private/tmp/honkumi-all-font-comparison-2026-07-31-924d6fc/`
- Modify: `/private/tmp/honkumi-all-font-comparison-2026-07-31-924d6fc/Honkumi/Shared/Models/AppFont.swift`
- Modify: `/private/tmp/honkumi-all-font-comparison-2026-07-31-924d6fc/Honkumi/Shared/Services/VerticalTypesettingSamplePDFExporter.swift`
- Preserve: `/Users/orca/Projects/Honkumi/Honkumi/Shared/Models/AppFont.swift`
- Preserve: `/Users/orca/Projects/Honkumi/Honkumi/Shared/Services/VerticalTypesettingSamplePDFExporter.swift`

**Interfaces:**

- Consumes: `AppFontCatalog.pdfPageNumberFontSize(...)`、`AppFontCatalog.pdfTableOfContentsPageNumberFontSize(...)`、`VerticalTypesettingSamplePDFExporter.exportAllFontSamples(...)`
- Produces: ノンブル補正を適用せず、全13サンプルで本文9pt・本文下部ノンブル8ptを指定する一時Debugソース

- [ ] **Step 1: 元ワークスペースの基準状態を記録する**

Run:

```bash
git -C /Users/orca/Projects/Honkumi status --short
git -C /Users/orca/Projects/Honkumi diff -- Honkumi/Shared/Models/AppFont.swift Honkumi/Shared/Services/VerticalTypesettingSamplePDFExporter.swift
```

Expected: 既存のユーザー差分は記録するが、対象2ファイルに未コミット差分はない。

- [ ] **Step 2: 固定一時ディレクトリへソースをコピーする**

Run:

```bash
test ! -e /private/tmp/honkumi-all-font-comparison-2026-07-31-924d6fc
mkdir /private/tmp/honkumi-all-font-comparison-2026-07-31-924d6fc
rsync -a \
  --exclude .git \
  --exclude output \
  --exclude artifacts \
  --exclude tmp \
  --exclude DerivedData \
  /Users/orca/Projects/Honkumi/ \
  /private/tmp/honkumi-all-font-comparison-2026-07-31-924d6fc/
```

Expected: 一時ディレクトリにXcodeプロジェクトとソースがあり、元ワークスペースは未変更。

- [ ] **Step 3: 一時コピーのノンブルサイズ計算だけを無補正化する**

Modify `AppFont.swift`の2関数を次の実装にする。

```swift
static func pdfPageNumberFontSize(
    pageNumberFontId: String?,
    bodyFontId: String,
    baseSize: CGFloat,
    isPageNumberFontUnlocked: Bool
) -> CGFloat {
    max(baseSize, 6)
}

static func pdfTableOfContentsPageNumberFontSize(
    pageNumberFontId: String?,
    bodyFontId: String,
    baseSize: CGFloat,
    glyphScale: CGFloat,
    isPageNumberFontUnlocked: Bool
) -> CGFloat {
    max(baseSize * glyphScale, 1)
}
```

Expected: フォント選択とフォールバック処理は維持され、ページ番号に加算されるフォント別deltaだけが適用されない。

- [ ] **Step 4: 一時コピーの全フォントサンプルを本文9pt・ノンブル8ptへ固定する**

`VerticalTypesettingSamplePDFExporter.exportAllFontSamples(...)`の本文フォント用ループとノンブル用ループの両方で、既存の`pageNumberSize`固定値を次へ置き換える。

```swift
document.settings.useRecommendedTypography = false
document.settings.pageNumberSize = max(
    document.settings.fontSize - 1,
    EditorSettings.pageNumberSizeRange.lowerBound
)
```

Expected: `sampleDocument(...)`の本文9ptが推奨設定で上書きされず、13件すべてで本文下部のノンブル設定が8ptになる。

- [ ] **Step 5: 一時コピーの差分を静的検証する**

Run:

```bash
diff -u \
  /Users/orca/Projects/Honkumi/Honkumi/Shared/Models/AppFont.swift \
  /private/tmp/honkumi-all-font-comparison-2026-07-31-924d6fc/Honkumi/Shared/Models/AppFont.swift
diff -u \
  /Users/orca/Projects/Honkumi/Honkumi/Shared/Services/VerticalTypesettingSamplePDFExporter.swift \
  /private/tmp/honkumi-all-font-comparison-2026-07-31-924d6fc/Honkumi/Shared/Services/VerticalTypesettingSamplePDFExporter.swift
```

Expected: 差分はStep 3とStep 4だけ。アプリ本体のフォント一覧、描画、組版、本文補正には差分がない。

---

### Task 2: iOS Simulatorで13 PDFを生成する

**Files:**

- Build: `/private/tmp/honkumi-all-font-comparison-2026-07-31-924d6fc/Honkumi.xcodeproj`
- Create: `/private/tmp/honkumi-all-font-comparison-2026-07-31-924d6fc/DerivedData/`
- Create: iOS Simulator app container `Documents/AllFontSamples/`
- Create: `/Users/orca/Projects/Honkumi/output/pdf/AllFontSamples-NoAdjust-BodyMinus1pt-2026-07-31/`

**Interfaces:**

- Consumes: Task 1の一時Debugソース、Simulator `6C9E009C-5004-4C8D-8627-753D6CE09EBF`、bundle ID `jp.honkumi.Honkumi`
- Produces: 元ワークスペース内の比較用13 PDF

- [ ] **Step 1: 一時コピーをSimulator向けにビルドする**

Run:

```bash
xcodebuild \
  -project /private/tmp/honkumi-all-font-comparison-2026-07-31-924d6fc/Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  -derivedDataPath /private/tmp/honkumi-all-font-comparison-2026-07-31-924d6fc/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 2: Simulatorを起動して比較アプリをインストールする**

Run:

```bash
xcrun simctl boot 6C9E009C-5004-4C8D-8627-753D6CE09EBF
xcrun simctl bootstatus 6C9E009C-5004-4C8D-8627-753D6CE09EBF -b
xcrun simctl install \
  6C9E009C-5004-4C8D-8627-753D6CE09EBF \
  /private/tmp/honkumi-all-font-comparison-2026-07-31-924d6fc/DerivedData/Build/Products/Debug-iphonesimulator/Honkumi.app
```

Expected: SimulatorがBootedになり、`jp.honkumi.Honkumi`を取得できる。

- [ ] **Step 3: 全フォントサンプル生成フラグ付きで起動する**

Run:

```bash
SIMCTL_CHILD_HONKUMI_EXPORT_VERTICAL_TYPESETTING_SAMPLES=1 \
SIMCTL_CHILD_HONKUMI_EXPORT_ALL_FONT_SAMPLES=1 \
SIMCTL_CHILD_HONKUMI_EXPORT_VERTICAL_TYPESETTING_EXIT=1 \
xcrun simctl launch --console \
  6C9E009C-5004-4C8D-8627-753D6CE09EBF \
  jp.honkumi.Honkumi
```

Expected: ログに`Exported all-font sample PDF:`が13回出力され、プロセスが終了する。

- [ ] **Step 4: Simulator内の生成件数を確認する**

Run:

```bash
app_data_container="$(xcrun simctl get_app_container 6C9E009C-5004-4C8D-8627-753D6CE09EBF jp.honkumi.Honkumi data)"
find "$app_data_container/Documents/AllFontSamples" -maxdepth 1 -type f -name '*.pdf' -print
```

Expected: 本文フォント5件、ノンブル用フォント8件、合計13件。

- [ ] **Step 5: 最終出力ディレクトリへPDFをコピーする**

Run:

```bash
mkdir -p /Users/orca/Projects/Honkumi/output/pdf/AllFontSamples-NoAdjust-BodyMinus1pt-2026-07-31
app_data_container="$(xcrun simctl get_app_container 6C9E009C-5004-4C8D-8627-753D6CE09EBF jp.honkumi.Honkumi data)"
rsync -a \
  "$app_data_container/Documents/AllFontSamples/" \
  /Users/orca/Projects/Honkumi/output/pdf/AllFontSamples-NoAdjust-BodyMinus1pt-2026-07-31/
```

Expected: 最終出力ディレクトリ直下に13 PDFがある。

---

### Task 3: PDF構造と全ページ描画を検証する

**Files:**

- Read: `/Users/orca/Projects/Honkumi/output/pdf/AllFontSamples-NoAdjust-BodyMinus1pt-2026-07-31/*.pdf`
- Create: `/Users/orca/Projects/Honkumi/tmp/pdfs/validate_all_font_comparison.py`
- Create: `/Users/orca/Projects/Honkumi/tmp/pdfs/make_all_font_contact_sheets.py`
- Create: `/Users/orca/Projects/Honkumi/tmp/pdfs/all-font-comparison-rendered/`
- Create: `/Users/orca/Projects/Honkumi/tmp/pdfs/all-font-comparison-contact-sheets/`

**Interfaces:**

- Consumes: Task 2の13 PDF
- Produces: ファイル名、ページ数、PDF再読込、全ページレンダリング、目視検証の証跡

- [ ] **Step 1: PDF検証スクリプトを作成する**

Python executable:

```text
/Users/orca/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3
```

Create `validate_all_font_comparison.py` with:

```python
from pathlib import Path
import unicodedata

from pypdf import PdfReader


root = Path(
    "/Users/orca/Projects/Honkumi/output/pdf/"
    "AllFontSamples-NoAdjust-BodyMinus1pt-2026-07-31"
)
expected_names = {
    "本文フォント BIZ UD明朝.pdf",
    "本文フォント BIZ UDゴシック.pdf",
    "本文フォント しっぽり明朝.pdf",
    "本文フォント Zen Old Mincho.pdf",
    "本文フォント M PLUS 1.pdf",
    "ノンブルフォント Love Light.pdf",
    "ノンブルフォント Dancing Script.pdf",
    "ノンブルフォント Pacifico.pdf",
    "ノンブルフォント Great Vibes.pdf",
    "ノンブルフォント Caveat.pdf",
    "ノンブルフォント Homemade Apple.pdf",
    "ノンブルフォント Hachi Maru Pop.pdf",
    "ノンブルフォント Cherry Bomb One.pdf",
}
pdf_paths = sorted(root.glob("*.pdf"))
actual_names = {
    unicodedata.normalize("NFC", path.name)
    for path in pdf_paths
}
if actual_names != expected_names:
    missing = sorted(expected_names - actual_names)
    extra = sorted(actual_names - expected_names)
    raise SystemExit(f"PDF filename mismatch: missing={missing}, extra={extra}")

media_boxes = set()
page_counts = {}
for pdf_path in pdf_paths:
    reader = PdfReader(str(pdf_path))
    if not reader.pages:
        raise SystemExit(f"PDF has no pages: {pdf_path.name}")
    page_counts[unicodedata.normalize("NFC", pdf_path.name)] = len(reader.pages)
    for page in reader.pages:
        media_boxes.add(
            (
                round(float(page.mediabox.width), 3),
                round(float(page.mediabox.height), 3),
            )
        )

if len(media_boxes) != 1:
    raise SystemExit(f"Page-size mismatch: {sorted(media_boxes)}")

print(f"Validated {len(pdf_paths)} PDFs")
print(f"Page size: {next(iter(media_boxes))}")
for name, count in sorted(page_counts.items()):
    print(f"{count:02d} pages  {name}")
```

Expected: スクリプトに13件の完全な期待ファイル名、PDF再読込、ページ数、ページサイズ検証が含まれる。

- [ ] **Step 2: pypdfとpdfinfoで全PDFを再読込する**

Run:

```bash
/Users/orca/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 \
  /Users/orca/Projects/Honkumi/tmp/pdfs/validate_all_font_comparison.py
find \
  /Users/orca/Projects/Honkumi/output/pdf/AllFontSamples-NoAdjust-BodyMinus1pt-2026-07-31 \
  -maxdepth 1 -type f -name '*.pdf' -print0 |
while IFS= read -r -d '' pdf_path; do
  /Users/orca/.cache/codex-runtimes/codex-primary-runtime/dependencies/bin/override/pdfinfo \
    "$pdf_path"
done
```

Expected: 13 PDFすべてが例外なく開き、各`Pages`が1以上、ページサイズが全件で一致する。

- [ ] **Step 3: 全PDFの全ページをPNGへレンダリングする**

Run:

```bash
mkdir -p /Users/orca/Projects/Honkumi/tmp/pdfs/all-font-comparison-rendered
find \
  /Users/orca/Projects/Honkumi/output/pdf/AllFontSamples-NoAdjust-BodyMinus1pt-2026-07-31 \
  -maxdepth 1 -type f -name '*.pdf' -print0 |
while IFS= read -r -d '' pdf_path; do
  pdf_stem="$(basename "$pdf_path" .pdf)"
  page_directory="/Users/orca/Projects/Honkumi/tmp/pdfs/all-font-comparison-rendered/$pdf_stem"
  mkdir -p "$page_directory"
  /Users/orca/.cache/codex-runtimes/codex-primary-runtime/dependencies/bin/override/pdftoppm \
    -png -r 120 \
    "$pdf_path" \
    "$page_directory/page"
done
```

Expected: 各PDFのページ数と同数のPNGが生成され、Popplerエラーがない。

- [ ] **Step 4: 13件のコンタクトシートを作成する**

Create `make_all_font_contact_sheets.py` with:

```python
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


render_root = Path(
    "/Users/orca/Projects/Honkumi/tmp/pdfs/all-font-comparison-rendered"
)
output_root = Path(
    "/Users/orca/Projects/Honkumi/tmp/pdfs/"
    "all-font-comparison-contact-sheets"
)
output_root.mkdir(parents=True, exist_ok=True)
font = ImageFont.truetype(
    "/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc",
    24,
)
target_width = 600
gap = 24
title_height = 64

for pdf_directory in sorted(path for path in render_root.iterdir() if path.is_dir()):
    rendered_pages = []
    for page_path in sorted(pdf_directory.glob("page-*.png")):
        with Image.open(page_path) as source:
            source = source.convert("RGB")
            target_height = round(source.height * target_width / source.width)
            rendered_pages.append(
                source.resize((target_width, target_height), Image.Resampling.LANCZOS)
            )
    if not rendered_pages:
        raise SystemExit(f"No rendered pages: {pdf_directory.name}")

    sheet_height = (
        title_height
        + sum(page.height for page in rendered_pages)
        + gap * (len(rendered_pages) - 1)
    )
    sheet = Image.new("RGB", (target_width, sheet_height), "white")
    draw = ImageDraw.Draw(sheet)
    draw.text((16, 16), pdf_directory.name, font=font, fill="black")
    y = title_height
    for page in rendered_pages:
        sheet.paste(page, (0, y))
        y += page.height + gap
    sheet.save(output_root / f"{pdf_directory.name}.png")

print(f"Created {len(list(output_root.glob('*.png')))} contact sheets")
```

Run:

```bash
/Users/orca/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 \
  /Users/orca/Projects/Honkumi/tmp/pdfs/make_all_font_contact_sheets.py
```

Expected: `/Users/orca/Projects/Honkumi/tmp/pdfs/all-font-comparison-contact-sheets/`に13 PNG。

- [ ] **Step 5: 13コンタクトシートを目視確認する**

Inspect every contact sheet at high detail.

Expected:

- 本文下部のノンブルが全ページで読み取れる。
- 目次ページ番号の欠け、重なり、文字化けがない。
- 本文、章見出し、奥付に欠けやページ外へのはみ出しがない。
- 13種類で本文組版とページ数が一致し、比較対象以外のレイアウト差がない。

---

### Task 4: ZIP化、元ワークスペース確認、後片付けを行う

**Files:**

- Create: `/Users/orca/Projects/Honkumi/output/pdf/AllFontSamples-NoAdjust-BodyMinus1pt-2026-07-31.zip`
- Preserve: `/Users/orca/Projects/Honkumi/Honkumi/`
- Delete after verification: `/private/tmp/honkumi-all-font-comparison-2026-07-31-924d6fc/`
- Delete after verification: `/Users/orca/Projects/Honkumi/tmp/pdfs/validate_all_font_comparison.py`
- Delete after verification: `/Users/orca/Projects/Honkumi/tmp/pdfs/make_all_font_contact_sheets.py`
- Delete after verification: `/Users/orca/Projects/Honkumi/tmp/pdfs/all-font-comparison-rendered/`
- Delete after verification: `/Users/orca/Projects/Honkumi/tmp/pdfs/all-font-comparison-contact-sheets/`

**Interfaces:**

- Consumes: Task 3で検証済みの13 PDF
- Produces: 検証済みZIPと、アプリ本体に追加差分がない最終ワークスペース

- [ ] **Step 1: 13 PDFをZIPへまとめる**

Run:

```bash
cd /Users/orca/Projects/Honkumi/output/pdf
zip -r AllFontSamples-NoAdjust-BodyMinus1pt-2026-07-31.zip \
  AllFontSamples-NoAdjust-BodyMinus1pt-2026-07-31
```

Expected: ZIPが作成される。

- [ ] **Step 2: ZIP内容を検証する**

Run:

```bash
unzip -t /Users/orca/Projects/Honkumi/output/pdf/AllFontSamples-NoAdjust-BodyMinus1pt-2026-07-31.zip
unzip -Z1 /Users/orca/Projects/Honkumi/output/pdf/AllFontSamples-NoAdjust-BodyMinus1pt-2026-07-31.zip
```

Expected: CRCエラーなし。ディレクトリ項目を除きPDFが13件。

- [ ] **Step 3: 元ワークスペースのアプリ本体差分を再確認する**

Run:

```bash
git -C /Users/orca/Projects/Honkumi diff -- Honkumi/Shared/Models/AppFont.swift Honkumi/Shared/Services/VerticalTypesettingSamplePDFExporter.swift
git -C /Users/orca/Projects/Honkumi status --short
```

Expected: 対象2ファイルに新しい差分なし。既存のユーザー差分と`output/`以外に生成作業由来の差分なし。

- [ ] **Step 4: 検証用一時ファイルを削除する**

Delete only these exact paths:

```text
/private/tmp/honkumi-all-font-comparison-2026-07-31-924d6fc/
/Users/orca/Projects/Honkumi/tmp/pdfs/validate_all_font_comparison.py
/Users/orca/Projects/Honkumi/tmp/pdfs/make_all_font_contact_sheets.py
/Users/orca/Projects/Honkumi/tmp/pdfs/all-font-comparison-rendered/
/Users/orca/Projects/Honkumi/tmp/pdfs/all-font-comparison-contact-sheets/
```

Expected: 最終成果物ディレクトリとZIPだけが残る。

- [ ] **Step 5: 最終成果物を報告する**

Report absolute clickable links to:

```text
/Users/orca/Projects/Honkumi/output/pdf/AllFontSamples-NoAdjust-BodyMinus1pt-2026-07-31/
/Users/orca/Projects/Honkumi/output/pdf/AllFontSamples-NoAdjust-BodyMinus1pt-2026-07-31.zip
```

Include: 13 PDF、本文9pt、ノンブル8pt、個別補正なし、全ページ画像検証済み、元アプリ本体コード変更なし。
