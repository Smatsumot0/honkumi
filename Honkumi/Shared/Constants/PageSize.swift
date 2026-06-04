import Foundation

nonisolated enum PageSize: String, CaseIterable, Identifiable, Codable {
    case a6
    case shinsho
    case b6
    case a5
    case b5

    static let selectableCases: [PageSize] = [.a6, .shinsho, .b6, .a5, .b5]

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .a6:
            "A6（文庫）"
        case .shinsho:
            "新書"
        case .b6:
            "B6"
        case .a5:
            "A5"
        case .b5:
            "B5"
        }
    }

    var widthMillimeters: Double {
        switch self {
        case .a6:
            105
        case .shinsho:
            103
        case .b6:
            128
        case .a5:
            148
        case .b5:
            182
        }
    }

    var heightMillimeters: Double {
        switch self {
        case .a6:
            148
        case .shinsho:
            182
        case .b6:
            182
        case .a5:
            210
        case .b5:
            257
        }
    }
}

nonisolated extension PageSize {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        switch value {
        case "a6", "A6":
            self = .a6
        case "shinsho", "新書":
            self = .shinsho
        case "b6", "B6":
            self = .b6
        case "a5", "A5":
            self = .a5
        case "b5", "B5":
            self = .b5
        default:
            self = .a6
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
