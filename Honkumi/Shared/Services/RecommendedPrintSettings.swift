import CoreGraphics
import Foundation

nonisolated enum RecommendedPrintSettings {
    static let unsupportedPageSizeMessage = "A5/B5の推奨設定は段組み対応後に利用できます"
    static let wideGutterNote = "ページ数が多い本では、製本後にノド側が読みにくくなるため、ノド余白を広めに設定しています。"

    private enum PageBand: CaseIterable, Hashable {
        case upTo48
        case upTo99
        case upTo199
        case over200

        init(pageCount: Int) {
            switch pageCount {
            case ...48:
                self = .upTo48
            case 49...99:
                self = .upTo99
            case 100...199:
                self = .upTo199
            default:
                self = .over200
            }
        }
    }

    private struct Preset: Equatable {
        var fontSize: CGFloat
        var charactersPerLine: Int
        var linesPerPage: Int
        var marginTop: CGFloat
        var marginBottom: CGFloat
        var marginInner: CGFloat
        var marginOuter: CGFloat
    }

    static func effectiveSettings(for document: ManuscriptDocument) -> EditorSettings {
        effectiveSettings(body: document.body, settings: document.settings)
    }

    static func effectiveSettings(body: String, settings: EditorSettings) -> EditorSettings {
        let validated = settings.validated
        guard validated.useRecommendedTypography || validated.useRecommendedMargins else {
            return validated
        }

        guard supportsRecommendations(for: validated.pageSize),
              let standardPreset = preset(for: validated.pageSize, band: .upTo48) else {
            return validated
        }

        var recommended = settingsByApplyingPreset(standardPreset, to: validated)
        let firstPageCount = recommendationPageCount(body: body, settings: recommended)
        recommended = settingsByApplyingRecommendation(
            to: validated,
            estimatedPageCount: firstPageCount
        )

        for _ in 0..<2 {
            let pageCount = recommendationPageCount(body: body, settings: recommended)
            let next = settingsByApplyingRecommendation(to: validated, estimatedPageCount: pageCount)
            if next == recommended {
                break
            }
            recommended = next
        }

        return recommended.validated
    }

    static func estimatedPageCount(body: String, settings: EditorSettings) -> Int {
        let settings = settings.validated
        let charactersPerLine = max(settings.charactersPerLine, 1)
        let linesPerPage = max(settings.linesPerPage, 1)
        let parsed = ManuscriptMarkupParser.parse(body)
        var pageCount = 0
        var currentLineCount = 0
        var chapterCount = 0
        var hasExplicitColophon = false

        func finishCurrentPageSet() {
            guard currentLineCount > 0 else { return }
            pageCount += Int(ceil(CGFloat(currentLineCount) / CGFloat(linesPerPage)))
            currentLineCount = 0
        }

        func appendLineCount(_ lineCount: Int) {
            currentLineCount += max(lineCount, 1)
        }

        for segment in parsed.segments {
            if segment.isTableOfContentsPlaceholder {
                continue
            }

            if segment.isColophonPlaceholder {
                finishCurrentPageSet()
                pageCount += 1
                hasExplicitColophon = true
                continue
            }

            if segment.startsAfterPageBreak
                || (settings.startsChapterOnNewPage && segment.startsChapter && currentLineCount > 0) {
                finishCurrentPageSet()
            }

            if let chapterTitle = segment.chapterTitle, segment.startsChapter {
                chapterCount += 1
                let titleLineCount = estimatedLineCount(
                    for: ChapterTitleFormatter.format(chapterTitle, style: settings.chapterTitleStyle),
                    charactersPerLine: charactersPerLine,
                    alphanumericOrientation: settings.alphanumericOrientation
                )
                appendLineCount(titleLineCount + 2)
            }

            for line in segment.text.components(separatedBy: .newlines) {
                appendLineCount(
                    estimatedLineCount(
                        for: line,
                        charactersPerLine: charactersPerLine,
                        alphanumericOrientation: settings.alphanumericOrientation
                    )
                )
            }
        }

        finishCurrentPageSet()

        if settings.showTableOfContents {
            let tableOfContentsLineCount = max(chapterCount + 2, 1)
            pageCount += Int(ceil(CGFloat(tableOfContentsLineCount) / CGFloat(linesPerPage)))
        }

        if settings.colophon.isEnabled && !hasExplicitColophon {
            pageCount += 1
        }

        return max(pageCount, 1)
    }

    static func supportsRecommendations(for pageSize: PageSize) -> Bool {
        presetTable[pageSize] != nil
    }

    static func shouldShowWideGutterNote(body: String, settings: EditorSettings) -> Bool {
        let settings = settings.validated
        guard settings.useRecommendedMargins,
              supportsRecommendations(for: settings.pageSize) else {
            return false
        }

        let effectiveSettings = effectiveSettings(body: body, settings: settings)
        return estimatedPageCount(body: body, settings: effectiveSettings) >= 100
    }

    private static func settingsByApplyingRecommendation(
        to settings: EditorSettings,
        estimatedPageCount: Int
    ) -> EditorSettings {
        let band = PageBand(pageCount: estimatedPageCount)
        guard let preset = preset(for: settings.pageSize, band: band) else {
            return settings.validated
        }
        return settingsByApplyingPreset(preset, to: settings)
    }

    private static func settingsByApplyingPreset(
        _ preset: Preset,
        to settings: EditorSettings
    ) -> EditorSettings {
        var updated = settings.validated

        if updated.useRecommendedTypography {
            updated.fontSize = preset.fontSize
            updated.charactersPerLine = preset.charactersPerLine
            updated.linesPerPage = preset.linesPerPage
        }

        if updated.useRecommendedMargins {
            updated.marginTop = preset.marginTop
            updated.marginBottom = preset.marginBottom
            updated.marginInner = preset.marginInner
            updated.marginOuter = preset.marginOuter
        }

        updated.lineSpacing = 0
        updated.characterSpacing = 0
        return updated.validated
    }

    private static func recommendationPageCount(body: String, settings: EditorSettings) -> Int {
        let settings = settings.validated
        let bodyCharacterCount = ManuscriptMarkupParser.characterCountBody(from: body).count
        let charactersPerPage = max(settings.charactersPerLine * settings.linesPerPage, 1)
        return max(Int(ceil(CGFloat(bodyCharacterCount) / CGFloat(charactersPerPage))), 1)
    }

    private static func preset(for pageSize: PageSize, band: PageBand) -> Preset? {
        presetTable[pageSize]?[band]
    }

    private static let presetTable: [PageSize: [PageBand: Preset]] = [
        .a6: [
            .upTo48: Preset(
                fontSize: 9.0,
                charactersPerLine: 38,
                linesPerPage: 16,
                marginTop: 16,
                marginBottom: 16,
                marginInner: 15,
                marginOuter: 13
            ),
            .upTo99: Preset(
                fontSize: 8.5,
                charactersPerLine: 40,
                linesPerPage: 17,
                marginTop: 15,
                marginBottom: 15,
                marginInner: 20,
                marginOuter: 12
            ),
            .upTo199: Preset(
                fontSize: 8.5,
                charactersPerLine: 42,
                linesPerPage: 17,
                marginTop: 14,
                marginBottom: 14,
                marginInner: 25,
                marginOuter: 11
            ),
            .over200: Preset(
                fontSize: 8.0,
                charactersPerLine: 43,
                linesPerPage: 18,
                marginTop: 13,
                marginBottom: 13,
                marginInner: 25,
                marginOuter: 11
            )
        ],
        .shinsho: [
            .upTo48: Preset(
                fontSize: 9.0,
                charactersPerLine: 39,
                linesPerPage: 15,
                marginTop: 20,
                marginBottom: 20,
                marginInner: 15,
                marginOuter: 14
            ),
            .upTo99: Preset(
                fontSize: 8.5,
                charactersPerLine: 40,
                linesPerPage: 16,
                marginTop: 18,
                marginBottom: 18,
                marginInner: 20,
                marginOuter: 13
            ),
            .upTo199: Preset(
                fontSize: 8.5,
                charactersPerLine: 41,
                linesPerPage: 17,
                marginTop: 17,
                marginBottom: 17,
                marginInner: 25,
                marginOuter: 12
            ),
            .over200: Preset(
                fontSize: 8.0,
                charactersPerLine: 42,
                linesPerPage: 18,
                marginTop: 16,
                marginBottom: 16,
                marginInner: 25,
                marginOuter: 11
            )
        ],
        .b6: [
            .upTo48: Preset(
                fontSize: 9.5,
                charactersPerLine: 42,
                linesPerPage: 16,
                marginTop: 18,
                marginBottom: 18,
                marginInner: 15,
                marginOuter: 14
            ),
            .upTo99: Preset(
                fontSize: 9.0,
                charactersPerLine: 44,
                linesPerPage: 17,
                marginTop: 17,
                marginBottom: 17,
                marginInner: 20,
                marginOuter: 13
            ),
            .upTo199: Preset(
                fontSize: 8.5,
                charactersPerLine: 46,
                linesPerPage: 17,
                marginTop: 16,
                marginBottom: 16,
                marginInner: 25,
                marginOuter: 12
            ),
            .over200: Preset(
                fontSize: 8.5,
                charactersPerLine: 47,
                linesPerPage: 18,
                marginTop: 15,
                marginBottom: 15,
                marginInner: 25,
                marginOuter: 11
            )
        ]
    ]

    private static func estimatedLineCount(
        for line: String,
        charactersPerLine: Int,
        alphanumericOrientation: AlphanumericOrientation
    ) -> Int {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty else { return 1 }

        let cellCount = VerticalTextTypesetter.cellCount(
            for: trimmedLine,
            alphanumericOrientation: alphanumericOrientation
        )
        return max(Int(ceil(CGFloat(cellCount) / CGFloat(max(charactersPerLine, 1)))), 1)
    }
}
