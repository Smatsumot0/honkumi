import Foundation
@testable import Honkumi
import XCTest

final class PDFExportCancellationTests: XCTestCase {
    func testCancellingPublicExportCancelsRendererAndRemovesOutput() async throws {
        let document = ManuscriptDocument(
            title: "Cancellation",
            body: String(repeating: "本文です。", count: 200)
        )
        let expectedURL = BodyPDFExportService.temporaryExportURL(for: document)
        try? FileManager.default.removeItem(at: expectedURL)

        let exportTask = Task {
            try await PDFExportService().export(document: document)
        }
        exportTask.cancel()

        do {
            let unexpectedURL = try await exportTask.value
            try? FileManager.default.removeItem(at: unexpectedURL)
            XCTFail("Cancelled export unexpectedly completed")
        } catch is CancellationError {
            XCTAssertFalse(FileManager.default.fileExists(atPath: expectedURL.path))
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }
}
