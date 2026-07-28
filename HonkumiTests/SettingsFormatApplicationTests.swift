@testable import Honkumi
import Combine
import XCTest

@MainActor
final class SettingsFormatApplicationTests: XCTestCase {
    func testUnlockingProPublishesStatusAndFormatsExistingBody() async throws {
        var document = ManuscriptDocument(title: "Formatting", body: "A,B.")
        document.settings.formatSettings.enableAutoFormat = true
        document.settings.formatSettings.enableNormalizePunctuation = true
        let store = makeStore(document: document, subscriptionStatus: .free)
        let viewModel = SettingsViewModel(documentStore: store)
        var publishedStatuses: [SubscriptionStatus] = []
        let cancellable = viewModel.$subscriptionStatus
            .dropFirst()
            .sink { publishedStatuses.append($0) }

        store.setProUnlocked(true)

        try await waitUntil {
            viewModel.subscriptionStatus == .paid &&
                viewModel.document.body == "A、B。"
        }
        XCTAssertEqual(publishedStatuses, [.paid])
        XCTAssertFalse(viewModel.isApplyingFormat)
        withExtendedLifetime(cancellable) {}
    }

    func testEnablingPaidPunctuationRuleFormatsExistingBodyWhileAutoFormatIsOn() async throws {
        var document = ManuscriptDocument(title: "Formatting", body: "A,B.")
        document.settings.formatSettings.enableAutoFormat = true
        document.settings.formatSettings.enableNormalizePunctuation = false
        let store = makeStore(document: document, subscriptionStatus: .paid)
        let viewModel = SettingsViewModel(documentStore: store)

        viewModel.updateFormatRule(\.enableNormalizePunctuation, isEnabled: true)

        XCTAssertTrue(viewModel.isApplyingFormat)
        try await waitUntil {
            viewModel.document.body == "A、B。"
        }
        XCTAssertFalse(viewModel.isApplyingFormat)
    }

    func testLateResultFromSupersededFormatRequestDoesNotOverwriteLatestBody() async throws {
        var document = ManuscriptDocument(title: "Formatting", body: "original")
        document.settings.formatSettings.enableAutoFormat = true
        let store = makeStore(document: document, subscriptionStatus: .paid)
        let formatter = ControlledFormatter()
        let viewModel = SettingsViewModel(
            documentStore: store,
            formatOperation: { text, _, _ in
                await formatter.format(text)
            }
        )

        viewModel.updateFormatRule(\.enableNormalizePunctuation, isEnabled: true)
        try await waitUntil {
            await formatter.requestCount == 1
        }

        viewModel.updateFormatRule(\.enableNormalizeBrackets, isEnabled: true)
        try await waitUntil {
            await formatter.requestCount == 2
        }

        await formatter.resolveRequest(at: 1, with: "latest")
        try await waitUntil {
            viewModel.document.body == "latest"
        }

        await formatter.resolveRequest(at: 0, with: "stale")
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(viewModel.document.body, "latest")
        XCTAssertFalse(viewModel.isApplyingFormat)
    }

    func testPaidFormatResultIsRejectedAfterProRelocks() async throws {
        var document = ManuscriptDocument(title: "Formatting", body: "A,B.")
        document.settings.formatSettings.enableAutoFormat = true
        document.settings.formatSettings.enableNormalizePunctuation = false
        let store = makeStore(document: document, subscriptionStatus: .paid)
        let formatter = ControlledFormatter()
        let viewModel = SettingsViewModel(
            documentStore: store,
            formatOperation: { text, _, _ in
                await formatter.format(text)
            }
        )

        viewModel.updateFormatRule(\.enableNormalizePunctuation, isEnabled: true)
        try await waitUntil {
            await formatter.requestCount == 1
        }

        store.setProUnlocked(false)
        await formatter.resolveRequest(at: 0, with: "stale paid result")
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(viewModel.subscriptionStatus, .free)
        XCTAssertEqual(viewModel.document.body, "A,B.")
        XCTAssertFalse(viewModel.isApplyingFormat)
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

private actor ControlledFormatter {
    private var continuations: [CheckedContinuation<String, Never>] = []

    var requestCount: Int {
        continuations.count
    }

    func format(_ text: String) async -> String {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resolveRequest(at index: Int, with result: String) {
        continuations[index].resume(returning: result)
    }
}
