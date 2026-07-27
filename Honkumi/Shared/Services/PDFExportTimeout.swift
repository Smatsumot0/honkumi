import Foundation

nonisolated enum PDFExportFlowError: LocalizedError, Equatable {
    case timedOut

    var errorDescription: String? {
        switch self {
        case .timedOut:
            "PDF生成が30秒以内に完了しませんでした。もう一度お試しください。"
        }
    }
}

@MainActor
protocol PDFExportTimeoutSleeping: AnyObject {
    func sleep(for duration: Duration) async throws
}

@MainActor
final class TaskPDFExportTimeoutSleeper: PDFExportTimeoutSleeping {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
