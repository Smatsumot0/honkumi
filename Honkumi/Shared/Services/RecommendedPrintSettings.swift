import CoreGraphics
import Foundation

nonisolated enum RecommendedPrintSettings {
    private enum PageVolume {
        case short
        case standard
        case long
        case veryLong

        init(pageCount: Int) {
            switch pageCount {
            case ..<50:
                self = .short
            case 50...150:
                self = .standard
            case 151...300:
                self = .long
            default:
                self = .veryLong
            }
        }
    }

    private struct Preset {
        var fontSize: CGFloat
        var charactersPerLine: Int
        var linesPerPage: Int
        var marginTop: CGFloat
        var marginBottom: CGFloat
        var marginInner: CGFloat
        var marginOuter: CGFloat
        var lineSpacing: CGFloat
        var characterSpacing: CGFloat
    }

    static func effectiveSettings(for document: ManuscriptDocument) -> EditorSettings {
        effectiveSettings(body: document.body, settings: document.settings)
    }

    static func effectiveSettings(body: String, settings: EditorSettings) -> EditorSettings {
        let validated = settings.validated
        guard validated.useRecommendedPrintSettings else { return validated }

        var recommended = settingsByApplyingRecommendation(
            to: validated,
            estimatedPageCount: estimatedPageCount(body: body, settings: validated)
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

    private static func settingsByApplyingRecommendation(
        to settings: EditorSettings,
        estimatedPageCount: Int
    ) -> EditorSettings {
        var updated = settings.validated
        let preset = adjustedPreset(
            basePreset(for: updated.pageSize),
            volume: PageVolume(pageCount: estimatedPageCount)
        )

        updated.selectedFontId = AppFontCatalog.defaultFontId
        updated.fontSize = preset.fontSize
        updated.charactersPerLine = preset.charactersPerLine
        updated.linesPerPage = preset.linesPerPage
        updated.marginTop = preset.marginTop
        updated.marginBottom = preset.marginBottom
        updated.marginInner = preset.marginInner
        updated.marginOuter = preset.marginOuter
        updated.lineSpacing = preset.lineSpacing
        updated.characterSpacing = preset.characterSpacing
        updated.useRecommendedPrintSettings = true
        return updated.validated
    }

    private static func basePreset(for pageSize: PageSize) -> Preset {
        switch pageSize {
        case .a6:
            Preset(
                fontSize: 9,
                charactersPerLine: 40,
                linesPerPage: 17,
                marginTop: 18,
                marginBottom: 16,
                marginInner: 14,
                marginOuter: 12,
                lineSpacing: 1,
                characterSpacing: 0.2
            )
        case .shinsho:
            Preset(
                fontSize: 9,
                charactersPerLine: 42,
                linesPerPage: 18,
                marginTop: 18,
                marginBottom: 16,
                marginInner: 15,
                marginOuter: 12,
                lineSpacing: 1,
                characterSpacing: 0.2
            )
        case .b6:
            Preset(
                fontSize: 9.5,
                charactersPerLine: 44,
                linesPerPage: 19,
                marginTop: 19,
                marginBottom: 16,
                marginInner: 15,
                marginOuter: 12,
                lineSpacing: 1,
                characterSpacing: 0.2
            )
        case .a5:
            Preset(
                fontSize: 9.5,
                charactersPerLine: 48,
                linesPerPage: 22,
                marginTop: 20,
                marginBottom: 17,
                marginInner: 16,
                marginOuter: 13,
                lineSpacing: 1,
                characterSpacing: 0.2
            )
        case .b5:
            Preset(
                fontSize: 10,
                charactersPerLine: 51,
                linesPerPage: 25,
                marginTop: 22,
                marginBottom: 18,
                marginInner: 17,
                marginOuter: 14,
                lineSpacing: 1,
                characterSpacing: 0.2
            )
        }
    }

    private static func adjustedPreset(_ preset: Preset, volume: PageVolume) -> Preset {
        var adjusted = preset

        switch volume {
        case .short:
            adjusted.charactersPerLine -= 1
            adjusted.linesPerPage -= 1
            adjusted.marginTop += 1
            adjusted.marginBottom += 1
            adjusted.marginInner += 1
            adjusted.marginOuter += 1
            adjusted.lineSpacing = 1.5
            adjusted.characterSpacing = 0.4
        case .standard:
            break
        case .long:
            adjusted.charactersPerLine += 1
            adjusted.linesPerPage += 1
            adjusted.lineSpacing = 0.5
            adjusted.characterSpacing = 0.1
        case .veryLong:
            adjusted.fontSize -= 0.3
            adjusted.charactersPerLine += 2
            adjusted.linesPerPage += 2
            adjusted.marginInner += 1
            adjusted.lineSpacing = 0
            adjusted.characterSpacing = 0
        }

        adjusted.fontSize = clamped(adjusted.fontSize, to: EditorSettings.fontSizeRange)
        adjusted.charactersPerLine = clamped(adjusted.charactersPerLine, to: EditorSettings.charactersPerLineRange)
        adjusted.linesPerPage = clamped(adjusted.linesPerPage, to: EditorSettings.linesPerPageRange)
        adjusted.marginTop = clamped(adjusted.marginTop, to: EditorSettings.marginTopRange)
        adjusted.marginBottom = clamped(adjusted.marginBottom, to: EditorSettings.marginBottomRange)
        adjusted.marginInner = clamped(adjusted.marginInner, to: EditorSettings.marginInnerRange)
        adjusted.marginOuter = clamped(adjusted.marginOuter, to: EditorSettings.marginOuterRange)
        adjusted.lineSpacing = clamped(adjusted.lineSpacing, to: EditorSettings.lineSpacingRange)
        adjusted.characterSpacing = clamped(adjusted.characterSpacing, to: EditorSettings.characterSpacingRange)
        return adjusted
    }

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

    private static func clamped<Value: Comparable>(_ value: Value, to range: ClosedRange<Value>) -> Value {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
