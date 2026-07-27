import Foundation

nonisolated struct TableOfContentsPageNumberSourcePage: Equatable {
    var kind: PDFPageNumberContentKind
    var chapterTitlesStartingOnPage: [String]

    init(
        kind: PDFPageNumberContentKind,
        chapterTitlesStartingOnPage: [String] = []
    ) {
        self.kind = kind
        self.chapterTitlesStartingOnPage = chapterTitlesStartingOnPage
    }
}

nonisolated struct TableOfContentsPageNumberEntry: Equatable {
    var title: String
    var pageNumber: Int
}

nonisolated enum TableOfContentsPageNumberPolicy {
    static func entries(
        for pages: [TableOfContentsPageNumberSourcePage],
        settings: EditorSettings
    ) -> [TableOfContentsPageNumberEntry] {
        let physicalPageNumbers = PDFPageNumberPolicy.physicalPageNumbers(
            forPageCount: pages.count,
            settings: settings
        )

        return zip(pages, physicalPageNumbers).flatMap { page, pageNumber in
            guard page.kind == .body else { return [TableOfContentsPageNumberEntry]() }
            return page.chapterTitlesStartingOnPage.map { title in
                TableOfContentsPageNumberEntry(title: title, pageNumber: pageNumber)
            }
        }
    }
}
