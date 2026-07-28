import Foundation
import UIKit

nonisolated enum ChapterHeaderHorizontalAlignment: Equatable {
    case leading
    case trailing
}

nonisolated struct ChapterHeaderFragment: Equatable {
    let pageID: UUID
    let text: String
    let alignment: ChapterHeaderHorizontalAlignment
}

nonisolated struct ChapterHeaderLayoutIssue: Equatable {
    let chapterIndex: Int
    let title: String
    let pageNumbers: [Int]
}

nonisolated struct ChapterHeaderLayoutPlan: Equatable {
    let fragmentsByPageID: [UUID: ChapterHeaderFragment]
    let issues: [ChapterHeaderLayoutIssue]
}

nonisolated enum ChapterHeaderLayoutPlanner {
    typealias MeasureWidth = (String, UIFont) -> CGFloat

    private struct PageCandidate {
        let page: PreviewPage
        let physicalPageNumber: Int
        let layout: PageLayout
        let title: String?
        let chapterIndex: Int?
    }

    static func makePlan(
        pages: [PreviewPage],
        settings: EditorSettings,
        subscriptionStatus: SubscriptionStatus,
        measureWidth: MeasureWidth = defaultMeasureWidth
    ) -> ChapterHeaderLayoutPlan {
        guard settings.showChapterTitle, !pages.isEmpty else {
            return ChapterHeaderLayoutPlan(fragmentsByPageID: [:], issues: [])
        }

        let physicalPageNumbers = PDFPageNumberPolicy.physicalPageNumbers(
            forPageCount: pages.count,
            settings: settings
        )
        var nextChapterIndex = 0
        var activeChapterIndex: Int?
        var activeChapterTitle: String?
        let candidates = zip(pages, physicalPageNumbers).map { page, pageNumber in
            if !page.chapterTitlesStartingOnPage.isEmpty {
                for title in page.chapterTitlesStartingOnPage {
                    activeChapterIndex = nextChapterIndex
                    activeChapterTitle = normalizedTitle(title)
                    nextChapterIndex += 1
                }
            } else if page.kind == .body,
                      let pageChapterTitle = page.chapterTitle.flatMap(normalizedTitle),
                      activeChapterIndex == nil || activeChapterTitle != pageChapterTitle {
                activeChapterIndex = nextChapterIndex
                activeChapterTitle = pageChapterTitle
                nextChapterIndex += 1
            }

            let layout = LayoutCalculator.layout(for: settings, pageNumber: pageNumber)
            let title = eligibleTitle(on: page, settings: settings)
            return PageCandidate(
                page: page,
                physicalPageNumber: pageNumber,
                layout: layout,
                title: title,
                chapterIndex: title == nil ? nil : activeChapterIndex
            )
        }

        var fragments: [UUID: ChapterHeaderFragment] = [:]
        var issuesByChapter: [Int: ChapterHeaderLayoutIssue] = [:]

        for candidate in candidates {
            guard let title = candidate.title,
                  let chapterIndex = candidate.chapterIndex else {
                continue
            }

            let font = font(for: candidate.layout, subscriptionStatus: subscriptionStatus)
            if measureWidth(title, font) <= candidate.layout.bodyFrame.width {
                fragments[candidate.page.id] = singleFragment(for: candidate, title: title)
            } else {
                recordOverflow(
                    chapterIndex: chapterIndex,
                    title: title,
                    pageNumber: candidate.physicalPageNumber,
                    in: &issuesByChapter
                )
            }
        }

        return ChapterHeaderLayoutPlan(
            fragmentsByPageID: fragments,
            issues: issuesByChapter.values.sorted {
                $0.chapterIndex < $1.chapterIndex
            }
        )
    }

    static func font(
        for layout: PageLayout,
        subscriptionStatus: SubscriptionStatus
    ) -> UIFont {
        AppFontCatalog.uiFont(
            selectedFontId: layout.settings.selectedFontId,
            size: max(layout.fontSize * 0.8, 6),
            isAdditionalFontPackUnlocked: subscriptionStatus == .paid
        )
    }

    private static func eligibleTitle(
        on page: PreviewPage,
        settings: EditorSettings
    ) -> String? {
        guard settings.showChapterTitle,
              page.kind == .body,
              let title = page.chapterTitle,
              !title.isEmpty,
              !page.chapterTitlesStartingOnPage.contains(title) else {
            return nil
        }

        return normalizedTitle(title)
    }

    private static func normalizedTitle(_ title: String) -> String? {
        let normalized = PrintTextNormalizer.normalize(title, location: .title).text
        return normalized.isEmpty ? nil : normalized
    }

    private static func recordOverflow(
        chapterIndex: Int,
        title: String,
        pageNumber: Int,
        in issuesByChapter: inout [Int: ChapterHeaderLayoutIssue]
    ) {
        let existingPages = issuesByChapter[chapterIndex]?.pageNumbers ?? []
        let pageNumbers = existingPages.contains(pageNumber)
            ? existingPages
            : existingPages + [pageNumber]
        issuesByChapter[chapterIndex] = ChapterHeaderLayoutIssue(
            chapterIndex: chapterIndex,
            title: title,
            pageNumbers: pageNumbers
        )
    }

    private static func singleFragment(
        for candidate: PageCandidate,
        title: String
    ) -> ChapterHeaderFragment {
        ChapterHeaderFragment(
            pageID: candidate.page.id,
            text: title,
            alignment: candidate.physicalPageNumber.isMultiple(of: 2) ? .trailing : .leading
        )
    }

    private static func defaultMeasureWidth(_ text: String, font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}
