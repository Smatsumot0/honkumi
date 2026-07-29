@testable import Honkumi
import XCTest

@MainActor
final class CommonSettingsSessionTests: XCTestCase {
    func testMultipleChangesIncrementRevisionOnceWhenSessionFinishes() {
        let store = makeStore()
        let initial = store.userDefaultSettings
        var first = initial
        first.editorFontSize = 16
        store.updateUserDefaultSettings(first)
        var second = first
        second.marginInner = 22
        store.updateUserDefaultSettings(second)

        XCTAssertEqual(store.userDefaultSettingsRevision, 0)
        XCTAssertTrue(
            store.finishUserDefaultSettingsSession(startingFrom: initial)
        )
        XCTAssertEqual(store.userDefaultSettingsRevision, 1)
    }

    func testUnchangedSessionDoesNotIncrementRevision() {
        let store = makeStore()

        XCTAssertFalse(
            store.finishUserDefaultSettingsSession(
                startingFrom: store.userDefaultSettings
            )
        )
        XCTAssertEqual(store.userDefaultSettingsRevision, 0)
    }

    func testSecondDistinctSessionIncrementsAgain() {
        let store = makeStore()
        let firstStart = store.userDefaultSettings
        var first = firstStart
        first.editorFontSize = 16
        store.updateUserDefaultSettings(first)
        XCTAssertTrue(
            store.finishUserDefaultSettingsSession(startingFrom: firstStart)
        )

        let secondStart = store.userDefaultSettings
        var second = secondStart
        second.colophon.authorName = "作者"
        store.updateUserDefaultSettings(second)
        XCTAssertTrue(
            store.finishUserDefaultSettingsSession(startingFrom: secondStart)
        )

        XCTAssertEqual(store.userDefaultSettingsRevision, 2)
    }

    func testNewWorkUsesExistingInitializationRulesAndCurrentRevision() {
        var data = AppData.initial
        data.userDefaultSettingsRevision = 4
        data.userDefaultSettings.useRecommendedTypography = false
        data.userDefaultSettings.useRecommendedMargins = false
        data.userDefaultSettings.editorFontSize = 17
        let store = DocumentStore(appData: data)

        let work = store.createWork(title: "新作")

        XCTAssertEqual(work.reviewedUserDefaultSettingsRevision, 4)
        XCTAssertEqual(work.settings.editorFontSize, 17)
        XCTAssertTrue(work.settings.useRecommendedTypography)
        XCTAssertTrue(work.settings.useRecommendedMargins)
    }

    func testDeleteLastWorkCreatesReviewedFallback() {
        var data = AppData.initial
        data.userDefaultSettingsRevision = 3
        let store = DocumentStore(appData: data)
        let onlyID = store.document.id

        store.deleteWork(id: onlyID)

        XCTAssertEqual(
            store.document.reviewedUserDefaultSettingsRevision,
            3
        )
    }

    func testInitialSampleRecordsCurrentRevision() {
        var data = AppData.emptyLibrary
        data.userDefaultSettingsRevision = 5

        let result = InitialSampleWork.seedIfNeeded(
            in: data,
            hasCreatedInitialSample: false,
            settings: data.userDefaultSettings
        )

        XCTAssertEqual(
            result.data.works.first?.reviewedUserDefaultSettingsRevision,
            5
        )
    }

    func testPublisherInformationChangeUsesTheSameFullSettingsSessionBoundary() {
        let store = makeStore()
        let initial = store.userDefaultSettings
        var changed = initial
        changed.colophon.authorName = "作者"
        changed.colophon.circleName = "サークル"
        store.updateUserDefaultSettings(changed)

        XCTAssertTrue(
            store.finishUserDefaultSettingsSession(startingFrom: initial)
        )
        XCTAssertEqual(store.userDefaultSettingsRevision, 1)
    }

    private func makeStore() -> DocumentStore {
        DocumentStore(appData: .initial)
    }
}
