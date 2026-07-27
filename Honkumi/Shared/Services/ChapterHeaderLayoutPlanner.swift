import Foundation
import UIKit

nonisolated enum ChapterHeaderSplitResult: Equatable {
    case single(String)
    case spread(first: String, second: String)
    case overflow
}

nonisolated enum ChapterHeaderHorizontalAlignment: Equatable {
    case leading
    case trailing
}

nonisolated struct ChapterHeaderFragment: Equatable {
    let pageID: UUID
    let text: String
    let alignment: ChapterHeaderHorizontalAlignment
}

nonisolated enum ChapterHeaderLayoutIssueKind: Equatable {
    case spread
    case overflow
}

nonisolated struct ChapterHeaderLayoutIssue: Equatable {
    let chapterIndex: Int
    let kind: ChapterHeaderLayoutIssueKind
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

    static func split(
        title: String,
        firstAvailableWidth: CGFloat,
        secondAvailableWidth: CGFloat?,
        font: UIFont,
        measureWidth: MeasureWidth = defaultMeasureWidth
    ) -> ChapterHeaderSplitResult {
        if measureWidth(title, font) <= firstAvailableWidth {
            return .single(title)
        }

        guard let secondAvailableWidth else {
            return .overflow
        }

        for splitIndex in title.indices.reversed() where splitIndex != title.startIndex {
            let first = String(title[..<splitIndex])
            guard measureWidth(first, font) <= firstAvailableWidth else {
                continue
            }

            let second = String(title[splitIndex...])
            if measureWidth(second, font) <= secondAvailableWidth {
                return .spread(first: first, second: second)
            }
        }

        return .overflow
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
        let candidatesByPageNumber = Dictionary(
            uniqueKeysWithValues: candidates.map { ($0.physicalPageNumber, $0) }
        )
        let spreadLeftPageNumbers = Set(candidates.map {
            spreadLeftPageNumber(containing: $0.physicalPageNumber)
        }).sorted()

        var fragments: [UUID: ChapterHeaderFragment] = [:]
        var issuesByChapter: [Int: ChapterHeaderLayoutIssue] = [:]

        for leftPageNumber in spreadLeftPageNumbers {
            let left = candidatesByPageNumber[leftPageNumber]
            let right = candidatesByPageNumber[leftPageNumber - 1]
            let pageNumbers = [left, right].compactMap(\.?.physicalPageNumber)

            if let left,
               let right,
               let leftTitle = left.title,
               leftTitle == right.title,
               let chapterIndex = left.chapterIndex,
               chapterIndex == right.chapterIndex {
                let font = font(for: left.layout, subscriptionStatus: subscriptionStatus)
                switch split(
                    title: leftTitle,
                    firstAvailableWidth: left.layout.bodyFrame.width,
                    secondAvailableWidth: right.layout.bodyFrame.width,
                    font: font,
                    measureWidth: measureWidth
                ) {
                case .single:
                    fragments[left.page.id] = singleFragment(for: left, title: leftTitle)
                    fragments[right.page.id] = singleFragment(for: right, title: leftTitle)
                case let .spread(first, second):
                    fragments[left.page.id] = ChapterHeaderFragment(
                        pageID: left.page.id,
                        text: first,
                        alignment: .trailing
                    )
                    fragments[right.page.id] = ChapterHeaderFragment(
                        pageID: right.page.id,
                        text: second,
                        alignment: .leading
                    )
                    record(
                        ChapterHeaderLayoutIssue(
                            chapterIndex: chapterIndex,
                            kind: .spread,
                            title: leftTitle,
                            pageNumbers: pageNumbers
                        ),
                        in: &issuesByChapter
                    )
                case .overflow:
                    record(
                        ChapterHeaderLayoutIssue(
                            chapterIndex: chapterIndex,
                            kind: .overflow,
                            title: leftTitle,
                            pageNumbers: pageNumbers
                        ),
                        in: &issuesByChapter
                    )
                }
                continue
            }

            for candidate in [left, right].compactMap({ $0 }) {
                guard let title = candidate.title,
                      let chapterIndex = candidate.chapterIndex else {
                    continue
                }
                let font = font(for: candidate.layout, subscriptionStatus: subscriptionStatus)
                if measureWidth(title, font) <= candidate.layout.bodyFrame.width {
                    fragments[candidate.page.id] = singleFragment(for: candidate, title: title)
                } else {
                    record(
                        ChapterHeaderLayoutIssue(
                            chapterIndex: chapterIndex,
                            kind: .overflow,
                            title: title,
                            pageNumbers: pageNumbers
                        ),
                        in: &issuesByChapter
                    )
                }
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

    private static func record(
        _ issue: ChapterHeaderLayoutIssue,
        in issuesByChapter: inout [Int: ChapterHeaderLayoutIssue]
    ) {
        guard let existing = issuesByChapter[issue.chapterIndex] else {
            issuesByChapter[issue.chapterIndex] = issue
            return
        }
        guard existing.kind != .overflow, issue.kind == .overflow else {
            return
        }
        issuesByChapter[issue.chapterIndex] = issue
    }

    private static func spreadLeftPageNumber(containing physicalPageNumber: Int) -> Int {
        physicalPageNumber.isMultiple(of: 2)
            ? physicalPageNumber + 1
            : physicalPageNumber
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
