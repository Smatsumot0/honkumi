import UIKit
@testable import Honkumi
import XCTest

final class ChapterHeaderLayoutPlannerTests: XCTestCase {
    private let measure: (String, UIFont) -> CGFloat = { text, _ in
        CGFloat(text.count)
    }

    func testTitleThatFitsPrimaryPageUsesOneFragment() {
        let result = ChapterHeaderLayoutPlanner.split(
            title: "12345",
            firstAvailableWidth: 5,
            secondAvailableWidth: nil,
            font: .systemFont(ofSize: 10),
            measureWidth: measure
        )

        XCTAssertEqual(result, .single("12345"))
    }

    func testTitleThatNeedsSpreadSplitsOnCharacterBoundary() {
        let result = ChapterHeaderLayoutPlanner.split(
            title: "123456789",
            firstAvailableWidth: 5,
            secondAvailableWidth: 4,
            font: .systemFont(ofSize: 10),
            measureWidth: measure
        )

        XCTAssertEqual(result, .spread(first: "12345", second: "6789"))
    }

    func testTitleThatExceedsSpreadIsOverflow() {
        let result = ChapterHeaderLayoutPlanner.split(
            title: "1234567890",
            firstAvailableWidth: 5,
            secondAvailableWidth: 4,
            font: .systemFont(ofSize: 10),
            measureWidth: measure
        )

        XCTAssertEqual(result, .overflow)
    }

    func testSplitPreservesExtendedGraphemeClusters() {
        let title = "A👨‍👩‍👧‍👦か\u{3099}B"
        let result = ChapterHeaderLayoutPlanner.split(
            title: title,
            firstAvailableWidth: 2,
            secondAvailableWidth: 2,
            font: .systemFont(ofSize: 10),
            measureWidth: measure
        )

        guard case let .spread(first, second) = result else {
            return XCTFail("Expected a spread split")
        }
        XCTAssertEqual(first + second, title)
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(second.count, 2)
    }

    func testEmptyTitleUsesOneEmptyFragment() {
        XCTAssertEqual(
            ChapterHeaderLayoutPlanner.split(
                title: "",
                firstAvailableWidth: 0,
                secondAvailableWidth: nil,
                font: .systemFont(ofSize: 10),
                measureWidth: measure
            ),
            .single("")
        )
    }

    func testSinglePageTitleCreatesOneFragmentWithoutIssue() {
        let pages = [bodyPage(title: "短い章題")]
        let plan = ChapterHeaderLayoutPlanner.makePlan(
            pages: pages,
            settings: chapterSettings,
            subscriptionStatus: .free,
            measureWidth: measure
        )

        XCTAssertEqual(plan.fragmentsByPageID[pages[0].id]?.text, "短い章題")
        XCTAssertEqual(plan.fragmentsByPageID[pages[0].id]?.alignment, .leading)
        XCTAssertTrue(plan.issues.isEmpty)
    }

    func testLongTitleUsesOddLeftAndEvenRightPagesOfSameSpread() {
        var settings = chapterSettings
        settings.pageNumberStart = 2
        let width = LayoutCalculator.layout(for: settings, pageNumber: 2).bodyFrame.width
        let title = String(repeating: "A", count: Int(width) + 10)
        let pages = [
            bodyPage(title: title),
            bodyPage(title: title)
        ]

        let plan = ChapterHeaderLayoutPlanner.makePlan(
            pages: pages,
            settings: settings,
            subscriptionStatus: .free,
            measureWidth: measure
        )

        let left = plan.fragmentsByPageID[pages[1].id]
        let right = plan.fragmentsByPageID[pages[0].id]
        XCTAssertEqual((left?.text ?? "") + (right?.text ?? ""), title)
        XCTAssertEqual(left?.alignment, .trailing)
        XCTAssertEqual(right?.alignment, .leading)
        XCTAssertEqual(plan.issues, [.spread(title: title, pageNumbers: [3, 2])])
    }

    func testTitleThatExceedsBothPagesCreatesOverflowWithoutFragments() {
        var settings = chapterSettings
        settings.pageNumberStart = 2
        let width = LayoutCalculator.layout(for: settings, pageNumber: 2).bodyFrame.width
        let title = String(repeating: "A", count: Int(width * 2) + 2)
        let pages = [
            bodyPage(title: title),
            bodyPage(title: title)
        ]

        let plan = ChapterHeaderLayoutPlanner.makePlan(
            pages: pages,
            settings: settings,
            subscriptionStatus: .free,
            measureWidth: measure
        )

        XCTAssertTrue(plan.fragmentsByPageID.isEmpty)
        XCTAssertEqual(plan.issues, [.overflow(title: title, pageNumbers: [3, 2])])
    }

    func testMissingCompanionPageCreatesOverflow() {
        let title = String(repeating: "A", count: Int(pageBodyWidth) + 1)
        let pages = [bodyPage(title: title)]

        let plan = ChapterHeaderLayoutPlanner.makePlan(
            pages: pages,
            settings: chapterSettings,
            subscriptionStatus: .free,
            measureWidth: measure
        )

        XCTAssertTrue(plan.fragmentsByPageID.isEmpty)
        XCTAssertEqual(plan.issues, [.overflow(title: title, pageNumbers: [1])])
    }

    func testChapterStartingOnCompanionPageCannotContinuePreviousTitle() {
        var settings = chapterSettings
        settings.pageNumberStart = 2
        let width = LayoutCalculator.layout(for: settings, pageNumber: 2).bodyFrame.width
        let title = String(repeating: "A", count: Int(width) + 1)
        let pages = [
            bodyPage(title: title),
            bodyPage(title: title, startsTitle: true)
        ]

        let plan = ChapterHeaderLayoutPlanner.makePlan(
            pages: pages,
            settings: settings,
            subscriptionStatus: .free,
            measureWidth: measure
        )

        XCTAssertTrue(plan.fragmentsByPageID.isEmpty)
        XCTAssertEqual(plan.issues, [.overflow(title: title, pageNumbers: [3, 2])])
    }

    private var chapterSettings: EditorSettings {
        var settings = EditorSettings.default
        settings.showChapterTitle = true
        settings.useRecommendedTypography = false
        settings.useRecommendedMargins = false
        settings.pageNumberStart = 1
        return settings
    }

    private var pageBodyWidth: CGFloat {
        LayoutCalculator.layout(for: chapterSettings, pageNumber: 1).bodyFrame.width
    }

    private func bodyPage(title: String?, startsTitle: Bool = false) -> PreviewPage {
        PreviewPage(
            kind: .body,
            columns: ["本文"],
            startsAfterPageBreak: false,
            chapterTitle: title,
            chapterTitlesStartingOnPage: startsTitle ? [title].compactMap { $0 } : []
        )
    }
}
