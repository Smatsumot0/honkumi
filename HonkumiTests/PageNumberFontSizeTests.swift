import CoreGraphics
@testable import Honkumi
import XCTest

final class PageNumberFontSizeTests: XCTestCase {
    func testFooterSizeDoesNotVaryByBodyOrDedicatedFont() {
        let requestedSize: CGFloat = 11.5

        for bodyFont in AppFontCatalog.all {
            XCTAssertEqual(
                AppFontCatalog.pdfPageNumberUIFont(
                    pageNumberFontId: nil,
                    bodyFontId: bodyFont.id,
                    size: requestedSize,
                    isPageNumberFontUnlocked: false
                ).pointSize,
                requestedSize,
                accuracy: 0.001
            )
        }

        for pageNumberFont in AppFontCatalog.pageNumberFonts {
            XCTAssertEqual(
                AppFontCatalog.pdfPageNumberUIFont(
                    pageNumberFontId: pageNumberFont.id,
                    bodyFontId: AppFontCatalog.defaultFontId,
                    size: requestedSize,
                    isPageNumberFontUnlocked: true
                ).pointSize,
                requestedSize,
                accuracy: 0.001
            )
        }
    }

    func testTableOfContentsSizeDoesNotVaryByBodyOrDedicatedFont() {
        let requestedSize: CGFloat = 10.5

        for bodyFont in AppFontCatalog.all {
            XCTAssertEqual(
                AppFontCatalog.pdfTableOfContentsPageNumberUIFont(
                    pageNumberFontId: nil,
                    bodyFontId: bodyFont.id,
                    size: requestedSize,
                    isPageNumberFontUnlocked: false
                ).pointSize,
                requestedSize,
                accuracy: 0.001
            )
        }

        for pageNumberFont in AppFontCatalog.pageNumberFonts {
            XCTAssertEqual(
                AppFontCatalog.pdfTableOfContentsPageNumberUIFont(
                    pageNumberFontId: pageNumberFont.id,
                    bodyFontId: AppFontCatalog.defaultFontId,
                    size: requestedSize,
                    isPageNumberFontUnlocked: true
                ).pointSize,
                requestedSize,
                accuracy: 0.001
            )
        }
    }

    func testPageLayoutResolvesPaidAndFreeTableOfContentsSizes() {
        var settings = EditorSettings.default
        settings.tableOfContentsPageNumberSize = 12.5
        let layout = LayoutCalculator.layout(for: settings, pageNumber: 1)

        XCTAssertEqual(
            layout.effectiveTableOfContentsPageNumberFontSize(
                isPageNumberFontUnlocked: true
            ),
            12.5
        )
        XCTAssertEqual(
            layout.effectiveTableOfContentsPageNumberFontSize(
                isPageNumberFontUnlocked: false
            ),
            EditorSettings.default.tableOfContentsPageNumberSize
        )
    }
}
