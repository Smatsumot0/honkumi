import CoreGraphics
import Foundation

nonisolated struct VerticalGlyphLayout: Equatable {
    let text: String
    let rotationDegrees: Double
    let fontScale: CGFloat
    let xOffset: CGFloat
    let yOffset: CGFloat
    let isPunctuation: Bool
    let disablesCharacterSpacing: Bool

    init(
        _ text: String,
        rotationDegrees: Double = 0,
        fontScale: CGFloat = 1,
        xOffset: CGFloat = 0,
        yOffset: CGFloat = 0,
        isPunctuation: Bool = false,
        disablesCharacterSpacing: Bool = false
    ) {
        self.text = text
        self.rotationDegrees = rotationDegrees
        self.fontScale = fontScale
        self.xOffset = xOffset
        self.yOffset = yOffset
        self.isPunctuation = isPunctuation
        self.disablesCharacterSpacing = disablesCharacterSpacing
    }
}

nonisolated struct VerticalTextLayoutUnit: Equatable {
    let text: String
    let cellSpan: Int

    init(_ text: String, cellSpan: Int = 1) {
        self.text = text
        self.cellSpan = max(cellSpan, 1)
    }
}

nonisolated struct VerticalGlyphAdjustment: Equatable {
    let fontScale: CGFloat
    let xOffset: CGFloat
    let yOffset: CGFloat
}

nonisolated enum VerticalGlyphMetrics {
    static let punctuation = VerticalGlyphAdjustment(
        fontScale: 0.64,
        xOffset: 0.10,
        yOffset: -0.04
    )
    static let punctuationAfterBaseYOffset: CGFloat = 0.30
    static let punctuationOverflowYOffset: CGFloat = 0.30

    static let smallKana = VerticalGlyphAdjustment(
        fontScale: 0.76,
        xOffset: 0.06,
        yOffset: -0.06
    )

    static let bracketFontScale: CGFloat = 0.88
    static let narrowSymbolFontScale: CGFloat = 0.86
    static let ellipsisFontScale: CGFloat = 0.86
    static let sidewaysAlphanumericFontScale: CGFloat = 0.72
    static let tateChuYokoFontScale: CGFloat = 0.72
    static let closingBracketAfterBaseOffset = CGPoint(x: -0.03, y: 0.30)
    static let stackedGlyphOverflowYOffset: CGFloat = -0.16

    static func centeredRunYOffset(cellSpan: Int) -> CGFloat {
        CGFloat(max(cellSpan, 1) - 1) / 2
    }
}

nonisolated enum VerticalTextTypesetter {
    static func cells(
        from column: String,
        alphanumericOrientation: AlphanumericOrientation
    ) -> [[String]] {
        layoutUnits(from: column, alphanumericOrientation: alphanumericOrientation)
            .flatMap { unit in
                var cells = [cellCharacters(for: unit.text)]
                if unit.cellSpan > 1 {
                    cells.append(contentsOf: Array(repeating: [], count: unit.cellSpan - 1))
                }
                return cells
            }
    }

    static func layoutUnits(
        from text: String,
        alphanumericOrientation: AlphanumericOrientation
    ) -> [VerticalTextLayoutUnit] {
        let characters = text.map(String.init)
        var units: [VerticalTextLayoutUnit] = []
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if isEllipsis(character) {
                let run = ellipsisRun(in: characters, startingAt: index)
                for chunk in ellipsisChunks(from: run.text) {
                    units.append(VerticalTextLayoutUnit(chunk, cellSpan: chunk.count))
                }
                index = run.endIndex
            } else if isExclamationQuestion(character),
                      characters.indices.contains(index + 1),
                      isExclamationQuestion(characters[index + 1]) {
                units.append(VerticalTextLayoutUnit(character + characters[index + 1]))
                index += 2
            } else if isHalfWidthRunStart(character) {
                let run = halfWidthRun(in: characters, startingAt: index)
                units.append(VerticalTextLayoutUnit(
                    run.text,
                    cellSpan: alphanumericCellSpan(for: run.text)
                ))
                index = run.endIndex
            } else if isPunctuation(character),
                      characters.indices.contains(index + 1),
                      isClosingQuote(characters[index + 1]) {
                units.append(VerticalTextLayoutUnit(character + characters[index + 1]))
                index += 2
            } else {
                units.append(VerticalTextLayoutUnit(character))
                index += 1
            }
        }

        return units
    }

    static func cellCount(
        for text: String,
        alphanumericOrientation: AlphanumericOrientation
    ) -> Int {
        layoutUnits(from: text, alphanumericOrientation: alphanumericOrientation)
            .reduce(0) { $0 + $1.cellSpan }
    }

    private static func cellCharacters(for text: String) -> [String] {
        if isExclamationQuestionPair(text)
            || isAlphanumericRun(text)
            || isEllipsisRun(text) {
            return [text]
        }

        return text.map(String.init)
    }

    static func adjustedCharacterAdvance(
        cellCount: Int,
        characterCount: Int,
        bodyHeight: CGFloat,
        rowHeight: CGFloat
    ) -> CGFloat {
        guard cellCount > 1 else { return rowHeight }
        guard cellCount > characterCount || cellCount >= characterCount - 2 else {
            return rowHeight
        }

        return max((bodyHeight - rowHeight) / CGFloat(cellCount - 1), 1)
    }

    static func glyph(
        for character: String,
        alphanumericOrientation: AlphanumericOrientation
    ) -> VerticalGlyphLayout {
        if isExclamationQuestionPair(character) {
            return VerticalGlyphLayout(
                character,
                fontScale: VerticalGlyphMetrics.tateChuYokoFontScale,
                disablesCharacterSpacing: true
            )
        }

        if isAlphanumericRun(character) {
            let reservedCellCount = sidewaysRunCellSpan(for: character)
            return VerticalGlyphLayout(
                character,
                rotationDegrees: 90,
                fontScale: VerticalGlyphMetrics.sidewaysAlphanumericFontScale,
                yOffset: VerticalGlyphMetrics.centeredRunYOffset(cellSpan: reservedCellCount),
                disablesCharacterSpacing: true
            )
        }

        if isEllipsisRun(character) {
            return VerticalGlyphLayout(
                character,
                rotationDegrees: 90,
                fontScale: VerticalGlyphMetrics.ellipsisFontScale,
                yOffset: VerticalGlyphMetrics.centeredRunYOffset(cellSpan: character.count),
                disablesCharacterSpacing: true
            )
        }

        return switch character {
        case "「":
            VerticalGlyphLayout("﹁", fontScale: VerticalGlyphMetrics.bracketFontScale)
        case "」":
            VerticalGlyphLayout("﹂", fontScale: VerticalGlyphMetrics.bracketFontScale)
        case "『":
            VerticalGlyphLayout("﹃", fontScale: VerticalGlyphMetrics.bracketFontScale)
        case "』":
            VerticalGlyphLayout("﹄", fontScale: VerticalGlyphMetrics.bracketFontScale)
        case "（", "(":
            VerticalGlyphLayout("︵", fontScale: VerticalGlyphMetrics.bracketFontScale)
        case "）", ")":
            VerticalGlyphLayout("︶", fontScale: VerticalGlyphMetrics.bracketFontScale)
        case "【":
            VerticalGlyphLayout("︻", fontScale: VerticalGlyphMetrics.bracketFontScale)
        case "】":
            VerticalGlyphLayout("︼", fontScale: VerticalGlyphMetrics.bracketFontScale)
        case "［", "[":
            VerticalGlyphLayout("﹇", fontScale: VerticalGlyphMetrics.bracketFontScale)
        case "］", "]":
            VerticalGlyphLayout("﹈", fontScale: VerticalGlyphMetrics.bracketFontScale)
        case "｛", "{":
            VerticalGlyphLayout("︷", fontScale: VerticalGlyphMetrics.bracketFontScale)
        case "｝", "}":
            VerticalGlyphLayout("︸", fontScale: VerticalGlyphMetrics.bracketFontScale)
        case "〈":
            VerticalGlyphLayout("︿", fontScale: VerticalGlyphMetrics.bracketFontScale)
        case "〉":
            VerticalGlyphLayout("﹀", fontScale: VerticalGlyphMetrics.bracketFontScale)
        case "《":
            VerticalGlyphLayout("︽", fontScale: VerticalGlyphMetrics.bracketFontScale)
        case "》":
            VerticalGlyphLayout("︾", fontScale: VerticalGlyphMetrics.bracketFontScale)
        case "〜", "～":
            VerticalGlyphLayout(
                character,
                rotationDegrees: 90,
                fontScale: VerticalGlyphMetrics.narrowSymbolFontScale
            )
        case "、", "。", "､", "｡", "，", "．", "︑", "︒", "︐":
            VerticalGlyphLayout(
                character,
                fontScale: VerticalGlyphMetrics.punctuation.fontScale,
                xOffset: VerticalGlyphMetrics.punctuation.xOffset,
                yOffset: VerticalGlyphMetrics.punctuation.yOffset,
                isPunctuation: true
            )
        case "ぁ", "ぃ", "ぅ", "ぇ", "ぉ", "っ", "ゃ", "ゅ", "ょ",
             "ゎ",
             "ァ", "ィ", "ゥ", "ェ", "ォ", "ッ", "ャ", "ュ", "ョ",
             "ヮ", "ヵ", "ヶ":
            VerticalGlyphLayout(
                character,
                fontScale: VerticalGlyphMetrics.smallKana.fontScale,
                xOffset: VerticalGlyphMetrics.smallKana.xOffset,
                yOffset: VerticalGlyphMetrics.smallKana.yOffset
            )
        case "ー":
            VerticalGlyphLayout(
                character,
                rotationDegrees: 90,
                fontScale: VerticalGlyphMetrics.narrowSymbolFontScale
            )
        case "─", "━", "―", "—":
            VerticalGlyphLayout(character, rotationDegrees: 90, fontScale: 1.05)
        default:
            VerticalGlyphLayout(character)
        }
    }

    static func glyphOffset(
        glyph: VerticalGlyphLayout,
        character: String,
        characters: [String],
        index: Int,
        columnWidth: CGFloat,
        rowHeight: CGFloat
    ) -> CGSize {
        let normalized: CGPoint

        if index > 0, glyph.isPunctuation, characters.first.map(isPunctuation) == false {
            normalized = CGPoint(
                x: glyph.xOffset,
                y: VerticalGlyphMetrics.punctuationAfterBaseYOffset
            )
        } else if index > 0, isClosingQuote(character), characters.first.map(isPunctuation) == false {
            normalized = VerticalGlyphMetrics.closingBracketAfterBaseOffset
        } else if index > 0, isClosingQuote(character), characters.first.map(isPunctuation) == true {
            normalized = VerticalGlyphMetrics.closingBracketAfterBaseOffset
        } else {
            normalized = CGPoint(
                x: glyph.xOffset,
                y: glyph.yOffset + overflowYOffset(index: index, glyph: glyph)
            )
        }

        return CGSize(width: normalized.x * columnWidth, height: normalized.y * rowHeight)
    }

    static func isPunctuation(_ character: String) -> Bool {
        punctuationCharacters.contains(character)
    }

    static func isClosingQuote(_ character: String) -> Bool {
        closingQuoteCharacters.contains(character)
    }

    static func isSmallKana(_ character: String) -> Bool {
        smallKanaCharacters.contains(character)
    }

    static func isDashLike(_ character: String) -> Bool {
        dashLikeCharacters.contains(character)
    }

    static func isDashConnector(_ character: String) -> Bool {
        dashConnectorCharacters.contains(character)
    }

    static func isAlphanumericRun(_ text: String) -> Bool {
        !text.isEmpty
            && text.unicodeScalars.contains(where: { $0.value != 0x20 })
            && text.unicodeScalars.allSatisfy(isHalfWidthRunScalar)
    }

    static func isLineStartProhibited(_ text: String?) -> Bool {
        guard let firstCharacter = text?.first.map(String.init) else { return false }
        return lineStartProhibitedCharacters.contains(firstCharacter)
    }

    static func isLineEndProhibited(_ text: String?) -> Bool {
        guard let lastCharacter = text?.last.map(String.init) else { return false }
        return lineEndProhibitedCharacters.contains(lastCharacter)
    }

    static func formsNonBreakingPair(_ first: String?, _ second: String) -> Bool {
        guard let firstCharacter = first?.last.map(String.init),
              let secondCharacter = second.first.map(String.init) else {
            return false
        }
        if let first, isEllipsisRun(first), isPunctuation(secondCharacter) {
            return true
        }
        if let first, isExclamationQuestionPair(first), isClosingQuote(secondCharacter) {
            return true
        }
        return nonBreakingPairs.contains(firstCharacter + secondCharacter)
    }

    private static func overflowYOffset(index: Int, glyph: VerticalGlyphLayout) -> CGFloat {
        guard index > 0 else { return 0 }
        return glyph.isPunctuation
            ? VerticalGlyphMetrics.punctuationOverflowYOffset
            : VerticalGlyphMetrics.stackedGlyphOverflowYOffset * CGFloat(index)
    }

    private static func isExclamationQuestion(_ character: String) -> Bool {
        exclamationQuestionCharacters.contains(character)
    }

    private static func isExclamationQuestionPair(_ text: String) -> Bool {
        text.count == 2 && text.map(String.init).allSatisfy(isExclamationQuestion)
    }

    private static func isEllipsisRun(_ text: String) -> Bool {
        !text.isEmpty && text.map(String.init).allSatisfy(isEllipsis)
    }

    private static func halfWidthRun(
        in characters: [String],
        startingAt index: Int
    ) -> (text: String, endIndex: Int) {
        var run = ""
        var cursor = index

        while cursor < characters.count, isHalfWidthRunCharacter(characters[cursor]) {
            run += characters[cursor]
            cursor += 1
        }

        while run.last == " " {
            run.removeLast()
            cursor -= 1
        }

        return (run, max(cursor, index + 1))
    }

    private static func ellipsisRun(
        in characters: [String],
        startingAt index: Int
    ) -> (text: String, endIndex: Int) {
        var run = ""
        var cursor = index

        while cursor < characters.count, isEllipsis(characters[cursor]) {
            run += characters[cursor]
            cursor += 1
        }

        return (run, cursor)
    }

    private static func ellipsisChunks(from run: String) -> [String] {
        let characters = run.map(String.init)
        var chunks: [String] = []
        var index = 0

        while index < characters.count {
            let nextIndex = min(index + 2, characters.count)
            chunks.append(characters[index..<nextIndex].joined())
            index = nextIndex
        }

        return chunks
    }

    private static func alphanumericCellSpan(for text: String) -> Int {
        sidewaysRunCellSpan(for: text)
    }

    private static func sidewaysRunCellSpan(for text: String) -> Int {
        let widthInEms = text.unicodeScalars.reduce(CGFloat(0)) { partialResult, scalar in
            partialResult + sidewaysScalarWidthInEms(scalar)
        }
        return max(1, Int(ceil(widthInEms * 0.72 + 0.3)))
    }

    private static func sidewaysScalarWidthInEms(_ scalar: UnicodeScalar) -> CGFloat {
        switch scalar.value {
        case 73, 105, 108, 46, 58, 59, 33, 39, 96, 124:
            0.28
        case 74, 106, 114, 116, 102:
            0.38
        case 77, 87, 109, 119:
            0.78
        case 48...57:
            0.52
        case 65...90:
            0.62
        case 32:
            0.32
        case 45, 95, 43, 47:
            0.36
        default:
            0.56
        }
    }

    private static func isHalfWidthRunStart(_ character: String) -> Bool {
        character.unicodeScalars.count == 1
            && character.unicodeScalars.allSatisfy { scalar in
                scalar.value >= 0x21 && scalar.value <= 0x7E
            }
    }

    private static func isHalfWidthRunCharacter(_ character: String) -> Bool {
        character.unicodeScalars.count == 1
            && character.unicodeScalars.allSatisfy(isHalfWidthRunScalar)
    }

    private static func isHalfWidthRunScalar(_ scalar: UnicodeScalar) -> Bool {
        (0x20...0x7E).contains(scalar.value)
    }

    private static func isEllipsis(_ character: String) -> Bool {
        ellipsisCharacters.contains(character)
    }

    private static let punctuationCharacters: Set<String> = [
        "、", "。", "､", "｡", "，", "．", "︑", "︒", "︐"
    ]

    private static let closingQuoteCharacters: Set<String> = [
        "」", "』", "）", "】", "〉", "》", "］", "｝"
    ]

    private static let smallKanaCharacters: Set<String> = [
        "ぁ", "ぃ", "ぅ", "ぇ", "ぉ", "っ", "ゃ", "ゅ", "ょ",
        "ゎ",
        "ァ", "ィ", "ゥ", "ェ", "ォ", "ッ", "ャ", "ュ", "ョ",
        "ヮ", "ヵ", "ヶ"
    ]

    private static let dashLikeCharacters: Set<String> = [
        "―", "─", "━", "—", "ー", "〜", "～", "…", "‥"
    ]

    private static let dashConnectorCharacters: Set<String> = [
        "―", "─", "━", "—"
    ]

    private static let exclamationQuestionCharacters: Set<String> = [
        "!", "?", "！", "？"
    ]

    private static let ellipsisCharacters: Set<String> = [
        "…", "‥"
    ]

    private static let lineStartProhibitedCharacters: Set<String> = [
        "、", "。", "，", "．", "︑", "︒", "︐", "・", "：", "；",
        "！", "？", "!", "?",
        "」", "』", "）", "】", "》", "〉", "］", "｝",
        "ぁ", "ぃ", "ぅ", "ぇ", "ぉ", "っ", "ゃ", "ゅ", "ょ", "ゎ",
        "ァ", "ィ", "ゥ", "ェ", "ォ", "ッ", "ャ", "ュ", "ョ", "ヮ", "ヵ", "ヶ",
        "ー", "─", "━", "―", "—", "々", "ゝ", "ゞ"
    ]

    private static let lineEndProhibitedCharacters: Set<String> = [
        "「", "『", "（", "【", "《", "〈", "［", "｛"
    ]

    private static let nonBreakingPairs: Set<String> = [
        "……", "‥‥", "──", "――", "——", "！？", "？！", "!!", "??", "!?", "?!"
    ]
}
