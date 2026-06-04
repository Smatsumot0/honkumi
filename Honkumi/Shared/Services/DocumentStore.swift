import Combine
import Foundation

@MainActor
final class DocumentStore: ObservableObject {
    @Published private(set) var appData: AppData
    @Published private(set) var document: ManuscriptDocument

    private let storageKey = "honkumi.appData"
    private let legacyStorageKey = "honkumi.currentDocument"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var pendingSaveTask: Task<Void, Never>?

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let loadedData: AppData
        let needsInitialSave: Bool
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let savedData = try? decoder.decode(AppData.self, from: data) {
            let migratedData = Self.migrate(savedData)
            loadedData = Self.normalized(migratedData)
            needsInitialSave = loadedData != savedData
        } else if let legacyData = UserDefaults.standard.data(forKey: legacyStorageKey),
                  let legacyDocument = try? decoder.decode(ManuscriptDocument.self, from: legacyData) {
            loadedData = Self.migratedFromLegacyDocument(legacyDocument)
            needsInitialSave = true
        } else {
            loadedData = .initial
            needsInitialSave = false
        }

        self.appData = loadedData
        self.document = Self.activeDocument(in: loadedData)
        if needsInitialSave {
            save()
        }
    }

    init(appData: AppData) {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let loadedData = Self.normalized(Self.migrate(appData))
        self.appData = loadedData
        self.document = Self.activeDocument(in: loadedData)
        save()
    }

    var categories: [WorkCategory] {
        appData.categories
    }

    var works: [ManuscriptDocument] {
        appData.works
    }

    var userDefaultSettings: EditorSettings {
        appData.userDefaultSettings
    }

    var subscriptionStatus: SubscriptionStatus {
        appData.subscriptionStatus
    }

    var isAdditionalFontPackUnlocked: Bool {
        appData.subscriptionStatus == .paid
    }

    var isPageNumberFontUnlocked: Bool {
        appData.subscriptionStatus == .paid
    }

    func works(in category: WorkCategory) -> [ManuscriptDocument] {
        works
            .filter { $0.categoryId == category.id }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func selectWork(id: UUID) {
        updateAppData { data in
            guard data.works.contains(where: { $0.id == id }) else { return }
            data.activeWorkId = id
        }
    }

    @discardableResult
    func createWork(title: String = "", in categoryId: UUID? = nil) -> ManuscriptDocument {
        var createdWork = ManuscriptDocument()
        updateAppData { data in
            let targetCategoryId = categoryId ?? WorkCategory.uncategorizedId
            let categoryExists = data.categories.contains(where: { $0.id == targetCategoryId })
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            createdWork = ManuscriptDocument(
                categoryId: categoryExists ? targetCategoryId : WorkCategory.uncategorizedId,
                title: trimmedTitle.isEmpty ? "無題の作品" : trimmedTitle,
                body: "",
                settings: data.userDefaultSettings.validated
            )
            data.works.append(createdWork)
            data.activeWorkId = createdWork.id
        }
        return createdWork
    }

    func deleteWork(id: UUID) {
        updateAppData { data in
            data.works.removeAll { $0.id == id }
            if data.works.isEmpty {
                let work = ManuscriptDocument(title: "無題の作品", settings: data.userDefaultSettings.validated)
                data.works = [work]
                data.activeWorkId = work.id
            } else if data.activeWorkId == id {
                data.activeWorkId = data.works.sorted { $0.updatedAt > $1.updatedAt }.first?.id
            }
        }
    }

    func moveWork(id: UUID, to categoryId: UUID) {
        updateWork(id: id) { work in
            work.categoryId = categoryId
        }
    }

    func updateBody(_ body: String) {
        guard let id = appData.activeWorkId else { return }
        updateWork(id: id) { work in
            work.body = body
        }
    }

    func updateTitle(_ title: String) {
        guard let id = appData.activeWorkId else { return }
        updateWork(id: id) { work in
            work.title = title
        }
    }

    func updateTitle(for id: UUID, title: String) {
        updateWork(id: id) { work in
            work.title = title
        }
    }

    func updateSettings(_ settings: EditorSettings) {
        guard let id = appData.activeWorkId else { return }
        updateWork(id: id) { work in
            work.settings = settings.validated
        }
    }

    func updateUserDefaultSettings(_ settings: EditorSettings) {
        updateAppData { data in
            data.userDefaultSettings = settings.validated
        }
    }

    @discardableResult
    func createCategory(name: String) -> WorkCategory {
        var category = WorkCategory.uncategorized
        updateAppData { data in
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            category = WorkCategory(name: trimmedName.isEmpty ? "新規カテゴリ" : trimmedName)
            data.categories.append(category)
        }
        return category
    }

    func renameCategory(id: UUID, name: String) {
        guard id != WorkCategory.uncategorizedId else { return }
        updateAppData { data in
            guard let index = data.categories.firstIndex(where: { $0.id == id }) else { return }
            data.categories[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if data.categories[index].name.isEmpty {
                data.categories[index].name = "名称未設定"
            }
            data.categories[index].updatedAt = Date()
        }
    }

    func deleteCategory(id: UUID) {
        guard id != WorkCategory.uncategorizedId else { return }
        updateAppData { data in
            data.categories.removeAll { $0.id == id }
            for index in data.works.indices where data.works[index].categoryId == id {
                data.works[index].categoryId = WorkCategory.uncategorizedId
                data.works[index].updatedAt = Date()
            }
        }
    }

    private func updateWork(id: UUID, changes: (inout ManuscriptDocument) -> Void) {
        updateAppData { data in
            guard let index = data.works.firstIndex(where: { $0.id == id }) else { return }
            changes(&data.works[index])
            data.works[index].settings = data.works[index].settings.validated
            data.works[index].updatedAt = Date()
        }
    }

    private func updateAppData(_ changes: (inout AppData) -> Void) {
        var updatedData = appData
        changes(&updatedData)
        updatedData = Self.normalized(Self.migrate(updatedData))
        appData = updatedData
        document = Self.activeDocument(in: updatedData)
        scheduleSave()
    }

    private func save() {
        guard let data = try? encoder.encode(appData) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func scheduleSave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.save()
            }
        }
    }

    private static func migrate(_ data: AppData) -> AppData {
        switch data.version {
        case AppData.currentVersion:
            return data
        default:
            var migratedData = data
            migratedData.version = AppData.currentVersion
            return migratedData
        }
    }

    private static func migratedFromLegacyDocument(_ document: ManuscriptDocument) -> AppData {
        var migratedDocument = document
        migratedDocument.categoryId = WorkCategory.uncategorizedId
        if migratedDocument.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            migratedDocument.title = "無題の作品"
        }

        return AppData(
            version: AppData.currentVersion,
            categories: [.uncategorized],
            works: [migratedDocument],
            userDefaultSettings: migratedDocument.settings.validated,
            activeWorkId: migratedDocument.id,
            subscriptionStatus: .free
        )
    }

    private static func normalized(_ data: AppData) -> AppData {
        var normalizedData = data
        normalizedData.version = AppData.currentVersion

        if !normalizedData.categories.contains(where: { $0.id == WorkCategory.uncategorizedId }) {
            normalizedData.categories.insert(.uncategorized, at: 0)
        }

        let categoryIds = Set(normalizedData.categories.map(\.id))
        for index in normalizedData.works.indices {
            if !categoryIds.contains(normalizedData.works[index].categoryId) {
                normalizedData.works[index].categoryId = WorkCategory.uncategorizedId
            }
            normalizedData.works[index].settings = normalizedData.works[index].settings.validated
        }

        if normalizedData.works.isEmpty {
            let work = ManuscriptDocument(title: "無題の作品", settings: normalizedData.userDefaultSettings.validated)
            normalizedData.works = [work]
            normalizedData.activeWorkId = work.id
        }

        if let activeWorkId = normalizedData.activeWorkId,
           normalizedData.works.contains(where: { $0.id == activeWorkId }) {
            return normalizedData
        }

        normalizedData.activeWorkId = normalizedData.works.sorted { $0.updatedAt > $1.updatedAt }.first?.id
        return normalizedData
    }

    private static func activeDocument(in data: AppData) -> ManuscriptDocument {
        if let activeWorkId = data.activeWorkId,
           let work = data.works.first(where: { $0.id == activeWorkId }) {
            return work
        }

        return data.works.first ?? ManuscriptDocument(title: "無題の作品")
    }
}
