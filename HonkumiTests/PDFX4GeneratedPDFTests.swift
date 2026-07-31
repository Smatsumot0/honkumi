import CoreGraphics
import Foundation
@testable import Honkumi
import XCTest

final class PDFX4GeneratedPDFTests: XCTestCase {
    private let requiredSizes: Set<CGFloat> = [7, 10, 12, 12.5, 16.5]

    func testRequiredFontSizesProduceValidStructuresForNormalAndSpreadPDFs() throws {
        let samples = PrintSettingSampleManifest.fontSizeCases().filter {
            requiredSizes.contains($0.document.settings.fontSize)
        }
        XCTAssertEqual(samples.count, requiredSizes.count)
        XCTAssertEqual(Set(samples.map(\.document.settings.fontSize)), requiredSizes)

        for sample in samples {
            let normalURL = try BodyPDFExportService().export(
                document: sample.document,
                subscriptionStatus: .free
            )
            defer { try? FileManager.default.removeItem(at: normalURL) }
            try assertRequiredStructure(at: normalURL, label: "\(sample.fileName) normal")
            try persistArtifactIfRequested(
                sourceURL: normalURL,
                fontSize: sample.document.settings.fontSize,
                kind: "normal"
            )

            let spreadURL = try BodyPDFExportService().exportPreviewPDF(
                document: sample.document,
                subscriptionStatus: .free,
                previewKind: .spread,
                generationID: UUID()
            )
            defer { try? FileManager.default.removeItem(at: spreadURL) }
            try assertRequiredStructure(at: spreadURL, label: "\(sample.fileName) spread")
            try persistArtifactIfRequested(
                sourceURL: spreadURL,
                fontSize: sample.document.settings.fontSize,
                kind: "spread"
            )
        }
    }

    private func assertRequiredStructure(at url: URL, label: String) throws {
        let data = try Data(contentsOf: url)
        let structure = try PDFX4StructureFinalizer.structure(in: data)
        try PDFX4StructureFinalizer.validateReferences(in: structure)

        XCTAssertTrue(
            data.starts(with: Data("%PDF-\(PDFPrintProduction.targetPDFVersion)".utf8)),
            label
        )
        XCTAssertEqual(
            structure.declaredSize,
            (structure.entries.keys.max() ?? -1) + 1,
            label
        )
        XCTAssertNotNil(structure.objectBodies[structure.rootReference], label)
        XCTAssertEqual(data[structure.xrefOffset...].prefix(4), Data("xref".utf8), label)

        for entry in structure.entries.values {
            guard case let .inUse(offset) = entry.kind else { continue }
            XCTAssertGreaterThan(offset, 0, label)
            let header = Data(
                "\(entry.reference.number) \(entry.reference.generation) obj".utf8
            )
            XCTAssertEqual(data[offset...].prefix(header.count), header, label)
        }

        let semantic = try PDFX4TestInspector.inspect(data)
        XCTAssertEqual(semantic.version, "1.6", label)
        XCTAssertTrue(
            semantic.catalogVersion == nil || semantic.catalogVersion == "1.6",
            label
        )
        XCTAssertEqual(semantic.trappedName, "False", label)
        XCTAssertEqual(semantic.outputIntentSubtype, "GTS_PDFX", label)
        XCTAssertFalse(semantic.outputConditionIdentifier.isEmpty, label)
        XCTAssertEqual(semantic.iccComponentCount, 4, label)
        XCTAssertFalse(semantic.iccData.isEmpty, label)
        XCTAssertEqual(semantic.iccData.subdata(in: 36..<40), Data("acsp".utf8), label)
        XCTAssertTrue(semantic.iccLoadsAsFourComponentColorSpace, label)
        XCTAssertEqual(semantic.pdfXVersionCount, 1, label)
        XCTAssertEqual(semantic.pdfXConformanceCount, 1, label)
        XCTAssertEqual(semantic.infoTitle, semantic.xmpTitle, label)
        XCTAssertEqual(semantic.infoCreator, semantic.xmpCreatorTool, label)
        XCTAssertFalse(semantic.isEncrypted, label)
        XCTAssertFalse(semantic.hasAcroForm, label)
        XCTAssertFalse(semantic.hasJavaScript, label)
        XCTAssertFalse(semantic.hasEmbeddedFiles, label)
        XCTAssertFalse(semantic.hasExternalReferences, label)
        XCTAssertTrue(semantic.unresolvedColorSpaceNames.isEmpty, label)
        XCTAssertTrue(semantic.embeddedBaseFontNames.contains("BIZUDMincho-Regular"), label)
        XCTAssertTrue(semantic.embeddedBaseFontNames.contains("HiraginoSans-W3"), label)
    }

    private func persistArtifactIfRequested(
        sourceURL: URL,
        fontSize: CGFloat,
        kind: String
    ) throws {
        guard let directory = ProcessInfo.processInfo.environment[
            "HONKUMI_PDF_X4_ARTIFACT_DIR"
        ] else {
            return
        }
        let directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let name = String(format: "font-%04.1f-%@.pdf", Double(fontSize), kind)
        let destination = directoryURL.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
    }
}
