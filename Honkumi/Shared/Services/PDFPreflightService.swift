import CoreGraphics
import Foundation
import UIKit

nonisolated enum PreflightSeverity: String, CaseIterable, Identifiable {
    case error
    case warning
    case info

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .error:
            "エラー"
        case .warning:
            "警告"
        case .info:
            "情報"
        }
    }
}

nonisolated enum PreflightIssueLocationType: String {
    case text
    case settings
    case page
    case colophon
    case toc
    case pdf
}

nonisolated struct PreflightIssueLocation: Equatable {
    let type: PreflightIssueLocationType
    let pageNumber: Int?
    let characterRange: Range<Int>?
    let settingKey: String?
}

nonisolated struct PreflightIssue: Identifiable, Equatable {
    let id: String
    let severity: PreflightSeverity
    let title: String
    let message: String
    let location: PreflightIssueLocation?
    let isAutoFixable: Bool
    let autoFixDescription: String?
}

nonisolated struct PreflightResult: Identifiable, Equatable {
    let id = UUID()
    let issues: [PreflightIssue]

    var hasError: Bool {
        issues.contains { $0.severity == .error }
    }

    var hasWarning: Bool {
        issues.contains { $0.severity == .warning }
    }

    var hasProblems: Bool {
        hasError || hasWarning
    }

    var autoFixableIssues: [PreflightIssue] {
        issues.filter(\.isAutoFixable)
    }

    var canContinue: Bool {
        !hasError
    }

    var errorCount: Int {
        issues.filter { $0.severity == .error }.count
    }

    var warningCount: Int {
        issues.filter { $0.severity == .warning }.count
    }
}

nonisolated struct PDFPreflightService {
    func check(document: ManuscriptDocument, subscriptionStatus: SubscriptionStatus) -> PreflightResult {
        var checkedDocument = document
        checkedDocument.settings = document.settings.validated
        let paginationResult = ManuscriptRenderPipeline.paginationResult(
            for: checkedDocument,
            subscriptionStatus: subscriptionStatus
        )
        let effectiveDocument = paginationResult.document
        let effectiveSettings = effectiveDocument.settings.validated
        let parsed = ManuscriptMarkupParser.parse(effectiveDocument.body)
        let pages = paginationResult.pages
        let textNormalizationReport = ManuscriptRenderPipeline.printTextNormalizationReport(
            for: checkedDocument,
            subscriptionStatus: subscriptionStatus
        )
        var issues: [PreflightIssue] = []

        checkBody(effectiveDocument.body, parsed: parsed, settings: effectiveSettings, into: &issues)
        checkPrintTextNormalization(textNormalizationReport, into: &issues)
        checkPageStructure(
            document: effectiveDocument,
            parsed: parsed,
            pages: pages,
            subscriptionStatus: subscriptionStatus,
            into: &issues
        )
        checkPrintSettings(effectiveSettings, into: &issues)
        checkPDFDisplay(settings: effectiveSettings, pages: pages, into: &issues)
        checkSubmissionReadiness(
            settings: effectiveSettings,
            pages: pages,
            subscriptionStatus: subscriptionStatus,
            into: &issues
        )
        checkPrintProduction(
            settings: effectiveSettings,
            pages: pages,
            subscriptionStatus: subscriptionStatus,
            textNormalizationReport: textNormalizationReport,
            into: &issues
        )
        appendInfo(
            document: effectiveDocument,
            pages: pages,
            settings: effectiveSettings,
            into: &issues
        )

        return PreflightResult(issues: issues)
    }

    func autoFixedDocument(
        from document: ManuscriptDocument,
        subscriptionStatus: SubscriptionStatus
    ) -> ManuscriptDocument {
        var fixedDocument = document
        fixedDocument.body = autoFixedBody(document.body, settings: document.settings.validated)
        fixedDocument.settings = autoFixedSettings(
            document.settings,
            body: fixedDocument.body,
            subscriptionStatus: subscriptionStatus
        ).validated
        return fixedDocument
    }

    private func checkBody(
        _ body: String,
        parsed: ParsedManuscript,
        settings: EditorSettings,
        into issues: inout [PreflightIssue]
    ) {
        if body.isEmpty {
            issues.append(error(
                id: "body.empty",
                title: "本文が空です",
                message: "PDF出力には本文が必要です。",
                location: .init(type: .text, pageNumber: nil, characterRange: nil, settingKey: nil)
            ))
            return
        }

        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(error(
                id: "body.blank",
                title: "本文が空白だけです",
                message: "空白と改行だけの原稿はPDF出力できません。",
                location: .init(type: .text, pageNumber: nil, characterRange: nil, settingKey: nil)
            ))
        }

        let lines = body.components(separatedBy: .newlines)
        let excessiveBlankRun = max(settings.formatSettings.maxConsecutiveBlankLines + 1, 3)
        if longestBlankLineRun(in: lines) > excessiveBlankRun {
            issues.append(warning(
                id: "body.tooManyBlankLines",
                title: "連続した空行が多すぎます",
                message: "意図しない空白ページや余白が発生する可能性があります。",
                location: .init(type: .text, pageNumber: nil, characterRange: nil, settingKey: nil),
                isAutoFixable: true,
                autoFixDescription: "連続空行を設定値まで圧縮します。"
            ))
        }

        if lines.contains(where: { $0.hasPrefix(" ") }) {
            issues.append(warning(
                id: "body.leadingHalfSpace",
                title: "行頭に半角スペースがあります",
                message: "縦書き本文では行頭の半角スペースが不自然に見える場合があります。",
                location: .init(type: .text, pageNumber: nil, characterRange: nil, settingKey: nil)
            ))
        }

        if body.contains("　　") {
            issues.append(warning(
                id: "body.consecutiveFullWidthSpaces",
                title: "全角スペースが連続しています",
                message: "意図しない字下げや空白に見える可能性があります。",
                location: .init(type: .text, pageNumber: nil, characterRange: nil, settingKey: nil)
            ))
        }

        if containsConsecutivePageBreaks(lines) {
            issues.append(warning(
                id: "body.consecutivePageBreaks",
                title: "改ページタグが連続しています",
                message: "\(ManuscriptMarkupParser.pageBreakTag) が連続しているため、白紙ページが発生する可能性があります。",
                location: .init(type: .text, pageNumber: nil, characterRange: nil, settingKey: nil),
                isAutoFixable: true,
                autoFixDescription: "連続した改ページタグを1つにまとめます。"
            ))
        }

        if hasStandaloneEdgePageBreak(lines) {
            issues.append(warning(
                id: "body.edgePageBreak",
                title: "本文の先頭または末尾に単独の改ページタグがあります",
                message: "先頭または末尾の改ページタグにより、白紙ページが発生する可能性があります。",
                location: .init(type: .text, pageNumber: nil, characterRange: nil, settingKey: nil),
                isAutoFixable: true,
                autoFixDescription: "本文先頭・末尾の単独改ページタグを削除します。"
            ))
        }

        if body.contains("。」") || body.contains("。』") {
            issues.append(warning(
                id: "body.periodBeforeClosingQuote",
                title: "閉じ鉤括弧の前に句点があります",
                message: "表記ルールによっては入稿前の確認が必要です。自動では削除しません。",
                location: .init(type: .text, pageNumber: nil, characterRange: nil, settingKey: nil)
            ))
        }

        if unmatchedCount(open: "「", close: "」", in: body) != 0 {
            issues.append(warning(
                id: "body.unmatchedJapaneseQuote",
                title: "鉤括弧の閉じ忘れの可能性があります",
                message: "「」の数が一致していません。本文を確認してください。",
                location: .init(type: .text, pageNumber: nil, characterRange: nil, settingKey: nil)
            ))
        }

        if unmatchedCount(open: "（", close: "）", in: body) != 0 {
            issues.append(warning(
                id: "body.unmatchedParenthesis",
                title: "丸括弧の閉じ忘れの可能性があります",
                message: "（）の数が一致していません。本文を確認してください。",
                location: .init(type: .text, pageNumber: nil, characterRange: nil, settingKey: nil)
            ))
        }

        let emptyChapterTitles = parsed.segments.compactMap { segment -> String? in
            guard segment.startsChapter,
                  let chapterTitle = segment.chapterTitle,
                  segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return chapterTitle
        }
        if !emptyChapterTitles.isEmpty {
            issues.append(warning(
                id: "body.emptyChapter",
                title: "本文がない章があります",
                message: "章タイトルだけで本文がない章があります: \(emptyChapterTitles.joined(separator: "、"))",
                location: .init(type: .text, pageNumber: nil, characterRange: nil, settingKey: nil)
            ))
        }
    }

    private func checkPageStructure(
        document: ManuscriptDocument,
        parsed: ParsedManuscript,
        pages: [PreviewPage],
        subscriptionStatus: SubscriptionStatus,
        into issues: inout [PreflightIssue]
    ) {
        if pages.isEmpty {
            issues.append(error(
                id: "pages.none",
                title: "ページが生成できません",
                message: "本文と設定を確認してください。",
                location: .init(type: .page, pageNumber: nil, characterRange: nil, settingKey: nil)
            ))
        }

        if let lastPage = pages.last,
           lastPage.kind == .body,
           lastPage.columns.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            issues.append(warning(
                id: "pages.trailingBlank",
                title: "最終ページが白紙です",
                message: "末尾の改ページタグや空行により白紙ページが生成されている可能性があります。",
                location: .init(type: .page, pageNumber: pages.count, characterRange: nil, settingKey: nil),
                isAutoFixable: true,
                autoFixDescription: "本文末尾の空白・空行・単独改ページタグを整理します。"
            ))
        }

        if document.settings.showTableOfContents,
           !parsed.segments.contains(where: { $0.startsChapter && $0.chapterTitle != nil }) {
            issues.append(warning(
                id: "toc.noChapters",
                title: "目次対象の章タイトルがありません",
                message: "目次をオンにしていますが、本文に章タイトルがありません。",
                location: .init(type: .toc, pageNumber: nil, characterRange: nil, settingKey: "showTableOfContents"),
                isAutoFixable: true,
                autoFixDescription: "目次をオフにします。"
            ))
        }

        if document.settings.colophon.isEnabled,
           !pages.contains(where: {
               if case .colophon = $0.kind { return true }
               return false
           }) {
            issues.append(warning(
                id: "colophon.notGenerated",
                title: "奥付ページが生成されていません",
                message: "奥付設定を確認してください。",
                location: .init(type: .colophon, pageNumber: nil, characterRange: nil, settingKey: "colophon")
            ))
        }

    }

    private func checkPrintSettings(_ settings: EditorSettings, into issues: inout [PreflightIssue]) {
        checkRange(settings.marginTop, range: EditorSettings.marginTopRange, key: "marginTop", title: "天の余白が範囲外です", unit: "mm", into: &issues)
        checkRange(settings.marginBottom, range: EditorSettings.marginBottomRange, key: "marginBottom", title: "地の余白が範囲外です", unit: "mm", into: &issues)
        checkRange(settings.marginInner, range: EditorSettings.marginInnerRange, key: "marginInner", title: "ノドの余白が範囲外です", unit: "mm", into: &issues)
        checkRange(settings.marginOuter, range: EditorSettings.marginOuterRange, key: "marginOuter", title: "小口の余白が範囲外です", unit: "mm", into: &issues)
        checkRange(settings.fontSize, range: EditorSettings.fontSizeRange, key: "fontSize", title: "文字サイズが範囲外です", unit: "pt", into: &issues)
        checkRange(CGFloat(settings.linesPerPage), range: CGFloat(EditorSettings.linesPerPageRange.lowerBound)...CGFloat(EditorSettings.linesPerPageRange.upperBound), key: "linesPerPage", title: "1ページあたりの行数が範囲外です", unit: "行", into: &issues)
        checkRange(CGFloat(settings.charactersPerLine), range: CGFloat(EditorSettings.charactersPerLineRange.lowerBound)...CGFloat(EditorSettings.charactersPerLineRange.upperBound), key: "charactersPerLine", title: "1行あたりの文字数が範囲外です", unit: "文字", into: &issues)

        if settings.isPageNumberEnabled, settings.marginBottom < 10 {
            issues.append(warning(
                id: "settings.pageNumberCloseToBody",
                title: "ノンブルが本文に近すぎる可能性があります",
                message: "地の余白が狭いため、ノンブルと本文が近く見える可能性があります。",
                location: .init(type: .settings, pageNumber: nil, characterRange: nil, settingKey: "pageNumberPosition"),
                isAutoFixable: true,
                autoFixDescription: "ノンブル位置を端に移動し、設定値を安全な範囲に丸めます。"
            ))
        }
    }

    private func checkPDFDisplay(settings: EditorSettings, pages: [PreviewPage], into issues: inout [PreflightIssue]) {
        for pageNumber in max(pages.indices.lowerBound, 0)..<pages.count {
            let layout = LayoutCalculator.layout(for: settings, pageNumber: pageNumber + 1)
            if !CGRect(x: 0, y: 0, width: layout.pageWidth, height: layout.pageHeight).contains(layout.bodyFrame) {
                issues.append(error(
                    id: "display.bodyOutside.\(pageNumber + 1)",
                    title: "本文がページ外にはみ出しています",
                    message: "\(pageNumber + 1)ページ目の本文領域が用紙サイズ外です。",
                    location: .init(type: .page, pageNumber: pageNumber + 1, characterRange: nil, settingKey: nil)
                ))
            }
        }

        if settings.isPageNumberEnabled, settings.marginBottom < 8 {
            issues.append(warning(
                id: "display.pageNumberOutside",
                title: "ノンブルがページ外にはみ出す可能性があります",
                message: "地の余白が非常に狭いため、PDF出力時の確認をおすすめします。",
                location: .init(type: .settings, pageNumber: nil, characterRange: nil, settingKey: "marginBottom"),
                isAutoFixable: true,
                autoFixDescription: "余白を許容範囲内へ丸めます。"
            ))
        }

        if settings.showChapterTitle, settings.marginTop < 10 {
            issues.append(warning(
                id: "display.chapterTitleCloseToEdge",
                title: "章タイトルがページ上端に近い可能性があります",
                message: "天の余白が狭いため、章タイトルがページ端に近くなる可能性があります。",
                location: .init(type: .settings, pageNumber: nil, characterRange: nil, settingKey: "marginTop"),
                isAutoFixable: true,
                autoFixDescription: "余白を許容範囲内へ丸めます。"
            ))
        }
    }

    private func checkSubmissionReadiness(
        settings: EditorSettings,
        pages: [PreviewPage],
        subscriptionStatus: SubscriptionStatus,
        into issues: inout [PreflightIssue]
    ) {
        let firstLayout = LayoutCalculator.layout(for: settings, pageNumber: 1)
        let expectedWidth = LayoutCalculator.millimetersToPoints(settings.pageSize.widthMillimeters)
        let expectedHeight = LayoutCalculator.millimetersToPoints(settings.pageSize.heightMillimeters)
        if abs(firstLayout.pageWidth - expectedWidth) > 0.1 || abs(firstLayout.pageHeight - expectedHeight) > 0.1 {
            issues.append(error(
                id: "submission.pageSizeMismatch",
                title: "PDFページサイズが設定と一致しません",
                message: "用紙サイズの計算結果が作品設定と一致していません。",
                location: .init(type: .settings, pageNumber: nil, characterRange: nil, settingKey: "pageSize")
            ))
        }

        if settings.marginInner < 12 || settings.marginOuter < 10 || settings.marginTop < 10 || settings.marginBottom < 10 {
            issues.append(warning(
                id: "submission.narrowMargins",
                title: "余白が狭すぎる可能性があります",
                message: "入稿先によっては余白不足になる可能性があります。",
                location: .init(type: .settings, pageNumber: nil, characterRange: nil, settingKey: "margins"),
                isAutoFixable: true,
                autoFixDescription: "余白を安全な最小値に近づけます。"
            ))
        }

        if settings.colophon.isEnabled,
           !settings.colophon.websiteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           settings.marginBottom < 10 {
            issues.append(warning(
                id: "submission.qrAreaTight",
                title: "QRコード周辺の余白が狭い可能性があります",
                message: "奥付にHPを入れる場合、読み取りやすい余白が確保されているか確認してください。",
                location: .init(type: .colophon, pageNumber: pages.count, characterRange: nil, settingKey: "websiteURL")
            ))
        }

        issues.append(info(
            id: "submission.bookDirection",
            title: "綴じ方向",
            message: "縦書き・右綴じ前提の本文PDFとして出力します。",
            location: nil
        ))

        issues.append(info(
            id: "submission.noCover",
            title: "表紙なし本文PDF",
            message: "このPDF出力には表紙を含めません。",
            location: nil
        ))

    }

    private func checkPrintProduction(
        settings: EditorSettings,
        pages: [PreviewPage],
        subscriptionStatus: SubscriptionStatus,
        textNormalizationReport: PrintTextNormalizationReport,
        into issues: inout [PreflightIssue]
    ) {
        let firstLayout = LayoutCalculator.layout(for: settings, pageNumber: 1)
        let geometry = PDFPrintProduction.pageGeometry(for: firstLayout)
        let profile = PDFPrintProduction.pdfX4Profile

        issues.append(info(
            id: "print.cropMarks",
            title: "トンボ",
            message: settings.showsCropMarks
                ? "ON。仕上がりサイズの外側にコーナートンボを追加します。"
                : "OFF。仕上がりサイズどおりのPDFを出力します。",
            location: .init(type: .settings, pageNumber: nil, characterRange: nil, settingKey: "showsCropMarks")
        ))

        issues.append(info(
            id: "print.pdfx4",
            title: "PDF/X-4検証状態",
            message: "PDF/X-4向け設定・未検証。CoreGraphics出力後にPDF-\(PDFPrintProduction.targetPDFVersion)ヘッダーへ補正し、Output Intent / ICC / PDFボックスを付与しますが、veraPDF未実行のため準拠済みとは表示しません。",
            location: .init(type: .pdf, pageNumber: nil, characterRange: nil, settingKey: nil)
        ))

        issues.append(info(
            id: "print.pdfVersion",
            title: "PDF version",
            message: "出力後にPDFヘッダーをPDF-\(PDFPrintProduction.targetPDFVersion)へ補正します。低レベル構造のPDF/X-4適合性は未検証です。",
            location: .init(type: .pdf, pageNumber: nil, characterRange: nil, settingKey: nil)
        ))

        if profile.outputIntent != nil, profile.hasEmbeddableICCProfile {
            issues.append(info(
                id: "print.outputIntent",
                title: "ICC / Output Intent",
                message: "\(profile.outputConditionIdentifier) のOutput IntentとICCプロファイルをPDFへ埋め込みます。",
                location: .init(type: .pdf, pageNumber: nil, characterRange: nil, settingKey: nil)
            ))
        } else {
            issues.append(warning(
                id: "print.outputIntent.missing",
                title: "ICC / Output Intentを埋め込めません",
                message: "CoreGraphicsから埋め込み可能なICCプロファイルを取得できませんでした。",
                location: .init(type: .pdf, pageNumber: nil, characterRange: nil, settingKey: nil)
            ))
        }

        checkFontEmbedding(settings: settings, subscriptionStatus: subscriptionStatus, into: &issues)
        checkEmojiFontRisk(textNormalizationReport, into: &issues)
        checkImageQuality(settings: settings, pages: pages, subscriptionStatus: subscriptionStatus, into: &issues)

        issues.append(info(
            id: "print.fullPageRaster",
            title: "PDF全体の画像化",
            message: "なし。本文、罫線、トンボ、ノンブル、QRコードはテキストまたはベクターとして描画します。",
            location: .init(type: .pdf, pageNumber: nil, characterRange: nil, settingKey: nil)
        ))

        issues.append(info(
            id: "print.encryption",
            title: "暗号化",
            message: "なし。PDF生成時にユーザー/オーナーパスワードを設定しません。",
            location: .init(type: .pdf, pageNumber: nil, characterRange: nil, settingKey: nil)
        ))

        issues.append(info(
            id: "print.interactiveElements",
            title: "JavaScript / フォーム / 注釈",
            message: "なし。PDF生成処理ではJavaScript、フォーム、動画、音声、注釈を追加しません。",
            location: .init(type: .pdf, pageNumber: nil, characterRange: nil, settingKey: nil)
        ))

        issues.append(info(
            id: "print.pdfBoxes",
            title: "PDFボックス",
            message: pdfBoxSummary(geometry),
            location: .init(type: .pdf, pageNumber: nil, characterRange: nil, settingKey: nil)
        ))

        issues.append(warning(
            id: "print.pdfx4.unsupported",
            title: "PDF/X-4未対応 / 未検証項目",
            message: PDFX4ProductionProfile.unsupportedCapabilities.joined(separator: " / "),
            location: .init(type: .pdf, pageNumber: nil, characterRange: nil, settingKey: nil)
        ))
    }

    private func checkPrintTextNormalization(
        _ report: PrintTextNormalizationReport,
        into issues: inout [PreflightIssue]
    ) {
        if report.totalReplacementCount == 0 {
            issues.append(info(
                id: "print.textNormalization.none",
                title: "絵文字置換件数",
                message: "0件。印刷用の絵文字置換は不要です。",
                location: .init(type: .text, pageNumber: nil, characterRange: nil, settingKey: nil)
            ))
            return
        }

        issues.append(warning(
            id: "print.textNormalization.summary",
            title: "絵文字置換件数",
            message: "合計\(report.totalReplacementCount)件を印刷用に置換します。\(report.sampleLocations)",
            location: firstReplacementLocation(in: report)
        ))

        issues.append(info(
            id: "print.textNormalization.hearts",
            title: "ハート置換件数",
            message: "\(report.heartReplacementCount)件。ハート系文字はすべて\(PrintTextNormalizer.printableHeart)へ置換します。",
            location: .init(type: .text, pageNumber: nil, characterRange: nil, settingKey: nil)
        ))

        issues.append(info(
            id: "print.textNormalization.unsupported",
            title: "未対応文字の置換件数",
            message: "\(report.unsupportedEmojiReplacementCount)件。ハート以外のカラー絵文字や環境依存絵文字は\(PrintTextNormalizer.unsupportedEmojiReplacement)へ置換します。",
            location: .init(type: .text, pageNumber: nil, characterRange: nil, settingKey: nil)
        ))
    }

    private func checkEmojiFontRisk(
        _ report: PrintTextNormalizationReport,
        into issues: inout [PreflightIssue]
    ) {
        if report.containsEmojiFontRisk {
            issues.append(warning(
                id: "print.emojiFontRisk",
                title: "AppleColorEmojiなど絵文字フォント",
                message: "入力内の絵文字系文字はPDF/プレビュー用に置換します。置換後PDFにAppleColorEmojiが残っていないかは出力後検査してください。",
                location: firstReplacementLocation(in: report)
            ))
        } else {
            issues.append(info(
                id: "print.emojiFontRisk.none",
                title: "AppleColorEmojiなど絵文字フォント",
                message: "入力内に絵文字フォントへフォールバックしそうな文字は検出していません。",
                location: .init(type: .pdf, pageNumber: nil, characterRange: nil, settingKey: nil)
            ))
        }
    }

    private func firstReplacementLocation(in report: PrintTextNormalizationReport) -> PreflightIssueLocation? {
        guard let first = report.replacements.first else { return nil }
        switch first.location {
        case .title:
            return .init(type: .settings, pageNumber: nil, characterRange: nil, settingKey: "title")
        case let .body(offset):
            return .init(type: .text, pageNumber: nil, characterRange: offset..<(offset + 1), settingKey: nil)
        case let .colophon(field):
            return .init(type: .colophon, pageNumber: nil, characterRange: nil, settingKey: field)
        }
    }

    private func checkFontEmbedding(
        settings: EditorSettings,
        subscriptionStatus: SubscriptionStatus,
        into issues: inout [PreflightIssue]
    ) {
        let bodyFont = AppFontCatalog.effectiveFont(
            selectedFontId: settings.selectedFontId,
            isAdditionalFontPackUnlocked: subscriptionStatus == .paid
        )
        if let postScriptName = bodyFont.postScriptName,
           bodyFont.fileName != nil,
           UIFont(name: postScriptName, size: 10) != nil {
            issues.append(info(
                id: "print.fontEmbedding.body",
                title: "フォント埋め込みチェック",
                message: "本文フォント「\(bodyFont.displayName)」は同梱フォントをPDFへ埋め込み対象として描画します。",
                location: .init(type: .pdf, pageNumber: nil, characterRange: nil, settingKey: "selectedFontId")
            ))
        } else {
            issues.append(warning(
                id: "print.fontEmbedding.bodyFallback",
                title: "本文フォントの埋め込み確認が必要です",
                message: "本文フォントが同梱フォントとして読み込めないため、システムフォントへフォールバックする可能性があります。",
                location: .init(type: .settings, pageNumber: nil, characterRange: nil, settingKey: "selectedFontId")
            ))
        }

        guard settings.isPageNumberEnabled else { return }

        if subscriptionStatus == .paid,
           let pageNumberFont = AppFontCatalog.pageNumberFont(id: settings.pageNumberFontId) {
            if UIFont(name: pageNumberFont.postScriptName, size: 10) != nil {
                issues.append(info(
                    id: "print.fontEmbedding.pageNumber",
                    title: "ノンブルフォント埋め込みチェック",
                    message: "ノンブルフォント「\(pageNumberFont.displayName)」は同梱フォントをPDFへ埋め込み対象として描画します。",
                    location: .init(type: .pdf, pageNumber: nil, characterRange: nil, settingKey: "pageNumberFontId")
                ))
            } else {
                issues.append(warning(
                    id: "print.fontEmbedding.pageNumberFallback",
                    title: "ノンブルフォントの埋め込み確認が必要です",
                    message: "選択中のノンブルフォントを読み込めないため、本文フォントへフォールバックする可能性があります。",
                    location: .init(type: .settings, pageNumber: nil, characterRange: nil, settingKey: "pageNumberFontId")
                ))
            }
        } else {
            issues.append(info(
                id: "print.fontEmbedding.pageNumber.body",
                title: "ノンブルフォント埋め込みチェック",
                message: "ノンブルは本文フォントと同じ同梱フォントで描画します。",
                location: .init(type: .pdf, pageNumber: nil, characterRange: nil, settingKey: "pageNumberFontId")
            ))
        }
    }

    private func checkImageQuality(
        settings: EditorSettings,
        pages: [PreviewPage],
        subscriptionStatus: SubscriptionStatus,
        into issues: inout [PreflightIssue]
    ) {
        if settings.colophon.isEnabled,
           settings.colophon.showsQRCode,
           !settings.colophon.websiteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(info(
                id: "print.qrResolution",
                title: "QRコード解像度",
                message: "奥付QRコードはPDF上でベクター矩形として描画するため、低解像度画像は使用しません。",
                location: .init(type: .colophon, pageNumber: pages.count, characterRange: nil, settingKey: "websiteURL")
            ))
        } else {
            issues.append(info(
                id: "print.qrResolution.notUsed",
                title: "QRコード解像度",
                message: "奥付QRコードは出力しません。",
                location: .init(type: .colophon, pageNumber: nil, characterRange: nil, settingKey: "showsQRCode")
            ))
        }

        guard subscriptionStatus == .paid,
              settings.colophon.hasCreatorImage,
              let imageData = settings.colophon.circleImageData,
              let image = UIImage(data: imageData),
              let cgImage = image.cgImage else {
            issues.append(info(
                id: "print.imageResolution.none",
                title: "画像解像度",
                message: "本文内の挿絵画像は未使用です。PDF出力時に全体を低解像度画像へ変換しません。",
                location: .init(type: .pdf, pageNumber: nil, characterRange: nil, settingKey: nil)
            ))
            return
        }

        let layout = LayoutCalculator.layout(for: settings, pageNumber: max(pages.count, 1))
        let displayHeight = max(layout.fontSize * 2.4, 18)
        let aspectRatio = CGFloat(cgImage.width) / max(CGFloat(cgImage.height), 1)
        let displayWidth = min(displayHeight * aspectRatio, layout.bodyFrame.width * 0.36)
        let ppiX = CGFloat(cgImage.width) / max(displayWidth / LayoutCalculator.pointsPerInch, 0.01)
        let ppiY = CGFloat(cgImage.height) / max(displayHeight / LayoutCalculator.pointsPerInch, 0.01)
        let effectivePPI = min(ppiX, ppiY)

        if effectivePPI < 300 {
            issues.append(warning(
                id: "print.imageResolution.lowCreator",
                title: "画像解像度が低い可能性があります",
                message: "奥付のサークル画像は実寸配置で約\(formatted(effectivePPI))ppiです。300ppi以上を目安にしてください。",
                location: .init(type: .colophon, pageNumber: pages.count, characterRange: nil, settingKey: "circleImageData")
            ))
        } else {
            issues.append(info(
                id: "print.imageResolution.creator",
                title: "画像解像度",
                message: "奥付のサークル画像は実寸配置で約\(formatted(effectivePPI))ppiです。",
                location: .init(type: .colophon, pageNumber: pages.count, characterRange: nil, settingKey: "circleImageData")
            ))
        }
    }

    private func pdfBoxSummary(_ geometry: PDFPageGeometry) -> String {
        [
            "MediaBox \(formattedMillimeters(geometry.mediaBox.size))",
            "TrimBox \(formattedMillimeters(geometry.trimBox.size))",
            "CropBox \(formattedMillimeters(geometry.cropBox.size))",
            "BleedBox \(formattedMillimeters(geometry.bleedBox.size))"
        ].joined(separator: " / ")
    }

    private func appendInfo(
        document: ManuscriptDocument,
        pages: [PreviewPage],
        settings: EditorSettings,
        into issues: inout [PreflightIssue]
    ) {
        issues.append(info(
            id: "info.pageCount",
            title: "総ページ数",
            message: "\(pages.count)ページ",
            location: nil
        ))
        issues.append(info(
            id: "info.characterCount",
            title: "総文字数",
            message: "\(ManuscriptMarkupParser.characterCountBody(from: document.body).count)文字",
            location: nil
        ))
        issues.append(info(
            id: "info.pageSize",
            title: "用紙サイズ",
            message: settings.pageSize.displayName,
            location: .init(type: .settings, pageNumber: nil, characterRange: nil, settingKey: "pageSize")
        ))
        issues.append(info(
            id: "info.recommendedPrintSettings",
            title: "推奨設定",
            message: settings.useRecommendedPrintSettings ? "ON。推奨設定を適用しています。" : "OFF。手動設定を適用しています。",
            location: .init(type: .settings, pageNumber: nil, characterRange: nil, settingKey: "useRecommendedPrintSettings")
        ))
        issues.append(info(
            id: "info.bodyFont",
            title: "本文フォント",
            message: AppFontCatalog.font(id: settings.selectedFontId)?.displayName ?? "BIZ UD明朝",
            location: .init(type: .settings, pageNumber: nil, characterRange: nil, settingKey: "selectedFontId")
        ))
    }

    private func checkRange(
        _ value: CGFloat,
        range: ClosedRange<CGFloat>,
        key: String,
        title: String,
        unit: String,
        into issues: inout [PreflightIssue]
    ) {
        guard !range.contains(value) else { return }
        issues.append(error(
            id: "settings.\(key).range",
            title: title,
            message: "現在値 \(formatted(value))\(unit) は許容範囲 \(formatted(range.lowerBound))〜\(formatted(range.upperBound))\(unit) の外です。",
            location: .init(type: .settings, pageNumber: nil, characterRange: nil, settingKey: key),
            isAutoFixable: true,
            autoFixDescription: "許容範囲内に丸めます。"
        ))
    }

    private func autoFixedBody(_ body: String, settings: EditorSettings) -> String {
        var lines = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == ManuscriptMarkupParser.pageBreakTag {
            lines.removeFirst()
        }
        while lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == ManuscriptMarkupParser.pageBreakTag {
            lines.removeLast()
        }

        var normalized: [String] = []
        var previousWasPageBreak = false
        var blankRun = 0
        let maxBlankLines = min(
            max(
                settings.formatSettings.maxConsecutiveBlankLines,
                EditorSettings.maxConsecutiveBlankLinesRange.lowerBound
            ),
            EditorSettings.maxConsecutiveBlankLinesRange.upperBound
        )

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
            let isPageBreak = line.trimmingCharacters(in: .whitespaces) == ManuscriptMarkupParser.pageBreakTag
            if isPageBreak {
                if previousWasPageBreak {
                    continue
                }
                normalized.append(ManuscriptMarkupParser.pageBreakTag)
                previousWasPageBreak = true
                blankRun = 0
                continue
            }

            previousWasPageBreak = false
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                blankRun += 1
                if blankRun <= maxBlankLines {
                    normalized.append("")
                }
            } else {
                blankRun = 0
                normalized.append(line)
            }
        }

        while normalized.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            normalized.removeLast()
        }

        return normalized.joined(separator: "\n")
    }

    private func autoFixedSettings(
        _ settings: EditorSettings,
        body: String,
        subscriptionStatus: SubscriptionStatus
    ) -> EditorSettings {
        var fixed = settings.validated

        if fixed.showTableOfContents {
            let parsed = ManuscriptMarkupParser.parse(body)
            if !parsed.segments.contains(where: { $0.startsChapter && $0.chapterTitle != nil }) {
                fixed.showTableOfContents = false
            }
        }

        if fixed.isPageNumberEnabled,
           fixed.marginBottom <= EditorSettings.marginBottomRange.lowerBound {
            fixed.pageNumberPosition = .outside
        }

        fixed.marginTop = max(fixed.marginTop, min(10, EditorSettings.marginTopRange.upperBound))
        fixed.marginBottom = max(fixed.marginBottom, min(10, EditorSettings.marginBottomRange.upperBound))
        fixed.marginInner = max(fixed.marginInner, min(12, EditorSettings.marginInnerRange.upperBound))
        fixed.marginOuter = max(fixed.marginOuter, min(10, EditorSettings.marginOuterRange.upperBound))

        if subscriptionStatus == .free {
            fixed.pageNumberFontId = nil
            fixed.pageNumberSize = EditorSettings.default.pageNumberSize
        }

        return fixed
    }

    private func longestBlankLineRun(in lines: [String]) -> Int {
        var longest = 0
        var current = 0
        for line in lines {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return longest
    }

    private func containsConsecutivePageBreaks(_ lines: [String]) -> Bool {
        var previousWasPageBreak = false
        for line in lines {
            let isPageBreak = line.trimmingCharacters(in: .whitespacesAndNewlines) == ManuscriptMarkupParser.pageBreakTag
            if isPageBreak, previousWasPageBreak {
                return true
            }
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                previousWasPageBreak = isPageBreak
            }
        }
        return false
    }

    private func hasStandaloneEdgePageBreak(_ lines: [String]) -> Bool {
        let meaningfulLines = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return meaningfulLines.first == ManuscriptMarkupParser.pageBreakTag
            || meaningfulLines.last == ManuscriptMarkupParser.pageBreakTag
    }

    private func unmatchedCount(open: Character, close: Character, in text: String) -> Int {
        text.reduce(0) { count, character in
            if character == open { return count + 1 }
            if character == close { return count - 1 }
            return count
        }
    }

    private func error(
        id: String,
        title: String,
        message: String,
        location: PreflightIssueLocation?,
        isAutoFixable: Bool = false,
        autoFixDescription: String? = nil
    ) -> PreflightIssue {
        PreflightIssue(
            id: id,
            severity: .error,
            title: title,
            message: message,
            location: location,
            isAutoFixable: isAutoFixable,
            autoFixDescription: autoFixDescription
        )
    }

    private func warning(
        id: String,
        title: String,
        message: String,
        location: PreflightIssueLocation?,
        isAutoFixable: Bool = false,
        autoFixDescription: String? = nil
    ) -> PreflightIssue {
        PreflightIssue(
            id: id,
            severity: .warning,
            title: title,
            message: message,
            location: location,
            isAutoFixable: isAutoFixable,
            autoFixDescription: autoFixDescription
        )
    }

    private func info(
        id: String,
        title: String,
        message: String,
        location: PreflightIssueLocation?
    ) -> PreflightIssue {
        PreflightIssue(
            id: id,
            severity: .info,
            title: title,
            message: message,
            location: location,
            isAutoFixable: false,
            autoFixDescription: nil
        )
    }

    private func formatted(_ value: CGFloat) -> String {
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private func formattedMillimeters(_ size: CGSize) -> String {
        let width = size.width * LayoutCalculator.millimetersPerInch / LayoutCalculator.pointsPerInch
        let height = size.height * LayoutCalculator.millimetersPerInch / LayoutCalculator.pointsPerInch
        return "\(formatted(width))×\(formatted(height))mm"
    }
}
