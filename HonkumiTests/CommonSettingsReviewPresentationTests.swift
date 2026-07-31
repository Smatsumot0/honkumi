@testable import Honkumi
import PDFKit
import SwiftUI
import UIKit
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

    func testPendingReviewBlocksAndHidesBackgroundAndMakesDialogModal() {
        let state = CommonSettingsReviewModalState(isPresented: true)

        XCTAssertTrue(state.blocksBackgroundInteraction)
        XCTAssertTrue(state.hidesBackgroundFromAccessibility)
        XCTAssertTrue(state.dialogIsAccessibilityModal)
    }

    func testDismissedReviewRestoresBackgroundInteractionAndAccessibility() {
        let state = CommonSettingsReviewModalState(isPresented: false)

        XCTAssertFalse(state.blocksBackgroundInteraction)
        XCTAssertFalse(state.hidesBackgroundFromAccessibility)
        XCTAssertFalse(state.dialogIsAccessibilityModal)
    }

    func testCompactHeightConstrainsCardAndRequiresScrolling() {
        let layout = CommonSettingsReviewLayout(
            availableHeight: 280,
            outerVerticalPadding: 24
        )

        XCTAssertEqual(layout.maximumCardHeight, 232, accuracy: 0.001)
        XCTAssertEqual(
            layout.cardPresentation(forContentHeight: 500),
            CommonSettingsReviewCardPresentation(
                height: 232,
                minY: 24,
                requiresScrolling: true
            )
        )
    }

    func testFittingContentKeepsIntrinsicHeightAndCentersCard() {
        let layout = CommonSettingsReviewLayout(
            availableHeight: 700,
            outerVerticalPadding: 24
        )

        XCTAssertEqual(
            layout.cardPresentation(forContentHeight: 420),
            CommonSettingsReviewCardPresentation(
                height: 420,
                minY: 140,
                requiresScrolling: false
            )
        )
    }

    @MainActor
    func testTallContainerKeepsDialogAtIntrinsicHeight() {
        let maximumHeight: CGFloat = 652
        let controller = UIHostingController(
            rootView: CommonSettingsReviewDialog(
                selection: .constant(.all),
                maximumHeight: maximumHeight,
                onApply: {},
                onKeepCurrent: {},
                onCancel: {}
            )
        )

        let measuredSize = controller.sizeThatFits(
            in: CGSize(width: 390, height: 700)
        )

        XCTAssertGreaterThan(measuredSize.height, 300)
        XCTAssertLessThan(measuredSize.height, maximumHeight - 100)
    }

    @MainActor
    func testCompactContainerKeepsDialogWithinMaximumHeight() {
        let maximumHeight: CGFloat = 232
        let controller = UIHostingController(
            rootView: CommonSettingsReviewDialog(
                selection: .constant(.all),
                maximumHeight: maximumHeight,
                onApply: {},
                onKeepCurrent: {},
                onCancel: {}
            )
        )

        let measuredSize = controller.sizeThatFits(
            in: CGSize(width: 390, height: 280)
        )

        XCTAssertGreaterThan(measuredSize.height, 0)
        XCTAssertLessThanOrEqual(
            measuredSize.height,
            maximumHeight + 0.5
        )
    }
}
