import CoreGraphics
import Foundation

nonisolated struct EditorSettings: Codable, Equatable {
    static let fontSizeRange: ClosedRange<CGFloat> = 7...20
    static let charactersPerLineRange: ClosedRange<Int> = 25...54
    static let linesPerPageRange: ClosedRange<Int> = 10...28
    static let marginTopRange: ClosedRange<CGFloat> = 8...30
    static let marginBottomRange: ClosedRange<CGFloat> = 8...30
    static let marginInnerRange: ClosedRange<CGFloat> = 10...30
    static let marginOuterRange: ClosedRange<CGFloat> = 8...25
    static let lineSpacingRange: ClosedRange<CGFloat> = 0...8
    static let characterSpacingRange: ClosedRange<CGFloat> = 0...4
    static let maxConsecutiveBlankLinesRange: ClosedRange<Int> = 0...5
    static let pageNumberSizeRange: ClosedRange<CGFloat> = 6...18
    static let pageNumberStartRange: ClosedRange<Int> = 1...9999
    static let editorFontSizeRange: ClosedRange<CGFloat> = 7...20

    var pageSize: PageSize
    var selectedFontId: String
    var fontSize: CGFloat
    var editorFontId: String
    var editorFontSize: CGFloat
    var lineSpacing: CGFloat
    var characterSpacing: CGFloat
    var charactersPerLine: Int
    var linesPerPage: Int
    var marginTop: CGFloat
    var marginBottom: CGFloat
    var marginInner: CGFloat
    var marginOuter: CGFloat
    var isPageNumberEnabled: Bool
    var pageNumberFontId: String?
    var pageNumberSize: CGFloat
    var pageNumberStart: Int
    var pageNumberPosition: PageNumberPosition
    var showTableOfContents: Bool
    var showChapterTitle: Bool
    var chapterTitleStyle: ChapterTitleStyle
    var startsChapterOnNewPage: Bool
    var alphanumericOrientation: AlphanumericOrientation
    var useRecommendedPrintSettings: Bool
    var showsCropMarks: Bool
    var colophon: ColophonSettings
    var formatSettings: FormatSettings

    init(
        pageSize: PageSize,
        selectedFontId: String,
        fontSize: CGFloat,
        editorFontId: String = AppFontCatalog.defaultFontId,
        editorFontSize: CGFloat = 14,
        lineSpacing: CGFloat,
        characterSpacing: CGFloat,
        charactersPerLine: Int,
        linesPerPage: Int,
        marginTop: CGFloat,
        marginBottom: CGFloat,
        marginInner: CGFloat,
        marginOuter: CGFloat,
        isPageNumberEnabled: Bool,
        pageNumberFontId: String?,
        pageNumberSize: CGFloat,
        pageNumberStart: Int = 1,
        pageNumberPosition: PageNumberPosition,
        showTableOfContents: Bool,
        showChapterTitle: Bool,
        chapterTitleStyle: ChapterTitleStyle,
        startsChapterOnNewPage: Bool,
        alphanumericOrientation: AlphanumericOrientation = .sideways,
        useRecommendedPrintSettings: Bool = true,
        showsCropMarks: Bool = false,
        colophon: ColophonSettings = .default,
        formatSettings: FormatSettings = .default
    ) {
        self.pageSize = pageSize
        self.selectedFontId = selectedFontId
        self.fontSize = fontSize
        self.editorFontId = editorFontId
        self.editorFontSize = editorFontSize
        self.lineSpacing = lineSpacing
        self.characterSpacing = characterSpacing
        self.charactersPerLine = charactersPerLine
        self.linesPerPage = linesPerPage
        self.marginTop = marginTop
        self.marginBottom = marginBottom
        self.marginInner = marginInner
        self.marginOuter = marginOuter
        self.isPageNumberEnabled = isPageNumberEnabled
        self.pageNumberFontId = pageNumberFontId
        self.pageNumberSize = pageNumberSize
        self.pageNumberStart = pageNumberStart
        self.pageNumberPosition = pageNumberPosition
        self.showTableOfContents = showTableOfContents
        self.showChapterTitle = showChapterTitle
        self.chapterTitleStyle = chapterTitleStyle
        self.startsChapterOnNewPage = startsChapterOnNewPage
        self.alphanumericOrientation = alphanumericOrientation
        self.useRecommendedPrintSettings = useRecommendedPrintSettings
        self.showsCropMarks = showsCropMarks
        self.colophon = colophon
        self.formatSettings = formatSettings
    }

    static let `default` = EditorSettings(
        pageSize: .a6,
        selectedFontId: AppFontCatalog.defaultFontId,
        fontSize: 9,
        editorFontId: AppFontCatalog.defaultFontId,
        editorFontSize: 14,
        lineSpacing: 0,
        characterSpacing: 0,
        charactersPerLine: 37,
        linesPerPage: 17,
        marginTop: 18,
        marginBottom: 15,
        marginInner: 10,
        marginOuter: 10,
        isPageNumberEnabled: true,
        pageNumberFontId: nil,
        pageNumberSize: 7,
        pageNumberStart: 1,
        pageNumberPosition: .outside,
        showTableOfContents: false,
        showChapterTitle: false,
        chapterTitleStyle: .plain,
        startsChapterOnNewPage: false,
        alphanumericOrientation: .sideways,
        useRecommendedPrintSettings: true,
        showsCropMarks: false,
        colophon: .default,
        formatSettings: .default
    )

    var validated: EditorSettings {
        EditorSettings(
            pageSize: pageSize,
            selectedFontId: AppFontCatalog.normalizedFontId(selectedFontId),
            fontSize: fontSize.clamped(to: Self.fontSizeRange),
            editorFontId: AppFontCatalog.normalizedFontId(editorFontId),
            editorFontSize: editorFontSize.clamped(to: Self.editorFontSizeRange),
            lineSpacing: lineSpacing.clamped(to: Self.lineSpacingRange),
            characterSpacing: characterSpacing.clamped(to: Self.characterSpacingRange),
            charactersPerLine: charactersPerLine.clamped(to: Self.charactersPerLineRange),
            linesPerPage: linesPerPage.clamped(to: Self.linesPerPageRange),
            marginTop: marginTop.clamped(to: Self.marginTopRange),
            marginBottom: marginBottom.clamped(to: Self.marginBottomRange),
            marginInner: marginInner.clamped(to: Self.marginInnerRange),
            marginOuter: marginOuter.clamped(to: Self.marginOuterRange),
            isPageNumberEnabled: isPageNumberEnabled,
            pageNumberFontId: pageNumberFontId,
            pageNumberSize: pageNumberSize.clamped(to: Self.pageNumberSizeRange),
            pageNumberStart: pageNumberStart.clamped(to: Self.pageNumberStartRange),
            pageNumberPosition: pageNumberPosition,
            showTableOfContents: showTableOfContents,
            showChapterTitle: showChapterTitle,
            chapterTitleStyle: chapterTitleStyle,
            startsChapterOnNewPage: startsChapterOnNewPage,
            alphanumericOrientation: alphanumericOrientation,
            useRecommendedPrintSettings: useRecommendedPrintSettings,
            showsCropMarks: showsCropMarks,
            colophon: colophon.validated,
            formatSettings: formatSettings.validated
        )
    }
}

nonisolated extension EditorSettings {
    private enum CodingKeys: String, CodingKey {
        case pageSize
        case selectedFontId
        case japaneseFont
        case fontSize
        case editorFontId
        case editorFontSize
        case lineSpacing
        case characterSpacing
        case charactersPerLine
        case linesPerPage
        case marginTop
        case marginBottom
        case marginInner
        case marginOuter
        case isPageNumberEnabled
        case pageNumberFontId
        case pageNumberSize
        case pageNumberStart
        case pageNumberPosition
        case showTableOfContents
        case showChapterTitle
        case chapterTitleStyle
        case startsChapterOnNewPage
        case alphanumericOrientation
        case useRecommendedPrintSettings
        case showsCropMarks
        case colophon
        case formatSettings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = EditorSettings.default
        let decodedSelectedFontId = try container.decodeIfPresent(String.self, forKey: .selectedFontId)
            ?? Self.selectedFontIdFromLegacyJapaneseFont(
                try container.decodeIfPresent(JapaneseFont.self, forKey: .japaneseFont)
            )
        let decodedEditorFontId = try container.decodeIfPresent(String.self, forKey: .editorFontId)
            ?? decodedSelectedFontId

        let decodedPageNumberPosition = try container.decodeIfPresent(PageNumberPosition.self, forKey: .pageNumberPosition)
            ?? defaults.pageNumberPosition
        let decodedIsPageNumberEnabled = try container.decodeIfPresent(Bool.self, forKey: .isPageNumberEnabled)
            ?? (decodedPageNumberPosition != .hidden)

        self.init(
            pageSize: try container.decodeIfPresent(PageSize.self, forKey: .pageSize) ?? defaults.pageSize,
            selectedFontId: AppFontCatalog.normalizedFontId(decodedSelectedFontId),
            fontSize: try container.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? defaults.fontSize,
            editorFontId: AppFontCatalog.normalizedFontId(decodedEditorFontId),
            editorFontSize: try container.decodeIfPresent(CGFloat.self, forKey: .editorFontSize) ?? defaults.editorFontSize,
            lineSpacing: try container.decodeIfPresent(CGFloat.self, forKey: .lineSpacing) ?? defaults.lineSpacing,
            characterSpacing: try container.decodeIfPresent(CGFloat.self, forKey: .characterSpacing) ?? defaults.characterSpacing,
            charactersPerLine: try container.decodeIfPresent(Int.self, forKey: .charactersPerLine) ?? defaults.charactersPerLine,
            linesPerPage: try container.decodeIfPresent(Int.self, forKey: .linesPerPage) ?? defaults.linesPerPage,
            marginTop: try container.decodeIfPresent(CGFloat.self, forKey: .marginTop) ?? defaults.marginTop,
            marginBottom: try container.decodeIfPresent(CGFloat.self, forKey: .marginBottom) ?? defaults.marginBottom,
            marginInner: try container.decodeIfPresent(CGFloat.self, forKey: .marginInner) ?? defaults.marginInner,
            marginOuter: try container.decodeIfPresent(CGFloat.self, forKey: .marginOuter) ?? defaults.marginOuter,
            isPageNumberEnabled: decodedIsPageNumberEnabled,
            pageNumberFontId: try container.decodeIfPresent(String.self, forKey: .pageNumberFontId),
            pageNumberSize: try container.decodeIfPresent(CGFloat.self, forKey: .pageNumberSize) ?? defaults.pageNumberSize,
            pageNumberStart: try container.decodeIfPresent(Int.self, forKey: .pageNumberStart) ?? defaults.pageNumberStart,
            pageNumberPosition: decodedPageNumberPosition,
            showTableOfContents: try container.decodeIfPresent(Bool.self, forKey: .showTableOfContents) ?? defaults.showTableOfContents,
            showChapterTitle: try container.decodeIfPresent(Bool.self, forKey: .showChapterTitle) ?? defaults.showChapterTitle,
            chapterTitleStyle: try container.decodeIfPresent(ChapterTitleStyle.self, forKey: .chapterTitleStyle) ?? defaults.chapterTitleStyle,
            startsChapterOnNewPage: try container.decodeIfPresent(Bool.self, forKey: .startsChapterOnNewPage) ?? defaults.startsChapterOnNewPage,
            alphanumericOrientation: try container.decodeIfPresent(AlphanumericOrientation.self, forKey: .alphanumericOrientation) ?? defaults.alphanumericOrientation,
            useRecommendedPrintSettings: try container.decodeIfPresent(Bool.self, forKey: .useRecommendedPrintSettings) ?? true,
            showsCropMarks: try container.decodeIfPresent(Bool.self, forKey: .showsCropMarks) ?? defaults.showsCropMarks,
            colophon: try container.decodeIfPresent(ColophonSettings.self, forKey: .colophon) ?? defaults.colophon,
            formatSettings: try container.decodeIfPresent(FormatSettings.self, forKey: .formatSettings) ?? defaults.formatSettings
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pageSize, forKey: .pageSize)
        try container.encode(selectedFontId, forKey: .selectedFontId)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(editorFontId, forKey: .editorFontId)
        try container.encode(editorFontSize, forKey: .editorFontSize)
        try container.encode(lineSpacing, forKey: .lineSpacing)
        try container.encode(characterSpacing, forKey: .characterSpacing)
        try container.encode(charactersPerLine, forKey: .charactersPerLine)
        try container.encode(linesPerPage, forKey: .linesPerPage)
        try container.encode(marginTop, forKey: .marginTop)
        try container.encode(marginBottom, forKey: .marginBottom)
        try container.encode(marginInner, forKey: .marginInner)
        try container.encode(marginOuter, forKey: .marginOuter)
        try container.encode(isPageNumberEnabled, forKey: .isPageNumberEnabled)
        try container.encodeIfPresent(pageNumberFontId, forKey: .pageNumberFontId)
        try container.encode(pageNumberSize, forKey: .pageNumberSize)
        try container.encode(pageNumberStart, forKey: .pageNumberStart)
        try container.encode(pageNumberPosition, forKey: .pageNumberPosition)
        try container.encode(showTableOfContents, forKey: .showTableOfContents)
        try container.encode(showChapterTitle, forKey: .showChapterTitle)
        try container.encode(chapterTitleStyle, forKey: .chapterTitleStyle)
        try container.encode(startsChapterOnNewPage, forKey: .startsChapterOnNewPage)
        try container.encode(alphanumericOrientation, forKey: .alphanumericOrientation)
        try container.encode(useRecommendedPrintSettings, forKey: .useRecommendedPrintSettings)
        try container.encode(showsCropMarks, forKey: .showsCropMarks)
        try container.encode(colophon, forKey: .colophon)
        try container.encode(formatSettings, forKey: .formatSettings)
    }

    private static func selectedFontIdFromLegacyJapaneseFont(_ font: JapaneseFont?) -> String {
        switch font?.regularized {
        case .hiraginoSans, .hiraginoMaruGothic:
            "biz-ud-gothic"
        case .hiraginoMincho:
            AppFontCatalog.defaultFontId
        case .none:
            AppFontCatalog.defaultFontId
        case .some(.hiraginoSansBold), .some(.hiraginoMinchoBold):
            AppFontCatalog.defaultFontId
        }
    }
}

nonisolated struct FormatSettings: Codable, Equatable {
    var enableAutoFormat: Bool
    var enableIndent: Bool
    var skipIndentBeforeOpeningQuote: Bool
    var enableTrimLineSpaces: Bool
    var enableNormalizeBlankLines: Bool
    var maxConsecutiveBlankLines: Int
    var enableNormalizePageBreakSpacing: Bool
    var enableNormalizeConsecutiveExclamationQuestion: Bool
    var enableNormalizeEllipsis: Bool
    var enableNormalizeDash: Bool
    var enableSpaceAfterExclamationQuestion: Bool
    var enableNormalizePunctuation: Bool
    var enableNormalizeBrackets: Bool

    static let `default` = FormatSettings(
        enableAutoFormat: false,
        enableIndent: false,
        skipIndentBeforeOpeningQuote: true,
        enableTrimLineSpaces: true,
        enableNormalizeBlankLines: true,
        maxConsecutiveBlankLines: 1,
        enableNormalizePageBreakSpacing: true,
        enableNormalizeConsecutiveExclamationQuestion: false,
        enableNormalizeEllipsis: false,
        enableNormalizeDash: false,
        enableSpaceAfterExclamationQuestion: false,
        enableNormalizePunctuation: false,
        enableNormalizeBrackets: false
    )

    var validated: FormatSettings {
        var validatedSettings = self
        validatedSettings.maxConsecutiveBlankLines = maxConsecutiveBlankLines.clamped(
            to: EditorSettings.maxConsecutiveBlankLinesRange
        )
        return validatedSettings
    }
}

nonisolated struct FormatOptions: Equatable {
    var isPremiumUser: Bool
}

nonisolated extension FormatSettings {
    private enum CodingKeys: String, CodingKey {
        case enableAutoFormat
        case enableIndent
        case skipIndentBeforeOpeningQuote
        case enableTrimLineSpaces
        case enableNormalizeBlankLines
        case maxConsecutiveBlankLines
        case enableNormalizePageBreakSpacing
        case enableNormalizeConsecutiveExclamationQuestion
        case enableNormalizeEllipsis
        case enableNormalizeDash
        case enableSpaceAfterExclamationQuestion
        case enableNormalizePunctuation
        case enableNormalizeBrackets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = FormatSettings.default

        self.init(
            enableAutoFormat: try container.decodeIfPresent(Bool.self, forKey: .enableAutoFormat) ?? defaults.enableAutoFormat,
            enableIndent: try container.decodeIfPresent(Bool.self, forKey: .enableIndent) ?? defaults.enableIndent,
            skipIndentBeforeOpeningQuote: try container.decodeIfPresent(Bool.self, forKey: .skipIndentBeforeOpeningQuote) ?? defaults.skipIndentBeforeOpeningQuote,
            enableTrimLineSpaces: try container.decodeIfPresent(Bool.self, forKey: .enableTrimLineSpaces) ?? defaults.enableTrimLineSpaces,
            enableNormalizeBlankLines: try container.decodeIfPresent(Bool.self, forKey: .enableNormalizeBlankLines) ?? defaults.enableNormalizeBlankLines,
            maxConsecutiveBlankLines: try container.decodeIfPresent(Int.self, forKey: .maxConsecutiveBlankLines) ?? defaults.maxConsecutiveBlankLines,
            enableNormalizePageBreakSpacing: try container.decodeIfPresent(Bool.self, forKey: .enableNormalizePageBreakSpacing) ?? defaults.enableNormalizePageBreakSpacing,
            enableNormalizeConsecutiveExclamationQuestion: try container.decodeIfPresent(Bool.self, forKey: .enableNormalizeConsecutiveExclamationQuestion) ?? defaults.enableNormalizeConsecutiveExclamationQuestion,
            enableNormalizeEllipsis: try container.decodeIfPresent(Bool.self, forKey: .enableNormalizeEllipsis) ?? defaults.enableNormalizeEllipsis,
            enableNormalizeDash: try container.decodeIfPresent(Bool.self, forKey: .enableNormalizeDash) ?? defaults.enableNormalizeDash,
            enableSpaceAfterExclamationQuestion: try container.decodeIfPresent(Bool.self, forKey: .enableSpaceAfterExclamationQuestion) ?? defaults.enableSpaceAfterExclamationQuestion,
            enableNormalizePunctuation: try container.decodeIfPresent(Bool.self, forKey: .enableNormalizePunctuation) ?? defaults.enableNormalizePunctuation,
            enableNormalizeBrackets: try container.decodeIfPresent(Bool.self, forKey: .enableNormalizeBrackets) ?? defaults.enableNormalizeBrackets
        )
    }
}

nonisolated struct ColophonSettings: Codable, Equatable {
    var isEnabled: Bool
    var writingDirection: ColophonWritingDirection
    var workTitle: String
    var publisherName: String
    var authorName: String
    var circleName: String
    var authorImageData: Data?
    var circleImageData: Data?
    var usesCircleImageForCreator: Bool
    var showsPublisherName: Bool
    var showsAuthorName: Bool
    var showsCircleName: Bool
    var showsWebsiteURL: Bool
    var showsQRCode: Bool
    var showsPublicationDate: Bool
    var showsPrinterName: Bool
    var publicationDate: Date?
    var printerName: String
    var websiteURL: String
    var xURL: String
    var pixivURL: String
    var contact: String
    var notes: String

    static let `default` = ColophonSettings(
        isEnabled: false,
        writingDirection: .horizontal,
        workTitle: "",
        publisherName: "",
        authorName: "",
        circleName: "",
        authorImageData: nil,
        circleImageData: nil,
        usesCircleImageForCreator: false,
        showsPublisherName: true,
        showsAuthorName: true,
        showsCircleName: true,
        showsWebsiteURL: true,
        showsQRCode: true,
        showsPublicationDate: true,
        showsPrinterName: true,
        publicationDate: nil,
        printerName: "",
        websiteURL: "",
        xURL: "",
        pixivURL: "",
        contact: "",
        notes: ""
    )

    var validated: ColophonSettings {
        ColophonSettings(
            isEnabled: isEnabled,
            writingDirection: .horizontal,
            workTitle: workTitle.trimmedForStorage,
            publisherName: publisherName.trimmedForStorage,
            authorName: authorName.trimmedForStorage,
            circleName: circleName.trimmedForStorage,
            authorImageData: authorImageData,
            circleImageData: circleImageData,
            usesCircleImageForCreator: usesCircleImageForCreator,
            showsPublisherName: showsPublisherName,
            showsAuthorName: showsAuthorName,
            showsCircleName: showsCircleName,
            showsWebsiteURL: showsWebsiteURL,
            showsQRCode: showsQRCode,
            showsPublicationDate: showsPublicationDate,
            showsPrinterName: showsPrinterName,
            publicationDate: publicationDate,
            printerName: printerName.trimmedForStorage,
            websiteURL: websiteURL.trimmedForStorage,
            xURL: xURL.trimmedForStorage,
            pixivURL: pixivURL.trimmedForStorage,
            contact: contact.trimmedForStorage,
            notes: notes.trimmedForStorage
        )
    }

    func applyingPublisherInfo(from publisherInfo: ColophonSettings) -> ColophonSettings {
        let publisherInfo = publisherInfo.validated
        var merged = self
        merged.publisherName = publisherInfo.publisherName
        merged.authorName = publisherInfo.authorName
        merged.circleName = publisherInfo.circleName
        merged.authorImageData = publisherInfo.authorImageData
        merged.circleImageData = publisherInfo.circleImageData
        merged.usesCircleImageForCreator = publisherInfo.usesCircleImageForCreator
        merged.showsPublisherName = publisherInfo.showsPublisherName
        merged.showsAuthorName = publisherInfo.showsAuthorName
        merged.showsCircleName = publisherInfo.showsCircleName
        merged.showsWebsiteURL = publisherInfo.showsWebsiteURL
        merged.showsQRCode = publisherInfo.showsQRCode
        merged.websiteURL = publisherInfo.websiteURL
        merged.xURL = publisherInfo.xURL
        merged.pixivURL = publisherInfo.pixivURL
        merged.contact = publisherInfo.contact
        merged.notes = publisherInfo.notes
        return merged.validated
    }

    var formattedPublicationDate: String {
        guard let publicationDate else { return "" }
        return Self.publicationDateFormatter.string(from: publicationDate)
    }

    private static let publicationDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()
}

nonisolated enum AlphanumericOrientation: String, Codable, CaseIterable, Identifiable {
    case stacked
    case sideways
    case tateChuYoko

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stacked:
            "縦積み"
        case .sideways:
            "横倒し"
        case .tateChuYoko:
            "縦中横"
        }
    }
}

nonisolated enum ColophonWritingDirection: String, Codable, CaseIterable, Identifiable {
    case vertical
    case horizontal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vertical:
            "縦書き"
        case .horizontal:
            "横書き"
        }
    }
}

nonisolated extension ColophonSettings {
    var creatorImageData: [Data] {
        guard usesCircleImageForCreator, let circleImageData else { return [] }
        return [circleImageData]
    }

    var hasCreatorImage: Bool {
        !creatorImageData.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case writingDirection
        case workTitle
        case publisherName
        case authorName
        case circleName
        case authorImageData
        case circleImageData
        case usesCircleImageForCreator
        case showsPublisherName
        case showsAuthorName
        case showsCircleName
        case showsWebsiteURL
        case showsQRCode
        case showsPublicationDate
        case showsPrinterName
        case publicationDate
        case printerName
        case websiteURL
        case xURL
        case pixivURL
        case contact
        case notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ColophonSettings.default

        self.init(
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? defaults.isEnabled,
            writingDirection: try container.decodeIfPresent(ColophonWritingDirection.self, forKey: .writingDirection) ?? defaults.writingDirection,
            workTitle: try container.decodeIfPresent(String.self, forKey: .workTitle) ?? defaults.workTitle,
            publisherName: try container.decodeIfPresent(String.self, forKey: .publisherName) ?? defaults.publisherName,
            authorName: try container.decodeIfPresent(String.self, forKey: .authorName) ?? defaults.authorName,
            circleName: try container.decodeIfPresent(String.self, forKey: .circleName) ?? defaults.circleName,
            authorImageData: try container.decodeIfPresent(Data.self, forKey: .authorImageData),
            circleImageData: try container.decodeIfPresent(Data.self, forKey: .circleImageData),
            usesCircleImageForCreator: try container.decodeIfPresent(Bool.self, forKey: .usesCircleImageForCreator) ?? defaults.usesCircleImageForCreator,
            showsPublisherName: try container.decodeIfPresent(Bool.self, forKey: .showsPublisherName) ?? defaults.showsPublisherName,
            showsAuthorName: try container.decodeIfPresent(Bool.self, forKey: .showsAuthorName) ?? defaults.showsAuthorName,
            showsCircleName: try container.decodeIfPresent(Bool.self, forKey: .showsCircleName) ?? defaults.showsCircleName,
            showsWebsiteURL: try container.decodeIfPresent(Bool.self, forKey: .showsWebsiteURL) ?? defaults.showsWebsiteURL,
            showsQRCode: try container.decodeIfPresent(Bool.self, forKey: .showsQRCode) ?? defaults.showsQRCode,
            showsPublicationDate: try container.decodeIfPresent(Bool.self, forKey: .showsPublicationDate) ?? defaults.showsPublicationDate,
            showsPrinterName: try container.decodeIfPresent(Bool.self, forKey: .showsPrinterName) ?? defaults.showsPrinterName,
            publicationDate: Self.decodePublicationDate(from: container),
            printerName: try container.decodeIfPresent(String.self, forKey: .printerName) ?? defaults.printerName,
            websiteURL: try container.decodeIfPresent(String.self, forKey: .websiteURL) ?? defaults.websiteURL,
            xURL: try container.decodeIfPresent(String.self, forKey: .xURL) ?? defaults.xURL,
            pixivURL: try container.decodeIfPresent(String.self, forKey: .pixivURL) ?? defaults.pixivURL,
            contact: try container.decodeIfPresent(String.self, forKey: .contact) ?? defaults.contact,
            notes: try container.decodeIfPresent(String.self, forKey: .notes) ?? defaults.notes
        )
    }

    private static func decodePublicationDate(from container: KeyedDecodingContainer<CodingKeys>) -> Date? {
        if let date = try? container.decodeIfPresent(Date.self, forKey: .publicationDate) {
            return date
        }

        guard let string = try? container.decodeIfPresent(String.self, forKey: .publicationDate) else {
            return nil
        }

        return legacyPublicationDateFormatters.compactMap { $0.date(from: string) }.first
    }

    private static let legacyPublicationDateFormatters: [DateFormatter] = {
        ["yyyy年M月d日", "yyyy/M/d", "yyyy-MM-dd"].map { format in
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateFormat = format
            return formatter
        }
    }()
}

nonisolated private extension String {
    var trimmedForStorage: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
