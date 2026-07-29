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

    private func makeStore() -> DocumentStore {
        DocumentStore(appData: .initial)
    }
}
