import CoreGraphics
import PDFKit
@testable import Honkumi
import XCTest

final class PrintSettingSamplePDFTests: XCTestCase {
    func testRepresentativeSamplesUseExpectedPaperDimensions() throws {
        let recommended = PageSize.selectableCases.compactMap { pageSize in
            PrintSettingSampleManifest.recommendedSettingCases().first {
                $0.document.settings.pageSize == pageSize
                    && $0.pageBand == .pages1Through48
            }?.output
        }
        let fontSamples = PrintSettingSampleManifest.fontSizeCases().filter {
            [CGFloat(7), CGFloat(20)].contains($0.document.settings.fontSize)
        }

        for sample in recommended + fontSamples {
            let url = try BodyPDFExportService().export(
                document: sample.document,
                subscriptionStatus: .free
            )
            defer { try? FileManager.default.removeItem(at: url) }

            let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL), sample.fileName)
            let page = try XCTUnwrap(pdf.page(at: 1), sample.fileName)
            let mediaBox = page.getBoxRect(.mediaBox)
            XCTAssertEqual(
                mediaBox.width,
                LayoutCalculator.millimetersToPoints(
                    CGFloat(sample.document.settings.pageSize.widthMillimeters)
                ),
                accuracy: 0.5,
                sample.fileName
            )
            XCTAssertEqual(
                mediaBox.height,
                LayoutCalculator.millimetersToPoints(
                    CGFloat(sample.document.settings.pageSize.heightMillimeters)
                ),
                accuracy: 0.5,
                sample.fileName
            )
        }
    }

    func testFontSamplePDFContainsNormalizedTextWithoutCross() throws {
        let sample = try XCTUnwrap(
            PrintSettingSampleManifest.fontSizeCases().first {
                $0.document.settings.fontSize == 7
            }
        )
        let url = try BodyPDFExportService().export(
            document: sample.document,
            subscriptionStatus: .free
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let pdf = try XCTUnwrap(PDFDocument(url: url))
        let text = (0..<pdf.pageCount)
            .compactMap { pdf.page(at: $0)?.string }
            .joined()

        XCTAssertTrue(text.contains("文字サイズ・章タイトル確認"))
        XCTAssertTrue(text.contains("PDF 123"))
        XCTAssertTrue(text.contains("。"))
        XCTAssertTrue(text.contains("□"))
        XCTAssertFalse(text.contains("😀"))
        XCTAssertFalse(text.contains("×"))
    }
}
