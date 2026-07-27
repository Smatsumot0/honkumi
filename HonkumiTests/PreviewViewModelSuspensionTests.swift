import Foundation
@testable import Honkumi
import XCTest

@MainActor
final class PreviewViewModelSuspensionTests: XCTestCase {
    func testInjectedExporterBuildsPreview() async throws {
        let store = makeStore()
        let exporter = FakePreviewPDFExporter()
        let viewModel = PreviewViewModel(documentStore: store, pdfExporter: exporter)

        viewModel.setPreviewActive(true, kind: .normal)
        try await waitUntil { exporter.documents.count == 1 && !viewModel.isGeneratingPDF }

        XCTAssertEqual(exporter.documents.count, 1)
        XCTAssertNotNil(viewModel.previewPDFURL)
    }

    func testSuspensionCancelsInFlightGenerationWithoutShowingAnError() async throws {
        let store = makeStore()
        let exporter = FakePreviewPDFExporter(holdsRequests: true)
        let viewModel = PreviewViewModel(documentStore: store, pdfExporter: exporter)

        viewModel.setPreviewActive(true, kind: .normal)
        try await waitUntil { exporter.documents.count == 1 }

        viewModel.setGenerationSuspended(true)

        try await waitUntil { exporter.cancellationCount == 1 }
        XCTAssertFalse(viewModel.isGeneratingPDF)
        XCTAssertNil(viewModel.generationErrorMessage)
    }

    func testMultipleDocumentChangesWhileSuspendedDoNotGenerate() async throws {
        let store = makeStore()
        let exporter = FakePreviewPDFExporter(holdsRequests: true)
        let viewModel = PreviewViewModel(documentStore: store, pdfExporter: exporter)
        viewModel.setPreviewActive(true, kind: .normal)
        try await waitUntil { exporter.documents.count == 1 }

        viewModel.setGenerationSuspended(true)
        var firstSettings = store.document.settings
        firstSettings.fontSize = 12
        store.updateSettings(firstSettings)
        var secondSettings = firstSettings
        secondSettings.fontSize = 13
        store.updateSettings(secondSettings)
        await Task.yield()

        XCTAssertEqual(exporter.documents.count, 1)
    }

    func testResumeGeneratesLatestSnapshotExactlyOnce() async throws {
        let store = makeStore()
        let exporter = FakePreviewPDFExporter()
        let viewModel = PreviewViewModel(documentStore: store, pdfExporter: exporter)
        viewModel.setPreviewActive(true, kind: .normal)
        try await waitUntil { exporter.documents.count == 1 && !viewModel.isGeneratingPDF }

        viewModel.setGenerationSuspended(true)
        var firstSettings = store.document.settings
        firstSettings.fontSize = 12
        store.updateSettings(firstSettings)
        var secondSettings = firstSettings
        secondSettings.fontSize = 13
        store.updateSettings(secondSettings)

        viewModel.setGenerationSuspended(false)

        try await waitUntil { exporter.documents.count == 2 && !viewModel.isGeneratingPDF }
        await Task.yield()
        XCTAssertEqual(exporter.documents.count, 2)
        XCTAssertEqual(exporter.documents.last?.settings, secondSettings.validated)
    }

    func testResumeWhilePreviewInactiveDoesNotGenerate() async {
        let store = makeStore()
        let exporter = FakePreviewPDFExporter()
        let viewModel = PreviewViewModel(documentStore: store, pdfExporter: exporter)

        viewModel.setGenerationSuspended(true)
        var settings = store.document.settings
        settings.fontSize = 13
        store.updateSettings(settings)
        viewModel.setGenerationSuspended(false)
        await Task.yield()

        XCTAssertTrue(exporter.documents.isEmpty)
    }

    private func makeStore() -> DocumentStore {
        let document = ManuscriptDocument(title: "Preview", body: "本文")
        return DocumentStore(
            appData: AppData(
                version: AppData.currentVersion,
                categories: [.uncategorized],
                works: [document],
                userDefaultSettings: .default,
                activeWorkId: document.id,
                subscriptionStatus: .free
            )
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
private final class FakePreviewPDFExporter: PreviewPDFExporting {
    private(set) var documents: [ManuscriptDocument] = []
    private(set) var cancellationCount = 0
    private let holdsRequests: Bool

    init(holdsRequests: Bool = false) {
        self.holdsRequests = holdsRequests
    }

    func exportPreviewPDF(
        document: ManuscriptDocument,
        subscriptionStatus: SubscriptionStatus,
        previewKind: PreviewPDFKind,
        generationID: UUID
    ) async throws -> URL {
        documents.append(document)

        if holdsRequests {
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                cancellationCount += 1
                throw error
            }
        }

        try Task.checkCancellation()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(generationID.uuidString).pdf")
        try Data("%PDF-1.4\n".utf8).write(to: url)
        return url
    }
}
