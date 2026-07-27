import UIKit
@testable import Honkumi
import XCTest

final class PDFPreflightChapterHeaderTests: XCTestCase {
    func testSinglePageChapterHeaderAddsNoSpreadIssue() {
        let document = makeDocument(title: "短い章題", bodyCharacterCount: 700)

        let result = PDFPreflightService().check(document: document, subscriptionStatus: .free)

        XCTAssertFalse(result.issues.contains { $0.id.hasPrefix("pdf.chapterHeader.") })
    }

    func testSpreadChapterHeaderAddsContinuableWarning() throws {
        let title = makeTitle(exceedingBodyWidths: 1)
        let document = makeDocument(title: title, bodyCharacterCount: 520)
        XCTAssertEqual(
            ManuscriptRenderPipeline.paginationResult(
                for: document,
                subscriptionStatus: .free
            ).pages.count,
            3
        )

        let result = PDFPreflightService().check(document: document, subscriptionStatus: .free)

        let issue = try XCTUnwrap(result.issues.first {
            $0.id.hasPrefix("pdf.chapterHeader.spread.")
        })
        XCTAssertEqual(issue.severity, .warning)
        XCTAssertEqual(issue.title, "章タイトルが見開きにまたがります")
        XCTAssertTrue(issue.message.contains(title))
        XCTAssertTrue(issue.message.contains("ページ"))
        XCTAssertTrue(result.canContinue)
    }

    func testOverflowChapterHeaderAddsBlockingError() throws {
        let title = makeTitle(exceedingBodyWidths: 2)
        let document = makeDocument(title: title, bodyCharacterCount: 700)

        let result = PDFPreflightService().check(document: document, subscriptionStatus: .free)

        let issue = try XCTUnwrap(result.issues.first {
            $0.id.hasPrefix("pdf.chapterHeader.overflow.")
        })
        XCTAssertEqual(issue.severity, .error)
        XCTAssertEqual(issue.title, "章タイトルが見開きに収まりません")
        XCTAssertFalse(result.canContinue)
    }

    func testMissingCompanionPageAddsBlockingError() throws {
        let title = makeTitle(exceedingBodyWidths: 1)
        let document = makeDocument(title: title, bodyCharacterCount: 300)
        let pages = ManuscriptRenderPipeline.paginationResult(
            for: document,
            subscriptionStatus: .free
        ).pages
        XCTAssertEqual(pages.count, 2)

        let result = PDFPreflightService().check(document: document, subscriptionStatus: .free)

        let issue = try XCTUnwrap(result.issues.first {
            $0.id.hasPrefix("pdf.chapterHeader.overflow.")
        })
        XCTAssertEqual(issue.severity, .error)
        XCTAssertFalse(result.canContinue)
    }

    private func makeDocument(title: String, bodyCharacterCount: Int) -> ManuscriptDocument {
        ManuscriptDocument(
            title: "Chapter Header",
            body: "\(ManuscriptMarkupParser.chapterTag(for: title))\n"
                + String(repeating: "本", count: bodyCharacterCount),
            settings: chapterSettings
        )
    }

    private var chapterSettings: EditorSettings {
        var settings = EditorSettings.default
        settings.showChapterTitle = true
        settings.showTableOfContents = false
        settings.colophon.isEnabled = false
        settings.useRecommendedTypography = false
        settings.useRecommendedMargins = false
        settings.charactersPerLine = 25
        settings.linesPerPage = 10
        settings.pageNumberStart = 1
        return settings
    }

    private func makeTitle(exceedingBodyWidths widthCount: CGFloat) -> String {
        let layout = LayoutCalculator.layout(for: chapterSettings, pageNumber: 2)
        let font = ChapterHeaderLayoutPlanner.font(for: layout, subscriptionStatus: .free)
        let targetWidth = layout.bodyFrame.width * widthCount
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var title = ""
        var index = 0
        while (title as NSString).size(withAttributes: [.font: font]).width <= targetWidth {
            title.append(alphabet[index % alphabet.count])
            index += 1
        }
        return title
    }
}
