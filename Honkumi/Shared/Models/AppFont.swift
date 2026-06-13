import CoreText
import SwiftUI
import UIKit

nonisolated enum AppFontCategory: String, Codable, CaseIterable, Identifiable {
    case standard
    case novel
    case proofreading

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard:
            "標準"
        case .novel:
            "小説本文向け"
        case .proofreading:
            "読みやすさ・校閲向け"
        }
    }
}

nonisolated struct AppFont: Identifiable, Equatable {
    let id: String
    let displayName: String
    let postScriptName: String?
    let fileName: String?
    let isPremium: Bool
    let category: AppFontCategory
    let licenseName: String
    let copyrightText: String
}

nonisolated enum PageNumberFontCategory: String, Codable, CaseIterable, Identifiable {
    case romantic
    case script
    case handwriting
    case pop

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .romantic:
            "ハート・ロマンチック"
        case .script:
            "筆記体"
        case .handwriting:
            "手書き"
        case .pop:
            "ポップ"
        }
    }
}

nonisolated struct PageNumberFont: Identifiable, Equatable {
    let id: String
    let displayName: String
    let postScriptName: String
    let fileName: String
    let category: PageNumberFontCategory
    let licenseName: String
    let copyrightText: String

    /// Multiplier for UI previews. PDF output uses explicit point-size adjustments below.
    let sizeMultiplier: CGFloat
    let usesDotLeaderInTableOfContents: Bool

    init(
        id: String,
        displayName: String,
        postScriptName: String,
        fileName: String,
        category: PageNumberFontCategory,
        licenseName: String,
        copyrightText: String,
        sizeMultiplier: CGFloat = 1,
        usesDotLeaderInTableOfContents: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.postScriptName = postScriptName
        self.fileName = fileName
        self.category = category
        self.licenseName = licenseName
        self.copyrightText = copyrightText
        self.sizeMultiplier = sizeMultiplier
        self.usesDotLeaderInTableOfContents = usesDotLeaderInTableOfContents
    }
}

nonisolated struct PDFBodyFontSizeAdjustment: Equatable {
    let tableOfContentsDelta: CGFloat
    let pageNumberDelta: CGFloat
    let exclamationQuestionDelta: CGFloat
    let longVowelDelta: CGFloat
    let longVowelYOffset: CGFloat

    init(
        tableOfContentsDelta: CGFloat = 0,
        pageNumberDelta: CGFloat = 0,
        exclamationQuestionDelta: CGFloat = 0,
        longVowelDelta: CGFloat = 0,
        longVowelYOffset: CGFloat = 0
    ) {
        self.tableOfContentsDelta = tableOfContentsDelta
        self.pageNumberDelta = pageNumberDelta
        self.exclamationQuestionDelta = exclamationQuestionDelta
        self.longVowelDelta = longVowelDelta
        self.longVowelYOffset = longVowelYOffset
    }
}

nonisolated struct PDFPageNumberFontSizeAdjustment: Equatable {
    let tableOfContentsDelta: CGFloat
    let pageNumberDelta: CGFloat

    init(
        tableOfContentsDelta: CGFloat = 0,
        pageNumberDelta: CGFloat = 0
    ) {
        self.tableOfContentsDelta = tableOfContentsDelta
        self.pageNumberDelta = pageNumberDelta
    }
}

nonisolated enum AppFontCatalog {
    static let defaultFontId = "biz-ud-mincho"
    private static let gothicFallbackFontId = "biz-ud-gothic"
    private static let legacyFontReplacements: [String: String] = [
        "source-han-serif-jp": defaultFontId,
        "noto-serif-jp": defaultFontId,
        "source-han-sans-jp": gothicFallbackFontId,
        "noto-sans-jp": gothicFallbackFontId,
        "ibm-plex-sans-jp": gothicFallbackFontId
    ]
    private static let bodyPDFFontSizeAdjustments: [String: PDFBodyFontSizeAdjustment] = [
        defaultFontId: PDFBodyFontSizeAdjustment(
            tableOfContentsDelta: 3,
            pageNumberDelta: -1,
            exclamationQuestionDelta: 1
        ),
        "biz-ud-gothic": PDFBodyFontSizeAdjustment(
            tableOfContentsDelta: 2,
            pageNumberDelta: -1
        ),
        "m-plus-1": PDFBodyFontSizeAdjustment(
            tableOfContentsDelta: 2,
            pageNumberDelta: -1,
            exclamationQuestionDelta: 1
        ),
        "zen-old-mincho": PDFBodyFontSizeAdjustment(
            tableOfContentsDelta: 2,
            pageNumberDelta: -1,
            longVowelYOffset: 72 / 25.4
        ),
        "shippori-mincho": PDFBodyFontSizeAdjustment(
            tableOfContentsDelta: 2,
            pageNumberDelta: -1
        )
    ]
    private static let pageNumberPDFFontSizeAdjustments: [String: PDFPageNumberFontSizeAdjustment] = [
        "caveat": PDFPageNumberFontSizeAdjustment(
            tableOfContentsDelta: 2,
            pageNumberDelta: -1
        ),
        "cherry-bomb-one": PDFPageNumberFontSizeAdjustment(
            tableOfContentsDelta: 1,
            pageNumberDelta: -4
        ),
        "dancing-script": PDFPageNumberFontSizeAdjustment(
            pageNumberDelta: -4
        ),
        "great-vibes": PDFPageNumberFontSizeAdjustment(
            tableOfContentsDelta: 2,
            pageNumberDelta: -2
        ),
        "hachi-maru-pop": PDFPageNumberFontSizeAdjustment(
            tableOfContentsDelta: 2,
            pageNumberDelta: -3
        ),
        "homemade-apple": PDFPageNumberFontSizeAdjustment(
            tableOfContentsDelta: 4,
            pageNumberDelta: -2
        ),
        "love-light": PDFPageNumberFontSizeAdjustment(
            tableOfContentsDelta: 2,
            pageNumberDelta: -2
        ),
        "pacifico": PDFPageNumberFontSizeAdjustment(
            tableOfContentsDelta: 3,
            pageNumberDelta: -2
        )
    ]

    static let all: [AppFont] = [
        AppFont(
            id: defaultFontId,
            displayName: "BIZ UD明朝",
            postScriptName: "BIZUDMincho-Regular",
            fileName: "BIZUDMincho-Regular.ttf",
            isPremium: false,
            category: .standard,
            licenseName: "SIL Open Font License 1.1",
            copyrightText: "Copyright 2022 The BIZ UDGothic Project Authors."
        ),
        AppFont(
            id: "biz-ud-gothic",
            displayName: "BIZ UDゴシック",
            postScriptName: "BIZUDGothic-Regular",
            fileName: "BIZUDGothic-Regular.ttf",
            isPremium: false,
            category: .standard,
            licenseName: "SIL Open Font License 1.1",
            copyrightText: "Copyright 2022 The BIZ UDGothic Project Authors."
        ),
        AppFont(
            id: "shippori-mincho",
            displayName: "しっぽり明朝",
            postScriptName: "ShipporiMincho-Regular",
            fileName: "ShipporiMincho-Regular.ttf",
            isPremium: false,
            category: .novel,
            licenseName: "SIL Open Font License 1.1",
            copyrightText: "Copyright 2020 The Shippori Mincho Project Authors."
        ),
        AppFont(
            id: "zen-old-mincho",
            displayName: "Zen Old Mincho",
            postScriptName: "ZenOldMincho-Regular",
            fileName: "ZenOldMincho-Regular.ttf",
            isPremium: false,
            category: .novel,
            licenseName: "SIL Open Font License 1.1",
            copyrightText: "Copyright 2021 The Zen Old Mincho Project Authors."
        ),
        AppFont(
            id: "m-plus-1",
            displayName: "M PLUS 1",
            postScriptName: "MPLUS1-Regular",
            fileName: "MPLUS1-Regular.ttf",
            isPremium: false,
            category: .proofreading,
            licenseName: "SIL Open Font License 1.1",
            copyrightText: "Copyright 2016 The M PLUS Project Authors."
        )
    ]

    static let pageNumberFonts: [PageNumberFont] = [
        PageNumberFont(
            id: "love-light",
            displayName: "Love Light",
            postScriptName: "LoveLight-Regular",
            fileName: "LoveLight-Regular.ttf",
            category: .romantic,
            licenseName: "SIL Open Font License 1.1",
            copyrightText: "Copyright 2003 The Love Light Project Authors (https://github.com/googlefonts/love-light)"
        ),
        PageNumberFont(
            id: "dancing-script",
            displayName: "Dancing Script",
            postScriptName: "DancingScript-Regular",
            fileName: "DancingScript-Regular.ttf",
            category: .script,
            licenseName: "SIL Open Font License 1.1",
            copyrightText: "Copyright 2016 The Dancing Script Project Authors (https://github.com/googlefonts/DancingScript), with Reserved Font Name \"Dancing Script\"."
        ),
        PageNumberFont(
            id: "pacifico",
            displayName: "Pacifico",
            postScriptName: "Pacifico-Regular",
            fileName: "Pacifico-Regular.ttf",
            category: .script,
            licenseName: "SIL Open Font License 1.1",
            copyrightText: "Copyright 2018 The Pacifico Project Authors (https://github.com/googlefonts/Pacifico)",
            sizeMultiplier: 0.88,
            usesDotLeaderInTableOfContents: true
        ),
        PageNumberFont(
            id: "great-vibes",
            displayName: "Great Vibes",
            postScriptName: "GreatVibes-Regular",
            fileName: "GreatVibes-Regular.ttf",
            category: .script,
            licenseName: "SIL Open Font License 1.1",
            copyrightText: "Copyright 2010 The Great Vibes Pro Project Authors (https://github.com/googlefonts/great-vibes)"
        ),
        PageNumberFont(
            id: "caveat",
            displayName: "Caveat",
            postScriptName: "Caveat-Regular",
            fileName: "Caveat-Regular.ttf",
            category: .handwriting,
            licenseName: "SIL Open Font License 1.1",
            copyrightText: "Copyright 2014 The Caveat Project Authors (https://github.com/googlefonts/caveat)"
        ),
        PageNumberFont(
            id: "homemade-apple",
            displayName: "Homemade Apple",
            postScriptName: "HomemadeApple-Regular",
            fileName: "HomemadeApple-Regular.ttf",
            category: .handwriting,
            licenseName: "Apache License 2.0",
            copyrightText: "Copyright (c) 2010 by Font Diner, Inc. All rights reserved."
        ),
        PageNumberFont(
            id: "hachi-maru-pop",
            displayName: "Hachi Maru Pop",
            postScriptName: "HachiMaruPop-Regular",
            fileName: "HachiMaruPop-Regular.ttf",
            category: .handwriting,
            licenseName: "SIL Open Font License 1.1",
            copyrightText: "Copyright 2020 The Hachi Maru Pop Project Authors (https://github.com/noriokanisawa/HachiMaruPop)",
            sizeMultiplier: 0.92,
            usesDotLeaderInTableOfContents: true
        ),
        PageNumberFont(
            id: "cherry-bomb-one",
            displayName: "Cherry Bomb One",
            postScriptName: "CherryBombOne-Regular",
            fileName: "CherryBombOne-Regular.ttf",
            category: .pop,
            licenseName: "SIL Open Font License 1.1",
            copyrightText: "Copyright 2019 The Cherry Bomb Project Authors (https://github.com/satsuyako/CherryBomb)",
            sizeMultiplier: 0.86,
            usesDotLeaderInTableOfContents: true
        )
    ]

    private static var registeredFontFiles = Set<String>()
    private static let uiFontCache = NSCache<NSString, UIFont>()

    static func font(id: String) -> AppFont? {
        all.first { $0.id == normalizedFontId(id) }
    }

    static func normalizedFontId(_ id: String) -> String {
        let normalized = legacyFontReplacements[id] ?? id
        guard all.contains(where: { $0.id == normalized }) else {
            return defaultFontId
        }
        return normalized
    }

    static func fonts(in category: AppFontCategory) -> [AppFont] {
        all.filter { $0.category == category }
    }

    static func pageNumberFonts(in category: PageNumberFontCategory) -> [PageNumberFont] {
        pageNumberFonts.filter { $0.category == category }
    }

    static func pageNumberFont(id: String?) -> PageNumberFont? {
        guard let id else { return nil }
        return pageNumberFonts.first { $0.id == id }
    }

    static func usesDotLeaderInTableOfContents(pageNumberFontId: String?) -> Bool {
        pageNumberFont(id: pageNumberFontId)?.usesDotLeaderInTableOfContents == true
    }

    static func bodyPDFFontSizeAdjustment(selectedFontId: String) -> PDFBodyFontSizeAdjustment {
        bodyPDFFontSizeAdjustments[normalizedFontId(selectedFontId)] ?? PDFBodyFontSizeAdjustment()
    }

    static func pageNumberPDFFontSizeAdjustment(pageNumberFontId: String?) -> PDFPageNumberFontSizeAdjustment {
        guard let pageNumberFont = pageNumberFont(id: pageNumberFontId) else {
            return PDFPageNumberFontSizeAdjustment()
        }

        return pageNumberPDFFontSizeAdjustments[pageNumberFont.id] ?? PDFPageNumberFontSizeAdjustment()
    }

    static func pdfTableOfContentsBodyFontSize(
        selectedFontId: String,
        baseSize: CGFloat
    ) -> CGFloat {
        let adjustment = bodyPDFFontSizeAdjustment(selectedFontId: selectedFontId)
        return max(baseSize + adjustment.tableOfContentsDelta, 1)
    }

    static func pdfVerticalGlyphFontSize(
        selectedFontId: String,
        baseSize: CGFloat,
        glyphScale: CGFloat,
        sourceCharacter: String,
        appliesBodyGlyphAdjustment: Bool
    ) -> CGFloat {
        let scaledSize = baseSize * glyphScale
        guard appliesBodyGlyphAdjustment else {
            return max(scaledSize, 1)
        }

        let adjustment = bodyPDFFontSizeAdjustment(selectedFontId: selectedFontId)
        let delta: CGFloat
        if VerticalTextTypesetter.isExclamationQuestionCluster(sourceCharacter) {
            delta = adjustment.exclamationQuestionDelta
        } else if VerticalTextTypesetter.characterKind(for: sourceCharacter) == .longVowel {
            delta = adjustment.longVowelDelta
        } else {
            delta = 0
        }

        return max(scaledSize + delta, 1)
    }

    static func pdfVerticalGlyphPositionOffset(
        selectedFontId: String,
        sourceCharacter: String,
        appliesBodyGlyphAdjustment: Bool
    ) -> CGSize {
        guard appliesBodyGlyphAdjustment,
              VerticalTextTypesetter.characterKind(for: sourceCharacter) == .longVowel else {
            return .zero
        }

        let adjustment = bodyPDFFontSizeAdjustment(selectedFontId: selectedFontId)
        return CGSize(width: 0, height: adjustment.longVowelYOffset)
    }

    static func pdfPageNumberFontSize(
        pageNumberFontId: String?,
        bodyFontId: String,
        baseSize: CGFloat,
        isPageNumberFontUnlocked: Bool
    ) -> CGFloat {
        let delta = if isPageNumberFontUnlocked, pageNumberFont(id: pageNumberFontId) != nil {
            pageNumberPDFFontSizeAdjustment(pageNumberFontId: pageNumberFontId).pageNumberDelta
        } else {
            bodyPDFFontSizeAdjustment(selectedFontId: bodyFontId).pageNumberDelta
        }
        return max(baseSize + delta, 6)
    }

    static func pdfTableOfContentsPageNumberFontSize(
        pageNumberFontId: String?,
        bodyFontId: String,
        baseSize: CGFloat,
        glyphScale: CGFloat,
        isPageNumberFontUnlocked: Bool
    ) -> CGFloat {
        let scaledSize = baseSize * glyphScale
        let delta = if isPageNumberFontUnlocked, pageNumberFont(id: pageNumberFontId) != nil {
            pageNumberPDFFontSizeAdjustment(pageNumberFontId: pageNumberFontId).tableOfContentsDelta
        } else {
            bodyPDFFontSizeAdjustment(selectedFontId: bodyFontId).tableOfContentsDelta
        }
        return max(scaledSize + delta, 1)
    }

    static func pdfPageNumberUIFont(
        pageNumberFontId: String?,
        bodyFontId: String,
        size: CGFloat,
        isPageNumberFontUnlocked: Bool
    ) -> UIFont {
        let adjustedSize = pdfPageNumberFontSize(
            pageNumberFontId: pageNumberFontId,
            bodyFontId: bodyFontId,
            baseSize: size,
            isPageNumberFontUnlocked: isPageNumberFontUnlocked
        )
        guard isPageNumberFontUnlocked,
              let pageNumberFont = pageNumberFont(id: pageNumberFontId),
              let uiFont = cachedUIFont(name: pageNumberFont.postScriptName, size: adjustedSize) else {
            return uiFont(
                selectedFontId: bodyFontId,
                size: adjustedSize,
                isAdditionalFontPackUnlocked: true
            )
        }

        return uiFont
    }

    static func pdfTableOfContentsPageNumberUIFont(
        pageNumberFontId: String?,
        bodyFontId: String,
        bodyFontSize: CGFloat,
        glyphScale: CGFloat,
        isPageNumberFontUnlocked: Bool
    ) -> UIFont {
        let adjustedSize = pdfTableOfContentsPageNumberFontSize(
            pageNumberFontId: pageNumberFontId,
            bodyFontId: bodyFontId,
            baseSize: bodyFontSize,
            glyphScale: glyphScale,
            isPageNumberFontUnlocked: isPageNumberFontUnlocked
        )
        guard isPageNumberFontUnlocked,
              let pageNumberFont = pageNumberFont(id: pageNumberFontId),
              let uiFont = cachedUIFont(name: pageNumberFont.postScriptName, size: adjustedSize) else {
            return uiFont(
                selectedFontId: bodyFontId,
                size: adjustedSize,
                isAdditionalFontPackUnlocked: true
            )
        }

        return uiFont
    }

    static func effectiveFont(
        selectedFontId: String,
        isAdditionalFontPackUnlocked: Bool
    ) -> AppFont {
        guard let selected = font(id: normalizedFontId(selectedFontId)),
              canLoad(selected) else {
            return fallbackFont()
        }
        return selected
    }

    static func uiFont(
        selectedFontId: String,
        size: CGFloat,
        isAdditionalFontPackUnlocked: Bool
    ) -> UIFont {
        let font = effectiveFont(
            selectedFontId: selectedFontId,
            isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked
        )

        if let postScriptName = font.postScriptName,
           let uiFont = cachedUIFont(name: postScriptName, size: size) {
            return uiFont
        }

        if let fallbackPostScriptName = fallbackFont().postScriptName,
           let uiFont = cachedUIFont(name: fallbackPostScriptName, size: size) {
            return uiFont
        }

        return UIFont.systemFont(ofSize: size)
    }

    static func swiftUIFont(
        selectedFontId: String,
        size: CGFloat,
        isAdditionalFontPackUnlocked: Bool
    ) -> Font {
        let font = effectiveFont(
            selectedFontId: selectedFontId,
            isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked
        )

        if let postScriptName = font.postScriptName,
           UIFont(name: postScriptName, size: size) != nil {
            return .custom(postScriptName, size: size)
        }

        if let fallbackPostScriptName = fallbackFont().postScriptName,
           UIFont(name: fallbackPostScriptName, size: size) != nil {
            return .custom(fallbackPostScriptName, size: size)
        }

        return .system(size: size)
    }

    static func pageNumberUIFont(
        pageNumberFontId: String?,
        bodyFontId: String,
        size: CGFloat,
        isPageNumberFontUnlocked: Bool
    ) -> UIFont {
        guard isPageNumberFontUnlocked,
              let pageNumberFont = pageNumberFont(id: pageNumberFontId),
              let uiFont = cachedUIFont(
                name: pageNumberFont.postScriptName,
                size: size * pageNumberFont.sizeMultiplier
              ) else {
            return uiFont(
                selectedFontId: bodyFontId,
                size: size,
                isAdditionalFontPackUnlocked: true
            )
        }

        return uiFont
    }

    static func pageNumberSwiftUIFont(
        pageNumberFontId: String?,
        bodyFontId: String,
        size: CGFloat,
        isPageNumberFontUnlocked: Bool
    ) -> Font {
        guard isPageNumberFontUnlocked,
              let pageNumberFont = pageNumberFont(id: pageNumberFontId),
              UIFont(name: pageNumberFont.postScriptName, size: size * pageNumberFont.sizeMultiplier) != nil else {
            return swiftUIFont(
                selectedFontId: bodyFontId,
                size: size,
                isAdditionalFontPackUnlocked: true
            )
        }

        return .custom(pageNumberFont.postScriptName, size: size * pageNumberFont.sizeMultiplier)
    }

    static func registerBundledFonts() {
        for fileName in all.compactMap(\.fileName) + pageNumberFonts.map(\.fileName) {
            registerFont(fileName: fileName)
        }

        #if DEBUG
        for family in UIFont.familyNames.sorted() {
            for name in UIFont.fontNames(forFamilyName: family).sorted()
            where all.contains(where: { $0.postScriptName == name }) {
                debugPrint("Available Honkumi font PostScript name:", name)
            }
        }
        #endif
    }

    private static func fallbackFont() -> AppFont {
        font(id: defaultFontId) ?? all[0]
    }

    private static func cachedUIFont(name: String, size: CGFloat) -> UIFont? {
        let cacheKey = "\(name)-\(String(format: "%.3f", Double(size)))" as NSString
        if let cachedFont = uiFontCache.object(forKey: cacheKey) {
            return cachedFont
        }

        guard let font = UIFont(name: name, size: size) else { return nil }
        uiFontCache.setObject(font, forKey: cacheKey)
        return font
    }

    private static func canLoad(_ font: AppFont) -> Bool {
        if let postScriptName = font.postScriptName,
           cachedUIFont(name: postScriptName, size: 12) != nil {
            return true
        }

        return false
    }

    private static func registerFont(fileName: String) {
        guard !registeredFontFiles.contains(fileName),
              let url = Bundle.main.url(forResource: fileName, withExtension: nil) else {
            return
        }

        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            registeredFontFiles.insert(fileName)
            debugPrint("Registered font file:", fileName)
        } else if let error {
            debugPrint("Failed to register font file:", fileName, error.takeRetainedValue())
        }
    }
}
