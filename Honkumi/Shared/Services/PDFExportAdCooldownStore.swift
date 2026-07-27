import Foundation

protocol PDFExportAdClock {
    var now: Date { get }
}

struct SystemPDFExportAdClock: PDFExportAdClock {
    var now: Date {
        Date()
    }
}

@MainActor
protocol PDFExportAdCooldownStoring: AnyObject {
    func lastPresentedAt(for documentID: UUID) -> Date?
    func recordPresentation(at date: Date, for documentID: UUID)
}

@MainActor
final class InMemoryPDFExportAdCooldownStore: PDFExportAdCooldownStoring {
    private var datesByDocumentID: [UUID: Date] = [:]

    func lastPresentedAt(for documentID: UUID) -> Date? {
        datesByDocumentID[documentID]
    }

    func recordPresentation(at date: Date, for documentID: UUID) {
        datesByDocumentID[documentID] = date
    }
}

struct PDFExportAdCooldownPolicy {
    static let duration: TimeInterval = 5 * 60

    func isCoolingDown(lastPresentedAt: Date?, now: Date) -> Bool {
        guard let lastPresentedAt else { return false }
        return now.timeIntervalSince(lastPresentedAt) < Self.duration
    }
}
