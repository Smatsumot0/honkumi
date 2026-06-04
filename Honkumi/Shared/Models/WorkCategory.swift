import Foundation

nonisolated struct WorkCategory: Codable, Equatable, Identifiable {
    static let uncategorizedId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static var uncategorized: WorkCategory {
        WorkCategory(id: uncategorizedId, name: "未分類")
    }
}
