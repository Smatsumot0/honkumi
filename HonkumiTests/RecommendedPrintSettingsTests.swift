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
