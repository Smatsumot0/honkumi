import Combine
import Foundation
import OSLog

@MainActor
protocol PDFExportConsentManaging: AnyObject {
    var canRequestAds: Bool { get }

    func requestConsentInfoUpdate(completion: @MainActor @escaping () -> Void)
    func loadAndPresentConsentFormIfRequired() async
}

@MainActor
protocol PDFExportMobileAdsStarting: AnyObject {
    func start() async
}

@MainActor
protocol PDFExportInterstitialAdLoading: AnyObject {
    func loadInterstitialAd(adUnitID: String) async throws -> PDFExportInterstitialAd
}

@MainActor
protocol PDFExportInterstitialAd: AnyObject {
    var delegate: PDFExportInterstitialAdDelegate? { get set }

    func canPresent() throws
    func present()
}

@MainActor
protocol PDFExportInterstitialAdDelegate: AnyObject {
    func interstitialAdWillPresent()
    func interstitialAdDidDismiss()
    func interstitialAdDidFailToPresent(error: Error)
}

@MainActor
protocol PDFExportAdRetryScheduling: AnyObject {
    func scheduleRetry(after delay: TimeInterval, operation: @MainActor @escaping () async -> Void)
}

@MainActor
final class PDFExportAdService: ObservableObject, PDFExportAdPresenting {
    private let configurationProvider: () -> PDFExportAdConfiguration
    private let consentManager: PDFExportConsentManaging
    private let mobileAdsStarter: PDFExportMobileAdsStarting
    private let adLoader: PDFExportInterstitialAdLoading
    private let cooldownStore: PDFExportAdCooldownStoring
    private let clock: PDFExportAdClock
    private let retryScheduler: PDFExportAdRetryScheduling
    private let cooldownPolicy = PDFExportAdCooldownPolicy()
    private let adLoadRetryDelay: TimeInterval = 15

    private var entitlementState: ProEntitlementState = .unknown
    private var hasStartedMobileAdsSDK = false
    private var isUpdatingConsent = false
    private var isLoadingAd = false
    private var isLoadRetryScheduled = false
    private var loadedAd: PDFExportInterstitialAd?
    private var activePresentation: PDFExportAdPresentation?

    convenience init() {
        self.init(
            configurationProvider: { PDFExportAdConfiguration.current() },
            consentManager: GooglePDFExportConsentManager(),
            mobileAdsStarter: GooglePDFExportMobileAdsStarter(),
            adLoader: GooglePDFExportInterstitialAdLoader(),
            cooldownStore: InMemoryPDFExportAdCooldownStore(),
            clock: SystemPDFExportAdClock(),
            retryScheduler: TaskPDFExportAdRetryScheduler()
        )
    }

    init(
        configurationProvider: @escaping () -> PDFExportAdConfiguration,
        consentManager: PDFExportConsentManaging,
        mobileAdsStarter: PDFExportMobileAdsStarting,
        adLoader: PDFExportInterstitialAdLoading,
        cooldownStore: PDFExportAdCooldownStoring,
        clock: PDFExportAdClock,
        retryScheduler: PDFExportAdRetryScheduling
    ) {
        self.configurationProvider = configurationProvider
        self.consentManager = consentManager
        self.mobileAdsStarter = mobileAdsStarter
        self.adLoader = adLoader
        self.cooldownStore = cooldownStore
        self.clock = clock
        self.retryScheduler = retryScheduler
    }

    func updateEntitlementState(_ state: ProEntitlementState) {
        entitlementState = state

        guard state == .free else {
            loadedAd = nil
            return
        }
    }

    func prepareForAppLaunch() async {
        guard !isUpdatingConsent else {
            PDFExportAdLog.logger.info("PDF export ad launch preparation skipped: consent update already running.")
            return
        }
        PDFExportAdLog.logger.info("PDF export ad launch preparation started.")
        isUpdatingConsent = true
        defer {
            isUpdatingConsent = false
            PDFExportAdLog.logger.info("PDF export ad launch preparation finished.")
        }

        let consentInfoUpdate = PDFExportConsentInfoUpdate()
        consentManager.requestConsentInfoUpdate {
            consentInfoUpdate.finish()
        }

        await preloadAdIfEligible()
        await consentInfoUpdate.wait()
        await preloadAdIfEligible()
        await consentManager.loadAndPresentConsentFormIfRequired()
        await preloadAdIfEligible()
    }

    func preloadAdIfEligible() async {
        guard entitlementState == .free else {
            loadedAd = nil
            logSkip("preload skipped because entitlement is \(String(describing: entitlementState))")
            return
        }

        let configuration = configurationProvider()
        guard configuration.isEnabled else {
            logDisabledConfiguration(configuration)
            return
        }

        guard consentManager.canRequestAds else {
            logSkip("preload skipped because UMP canRequestAds is false")
            return
        }

        guard let adUnitID = configuration.interstitialAdUnitID else {
            PDFExportAdLog.logger.error("PDF export ad unit ID is missing.")
            return
        }

        if !hasStartedMobileAdsSDK {
            hasStartedMobileAdsSDK = true
            PDFExportAdLog.logger.info("Starting Google Mobile Ads SDK for PDF export ads.")
            await mobileAdsStarter.start()
        }

        await loadAdIfNeeded(adUnitID: adUnitID)
    }

    func presentAdIfNeeded(
        documentID: UUID,
        entitlementState currentEntitlementState: ProEntitlementState
    ) async {
        updateEntitlementState(currentEntitlementState)

        guard currentEntitlementState == .free else {
            logSkip("presentation skipped because entitlement is \(String(describing: currentEntitlementState))")
            return
        }

        let configuration = configurationProvider()
        guard configuration.isEnabled else {
            logDisabledConfiguration(configuration)
            return
        }

        guard consentManager.canRequestAds else {
            logSkip("presentation skipped because UMP canRequestAds is false")
            return
        }

        guard hasStartedMobileAdsSDK else {
            logSkip("presentation skipped because Mobile Ads SDK is not started")
            Task { await preloadAdIfEligible() }
            return
        }

        guard !cooldownPolicy.isCoolingDown(
            lastPresentedAt: cooldownStore.lastPresentedAt(for: documentID),
            now: clock.now
        ) else {
            logSkip("presentation skipped because cooldown is active for \(documentID.uuidString)")
            return
        }

        guard let ad = loadedAd else {
            logSkip("presentation skipped because no interstitial ad is loaded")
            Task { await preloadAdIfEligible() }
            return
        }

        loadedAd = nil

        do {
            try ad.canPresent()
        } catch {
            PDFExportAdLog.logger.error("PDF export ad canPresent failed: \(error.localizedDescription, privacy: .public)")
            Task { await preloadAdIfEligible() }
            return
        }

        PDFExportAdLog.logger.info("Presenting PDF export interstitial ad.")
        await presentLoadedAd(ad, documentID: documentID)
    }

    private func loadAdIfNeeded(adUnitID: String) async {
        guard loadedAd == nil, !isLoadingAd else { return }
        isLoadingAd = true
        defer { isLoadingAd = false }

        do {
            let ad = try await adLoader.loadInterstitialAd(adUnitID: adUnitID)
            guard entitlementState == .free else {
                loadedAd = nil
                logSkip("discarded loaded ad because entitlement changed to \(String(describing: entitlementState))")
                return
            }
            isLoadRetryScheduled = false
            loadedAd = ad
            PDFExportAdLog.logger.info("PDF export interstitial ad loaded.")
        } catch {
            PDFExportAdLog.logger.error("Failed to load PDF export interstitial ad: \(error.localizedDescription, privacy: .public)")
            scheduleLoadRetryIfEligible()
        }
    }

    private func scheduleLoadRetryIfEligible() {
        guard !isLoadRetryScheduled else { return }
        guard entitlementState == .free else { return }
        guard configurationProvider().isEnabled else { return }
        guard consentManager.canRequestAds else { return }

        isLoadRetryScheduled = true
        PDFExportAdLog.logger.info("PDF export interstitial ad retry scheduled.")
        retryScheduler.scheduleRetry(after: adLoadRetryDelay) { [weak self] in
            guard let self else { return }
            self.isLoadRetryScheduled = false
            await self.preloadAdIfEligible()
        }
    }

    private func presentLoadedAd(_ ad: PDFExportInterstitialAd, documentID: UUID) async {
        await withCheckedContinuation { continuation in
            let presentation = PDFExportAdPresentation(
                documentID: documentID,
                clock: clock,
                cooldownStore: cooldownStore,
                onComplete: { [weak self] in
                    self?.activePresentation = nil
                    continuation.resume()
                    Task { await self?.preloadAdIfEligible() }
                }
            )
            activePresentation = presentation
            ad.delegate = presentation
            ad.present()
        }
    }

    private func logDisabledConfiguration(_ configuration: PDFExportAdConfiguration) {
        if let reason = configuration.disableReason {
            PDFExportAdLog.logger.error("\(reason, privacy: .public)")
        }
    }

    private func logSkip(_ reason: String) {
        PDFExportAdLog.logger.info("\(reason, privacy: .public)")
    }
}

@MainActor
private final class TaskPDFExportAdRetryScheduler: PDFExportAdRetryScheduling {
    func scheduleRetry(after delay: TimeInterval, operation: @MainActor @escaping () async -> Void) {
        Task { @MainActor in
            let nanoseconds = UInt64(max(delay, 0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await operation()
        }
    }
}

@MainActor
private final class PDFExportConsentInfoUpdate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isFinished = false

    func wait() async {
        guard !isFinished else { return }

        await withCheckedContinuation { continuation in
            guard !isFinished else {
                continuation.resume()
                return
            }
            self.continuation = continuation
        }
    }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class PDFExportAdPresentation: PDFExportInterstitialAdDelegate {
    private let documentID: UUID
    private let clock: PDFExportAdClock
    private let cooldownStore: PDFExportAdCooldownStoring
    private let onComplete: () -> Void
    private var hasRecordedPresentation = false
    private var hasCompleted = false

    init(
        documentID: UUID,
        clock: PDFExportAdClock,
        cooldownStore: PDFExportAdCooldownStoring,
        onComplete: @escaping () -> Void
    ) {
        self.documentID = documentID
        self.clock = clock
        self.cooldownStore = cooldownStore
        self.onComplete = onComplete
    }

    func interstitialAdWillPresent() {
        guard !hasRecordedPresentation else { return }
        hasRecordedPresentation = true
        cooldownStore.recordPresentation(at: clock.now, for: documentID)
    }

    func interstitialAdDidDismiss() {
        completeOnce()
    }

    func interstitialAdDidFailToPresent(error: Error) {
        PDFExportAdLog.logger.error("PDF export ad failed to present: \(error.localizedDescription, privacy: .public)")
        completeOnce()
    }

    private func completeOnce() {
        guard !hasCompleted else { return }
        hasCompleted = true
        onComplete()
    }
}
