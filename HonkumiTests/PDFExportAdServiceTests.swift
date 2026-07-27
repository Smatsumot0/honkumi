import Foundation
@testable import Honkumi
import XCTest

@MainActor
final class PDFExportAdServiceTests: XCTestCase {
    func testProUserSkipsAdAndDoesNotStartCooldown() async {
        let documentID = UUID()
        let harness = AdServiceHarness(preloadedAd: FakeInterstitialAd())
        await harness.service.preloadAdIfEligible()

        await harness.service.presentAdIfNeeded(documentID: documentID, entitlementState: .pro)

        XCTAssertEqual(harness.preloadedAd.presentCount, 0)
        XCTAssertNil(harness.cooldownStore.lastPresentedAt(for: documentID))
    }

    func testUnknownPurchaseStateSkipsAd() async {
        let documentID = UUID()
        let harness = AdServiceHarness(preloadedAd: FakeInterstitialAd())
        await harness.service.preloadAdIfEligible()

        await harness.service.presentAdIfNeeded(documentID: documentID, entitlementState: .unknown)

        XCTAssertEqual(harness.preloadedAd.presentCount, 0)
        XCTAssertNil(harness.cooldownStore.lastPresentedAt(for: documentID))
    }

    func testFreeUserWithLoadedAdSharesAfterDismiss() async {
        let documentID = UUID()
        let ad = FakeInterstitialAd(presentationBehavior: .willPresentThenDismiss)
        let harness = AdServiceHarness(preloadedAd: ad)
        await harness.service.preloadAdIfEligible()

        await harness.service.presentAdIfNeeded(documentID: documentID, entitlementState: .free)

        XCTAssertEqual(ad.canPresentCount, 1)
        XCTAssertEqual(ad.presentCount, 1)
        XCTAssertEqual(harness.cooldownStore.lastPresentedAt(for: documentID), harness.clock.now)
    }

    func testNoLoadedAdReturnsImmediatelyWithoutCooldown() async {
        let documentID = UUID()
        let harness = AdServiceHarness(preloadedAd: nil)
        await harness.service.preloadAdIfEligible()

        await harness.service.presentAdIfNeeded(documentID: documentID, entitlementState: .free)

        XCTAssertGreaterThanOrEqual(harness.loader.loadCount, 1)
        XCTAssertNil(harness.cooldownStore.lastPresentedAt(for: documentID))
    }

    func testLoadFailureSchedulesBackgroundRetryThatCanFillNextPresentation() async {
        let retriedAd = FakeInterstitialAd(presentationBehavior: .willPresentThenDismiss)
        let harness = AdServiceHarness(
            loaderResults: [
                .failure(FakeAdError.noAd),
                .success(retriedAd)
            ]
        )

        await harness.service.preloadAdIfEligible()

        XCTAssertEqual(harness.loader.loadCount, 1)
        XCTAssertEqual(harness.retryScheduler.scheduledRetryCount, 1)

        await harness.retryScheduler.runNextRetry()
        await harness.service.presentAdIfNeeded(documentID: UUID(), entitlementState: .free)

        XCTAssertEqual(harness.loader.loadCount, 2)
        XCTAssertEqual(retriedAd.presentCount, 1)
    }

    func testAdPresentationFailureReturnsWithoutCooldownWhenAdNeverPresented() async {
        let documentID = UUID()
        let ad = FakeInterstitialAd(presentationBehavior: .failToPresent)
        let harness = AdServiceHarness(preloadedAd: ad)
        await harness.service.preloadAdIfEligible()

        await harness.service.presentAdIfNeeded(documentID: documentID, entitlementState: .free)

        XCTAssertEqual(ad.presentCount, 1)
        XCTAssertNil(harness.cooldownStore.lastPresentedAt(for: documentID))
    }

    func testCanPresentFailureSkipsPresentAndDoesNotStartCooldown() async {
        let documentID = UUID()
        let ad = FakeInterstitialAd(canPresentError: FakeAdError.cannotPresent)
        let harness = AdServiceHarness(preloadedAd: ad)
        await harness.service.preloadAdIfEligible()

        await harness.service.presentAdIfNeeded(documentID: documentID, entitlementState: .free)

        XCTAssertEqual(ad.canPresentCount, 1)
        XCTAssertEqual(ad.presentCount, 0)
        XCTAssertNil(harness.cooldownStore.lastPresentedAt(for: documentID))
    }

    func testDuplicateDelegateNotificationsOnlyCompleteOnce() async {
        let ad = FakeInterstitialAd(presentationBehavior: .manual)
        let harness = AdServiceHarness(preloadedAd: ad)
        await harness.service.preloadAdIfEligible()
        let coordinator = PDFExportFlowCoordinator()
        let document = ManuscriptDocument(title: "Duplicate", body: "本文")
        let exporter = FakePDFExporter(
            result: .success(URL(fileURLWithPath: "/tmp/honkumi-duplicate-delegate.pdf")),
            events: EventRecorder()
        )
        var shareCount = 0

        async let export: Bool = coordinator.exportAndShare(
            document: document,
            subscriptionStatus: .free,
            entitlementState: .free,
            pdfExporter: exporter,
            adPresenter: harness.service,
            share: { _ in
                shareCount += 1
            },
            handleError: { _ in }
        )

        await waitForAdPresentation(ad)
        ad.triggerWillPresent()
        ad.triggerDidDismiss()
        ad.triggerDidFailToPresent()
        ad.triggerDidDismiss()
        _ = await export

        XCTAssertEqual(shareCount, 1)
        XCTAssertEqual(
            harness.cooldownStore.lastPresentedAt(for: document.id),
            harness.clock.now
        )
    }

    func testCooldownStartsOnlyWhenAdWillPresentIsReceived() async {
        let documentID = UUID()
        let ad = FakeInterstitialAd(presentationBehavior: .manual)
        let harness = AdServiceHarness(preloadedAd: ad)
        await harness.service.preloadAdIfEligible()

        async let presentation: Void = harness.service.presentAdIfNeeded(
            documentID: documentID,
            entitlementState: .free
        )
        await waitForAdPresentation(ad)
        XCTAssertNil(harness.cooldownStore.lastPresentedAt(for: documentID))

        ad.triggerWillPresent()
        ad.triggerDidDismiss()
        await presentation

        XCTAssertEqual(harness.cooldownStore.lastPresentedAt(for: documentID), harness.clock.now)
    }

    func testCooldownUnderFiveMinutesSkipsSameWorkAd() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let documentID = UUID()
        let ad = FakeInterstitialAd()
        let harness = AdServiceHarness(now: now.addingTimeInterval(299), preloadedAd: ad)
        harness.cooldownStore.recordPresentation(at: now, for: documentID)
        await harness.service.preloadAdIfEligible()

        await harness.service.presentAdIfNeeded(documentID: documentID, entitlementState: .free)

        XCTAssertEqual(ad.presentCount, 0)
    }

    func testCooldownAtFiveMinutesAllowsSameWorkAd() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let documentID = UUID()
        let ad = FakeInterstitialAd(presentationBehavior: .willPresentThenDismiss)
        let harness = AdServiceHarness(now: now.addingTimeInterval(300), preloadedAd: ad)
        harness.cooldownStore.recordPresentation(at: now, for: documentID)
        await harness.service.preloadAdIfEligible()

        await harness.service.presentAdIfNeeded(documentID: documentID, entitlementState: .free)

        XCTAssertEqual(ad.presentCount, 1)
    }

    func testCooldownIsStoredIndependentlyPerDocument() {
        let workA = UUID()
        let workB = UUID()
        let date = Date(timeIntervalSince1970: 5_000)
        let store = InMemoryPDFExportAdCooldownStore()

        store.recordPresentation(at: date, for: workA)

        XCTAssertEqual(store.lastPresentedAt(for: workA), date)
        XCTAssertNil(store.lastPresentedAt(for: workB))
    }

    func testCooldownDurationIsFiveMinutes() {
        XCTAssertEqual(PDFExportAdCooldownPolicy.duration, 5 * 60)
    }

    func testNewStoreDoesNotRestorePreviousProcessState() {
        let work = UUID()
        let first = InMemoryPDFExportAdCooldownStore()
        first.recordPresentation(at: Date(), for: work)

        let relaunched = InMemoryPDFExportAdCooldownStore()

        XCTAssertNil(relaunched.lastPresentedAt(for: work))
    }

    func testDifferentWorkCanShowDuringAnotherWorksCooldown() async {
        let workA = UUID()
        let workB = UUID()
        let firstAd = FakeInterstitialAd(presentationBehavior: .willPresentThenDismiss)
        let secondAd = FakeInterstitialAd(presentationBehavior: .willPresentThenDismiss)
        let harness = AdServiceHarness(loaderResults: [.success(firstAd), .success(secondAd)])

        await harness.service.preloadAdIfEligible()
        await harness.service.presentAdIfNeeded(documentID: workA, entitlementState: .free)
        await harness.service.preloadAdIfEligible()
        await harness.service.presentAdIfNeeded(documentID: workB, entitlementState: .free)

        XCTAssertEqual(firstAd.presentCount, 1)
        XCTAssertEqual(secondAd.presentCount, 1)
        XCTAssertEqual(harness.cooldownStore.lastPresentedAt(for: workA), harness.clock.now)
        XCTAssertEqual(harness.cooldownStore.lastPresentedAt(for: workB), harness.clock.now)
    }

    func testProUpdateAfterLoadClearsAdAndPreventsFutureLoads() async {
        let ad = FakeInterstitialAd(presentationBehavior: .willPresentThenDismiss)
        let harness = AdServiceHarness(preloadedAd: ad)
        await harness.service.preloadAdIfEligible()

        harness.service.updateEntitlementState(.pro)
        await harness.service.preloadAdIfEligible()
        await harness.service.presentAdIfNeeded(documentID: UUID(), entitlementState: .pro)

        XCTAssertEqual(ad.presentCount, 0)
        XCTAssertEqual(harness.loader.loadCount, 1)
    }

    func testUMPDisallowsRequestsStillReturnsToPDFSharing() async {
        let harness = AdServiceHarness(canRequestAds: false, preloadedAd: FakeInterstitialAd())
        let coordinator = PDFExportFlowCoordinator()
        let document = ManuscriptDocument(title: "Consent", body: "本文")
        let exporter = FakePDFExporter(
            result: .success(URL(fileURLWithPath: "/tmp/honkumi-no-consent.pdf")),
            events: EventRecorder()
        )
        var shareCount = 0

        await coordinator.exportAndShare(
            document: document,
            subscriptionStatus: .free,
            entitlementState: .free,
            pdfExporter: exporter,
            adPresenter: harness.service,
            share: { _ in
                shareCount += 1
            },
            handleError: { _ in }
        )

        XCTAssertEqual(shareCount, 1)
        XCTAssertEqual(harness.preloadedAd.presentCount, 0)
        XCTAssertNil(harness.cooldownStore.lastPresentedAt(for: document.id))
    }

    func testAppLaunchPreloadUsesPreviousSessionConsentWhileConsentUpdateIsInFlight() async {
        let consentManager = SuspendedPDFExportConsentManager(canRequestAds: true)
        let harness = AdServiceHarness(
            consentManager: consentManager,
            preloadedAd: FakeInterstitialAd()
        )

        async let preparation: Void = harness.service.prepareForAppLaunch()
        await Task.yield()

        XCTAssertEqual(consentManager.requestConsentInfoUpdateCount, 1)
        XCTAssertEqual(harness.mobileAdsStarter.startCount, 1)
        XCTAssertEqual(harness.loader.loadCount, 1)

        consentManager.finishConsentInfoUpdate()
        await preparation

        XCTAssertEqual(consentManager.loadAndPresentConsentFormCount, 1)
    }
}

@MainActor
private func waitForAdPresentation(
    _ ad: FakeInterstitialAd,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    for _ in 0..<100 {
        if ad.presentCount > 0 { return }
        await Task.yield()
    }
    XCTFail("Expected the fake ad to begin presentation.", file: file, line: line)
}

@MainActor
private final class AdServiceHarness {
    let clock: FakePDFExportAdClock
    let cooldownStore: InMemoryPDFExportAdCooldownStore
    let consentManager: FakePDFExportConsentManager
    let mobileAdsStarter = FakePDFExportMobileAdsStarter()
    let loader: FakePDFExportInterstitialAdLoader
    let retryScheduler = FakePDFExportAdRetryScheduler()
    let service: PDFExportAdService
    let preloadedAd: FakeInterstitialAd

    init(
        now: Date = Date(timeIntervalSince1970: 10_000),
        canRequestAds: Bool = true,
        consentManager: FakePDFExportConsentManager? = nil,
        preloadedAd: FakeInterstitialAd?,
        loaderResults: [Result<FakeInterstitialAd, Error>] = []
    ) {
        self.clock = FakePDFExportAdClock(now: now)
        self.cooldownStore = InMemoryPDFExportAdCooldownStore()
        let resolvedConsentManager = consentManager ?? FakePDFExportConsentManager(canRequestAds: canRequestAds)
        self.consentManager = resolvedConsentManager
        self.loader = FakePDFExportInterstitialAdLoader(nextAd: preloadedAd, queuedResults: loaderResults)
        self.preloadedAd = preloadedAd ?? FakeInterstitialAd()
        self.service = PDFExportAdService(
            configurationProvider: {
                PDFExportAdConfiguration(
                    isEnabled: true,
                    applicationID: "ca-app-pub-1234567890123456~1234567890",
                    interstitialAdUnitID: "ca-app-pub-1234567890123456/1234567890",
                    isTestMode: false,
                    disableReason: nil
                )
            },
            consentManager: resolvedConsentManager,
            mobileAdsStarter: mobileAdsStarter,
            adLoader: loader,
            cooldownStore: cooldownStore,
            clock: clock,
            retryScheduler: retryScheduler
        )

        service.updateEntitlementState(.free)
    }

    convenience init(
        now: Date = Date(timeIntervalSince1970: 10_000),
        canRequestAds: Bool = true,
        consentManager: FakePDFExportConsentManager? = nil,
        loaderResults: [Result<FakeInterstitialAd, Error>]
    ) {
        self.init(
            now: now,
            canRequestAds: canRequestAds,
            consentManager: consentManager,
            preloadedAd: nil,
            loaderResults: loaderResults
        )
    }
}

private final class FakePDFExportAdClock: PDFExportAdClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

@MainActor
private class FakePDFExportConsentManager: PDFExportConsentManaging {
    var canRequestAds: Bool
    fileprivate(set) var requestConsentInfoUpdateCount = 0
    fileprivate(set) var loadAndPresentConsentFormCount = 0

    init(canRequestAds: Bool) {
        self.canRequestAds = canRequestAds
    }

    func requestConsentInfoUpdate(completion: @MainActor @escaping () -> Void) {
        requestConsentInfoUpdateCount += 1
        completion()
    }

    func loadAndPresentConsentFormIfRequired() async {
        loadAndPresentConsentFormCount += 1
    }
}

@MainActor
private final class SuspendedPDFExportConsentManager: FakePDFExportConsentManager {
    private var completion: (@MainActor () -> Void)?

    override func requestConsentInfoUpdate(completion: @MainActor @escaping () -> Void) {
        requestConsentInfoUpdateCount += 1
        self.completion = completion
    }

    func finishConsentInfoUpdate() {
        completion?()
        completion = nil
    }
}

@MainActor
private final class FakePDFExportMobileAdsStarter: PDFExportMobileAdsStarting {
    private(set) var startCount = 0

    func start() async {
        startCount += 1
    }
}

@MainActor
private final class FakePDFExportAdRetryScheduler: PDFExportAdRetryScheduling {
    private var retryOperations: [@MainActor () async -> Void] = []
    private(set) var scheduledDelays: [TimeInterval] = []

    var scheduledRetryCount: Int {
        retryOperations.count
    }

    func scheduleRetry(after delay: TimeInterval, operation: @MainActor @escaping () async -> Void) {
        scheduledDelays.append(delay)
        retryOperations.append(operation)
    }

    func runNextRetry() async {
        guard !retryOperations.isEmpty else { return }
        let operation = retryOperations.removeFirst()
        await operation()
    }
}

@MainActor
private final class FakePDFExportInterstitialAdLoader: PDFExportInterstitialAdLoading {
    private let nextAd: FakeInterstitialAd?
    private var queuedResults: [Result<FakeInterstitialAd, Error>]
    private(set) var loadCount = 0

    init(nextAd: FakeInterstitialAd?, queuedResults: [Result<FakeInterstitialAd, Error>] = []) {
        self.nextAd = nextAd
        self.queuedResults = queuedResults
    }

    func loadInterstitialAd(adUnitID: String) async throws -> PDFExportInterstitialAd {
        loadCount += 1
        if !queuedResults.isEmpty {
            switch queuedResults.removeFirst() {
            case .success(let ad):
                return ad
            case .failure(let error):
                throw error
            }
        }

        guard let nextAd else {
            throw FakeAdError.noAd
        }
        return nextAd
    }
}

@MainActor
private final class FakeInterstitialAd: PDFExportInterstitialAd {
    weak var delegate: PDFExportInterstitialAdDelegate?
    private let canPresentError: Error?
    private let presentationBehavior: PresentationBehavior
    private(set) var canPresentCount = 0
    private(set) var presentCount = 0

    init(
        canPresentError: Error? = nil,
        presentationBehavior: PresentationBehavior = .willPresentThenDismiss
    ) {
        self.canPresentError = canPresentError
        self.presentationBehavior = presentationBehavior
    }

    func canPresent() throws {
        canPresentCount += 1
        if let canPresentError {
            throw canPresentError
        }
    }

    func present() {
        presentCount += 1
        switch presentationBehavior {
        case .willPresentThenDismiss:
            delegate?.interstitialAdWillPresent()
            delegate?.interstitialAdDidDismiss()
        case .failToPresent:
            delegate?.interstitialAdDidFailToPresent(error: FakeAdError.presentFailed)
        case .manual:
            break
        }
    }

    func triggerWillPresent() {
        delegate?.interstitialAdWillPresent()
    }

    func triggerDidDismiss() {
        delegate?.interstitialAdDidDismiss()
    }

    func triggerDidFailToPresent() {
        delegate?.interstitialAdDidFailToPresent(error: FakeAdError.presentFailed)
    }

    enum PresentationBehavior {
        case willPresentThenDismiss
        case failToPresent
        case manual
    }
}

private enum FakeAdError: Error {
    case cannotPresent
    case noAd
    case presentFailed
}
