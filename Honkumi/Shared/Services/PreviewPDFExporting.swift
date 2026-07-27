import Foundation

@MainActor
protocol PreviewPDFExporting {
    func exportPreviewPDF(
        document: ManuscriptDocument,
        subscriptionStatus: SubscriptionStatus,
        previewKind: PreviewPDFKind,
        generationID: UUID
    ) async throws -> URL
}

extension PDFExportService: PreviewPDFExporting {}
