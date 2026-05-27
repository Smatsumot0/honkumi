import Foundation

struct AppData: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var categories: [WorkCategory]
    var works: [ManuscriptDocument]
    var userDefaultSettings: EditorSettings
    var activeWorkId: UUID?
    var subscriptionStatus: SubscriptionStatus

    static var initial: AppData {
        let work = ManuscriptDocument(title: "無題の作品")
        return AppData(
            version: currentVersion,
            categories: [.uncategorized],
            works: [work],
            userDefaultSettings: .default,
            activeWorkId: work.id,
            subscriptionStatus: .free
        )
    }
}

enum SubscriptionStatus: String, Codable, Equatable {
    case free
    case paid

    var showsPoweredByHonkumi: Bool {
        self == .free
    }
}

extension AppData {
    private enum CodingKeys: String, CodingKey {
        case version
        case categories
        case works
        case userDefaultSettings
        case activeWorkId
        case subscriptionStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            version: try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion,
            categories: try container.decodeIfPresent([WorkCategory].self, forKey: .categories) ?? [.uncategorized],
            works: try container.decodeIfPresent([ManuscriptDocument].self, forKey: .works) ?? [],
            userDefaultSettings: try container.decodeIfPresent(EditorSettings.self, forKey: .userDefaultSettings) ?? .default,
            activeWorkId: try container.decodeIfPresent(UUID.self, forKey: .activeWorkId),
            subscriptionStatus: try container.decodeIfPresent(SubscriptionStatus.self, forKey: .subscriptionStatus) ?? .free
        )
    }
}
