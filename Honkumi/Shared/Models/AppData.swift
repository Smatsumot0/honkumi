import Foundation

struct AppData: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var categories: [WorkCategory]
    var works: [ManuscriptDocument]
    var userDefaultSettings: EditorSettings
    var activeWorkId: UUID?

    static var initial: AppData {
        let work = ManuscriptDocument(title: "無題の作品")
        return AppData(
            version: currentVersion,
            categories: [.uncategorized],
            works: [work],
            userDefaultSettings: .default,
            activeWorkId: work.id
        )
    }
}
