@testable import Honkumi
import XCTest

@MainActor
final class ManuscriptFormattingCoordinatorTests: XCTestCase {
    func testRequestShowsProgressAndAppliesLatestEligibleResult() async throws {
        let store = makeStore(body: "A,B.", premium: true)
        let formatter = ControlledFormatter()
        let coordinator = ManuscriptFormattingCoordinator(
            documentStore: store,
            editDebounce: .zero,
            formatOperation: { text, _, _ in await formatter.format(text) }
        )

        coordinator.requestFormatting()
        try await waitUntil { await formatter.requestCount == 1 }
        XCTAssertTrue(coordinator.isFormatting)

        await formatter.resolveRequest(at: 0, with: "A、B。")
        try await waitUntil { store.document.body == "A、B。" }
        XCTAssertFalse(coordinator.isFormatting)
    }

    func testEditingDuringFormattingQueuesOnlyTheLatestBodyAfterTheRunningCall() async throws {
        let store = makeStore(body: "old", premium: true)
        let formatter = ControlledFormatter()
        let coordinator = ManuscriptFormattingCoordinator(
            documentStore: store,
            editDebounce: .zero,
            formatOperation: { text, _, _ in await formatter.format(text) }
        )

        coordinator.requestFormatting()
        try await waitUntil { await formatter.requestCount == 1 }
        store.updateBody("newest")
        try await Task.sleep(for: .milliseconds(20))
        let countBeforeCompletingFirst = await formatter.requestCount
        XCTAssertEqual(countBeforeCompletingFirst, 1)

        await formatter.resolveRequest(at: 0, with: "stale")
        try await waitUntil { await formatter.requestCount == 2 }
        let secondRequestText = await formatter.requestText(at: 1)
        XCTAssertEqual(secondRequestText, "newest")

        await formatter.resolveRequest(at: 1, with: "latest")
        try await waitUntil { store.document.body == "latest" }
        XCTAssertFalse(coordinator.isFormatting)
    }

    func testWorkSwitchRejectsRunningResultAndClearsProgress() async throws {
        let first = configuredDocument(title: "First", body: "first")
        let second = configuredDocument(title: "Second", body: "second")
        let store = makeStore(
            works: [first, second],
            activeID: first.id,
            premium: true
        )
        let formatter = ControlledFormatter()
        let coordinator = ManuscriptFormattingCoordinator(
            documentStore: store,
            editDebounce: .zero,
            formatOperation: { text, _, _ in await formatter.format(text) }
        )

        coordinator.requestFormatting()
        try await waitUntil { await formatter.requestCount == 1 }
        store.selectWork(id: second.id)
        XCTAssertFalse(coordinator.isFormatting)

        await formatter.resolveRequest(at: 0, with: "stale")
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(store.document.id, second.id)
        XCTAssertEqual(store.document.body, "second")
    }

    func testSettingsMismatchPreventsWriteback() async throws {
        let store = makeStore(body: "original", premium: true)
        let formatter = ControlledFormatter()
        let coordinator = ManuscriptFormattingCoordinator(
            documentStore: store,
            editDebounce: .zero,
            formatOperation: { text, _, _ in await formatter.format(text) }
        )

        coordinator.requestFormatting()
        try await waitUntil { await formatter.requestCount == 1 }
        var changedSettings = store.document.settings
        changedSettings.formatSettings.enableNormalizeBrackets.toggle()
        store.updateSettings(changedSettings)

        await formatter.resolveRequest(at: 0, with: "stale settings")
        try await waitUntil { !coordinator.isFormatting }
        XCTAssertEqual(store.document.body, "original")
    }

    func testProMismatchPreventsWriteback() async throws {
        let store = makeStore(body: "original", premium: true)
        let formatter = ControlledFormatter()
        let coordinator = ManuscriptFormattingCoordinator(
            documentStore: store,
            editDebounce: .zero,
            formatOperation: { text, _, _ in await formatter.format(text) }
        )

        coordinator.requestFormatting()
        try await waitUntil { await formatter.requestCount == 1 }
        store.setProUnlocked(false)

        await formatter.resolveRequest(at: 0, with: "stale paid result")
        try await waitUntil { !coordinator.isFormatting }
        XCTAssertEqual(store.document.body, "original")
    }

    private func makeStore(
        body: String,
        premium: Bool
    ) -> DocumentStore {
        let document = configuredDocument(title: "Work", body: body)
        return makeStore(
            works: [document],
            activeID: document.id,
            premium: premium
        )
    }

    private func makeStore(
        works: [ManuscriptDocument],
        activeID: UUID,
        premium: Bool
    ) -> DocumentStore {
        DocumentStore(
            appData: AppData(
                version: AppData.currentVersion,
                categories: [.uncategorized],
                works: works,
                userDefaultSettings: .default,
                activeWorkId: activeID,
                subscriptionStatus: premium ? .paid : .free
            )
        )
    }

    private func configuredDocument(
        title: String,
        body: String
    ) -> ManuscriptDocument {
        var document = ManuscriptDocument(title: title, body: body)
        document.settings.formatSettings.enableAutoFormat = true
        return document
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping () async -> Bool
    ) async throws {
        let deadline = ContinuousClock().now.advanced(by: timeout)
        while !(await condition()) {
            guard ContinuousClock().now < deadline else {
                XCTFail("Timed out waiting for formatting condition")
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
    private struct Request {
        let text: String
        let continuation: CheckedContinuation<String, Never>
    }

    private var requests: [Request] = []

    var requestCount: Int { requests.count }

    func requestText(at index: Int) -> String {
        requests[index].text
    }

    func format(_ text: String) async -> String {
        await withCheckedContinuation { continuation in
            requests.append(
                Request(text: text, continuation: continuation)
            )
        }
    }

    func resolveRequest(at index: Int, with result: String) {
        requests[index].continuation.resume(returning: result)
    }
}
