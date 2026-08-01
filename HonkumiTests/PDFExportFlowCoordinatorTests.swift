import Foundation
@testable import Honkumi
import XCTest

@MainActor
final class PDFExportFlowCoordinatorTests: XCTestCase {
    func testDefaultCoordinatorCanBeReleasedFromSynchronousMainQueueCallback() async {
        let didRelease = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let released = MainActor.assumeIsolated {
                    weak var weakCoordinator: PDFExportFlowCoordinator?
                    autoreleasepool {
                        let coordinator = PDFExportFlowCoordinator()
                        weakCoordinator = coordinator
                    }
                    return weakCoordinator == nil
                }
                continuation.resume(returning: released)
            }
        }

        XCTAssertTrue(didRelease)
    }

    func testTimeoutErrorHasRetryableUserMessage() {
        XCTAssertEqual(
            PDFExportFlowError.timedOut.localizedDescription,
            "PDF生成が30秒以内に完了しませんでした。もう一度お試しください。"
        )
    }

    func testTimeoutSkipsGeneratedURLAdAndShareThenAllowsImmediateRetry() async throws {
        let sleeper = ManualPDFExportTimeoutSleeper()
        let coordinator = PDFExportFlowCoordinator(timeoutSleeper: sleeper)
        let events = EventRecorder()
        let suspendedExporter = SuspendedPDFExporter(events: events)
        let adPresenter = FakePDFExportAdPresenter(events: events)
        var storedURLs: [URL] = []
        var sharedURLs: [URL] = []
        var handledErrors: [Error] = []

        async let timedOutFlow: Bool = coordinator.exportAndShare(
            document: ManuscriptDocument(title: "Timeout", body: "本文"),
            subscriptionStatus: .free,
            entitlementState: .free,
            pdfExporter: suspendedExporter,
            adPresenter: adPresenter,
            storeGeneratedURL: { storedURLs.append($0) },
            share: { sharedURLs.append($0) },
            handleError: { handledErrors.append($0) }
        )
        try await waitUntil { sleeper.requestedDurations.count == 1 }
        sleeper.fire()
        let didFinishTimedOutFlow = await timedOutFlow
        XCTAssertTrue(didFinishTimedOutFlow)

        XCTAssertEqual(sleeper.requestedDurations, [.seconds(30)])
        XCTAssertTrue(storedURLs.isEmpty)
        XCTAssertTrue(sharedURLs.isEmpty)
        XCTAssertTrue(adPresenter.requestedEntitlementStates.isEmpty)
        XCTAssertEqual(handledErrors.count, 1)
        XCTAssertEqual(handledErrors.first as? PDFExportFlowError, .timedOut)

        let retryURL = URL(fileURLWithPath: "/tmp/honkumi-timeout-retry.pdf")
        let retryExporter = FakePDFExporter(result: .success(retryURL), events: events)
        let didStartRetry = await coordinator.exportAndShare(
            document: ManuscriptDocument(title: "Retry", body: "本文"),
            subscriptionStatus: .free,
            entitlementState: .free,
            pdfExporter: retryExporter,
            adPresenter: adPresenter,
            share: { sharedURLs.append($0) },
            handleError: { handledErrors.append($0) }
        )

        XCTAssertTrue(didStartRetry)
        XCTAssertEqual(sharedURLs, [retryURL])
        XCTAssertEqual(handledErrors.count, 1)

        suspendedExporter.resume(
            with: FileManager.default.temporaryDirectory
                .appendingPathComponent("honkumi-abandoned-\(UUID().uuidString).pdf")
        )
    }

    func testLateURLAfterTimeoutIsDeletedAndNeverShared() async throws {
        let sleeper = ManualPDFExportTimeoutSleeper()
        let coordinator = PDFExportFlowCoordinator(timeoutSleeper: sleeper)
        let events = EventRecorder()
        let exporter = SuspendedPDFExporter(events: events)
        let adPresenter = FakePDFExportAdPresenter(events: events)
        let lateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("honkumi-late-\(UUID().uuidString).pdf")
        try Data("%PDF-1.4\n".utf8).write(to: lateURL)
        var shareCount = 0
        var errors: [Error] = []

        async let timedOutFlow: Bool = coordinator.exportAndShare(
            document: ManuscriptDocument(title: "Late", body: "本文"),
            subscriptionStatus: .free,
            entitlementState: .free,
            pdfExporter: exporter,
            adPresenter: adPresenter,
            share: { _ in shareCount += 1 },
            handleError: { errors.append($0) }
        )
        try await waitUntil { sleeper.requestedDurations.count == 1 }
        sleeper.fire()
        _ = await timedOutFlow
        exporter.resume(with: lateURL)

        try await waitUntil { !FileManager.default.fileExists(atPath: lateURL.path) }
        XCTAssertEqual(shareCount, 0)
        XCTAssertEqual(errors.first as? PDFExportFlowError, .timedOut)
    }

    func testTimeoutFiredAfterSuccessDoesNotCompleteFlowAgain() async {
        let sleeper = ManualPDFExportTimeoutSleeper()
        let coordinator = PDFExportFlowCoordinator(timeoutSleeper: sleeper)
        let events = EventRecorder()
        let pdfURL = URL(fileURLWithPath: "/tmp/honkumi-before-timeout.pdf")
        let exporter = FakePDFExporter(result: .success(pdfURL), events: events)
        let adPresenter = FakePDFExportAdPresenter(events: events)
        var shareCount = 0
        var errors: [Error] = []

        await coordinator.exportAndShare(
            document: ManuscriptDocument(title: "Success", body: "本文"),
            subscriptionStatus: .free,
            entitlementState: .free,
            pdfExporter: exporter,
            adPresenter: adPresenter,
            share: { _ in shareCount += 1 },
            handleError: { errors.append($0) }
        )
        sleeper.fire()
        await Task.yield()

        XCTAssertEqual(shareCount, 1)
        XCTAssertTrue(errors.isEmpty)
    }

    func testPDFGenerationSuccessRequestsAdAfterURLIsProducedThenShares() async {
        let coordinator = PDFExportFlowCoordinator()
        let events = EventRecorder()
        let pdfURL = URL(fileURLWithPath: "/tmp/honkumi-flow-success.pdf")
        let exporter = FakePDFExporter(result: .success(pdfURL), events: events)
        let adPresenter = FakePDFExportAdPresenter(events: events)
        let document = ManuscriptDocument(title: "Flow Success", body: "本文")
        var sharedURLs: [URL] = []
        var handledErrors: [Error] = []

        await coordinator.exportAndShare(
            document: document,
            subscriptionStatus: .free,
            entitlementState: .free,
            pdfExporter: exporter,
            adPresenter: adPresenter,
            share: { url in
                events.append("share")
                sharedURLs.append(url)
            },
            handleError: { error in
                handledErrors.append(error)
            }
        )

        XCTAssertEqual(events.values, ["pdf-start", "pdf-success", "ad", "share"])
        XCTAssertEqual(adPresenter.requestedDocumentIDs, [document.id])
        XCTAssertEqual(adPresenter.requestedEntitlementStates, [.free])
        XCTAssertEqual(sharedURLs, [pdfURL])
        XCTAssertTrue(handledErrors.isEmpty)
    }

    func testPDFGenerationFailureSkipsAdAndShare() async {
        let coordinator = PDFExportFlowCoordinator()
        let events = EventRecorder()
        let exporter = FakePDFExporter(result: .failure(FakePDFExportError.failed), events: events)
        let adPresenter = FakePDFExportAdPresenter(events: events)
        var shareCount = 0
        var handledErrors: [Error] = []

        await coordinator.exportAndShare(
            document: ManuscriptDocument(title: "Flow Failure", body: "本文"),
            subscriptionStatus: .free,
            entitlementState: .free,
            pdfExporter: exporter,
            adPresenter: adPresenter,
            share: { _ in
                shareCount += 1
            },
            handleError: { error in
                handledErrors.append(error)
            }
        )

        XCTAssertEqual(events.values, ["pdf-start", "pdf-failure"])
        XCTAssertTrue(adPresenter.requestedEntitlementStates.isEmpty)
        XCTAssertEqual(shareCount, 0)
        XCTAssertEqual(handledErrors.count, 1)
    }

    func testConcurrentExportsRunOnlyOnePDFAdAndShareFlow() async throws {
        let coordinator = PDFExportFlowCoordinator()
        let events = EventRecorder()
        let exporter = SuspendedPDFExporter(events: events)
        let adPresenter = FakePDFExportAdPresenter(events: events)
        var sharedURLs: [URL] = []
        var handledErrors: [Error] = []

        async let first: Bool = coordinator.exportAndShare(
            document: ManuscriptDocument(title: "First", body: "本文"),
            subscriptionStatus: .free,
            entitlementState: .free,
            pdfExporter: exporter,
            adPresenter: adPresenter,
            share: { url in
                events.append("share")
                sharedURLs.append(url)
            },
            handleError: { error in
                handledErrors.append(error)
            }
        )
        async let second: Bool = coordinator.exportAndShare(
            document: ManuscriptDocument(title: "Second", body: "本文"),
            subscriptionStatus: .free,
            entitlementState: .free,
            pdfExporter: exporter,
            adPresenter: adPresenter,
            share: { url in
                events.append("share")
                sharedURLs.append(url)
            },
            handleError: { error in
                handledErrors.append(error)
            }
        )

        try await waitUntil { exporter.callCount == 1 }
        XCTAssertEqual(exporter.callCount, 1)

        let pdfURL = URL(fileURLWithPath: "/tmp/honkumi-single-export.pdf")
        exporter.resume(with: pdfURL)
        _ = await first
        _ = await second

        XCTAssertEqual(events.values, ["pdf-start", "pdf-success", "ad", "share"])
        XCTAssertEqual(adPresenter.requestedEntitlementStates, [.free])
        XCTAssertEqual(sharedURLs, [pdfURL])
        XCTAssertTrue(handledErrors.isEmpty)
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
final class FakePDFExporter: PDFExportProducing {
    private let result: Result<URL, Error>
    private let events: EventRecorder

    init(result: Result<URL, Error>, events: EventRecorder) {
        self.result = result
        self.events = events
    }

    func export(document: ManuscriptDocument, subscriptionStatus: SubscriptionStatus) async throws -> URL {
        events.append("pdf-start")
        switch result {
        case .success(let url):
            events.append("pdf-success")
            return url
        case .failure(let error):
            events.append("pdf-failure")
            throw error
        }
    }
}

@MainActor
private final class SuspendedPDFExporter: PDFExportProducing {
    private let events: EventRecorder
    private var continuation: CheckedContinuation<URL, Never>?
    private(set) var callCount = 0

    init(events: EventRecorder) {
        self.events = events
    }

    func export(document: ManuscriptDocument, subscriptionStatus: SubscriptionStatus) async throws -> URL {
        callCount += 1
        events.append("pdf-start")
        let url = await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        events.append("pdf-success")
        return url
    }

    func resume(with url: URL) {
        continuation?.resume(returning: url)
        continuation = nil
    }
}

@MainActor
private final class FakePDFExportAdPresenter: PDFExportAdPresenting {
    private let events: EventRecorder
    private(set) var requestedDocumentIDs: [UUID] = []
    private(set) var requestedEntitlementStates: [ProEntitlementState] = []

    init(events: EventRecorder) {
        self.events = events
    }

    func presentAdIfNeeded(
        documentID: UUID,
        entitlementState: ProEntitlementState
    ) async {
        requestedDocumentIDs.append(documentID)
        requestedEntitlementStates.append(entitlementState)
        events.append("ad")
    }
}

@MainActor
private final class ManualPDFExportTimeoutSleeper: PDFExportTimeoutSleeping {
    private var continuation: CheckedContinuation<Void, Error>?
    private(set) var requestedDurations: [Duration] = []

    func sleep(for duration: Duration) async throws {
        requestedDurations.append(duration)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                continuation = $0
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel()
            }
        }
    }

    func fire() {
        continuation?.resume()
        continuation = nil
    }

    func cancel() {
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}

@MainActor
final class EventRecorder {
    private(set) var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }
}

private enum FakePDFExportError: Error {
    case failed
}
