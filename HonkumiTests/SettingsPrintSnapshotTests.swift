@testable import Honkumi
import XCTest

@MainActor
final class SettingsPrintSnapshotTests: XCTestCase {
    func testSettingsAreImmediateAndLateSnapshotIsDiscarded() async throws {
        var document = ManuscriptDocument(title: "Print", body: "本文")
        document.settings.pageSize = .a6
        let store = makeStore(document: document)
        let harness = PrintSnapshotHarness()
        let viewModel = SettingsViewModel(
            documentStore: store,
            printSnapshotOperation: { body, settings in
                await harness.calculate(body: body, settings: settings)
            }
        )
        try await waitUntil {
            await harness.requestCount == 1
        }

        viewModel.updatePageSize(.b6)

        XCTAssertEqual(viewModel.settings.pageSize, .b6)
        XCTAssertEqual(viewModel.printSettingsForDisplay.pageSize, .b6)
        XCTAssertTrue(viewModel.isCalculatingPrintSettings)
        try await waitUntil {
            await harness.requestCount == 2
        }

        var latestSettings = viewModel.settings
        latestSettings.pageSize = .b6
        await harness.complete(
            request: 1,
            result: PrintSettingsDisplaySnapshot(
                settings: latestSettings,
                estimatedPageCount: 99,
                showsWideGutterNote: true
            )
        )
        try await waitUntil {
            viewModel.estimatedPrintPageCount == 99
        }

        await harness.complete(
            request: 0,
            result: PrintSettingsDisplaySnapshot(
                settings: .default,
                estimatedPageCount: 1,
                showsWideGutterNote: false
            )
        )
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(viewModel.estimatedPrintPageCount, 99)
        XCTAssertEqual(viewModel.printSettingsForDisplay.pageSize, .b6)
        XCTAssertTrue(viewModel.showsWideGutterRecommendationNote)
        XCTAssertFalse(viewModel.isCalculatingPrintSettings)
    }

    private func makeStore(document: ManuscriptDocument) -> DocumentStore {
        DocumentStore(
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
        condition: @escaping () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while !(await condition()) {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for condition")
                throw WaitError.timedOut
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private enum WaitError: Error {
        case timedOut
    }
}

private actor PrintSnapshotHarness {
    private var continuations: [
        CheckedContinuation<PrintSettingsDisplaySnapshot, Never>
    ] = []

    var requestCount: Int {
        continuations.count
    }

    func calculate(
        body: String,
        settings: EditorSettings
    ) async -> PrintSettingsDisplaySnapshot {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func complete(
        request index: Int,
        result: PrintSettingsDisplaySnapshot
    ) {
        continuations[index].resume(returning: result)
    }
}
