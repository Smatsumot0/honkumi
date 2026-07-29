@testable import Honkumi
import XCTest

@MainActor
final class SettingsFormatApplicationTests: XCTestCase {
    func testChangingFormatSettingsDoesNotModifyBodyInsideSettings() async throws {
        var document = ManuscriptDocument(title: "Formatting", body: "A,B.")
        document.settings.formatSettings.enableAutoFormat = true
        let store = makeStore(document: document, subscriptionStatus: .paid)
        let viewModel = SettingsViewModel(documentStore: store)

        viewModel.updateFormatRule(\.enableNormalizePunctuation, isEnabled: true)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(store.document.body, "A,B.")
        XCTAssertTrue(
            store.document.settings.formatSettings.enableNormalizePunctuation
        )
    }

    func testProUnlockPublishesStatusWithoutFormattingInsideSettings() async throws {
        var document = ManuscriptDocument(title: "Formatting", body: "A,B.")
        document.settings.formatSettings.enableAutoFormat = true
        document.settings.formatSettings.enableNormalizePunctuation = true
        let store = makeStore(document: document, subscriptionStatus: .free)
        let viewModel = SettingsViewModel(documentStore: store)

        store.setProUnlocked(true)

        try await waitUntil { viewModel.subscriptionStatus == .paid }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(store.document.body, "A,B.")
    }

    private func makeStore(
        document: ManuscriptDocument,
        subscriptionStatus: SubscriptionStatus
    ) -> DocumentStore {
        DocumentStore(
            appData: AppData(
                version: AppData.currentVersion,
                categories: [.uncategorized],
                works: [document],
                userDefaultSettings: .default,
                activeWorkId: document.id,
                subscriptionStatus: subscriptionStatus
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
