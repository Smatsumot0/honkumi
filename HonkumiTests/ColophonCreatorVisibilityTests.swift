import PDFKit
@testable import Honkumi
import XCTest

final class ColophonCreatorVisibilityTests: XCTestCase {
    func testWideCircleLogoUsesHalfBodyWidthAndKeepsAspectRatio() throws {
        let bodyFrame = CGRect(x: 20, y: 40, width: 200, height: 300)

        let placement = try XCTUnwrap(
            CircleLogoRenderPlacement.make(
                imageSize: CGSize(width: 400, height: 100),
                bodyFrame: bodyFrame,
                lineHeight: 20,
                y: 60
            )
        )

        XCTAssertEqual(placement.rect.width, 100, accuracy: 0.001)
        XCTAssertEqual(placement.rect.height, 25, accuracy: 0.001)
        XCTAssertEqual(placement.rect.minX, 70, accuracy: 0.001)
        XCTAssertEqual(placement.rect.minY, 60, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(placement.rect.minX, bodyFrame.minX)
        XCTAssertLessThanOrEqual(placement.rect.maxX, bodyFrame.maxX)
    }

    func testTallCircleLogoUsesFourLineHeightAndKeepsAspectRatio() throws {
        let placement = try XCTUnwrap(
            CircleLogoRenderPlacement.make(
                imageSize: CGSize(width: 100, height: 400),
                bodyFrame: CGRect(x: 20, y: 40, width: 200, height: 300),
                lineHeight: 20,
                y: 60
            )
        )

        XCTAssertEqual(placement.rect.width, 20, accuracy: 0.001)
        XCTAssertEqual(placement.rect.height, 80, accuracy: 0.001)
        XCTAssertEqual(placement.rect.minX, 110, accuracy: 0.001)
    }

    func testSquareCircleLogoUsesLargestSizeWithinBothLimits() throws {
        let placement = try XCTUnwrap(
            CircleLogoRenderPlacement.make(
                imageSize: CGSize(width: 100, height: 100),
                bodyFrame: CGRect(x: 20, y: 40, width: 200, height: 300),
                lineHeight: 20,
                y: 60
            )
        )

        XCTAssertEqual(placement.rect.width, 80, accuracy: 0.001)
        XCTAssertEqual(placement.rect.height, 80, accuracy: 0.001)
        XCTAssertEqual(placement.rect.minX, 80, accuracy: 0.001)
    }

    func testCircleLogoBlockHeightUsesRenderedHeightWithOneLineMinimum() throws {
        let bodyFrame = CGRect(x: 0, y: 0, width: 200, height: 300)
        let widePlacement = try XCTUnwrap(
            CircleLogoRenderPlacement.make(
                imageSize: CGSize(width: 400, height: 20),
                bodyFrame: bodyFrame,
                lineHeight: 20,
                y: 0
            )
        )
        let tallPlacement = try XCTUnwrap(
            CircleLogoRenderPlacement.make(
                imageSize: CGSize(width: 100, height: 400),
                bodyFrame: bodyFrame,
                lineHeight: 20,
                y: 0
            )
        )

        XCTAssertEqual(
            widePlacement.blockHeight(minimumLineHeight: 20),
            20,
            accuracy: 0.001
        )
        XCTAssertEqual(
            tallPlacement.blockHeight(minimumLineHeight: 20),
            80,
            accuracy: 0.001
        )
    }

    func testCircleLogoPlacementRejectsInvalidDimensions() {
        let bodyFrame = CGRect(x: 0, y: 0, width: 200, height: 300)

        XCTAssertNil(
            CircleLogoRenderPlacement.make(
                imageSize: CGSize(width: 0, height: 100),
                bodyFrame: bodyFrame,
                lineHeight: 20,
                y: 0
            )
        )
        XCTAssertNil(
            CircleLogoRenderPlacement.make(
                imageSize: CGSize(width: 100, height: CGFloat.infinity),
                bodyFrame: bodyFrame,
                lineHeight: 20,
                y: 0
            )
        )
    }

    func testCircleLogoPlacementRejectsNonFiniteDerivedRect() {
        XCTAssertNil(
            CircleLogoRenderPlacement.make(
                imageSize: CGSize(width: 100, height: 100),
                bodyFrame: CGRect(
                    x: CGFloat.greatestFiniteMagnitude,
                    y: 0,
                    width: 200,
                    height: 300
                ),
                lineHeight: 20,
                y: 0
            )
        )
    }

    func testActiveLogoOmitsAuthorAndCircleWithoutDeletingValues() {
        var colophon = ColophonSettings.default
        colophon.authorName = "保持する作者"
        colophon.circleName = "保持するサークル"
        colophon.showsAuthorName = true
        colophon.showsCircleName = true
        colophon.usesCircleImageForCreator = true
        colophon.circleImageData = Data([0x01])

        let entries = ManuscriptPaginator.colophonEntries(
            from: colophon,
            subscriptionStatus: .paid
        )

        XCTAssertFalse(entries.contains { $0.id == "author" })
        XCTAssertFalse(entries.contains { $0.id == "circle" })
        XCTAssertEqual(colophon.authorName, "保持する作者")
        XCTAssertEqual(colophon.circleName, "保持するサークル")
        XCTAssertTrue(colophon.showsAuthorName)
        XCTAssertTrue(colophon.showsCircleName)
    }

    func testDisablingLogoRestoresAuthorAndCircleEntries() {
        var colophon = ColophonSettings.default
        colophon.authorName = "作者"
        colophon.circleName = "サークル"
        colophon.usesCircleImageForCreator = false
        colophon.circleImageData = Data([0x01])

        let entries = ManuscriptPaginator.colophonEntries(
            from: colophon,
            subscriptionStatus: .paid
        )

        XCTAssertTrue(entries.contains { $0.id == "author" })
        XCTAssertTrue(entries.contains { $0.id == "circle" })
    }

    func testFreeEntitlementFallsBackToAuthorAndCircleEntries() {
        var colophon = ColophonSettings.default
        colophon.authorName = "無料時の作者"
        colophon.circleName = "無料時のサークル"
        colophon.showsAuthorName = true
        colophon.showsCircleName = true
        colophon.usesCircleImageForCreator = true
        colophon.circleImageData = Data([0x01])

        let entries = ManuscriptPaginator.colophonEntries(
            from: colophon,
            subscriptionStatus: .free
        )

        XCTAssertFalse(entries.contains { $0.id == "creator" })
        XCTAssertTrue(entries.contains {
            $0.id == "author" && $0.value == "無料時の作者"
        })
        XCTAssertTrue(entries.contains {
            $0.id == "circle" && $0.value == "無料時のサークル"
        })
    }

    func testFreeEntitlementAllowsRecoveryButNotPaidActions() {
        var colophon = ColophonSettings.default
        colophon.usesCircleImageForCreator = true
        colophon.circleImageData = Data([0x01])

        let access = CircleLogoCreatorAccess(
            colophon: colophon,
            isPaid: false
        )

        XCTAssertFalse(access.isCreatorLogoActive)
        XCTAssertTrue(access.showsIdentityFields)
        XCTAssertTrue(access.canSetUsage(to: false))
        XCTAssertFalse(access.canSetUsage(to: true))
        XCTAssertFalse(access.canUpload)
        XCTAssertTrue(access.canDelete)
        XCTAssertTrue(access.showsImportRow)

        colophon.usesCircleImageForCreator = false
        let disabledAccess = CircleLogoCreatorAccess(
            colophon: colophon,
            isPaid: false
        )
        XCTAssertTrue(disabledAccess.showsIdentityFields)
        XCTAssertTrue(disabledAccess.canDelete)
        XCTAssertTrue(disabledAccess.showsImportRow)
    }

    func testExportedPDFDoesNotDrawAuthorOrCircleBesideActiveLogo() async throws {
        var document = ManuscriptDocument(title: "ロゴ作品", body: "本文")
        var colophon = document.settings.colophon
        colophon.isEnabled = true
        colophon.authorName = "PDFに出さない作者"
        colophon.circleName = "PDFに出さないサークル"
        colophon.showsAuthorName = true
        colophon.showsCircleName = true
        colophon.usesCircleImageForCreator = true
        colophon.circleImageData = Data(
            base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC"
                + "AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )
        document.settings.colophon = colophon

        let url = try await PDFExportService().export(
            document: document,
            subscriptionStatus: .paid
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        let text = (0..<pdf.pageCount)
            .compactMap { pdf.page(at: $0)?.string }
            .joined(separator: "\n")

        XCTAssertFalse(text.contains("PDFに出さない作者"))
        XCTAssertFalse(text.contains("PDFに出さないサークル"))
    }

    func testFreeExportedPDFFallsBackToPreservedAuthorAndCircle() async throws {
        var document = ManuscriptDocument(title: "無料フォールバック作品", body: "本文")
        var colophon = document.settings.colophon
        colophon.isEnabled = true
        colophon.authorName = "無料PDF作者"
        colophon.circleName = "無料PDFサークル"
        colophon.showsAuthorName = true
        colophon.showsCircleName = true
        colophon.usesCircleImageForCreator = true
        colophon.circleImageData = Data(
            base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC"
                + "AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )
        document.settings.colophon = colophon

        let url = try await PDFExportService().export(
            document: document,
            subscriptionStatus: .free
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        let text = (0..<pdf.pageCount)
            .compactMap { pdf.page(at: $0)?.string }
            .joined(separator: "\n")

        XCTAssertTrue(text.contains("無料PDF作者"))
        XCTAssertTrue(text.contains("無料PDFサークル"))
    }
}
