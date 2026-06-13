import Combine
import Foundation

nonisolated struct PreviewPage: Identifiable, Equatable {
    let id = UUID()
    let kind: PreviewPageKind
    let columns: [String]
    let startsAfterPageBreak: Bool
    let chapterTitle: String?
    let chapterTitlesStartingOnPage: [String]
    let tableOfContentsEntries: [TableOfContentsEntry]

    init(
        kind: PreviewPageKind = .body,
        columns: [String],
        startsAfterPageBreak: Bool,
        chapterTitle: String?,
        chapterTitlesStartingOnPage: [String] = [],
        tableOfContentsEntries: [TableOfContentsEntry] = []
    ) {
        self.kind = kind
        self.columns = columns
        self.startsAfterPageBreak = startsAfterPageBreak
        self.chapterTitle = chapterTitle
        self.chapterTitlesStartingOnPage = chapterTitlesStartingOnPage
        self.tableOfContentsEntries = tableOfContentsEntries
    }
}

nonisolated enum PreviewPageKind: Equatable {
    case body
    case tableOfContents
    case colophon(ColophonSettings)
}

nonisolated struct ColophonEntry: Identifiable, Equatable {
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

nonisolated struct VerticalHorizontalColophonEntry: Identifiable, Equatable {
    let id: String
    let entry: ColophonEntry
    let columnIndex: Int
}

private struct TableOfContentsPaginationRow {
    let text: String
    let entry: TableOfContentsEntry?
}

nonisolated enum ManuscriptPaginator {
    private static let maxTableOfContentsPasses = 6

    static func pages(for document: ManuscriptDocument) -> [PreviewPage] {
        let settings = document.settings.validated
        let parsedSegments = ManuscriptMarkupParser.parse(document.body).segments
        let segments = normalizedSegments(parsedSegments, settings: settings)
        var tableOfContentsEntries = chapterEntries(in: paginate(
            segments,
            settings: settings,
            workTitle: document.title,
            tableOfContentsEntries: []
        ), settings: settings)

        guard settings.showTableOfContents else {
            return appendingColophonIfNeeded(
                to: paginate(segments, settings: settings, workTitle: document.title, tableOfContentsEntries: []),
                hasColophonPlaceholder: segments.contains(where: \.isColophonPlaceholder),
                settings: settings,
                workTitle: document.title
            )
        }

        var pages = paginate(
            segments,
            settings: settings,
            workTitle: document.title,
            tableOfContentsEntries: tableOfContentsEntries
        )
        for _ in 0..<maxTableOfContentsPasses {
            let updatedEntries = chapterEntries(in: pages, settings: settings)
            if updatedEntries == tableOfContentsEntries {
                return appendingColophonIfNeeded(
                    to: pages,
                    hasColophonPlaceholder: segments.contains(where: \.isColophonPlaceholder),
                    settings: settings,
                    workTitle: document.title
                )
            }

            tableOfContentsEntries = updatedEntries
            pages = paginate(
                segments,
                settings: settings,
                workTitle: document.title,
                tableOfContentsEntries: tableOfContentsEntries
            )
        }

        return appendingColophonIfNeeded(
            to: pages,
            hasColophonPlaceholder: segments.contains(where: \.isColophonPlaceholder),
            settings: settings,
            workTitle: document.title
        )
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
        workTitle: String,
        tableOfContentsEntries: [TableOfContentsEntry]
    ) -> [PreviewPage] {
        let maxLines = max(settings.linesPerPage, 1)
        var pages: [PreviewPage] = []
        var currentLines: [String] = []
        var currentPageKind: PreviewPageKind = .body
        var currentChapterTitle: String?
        var currentStartsAfterPageBreak = false
        var currentChapterStarts: [String] = []
        var currentTableOfContentsEntries: [TableOfContentsEntry] = []

        func appendCurrentPage() {
            guard !currentLines.isEmpty || pages.isEmpty else {
                currentPageKind = .body
                currentStartsAfterPageBreak = false
                currentChapterStarts = []
                currentTableOfContentsEntries = []
                return
            }
            pages.append(PreviewPage(
                kind: currentPageKind,
                columns: currentLines.isEmpty ? [""] : currentLines,
                startsAfterPageBreak: currentStartsAfterPageBreak,
                chapterTitle: currentChapterTitle,
                chapterTitlesStartingOnPage: currentChapterStarts,
                tableOfContentsEntries: currentPageKind == .tableOfContents
                    ? currentTableOfContentsEntries
                    : []
            ))
            currentLines = []
            currentPageKind = .body
            currentStartsAfterPageBreak = false
            currentChapterStarts = []
            currentTableOfContentsEntries = []
        }

        for (segmentIndex, segment) in segments.enumerated() {
            if segment.isColophonPlaceholder {
                appendCurrentPage()
                if let colophonPage = colophonPage(settings: settings, workTitle: workTitle) {
                    pages.append(colophonPage)
                }
                currentStartsAfterPageBreak = false
                continue
            }

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

            if segment.isTableOfContentsPlaceholder {
                if !currentLines.isEmpty {
                    appendCurrentPage()
                    currentStartsAfterPageBreak = true
                }
                currentPageKind = .tableOfContents
                for row in tableOfContentsRows(entries: tableOfContentsEntries, settings: settings) {
                    currentLines.append(row.text)
                    if let entry = row.entry {
                        currentTableOfContentsEntries.append(entry)
                    }

                    if currentLines.count >= maxLines {
                        appendCurrentPage()
                        currentPageKind = .tableOfContents
                    }
                }

                appendCurrentPage()
                currentStartsAfterPageBreak = true
                continue
            }

            let text = previewText(for: segment, settings: settings, tableOfContentsEntries: tableOfContentsEntries)
            let lines = makeVerticalLines(
                from: text,
                charactersPerLine: settings.charactersPerLine,
                alphanumericOrientation: settings.alphanumericOrientation,
                indentsParagraphs: !segment.isTableOfContentsPlaceholder,
                indentExemptLines: indentExemptLines(for: segment, settings: settings)
            )

            for line in lines {
                currentLines.append(line)

                if currentLines.count >= maxLines {
                    appendCurrentPage()
                    if segment.isTableOfContentsPlaceholder {
                        currentPageKind = .tableOfContents
                    }
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

    private static func chapterEntries(in pages: [PreviewPage], settings: EditorSettings) -> [TableOfContentsEntry] {
        var pageNumber = settings.pageNumberStart
        var entries: [TableOfContentsEntry] = []

        for page in pages {
            switch page.kind {
            case .body:
                entries.append(contentsOf: page.chapterTitlesStartingOnPage.map { title in
                    TableOfContentsEntry(title: title, pageNumber: pageNumber)
                })
                pageNumber += 1
            case .tableOfContents, .colophon:
                continue
            }
        }

        return entries
    }

    private static func appendingColophonIfNeeded(
        to pages: [PreviewPage],
        hasColophonPlaceholder: Bool,
        settings: EditorSettings,
        workTitle: String
    ) -> [PreviewPage] {
        guard !hasColophonPlaceholder, let colophonPage = colophonPage(settings: settings, workTitle: workTitle) else {
            return pages
        }

        return pages + [colophonPage]
    }

    private static func colophonPage(settings: EditorSettings, workTitle: String) -> PreviewPage? {
        var colophon = settings.colophon.validated
        colophon.workTitle = workTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard colophon.isEnabled else { return nil }

        return PreviewPage(
            kind: .colophon(colophon),
            columns: colophonColumns(from: colophon),
            startsAfterPageBreak: false,
            chapterTitle: nil
        )
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
                value: "",
                addsFollowingSpace: false,
                centersInHorizontalLayout: true
            ),
            ColophonEntry(
                id: "author",
                label: "作者",
                value: colophon.showsAuthorName ? colophon.authorName : "",
                addsFollowingSpace: false
            ),
            ColophonEntry(
                id: "circle",
                label: "サークル",
                value: colophon.showsCircleName ? colophon.circleName : "",
                addsFollowingSpace: true
            ),
            ColophonEntry(
                id: "publicationDate",
                label: "発行日",
                value: colophon.showsPublicationDate ? colophon.formattedPublicationDate : "",
                addsFollowingSpace: false
            ),
            ColophonEntry(
                id: "printer",
                label: "印刷所",
                value: colophon.showsPrinterName ? colophon.printerName : "",
                addsFollowingSpace: true
            ),
            ColophonEntry(
                id: "hp",
                label: "HP",
                value: (colophon.showsWebsiteURL || colophon.showsQRCode) ? colophon.websiteURL : "",
                addsFollowingSpace: false
            ),
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
            if entry.id == "creator" { return colophon.hasCreatorImage }

            return !entry.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
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
            tableOfContentsLine(for: entry, settings: settings)
        }

        guard !lines.isEmpty else {
            return "\(title)\n"
        }

        return ([title, ""] + lines).joined(separator: "\n")
    }

    private static func tableOfContentsRows(
        entries: [TableOfContentsEntry],
        settings: EditorSettings
    ) -> [TableOfContentsPaginationRow] {
        let title = tableOfContentsTitle(settings: settings)
        guard !entries.isEmpty else {
            return [TableOfContentsPaginationRow(text: title, entry: nil)]
        }

        let entryRows = entries.map { entry in
            TableOfContentsPaginationRow(
                text: entry.title + tableOfContentsPageNumber(entry.pageNumber),
                entry: entry
            )
        }
        return [TableOfContentsPaginationRow(text: title, entry: nil), TableOfContentsPaginationRow(text: "", entry: nil)]
            + entryRows
    }

    private static func tableOfContentsLine(for entry: TableOfContentsEntry, settings: EditorSettings) -> String {
        let pageNumber = tableOfContentsPageNumber(entry.pageNumber)
        let titleCellCount = VerticalTextTypesetter.cellCount(
            for: entry.title,
            alphanumericOrientation: settings.alphanumericOrientation
        )
        let pageNumberCellCount = VerticalTextTypesetter.cellCount(
            for: pageNumber,
            alphanumericOrientation: settings.alphanumericOrientation
        )
        let availableCellCount = max(settings.charactersPerLine - titleCellCount - pageNumberCellCount, 0)
        let separator = tableOfContentsSeparator(
            availableCellCount: availableCellCount,
            settings: settings
        )
        return entry.title + separator + pageNumber
    }

    private static let tableOfContentsLeader = "︙"

    private static func tableOfContentsSeparator(availableCellCount: Int, settings: EditorSettings) -> String {
        guard availableCellCount > 0 else { return "" }
        let sideSpaceCount = 2
        let reservedSpaceCount = sideSpaceCount * 2
        guard availableCellCount > reservedSpaceCount else {
            return String(repeating: "　", count: availableCellCount)
        }
        let leader = tableOfContentsLeader
        let dottedLeader = Array(repeating: leader, count: availableCellCount - reservedSpaceCount).joined()
        let sideSpaces = String(repeating: "　", count: sideSpaceCount)
        return sideSpaces + dottedLeader + sideSpaces
    }

    private static func tableOfContentsPageNumber(_ pageNumber: Int) -> String {
        VerticalTextTypesetter.horizontalRun(String(pageNumber))
    }

    private static func tableOfContentsTitle(settings: EditorSettings) -> String {
        "目次"
    }

    private static func formattedBodyChapterTitle(_ title: String, settings: EditorSettings) -> String {
        let formattedTitle = ChapterTitleFormatter.format(title, style: settings.chapterTitleStyle)
        guard settings.chapterTitleStyle == .centered else {
            return formattedTitle
        }

        let leadingSpaces = max((settings.charactersPerLine - formattedTitle.count) / 2, 0)
        return String(repeating: "　", count: leadingSpaces) + formattedTitle
    }

    private static func makeVerticalLines(
        from text: String,
        charactersPerLine: Int,
        alphanumericOrientation: AlphanumericOrientation,
        indentsParagraphs: Bool,
        indentExemptLines: Set<String>
    ) -> [String] {
        let maxCharacters = max(charactersPerLine, 1)
        var lines: [String] = []
        var previousLineWasEmpty = false

        for rawLine in text.components(separatedBy: .newlines) {
            let line = preparedParagraphLine(
                rawLine,
                indentsParagraphs: indentsParagraphs,
                indentExemptLines: indentExemptLines
            )
            if line.isEmpty {
                if !previousLineWasEmpty {
                    lines.append("")
                }
                previousLineWasEmpty = true
                continue
            }

            previousLineWasEmpty = false
            lines.append(contentsOf: wrappedVerticalLines(
                from: line,
                maxCharacters: maxCharacters,
                alphanumericOrientation: alphanumericOrientation
            ))
        }

        return lines.isEmpty ? [""] : lines
    }

    private static func preparedParagraphLine(
        _ line: String,
        indentsParagraphs: Bool,
        indentExemptLines: Set<String>
    ) -> String {
        let normalizedLine = line.replacingOccurrences(of: "\r", with: "")
        let trimmedLine = normalizedLine.trimmingCharacters(in: .whitespaces)
        guard indentsParagraphs,
              !trimmedLine.isEmpty,
              !indentExemptLines.contains(trimmedLine),
              !normalizedLine.hasPrefix("　"),
              !normalizedLine.hasPrefix("「"),
              !normalizedLine.hasPrefix("『"),
              !normalizedLine.hasPrefix("“"),
              !normalizedLine.hasPrefix("〝") else {
            return normalizedLine
        }

        return "　" + normalizedLine
    }

    private static func indentExemptLines(
        for segment: ParsedManuscriptSegment,
        settings: EditorSettings
    ) -> Set<String> {
        guard let chapterTitle = segment.chapterTitle, segment.startsChapter else {
            return []
        }

        return [formattedBodyChapterTitle(chapterTitle, settings: settings).trimmingCharacters(in: .whitespaces)]
    }

    private static func wrappedVerticalLines(
        from line: String,
        maxCharacters: Int,
        alphanumericOrientation: AlphanumericOrientation
    ) -> [String] {
        let units = VerticalTextTypesetter.layoutUnits(
            from: line,
            alphanumericOrientation: alphanumericOrientation
        )
        var wrappedLines: [String] = []
        var index = 0

        while index < units.count {
            var currentLine: [VerticalTextLayoutUnit] = []
            var currentCellCount = 0

            while index < units.count {
                let unit = units[index]
                let proposedCellCount = currentCellCount + unit.cellSpan

                if !currentLine.isEmpty, proposedCellCount > maxCharacters {
                    break
                }

                currentLine.append(unit)
                currentCellCount = proposedCellCount
                index += 1

                if currentCellCount >= maxCharacters {
                    break
                }
            }

            if index < units.count {
                if shouldMoveLastUnitToNextLine(currentLine, nextUnits: Array(units[index...])) {
                    index -= 1
                    currentLine.removeLast()
                } else {
                    appendHangingCharacters(
                        to: &currentLine,
                        from: units,
                        index: &index
                    )
                }
            }

            if currentLine.isEmpty, index < units.count {
                currentLine.append(units[index])
                index += 1
            }

            wrappedLines.append(currentLine.map(\.text).joined())
        }

        return wrappedLines
    }

    private static func shouldMoveLastUnitToNextLine(
        _ currentLine: [VerticalTextLayoutUnit],
        nextUnits: [VerticalTextLayoutUnit]
    ) -> Bool {
        guard currentLine.count > 1 else { return false }

        if VerticalTextTypesetter.isLineEndProhibited(currentLine.last?.text) {
            return true
        }

        if nextUnitsCellCount(nextUnits) == 1 {
            return true
        }

        if leavesSingleBaseWithTrailingMarks(nextUnits) {
            return true
        }

        guard let nextText = nextUnits.first?.text,
              let nextCharacter = nextText.first.map(String.init),
              isPunctuation(nextCharacter),
              nextUnits.indices.contains(1),
              let followingCharacter = nextUnits[1].text.first.map(String.init),
              isClosingQuote(followingCharacter) else {
            return false
        }

        return true
    }

    private static func leavesSingleBaseWithTrailingMarks(_ nextUnits: [VerticalTextLayoutUnit]) -> Bool {
        guard let firstUnit = nextUnits.first,
              firstUnit.cellSpan == 1,
              isSingleBaseCharacter(firstUnit.text),
              !VerticalTextTypesetter.isLineStartProhibited(firstUnit.text) else {
            return false
        }

        let trailingUnits = Array(nextUnits.dropFirst())
        guard !trailingUnits.isEmpty else { return true }

        var consumedCellCount = 0
        for unit in trailingUnits.prefix(2) {
            if VerticalTextTypesetter.isLineStartProhibited(unit.text)
                || VerticalTextTypesetter.formsNonBreakingPair(firstUnit.text, unit.text) {
                consumedCellCount += unit.cellSpan
                continue
            }
            return false
        }

        return consumedCellCount > 0 && consumedCellCount <= 2
    }

    private static func appendHangingCharacters(
        to currentLine: inout [VerticalTextLayoutUnit],
        from units: [VerticalTextLayoutUnit],
        index: inout Int
    ) {
        while index < units.count {
            let nextUnit = units[index]

            if VerticalTextTypesetter.isLineStartProhibited(nextUnit.text)
                || VerticalTextTypesetter.formsNonBreakingPair(currentLine.last?.text, nextUnit.text) {
                currentLine.append(nextUnit)
                index += 1
            } else {
                break
            }
        }
    }

    private static func nextUnitsCellCount(_ units: [VerticalTextLayoutUnit]) -> Int {
        units.reduce(0) { $0 + $1.cellSpan }
    }

    private static func isPunctuation(_ character: String) -> Bool {
        punctuationCharacters.contains(character)
    }

    private static func isClosingQuote(_ character: String) -> Bool {
        ["」", "』", "”", "〟", "〞", "）", "】", "〉", "》", "］", "｝"].contains(character)
    }

    private static func isSingleBaseCharacter(_ text: String) -> Bool {
        text.count == 1
            && !isPunctuation(text)
            && !VerticalTextTypesetter.isSmallKana(text)
            && !VerticalTextTypesetter.isDashLike(text)
    }

    private static let punctuationCharacters: Set<String> = [
        "、", "。", "，", "．", "､", "｡", "︑", "︒", "︐"
    ]
}

nonisolated struct TableOfContentsEntry: Equatable {
    let title: String
    let pageNumber: Int
}

nonisolated enum PreviewPDFKind: String, Equatable {
    case normal
    case spread
}

@MainActor
final class PreviewViewModel: ObservableObject {
    @Published private(set) var document: ManuscriptDocument
    @Published private(set) var previewPDFURL: URL?
    @Published private(set) var isGeneratingPDF = false
    @Published private(set) var generationErrorMessage: String?

    private let documentStore: DocumentStore
    private let pdfExportService = PDFExportService()
    private var cancellables = Set<AnyCancellable>()
    private var generationTask: Task<Void, Never>?
    private var generation = 0
    private var isPreviewActive = false
    private var activePreviewKind: PreviewPDFKind = .normal

    init(documentStore: DocumentStore) {
        self.documentStore = documentStore
        self.document = documentStore.document.applyingPublisherInfo(from: documentStore.userDefaultSettings)

        documentStore.$document
            .sink { [weak self] document in
                guard let self else { return }
                let previewDocument = self.previewDocument(from: document)
                self.document = previewDocument
                if self.isPreviewActive {
                    self.schedulePDFGeneration(
                        for: previewDocument,
                        kind: self.activePreviewKind,
                        debounceMilliseconds: 350
                    )
                } else {
                    self.cancelInactiveGeneration()
                }
            }
            .store(in: &cancellables)

        documentStore.$appData
            .map { ($0.userDefaultSettings, $0.subscriptionStatus) }
            .removeDuplicates { previous, current in
                previous.0 == current.0 && previous.1 == current.1
            }
            .sink { [weak self] _ in
                guard let self else { return }
                let previewDocument = self.previewDocument(from: self.documentStore.document)
                self.document = previewDocument
                guard self.isPreviewActive else { return }
                self.schedulePDFGeneration(
                    for: previewDocument,
                    kind: self.activePreviewKind,
                    debounceMilliseconds: 0
                )
            }
            .store(in: &cancellables)
    }

    deinit {
        generationTask?.cancel()
    }

    var subscriptionStatus: SubscriptionStatus {
        documentStore.subscriptionStatus
    }

    var isAdditionalFontPackUnlocked: Bool {
        documentStore.isAdditionalFontPackUnlocked
    }

    var isPageNumberFontUnlocked: Bool {
        documentStore.isPageNumberFontUnlocked
    }

    var displayTitle: String {
        let trimmedTitle = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "Honkumi" : trimmedTitle
    }

    func preparePreviewIfNeeded(for kind: PreviewPDFKind = .normal) {
        if activePreviewKind != kind {
            activePreviewKind = kind
            guard isPreviewActive else { return }
            schedulePDFGeneration(
                for: previewDocument(from: documentStore.document),
                kind: kind,
                debounceMilliseconds: 0
            )
            return
        }

        guard isPreviewActive, !isGeneratingPDF, previewPDFURL == nil else { return }
        schedulePDFGeneration(
            for: previewDocument(from: documentStore.document),
            kind: kind,
            debounceMilliseconds: 0
        )
    }

    func setPreviewActive(_ isActive: Bool, kind: PreviewPDFKind = .normal) {
        guard isPreviewActive != isActive else {
            if isActive {
                preparePreviewIfNeeded(for: kind)
            } else {
                activePreviewKind = kind
            }
            return
        }

        activePreviewKind = kind
        isPreviewActive = isActive
        if isActive {
            preparePreviewIfNeeded(for: kind)
        } else {
            cancelInactiveGeneration()
            clearCurrentPreviewPDF()
        }
    }

    private func schedulePDFGeneration(
        for document: ManuscriptDocument,
        kind: PreviewPDFKind,
        debounceMilliseconds: UInt64
    ) {
        generationTask?.cancel()
        generation += 1
        let generationID = generation
        let documentSnapshot = document
        let previewKind = kind
        let subscriptionStatus = documentStore.subscriptionStatus
        let pdfExportService = pdfExportService
        clearCurrentPreviewPDF()
        isGeneratingPDF = true
        generationErrorMessage = nil

        generationTask = Task { [weak self] in
            var generatedURL: URL?
            do {
                if debounceMilliseconds > 0 {
                    try await Task.sleep(for: .milliseconds(debounceMilliseconds))
                }

                try Task.checkCancellation()
                let outputURL = try await pdfExportService.exportPreviewPDF(
                    document: documentSnapshot,
                    subscriptionStatus: subscriptionStatus,
                    previewKind: previewKind,
                    generationID: UUID()
                )
                generatedURL = outputURL
                try Self.validateGeneratedPDF(at: outputURL)
                try Task.checkCancellation()

                self?.applyGeneratedPDF(
                    at: outputURL,
                    generation: generationID,
                    documentID: documentSnapshot.id,
                    kind: previewKind
                )
            } catch is CancellationError {
                self?.cleanupPreviewPDF(at: generatedURL)
                self?.discardCancelledGeneration(generation: generationID)
            } catch {
                self?.applyGenerationError(
                    error,
                    generation: generationID,
                    documentID: documentSnapshot.id,
                    kind: previewKind
                )
            }
        }
    }

    private func previewDocument(from document: ManuscriptDocument) -> ManuscriptDocument {
        document.applyingPublisherInfo(from: documentStore.userDefaultSettings)
    }

    private func applyGeneratedPDF(
        at url: URL,
        generation: Int,
        documentID: UUID,
        kind: PreviewPDFKind
    ) {
        guard self.generation == generation,
              document.id == documentID,
              activePreviewKind == kind,
              isPreviewActive else {
            cleanupPreviewPDF(at: url)
            return
        }

        previewPDFURL = url
        isGeneratingPDF = false
        generationErrorMessage = nil
    }

    private func applyGenerationError(
        _ error: Error,
        generation: Int,
        documentID: UUID,
        kind: PreviewPDFKind
    ) {
        guard self.generation == generation,
              document.id == documentID,
              activePreviewKind == kind,
              isPreviewActive else { return }
        previewPDFURL = nil
        isGeneratingPDF = false
        generationErrorMessage = error.localizedDescription
    }

    private func discardCancelledGeneration(generation: Int) {
        guard self.generation == generation else { return }
        isGeneratingPDF = false
    }

    private func cancelInactiveGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isGeneratingPDF = false
    }

    private func clearCurrentPreviewPDF() {
        let url = previewPDFURL
        previewPDFURL = nil
        generationErrorMessage = nil
        cleanupPreviewPDF(at: url)
    }

    private func cleanupPreviewPDF(at url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func validateGeneratedPDF(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PreviewPDFGenerationError.fileNotFound
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? NSNumber
        guard (fileSize?.int64Value ?? 0) > 0 else {
            throw PreviewPDFGenerationError.emptyFile
        }
    }
}

private enum PreviewPDFGenerationError: LocalizedError {
    case fileNotFound
    case emptyFile

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            "プレビュー用PDFを生成できませんでした。もう一度プレビューを開いてください。"
        case .emptyFile:
            "プレビュー用PDFが空です。本文とPDF設定を確認してください。"
        }
    }
}
