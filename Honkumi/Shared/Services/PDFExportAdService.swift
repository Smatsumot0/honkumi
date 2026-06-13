import Foundation

@MainActor
struct PDFExportAdService {
    func presentAdIfNeeded(subscriptionStatus: SubscriptionStatus) async {
        guard subscriptionStatus == .free else { return }

        // 広告SDKを組み込む場合は、この境界で表示完了を待ってからPDF生成へ進む。
        #if DEBUG
        print("PDF export ad display requested for free user.")
        #endif
    }
}
