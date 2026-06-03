import CoreText
import SwiftUI
import UIKit

enum AppFontCategory: String, Codable, CaseIterable, Identifiable {
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

struct AppFont: Identifiable, Equatable {
    let id: String
    let displayName: String
    let postScriptName: String?
    let fileName: String?
    let isPremium: Bool
    let category: AppFontCategory
    let licenseName: String
    let copyrightText: String
}

enum AppFontCatalog {
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

    private static var registeredFontFiles = Set<String>()

    static func font(id: String) -> AppFont? {
        all.first { $0.id == id }
    }

    static func fonts(in category: AppFontCategory) -> [AppFont] {
        all.filter { $0.category == category }
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

    static func registerBundledFonts() {
        for font in all {
            guard let fileName = font.fileName,
                  !registeredFontFiles.contains(fileName),
                  let url = Bundle.main.url(forResource: fileName, withExtension: nil) else {
                continue
            }

            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                registeredFontFiles.insert(fileName)
                debugPrint("Registered font file:", fileName)
            } else if let error {
                debugPrint("Failed to register font file:", fileName, error.takeRetainedValue())
            }
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
}
