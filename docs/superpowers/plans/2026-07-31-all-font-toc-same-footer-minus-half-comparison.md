# 全フォント・目次同サイズ／ノンブル0.5pt小比較PDF Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** アプリ本体を変更せず、本文9pt、目次内ページ番号9pt、下部ノンブル8.5pt、フォント別サイズ補正なしの比較PDFを全13フォント分生成し、検証済みZIPとして渡す。

**Architecture:** ワークスペースを固定の一時ディレクトリへコピーし、一時コピー内のサイズ計算、Debugサンプル設定、ポータブル描画対策だけを変更する。iOS Simulatorで既存の全フォントサンプル生成処理を実行し、成果物だけを新しい output/pdf/ ディレクトリへコピーする。

**Tech Stack:** Swift 5、UIKit PDF Renderer、CoreText、Xcode 26.6、iOS 26.5 Simulator、Poppler、pypdf、Pillow、Python zipfile

## Global Constraints

- 元ワークスペースのアプリ本体Swiftコード、テスト、Xcodeプロジェクト設定、既存成果物を変更しない。
- 本文フォント5種類とノンブル用フォント8種類の合計13 PDFを生成する。
- 本文サイズは9pt、目次内ページ番号は実描画9pt、本文下部のノンブルは8.5ptとする。
- 下部ノンブルと目次内ページ番号のフォント別サイズ補正をすべて外す。
- 本文中の約物、長音、行送り、文字送り、配置など、比較対象以外の組版補正は維持する。
- 前回の output/pdf/AllFontSamples-NoAdjust-BodyMinus1pt-2026-07-31.zip を残す。
- 新版の最終出力先は output/pdf/AllFontSamples-NoAdjust-TOCSame-BodyMinus0.5pt-2026-07-31/ と、その同名ZIPとする。
- 一時ソースは /private/tmp/honkumi-all-font-toc-same-footer-minus-half-2026-07-31-5324f11/ に限定する。
- 比較用一時ソースには、U+30FB目次リーダーと同ポイントサイズのしっぽり明朝字形フォールバックを適用するが、元アプリへ反映しない。
- ZIP内の13個の日本語PDF名はNFC正規化し、UTF-8 general-purpose flag bit 11を設定する。

---

### Task 1: 比較用一時ソースをRED/GREENで準備する

**Files:**

- Create: /private/tmp/honkumi-all-font-toc-same-footer-minus-half-2026-07-31-5324f11/
- Create: /private/tmp/honkumi-all-font-toc-same-footer-minus-half-2026-07-31-5324f11/scripts/check-comparison-source-settings.py
- Modify: /private/tmp/honkumi-all-font-toc-same-footer-minus-half-2026-07-31-5324f11/Honkumi/Shared/Models/AppFont.swift
- Modify: /private/tmp/honkumi-all-font-toc-same-footer-minus-half-2026-07-31-5324f11/Honkumi/Shared/Services/VerticalTypesettingSamplePDFExporter.swift
- Modify: /private/tmp/honkumi-all-font-toc-same-footer-minus-half-2026-07-31-5324f11/Honkumi/Shared/Services/PDFExportService.swift
- Preserve: /Users/orca/Projects/Honkumi/Honkumi/

**Interfaces:**

- Consumes: AppFontCatalog.pdfPageNumberFontSize(...), AppFontCatalog.pdfTableOfContentsPageNumberFontSize(...), VerticalTypesettingSamplePDFExporter.exportAllFontSamples(...), BodyPDFExportService
- Produces: 本文9pt、目次番号9pt、下部ノンブル8.5ptを指定し、未解決フォント資源を作らない一時Debugソース

- [ ] **Step 1: 元ワークスペースの基準状態を記録する**

Run:

    git -C /Users/orca/Projects/Honkumi status --short
    git -C /Users/orca/Projects/Honkumi diff --name-only -- \
      Honkumi HonkumiTests HonkumiUITests \
      Honkumi.xcodeproj Honkumi.xcworkspace \
      Package.swift Package.resolved project.yml

Expected: 既存のユーザー差分は記録する。2つ目のコマンドは出力なし。

- [ ] **Step 2: 固定一時ディレクトリへ現在のソースをコピーする**

Run:

    test ! -e /private/tmp/honkumi-all-font-toc-same-footer-minus-half-2026-07-31-5324f11
    mkdir /private/tmp/honkumi-all-font-toc-same-footer-minus-half-2026-07-31-5324f11
    rsync -a \
      --exclude .git \
      --exclude output \
      --exclude artifacts \
      --exclude tmp \
      --exclude DerivedData \
      /Users/orca/Projects/Honkumi/ \
      /private/tmp/honkumi-all-font-toc-same-footer-minus-half-2026-07-31-5324f11/

Expected: 一時ディレクトリにHonkumi.xcodeprojと3つの対象Swiftファイルがある。元ワークスペースは未変更。

- [ ] **Step 3: 一時ソース条件の回帰チェッカーを作成する**

Create scripts/check-comparison-source-settings.py with:

    from pathlib import Path
    import re

    root = Path(
        "/private/tmp/"
        "honkumi-all-font-toc-same-footer-minus-half-2026-07-31-5324f11"
    )
    app_font = (root / "Honkumi/Shared/Models/AppFont.swift").read_text()
    sample_exporter = (
        root / "Honkumi/Shared/Services/VerticalTypesettingSamplePDFExporter.swift"
    ).read_text()
    pdf_exporter = (
        root / "Honkumi/Shared/Services/PDFExportService.swift"
    ).read_text()

    page_number_expression = """document.settings.pageNumberSize = max(
                    document.settings.fontSize - 0.5,
                    EditorSettings.pageNumberSizeRange.lowerBound
                )"""

    checks = {
        "footer size deltas disabled": "return max(baseSize, 6)" in app_font,
        "TOC scale and deltas disabled": "return max(baseSize, 1)" in app_font,
        "recommended typography disabled twice": (
            sample_exporter.count(
                "document.settings.useRecommendedTypography = false"
            ) == 2
        ),
        "8.5pt footer expression used twice": (
            sample_exporter.count(page_number_expression) == 2
        ),
        "CoreText imported": "import CoreText" in pdf_exporter,
        "portable U+30FB leader": bool(
            re.search(
                r'private func tableOfContentsLeader\([\s\S]*?\) -> String \{\s*"・"\s*\}',
                pdf_exporter,
            )
        ),
        "same-size explicit glyph fallback": (
            "!pdfFont(font, supports: glyph.text)" in pdf_exporter
            and 'selectedFontId: "shippori-mincho"' in pdf_exporter
            and "size: font.pointSize" in pdf_exporter
            and "CTFontGetGlyphsForCharacters" in pdf_exporter
        ),
    }

    failed = [name for name, passed in checks.items() if not passed]
    for name, passed in checks.items():
        print(f"{'PASS' if passed else 'FAIL'}  {name}")
    if failed:
        raise SystemExit(f"RESULT: FAIL ({len(failed)} checks): {failed}")
    print("RESULT: PASS")

- [ ] **Step 4: チェッカーを実行してREDを確認する**

Run:

    cd /private/tmp/honkumi-all-font-toc-same-footer-minus-half-2026-07-31-5324f11
    /Users/orca/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 \
      scripts/check-comparison-source-settings.py

Expected: exit 1。少なくともfooter size deltas disabled、TOC scale and deltas disabled、8.5pt footer expression used twiceがFAILする。

- [ ] **Step 5: 一時コピーのフォントサイズ計算を無補正化する**

Replace the two functions in temporary AppFont.swift with:

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
        max(baseSize, 1)
    }

Expected: 下部ノンブルは設定値をそのまま使い、目次内ページ番号は本文サイズをそのまま使う。glyphScaleと全フォント別deltaはこの比較ビルドに限って使わない。

- [ ] **Step 6: 13サンプルの本文9pt・ノンブル8.5ptを設定する**

In both loops of temporary VerticalTypesettingSamplePDFExporter.exportAllFontSamples(...), replace the fixed pageNumberSize assignment with:

    document.settings.useRecommendedTypography = false
    document.settings.pageNumberSize = max(
        document.settings.fontSize - 0.5,
        EditorSettings.pageNumberSizeRange.lowerBound
    )

Expected: sampleDocument(...)のfontSize = 9が維持され、本文フォント5件とノンブル用フォント8件の下部ノンブル設定が8.5になる。

- [ ] **Step 7: 一時コピーへポータブル描画対策を追加する**

Add import CoreText to temporary PDFExportService.swift.

Replace tableOfContentsLeader(...) with:

    private func tableOfContentsLeader(
        pageNumberFontId: String?,
        isPageNumberFontUnlocked: Bool
    ) -> String {
        "・"
    }

Immediately before return attributes in pdfAttributes(...), after the table-of-contents page-number font selection, add:

    if let font = attributes[.font] as? UIFont,
       !pdfFont(font, supports: glyph.text) {
        attributes[.font] = AppFontCatalog.uiFont(
            selectedFontId: "shippori-mincho",
            size: font.pointSize,
            isAdditionalFontPackUnlocked: true
        )
    }

Add beside the other private PDF font helpers:

    private func pdfFont(_ font: UIFont, supports text: String) -> Bool {
        var characters = Array(text.utf16)
        var glyphs = Array(repeating: CGGlyph(), count: characters.count)
        return CTFontGetGlyphsForCharacters(
            font as CTFont,
            &characters,
            &glyphs,
            characters.count
        )
    }

Expected: U+30FBリーダーは本文5フォントの埋め込み資源で描画され、欠落字形だけが同ポイントサイズのしっぽり明朝へ切り替わる。サイズと位置は変えない。

- [ ] **Step 8: 同じチェッカーを実行してGREENを確認する**

Run:

    cd /private/tmp/honkumi-all-font-toc-same-footer-minus-half-2026-07-31-5324f11
    /Users/orca/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 \
      scripts/check-comparison-source-settings.py

Expected: exit 0、7 checks PASS、RESULT: PASS。

- [ ] **Step 9: 一時差分と元ワークスペース保存を確認する**

Run:

    diff -u \
      /Users/orca/Projects/Honkumi/Honkumi/Shared/Models/AppFont.swift \
      /private/tmp/honkumi-all-font-toc-same-footer-minus-half-2026-07-31-5324f11/Honkumi/Shared/Models/AppFont.swift
    diff -u \
      /Users/orca/Projects/Honkumi/Honkumi/Shared/Services/VerticalTypesettingSamplePDFExporter.swift \
      /private/tmp/honkumi-all-font-toc-same-footer-minus-half-2026-07-31-5324f11/Honkumi/Shared/Services/VerticalTypesettingSamplePDFExporter.swift
    diff -u \
      /Users/orca/Projects/Honkumi/Honkumi/Shared/Services/PDFExportService.swift \
      /private/tmp/honkumi-all-font-toc-same-footer-minus-half-2026-07-31-5324f11/Honkumi/Shared/Services/PDFExportService.swift
    git -C /Users/orca/Projects/Honkumi diff --name-only -- \
      Honkumi HonkumiTests HonkumiUITests \
      Honkumi.xcodeproj Honkumi.xcworkspace \
      Package.swift Package.resolved project.yml

Expected: 一時差分はSteps 5-7だけ。最後のコマンドは出力なし。実装コミットは作成しない。

---

### Task 2: iOS Simulatorで新版13 PDFを生成する

**Files:**

- Build: /private/tmp/honkumi-all-font-toc-same-footer-minus-half-2026-07-31-5324f11/Honkumi.xcodeproj
- Create: /private/tmp/honkumi-all-font-toc-same-footer-minus-half-2026-07-31-5324f11/DerivedData/
- Create: iOS Simulator app container Documents/AllFontSamples/
- Create: /Users/orca/Projects/Honkumi/output/pdf/AllFontSamples-NoAdjust-TOCSame-BodyMinus0.5pt-2026-07-31/

**Interfaces:**

- Consumes: Task 1のGREEN一時ソース、Simulator 6C9E009C-5004-4C8D-8627-753D6CE09EBF、bundle ID jp.honkumi.Honkumi
- Produces: 元ワークスペース内の新版13 PDF

- [ ] **Step 1: 一時コピーをSimulator向けにビルドする**

Run:

    xcodebuild \
      -project /private/tmp/honkumi-all-font-toc-same-footer-minus-half-2026-07-31-5324f11/Honkumi.xcodeproj \
      -scheme Honkumi \
      -configuration Debug \
      -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
      -derivedDataPath /private/tmp/honkumi-all-font-toc-same-footer-minus-half-2026-07-31-5324f11/DerivedData \
      CODE_SIGNING_ALLOWED=NO \
      build

Expected: exit 0、BUILD SUCCEEDED。

- [ ] **Step 2: Simulatorを起動して比較アプリをインストールする**

Run:

    xcrun simctl boot 6C9E009C-5004-4C8D-8627-753D6CE09EBF
    xcrun simctl bootstatus 6C9E009C-5004-4C8D-8627-753D6CE09EBF -b
    xcrun simctl install \
      6C9E009C-5004-4C8D-8627-753D6CE09EBF \
      /private/tmp/honkumi-all-font-toc-same-footer-minus-half-2026-07-31-5324f11/DerivedData/Build/Products/Debug-iphonesimulator/Honkumi.app

Expected: SimulatorがBootedになり、インストールがexit 0。

- [ ] **Step 3: Simulator内のサンプル出力ディレクトリを空にする**

Run:

    app_data_container="$(xcrun simctl get_app_container \
      6C9E009C-5004-4C8D-8627-753D6CE09EBF \
      jp.honkumi.Honkumi data)"
    case "$app_data_container" in
      */Library/Developer/CoreSimulator/Devices/6C9E009C-5004-4C8D-8627-753D6CE09EBF/data/Containers/Data/Application/*) ;;
      *) exit 1 ;;
    esac
    sample_output_directory="$app_data_container/Documents/AllFontSamples"
    test "$sample_output_directory" = "$app_data_container/Documents/AllFontSamples"
    if [ -d "$sample_output_directory" ]; then
      rm -rf -- "$sample_output_directory"
    fi
    mkdir -p "$sample_output_directory"

Delete only the validated app container's exact Documents/AllFontSamples/ directory. Do not delete any other Simulator container path.

Expected: Documents/AllFontSamples/が空で存在する。

- [ ] **Step 4: 全フォントサンプル生成フラグ付きで起動する**

Run:

    SIMCTL_CHILD_HONKUMI_EXPORT_VERTICAL_TYPESETTING_SAMPLES=1 \
    SIMCTL_CHILD_HONKUMI_EXPORT_ALL_FONT_SAMPLES=1 \
    SIMCTL_CHILD_HONKUMI_EXPORT_VERTICAL_TYPESETTING_EXIT=1 \
    xcrun simctl launch --console \
      6C9E009C-5004-4C8D-8627-753D6CE09EBF \
      jp.honkumi.Honkumi

Expected: exit 0。ログにExported all-font sample PDF:が13回出力される。

- [ ] **Step 5: Simulator内の生成件数を確認する**

Run:

    app_data_container="$(xcrun simctl get_app_container \
      6C9E009C-5004-4C8D-8627-753D6CE09EBF \
      jp.honkumi.Honkumi data)"
    find "$app_data_container/Documents/AllFontSamples" \
      -mindepth 1 -maxdepth 1 -type f -name '*.pdf' -print

Expected: 本文フォント5件、ノンブル用フォント8件、合計13件。他のファイルなし。

- [ ] **Step 6: 新版出力ディレクトリへコピーする**

Run:

    app_data_container="$(xcrun simctl get_app_container \
      6C9E009C-5004-4C8D-8627-753D6CE09EBF \
      jp.honkumi.Honkumi data)"
    test ! -e /Users/orca/Projects/Honkumi/output/pdf/AllFontSamples-NoAdjust-TOCSame-BodyMinus0.5pt-2026-07-31
    mkdir -p /Users/orca/Projects/Honkumi/output/pdf/AllFontSamples-NoAdjust-TOCSame-BodyMinus0.5pt-2026-07-31
    rsync -a \
      "$app_data_container/Documents/AllFontSamples/" \
      /Users/orca/Projects/Honkumi/output/pdf/AllFontSamples-NoAdjust-TOCSame-BodyMinus0.5pt-2026-07-31/

Expected: 新版出力ディレクトリ直下に13 PDFだけがある。前回ZIPは存在したまま。

---

### Task 3: PDF構造、サイズ、フォント、全ページ描画を検証する

**Files:**

- Create: /Users/orca/Projects/Honkumi/tmp/pdfs/toc-same-footer-minus-half-20260731/validate_and_render.py
- Create: /Users/orca/Projects/Honkumi/tmp/pdfs/toc-same-footer-minus-half-20260731/make_contact_sheets.py
- Create: /Users/orca/Projects/Honkumi/tmp/pdfs/toc-same-footer-minus-half-20260731/rendered/
- Create: /Users/orca/Projects/Honkumi/tmp/pdfs/toc-same-footer-minus-half-20260731/contact-sheets/

**Interfaces:**

- Consumes: Task 2の新版13 PDF
- Produces: 13件・143ページ・本文9pt・目次番号9pt・下部ノンブル8.5pt・埋め込みフォント・全ページレンダーの検証証跡

- [ ] **Step 1: PDF検証・全ページレンダースクリプトを作成する**

Create validate_and_render.py with:

    from __future__ import annotations

    from pathlib import Path
    import logging
    import subprocess
    import unicodedata

    from PIL import Image
    from pypdf import PdfReader
    from pypdf.generic import ContentStream

    logging.getLogger("pypdf").setLevel(logging.ERROR)

    WORKSPACE = Path("/Users/orca/Projects/Honkumi")
    PDF_ROOT = (
        WORKSPACE
        / "output/pdf/AllFontSamples-NoAdjust-TOCSame-BodyMinus0.5pt-2026-07-31"
    )
    RENDER_ROOT = (
        WORKSPACE / "tmp/pdfs/toc-same-footer-minus-half-20260731/rendered"
    )
    PDFTOPPM = Path(
        "/Users/orca/.cache/codex-runtimes/codex-primary-runtime/"
        "dependencies/native/poppler/poppler/bin/pdftoppm"
    )
    PDFFONTS = Path(
        "/Users/orca/.cache/codex-runtimes/codex-primary-runtime/"
        "dependencies/native/poppler/poppler/bin/pdffonts"
    )

    EXPECTED_FONT = {
        "本文フォント BIZ UD明朝.pdf": ("BIZUDMincho-Regular", "BIZUDMincho-Regular"),
        "本文フォント BIZ UDゴシック.pdf": ("BIZUDGothic-Regular", "BIZUDGothic-Regular"),
        "本文フォント M PLUS 1.pdf": ("MPLUS1-Regular", "MPLUS1-Regular"),
        "本文フォント Zen Old Mincho.pdf": ("ZenOldMincho-Regular", "ZenOldMincho-Regular"),
        "本文フォント しっぽり明朝.pdf": ("ShipporiMincho-Regular", "ShipporiMincho-Regular"),
        "ノンブルフォント Love Light.pdf": ("BIZUDMincho-Regular", "LoveLight-Regular"),
        "ノンブルフォント Dancing Script.pdf": ("BIZUDMincho-Regular", "DancingScript-Regular"),
        "ノンブルフォント Pacifico.pdf": ("BIZUDMincho-Regular", "Pacifico-Regular"),
        "ノンブルフォント Great Vibes.pdf": ("BIZUDMincho-Regular", "GreatVibes-Regular"),
        "ノンブルフォント Caveat.pdf": ("BIZUDMincho-Regular", "Caveat-Regular"),
        "ノンブルフォント Homemade Apple.pdf": ("BIZUDMincho-Regular", "HomemadeApple-Regular"),
        "ノンブルフォント Hachi Maru Pop.pdf": ("BIZUDMincho-Regular", "HachiMaruPop-Regular"),
        "ノンブルフォント Cherry Bomb One.pdf": ("BIZUDMincho-Regular", "CherryBombOne-Regular"),
    }

    def nfc(value: str) -> str:
        return unicodedata.normalize("NFC", value)

    def unhashed_font_name(value: str) -> str:
        return value.split("+", 1)[-1]

    def font_name(page, resource_name: str) -> str:
        font = page["/Resources"]["/Font"][resource_name].get_object()
        return unhashed_font_name(str(font["/BaseFont"]).lstrip("/"))

    paths = list(PDF_ROOT.glob("*.pdf"))
    by_nfc = {nfc(path.name): path for path in paths}
    assert len(paths) == 13
    assert set(by_nfc) == set(EXPECTED_FONT)
    assert not [
        path for path in PDF_ROOT.iterdir()
        if not path.is_file() or path.suffix != ".pdf"
    ]

    RENDER_ROOT.mkdir(parents=True, exist_ok=False)
    total_pages = 0
    total_footers = 0
    total_toc_numbers = 0

    for pdf_index, name in enumerate(sorted(EXPECTED_FONT), start=1):
        path = by_nfc[name]
        body_font, page_number_font = EXPECTED_FONT[name]
        reader = PdfReader(str(path), strict=True)
        assert len(reader.pages) == 11

        listed = subprocess.run(
            [str(PDFFONTS), str(path)],
            check=True,
            capture_output=True,
            text=True,
        )
        assert listed.stderr == ""
        rows = [
            line.split()
            for line in listed.stdout.splitlines()[2:]
            if line.strip()
        ]
        assert rows and all(row[-5:-3] == ["yes", "yes"] for row in rows)
        listed_fonts = {unhashed_font_name(row[0]) for row in rows}
        expected_fonts = {body_font, page_number_font}
        if body_font in {
            "BIZUDMincho-Regular",
            "BIZUDGothic-Regular",
            "MPLUS1-Regular",
        }:
            expected_fonts.add("ShipporiMincho-Regular")
        assert listed_fonts == expected_fonts, (
            name,
            listed_fonts,
            expected_fonts,
        )

        toc_fonts = []
        for page_number, page in enumerate(reader.pages, start=1):
            assert (
                round(float(page.mediabox.width), 3),
                round(float(page.mediabox.height), 3),
            ) == (297.638, 419.528)
            assert "/C1" not in page["/Resources"].get("/Font", {})

            matrix = None
            selected_font = None
            body_runs = 0
            footers = []
            stream = ContentStream(page.get_contents(), reader)
            for operands, operator in stream.operations:
                if operator == b"Tm":
                    matrix = [float(value) for value in operands]
                elif operator == b"Tf":
                    selected_font = str(operands[0])
                elif operator in (b"Tj", b"TJ") and matrix and selected_font:
                    current_font = font_name(page, selected_font)
                    if (
                        abs(matrix[0] - 9.0) < 0.001
                        and abs(matrix[3] + 9.0) < 0.001
                        and current_font == body_font
                    ):
                        body_runs += 1
                    if (
                        abs(matrix[0] - 8.5) < 0.001
                        and abs(matrix[3] + 8.5) < 0.001
                        and matrix[5] > 380
                    ):
                        footers.append(current_font)
                    if (
                        page_number == 1
                        and abs(matrix[0] - 9.0) < 0.001
                        and abs(matrix[3] - 9.0) < 0.001
                        and current_font == page_number_font
                    ):
                        toc_fonts.append(current_font)

            assert body_runs > 0, (name, page_number, "missing 9pt body run")
            assert footers == [page_number_font], (
                name,
                page_number,
                footers,
            )
            total_footers += 1

            page_directory = RENDER_ROOT / f"{pdf_index:02d}-{nfc(path.stem)}"
            page_directory.mkdir(parents=True, exist_ok=True)
            prefix = page_directory / f"page-{page_number:02d}"
            rendered = subprocess.run(
                [
                    str(PDFTOPPM),
                    "-png",
                    "-r",
                    "180",
                    "-f",
                    str(page_number),
                    "-l",
                    str(page_number),
                    "-singlefile",
                    str(path),
                    str(prefix),
                ],
                capture_output=True,
                text=True,
            )
            assert rendered.returncode == 0, (
                name,
                page_number,
                rendered.stderr,
            )
            assert rendered.stderr == "", (
                name,
                page_number,
                rendered.stderr,
            )
            png = prefix.with_suffix(".png")
            assert png.stat().st_size > 0
            with Image.open(png) as image:
                image.verify()
            total_pages += 1

        assert len(toc_fonts) == 6, (name, toc_fonts)
        total_toc_numbers += len(toc_fonts)

    assert total_pages == 143
    assert total_footers == 143
    assert total_toc_numbers == 78
    print(
        "RESULT: PASS "
        "pdfs=13 pages=143 body9pt_pages=143 footers8.5pt=143 "
        "toc9pt=78 render_errors=0 fonts_embedded_subset=yes"
    )

- [ ] **Step 2: 検証・レンダーを実行する**

Run:

    /Users/orca/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 \
      /Users/orca/Projects/Honkumi/tmp/pdfs/toc-same-footer-minus-half-20260731/validate_and_render.py

Expected: exit 0、RESULT: PASS pdfs=13 pages=143 body9pt_pages=143 footers8.5pt=143 toc9pt=78 render_errors=0 fonts_embedded_subset=yes。

- [ ] **Step 3: 13件のコンタクトシートを作成する**

Create make_contact_sheets.py with:

    from pathlib import Path
    from PIL import Image, ImageDraw, ImageFont

    root = Path(
        "/Users/orca/Projects/Honkumi/"
        "tmp/pdfs/toc-same-footer-minus-half-20260731"
    )
    render_root = root / "rendered"
    output_root = root / "contact-sheets"
    output_root.mkdir(parents=True, exist_ok=False)
    font = ImageFont.truetype(
        "/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc",
        28,
    )
    cell_width = 480
    gap = 20
    title_height = 70

    directories = sorted(
        path for path in render_root.iterdir() if path.is_dir()
    )
    assert len(directories) == 13
    for directory in directories:
        page_paths = sorted(directory.glob("page-*.png"))
        assert len(page_paths) == 11
        pages = []
        for page_path in page_paths:
            with Image.open(page_path) as source:
                source = source.convert("RGB")
                height = round(source.height * cell_width / source.width)
                pages.append(
                    source.resize(
                        (cell_width, height),
                        Image.Resampling.LANCZOS,
                    )
                )

        columns = 4
        rows = 3
        cell_height = max(page.height for page in pages)
        sheet = Image.new(
            "RGB",
            (
                columns * cell_width + (columns - 1) * gap,
                title_height + rows * cell_height + (rows - 1) * gap,
            ),
            "white",
        )
        draw = ImageDraw.Draw(sheet)
        draw.text((12, 14), directory.name, font=font, fill="black")
        for index, page in enumerate(pages):
            x = (index % columns) * (cell_width + gap)
            y = title_height + (index // columns) * (cell_height + gap)
            sheet.paste(page, (x, y))
        sheet.save(output_root / f"{directory.name}.png")

    print(
        "RESULT: PASS "
        f"contact_sheets={len(list(output_root.glob('*.png')))}"
    )

Run:

    /Users/orca/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 \
      /Users/orca/Projects/Honkumi/tmp/pdfs/toc-same-footer-minus-half-20260731/make_contact_sheets.py

Expected: exit 0、13 contact sheets。

- [ ] **Step 4: 全13コンタクトシートを目視確認する**

Use view_image at original detail for every PNG in:

    /Users/orca/Projects/Honkumi/tmp/pdfs/toc-same-footer-minus-half-20260731/contact-sheets/

Also inspect every page 1 and page 10 PNG directly from rendered/.

Expected:

- 全13件の目次に見出し、6つの項目、連続したリーダー、ページ番号2, 4, 5, 6, 7, 10がある。
- 目次番号は本文と同程度の見た目で、欠け、重なり、クリッピングがない。
- 全143ページの下部ノンブルが読み取れ、8つのノンブル用フォントが区別できる。
- 本文、章見出し、約物、長音、奥付に欠け、重なり、ページ外へのはみ出しがない。

---

### Task 4: UTF-8 ZIP化、元ワークスペース確認、後片付けを行う

**Files:**

- Create: /Users/orca/Projects/Honkumi/tmp/pdfs/toc-same-footer-minus-half-20260731/write_and_verify_zip.py
- Create: /Users/orca/Projects/Honkumi/output/pdf/AllFontSamples-NoAdjust-TOCSame-BodyMinus0.5pt-2026-07-31.zip
- Preserve: /Users/orca/Projects/Honkumi/output/pdf/AllFontSamples-NoAdjust-BodyMinus1pt-2026-07-31.zip
- Delete after verification: /private/tmp/honkumi-all-font-toc-same-footer-minus-half-2026-07-31-5324f11/
- Delete after verification: /Users/orca/Projects/Honkumi/tmp/pdfs/toc-same-footer-minus-half-20260731/

**Interfaces:**

- Consumes: Task 3で検証済みの新版13 PDF
- Produces: UTF-8名を正しく宣言した検証済みZIPと、生成用一時物が残らないワークスペース

- [ ] **Step 1: UTF-8 ZIP作成・検証スクリプトを作成する**

Create write_and_verify_zip.py with:

    from pathlib import Path
    import hashlib
    import os
    import struct
    import unicodedata
    import zipfile

    root = Path("/Users/orca/Projects/Honkumi/output/pdf")
    source = (
        root
        / "AllFontSamples-NoAdjust-TOCSame-BodyMinus0.5pt-2026-07-31"
    )
    archive = (
        root
        / "AllFontSamples-NoAdjust-TOCSame-BodyMinus0.5pt-2026-07-31.zip"
    )
    temporary = archive.with_suffix(".zip.tmp")

    def nfc(value: str) -> str:
        return unicodedata.normalize("NFC", value)

    pdfs = sorted(
        source.glob("*.pdf"),
        key=lambda path: nfc(path.name),
    )
    assert len(pdfs) == 13
    assert not [
        path for path in source.iterdir()
        if not path.is_file() or path.suffix != ".pdf"
    ]
    if temporary.exists():
        raise SystemExit(f"Temporary archive already exists: {temporary}")

    with zipfile.ZipFile(
        temporary,
        "w",
        compression=zipfile.ZIP_DEFLATED,
    ) as output:
        directory = zipfile.ZipInfo(f"{source.name}/")
        directory.external_attr = 0o40755 << 16
        output.writestr(directory, b"")
        for pdf in pdfs:
            output.write(
                pdf,
                arcname=f"{source.name}/{nfc(pdf.name)}",
            )

    os.replace(temporary, archive)
    data = archive.read_bytes()
    with zipfile.ZipFile(archive) as opened:
        assert opened.testzip() is None
        infos = opened.infolist()
        assert len(infos) == 14
        assert infos[0].is_dir()
        pdf_infos = [info for info in infos if not info.is_dir()]
        assert len(pdf_infos) == 13
        assert {
            nfc(Path(info.filename).name) for info in pdf_infos
        } == {
            nfc(pdf.name) for pdf in pdfs
        }
        assert all(info.flag_bits & 0x800 for info in pdf_infos)
        assert all(
            struct.unpack_from(
                "<H",
                data,
                info.header_offset + 6,
            )[0] & 0x800
            for info in pdf_infos
        )
        assert all(
            not info.extra and not info.comment
            for info in infos
        )
        assert opened.comment == b""
        for info in pdf_infos:
            source_pdf = next(
                pdf
                for pdf in pdfs
                if nfc(pdf.name) == nfc(Path(info.filename).name)
            )
            assert hashlib.sha256(
                opened.read(info)
            ).digest() == hashlib.sha256(
                source_pdf.read_bytes()
            ).digest()

    print(
        "RESULT: PASS entries=14 pdfs=13 bit11=13/13 "
        "crc=ok hash_match=13/13 extras=0 comments=0"
    )

- [ ] **Step 2: ZIPを作成して内容を検証する**

Run:

    /Users/orca/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 \
      /Users/orca/Projects/Honkumi/tmp/pdfs/toc-same-footer-minus-half-20260731/write_and_verify_zip.py

Expected: exit 0、RESULT: PASS entries=14 pdfs=13 bit11=13/13 crc=ok hash_match=13/13 extras=0 comments=0。

- [ ] **Step 3: 元ワークスペースと前回ZIPの保存を確認する**

Run:

    test -f /Users/orca/Projects/Honkumi/output/pdf/AllFontSamples-NoAdjust-BodyMinus1pt-2026-07-31.zip
    git -C /Users/orca/Projects/Honkumi status --short -- \
      Honkumi HonkumiTests HonkumiUITests \
      Honkumi.xcodeproj Honkumi.xcworkspace \
      Package.swift Package.resolved project.yml
    git -C /Users/orca/Projects/Honkumi diff --name-only -- \
      Honkumi HonkumiTests HonkumiUITests \
      Honkumi.xcodeproj Honkumi.xcworkspace \
      Package.swift Package.resolved project.yml
    git -C /Users/orca/Projects/Honkumi diff --cached --name-only -- \
      Honkumi HonkumiTests HonkumiUITests \
      Honkumi.xcodeproj Honkumi.xcworkspace \
      Package.swift Package.resolved project.yml

Expected: 4コマンドすべてexit 0。3つのGitコマンドは出力なし。

- [ ] **Step 4: 今回専用の一時ファイルだけを削除する**

Delete only these exact paths:

    /private/tmp/honkumi-all-font-toc-same-footer-minus-half-2026-07-31-5324f11/
    /Users/orca/Projects/Honkumi/tmp/pdfs/toc-same-footer-minus-half-20260731/

Expected: 2パスが存在しない。tmp/pdfs/自体、前回ZIP、新版13 PDF、新版ZIP、既存のユーザー差分は残る。

- [ ] **Step 5: 最終成果物を報告する**

Report absolute clickable links to:

    /Users/orca/Projects/Honkumi/output/pdf/AllFontSamples-NoAdjust-TOCSame-BodyMinus0.5pt-2026-07-31/
    /Users/orca/Projects/Honkumi/output/pdf/AllFontSamples-NoAdjust-TOCSame-BodyMinus0.5pt-2026-07-31.zip

Include: 13 PDF、本文9pt、目次内ページ番号9pt、下部ノンブル8.5pt、個別サイズ補正なし、全143ページ画像検証済み、元アプリ本体コード変更なし、前回ZIP保存。
