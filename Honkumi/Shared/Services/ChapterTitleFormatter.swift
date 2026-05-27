import Foundation

enum ChapterTitleFormatter {
    static func format(_ title: String, style: ChapterTitleStyle) -> String {
        switch style {
        case .plain, .centered:
            title
        case .diamond:
            "◆ \(title)"
        case .brackets:
            "【\(title)】"
        }
    }
}
