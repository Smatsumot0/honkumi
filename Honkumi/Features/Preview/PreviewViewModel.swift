import Combine
import Foundation

struct PreviewPage: Identifiable, Equatable {
    let id = UUID()
    let kind: PreviewPageKind
    let columns: [String]
    let startsAfterPageBreak: Bool
    let chapterTitle: String?
    let chapterTitlesStartingOnPage: [String]

    init(
        kind: PreviewPageKind = .body,
        columns: [String],
        startsAfterPageBreak: Bool,
        chapterTitle: String?,
        chapterTitlesStartingOnPage: [String] = []
    ) {
        self.kind = kind
        self.columns = columns
        self.startsAfterPageBreak = startsAfterPageBreak
        self.chapterTitle = chapterTitle
        self.chapterTitlesStartingOnPage = chapterTitlesStartingOnPage
    }
}

enum PreviewPageKind: Equatable {
    case body
    case colophon(ColophonSettings)
}

struct ColophonEntry: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
    let addsPrecedingSpace: Bool
    let addsFollowingSpace: Bool
    let centersInHorizontalLayout: Bool

    init(
        id: String,
        label: String,
        value: String,
        addsPrecedingSpace: Bool = false,
        addsFollowingSpace: Bool,
        centersInHorizontalLayout: Bool = false
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.addsPrecedingSpace = addsPrecedingSpace
        self.addsFollowingSpace = addsFollowingSpace
        self.centersInHorizontalLayout = centersInHorizontalLayout
    }
}

struct VerticalHorizontalColophonEntry: Identifiable, Equatable {
    let id: String
    let entry: ColophonEntry
    let columnIndex: Int
}

enum ManuscriptPaginator {
    private static let maxTableOfContentsPasses = 6

    static func pages(for document: ManuscriptDocument) -> [PreviewPage] {
        let settings = document.settings.validated
        let parsedSegments = ManuscriptMarkupParser.parse(document.body).segments
        let segments = normalizedSegments(parsedSegments, settings: settings)
        var tableOfContentsEntries = chapterEntries(in: paginate(segments, settings: settings, tableOfContentsEntries: []))

        guard settings.showTableOfContents else {
            return appendingColophonIfNeeded(
                to: paginate(segments, settings: settings, tableOfContentsEntries: []),
                settings: settings,
                workTitle: document.title
            )
        }

        var pages = paginate(segments, settings: settings, tableOfContentsEntries: tableOfContentsEntries)
        for _ in 0..<maxTableOfContentsPasses {
            let updatedEntries = chapterEntries(in: pages)
            if updatedEntries == tableOfContentsEntries {
                return appendingColophonIfNeeded(to: pages, settings: settings, workTitle: document.title)
            }

            tableOfContentsEntries = updatedEntries
            pages = paginate(segments, settings: settings, tableOfContentsEntries: tableOfContentsEntries)
        }

        return appendingColophonIfNeeded(to: pages, settings: settings, workTitle: document.title)
    }

    private static func normalizedSegments(
        _ segments: [ParsedManuscriptSegment],
        settings: EditorSettings
    ) -> [ParsedManuscriptSegment] {
        guard settings.showTableOfContents else {
            return segments.filter { !$0.isTableOfContentsPlaceholder }
        }

        if segments.contains(where: \.isTableOfContentsPlaceholder) {
            return segments
        }

        return [
            ParsedManuscriptSegment(
                text: "",
                chapterTitle: nil,
                startsAfterPageBreak: false,
                isTableOfContentsPlaceholder: true
            )
        ] + segments
    }

    private static func paginate(
        _ segments: [ParsedManuscriptSegment],
        settings: EditorSettings,
        tableOfContentsEntries: [TableOfContentsEntry]
    ) -> [PreviewPage] {
        let maxLines = max(settings.linesPerPage, 1)
        var pages: [PreviewPage] = []
        var currentLines: [String] = []
        var currentChapterTitle: String?
        var currentStartsAfterPageBreak = false
        var currentChapterStarts: [String] = []

        func appendCurrentPage() {
            guard !currentLines.isEmpty || pages.isEmpty else { return }
            pages.append(PreviewPage(
                columns: currentLines.isEmpty ? [""] : currentLines,
                startsAfterPageBreak: currentStartsAfterPageBreak,
                chapterTitle: currentChapterTitle,
                chapterTitlesStartingOnPage: currentChapterStarts
            ))
            currentLines = []
            currentStartsAfterPageBreak = false
            currentChapterStarts = []
        }

        for (segmentIndex, segment) in segments.enumerated() {
            let startsChapterPage = settings.startsChapterOnNewPage
                && segment.startsChapter
                && segmentIndex > 0

            if segment.startsAfterPageBreak || startsChapterPage {
                appendCurrentPage()
                currentStartsAfterPageBreak = true
            }

            if let chapterTitle = segment.chapterTitle {
                currentChapterTitle = chapterTitle
            }

            if let chapterTitle = segment.chapterTitle, segment.startsChapter {
                currentChapterStarts.append(chapterTitle)
            }

            let lines = makeVerticalLines(
                from: previewText(for: segment, settings: settings, tableOfContentsEntries: tableOfContentsEntries),
                charactersPerLine: settings.charactersPerLine
            )

            for line in lines {
                currentLines.append(line)

                if currentLines.count >= maxLines {
                    appendCurrentPage()
                }
            }

            if segment.isTableOfContentsPlaceholder {
                appendCurrentPage()
                currentStartsAfterPageBreak = true
            }
        }

        appendCurrentPage()
        return pages.isEmpty ? [PreviewPage(columns: [""], startsAfterPageBreak: false, chapterTitle: nil)] : pages
    }

    private static func chapterEntries(in pages: [PreviewPage]) -> [TableOfContentsEntry] {
        pages.enumerated().flatMap { index, page in
            page.chapterTitlesStartingOnPage.map { title in
                TableOfContentsEntry(title: title, pageNumber: index + 1)
            }
        }
    }

    private static func appendingColophonIfNeeded(
        to pages: [PreviewPage],
        settings: EditorSettings,
        workTitle: String
    ) -> [PreviewPage] {
        var colophon = settings.colophon.validated
        colophon.workTitle = workTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard colophon.isEnabled else { return pages }

        return pages + [
            PreviewPage(
                kind: .colophon(colophon),
                columns: colophonColumns(from: colophon),
                startsAfterPageBreak: false,
                chapterTitle: nil
            )
        ]
    }

    static func colophonColumns(from colophon: ColophonSettings) -> [String] {
        let entries = colophonEntries(from: colophon)
        let labelCharacterCount = entries.map { $0.label.count }.max() ?? 0
        var columns: [String] = []

        for entry in entries {
            if Self.isVerticalHorizontalColophonEntry(entry) {
                continue
            }

            if entry.addsPrecedingSpace {
                columns.append("")
            }

            if entry.label.isEmpty {
                columns.append(entry.value)
            } else {
                let padding = String(repeating: "　", count: max(labelCharacterCount - entry.label.count, 0))
                columns.append("\(entry.label)\(padding)　\(entry.value)")
            }

            if entry.addsFollowingSpace {
                columns.append("")
            }
        }

        return columns
    }

    static func verticalHorizontalColophonEntries(from colophon: ColophonSettings) -> [ColophonEntry] {
        colophonEntries(from: colophon).filter { ["hp", "x", "pixiv", "contact"].contains($0.id) }
    }

    private static func isVerticalHorizontalColophonEntry(_ entry: ColophonEntry) -> Bool {
        ["hp", "x", "pixiv", "contact"].contains(entry.id)
    }

    static func colophonEntries(from colophon: ColophonSettings) -> [ColophonEntry] {
        [
            ColophonEntry(
                id: "workTitle",
                label: "",
                value: colophon.workTitle,
                addsFollowingSpace: false,
                centersInHorizontalLayout: true
            ),
            ColophonEntry(
                id: "creator",
                label: "",
                value: authorCircleText(authorName: colophon.authorName, circleName: colophon.circleName),
                addsFollowingSpace: true,
                centersInHorizontalLayout: true
            ),
            ColophonEntry(
                id: "publicationDate",
                label: "発行日",
                value: colophon.formattedPublicationDate,
                addsFollowingSpace: false
            ),
            ColophonEntry(
                id: "printer",
                label: "印刷所",
                value: colophon.printerName,
                addsFollowingSpace: true
            ),
            ColophonEntry(id: "hp", label: "HP", value: colophon.websiteURL, addsFollowingSpace: false),
            ColophonEntry(id: "x", label: "x（旧Twitter）", value: colophon.xURL, addsFollowingSpace: false),
            ColophonEntry(id: "pixiv", label: "pixiv", value: colophon.pixivURL, addsFollowingSpace: false),
            ColophonEntry(id: "contact", label: "連絡先", value: colophon.contact, addsFollowingSpace: false),
            ColophonEntry(
                id: "notes",
                label: "その他",
                value: colophon.notes,
                addsPrecedingSpace: true,
                addsFollowingSpace: false
            )
        ].filter { entry in
            if entry.id == "creator", colophon.hasCreatorImage {
                return true
            }

            return !entry.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private static func authorCircleText(authorName: String, circleName: String) -> String {
        let values = [authorName, circleName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return values.joined(separator: "／")
    }

    private static func previewText(
        for segment: ParsedManuscriptSegment,
        settings: EditorSettings,
        tableOfContentsEntries: [TableOfContentsEntry]
    ) -> String {
        if segment.isTableOfContentsPlaceholder {
            guard settings.showTableOfContents else { return "" }
            return tableOfContentsText(entries: tableOfContentsEntries, settings: settings)
        }

        guard let chapterTitle = segment.chapterTitle, segment.startsChapter else {
            return segment.text
        }

        let formattedTitle = formattedBodyChapterTitle(chapterTitle, settings: settings)
        guard !segment.text.isEmpty else {
            return "\n\(formattedTitle)\n\n"
        }

        return "\n\(formattedTitle)\n\n\(segment.text)"
    }

    private static func tableOfContentsText(entries: [TableOfContentsEntry], settings: EditorSettings) -> String {
        let title = tableOfContentsTitle(settings: settings)
        let lines = entries.map { entry in
            "\(entry.title)　\(entry.pageNumber)"
        }

        guard !lines.isEmpty else {
            return "\(title)\n"
        }

        return ([title, ""] + lines).joined(separator: "\n")
    }

    private static func tableOfContentsTitle(settings: EditorSettings) -> String {
        guard settings.chapterTitleStyle == .centered else {
            return "目次"
        }

        let leadingSpaces = max((settings.charactersPerLine - "目次".count) / 2, 0)
        return String(repeating: "　", count: leadingSpaces) + "目次"
    }

    private static func formattedBodyChapterTitle(_ title: String, settings: EditorSettings) -> String {
        let formattedTitle = ChapterTitleFormatter.format(title, style: settings.chapterTitleStyle)
        guard settings.chapterTitleStyle == .centered else {
            return formattedTitle
        }

        let leadingSpaces = max((settings.charactersPerLine - formattedTitle.count) / 2, 0)
        return String(repeating: "　", count: leadingSpaces) + formattedTitle
    }

    private static func makeVerticalLines(from text: String, charactersPerLine: Int) -> [String] {
        let maxCharacters = max(charactersPerLine, 1)
        var lines: [String] = []
        var currentLine = ""

        for character in text {
            if character == "\r" {
                continue
            }

            if character == "\n" {
                lines.append(currentLine)
                currentLine = ""
                continue
            }

            currentLine.append(character)

            if currentLine.count >= maxCharacters {
                lines.append(currentLine)
                currentLine = ""
            }
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        return lines.isEmpty ? [""] : lines
    }
}

struct TableOfContentsEntry: Equatable {
    let title: String
    let pageNumber: Int
}

@MainActor
final class PreviewViewModel: ObservableObject {
    @Published private(set) var document: ManuscriptDocument

    private let documentStore: DocumentStore

    init(documentStore: DocumentStore) {
        self.documentStore = documentStore
        self.document = documentStore.document

        documentStore.$document
            .assign(to: &$document)
    }

    var pages: [PreviewPage] {
        ManuscriptPaginator.pages(for: document)
    }

    var subscriptionStatus: SubscriptionStatus {
        documentStore.subscriptionStatus
    }

    func layout(for pageNumber: Int) -> PageLayout {
        LayoutCalculator.layout(for: document.settings, pageNumber: pageNumber)
    }
}
