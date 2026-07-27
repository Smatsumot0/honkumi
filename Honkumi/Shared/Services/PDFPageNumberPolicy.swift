import Foundation

nonisolated enum PDFPageNumberContentKind: Equatable {
    case body
    case tableOfContents
    case colophon
}

nonisolated enum PDFPageNumberPolicy {
    static func physicalPageNumbers(
        forPageCount pageCount: Int,
        settings: EditorSettings
    ) -> [Int] {
        guard pageCount > 0 else { return [] }
        return (0..<pageCount).map { settings.pageNumberStart + $0 }
    }

    static func displayedPageNumbers(
        for pageKinds: [PDFPageNumberContentKind],
        settings: EditorSettings
    ) -> [Int?] {
        let physicalPageNumbers = physicalPageNumbers(
            forPageCount: pageKinds.count,
            settings: settings
        )

        return zip(pageKinds, physicalPageNumbers).map { pageKind, pageNumber in
            displayedPageNumber(
                pageNumber,
                for: pageKind,
                settings: settings
            )
        }
    }

    static func displayedPageNumber(
        _ pageNumber: Int,
        for pageKind: PDFPageNumberContentKind,
        settings: EditorSettings
    ) -> Int? {
        guard settings.isPageNumberEnabled,
              settings.pageNumberPosition != .hidden,
              shouldShowPageNumber(on: pageKind, settings: settings) else {
            return nil
        }

        return pageNumber
    }

    static func shouldShowPageNumber(
        on pageKind: PDFPageNumberContentKind,
        settings: EditorSettings
    ) -> Bool {
        switch pageKind {
        case .body:
            true
        case .tableOfContents:
            settings.showPageNumberOnToc
        case .colophon:
            settings.showPageNumberOnColophon
        }
    }
}
