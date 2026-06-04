import Foundation

nonisolated enum ChapterTitleStyle: String, Codable, CaseIterable, Identifiable {
    case plain
    case diamond
    case brackets
    case centered

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .plain:
            "飾りなし"
        case .diamond:
            "◆ 第一章"
        case .brackets:
            "【第一章】"
        case .centered:
            "中央配置"
        }
    }
}
