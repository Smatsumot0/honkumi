import CoreGraphics
import XCTest
@testable import Honkumi

final class RecommendedPrintSettingsTests: XCTestCase {
    func testA6ShortRecommendationUsesReadableDensity() throws {
        let recommendation = try XCTUnwrap(
            RecommendedPrintSettings.recommendation(for: .a6, estimatedPageCount: 48)
        )

        XCTAssertEqual(recommendation.fontSizePt, 10.0, accuracy: 0.001)
        XCTAssertEqual(recommendation.charactersPerLine, 34)
        XCTAssertEqual(recommendation.linesPerPage, 14)
    }

    func testRecommendationsKeepMinimumReadableAdvancesBeforeReducingFontSize() throws {
        for pageSize in [PageSize.a6, .shinsho, .b6] {
            for estimatedPageCount in [1, 49, 97, 161, 241] {
                let recommendation = try XCTUnwrap(
                    RecommendedPrintSettings.recommendation(
                        for: pageSize,
                        estimatedPageCount: estimatedPageCount
                    )
                )
                let layout = LayoutCalculator.layout(
                    for: settings(from: recommendation, pageSize: pageSize),
                    pageNumber: 1
                )

                XCTAssertGreaterThanOrEqual(
                    layout.characterAdvance / layout.fontSize,
                    0.9,
                    "\(pageSize) \(estimatedPageCount)P should preserve readable character advance"
                )
                XCTAssertGreaterThanOrEqual(
                    layout.lineAdvance / layout.fontSize,
                    1.5,
                    "\(pageSize) \(estimatedPageCount)P should preserve readable line advance"
                )
            }
        }
    }

    func testEstimatedPageCountUsesReadableRecommendedDensity() {
        let body = String(repeating: "あ", count: 36 * 15)
        var settings = EditorSettings.default
        settings.pageSize = .a6
        settings.useRecommendedTypography = true
        settings.useRecommendedMargins = true

        let effectiveSettings = RecommendedPrintSettings.effectiveSettings(
            body: body,
            settings: settings
        )
        let estimatedPageCount = RecommendedPrintSettings.estimatedPageCount(
            body: body,
            settings: effectiveSettings
        )

        XCTAssertEqual(effectiveSettings.fontSize, 10.0, accuracy: 0.001)
        XCTAssertEqual(effectiveSettings.charactersPerLine, 34)
        XCTAssertEqual(effectiveSettings.linesPerPage, 14)
        XCTAssertEqual(estimatedPageCount, 2)
    }

    func testA6BoundaryRecommendationsRemainUnchanged() throws {
        try assertRecommendation(
            pageSize: .a6, pageCount: 160,
            fontSize: 9.0, characters: 39, lines: 15,
            top: 16, bottom: 18, outer: 11, inner: 22
        )
        try assertRecommendation(
            pageSize: .a6, pageCount: 161,
            fontSize: 9.0, characters: 40, lines: 14,
            top: 15, bottom: 17, outer: 10, inner: 24
        )
        try assertRecommendation(
            pageSize: .a6, pageCount: 240,
            fontSize: 9.0, characters: 40, lines: 14,
            top: 15, bottom: 17, outer: 10, inner: 24
        )
        try assertRecommendation(
            pageSize: .a6, pageCount: 241,
            fontSize: 8.5, characters: 40, lines: 15,
            top: 15, bottom: 16, outer: 10, inner: 26
        )
    }

    func testB6RecommendationsRemainUnchangedAcrossAllBands() throws {
        try assertRecommendation(
            pageSize: .b6, pageCount: 1,
            fontSize: 10.0, characters: 42, lines: 15,
            top: 20, bottom: 22, outer: 15, inner: 17
        )
        try assertRecommendation(
            pageSize: .b6, pageCount: 49,
            fontSize: 9.5, characters: 44, lines: 16,
            top: 19, bottom: 21, outer: 14, inner: 19
        )
        try assertRecommendation(
            pageSize: .b6, pageCount: 97,
            fontSize: 9.0, characters: 45, lines: 17,
            top: 18, bottom: 20, outer: 13, inner: 23
        )
        try assertRecommendation(
            pageSize: .b6, pageCount: 161,
            fontSize: 9.0, characters: 46, lines: 17,
            top: 17, bottom: 19, outer: 12, inner: 25
        )
        try assertRecommendation(
            pageSize: .b6, pageCount: 241,
            fontSize: 8.5, characters: 47, lines: 18,
            top: 16, bottom: 18, outer: 12, inner: 27
        )
    }

    func testManualSettingsRemainUntouchedWhenRecommendationsAreOff() {
        var settings = EditorSettings.default
        settings.pageSize = .shinsho
        settings.useRecommendedTypography = false
        settings.useRecommendedMargins = false
        settings.fontSize = 12.5
        settings.charactersPerLine = 31
        settings.linesPerPage = 12
        settings.marginTop = 21
        settings.marginBottom = 22
        settings.marginOuter = 14
        settings.marginInner = 19

        let effective = RecommendedPrintSettings.effectiveSettings(
            settings: settings,
            estimatedPageCount: 241
        )

        XCTAssertEqual(effective, settings.validated)
    }

    func testRecommendedMarginsReflectBetweenOddAndEvenPages() {
        var settings = EditorSettings.default
        settings.pageSize = .shinsho
        let effective = RecommendedPrintSettings.effectiveSettings(
            settings: settings,
            estimatedPageCount: 241
        )

        let odd = LayoutCalculator.layout(for: effective, pageNumber: 1)
        let even = LayoutCalculator.layout(for: effective, pageNumber: 2)
        let outer = LayoutCalculator.millimetersToPoints(10)
        let inner = LayoutCalculator.millimetersToPoints(26)

        XCTAssertEqual(odd.bodyFrame.minX, outer, accuracy: 0.001)
        XCTAssertEqual(odd.bodyFrame.maxX, odd.pageWidth - inner, accuracy: 0.001)
        XCTAssertEqual(even.bodyFrame.minX, inner, accuracy: 0.001)
        XCTAssertEqual(even.bodyFrame.maxX, even.pageWidth - outer, accuracy: 0.001)
    }

    func testShinshoRecommendationSwitchesTo45CharactersAt241Pages() throws {
        try assertRecommendation(
            pageSize: .shinsho, pageCount: 240,
            fontSize: 9.0, characters: 42, lines: 14,
            top: 18, bottom: 18, outer: 10, inner: 24
        )
        try assertRecommendation(
            pageSize: .shinsho, pageCount: 241,
            fontSize: 8.5, characters: 45, lines: 14,
            top: 18, bottom: 17, outer: 10, inner: 26
        )
        try assertRecommendation(
            pageSize: .shinsho, pageCount: 242,
            fontSize: 8.5, characters: 45, lines: 14,
            top: 18, bottom: 17, outer: 10, inner: 26
        )
    }

    private func assertRecommendation(
        pageSize: PageSize,
        pageCount: Int,
        fontSize: CGFloat,
        characters: Int,
        lines: Int,
        top: CGFloat,
        bottom: CGFloat,
        outer: CGFloat,
        inner: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let recommendation = try XCTUnwrap(
            RecommendedPrintSettings.recommendation(
                for: pageSize,
                estimatedPageCount: pageCount
            ),
            file: file,
            line: line
        )

        XCTAssertEqual(
            recommendation.fontSizePt,
            fontSize,
            accuracy: 0.001,
            file: file,
            line: line
        )
        XCTAssertEqual(
            recommendation.charactersPerLine,
            characters,
            file: file,
            line: line
        )
        XCTAssertEqual(
            recommendation.linesPerPage,
            lines,
            file: file,
            line: line
        )
        XCTAssertEqual(
            recommendation.marginTopMm,
            top,
            accuracy: 0.001,
            file: file,
            line: line
        )
        XCTAssertEqual(
            recommendation.marginBottomMm,
            bottom,
            accuracy: 0.001,
            file: file,
            line: line
        )
        XCTAssertEqual(
            recommendation.marginOuterMm,
            outer,
            accuracy: 0.001,
            file: file,
            line: line
        )
        XCTAssertEqual(
            recommendation.marginInnerMm,
            inner,
            accuracy: 0.001,
            file: file,
            line: line
        )
    }

    private func settings(
        from recommendation: RecommendedLayoutSetting,
        pageSize: PageSize
    ) -> EditorSettings {
        var settings = EditorSettings.default
        settings.pageSize = pageSize
        settings.fontSize = recommendation.fontSizePt
        settings.charactersPerLine = recommendation.charactersPerLine
        settings.linesPerPage = recommendation.linesPerPage
        settings.marginTop = recommendation.marginTopMm
        settings.marginBottom = recommendation.marginBottomMm
        settings.marginInner = recommendation.marginInnerMm
        settings.marginOuter = recommendation.marginOuterMm
        return settings
    }
}
