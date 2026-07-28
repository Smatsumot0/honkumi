import UIKit
@testable import Honkumi
import XCTest

final class PDFPreflightChapterHeaderTests: XCTestCase {
    func testSinglePageChapterHeaderAddsNoOverflowIssue() {
        let document = makeDocument(title: "短い章題", bodyCharacterCount: 700)

        let result = PDFPreflightService().check(
            document: document,
            subscriptionStatus: .free
        )

        XCTAssertFalse(result.issues.contains { $0.id.hasPrefix("pdf.chapterHeader.") })
    }

    func testTitleExceedingPageWidthAddsBlockingError() throws {
        let title = makeTitle(exceedingBodyWidths: 1)
        let document = makeDocument(title: title, bodyCharacterCount: 700)

        let result = PDFPreflightService().check(
            document: document,
            subscriptionStatus: .free
        )

        let issue = try XCTUnwrap(result.issues.first {
            $0.id.hasPrefix("pdf.chapterHeader.overflow.chapter.")
        })
        XCTAssertEqual(issue.severity, .error)
        XCTAssertEqual(issue.title, "章タイトルがページ内に収まりません")
        XCTAssertTrue(issue.message.contains(title))
        XCTAssertTrue(issue.message.contains("ページ"))
        XCTAssertFalse(issue.message.contains("見開き"))
        XCTAssertFalse(result.canContinue)
    }

    func testOneLongChapterAcrossManyPagesProducesOneBlockingHeaderError() {
        let title = makeTitle(exceedingBodyWidths: 1)
        let document = makeDocument(title: title, bodyCharacterCount: 2_000)

        let result = PDFPreflightService().check(
            document: document,
            subscriptionStatus: .free
        )
        let chapterIssues = result.issues.filter {
            $0.id.hasPrefix("pdf.chapterHeader.")
        }

        XCTAssertEqual(chapterIssues.count, 1)
        XCTAssertEqual(chapterIssues.first?.severity, .error)
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
