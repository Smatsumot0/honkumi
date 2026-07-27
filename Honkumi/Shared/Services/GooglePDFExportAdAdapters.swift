import Foundation
import GoogleMobileAds
import OSLog
import UserMessagingPlatform

@MainActor
final class GooglePDFExportConsentManager: PDFExportConsentManaging {
    var canRequestAds: Bool {
        ConsentInformation.shared.canRequestAds
    }

    func requestConsentInfoUpdate(completion: @MainActor @escaping () -> Void) {
        let parameters = RequestParameters()

        ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { error in
            if let error {
                PDFExportAdLog.logger.error("UMP consent info update failed: \(error.localizedDescription, privacy: .public)")
            }

            Task { @MainActor in
                completion()
            }
        }
    }

    func loadAndPresentConsentFormIfRequired() async {
        do {
            try await ConsentForm.loadAndPresentIfRequired(from: nil)
        } catch {
            PDFExportAdLog.logger.error("UMP consent form failed: \(error.localizedDescription, privacy: .public)")
        }
    }

}

@MainActor
final class GooglePDFExportMobileAdsStarter: PDFExportMobileAdsStarting {
    func start() async {
        _ = await MobileAds.shared.start()
    }
}

@MainActor
final class GooglePDFExportInterstitialAdLoader: PDFExportInterstitialAdLoading {
    func loadInterstitialAd(adUnitID: String) async throws -> PDFExportInterstitialAd {
        let ad = try await InterstitialAd.load(with: adUnitID, request: Request())
        return GooglePDFExportInterstitialAd(ad: ad)
    }
}

@MainActor
private final class GooglePDFExportInterstitialAd: NSObject, PDFExportInterstitialAd {
    weak var delegate: PDFExportInterstitialAdDelegate?

    private let ad: InterstitialAd

    init(ad: InterstitialAd) {
        self.ad = ad
        super.init()
        self.ad.fullScreenContentDelegate = self
    }

    func canPresent() throws {
        try ad.canPresent(from: nil)
    }

    func present() {
        ad.present(from: nil)
    }
}

extension GooglePDFExportInterstitialAd: FullScreenContentDelegate {
    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        delegate?.interstitialAdWillPresent()
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        delegate?.interstitialAdDidDismiss()
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        delegate?.interstitialAdDidFailToPresent(error: error)
    }
}
