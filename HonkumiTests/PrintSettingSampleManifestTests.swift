import CoreGraphics
import Foundation
@testable import Honkumi
import XCTest

final class PrintSettingSampleManifestTests: XCTestCase {
    func testRecommendedManifestContainsThreeSizesByFiveBands() {
        let samples = PrintSettingSampleManifest.recommendedSettingCases()

        XCTAssertEqual(samples.count, 15)
        XCTAssertEqual(Set(samples.map(\.document.settings.pageSize)), Set(PageSize.selectableCases))
        XCTAssertEqual(Set(samples.map(\.requestedPageCount)), Set([1, 49, 97, 161, 241]))
        XCTAssertEqual(Set(samples.map(\.fileName)).count, 15)
    }

    func testRecommendedCasesUseBothRecommendationFlagsAndRequestedBands() {
        for sample in PrintSettingSampleManifest.recommendedSettingCases() {
            XCTAssertTrue(sample.document.settings.useRecommendedTypography)
            XCTAssertTrue(sample.document.settings.useRecommendedMargins)

            let effective = RecommendedPrintSettings.effectiveSettings(for: sample.document)
            let count = RecommendedPrintSettings.estimatedPageCount(
                body: sample.document.body,
                settings: effective
            )
            XCTAssertEqual(count, sample.requestedPageCount, sample.fileName)
            XCTAssertTrue(sample.pageBand.contains(count), sample.fileName)
            XCTAssertEqual(
                sample.fileName,
                PrintSettingSampleManifest.recommendedFileName(
                    pageSize: sample.document.settings.pageSize,
                    pageBand: sample.pageBand,
                    actualPageCount: count,
                    effectiveSettings: effective
                )
            )
        }
    }

    func testFontSizeManifestContainsEveryHalfPoint() {
        let samples = PrintSettingSampleManifest.fontSizeCases()
        let sizes = samples.map(\.document.settings.fontSize)

        XCTAssertEqual(samples.count, 27)
        XCTAssertEqual(sizes, (14...40).map { CGFloat($0) / 2 })
        XCTAssertEqual(Set(samples.map(\.fileName)).count, 27)
    }

    func testFontSizeCasesUseManualA6Settings() {
        for sample in PrintSettingSampleManifest.fontSizeCases() {
            XCTAssertEqual(sample.document.settings.pageSize, .a6)
            XCTAssertFalse(sample.document.settings.useRecommendedTypography)
            XCTAssertFalse(sample.document.settings.useRecommendedMargins)
            XCTAssertTrue(
                sample.fileName.contains(
                    String(format: "%.1fpt", Double(sample.document.settings.fontSize))
                )
            )
            XCTAssertEqual(
                RecommendedPrintSettings.effectiveSettings(for: sample.document).fontSize,
                sample.document.settings.fontSize
            )
        }
    }
}
