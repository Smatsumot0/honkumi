import Foundation

nonisolated struct ManuscriptPaginationResult {
    let document: ManuscriptDocument
    let pages: [PreviewPage]
    let cacheKey: String
}

nonisolated enum ManuscriptRenderPipeline {
    private static let cacheLock = NSLock()
    private static var pageCache: [String: ManuscriptPaginationResult] = [:]
    private static var pageCacheOrder: [String] = []
    private static let maximumCachedPageSets = 6

    static func paginationResult(
        for document: ManuscriptDocument,
        subscriptionStatus: SubscriptionStatus
    ) -> ManuscriptPaginationResult {
        let preparedDocument = preparedDocument(
            from: document,
            subscriptionStatus: subscriptionStatus
        )
        let key = cacheKey(
            for: preparedDocument,
            subscriptionStatus: subscriptionStatus
        )

        if let cached = cachedPaginationResult(forKey: key) {
            return cached
        }

        let pages = ManuscriptPaginator.pages(for: preparedDocument)
        let result = ManuscriptPaginationResult(
            document: preparedDocument,
            pages: pages,
            cacheKey: key
        )
        store(result, forKey: key)
        return result
    }

    static func cachedPaginationResult(
        for document: ManuscriptDocument,
        subscriptionStatus: SubscriptionStatus
    ) -> ManuscriptPaginationResult? {
        let preparedDocument = preparedDocument(
            from: document,
            subscriptionStatus: subscriptionStatus
        )
        let key = cacheKey(
            for: preparedDocument,
            subscriptionStatus: subscriptionStatus
        )
        return cachedPaginationResult(forKey: key)
    }

    static func preparedDocument(
        from document: ManuscriptDocument,
        subscriptionStatus: SubscriptionStatus
    ) -> ManuscriptDocument {
        let settings = document.settings.validated
        var preparedDocument = document
        preparedDocument.settings = settings
        preparedDocument.body = ManuscriptFormatter.formatManuscriptText(
            document.body,
            settings: settings.formatSettings,
            options: FormatOptions(isPremiumUser: subscriptionStatus == .paid)
        )
        return preparedDocument
    }

    private static func cachedPaginationResult(forKey key: String) -> ManuscriptPaginationResult? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return pageCache[key]
    }

    private static func store(_ result: ManuscriptPaginationResult, forKey key: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        pageCache[key] = result
        pageCacheOrder.removeAll { $0 == key }
        pageCacheOrder.append(key)

        while pageCacheOrder.count > maximumCachedPageSets {
            let removedKey = pageCacheOrder.removeFirst()
            pageCache[removedKey] = nil
        }
    }

    private static func cacheKey(
        for document: ManuscriptDocument,
        subscriptionStatus: SubscriptionStatus
    ) -> String {
        let settingsData = encodedSettingsData(document.settings)
        let hash = fnv1aHash([
            Data(document.id.uuidString.utf8),
            Data(document.title.utf8),
            Data(document.body.utf8),
            settingsData,
            Data(subscriptionStatus.rawValue.utf8)
        ])
        return [
            String(hash, radix: 16),
            String(document.title.utf8.count),
            String(document.body.utf8.count),
            String(settingsData.count),
            subscriptionStatus.rawValue
        ].joined(separator: "-")
    }

    private static func encodedSettingsData(_ settings: EditorSettings) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(settings)) ?? Data(String(describing: settings).utf8)
    }

    private static func fnv1aHash(_ components: [Data]) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211

        for component in components {
            for byte in component {
                hash ^= UInt64(byte)
                hash &*= prime
            }
            hash ^= 0xff
            hash &*= prime
        }

        return hash
    }
}
