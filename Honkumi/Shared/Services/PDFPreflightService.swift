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
        var issues: [PreflightIssue] = []
        let normalizationReport = ManuscriptRenderPipeline.printTextNormalizationReport(
            for: checkedDocument,
            subscriptionStatus: subscriptionStatus
        )

        if normalizationReport.heartReplacementCount > 0 {
            issues.append(warning(
                id: "print.textNormalization.heart",
                title: "ハートを印刷用文字に置換します",
                message: "ハートが\(normalizationReport.heartReplacementCount)件含まれています。PDFでは♡に置換します。",
                location: .init(
                    type: .text,
                    pageNumber: nil,
                    characterRange: nil,
                    settingKey: nil
                )
            ))
        }

        if normalizationReport.unsupportedEmojiReplacementCount > 0 {
            issues.append(warning(
                id: "print.textNormalization.unsupportedEmoji",
                title: "未対応絵文字を印刷用文字に置換します",
                message: "未対応絵文字が\(normalizationReport.unsupportedEmojiReplacementCount)件含まれています。PDFでは□に置換します。",
                location: .init(
                    type: .text,
                    pageNumber: nil,
                    characterRange: nil,
                    settingKey: nil
                )
            ))
        }

        checkBody(
            effectiveDocument.body,
            parsed: parsed,
            settings: effectiveSettings,
            subscriptionStatus: subscriptionStatus,
            into: &issues
        )
        checkPageStructure(
            document: effectiveDocument,
            parsed: parsed,
            pages: pages,
            subscriptionStatus: subscriptionStatus,
            into: &issues
        )
        checkPrintSettings(effectiveSettings, into: &issues)
        checkPDFDisplay(settings: effectiveSettings, pages: pages, into: &issues)
        checkChapterHeaderLayout(
            settings: effectiveSettings,
            pages: pages,
            subscriptionStatus: subscriptionStatus,
            into: &issues
        )
        checkPageNumberRenderingPolicy(settings: effectiveSettings, pages: pages, into: &issues)
        checkRecommendedSettingsConformance(settings: effectiveSettings, pages: pages, into: &issues)
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
            into: &issues
        )

        return PreflightResult(issues: issues)
    }

    func autoFixedDocument(
        from document: ManuscriptDocument,
        subscriptionStatus: SubscriptionStatus
    ) -> ManuscriptDocument {
        var fixedDocument = document
        fixedDocument.body = autoFixedBody(
            document.body,
            settings: document.settings.validated,
            subscriptionStatus: subscriptionStatus
        )
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
        subscriptionStatus: SubscriptionStatus,
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

        if let periodRange = ManuscriptFormatter.firstPeriodBeforeClosingBracketRange(in: body) {
            let isPaid = subscriptionStatus == .paid
            issues.append(warning(
                id: "body.periodBeforeClosingQuote",
                title: "閉じ鉤括弧の前に句点があります",
                message: isPaid
                    ? "閉じかっこ直前の句点は、自動修正で本文から削除できます。"
                    : "表記ルールによっては入稿前の確認が必要です。Honkumi Proでは自動修正できます。",
                location: .init(type: .text, pageNumber: nil, characterRange: periodRange, settingKey: nil),
                isAutoFixable: isPaid,
                autoFixDescription: isPaid ? "閉じかっこ直前の句点を本文から削除します。" : nil
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

    private func checkPageNumberRenderingPolicy(
        settings: EditorSettings,
        pages: [PreviewPage],
        into issues: inout [PreflightIssue]
    ) {
        guard settings.isPageNumberEnabled else { return }

        let pageKinds = pages.map(pageNumberContentKind)
        let displayedPageNumbers = PDFPageNumberPolicy.displayedPageNumbers(
            for: pageKinds,
            settings: settings
        )

        func hasMissingPageNumber(for pageKind: PDFPageNumberContentKind) -> Bool {
            zip(pageKinds, displayedPageNumbers).contains { candidateKind, displayedPageNumber in
                candidateKind == pageKind && displayedPageNumber == nil
            }
        }

        if hasMissingPageNumber(for: .body) {
            issues.append(warning(
                id: "display.pageNumberMissing.body",
                title: "本文ページにノンブルが表示されません",
                message: "ノンブルを表示する設定ですが、本文ページにノンブルが出ない状態です。表示位置の設定を確認してください。",
                location: .init(type: .settings, pageNumber: nil, characterRange: nil, settingKey: "pageNumberPosition")
            ))
        }

        if settings.showPageNumberOnToc,
           hasMissingPageNumber(for: .tableOfContents) {
            issues.append(warning(
                id: "display.pageNumberMissing.toc",
                title: "目次ページにノンブルが表示されません",
                message: "目次にノンブルを表示する設定ですが、PDF上では非表示になる状態です。",
                location: .init(type: .toc, pageNumber: nil, characterRange: nil, settingKey: "showPageNumberOnToc")
            ))
        }

        if settings.showPageNumberOnColophon,
           hasMissingPageNumber(for: .colophon) {
            issues.append(warning(
                id: "display.pageNumberMissing.colophon",
                title: "奥付ページにノンブルが表示されません",
                message: "奥付にノンブルを表示する設定ですが、PDF上では非表示になる状態です。",
                location: .init(type: .colophon, pageNumber: nil, characterRange: nil, settingKey: "showPageNumberOnColophon")
            ))
        }
    }

    private func checkChapterHeaderLayout(
        settings: EditorSettings,
        pages: [PreviewPage],
        subscriptionStatus: SubscriptionStatus,
        into issues: inout [PreflightIssue]
    ) {
        let plan = ChapterHeaderLayoutPlanner.makePlan(
            pages: pages,
            settings: settings,
            subscriptionStatus: subscriptionStatus
        )

        for issue in plan.issues {
            let pageNumbersText = issue.pageNumbers.map(String.init).joined(separator: "・")
            issues.append(error(
                id: "pdf.chapterHeader.overflow.chapter.\(issue.chapterIndex)",
                title: "章タイトルがページ内に収まりません",
                message: "「\(issue.title)」は \(pageNumbersText) ページの上部に収まりません。章タイトルを短くしてください。",
                location: .init(
                    type: .page,
                    pageNumber: issue.pageNumbers.first,
                    characterRange: nil,
                    settingKey: "showChapterTitle"
                )
            ))
        }
    }

    private func checkRecommendedSettingsConformance(
        settings: EditorSettings,
        pages: [PreviewPage],
        into issues: inout [PreflightIssue]
    ) {
        guard settings.useRecommendedTypography || settings.useRecommendedMargins,
              let recommendation = RecommendedPrintSettings.recommendation(
                for: settings.pageSize,
                estimatedPageCount: pages.count
              ) else {
            return
        }

        var mismatches: [String] = []

        if settings.useRecommendedTypography {
            if settings.charactersPerLine != recommendation.charactersPerLine {
                mismatches.append("文字数 \(settings.charactersPerLine)字 / 推奨 \(recommendation.charactersPerLine)字")
            }
            if settings.linesPerPage != recommendation.linesPerPage {
                mismatches.append("行数 \(settings.linesPerPage)行 / 推奨 \(recommendation.linesPerPage)行")
            }
            if !approximatelyEqual(settings.fontSize, recommendation.fontSizePt) {
                mismatches.append("文字サイズ \(formatted(settings.fontSize))pt / 推奨 \(formatted(recommendation.fontSizePt))pt")
            }
        }

        if settings.useRecommendedMargins {
            if !approximatelyEqual(settings.marginTop, recommendation.marginTopMm) {
                mismatches.append("天 \(formatted(settings.marginTop))mm / 推奨 \(formatted(recommendation.marginTopMm))mm")
            }
            if !approximatelyEqual(settings.marginBottom, recommendation.marginBottomMm) {
                mismatches.append("地 \(formatted(settings.marginBottom))mm / 推奨 \(formatted(recommendation.marginBottomMm))mm")
            }
            if !approximatelyEqual(settings.marginInner, recommendation.marginInnerMm) {
                mismatches.append("ノド \(formatted(settings.marginInner))mm / 推奨 \(formatted(recommendation.marginInnerMm))mm")
            }
            if !approximatelyEqual(settings.marginOuter, recommendation.marginOuterMm) {
                mismatches.append("小口 \(formatted(settings.marginOuter))mm / 推奨 \(formatted(recommendation.marginOuterMm))mm")
            }
        }

        guard !mismatches.isEmpty else { return }

        issues.append(warning(
            id: "settings.recommendedValuesMismatch",
            title: "推奨設定とPDF設定が一致していません",
            message: "推奨設定がオンですが、最終ページ数に対する推奨値と異なる項目があります: \(mismatches.joined(separator: "、"))。",
            location: .init(type: .settings, pageNumber: nil, characterRange: nil, settingKey: "recommendedPrintSettings")
        ))
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

    }

    private func checkPrintProduction(
        settings: EditorSettings,
        pages: [PreviewPage],
        subscriptionStatus: SubscriptionStatus,
        into issues: inout [PreflightIssue]
    ) {
        checkFontEmbedding(settings: settings, subscriptionStatus: subscriptionStatus, into: &issues)
        checkImageQuality(settings: settings, pages: pages, subscriptionStatus: subscriptionStatus, into: &issues)
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
        let canLoadBodyFont = bodyFont.postScriptName.map { postScriptName in
            bodyFont.fileName != nil && UIFont(name: postScriptName, size: 10) != nil
        } ?? false
        if !canLoadBodyFont {
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
            if UIFont(name: pageNumberFont.postScriptName, size: 10) == nil {
                issues.append(warning(
                    id: "print.fontEmbedding.pageNumberFallback",
                    title: "ノンブルフォントの埋め込み確認が必要です",
                    message: "選択中のノンブルフォントを読み込めないため、本文フォントへフォールバックする可能性があります。",
                    location: .init(type: .settings, pageNumber: nil, characterRange: nil, settingKey: "pageNumberFontId")
                ))
            }
        }
    }

    private func checkImageQuality(
        settings: EditorSettings,
        pages: [PreviewPage],
        subscriptionStatus: SubscriptionStatus,
        into issues: inout [PreflightIssue]
    ) {
        guard subscriptionStatus == .paid,
              settings.colophon.hasCreatorImage,
              let imageData = settings.colophon.circleImageData,
              let image = UIImage(data: imageData),
              let cgImage = image.cgImage else {
            return
        }

        let layout = LayoutCalculator.layout(for: settings, pageNumber: max(pages.count, 1))
        let lineHeight = max(layout.fontSize * 1.65, 12)
        guard let placement = CircleLogoRenderPlacement.make(
            imageSize: image.size,
            bodyFrame: layout.bodyFrame,
            lineHeight: lineHeight,
            y: 0
        ) else { return }

        let ppiX = CGFloat(cgImage.width) / max(
            placement.rect.width / LayoutCalculator.pointsPerInch,
            0.01
        )
        let ppiY = CGFloat(cgImage.height) / max(
            placement.rect.height / LayoutCalculator.pointsPerInch,
            0.01
        )
        let effectivePPI = min(ppiX, ppiY)

        if effectivePPI < 300 {
            issues.append(warning(
                id: "print.imageResolution.lowCreator",
                title: "画像解像度が低い可能性があります",
                message: "奥付のサークル画像は実寸配置で約\(formatted(effectivePPI))ppiです。300ppi以上を目安にしてください。",
                location: .init(type: .colophon, pageNumber: pages.count, characterRange: nil, settingKey: "circleImageData")
            ))
        }
    }

    private func pageNumberContentKind(for page: PreviewPage) -> PDFPageNumberContentKind {
        switch page.kind {
        case .body:
            .body
        case .tableOfContents:
            .tableOfContents
        case .colophon:
            .colophon
        }
    }

    private func approximatelyEqual(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) <= 0.001
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

    private func autoFixedBody(
        _ body: String,
        settings: EditorSettings,
        subscriptionStatus: SubscriptionStatus
    ) -> String {
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

        var fixedBody = normalized.joined(separator: "\n")
        if subscriptionStatus == .paid {
            fixedBody = ManuscriptFormatter.removePeriodsBeforeClosingBrackets(fixedBody)
        }

        return fixedBody
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

    private func formatted(_ value: CGFloat) -> String {
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}
