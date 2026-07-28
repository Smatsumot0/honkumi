import PDFKit
@testable import Honkumi
import XCTest

final class ChapterHeaderPDFRenderingTests: XCTestCase {
    func testNormalAndSpreadPreviewRenderFullTitleOnEveryEligiblePage() async throws {
        let document = makeFittingTitleDocument()
        let pagination = ManuscriptRenderPipeline.paginationResult(
            for: document,
            subscriptionStatus: .free
        )
        let plan = ChapterHeaderLayoutPlanner.makePlan(
            pages: pagination.pages,
            settings: pagination.document.settings,
            subscriptionStatus: .free
        )
        let fragments = pagination.pages.enumerated().compactMap { index, page in
            plan.fragmentsByPageID[page.id].map { (index, $0) }
        }

        XCTAssertGreaterThanOrEqual(fragments.count, 2)
        XCTAssertTrue(plan.issues.isEmpty)
        XCTAssertTrue(fragments.allSatisfy { $0.1.text == "短い章タイトル" })

        let exporter = PDFExportService()
        let normalURL = try await exporter.export(
            document: document,
            subscriptionStatus: .free
        )
        let spreadURL = try await exporter.exportPreviewPDF(
            document: document,
            subscriptionStatus: .free,
            previewKind: .spread,
            generationID: UUID()
        )
        defer {
            try? FileManager.default.removeItem(at: normalURL)
            try? FileManager.default.removeItem(at: spreadURL)
        }

        let normalPDF = try XCTUnwrap(PDFDocument(url: normalURL))
        for (pageIndex, fragment) in fragments {
            let pageText = try XCTUnwrap(normalPDF.page(at: pageIndex)?.string)
            XCTAssertTrue(pageText.contains(fragment.text))
        }

        let spreadPDF = try XCTUnwrap(PDFDocument(url: spreadURL))
        let spreadText = (0..<spreadPDF.pageCount)
            .compactMap { spreadPDF.page(at: $0)?.string }
            .joined()
        XCTAssertTrue(spreadText.contains("短い章タイトル"))
    }

    private func makeFittingTitleDocument() -> ManuscriptDocument {
        var settings = EditorSettings.default
        settings.showChapterTitle = true
        settings.showTableOfContents = false
        settings.colophon.isEnabled = false
        settings.useRecommendedTypography = false
        settings.useRecommendedMargins = false
        settings.charactersPerLine = 25
        settings.linesPerPage = 10
        settings.pageNumberStart = 1

        return ManuscriptDocument(
            title: "Chapter Header Rendering",
            body: "\(ManuscriptMarkupParser.chapterTag(for: "短い章タイトル"))\n"
                + String(repeating: "本", count: 700),
            settings: settings
        )
    }
}
