import Foundation

nonisolated enum AppDataPersistenceEncoder {
    typealias EncodeOperation = @Sendable (AppData) async -> Data?

    static func encode(_ appData: AppData) async -> Data? {
        await Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try? encoder.encode(appData)
        }.value
    }
}
