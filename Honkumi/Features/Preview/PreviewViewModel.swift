import Combine
import Foundation

nonisolated struct PreviewPage: Identifiable, Equatable {
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

nonisolated enum PreviewPageKind: Equatable {
    case body
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
        ))

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
            let updatedEntries = chapterEntries(in: pages)
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
        var currentChapterTitle: String?
        var currentStartsAfterPageBreak = false
        var currentChapterStarts: [String] = []

        func appendCurrentPage() {
            guard !currentLines.isEmpty || pages.isEmpty else {
                currentStartsAfterPageBreak = false
                currentChapterStarts = []
                return
            }
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
                label: "発行者",
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
        let leaderCount = max(settings.charactersPerLine - titleCellCount - pageNumberCellCount, 0)
        let separator = String(repeating: "…", count: leaderCount)
        return entry.title + separator + pageNumber
    }

    private static func tableOfContentsPageNumber(_ pageNumber: Int) -> String {
        String(pageNumber).map { character in
            guard let digit = character.wholeNumberValue else {
                return String(character)
            }
            let scalar = UnicodeScalar(0xFF10 + digit)!
            return String(Character(scalar))
        }.joined()
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

    private static func makeVerticalLines(
        from text: String,
        charactersPerLine: Int,
        alphanumericOrientation: AlphanumericOrientation,
        indentsParagraphs: Bool,
        indentExemptLines: Set<String>
    ) -> [String] {
        let maxCharacters = max(charactersPerLine, 1)
        var lines: [String] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = preparedParagraphLine(
                rawLine,
                indentsParagraphs: indentsParagraphs,
                indentExemptLines: indentExemptLines
            )
            if line.isEmpty {
                lines.append("")
                continue
            }

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
              !normalizedLine.hasPrefix("『") else {
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
        ["」", "』", "）", "】", "〉", "》", "］", "｝"].contains(character)
    }

    private static let punctuationCharacters: Set<String> = [
        "、", "。", "，", "．", "､", "｡", "︑", "︒", "︐"
    ]
}

nonisolated struct TableOfContentsEntry: Equatable {
    let title: String
    let pageNumber: Int
}

@MainActor
final class PreviewViewModel: ObservableObject {
    @Published private(set) var document: ManuscriptDocument
    @Published private(set) var pages: [PreviewPage]
    @Published private(set) var isPaginating = false

    private let documentStore: DocumentStore
    private var cancellables = Set<AnyCancellable>()
    private var paginationTask: Task<Void, Never>?
    private var paginationGeneration = 0
    private var layoutCacheSettings: EditorSettings?
    private var layoutCache: [Int: PageLayout] = [:]
    private var isPreviewActive = false

    init(documentStore: DocumentStore) {
        self.documentStore = documentStore
        self.document = documentStore.document
        self.pages = [PreviewPage(columns: [""], startsAfterPageBreak: false, chapterTitle: nil)]

        documentStore.$document
            .sink { [weak self] document in
                guard let self else { return }
                self.document = document
                self.clearLayoutCacheIfNeeded(for: document.settings.validated)
                if self.isPreviewActive {
                    self.schedulePagination(for: document, debounceMilliseconds: 350)
                } else {
                    self.cancelInactivePagination()
                }
            }
            .store(in: &cancellables)

        documentStore.$appData
            .map(\.subscriptionStatus)
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.isPreviewActive else { return }
                self.schedulePagination(for: self.documentStore.document, debounceMilliseconds: 0)
            }
            .store(in: &cancellables)
    }

    deinit {
        paginationTask?.cancel()
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

    func layout(for pageNumber: Int) -> PageLayout {
        let settings = document.settings.validated
        clearLayoutCacheIfNeeded(for: settings)
        if let cachedLayout = layoutCache[pageNumber] {
            return cachedLayout
        }

        let layout = LayoutCalculator.layout(for: settings, pageNumber: pageNumber)
        layoutCache[pageNumber] = layout
        return layout
    }

    func preparePreviewIfNeeded() {
        guard isPreviewActive else { return }
        schedulePagination(for: documentStore.document, debounceMilliseconds: 0)
    }

    func setPreviewActive(_ isActive: Bool) {
        guard isPreviewActive != isActive else {
            if isActive {
                preparePreviewIfNeeded()
            }
            return
        }

        isPreviewActive = isActive
        if isActive {
            preparePreviewIfNeeded()
        } else {
            cancelInactivePagination()
        }
    }

    private func schedulePagination(for document: ManuscriptDocument, debounceMilliseconds: UInt64) {
        paginationTask?.cancel()
        paginationGeneration += 1
        let generation = paginationGeneration
        let documentSnapshot = document
        let subscriptionStatus = documentStore.subscriptionStatus

        if let cachedResult = ManuscriptRenderPipeline.cachedPaginationResult(
            for: documentSnapshot,
            subscriptionStatus: subscriptionStatus
        ) {
            applyPagination(
                result: cachedResult,
                generation: generation,
                documentID: documentSnapshot.id
            )
            return
        }

        isPaginating = true

        paginationTask = Task.detached(priority: .utility) { [weak self] in
            if debounceMilliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(debounceMilliseconds))
                guard !Task.isCancelled else { return }
            }

            let result = ManuscriptRenderPipeline.paginationResult(
                for: documentSnapshot,
                subscriptionStatus: subscriptionStatus
            )
            guard !Task.isCancelled else { return }

            await self?.applyPagination(
                result: result,
                generation: generation,
                documentID: documentSnapshot.id
            )
        }
    }

    private func applyPagination(result: ManuscriptPaginationResult, generation: Int, documentID: UUID) {
        guard paginationGeneration == generation, document.id == documentID else { return }
        self.document = result.document
        clearLayoutCacheIfNeeded(for: result.document.settings.validated)
        self.pages = result.pages
        self.isPaginating = false
    }

    private func cancelInactivePagination() {
        paginationTask?.cancel()
        paginationTask = nil
        isPaginating = false
    }

    private func clearLayoutCacheIfNeeded(for settings: EditorSettings) {
        guard layoutCacheSettings != settings else { return }
        layoutCacheSettings = settings
        layoutCache.removeAll(keepingCapacity: true)
    }
}
