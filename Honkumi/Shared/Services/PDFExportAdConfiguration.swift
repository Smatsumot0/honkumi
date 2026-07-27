import Foundation
import OSLog

struct PDFExportAdConfiguration: Equatable {
    static let officialTestApplicationID = "ca-app-pub-3940256099942544~1458002511"
    static let officialTestInterstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910"
    static let applicationIDInfoKey = "GADApplicationIdentifier"
    static let interstitialAdUnitIDInfoKey = "HonkumiPDFExportInterstitialAdUnitID"

    let isEnabled: Bool
    let applicationID: String?
    let interstitialAdUnitID: String?
    let isTestMode: Bool
    let disableReason: String?

    static func current(bundle: Bundle = .main) -> PDFExportAdConfiguration {
        #if ADS_TEST_MODE
        return PDFExportAdConfiguration(
            isEnabled: true,
            applicationID: officialTestApplicationID,
            interstitialAdUnitID: officialTestInterstitialAdUnitID,
            isTestMode: true,
            disableReason: nil
        )
        #else
        let applicationID = normalizedString(bundle.object(forInfoDictionaryKey: applicationIDInfoKey))
        let adUnitID = normalizedString(bundle.object(forInfoDictionaryKey: interstitialAdUnitIDInfoKey))

        guard isValidApplicationID(applicationID), !isPlaceholder(applicationID) else {
            return disabled(
                applicationID: applicationID,
                interstitialAdUnitID: adUnitID,
                reason: "Release AdMob application ID is missing, placeholder, or invalid."
            )
        }

        guard isValidInterstitialAdUnitID(adUnitID), !isPlaceholder(adUnitID) else {
            return disabled(
                applicationID: applicationID,
                interstitialAdUnitID: adUnitID,
                reason: "Release PDF export interstitial ad unit ID is missing, placeholder, or invalid."
            )
        }

        return PDFExportAdConfiguration(
            isEnabled: true,
            applicationID: applicationID,
            interstitialAdUnitID: adUnitID,
            isTestMode: false,
            disableReason: nil
        )
        #endif
    }

    private static func disabled(
        applicationID: String?,
        interstitialAdUnitID: String?,
        reason: String
    ) -> PDFExportAdConfiguration {
        PDFExportAdConfiguration(
            isEnabled: false,
            applicationID: applicationID,
            interstitialAdUnitID: interstitialAdUnitID,
            isTestMode: false,
            disableReason: reason
        )
    }

    private static func normalizedString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isValidApplicationID(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.range(
            of: #"^ca-app-pub-[0-9]{16}~[0-9]{10}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isValidInterstitialAdUnitID(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.range(
            of: #"^ca-app-pub-[0-9]{16}/[0-9]{10}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isPlaceholder(_ value: String?) -> Bool {
        guard let value else { return true }
        return value.contains("0000000000000000") || value.contains("xxxxxxxx")
    }
}

enum PDFExportAdLog {
    static let logger = Logger(subsystem: "jp.honkumi.Honkumi", category: "PDFExportAds")
}
