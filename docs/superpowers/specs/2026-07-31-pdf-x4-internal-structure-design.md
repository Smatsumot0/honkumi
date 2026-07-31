# PDF/X-4内部構造修正 設計

**日付:** 2026-07-31

## 目的

HonkumiがCore Graphicsで生成する通常PDFと見開きプレビューPDFについて、
組版・画面表示・ページ描画を変更せず、PDF/X-4検証で問題になる内部構造だけを修正する。

現在の7.0pt、10.0pt、12.0pt、12.5pt、16.5ptサンプルでは、いずれも未参照の
7番オブジェクトがxref上で使用中かつoffset 0として記録されている。また、Info
Dictionaryに`/Trapped`がない。一方、PDF 1.6、PDF/X-4 XMP、`/GTS_PDFX`の
Output Intent、`/N 4`のGeneric CMYK ICC、BIZUDMincho-Regularと
HiraginoSans-W3の埋め込み、暗号化・JavaScript・フォームがない状態は維持する。

## 変更しない範囲

次の処理と出力には変更を加えない。

- 本文、章タイトル、目次、奥付、ノンブル、Powered by Honkumiの描画
- フォントサイズ、字送り、行送り、文字数、行数、余白、ページサイズ
- 縦書き、見開きのノド・小口反転、約物調整、禁則処理、改ページ位置
- プレビュー画面と通常PDFの見た目
- ページcontent stream、フォントストリーム、ICCストリーム、XMPストリーム
- 字送りと行送りを余白・文字数・行数から算出する現在の仕様

`LayoutCalculator`、`VerticalTextTypesetter`、描画関数、設定モデルには触れない。

## 採用方式

Core Graphicsの描画完了後に、PDFオブジェクト本体を保持したままxrefとtrailerを
決定的に再構築する`PDFX4StructureFinalizer`を追加する。既存xrefの不正行だけを
置換する方式やPDFKitで文書全体を再保存する方式は採用しない。

この方式では、Info Dictionary以外の間接オブジェクト本体を元のバイト列のまま
コピーする。描画内容の再生成やPDFKitによる再解釈を行わないため、ページ描画、
埋め込みフォント、文字検索、ICC、XMPを維持できる。

## 構造解析

最終化処理は、現在Quartzが生成している単一のclassic xref tableを入力とする。

1. `%PDF-`ヘッダー、末尾の`startxref`、xref、trailerを解析する。
2. xrefの各使用中エントリについて、指定offsetに同じ番号・世代番号の
   `objectNumber generationNumber obj`ヘッダーがあることを確認する。
3. object 0を含むfree entryと、実体のない予約番号を識別する。
4. 実オブジェクトのoffset順から各オブジェクト範囲を決める。stream内部を
   `endobj`検索して境界判定することはしない。
5. 重複番号、offset範囲外、ヘッダー不一致、無効な`/Root`・`/Info`、存在しない
   間接参照を検出した場合は失敗する。
6. 増分更新、xref stream、暗号化された入力など、Quartzの現行出力と異なる形式は
   推測で書き換えず、未対応形式として失敗する。

## Info DictionaryとPDF/Xメタデータ

既存Info Dictionaryのキーと値を保持し、PDF Name Objectとして
`/Trapped /False`を1件だけ追加する。既存値が`/True`または文字列の場合も、
Honkumiはトラッピング処理を行わないため`/False`へ正規化する。

既存XMPストリームは変更せず、XMLとして解析可能であることと、次の識別情報が
重複せず存在することを検証する。

- `pdfxid:GTS_PDFXVersion="PDF/X-4"`
- 既存の`pdfxid:GTS_PDFXConformance="PDF/X-4"`

InfoのTitle、CreatorとXMPの対応情報に重大な不整合がないことも検証する。

## Output Intent、ICC、フォント、カラー

Catalogの既存`/OutputIntents`とその参照先はバイト単位で保持する。最終化後に
次を検証する。

- Output Intentの`/S`が`/GTS_PDFX`
- `/OutputConditionIdentifier`が空でない
- `/DestOutputProfile`が有効なICCストリームを指す
- ICCの`/N`が4で、ストリームが空でなく、ICCヘッダーの`acsp`署名を持つ
- 使用フォントのFontDescriptorが`/FontFile`、`/FontFile2`、`/FontFile3`の
  いずれかを参照し、そのストリームが存在する
- BIZUDMincho-RegularとHiraginoSans-W3の埋め込みが維持される
- 未定義のカラースペース参照を生成せず、既存の描画色を変更しない

ToUnicodeは既存値を保持する。今回の構造修正では新規生成や文字の画像化、
アウトライン化を行わない。

## 再構築

1. ヘッダーを固定長の`%PDF-1.6`とする。
2. 実在する間接オブジェクトを、Info Dictionary以外は元のバイト列のまま出力する。
3. Info Dictionaryだけに`/Trapped /False`を反映する。
4. 0から最大オブジェクト番号までxref entryを生成する。
5. 使用中entryには新しい実offsetと元の世代番号を設定する。
6. 未使用entryにはfree entryを設定し、object 0から始まるfree listを構築する。
7. trailerの`/Root`、`/Info`、`/ID`など必要な値を保持し、`/Size`を最大番号+1へ
   設定する。`/Encrypt`は許可しない。
8. 実際のxref開始位置から`startxref`を生成し、`%%EOF`で終端する。

再構築後のDataをもう一度同じ解析器で検証し、`CGPDFDocument`でも開ける場合だけ
一時ファイルから出力先へ原子的に置換する。途中で失敗した場合は壊れたPDFを
完成品として残さず、既存のexportエラー処理へ返す。

## 統合箇所

通常PDFと見開きプレビューPDFの両方で、Core Graphicsの描画終了後に同じ最終化を
実行する。既存の`normalizePDFVersionHeader`呼び出しはこの最終化呼び出しへ
置き換える。キャンセル確認と失敗時削除の順序は維持する。

## 禁止要素の検証

最終化処理は新しい注釈やアクションを生成しない。生成PDFについて、少なくとも
次が存在しないことを検証する。

- `/Encrypt`
- JavaScript actionとname tree
- `/AcroForm`とWidget annotation
- `/EmbeddedFiles`とFileAttachment annotation
- 動画・音声・外部コンテンツ参照
- 印刷内容を変更する注釈またはOptional Content
- 解決できない間接参照

## 自動テスト

### 構造テスト

合成した不正xrefを入力し、offset 0の使用中entryがfree entryへ変換されることを
最初に失敗テストで固定する。続いて以下を検査する。

- 全使用中xref offsetのオブジェクトヘッダー一致
- free list、`startxref`、`/Size`、`/Root`、Catalogの妥当性
- 重複番号と存在しない参照の拒否
- `/Trapped /False`がName Objectであること
- Output Intent、ICC `/N 4`、ICCストリーム、XMPの妥当性
- 暗号化・JavaScript・フォーム・添付がないこと
- 全使用フォントの埋め込み

### 文字サイズ回帰

7.0pt、10.0pt、12.0pt、12.5pt、16.5ptについて、通常PDFと見開きプレビューPDFを
生成し、すべてが同じ構造基準を満たすことを確認する。

テスト用に最終化前と最終化後の出力を取得し、次を比較する。

- ページ数と全ページのMediaBox、TrimBox、BleedBox、CropBox
- ページcontent streamとページリソース
- 抽出テキスト
- 固定解像度でレンダリングした全ページの画素
- 既存レイアウトスナップショット上の余白、文字数、行数、字送り、行送り、
  本文・章タイトル・ノンブルのフォントサイズ

content streamとページリソースの同一性、および画素差分ゼロを必須とすることで、
改ページ、文字位置、ノンブル位置、見た目に変更がないことを確認する。

## 外部検証

実装後は次を実行する。

- XCTestの構造・回帰テストと既存テスト一式
- Core Graphicsによる修復なしの再読込
- pypdf strict modeによる全オブジェクト読込
- Poppler `pdfinfo`による構造・暗号化・ページ情報確認
- Poppler `pdftoppm`によるレンダリングと最終化前後の画像比較

現在の開発環境にはAdobe Acrobat Pro、qpdf、Ghostscript、veraPDFがないため、
それらを使った検証結果を装わない。利用可能になった場合はqpdfの構造検査と、
PDF/X-4対応製品のプリフライトを追加実行する。外部の完全なPDF/X-4プリフライトを
実行できない場合は、実施済みの構造検査と未実施の規格プリフライトを最終報告で
明確に区別する。

## 完了条件

- 通常PDFと見開きプレビューPDFにoffset 0の使用中xref entryがない
- xref、free list、trailer、`/Size`、`startxref`が実体と一致する
- `/Trapped /False`、PDF/X-4 XMP、Output Intent、CMYK ICCが存在する
- 使用フォントが埋め込まれ、暗号化・禁止要素・壊れた参照がない
- 5文字サイズの構造テストが成功する
- 最終化前後でページ内容、組版値、ページ数、レンダリング画像が変わらない
- 既存テストと追加テストが成功する
- 利用可能な厳密パーサーとPDF/X-4プリフライトの結果を区別して報告する
