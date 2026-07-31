import Foundation
@testable import Honkumi
import XCTest

final class PDFX4StructureFinalizerTests: XCTestCase {
    func testFinalizationRejectsMissingIndirectReference() {
        let input = PDFTestFixtureBuilder.pdfWithCatalogReference("99 0 R")

        XCTAssertThrowsError(try PDFX4StructureFinalizer.finalizedData(from: input)) {
            XCTAssertEqual(
                $0 as? PDFX4FinalizationError,
                .missingReference(.init(number: 99, generation: 0))
            )
        }
    }

    func testFinalizationNormalizesExistingStringTrappedValue() throws {
        let input = PDFTestFixtureBuilder.malformedQuartzStylePDF(trappedValue: "(False)")
        let output = try PDFX4StructureFinalizer.finalizedData(from: input)
        let info = try PDFX4TestInspector.infoObjectBody(in: output)

        XCTAssertEqual(
            PDFX4TestInspector.occurrenceCount(of: Data("/Trapped /False".utf8), in: info),
            1
        )
        XCTAssertFalse(info.contains(Data("/Trapped (False)".utf8)))
    }

    func testFileFinalizationLeavesOriginalBytesWhenValidationFails() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        let malformed = Data("%PDF-1.3\\nnot a pdf".utf8)
        try malformed.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try PDFX4StructureFinalizer.finalize(at: url))
        XCTAssertEqual(try Data(contentsOf: url), malformed)
    }

    func testStructureRejectsMalformedFixtureVariants() {
        let cases: [(Data, PDFX4FinalizationError)] = [
            (PDFTestFixtureBuilder.incorrectPositiveOffsetPDF(), .objectHeaderMismatch(1)),
            (PDFTestFixtureBuilder.duplicateXRefObjectNumberPDF(), .duplicateObjectNumber(1)),
            (PDFTestFixtureBuilder.incrementalUpdatePDF(), .unsupportedIncrementalUpdate),
            (PDFTestFixtureBuilder.encryptedPDF(), .encryptedPDF)
        ]

        for (input, expectedError) in cases {
            XCTAssertThrowsError(
                try PDFX4StructureFinalizer.structure(in: input, allowRepairableZeroOffsets: true)
            ) { error in
                XCTAssertEqual(error as? PDFX4FinalizationError, expectedError)
            }
        }
    }

    func testFinalizationPreservesEscapedNonForbiddenTrailerName() throws {
        let output = try PDFX4StructureFinalizer.finalizedData(
            from: PDFTestFixtureBuilder.malformedQuartzStylePDF(
                additionalTrailerEntries: " /Custom#2FKey /Value"
            )
        )
        let structure = try PDFX4StructureFinalizer.structure(in: output)

        XCTAssertTrue(output[structure.xrefOffset...].contains(Data("/Custom#2FKey /Value".utf8)))
        XCTAssertFalse(output[structure.xrefOffset...].contains(Data("/Custom/Key /Value".utf8)))
    }

    func testFinalizationRejectsEscapedForbiddenTrailerNames() {
        let cases: [(String, PDFX4FinalizationError)] = [
            ("Pr#65v", .unsupportedIncrementalUpdate),
            ("XRef#53tm", .unsupportedIncrementalUpdate),
            ("Encr#79pt", .encryptedPDF)
        ]

        for (name, expectedError) in cases {
            XCTAssertThrowsError(
                try PDFX4StructureFinalizer.finalizedData(
                    from: PDFTestFixtureBuilder.malformedQuartzStylePDF(
                        additionalTrailerEntries: " /\(name) 0"
                    )
                )
            ) { error in
                XCTAssertEqual(error as? PDFX4FinalizationError, expectedError)
            }
        }
    }

    func testStructureRejectsOverflowingXRefSubsection() {
        let input = PDFTestFixtureBuilder.replacingFirst(
            PDFTestFixtureBuilder.malformedQuartzStylePDF(),
            "xref\n0 5\n",
            with: "xref\n\(Int.max) 1\n"
        )

        XCTAssertThrowsError(try PDFX4StructureFinalizer.structure(in: input)) { error in
            XCTAssertEqual(error as? PDFX4FinalizationError, .malformedXRef)
        }
    }

    func testStructureRejectsInvalidXRefEntryRanges() {
        let inUseObjectZero = PDFTestFixtureBuilder.replacingFirst(
            PDFTestFixtureBuilder.malformedQuartzStylePDF(),
            "0000000000 65535 f ",
            with: "0000000000 00000 n "
        )
        let excessiveGeneration = PDFTestFixtureBuilder.replacingFirst(
            PDFTestFixtureBuilder.malformedQuartzStylePDF(),
            "00000 n \n",
            with: "65536 n \n"
        )
        let outOfRangeFreePointer = PDFTestFixtureBuilder.replacingFirst(
            PDFTestFixtureBuilder.malformedQuartzStylePDF(),
            "0000000000 65535 f ",
            with: "0000000005 65535 f "
        )

        for input in [inUseObjectZero, excessiveGeneration, outOfRangeFreePointer] {
            XCTAssertThrowsError(
                try PDFX4StructureFinalizer.structure(
                    in: input,
                    allowRepairableZeroOffsets: true
                )
            ) { error in
                XCTAssertEqual(error as? PDFX4FinalizationError, .malformedXRef)
            }
        }
    }

    func testFinalizationRejectsDuplicateTopLevelTrappedEntries() {
        XCTAssertThrowsError(
            try PDFX4StructureFinalizer.finalizedData(
                from: PDFTestFixtureBuilder.malformedQuartzStylePDF(
                    trappedValue: "/True /Trapped /Unknown"
                )
            )
        ) { error in
            XCTAssertEqual(error as? PDFX4FinalizationError, .invalidInfoDictionary)
        }
    }

    func testStructureParsesCommentSeparatedTrailerSize() throws {
        let input = PDFTestFixtureBuilder.replacingFirst(
            PDFTestFixtureBuilder.malformedQuartzStylePDF(),
            " /Size 5",
            with: " /Size % size comment\n 5"
        )

        let structure = try PDFX4StructureFinalizer.structure(
            in: input,
            allowRepairableZeroOffsets: true
        )

        XCTAssertEqual(structure.declaredSize, 5)
    }

    func testStructureRejectsOffsetZeroInUseEntryWithoutRepairPermission() {
        XCTAssertThrowsError(
            try PDFX4StructureFinalizer.structure(
                in: PDFTestFixtureBuilder.malformedQuartzStylePDF()
            )
        ) { error in
            XCTAssertEqual(error as? PDFX4FinalizationError, .invalidObjectOffset(0))
        }
    }

    func testFinalizationTurnsOffsetZeroInUseEntryIntoFreeEntry() throws {
        let output = try PDFX4StructureFinalizer.finalizedData(
            from: PDFTestFixtureBuilder.malformedQuartzStylePDF()
        )
        let structure = try PDFX4StructureFinalizer.structure(in: output)

        XCTAssertEqual(structure.entries[4]?.kind, .free(nextFreeObject: 0, generation: 1))
        XCTAssertEqual(structure.entries[0]?.kind, .free(nextFreeObject: 4, generation: 65_535))
        XCTAssertEqual(output[structure.xrefOffset...].prefix(4), Data("xref".utf8))
        XCTAssertEqual(structure.declaredSize, 5)
    }

    func testFinalizationAddsTrappedAsFalseName() throws {
        let output = try PDFX4StructureFinalizer.finalizedData(
            from: PDFTestFixtureBuilder.malformedQuartzStylePDF()
        )
        let structure = try PDFX4StructureFinalizer.structure(in: output)
        let info = try XCTUnwrap(structure.objectBodies[structure.infoReference])

        XCTAssertTrue(info.contains(Data("/Trapped /False".utf8)))
        XCTAssertFalse(info.contains(Data("/Trapped (False)".utf8)))
    }
}
