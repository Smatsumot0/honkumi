import UIKit
@testable import Honkumi
import XCTest

final class ChapterHeaderLayoutPlannerTests: XCTestCase {
    private let measure: (String, UIFont) -> CGFloat = { text, _ in
        CGFloat(text.count)
    }

    func testSinglePageTitleCreatesOneCompleteFragmentWithoutIssue() {
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

    func testSameChapterTitleCreatesCompleteFragmentOnEachEligiblePage() {
        var settings = chapterSettings
        settings.pageNumberStart = 2
        let pages = [
            bodyPage(title: "短い章題"),
            bodyPage(title: "短い章題")
        ]

        let plan = ChapterHeaderLayoutPlanner.makePlan(
            pages: pages,
            settings: settings,
            subscriptionStatus: .free,
            measureWidth: measure
        )

        XCTAssertEqual(plan.fragmentsByPageID[pages[0].id]?.text, "短い章題")
        XCTAssertEqual(plan.fragmentsByPageID[pages[1].id]?.text, "短い章題")
        XCTAssertEqual(plan.fragmentsByPageID[pages[0].id]?.alignment, .trailing)
        XCTAssertEqual(plan.fragmentsByPageID[pages[1].id]?.alignment, .leading)
        XCTAssertTrue(plan.issues.isEmpty)
    }

    func testTitleExceedingOnePageCreatesOneChapterIssueWithoutFragments() {
        var settings = chapterSettings
        settings.pageNumberStart = 2
        let width = LayoutCalculator.layout(for: settings, pageNumber: 2).bodyFrame.width
        let title = String(repeating: "A", count: Int(width) + 1)
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
        XCTAssertEqual(plan.issues, [
            ChapterHeaderLayoutIssue(
                chapterIndex: 0,
                title: title,
                pageNumbers: [2, 3]
            )
        ])
    }

    func testOverflowAcrossManyEligiblePagesAccumulatesPageNumbersOnce() {
        let title = String(repeating: "A", count: Int(pageBodyWidth) + 1)
        let pages = [
            bodyPage(title: title),
            bodyPage(title: title),
            bodyPage(title: title)
        ]

        let plan = ChapterHeaderLayoutPlanner.makePlan(
            pages: pages,
            settings: chapterSettings,
            subscriptionStatus: .free,
            measureWidth: measure
        )

        XCTAssertEqual(plan.issues, [
            ChapterHeaderLayoutIssue(
                chapterIndex: 0,
                title: title,
                pageNumbers: [1, 2, 3]
            )
        ])
    }

    func testSameLongTitleInSeparateChapterOccurrencesKeepsTwoIssues() {
        let title = String(repeating: "A", count: Int(pageBodyWidth) + 1)
        let pages = [
            bodyPage(title: title, startsTitle: true),
            bodyPage(title: title),
            bodyPage(title: title, startsTitle: true),
            bodyPage(title: title)
        ]

        let plan = ChapterHeaderLayoutPlanner.makePlan(
            pages: pages,
            settings: chapterSettings,
            subscriptionStatus: .free,
            measureWidth: measure
        )

        XCTAssertEqual(plan.issues.map(\.chapterIndex), [0, 1])
        XCTAssertEqual(plan.issues.map(\.pageNumbers), [[2], [4]])
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
