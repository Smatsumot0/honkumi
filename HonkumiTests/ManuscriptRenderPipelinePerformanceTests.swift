import XCTest
@testable import Honkumi

final class ManuscriptRenderPipelinePerformanceTests: XCTestCase {
    func testRecommendedSettingsDoNotRunExtraFullPaginationBeforeFinalResult() {
        var settings = EditorSettings.default
        settings.pageSize = .a6
        settings.useRecommendedTypography = true
        settings.useRecommendedMargins = true
        settings.showTableOfContents = true
        settings.startsChapterOnNewPage = true

        let body = (1...12)
            .map { chapter in
                "# 第\(chapter)章\n" + String(repeating: "これはプレビュー生成速度を確認するための本文です。\n", count: 24)
            }
            .joined(separator: "\n\n")
        let document = ManuscriptDocument(
            title: "Preview Performance",
            body: body,
            settings: settings
        )

        ManuscriptPaginatorInstrumentation.reset()
        _ = ManuscriptRenderPipeline.paginationResult(
            for: document,
            subscriptionStatus: .free
        )

        XCTAssertEqual(ManuscriptPaginatorInstrumentation.pagesCallCount, 1)
    }
}
