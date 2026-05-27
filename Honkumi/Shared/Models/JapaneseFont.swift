import Foundation

enum JapaneseFont: String, Codable, CaseIterable, Identifiable {
    case hiraginoSans = "HiraginoSans-W3"
    case hiraginoSansBold = "HiraginoSans-W6"
    case hiraginoMincho = "HiraMinProN-W3"
    case hiraginoMinchoBold = "HiraMinProN-W6"
    case hiraginoMaruGothic = "HiraMaruProN-W4"

    static let allCases: [JapaneseFont] = [
        .hiraginoSans,
        .hiraginoMincho,
        .hiraginoMaruGothic
    ]

    var id: String { rawValue }

    var postScriptName: String { rawValue }

    var regularized: JapaneseFont {
        switch self {
        case .hiraginoSansBold:
            .hiraginoSans
        case .hiraginoMinchoBold:
            .hiraginoMincho
        default:
            self
        }
    }

    var displayName: String {
        switch self {
        case .hiraginoSans:
            "ヒラギノ角ゴシック"
        case .hiraginoSansBold:
            "ヒラギノ角ゴシック 太字"
        case .hiraginoMincho:
            "ヒラギノ明朝"
        case .hiraginoMinchoBold:
            "ヒラギノ明朝 太字"
        case .hiraginoMaruGothic:
            "ヒラギノ丸ゴシック"
        }
    }
}
