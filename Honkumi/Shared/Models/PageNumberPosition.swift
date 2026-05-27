import Foundation

enum PageNumberPosition: String, Codable, CaseIterable, Identifiable {
    case hidden
    case center
    case outside

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hidden:
            "表示しない"
        case .center:
            "中央"
        case .outside:
            "端"
        }
    }
}
