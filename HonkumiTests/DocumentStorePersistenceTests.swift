@testable import Honkumi
import XCTest

@MainActor
final class DocumentStorePersistenceTests: XCTestCase {
    func testLateOldEncodingCannotOverwriteNewSettings() async throws {
        let suiteName = "DocumentStorePersistenceTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let document = ManuscriptDocument(title: "Persistence", body: "本文")
        let initialData = AppData(
            version: AppData.currentVersion,
            categories: [.uncategorized],
            works: [document],
            userDefaultSettings: .default,
            activeWorkId: document.id,
            subscriptionStatus: .free
        )
        let initialEncoder = JSONEncoder()
        initialEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        userDefaults.set(
            try initialEncoder.encode(initialData),
            forKey: "honkumi.appData"
        )

        let harness = PersistenceEncoderHarness()
        let store = DocumentStore(
            userDefaults: userDefaults,
            encodeOperation: { appData in
                await harness.encode(appData)
            }
        )

        var first = store.document.settings
        first.fontSize = 11
        store.updateSettings(first)
        try await waitUntil {
            await harness.requestCount == 1
        }

        var second = first
        second.fontSize = 12
        store.updateSettings(second)

        XCTAssertEqual(store.document.settings.fontSize, 12)
        try await waitUntil {
            await harness.requestCount == 2
        }

        await harness.complete(request: 1)
        try await waitUntil {
            try self.persistedFontSize(in: userDefaults) == 12
        }

        await harness.complete(request: 0)
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(try persistedFontSize(in: userDefaults), 12)
    }

    private func persistedFontSize(in userDefaults: UserDefaults) throws -> CGFloat {
        let data = try XCTUnwrap(userDefaults.data(forKey: "honkumi.appData"))
        let appData = try JSONDecoder().decode(AppData.self, from: data)
        let activeWork = try XCTUnwrap(
            appData.works.first { $0.id == appData.activeWorkId }
        )
        return activeWork.settings.fontSize
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping () async throws -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while try await !condition() {
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

private actor PersistenceEncoderHarness {
    private struct Request {
        let appData: AppData
        let continuation: CheckedContinuation<Data?, Never>
    }

    private var requests: [Request] = []

    var requestCount: Int {
        requests.count
    }

    func encode(_ appData: AppData) async -> Data? {
        await withCheckedContinuation { continuation in
            requests.append(
                Request(
                    appData: appData,
                    continuation: continuation
                )
            )
        }
    }

    func complete(request index: Int) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        requests[index].continuation.resume(
            returning: try? encoder.encode(requests[index].appData)
        )
    }
}
