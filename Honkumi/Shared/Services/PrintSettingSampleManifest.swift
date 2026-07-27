#if DEBUG
import CoreGraphics
import Foundation

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
        case .pages1Through48:
            1
        case .pages49Through96:
            49
        case .pages97Through160:
            97
        case .pages161Through240:
            161
        case .pages241AndOver:
            241
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
        case .pages1Through48:
            "001-048p"
        case .pages49Through96:
            "049-096p"
        case .pages97Through160:
            "097-160p"
        case .pages161Through240:
            "161-240p"
        case .pages241AndOver:
            "241p以上"
        }
    }
}

nonisolated enum PrintSettingSampleManifest {
    static func recommendedSettingCases() -> [RecommendedPrintSettingSampleCase] {
        PageSize.selectableCases.flatMap { pageSize in
            RecommendedSettingSamplePageBand.allCases.map { pageBand in
                let requestedPageCount = pageBand.representativePageCount
                var settings = EditorSettings.default.validated
                settings.pageSize = pageSize
                settings.useRecommendedTypography = true
                settings.useRecommendedMargins = true
                settings.showTableOfContents = false
                settings.showChapterTitle = false
                settings.showsCropMarks = false
                settings.colophon.isEnabled = false

                let document = ManuscriptDocument(
                    title: "推奨設定 \(pageSize.displayName) \(pageBand.fileComponent)",
                    body: fixedPageCountBody(requestedPageCount),
                    settings: settings
                )
                let effectiveSettings = RecommendedPrintSettings.effectiveSettings(for: document)
                let actualPageCount = RecommendedPrintSettings.estimatedPageCount(
                    body: document.body,
                    settings: effectiveSettings
                )
                let fileName = recommendedFileName(
                    pageSize: pageSize,
                    pageBand: pageBand,
                    actualPageCount: actualPageCount,
                    effectiveSettings: effectiveSettings
                )

                return RecommendedPrintSettingSampleCase(
                    output: PrintSettingSampleCase(
                        fileName: fileName,
                        outputDirectoryName: "RecommendedSettingSamples",
                        document: document
                    ),
                    requestedPageCount: requestedPageCount,
                    pageBand: pageBand
                )
            }
        }
    }

    static func fontSizeCases() -> [PrintSettingSampleCase] {
        (14...40).map { halfPoint in
            let fontSize = CGFloat(halfPoint) / 2
            var settings = EditorSettings.default.validated
            settings.pageSize = .a6
            settings.fontSize = fontSize
            settings.useRecommendedTypography = false
            settings.useRecommendedMargins = false
            settings.showTableOfContents = false
            settings.showChapterTitle = true
            settings.isPageNumberEnabled = true
            settings.pageNumberPosition = .outside
            settings.showsCropMarks = false
            settings.colophon.isEnabled = false

            return PrintSettingSampleCase(
                fileName: String(
                    format: "文字サイズ_%04.1fpt_A6.pdf",
                    Double(fontSize)
                ),
                outputDirectoryName: "FontSizeSamples",
                document: ManuscriptDocument(
                    title: String(format: "文字サイズ %.1fpt", Double(fontSize)),
                    body: fontSizeSampleBody,
                    settings: settings
                )
            )
        }
    }

    static func recommendedFileName(
        pageSize: PageSize,
        pageBand: RecommendedSettingSamplePageBand,
        actualPageCount: Int,
        effectiveSettings: EditorSettings
    ) -> String {
        String(
            format: "%@_%@_実%dp_%.1fpt_%d字_%d行_天%.1f_地%.1f_小口%.1f_ノド%.1f.pdf",
            pageSizeFileComponent(pageSize),
            pageBand.fileComponent,
            actualPageCount,
            Double(effectiveSettings.fontSize),
            effectiveSettings.charactersPerLine,
            effectiveSettings.linesPerPage,
            Double(effectiveSettings.marginTop),
            Double(effectiveSettings.marginBottom),
            Double(effectiveSettings.marginOuter),
            Double(effectiveSettings.marginInner)
        )
    }

    private static func fixedPageCountBody(_ pageCount: Int) -> String {
        (1...pageCount)
            .map { "推奨設定確認ページ \($0)\n句読点。、英数字PDF123、絵文字😀" }
            .joined(separator: "\n\(ManuscriptMarkupParser.pageBreakTag)\n")
    }

    private static let fontSizeSampleBody = """
    [[CHAPTER: 文字サイズ・章タイトル確認]]
    本文の句読点。、縦書き括弧「」と三点リーダー……を確認します。
    英数字 PDF 123 Next.js とノンブルを確認します。
    未対応絵文字😀は白い四角一文字になります。
    [[PAGE_BREAK]]
    章タイトル上部、本文、ノンブルの大きさを比較する二ページ目です。
    """

    private static func pageSizeFileComponent(_ pageSize: PageSize) -> String {
        switch pageSize {
        case .a6:
            "A6"
        case .shinsho:
            "新書"
        case .b6:
            "B6"
        case .a5:
            "A5"
        case .b5:
            "B5"
        }
    }
}
#endif
