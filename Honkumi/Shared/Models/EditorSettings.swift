import CoreGraphics
import Foundation

struct EditorSettings: Codable, Equatable {
    static let fontSizeRange: ClosedRange<CGFloat> = 8...14
    static let charactersPerLineRange: ClosedRange<Int> = 25...45
    static let linesPerPageRange: ClosedRange<Int> = 10...24
    static let marginTopRange: ClosedRange<CGFloat> = 8...30
    static let marginBottomRange: ClosedRange<CGFloat> = 8...30
    static let marginInnerRange: ClosedRange<CGFloat> = 10...30
    static let marginOuterRange: ClosedRange<CGFloat> = 8...25
    static let lineSpacingRange: ClosedRange<CGFloat> = 0...8
    static let characterSpacingRange: ClosedRange<CGFloat> = 0...4
    static let maxConsecutiveBlankLinesRange: ClosedRange<Int> = 0...5

    var pageSize: PageSize
    var japaneseFont: JapaneseFont
    var fontSize: CGFloat
    var lineSpacing: CGFloat
    var characterSpacing: CGFloat
    var charactersPerLine: Int
    var linesPerPage: Int
    var marginTop: CGFloat
    var marginBottom: CGFloat
    var marginInner: CGFloat
    var marginOuter: CGFloat
    var pageNumberPosition: PageNumberPosition
    var showTableOfContents: Bool
    var showChapterTitle: Bool
    var chapterTitleStyle: ChapterTitleStyle
    var startsChapterOnNewPage: Bool
    var colophon: ColophonSettings
    var formatSettings: FormatSettings

    init(
        pageSize: PageSize,
        japaneseFont: JapaneseFont,
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        characterSpacing: CGFloat,
        charactersPerLine: Int,
        linesPerPage: Int,
        marginTop: CGFloat,
        marginBottom: CGFloat,
        marginInner: CGFloat,
        marginOuter: CGFloat,
        pageNumberPosition: PageNumberPosition,
        showTableOfContents: Bool,
        showChapterTitle: Bool,
        chapterTitleStyle: ChapterTitleStyle,
        startsChapterOnNewPage: Bool,
        colophon: ColophonSettings = .default,
        formatSettings: FormatSettings = .default
    ) {
        self.pageSize = pageSize
        self.japaneseFont = japaneseFont
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.characterSpacing = characterSpacing
        self.charactersPerLine = charactersPerLine
        self.linesPerPage = linesPerPage
        self.marginTop = marginTop
        self.marginBottom = marginBottom
        self.marginInner = marginInner
        self.marginOuter = marginOuter
        self.pageNumberPosition = pageNumberPosition
        self.showTableOfContents = showTableOfContents
        self.showChapterTitle = showChapterTitle
        self.chapterTitleStyle = chapterTitleStyle
        self.startsChapterOnNewPage = startsChapterOnNewPage
        self.colophon = colophon
        self.formatSettings = formatSettings
    }

    static let `default` = EditorSettings(
        pageSize: .a6,
        japaneseFont: .hiraginoMincho,
        fontSize: 9,
        lineSpacing: 0,
        characterSpacing: 0,
        charactersPerLine: 37,
        linesPerPage: 17,
        marginTop: 18,
        marginBottom: 15,
        marginInner: 10,
        marginOuter: 10,
        pageNumberPosition: .center,
        showTableOfContents: false,
        showChapterTitle: false,
        chapterTitleStyle: .plain,
        startsChapterOnNewPage: false,
        colophon: .default,
        formatSettings: .default
    )

    var validated: EditorSettings {
        EditorSettings(
            pageSize: pageSize,
            japaneseFont: japaneseFont.regularized,
            fontSize: fontSize.clamped(to: Self.fontSizeRange),
            lineSpacing: lineSpacing.clamped(to: Self.lineSpacingRange),
            characterSpacing: characterSpacing.clamped(to: Self.characterSpacingRange),
            charactersPerLine: charactersPerLine.clamped(to: Self.charactersPerLineRange),
            linesPerPage: linesPerPage.clamped(to: Self.linesPerPageRange),
            marginTop: marginTop.clamped(to: Self.marginTopRange),
            marginBottom: marginBottom.clamped(to: Self.marginBottomRange),
            marginInner: marginInner.clamped(to: Self.marginInnerRange),
            marginOuter: marginOuter.clamped(to: Self.marginOuterRange),
            pageNumberPosition: pageNumberPosition,
            showTableOfContents: showTableOfContents,
            showChapterTitle: showChapterTitle,
            chapterTitleStyle: chapterTitleStyle,
            startsChapterOnNewPage: startsChapterOnNewPage,
            colophon: colophon.validated,
            formatSettings: formatSettings.validated
        )
    }
}

extension EditorSettings {
    private enum CodingKeys: String, CodingKey {
        case pageSize
        case japaneseFont
        case fontSize
        case lineSpacing
        case characterSpacing
        case charactersPerLine
        case linesPerPage
        case marginTop
        case marginBottom
        case marginInner
        case marginOuter
        case pageNumberPosition
        case showTableOfContents
        case showChapterTitle
        case chapterTitleStyle
        case startsChapterOnNewPage
        case colophon
        case formatSettings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = EditorSettings.default

        self.init(
            pageSize: try container.decodeIfPresent(PageSize.self, forKey: .pageSize) ?? defaults.pageSize,
            japaneseFont: try container.decodeIfPresent(JapaneseFont.self, forKey: .japaneseFont) ?? defaults.japaneseFont,
            fontSize: try container.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? defaults.fontSize,
            lineSpacing: try container.decodeIfPresent(CGFloat.self, forKey: .lineSpacing) ?? defaults.lineSpacing,
            characterSpacing: try container.decodeIfPresent(CGFloat.self, forKey: .characterSpacing) ?? defaults.characterSpacing,
            charactersPerLine: try container.decodeIfPresent(Int.self, forKey: .charactersPerLine) ?? defaults.charactersPerLine,
            linesPerPage: try container.decodeIfPresent(Int.self, forKey: .linesPerPage) ?? defaults.linesPerPage,
            marginTop: try container.decodeIfPresent(CGFloat.self, forKey: .marginTop) ?? defaults.marginTop,
            marginBottom: try container.decodeIfPresent(CGFloat.self, forKey: .marginBottom) ?? defaults.marginBottom,
            marginInner: try container.decodeIfPresent(CGFloat.self, forKey: .marginInner) ?? defaults.marginInner,
            marginOuter: try container.decodeIfPresent(CGFloat.self, forKey: .marginOuter) ?? defaults.marginOuter,
            pageNumberPosition: try container.decodeIfPresent(PageNumberPosition.self, forKey: .pageNumberPosition) ?? defaults.pageNumberPosition,
            showTableOfContents: try container.decodeIfPresent(Bool.self, forKey: .showTableOfContents) ?? defaults.showTableOfContents,
            showChapterTitle: try container.decodeIfPresent(Bool.self, forKey: .showChapterTitle) ?? defaults.showChapterTitle,
            chapterTitleStyle: try container.decodeIfPresent(ChapterTitleStyle.self, forKey: .chapterTitleStyle) ?? defaults.chapterTitleStyle,
            startsChapterOnNewPage: try container.decodeIfPresent(Bool.self, forKey: .startsChapterOnNewPage) ?? defaults.startsChapterOnNewPage,
            colophon: try container.decodeIfPresent(ColophonSettings.self, forKey: .colophon) ?? defaults.colophon,
            formatSettings: try container.decodeIfPresent(FormatSettings.self, forKey: .formatSettings) ?? defaults.formatSettings
        )
    }
}

struct FormatSettings: Codable, Equatable {
    var enableIndent: Bool
    var skipIndentBeforeOpeningQuote: Bool
    var enableTrimLineSpaces: Bool
    var enableNormalizeBlankLines: Bool
    var maxConsecutiveBlankLines: Int
    var enableNormalizePageBreakSpacing: Bool
    var enableNormalizeEllipsis: Bool
    var enableNormalizeDash: Bool
    var enableSpaceAfterExclamationQuestion: Bool
    var enableNormalizePunctuation: Bool
    var enableNormalizeBrackets: Bool

    static let `default` = FormatSettings(
        enableIndent: false,
        skipIndentBeforeOpeningQuote: true,
        enableTrimLineSpaces: true,
        enableNormalizeBlankLines: true,
        maxConsecutiveBlankLines: 1,
        enableNormalizePageBreakSpacing: true,
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

struct FormatOptions: Equatable {
    var isPremiumUser: Bool
}

struct ColophonSettings: Codable, Equatable {
    var isEnabled: Bool
    var writingDirection: ColophonWritingDirection
    var workTitle: String
    var authorName: String
    var circleName: String
    var authorImageData: Data?
    var circleImageData: Data?
    var usesCircleImageForCreator: Bool
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
        authorName: "",
        circleName: "",
        authorImageData: nil,
        circleImageData: nil,
        usesCircleImageForCreator: false,
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
            authorName: authorName.trimmedForStorage,
            circleName: circleName.trimmedForStorage,
            authorImageData: authorImageData,
            circleImageData: circleImageData,
            usesCircleImageForCreator: usesCircleImageForCreator,
            publicationDate: publicationDate,
            printerName: printerName.trimmedForStorage,
            websiteURL: websiteURL.trimmedForStorage,
            xURL: xURL.trimmedForStorage,
            pixivURL: pixivURL.trimmedForStorage,
            contact: contact.trimmedForStorage,
            notes: notes.trimmedForStorage
        )
    }

    var formattedPublicationDate: String {
        guard let publicationDate else { return "" }
        return Self.publicationDateFormatter.string(from: publicationDate)
    }

    private static let publicationDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()
}

enum ColophonWritingDirection: String, Codable, CaseIterable, Identifiable {
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

extension ColophonSettings {
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
        case authorName
        case circleName
        case authorImageData
        case circleImageData
        case usesCircleImageForCreator
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
            authorName: try container.decodeIfPresent(String.self, forKey: .authorName) ?? defaults.authorName,
            circleName: try container.decodeIfPresent(String.self, forKey: .circleName) ?? defaults.circleName,
            authorImageData: try container.decodeIfPresent(Data.self, forKey: .authorImageData),
            circleImageData: try container.decodeIfPresent(Data.self, forKey: .circleImageData),
            usesCircleImageForCreator: try container.decodeIfPresent(Bool.self, forKey: .usesCircleImageForCreator) ?? defaults.usesCircleImageForCreator,
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

private extension String {
    var trimmedForStorage: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
