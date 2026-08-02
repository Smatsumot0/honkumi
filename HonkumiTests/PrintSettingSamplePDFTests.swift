import CoreGraphics
import PDFKit
@testable import Honkumi
import XCTest

private enum CropMarkArtifactPersistenceError: Error, Equatable {
    case unexpectedPageSize(PageSize)
}

final class PrintSettingSamplePDFTests: XCTestCase {
    func testPDFX4FinalizationPreservesAllRequiredFontSizeRendering() throws {
        let requiredSizes: Set<CGFloat> = [7, 10, 12, 12.5, 16.5]
        let samples = PrintSettingSampleManifest.fontSizeCases().filter {
            requiredSizes.contains($0.document.settings.fontSize)
        }

        XCTAssertEqual(
            Set(samples.map { $0.document.settings.fontSize }),
            requiredSizes
        )
        XCTAssertEqual(samples.count, requiredSizes.count)

        for sample in samples {
            assertRequiredLayoutInvariants(for: sample)

            for kind in [PreviewPDFKind.normal, .spread] {
                try assertFinalizationPreservesPDF(for: sample, kind: kind)
            }
        }
    }

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

    // Catches metadata finalization changing page geometry, content, text, pixels, or
    // any non-Info object in production-size PDFs whose crop marks are actually enabled.
    func testPDFX4MetadataFinalizationPreservesCropMarkedProductionSizes() throws {
        let expectedPageSizes: [PageSize] = [.a6, .shinsho, .b6]
        XCTAssertEqual(PageSize.selectableCases, expectedPageSizes)

        let representativeSamples = expectedPageSizes.compactMap { pageSize in
            PrintSettingSampleManifest.recommendedSettingCases().first {
                $0.document.settings.pageSize == pageSize
                    && $0.pageBand == .pages1Through48
            }
        }

        XCTAssertEqual(
            representativeSamples.map(\.document.settings.pageSize),
            expectedPageSizes
        )

        for sample in representativeSamples {
            var document = sample.document
            document.settings.showsCropMarks = true
            let pageSize = document.settings.pageSize
            let finalizer = CapturingPDFX4Finalizer()
            let exportedURL = try BodyPDFExportService(finalizer: finalizer).export(
                document: document,
                subscriptionStatus: .free
            )
            defer { try? FileManager.default.removeItem(at: exportedURL) }

            let sourceData = finalizer.sourceData
            let finalData = finalizer.finalData
            XCTAssertEqual(sourceData.count, 1, pageSize.displayName)
            XCTAssertEqual(finalData.count, 1, pageSize.displayName)
            let capture = (
                beforeData: try XCTUnwrap(sourceData.first, pageSize.displayName),
                afterData: try XCTUnwrap(finalData.first, pageSize.displayName)
            )
            let beforeSnapshots = try PDFPageRegressionInspector.snapshots(
                from: capture.beforeData
            )
            XCTAssertFalse(beforeSnapshots.isEmpty, pageSize.displayName)
            let firstPage = try XCTUnwrap(beforeSnapshots.first, pageSize.displayName)
            XCTAssertNotEqual(firstPage.trimBox, firstPage.mediaBox, pageSize.displayName)

            XCTAssertEqual(
                beforeSnapshots,
                try PDFPageRegressionInspector.snapshots(from: capture.afterData),
                pageSize.displayName
            )
            try PDFX4TestInspector.assertNonInfoObjectBodiesEqual(
                before: capture.beforeData,
                after: capture.afterData,
                context: pageSize.displayName
            )
            try persistCropMarkArtifactIfRequested(
                capture.afterData,
                pageSize: pageSize
            )
        }
    }

    func testCropMarkArtifactPersistenceRejectsUnexpectedSizeWithoutEnvironment() {
        XCTAssertThrowsError(
            try persistCropMarkArtifactIfRequested(
                Data(),
                pageSize: .a5,
                environment: [:]
            )
        ) { error in
            XCTAssertEqual(
                error as? CropMarkArtifactPersistenceError,
                .unexpectedPageSize(.a5)
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

    private func assertFinalizationPreservesPDF(
        for sample: PrintSettingSampleCase,
        kind: PreviewPDFKind
    ) throws {
        let exporter = BodyPDFExportService(finalizer: PassthroughPDFFinalizer())
        let rawURL: URL
        switch kind {
        case .normal:
            rawURL = try exporter.export(
                document: sample.document,
                subscriptionStatus: .free
            )
        case .spread:
            rawURL = try exporter.exportPreviewPDF(
                document: sample.document,
                subscriptionStatus: .free,
                previewKind: .spread,
                generationID: UUID()
            )
        }
        defer { try? FileManager.default.removeItem(at: rawURL) }

        let before = try Data(contentsOf: rawURL)
        let after = try PDFX4StructureFinalizer.finalizedData(from: before)
        let context = "\(sample.fileName) \(kind)"

        XCTAssertEqual(
            try PDFPageRegressionInspector.snapshots(from: before),
            try PDFPageRegressionInspector.snapshots(from: after),
            context
        )
        try PDFX4TestInspector.assertNonInfoObjectBodiesEqual(
            before: before,
            after: after,
            context: context
        )
    }

    private func persistCropMarkArtifactIfRequested(
        _ data: Data,
        pageSize: PageSize,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        let fileName: String
        switch pageSize {
        case .a6:
            fileName = "A6-cropmarks.pdf"
        case .b6:
            fileName = "B6-cropmarks.pdf"
        case .shinsho:
            fileName = "Shinsho-cropmarks.pdf"
        case .a5, .b5:
            throw CropMarkArtifactPersistenceError.unexpectedPageSize(pageSize)
        }
        guard let directory = environment["HONKUMI_PDF_X4_ARTIFACT_DIR"] else {
            return
        }
        let directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try data.write(to: directoryURL.appendingPathComponent(fileName), options: .atomic)
    }

    private func assertRequiredLayoutInvariants(for sample: PrintSettingSampleCase) {
        let sampleSettings = sample.document.settings
        let settings = sample.document.settings.validated
        let odd = LayoutCalculator.layout(for: settings, pageNumber: 1)
        let even = LayoutCalculator.layout(for: settings, pageNumber: 2)
        let accuracy: CGFloat = 0.0001

        for layout in [odd, even] {
            XCTAssertEqual(
                layout.fontSize,
                sampleSettings.fontSize,
                accuracy: accuracy,
                sample.fileName
            )
            XCTAssertEqual(
                layout.lineAdvance,
                layout.bodyFrame.width / CGFloat(settings.linesPerPage),
                accuracy: accuracy,
                sample.fileName
            )
            XCTAssertEqual(
                layout.characterAdvance,
                layout.bodyFrame.height / CGFloat(settings.charactersPerLine),
                accuracy: accuracy,
                sample.fileName
            )
            XCTAssertEqual(
                layout.settings.charactersPerLine,
                sampleSettings.charactersPerLine,
                sample.fileName
            )
            XCTAssertEqual(
                layout.settings.linesPerPage,
                sampleSettings.linesPerPage,
                sample.fileName
            )
            XCTAssertEqual(
                layout.settings.marginTop,
                sampleSettings.marginTop,
                accuracy: accuracy,
                sample.fileName
            )
            XCTAssertEqual(
                layout.settings.marginBottom,
                sampleSettings.marginBottom,
                accuracy: accuracy,
                sample.fileName
            )
            XCTAssertEqual(
                layout.settings.marginInner,
                sampleSettings.marginInner,
                accuracy: accuracy,
                sample.fileName
            )
            XCTAssertEqual(
                layout.settings.marginOuter,
                sampleSettings.marginOuter,
                accuracy: accuracy,
                sample.fileName
            )
            XCTAssertEqual(
                ChapterHeaderLayoutPlanner.font(
                    for: layout,
                    subscriptionStatus: .free
                ).pointSize,
                max(settings.fontSize * 0.8, 6),
                accuracy: accuracy,
                sample.fileName
            )
            XCTAssertEqual(
                layout.settings.pageNumberSize,
                sampleSettings.pageNumberSize,
                accuracy: accuracy,
                sample.fileName
            )
        }

        XCTAssertEqual(odd.marginTop, even.marginTop, accuracy: accuracy, sample.fileName)
        XCTAssertEqual(odd.marginBottom, even.marginBottom, accuracy: accuracy, sample.fileName)
        XCTAssertEqual(odd.marginInner, even.marginInner, accuracy: accuracy, sample.fileName)
        XCTAssertEqual(odd.marginOuter, even.marginOuter, accuracy: accuracy, sample.fileName)
        XCTAssertEqual(
            odd.bodyFrame.minX,
            LayoutCalculator.millimetersToPoints(settings.marginOuter),
            accuracy: accuracy,
            sample.fileName
        )
        XCTAssertEqual(
            even.bodyFrame.minX,
            LayoutCalculator.millimetersToPoints(settings.marginInner),
            accuracy: accuracy,
            sample.fileName
        )
        XCTAssertEqual(
            odd.marginTop,
            LayoutCalculator.millimetersToPoints(settings.marginTop),
            accuracy: accuracy,
            sample.fileName
        )
        XCTAssertEqual(
            odd.marginBottom,
            LayoutCalculator.millimetersToPoints(settings.marginBottom),
            accuracy: accuracy,
            sample.fileName
        )
        XCTAssertEqual(
            odd.marginInner,
            LayoutCalculator.millimetersToPoints(settings.marginInner),
            accuracy: accuracy,
            sample.fileName
        )
        XCTAssertEqual(
            odd.marginOuter,
            LayoutCalculator.millimetersToPoints(settings.marginOuter),
            accuracy: accuracy,
            sample.fileName
        )
    }
}
