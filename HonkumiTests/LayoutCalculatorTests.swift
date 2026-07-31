import CoreGraphics
@testable import Honkumi
import XCTest

final class LayoutCalculatorTests: XCTestCase {
    func testManualFontSizesAboveNaturalAdvanceRemainUnchanged() {
        for requestedFontSize in [CGFloat(12.5), CGFloat(20)] {
            var settings = EditorSettings.default
            settings.pageSize = .a6
            settings.fontSize = requestedFontSize
            settings.useRecommendedTypography = false
            settings.useRecommendedMargins = false

            let layout = LayoutCalculator.layout(for: settings, pageNumber: 1)

            XCTAssertEqual(
                layout.fontSize,
                requestedFontSize,
                accuracy: 0.001,
                "\(requestedFontSize)pt should remain unchanged"
            )
        }
    }
}
