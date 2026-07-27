import CoreGraphics
import Foundation
@testable import Honkumi
import XCTest

final class ManuscriptTextEditorNavigationTests: XCTestCase {
    func testBottomSelectionUsesUTF16Length() {
        XCTAssertEqual(
            ManuscriptTextEditorNavigation.bottomSelectionRange(for: "本文😀"),
            NSRange(location: 4, length: 0)
        )
    }

    func testEmptyTextBottomSelectionIsZero() {
        XCTAssertEqual(
            ManuscriptTextEditorNavigation.bottomSelectionRange(for: ""),
            NSRange(location: 0, length: 0)
        )
    }

    func testMaximumOffsetIncludesBottomInset() {
        XCTAssertEqual(
            ManuscriptTextEditorNavigation.maximumContentOffsetY(
                contentHeight: 1_200,
                viewportHeight: 600,
                adjustedInsetTop: 10,
                adjustedInsetBottom: 96
            ),
            696,
            accuracy: 0.001
        )
    }

    func testMaximumOffsetDoesNotScrollShortContentBelowTop() {
        XCTAssertEqual(
            ManuscriptTextEditorNavigation.maximumContentOffsetY(
                contentHeight: 300,
                viewportHeight: 600,
                adjustedInsetTop: 10,
                adjustedInsetBottom: 96
            ),
            -10,
            accuracy: 0.001
        )
    }
}
