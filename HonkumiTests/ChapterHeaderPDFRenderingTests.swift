import PDFKit
@testable import Honkumi
import XCTest

final class ChapterHeaderPDFRenderingTests: XCTestCase {
    func testNormalAndSpreadPreviewRenderSameFragmentsOnOnePhysicalSpread() async throws {
        let document = makeSpreadDocument()
        let pagination = ManuscriptRenderPipeline.paginationResult(
            for: document,
            subscriptionStatus: .free
        )
        let plan = ChapterHeaderLayoutPlanner.makePlan(
            pages: pagination.pages,
            settings: pagination.document.settings,
            subscriptionStatus: .free
        )
        let issue = try XCTUnwrap(plan.issues.first)
        let title = issue.title
        let fragments = pagination.pages.enumerated().compactMap { index, page in
            plan.fragmentsByPageID[page.id].map { (index, $0) }
        }
        XCTAssertEqual(fragments.count, 2)
        let recombinedTitle =
            (fragments.first { $0.1.alignment == .trailing }?.1.text ?? "")
            + (fragments.first { $0.1.alignment == .leading }?.1.text ?? "")
        XCTAssertEqual(recombinedTitle, title)

        let exporter = PDFExportService()
        let normalURL = try await exporter.export(document: document, subscriptionStatus: .free)
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
            XCTAssertFalse(pageText.contains(title))
        }

        let spreadPDF = try XCTUnwrap(PDFDocument(url: spreadURL))
        let spreadText = (0..<spreadPDF.pageCount)
            .compactMap { spreadPDF.page(at: $0)?.string }
            .joined()
        for (_, fragment) in fragments {
            XCTAssertTrue(spreadText.contains(fragment.text))
        }
    }

    private func makeSpreadDocument() -> ManuscriptDocument {
        var settings = EditorSettings.default
        settings.showChapterTitle = true
        settings.showTableOfContents = false
        settings.colophon.isEnabled = false
        settings.useRecommendedTypography = false
        settings.useRecommendedMargins = false
        settings.charactersPerLine = 25
        settings.linesPerPage = 10
        settings.pageNumberStart = 1

        let layout = LayoutCalculator.layout(for: settings, pageNumber: 2)
        let font = ChapterHeaderLayoutPlanner.font(for: layout, subscriptionStatus: .free)
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var title = ""
        var index = 0
        while (title as NSString).size(withAttributes: [.font: font]).width <= layout.bodyFrame.width {
            title.append(alphabet[index % alphabet.count])
            index += 1
        }

        return ManuscriptDocument(
            title: "Chapter Header Rendering",
            body: "\(ManuscriptMarkupParser.chapterTag(for: title))\n"
                + String(repeating: "本", count: 700),
            settings: settings
        )
    }
}
