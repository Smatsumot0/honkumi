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
}

nonisolated enum AppFontCatalog {
    static let defaultFontId = "biz-ud-mincho"

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
            id: "source-han-serif-jp",
            displayName: "源ノ明朝",
            postScriptName: "SourceHanSerifJP-Regular",
            fileName: "SourceHanSerifJP-Regular.otf",
            isPremium: false,
            category: .novel,
            licenseName: "SIL Open Font License 1.1",
            copyrightText: "Copyright 2017 Adobe."
        ),
        AppFont(
            id: "source-han-sans-jp",
            displayName: "源ノ角ゴシック",
            postScriptName: "SourceHanSansJP-Regular",
            fileName: "SourceHanSansJP-Regular.otf",
            isPremium: false,
            category: .proofreading,
            licenseName: "SIL Open Font License 1.1",
            copyrightText: "Copyright 2014-2021 Adobe."
        ),
        AppFont(
            id: "noto-serif-jp",
            displayName: "Noto Serif JP",
            postScriptName: "NotoSerifJP-Regular",
            fileName: "NotoSerifJP-Regular.otf",
            isPremium: false,
            category: .novel,
            licenseName: "SIL Open Font License 1.1",
            copyrightText: "Copyright 2017 The Noto Project Authors."
        ),
        AppFont(
            id: "noto-sans-jp",
            displayName: "Noto Sans JP",
            postScriptName: "NotoSansJP-Regular",
            fileName: "NotoSansJP-Regular.otf",
            isPremium: false,
            category: .proofreading,
            licenseName: "SIL Open Font License 1.1",
            copyrightText: "Copyright 2014-2021 The Noto Project Authors."
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
        ),
        AppFont(
            id: "ibm-plex-sans-jp",
            displayName: "IBM Plex Sans JP",
            postScriptName: "IBMPlexSansJP-Regular",
            fileName: "IBMPlexSansJP-Regular.ttf",
            isPremium: false,
            category: .proofreading,
            licenseName: "SIL Open Font License 1.1",
            copyrightText: "Copyright 2017 IBM Corp."
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
            copyrightText: "Copyright 2018 The Pacifico Project Authors (https://github.com/googlefonts/Pacifico)"
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
            copyrightText: "Copyright 2020 The Hachi Maru Pop Project Authors (https://github.com/noriokanisawa/HachiMaruPop)"
        ),
        PageNumberFont(
            id: "cherry-bomb-one",
            displayName: "Cherry Bomb One",
            postScriptName: "CherryBombOne-Regular",
            fileName: "CherryBombOne-Regular.ttf",
            category: .pop,
            licenseName: "SIL Open Font License 1.1",
            copyrightText: "Copyright 2019 The Cherry Bomb Project Authors (https://github.com/satsuyako/CherryBomb)"
        )
    ]

    private static var registeredFontFiles = Set<String>()

    static func font(id: String) -> AppFont? {
        all.first { $0.id == id }
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

    static func effectiveFont(
        selectedFontId: String,
        isAdditionalFontPackUnlocked: Bool
    ) -> AppFont {
        guard let selected = font(id: selectedFontId),
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
           let uiFont = UIFont(name: postScriptName, size: size) {
            return uiFont
        }

        if let fallbackPostScriptName = fallbackFont().postScriptName,
           let uiFont = UIFont(name: fallbackPostScriptName, size: size) {
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
              let uiFont = UIFont(name: pageNumberFont.postScriptName, size: size) else {
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
              UIFont(name: pageNumberFont.postScriptName, size: size) != nil else {
            return swiftUIFont(
                selectedFontId: bodyFontId,
                size: size,
                isAdditionalFontPackUnlocked: true
            )
        }

        return .custom(pageNumberFont.postScriptName, size: size)
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

    private static func canLoad(_ font: AppFont) -> Bool {
        if let postScriptName = font.postScriptName,
           UIFont(name: postScriptName, size: 12) != nil {
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
