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
        startsChapterOnNewPage: Bool
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
        startsChapterOnNewPage: false
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
            startsChapterOnNewPage: startsChapterOnNewPage
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
            startsChapterOnNewPage: try container.decodeIfPresent(Bool.self, forKey: .startsChapterOnNewPage) ?? defaults.startsChapterOnNewPage
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
