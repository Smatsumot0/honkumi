@testable import Honkumi
import PDFKit
import XCTest

final class CommonSettingsReviewPresentationTests: XCTestCase {
    func testNewPresentationSelectsEveryGroup() {
        let request = UserDefaultSettingsReviewRequest(
            workID: UUID(),
            revision: 4
        )

        let presentation = CommonSettingsReviewPresentation(
            request: request
        )

        XCTAssertEqual(presentation.selection, .all)
        XCTAssertTrue(presentation.canApply)
    }

    func testApplyIsDisabledWhenEveryGroupIsOff() {
        var presentation = CommonSettingsReviewPresentation(
            request: UserDefaultSettingsReviewRequest(
                workID: UUID(),
                revision: 4
            )
        )

        presentation.selection = UserDefaultSettingsSelection()

        XCTAssertFalse(presentation.canApply)
    }
}
