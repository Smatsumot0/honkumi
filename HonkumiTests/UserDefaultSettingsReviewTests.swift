@testable import Honkumi
import XCTest

@MainActor
final class UserDefaultSettingsReviewTests: XCTestCase {
    func testLegacyZeroRevisionDoesNotRequestImmediateReview() {
        let store = makeStore(commonRevision: 0, reviewedRevision: 0)

        XCTAssertNil(
            store.userDefaultSettingsReviewRequest(for: store.document.id)
        )
    }

    func testOlderWorkRequestsReviewAfterCommonRevisionAdvances() {
        let store = makeStore(commonRevision: 2, reviewedRevision: 1)

        XCTAssertEqual(
            store.userDefaultSettingsReviewRequest(for: store.document.id),
            UserDefaultSettingsReviewRequest(
                workID: store.document.id,
                revision: 2
            )
        )
    }

    func testApplyCopiesEverySettingsGroupAndRequestsFormatting() throws {
        let store = makeStore(commonRevision: 3, reviewedRevision: 1)
        var defaults = store.userDefaultSettings
        defaults.editorFontSize = 18
        defaults.pageSize = .b6
        defaults.marginInner = 24
        defaults.formatSettings.enableAutoFormat = true
        defaults.formatSettings.enableNormalizePunctuation = true
        defaults.colophon.authorName = "共通作者"
        store.updateUserDefaultSettings(defaults)
        let request = try XCTUnwrap(
            store.userDefaultSettingsReviewRequest(for: store.document.id)
        )

        let result = store.resolveUserDefaultSettingsReview(
            request,
            decision: .apply
        )

        XCTAssertTrue(result.didSelect)
        XCTAssertTrue(result.shouldFormat)
        XCTAssertEqual(store.document.settings, defaults.validated)
        XCTAssertEqual(
            store.document.reviewedUserDefaultSettingsRevision,
            3
        )
    }

    func testKeepCurrentPreservesSettingsAndBodyButReviewsRevision() throws {
        let store = makeStore(commonRevision: 3, reviewedRevision: 1)
        let original = store.document
        let request = try XCTUnwrap(
            store.userDefaultSettingsReviewRequest(for: original.id)
        )

        let result = store.resolveUserDefaultSettingsReview(
            request,
            decision: .keepCurrent
        )

        XCTAssertTrue(result.didSelect)
        XCTAssertFalse(result.shouldFormat)
        XCTAssertEqual(store.document.settings, original.settings)
        XCTAssertEqual(store.document.body, original.body)
        XCTAssertEqual(store.document.updatedAt, original.updatedAt)
        XCTAssertEqual(
            store.document.reviewedUserDefaultSettingsRevision,
            3
        )
    }

    func testStaleRequestChangesNothing() {
        let store = makeStore(commonRevision: 3, reviewedRevision: 1)
        let request = UserDefaultSettingsReviewRequest(
            workID: store.document.id,
            revision: 2
        )
        let before = store.appData

        let result = store.resolveUserDefaultSettingsReview(
            request,
            decision: .apply
        )

        XCTAssertFalse(result.didSelect)
        XCTAssertFalse(result.shouldFormat)
        XCTAssertEqual(store.appData, before)
    }

    func testAlreadyReviewedWorkCanBeSelectedWithoutARequest() {
        let first = ManuscriptDocument(
            title: "First",
            body: "本文",
            reviewedUserDefaultSettingsRevision: 2
        )
        let second = ManuscriptDocument(
            title: "Second",
            body: "本文",
            reviewedUserDefaultSettingsRevision: 2
        )
        let store = DocumentStore(
            appData: AppData(
                version: AppData.currentVersion,
                categories: [.uncategorized],
                works: [first, second],
                userDefaultSettings: .default,
                activeWorkId: first.id,
                subscriptionStatus: .free,
                userDefaultSettingsRevision: 2
            )
        )

        XCTAssertNil(
            store.userDefaultSettingsReviewRequest(for: second.id)
        )
        store.selectWork(id: second.id)
        XCTAssertEqual(store.document.id, second.id)
    }

    private func makeStore(
        commonRevision: Int,
        reviewedRevision: Int
    ) -> DocumentStore {
        var work = ManuscriptDocument(
            title: "作品",
            body: "A,B.",
            reviewedUserDefaultSettingsRevision: reviewedRevision
        )
        work.settings.editorFontSize = 11
        return DocumentStore(
            appData: AppData(
                version: AppData.currentVersion,
                categories: [.uncategorized],
                works: [work],
                userDefaultSettings: .default,
                activeWorkId: work.id,
                subscriptionStatus: .paid,
                userDefaultSettingsRevision: commonRevision
            )
        )
    }
}
