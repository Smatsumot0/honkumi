import PDFKit
@testable import Honkumi
import XCTest

final class ColophonCreatorVisibilityTests: XCTestCase {
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
