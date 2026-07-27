import Foundation

@MainActor
protocol PDFExportProducing {
    func export(document: ManuscriptDocument, subscriptionStatus: SubscriptionStatus) async throws -> URL
}

@MainActor
protocol PDFExportAdPresenting: AnyObject {
    func presentAdIfNeeded(
        documentID: UUID,
        entitlementState: ProEntitlementState
    ) async
}

extension PDFExportService: PDFExportProducing {}

@MainActor
final class PDFExportFlowCoordinator {
    private var isExporting = false
    private let timeout: Duration
    private let timeoutSleeper: PDFExportTimeoutSleeping
    private let fileManager: FileManager

    init(
        timeout: Duration = .seconds(30),
        timeoutSleeper: PDFExportTimeoutSleeping? = nil,
        fileManager: FileManager = .default
    ) {
        self.timeout = timeout
        self.timeoutSleeper = timeoutSleeper ?? TaskPDFExportTimeoutSleeper()
        self.fileManager = fileManager
    }

    @discardableResult
    func exportAndShare(
        document: ManuscriptDocument,
        subscriptionStatus: SubscriptionStatus,
        entitlementState: ProEntitlementState,
        pdfExporter: PDFExportProducing,
        adPresenter: PDFExportAdPresenting,
        storeGeneratedURL: @MainActor (URL) -> Void = { _ in },
        share: @MainActor (URL) -> Void,
        handleError: @MainActor (Error) -> Void
    ) async -> Bool {
        guard !isExporting else { return false }
        isExporting = true
        defer { isExporting = false }

        do {
            let url = try await exportWithTimeout(
                document: document,
                subscriptionStatus: subscriptionStatus,
                pdfExporter: pdfExporter
            )
            storeGeneratedURL(url)
            await adPresenter.presentAdIfNeeded(
                documentID: document.id,
                entitlementState: entitlementState
            )
            share(url)
            return true
        } catch {
            handleError(error)
            return true
        }
    }

    private func exportWithTimeout(
        document: ManuscriptDocument,
        subscriptionStatus: SubscriptionStatus,
        pdfExporter: PDFExportProducing
    ) async throws -> URL {
        let gate = PDFExportCompletionGate()

        let exportTask = Task { @MainActor in
            do {
                let url = try await pdfExporter.export(
                    document: document,
                    subscriptionStatus: subscriptionStatus
                )
                if !gate.resolve(.success(url)) {
                    try? fileManager.removeItem(at: url)
                }
            } catch {
                _ = gate.resolve(.failure(error))
            }
        }

        let timeoutTask = Task { @MainActor in
            do {
                try await timeoutSleeper.sleep(for: timeout)
            } catch {
                return
            }

            if gate.resolve(.failure(PDFExportFlowError.timedOut)) {
                exportTask.cancel()
            }
        }

        defer {
            exportTask.cancel()
            timeoutTask.cancel()
        }
        return try await gate.value()
    }
}

@MainActor
private final class PDFExportCompletionGate {
    private var continuation: CheckedContinuation<URL, Error>?
    private var resolvedResult: Result<URL, Error>?

    func value() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            if let resolvedResult {
                continuation.resume(with: resolvedResult)
            } else {
                self.continuation = continuation
            }
        }
    }

    @discardableResult
    func resolve(_ result: Result<URL, Error>) -> Bool {
        guard resolvedResult == nil else { return false }
        resolvedResult = result
        continuation?.resume(with: result)
        continuation = nil
        return true
    }
}
