import CoreGraphics
import Foundation

nonisolated struct RecommendedLayoutSetting: Equatable {
    var charactersPerLine: Int
    var linesPerPage: Int
    var fontSizePt: CGFloat
    var marginTopMm: CGFloat
    var marginBottomMm: CGFloat
    var marginInnerMm: CGFloat
    var marginOuterMm: CGFloat
}

nonisolated enum RecommendedPrintSettings {
    static let unsupportedPageSizeMessage = "A5/B5の推奨設定は今後対応予定です"
    static let wideGutterNote = "ページ数が多い本では、製本後にノド側が読みにくくなるため、ノド余白を広めに設定しています。"

    private enum PageBand: CaseIterable, Hashable {
        case upTo48
        case upTo96
        case upTo160
        case upTo240
        case over240

        init(pageCount: Int) {
            switch pageCount {
            case ...48:
                self = .upTo48
            case 49...96:
                self = .upTo96
            case 97...160:
                self = .upTo160
            case 161...240:
                self = .upTo240
            default:
                self = .over240
            }
        }
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
              let standardPreset = recommendation(for: validated.pageSize, estimatedPageCount: 1) else {
            return validated
        }

        var recommended = settingsByApplyingPreset(standardPreset, to: validated)
        let firstPageCount = estimatedPageCount(body: body, settings: recommended)
        recommended = settingsByApplyingRecommendation(
            to: validated,
            estimatedPageCount: firstPageCount
        )

        for _ in 0..<2 {
            let pageCount = estimatedPageCount(body: body, settings: recommended)
            let next = settingsByApplyingRecommendation(to: validated, estimatedPageCount: pageCount)
            if next == recommended {
                break
            }
            recommended = next
        }

        return recommended.validated
    }

    static func effectiveSettings(
        settings: EditorSettings,
        estimatedPageCount: Int
    ) -> EditorSettings {
        let validated = settings.validated
        guard validated.useRecommendedTypography || validated.useRecommendedMargins else {
            return validated
        }

        return settingsByApplyingRecommendation(
            to: validated,
            estimatedPageCount: estimatedPageCount
        ).validated
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
        return estimatedPageCount(body: body, settings: effectiveSettings) >= 97
    }

    static func recommendation(
        for pageSize: PageSize,
        estimatedPageCount: Int
    ) -> RecommendedLayoutSetting? {
        guard let preset = presetTable[pageSize]?[PageBand(pageCount: estimatedPageCount)] else {
            return nil
        }
        return readableRecommendation(from: preset, pageSize: pageSize)
    }

    private static func settingsByApplyingRecommendation(
        to settings: EditorSettings,
        estimatedPageCount: Int
    ) -> EditorSettings {
        guard let preset = recommendation(for: settings.pageSize, estimatedPageCount: estimatedPageCount) else {
            return settings.validated
        }
        return settingsByApplyingPreset(preset, to: settings)
    }

    private static func settingsByApplyingPreset(
        _ preset: RecommendedLayoutSetting,
        to settings: EditorSettings
    ) -> EditorSettings {
        var updated = settings.validated

        if updated.useRecommendedMargins {
            updated.marginTop = preset.marginTopMm
            updated.marginBottom = preset.marginBottomMm
            updated.marginInner = preset.marginInnerMm
            updated.marginOuter = preset.marginOuterMm
        }

        if updated.useRecommendedTypography {
            let readablePreset = readableRecommendation(
                from: preset,
                pageSize: updated.pageSize,
                marginTopMm: updated.marginTop,
                marginBottomMm: updated.marginBottom,
                marginInnerMm: updated.marginInner,
                marginOuterMm: updated.marginOuter
            )
            updated.fontSize = readablePreset.fontSizePt
            updated.charactersPerLine = readablePreset.charactersPerLine
            updated.linesPerPage = readablePreset.linesPerPage
        }

        updated.lineSpacing = 0
        updated.characterSpacing = 0
        return updated.validated
    }

    private static let minimumReadableCharacterAdvanceRatio: CGFloat = 0.9
    private static let minimumReadableLineAdvanceRatio: CGFloat = 1.5
    private static let fallbackFontSizeStep: CGFloat = 0.5

    private static func readableRecommendation(
        from preset: RecommendedLayoutSetting,
        pageSize: PageSize
    ) -> RecommendedLayoutSetting {
        readableRecommendation(
            from: preset,
            pageSize: pageSize,
            marginTopMm: preset.marginTopMm,
            marginBottomMm: preset.marginBottomMm,
            marginInnerMm: preset.marginInnerMm,
            marginOuterMm: preset.marginOuterMm
        )
    }

    private static func readableRecommendation(
        from preset: RecommendedLayoutSetting,
        pageSize: PageSize,
        marginTopMm: CGFloat,
        marginBottomMm: CGFloat,
        marginInnerMm: CGFloat,
        marginOuterMm: CGFloat
    ) -> RecommendedLayoutSetting {
        let bodyWidth = max(
            LayoutCalculator.millimetersToPoints(CGFloat(pageSize.widthMillimeters) - marginInnerMm - marginOuterMm),
            1
        )
        let bodyHeight = max(
            LayoutCalculator.millimetersToPoints(CGFloat(pageSize.heightMillimeters) - marginTopMm - marginBottomMm),
            1
        )
        let fontSize = readableFontSize(
            requestedFontSize: preset.fontSizePt,
            bodyWidth: bodyWidth,
            bodyHeight: bodyHeight
        )

        return RecommendedLayoutSetting(
            charactersPerLine: readableCount(
                requestedCount: preset.charactersPerLine,
                availableAdvance: bodyHeight,
                minimumAdvance: fontSize * minimumReadableCharacterAdvanceRatio,
                range: EditorSettings.charactersPerLineRange
            ),
            linesPerPage: readableCount(
                requestedCount: preset.linesPerPage,
                availableAdvance: bodyWidth,
                minimumAdvance: fontSize * minimumReadableLineAdvanceRatio,
                range: EditorSettings.linesPerPageRange
            ),
            fontSizePt: fontSize,
            marginTopMm: preset.marginTopMm,
            marginBottomMm: preset.marginBottomMm,
            marginInnerMm: preset.marginInnerMm,
            marginOuterMm: preset.marginOuterMm
        )
    }

    private static func readableFontSize(
        requestedFontSize: CGFloat,
        bodyWidth: CGFloat,
        bodyHeight: CGFloat
    ) -> CGFloat {
        let minimumFontSize = EditorSettings.fontSizeRange.lowerBound
        var fontSize = EditorSettings.roundedPrintFontSize(requestedFontSize)

        while fontSize > minimumFontSize {
            let fitsMinimumCharacterCount = maximumReadableCount(
                availableAdvance: bodyHeight,
                minimumAdvance: fontSize * minimumReadableCharacterAdvanceRatio
            ) >= EditorSettings.charactersPerLineRange.lowerBound
            let fitsMinimumLineCount = maximumReadableCount(
                availableAdvance: bodyWidth,
                minimumAdvance: fontSize * minimumReadableLineAdvanceRatio
            ) >= EditorSettings.linesPerPageRange.lowerBound

            if fitsMinimumCharacterCount && fitsMinimumLineCount {
                break
            }

            fontSize = max(minimumFontSize, fontSize - fallbackFontSizeStep)
        }

        return EditorSettings.roundedPrintFontSize(fontSize)
    }

    private static func readableCount(
        requestedCount: Int,
        availableAdvance: CGFloat,
        minimumAdvance: CGFloat,
        range: ClosedRange<Int>
    ) -> Int {
        let maximumCount = maximumReadableCount(
            availableAdvance: availableAdvance,
            minimumAdvance: minimumAdvance
        )
        return min(requestedCount, maximumCount)
            .clamped(to: range)
    }

    private static func maximumReadableCount(
        availableAdvance: CGFloat,
        minimumAdvance: CGFloat
    ) -> Int {
        guard minimumAdvance > 0 else { return Int.max }
        return max(Int(floor(availableAdvance / minimumAdvance)), 1)
    }

    private static let presetTable: [PageSize: [PageBand: RecommendedLayoutSetting]] = [
        .a6: [
            .upTo48: RecommendedLayoutSetting(
                charactersPerLine: 34,
                linesPerPage: 14,
                fontSizePt: 10.0,
                marginTopMm: 18,
                marginBottomMm: 20,
                marginInnerMm: 16,
                marginOuterMm: 13
            ),
            .upTo96: RecommendedLayoutSetting(
                charactersPerLine: 38,
                linesPerPage: 16,
                fontSizePt: 9.5,
                marginTopMm: 17,
                marginBottomMm: 19,
                marginInnerMm: 18,
                marginOuterMm: 12
            ),
            .upTo160: RecommendedLayoutSetting(
                charactersPerLine: 39,
                linesPerPage: 17,
                fontSizePt: 9.0,
                marginTopMm: 16,
                marginBottomMm: 18,
                marginInnerMm: 22,
                marginOuterMm: 11
            ),
            .upTo240: RecommendedLayoutSetting(
                charactersPerLine: 40,
                linesPerPage: 17,
                fontSizePt: 9.0,
                marginTopMm: 15,
                marginBottomMm: 17,
                marginInnerMm: 24,
                marginOuterMm: 10
            ),
            .over240: RecommendedLayoutSetting(
                charactersPerLine: 40,
                linesPerPage: 18,
                fontSizePt: 8.5,
                marginTopMm: 15,
                marginBottomMm: 16,
                marginInnerMm: 26,
                marginOuterMm: 10
            )
        ],
        .shinsho: [
            .upTo48: RecommendedLayoutSetting(
                charactersPerLine: 38,
                linesPerPage: 15,
                fontSizePt: 10.0,
                marginTopMm: 20,
                marginBottomMm: 22,
                marginInnerMm: 16,
                marginOuterMm: 13
            ),
            .upTo96: RecommendedLayoutSetting(
                charactersPerLine: 40,
                linesPerPage: 16,
                fontSizePt: 9.5,
                marginTopMm: 20,
                marginBottomMm: 20,
                marginInnerMm: 18,
                marginOuterMm: 12
            ),
            .upTo160: RecommendedLayoutSetting(
                charactersPerLine: 41,
                linesPerPage: 17,
                fontSizePt: 9.0,
                marginTopMm: 19,
                marginBottomMm: 19,
                marginInnerMm: 22,
                marginOuterMm: 11
            ),
            .upTo240: RecommendedLayoutSetting(
                charactersPerLine: 42,
                linesPerPage: 17,
                fontSizePt: 9.0,
                marginTopMm: 18,
                marginBottomMm: 18,
                marginInnerMm: 24,
                marginOuterMm: 10
            ),
            .over240: RecommendedLayoutSetting(
                charactersPerLine: 45,
                linesPerPage: 18,
                fontSizePt: 8.5,
                marginTopMm: 18,
                marginBottomMm: 17,
                marginInnerMm: 26,
                marginOuterMm: 10
            )
        ],
        .b6: [
            .upTo48: RecommendedLayoutSetting(
                charactersPerLine: 42,
                linesPerPage: 15,
                fontSizePt: 10.0,
                marginTopMm: 20,
                marginBottomMm: 22,
                marginInnerMm: 17,
                marginOuterMm: 15
            ),
            .upTo96: RecommendedLayoutSetting(
                charactersPerLine: 44,
                linesPerPage: 16,
                fontSizePt: 9.5,
                marginTopMm: 19,
                marginBottomMm: 21,
                marginInnerMm: 19,
                marginOuterMm: 14
            ),
            .upTo160: RecommendedLayoutSetting(
                charactersPerLine: 45,
                linesPerPage: 17,
                fontSizePt: 9.0,
                marginTopMm: 18,
                marginBottomMm: 20,
                marginInnerMm: 23,
                marginOuterMm: 13
            ),
            .upTo240: RecommendedLayoutSetting(
                charactersPerLine: 46,
                linesPerPage: 17,
                fontSizePt: 9.0,
                marginTopMm: 17,
                marginBottomMm: 19,
                marginInnerMm: 25,
                marginOuterMm: 12
            ),
            .over240: RecommendedLayoutSetting(
                charactersPerLine: 47,
                linesPerPage: 18,
                fontSizePt: 8.5,
                marginTopMm: 16,
                marginBottomMm: 18,
                marginInnerMm: 27,
                marginOuterMm: 12
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

nonisolated private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
