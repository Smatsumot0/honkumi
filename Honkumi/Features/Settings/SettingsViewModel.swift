import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    typealias FormatOperation = @Sendable (
        _ text: String,
        _ settings: FormatSettings,
        _ options: FormatOptions
    ) async -> String
    typealias PrintSnapshotOperation = @Sendable (
        _ body: String,
        _ settings: EditorSettings
    ) async -> PrintSettingsDisplaySnapshot

    enum Scope {
        case activeWork
        case userDefault
    }

    @Published private(set) var document: ManuscriptDocument
    @Published private(set) var userDefaultSettings: EditorSettings
    @Published private(set) var isApplyingFormat = false
    @Published private(set) var isCalculatingPrintSettings = false
    @Published private var printSettingsSnapshot: PrintSettingsDisplaySnapshot

    private let documentStore: DocumentStore
    private let scope: Scope
    private let formatOperation: FormatOperation
    private let printSnapshotOperation: PrintSnapshotOperation
    private var cancellables = Set<AnyCancellable>()
    private var formatTask: Task<Void, Never>?
    private var formatGeneration = 0
    private var printSnapshotTask: Task<Void, Never>?
    private var printSnapshotGeneration = 0
    private var printSnapshotSource: PrintSnapshotSource
    private var requestedPrintSnapshotSource: PrintSnapshotSource?

    init(
        documentStore: DocumentStore,
        scope: Scope = .activeWork,
        formatOperation: @escaping FormatOperation = SettingsViewModel.defaultFormatOperation,
        printSnapshotOperation: @escaping PrintSnapshotOperation =
            SettingsViewModel.defaultPrintSnapshotOperation
    ) {
        let initialDocument = documentStore.document
        let initialUserDefaultSettings = documentStore.userDefaultSettings
        let initialSettings: EditorSettings
        switch scope {
        case .activeWork:
            initialSettings = initialDocument.settings
        case .userDefault:
            initialSettings = initialUserDefaultSettings
        }
        let initialPrintSource = PrintSnapshotSource(
            body: initialDocument.body,
            settings: initialSettings.validated
        )

        self.documentStore = documentStore
        self.scope = scope
        self.formatOperation = formatOperation
        self.printSnapshotOperation = printSnapshotOperation
        self.document = initialDocument
        self.userDefaultSettings = initialUserDefaultSettings
        self.printSettingsSnapshot = .initial(settings: initialSettings)
        self.printSnapshotSource = initialPrintSource

        documentStore.$document
            .dropFirst()
            .sink { [weak self] document in
                guard let self else { return }
                self.document = document
                self.schedulePrintSnapshotRefresh()
            }
            .store(in: &cancellables)

        documentStore.$appData
            .map(\.userDefaultSettings)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] settings in
                guard let self else { return }
                self.userDefaultSettings = settings
                self.schedulePrintSnapshotRefresh()
            }
            .store(in: &cancellables)

        schedulePrintSnapshotRefresh()
    }

    deinit {
        formatTask?.cancel()
        printSnapshotTask?.cancel()
    }

    var settings: EditorSettings {
        get {
            switch scope {
            case .activeWork:
                document.settings
            case .userDefault:
                userDefaultSettings
            }
        }
        set {
            switch scope {
            case .activeWork:
                documentStore.updateSettings(newValue)
            case .userDefault:
                documentStore.updateUserDefaultSettings(newValue)
            }
        }
    }

    var subscriptionStatus: SubscriptionStatus {
        documentStore.subscriptionStatus
    }

    var isPremiumUser: Bool {
        subscriptionStatus == .paid
    }

    var isAdditionalFontPackUnlocked: Bool {
        documentStore.isAdditionalFontPackUnlocked
    }

    var isPageNumberFontUnlocked: Bool {
        documentStore.isPageNumberFontUnlocked
    }

    var isActiveWorkScope: Bool {
        scope == .activeWork
    }

    var printSettingsForDisplay: EditorSettings {
        guard printSnapshotSource == currentPrintSnapshotSource else {
            return settings.validated
        }
        return printSettingsSnapshot.settings
    }

    var estimatedPrintPageCount: Int {
        printSettingsSnapshot.estimatedPageCount
    }

    var isPrintRecommendationAvailable: Bool {
        RecommendedPrintSettings.supportsRecommendations(for: settings.pageSize)
    }

    var unsupportedRecommendationMessage: String {
        RecommendedPrintSettings.unsupportedPageSizeMessage
    }

    var showsWideGutterRecommendationNote: Bool {
        guard printSnapshotSource == currentPrintSnapshotSource else {
            return false
        }
        return printSettingsSnapshot.showsWideGutterNote
    }

    var wideGutterRecommendationNote: String {
        RecommendedPrintSettings.wideGutterNote
    }

    private var printRecommendationBody: String {
        switch scope {
        case .activeWork:
            document.body
        case .userDefault:
            document.body
        }
    }

    private var currentPrintSnapshotSource: PrintSnapshotSource {
        PrintSnapshotSource(
            body: printRecommendationBody,
            settings: settings.validated
        )
    }

    func updateUseRecommendedTypography(_ value: Bool) {
        let displayed = printSettingsForDisplay
        var updated = settings
        if updated.useRecommendedTypography,
           !value,
           isPrintRecommendationAvailable {
            updated = Self.copyManualTypographyFields(from: displayed, to: updated)
        }
        updated.useRecommendedTypography = value
        settings = updated
    }

    func updateUseRecommendedMargins(_ value: Bool) {
        let displayed = printSettingsForDisplay
        var updated = settings
        if updated.useRecommendedMargins,
           !value,
           isPrintRecommendationAvailable {
            updated = Self.copyManualMarginFields(from: displayed, to: updated)
        }
        updated.useRecommendedMargins = value
        settings = updated
    }

    private static func copyManualTypographyFields(
        from recommended: EditorSettings,
        to settings: EditorSettings
    ) -> EditorSettings {
        var updated = settings
        updated.fontSize = recommended.fontSize
        updated.charactersPerLine = recommended.charactersPerLine
        updated.linesPerPage = recommended.linesPerPage
        return updated
    }

    private static func copyManualMarginFields(
        from recommended: EditorSettings,
        to settings: EditorSettings
    ) -> EditorSettings {
        var updated = settings
        updated.marginTop = recommended.marginTop
        updated.marginBottom = recommended.marginBottom
        updated.marginInner = recommended.marginInner
        updated.marginOuter = recommended.marginOuter
        return updated
    }

    func updatePageSize(_ value: PageSize) {
        var updated = settings
        updated.pageSize = value
        settings = updated
    }

    func updateSelectedFontId(_ value: String) {
        var updated = settings
        updated.selectedFontId = value
        settings = updated
    }

    func updateFontSize(_ value: CGFloat) {
        var updated = settings
        updated.fontSize = EditorSettings.roundedPrintFontSize(value)
        settings = updated
    }

    func updateEditorFontId(_ value: String) {
        var updated = settings
        updated.editorFontId = value
        settings = updated
    }

    func updateEditorFontSize(_ value: CGFloat) {
        var updated = settings
        updated.editorFontSize = value
        settings = updated
    }

    func updateLineSpacing(_ value: CGFloat) {
        var updated = settings
        updated.lineSpacing = 0
        settings = updated
    }

    func updateCharacterSpacing(_ value: CGFloat) {
        var updated = settings
        updated.characterSpacing = 0
        settings = updated
    }

    func updateCharactersPerLine(_ value: Int) {
        var updated = settings
        updated.charactersPerLine = value
        settings = updated
    }

    func updateLinesPerPage(_ value: Int) {
        var updated = settings
        updated.linesPerPage = value
        settings = updated
    }

    func updateMarginTop(_ value: CGFloat) {
        var updated = settings
        updated.marginTop = value
        settings = updated
    }

    func updateMarginBottom(_ value: CGFloat) {
        var updated = settings
        updated.marginBottom = value
        settings = updated
    }

    func updateVerticalMargins(_ value: CGFloat) {
        var updated = settings
        updated.marginTop = value
        updated.marginBottom = value
        settings = updated
    }

    func updateMarginInner(_ value: CGFloat) {
        var updated = settings
        updated.marginInner = value
        settings = updated
    }

    func updateMarginOuter(_ value: CGFloat) {
        var updated = settings
        updated.marginOuter = value
        settings = updated
    }

    func updateShowChapterTitle(_ value: Bool) {
        var updated = settings
        updated.showChapterTitle = value
        settings = updated
    }

    func updateChapterTitleStyle(_ value: ChapterTitleStyle) {
        var updated = settings
        updated.chapterTitleStyle = value
        settings = updated
    }

    func updateStartsChapterOnNewPage(_ value: Bool) {
        var updated = settings
        updated.startsChapterOnNewPage = value
        settings = updated
    }

    func updateShowsCropMarks(_ value: Bool) {
        var updated = settings
        updated.showsCropMarks = value
        settings = updated
    }

    func updateShowTableOfContents(_ value: Bool) {
        var updated = settings
        updated.showTableOfContents = value
        settings = updated
    }

    func updatePageNumberPosition(_ value: PageNumberPosition) {
        guard isPageNumberFontUnlocked else { return }
        var updated = settings
        updated.pageNumberPosition = value
        updated.isPageNumberEnabled = value != .hidden
        settings = updated
    }

    func updateIsPageNumberEnabled(_ value: Bool) {
        var updated = settings
        updated.isPageNumberEnabled = value
        if value, updated.pageNumberPosition == .hidden {
            updated.pageNumberPosition = .outside
        }
        settings = updated
    }

    func updateShowPageNumberOnToc(_ value: Bool) {
        var updated = settings
        updated.showPageNumberOnToc = value
        settings = updated
    }

    func updateShowPageNumberOnColophon(_ value: Bool) {
        var updated = settings
        updated.showPageNumberOnColophon = value
        settings = updated
    }

    func updatePageNumberFontId(_ value: String?) {
        guard isPageNumberFontUnlocked || value == nil else { return }
        var updated = settings
        updated.pageNumberFontId = value
        settings = updated
    }

    func updatePageNumberSize(_ value: CGFloat) {
        guard isPageNumberFontUnlocked else { return }
        var updated = settings
        updated.pageNumberSize = value
        settings = updated
    }

    func updatePageNumberStart(_ value: Int) {
        var updated = settings
        updated.pageNumberStart = value
        settings = updated
    }

    func updateColophon(_ changes: (inout ColophonSettings) -> Void) {
        var updated = settings
        changes(&updated.colophon)
        settings = updated
    }

    func updateFormatSettings(_ changes: (inout FormatSettings) -> Void) {
        let previousSettings = settings
        var updated = settings
        changes(&updated.formatSettings)
        settings = updated

        scheduleFormatApplication(previousSettings: previousSettings, updatedSettings: updated)
    }

    func updateFormatRule(_ keyPath: WritableKeyPath<FormatSettings, Bool>, isEnabled: Bool) {
        updateFormatSettings { formatSettings in
            formatSettings[keyPath: keyPath] = isEnabled
        }
    }

    private func scheduleFormatApplication(
        previousSettings: EditorSettings,
        updatedSettings: EditorSettings
    ) {
        guard scope == .activeWork else { return }
        guard previousSettings.formatSettings != updatedSettings.formatSettings else { return }

        formatTask?.cancel()
        formatGeneration += 1
        let generation = formatGeneration

        guard updatedSettings.formatSettings.enableAutoFormat else {
            isApplyingFormat = false
            return
        }

        let sourceDocument = documentStore.document
        let sourceFormatSettings = updatedSettings.validated.formatSettings
        let sourceOptions = FormatOptions(isPremiumUser: isPremiumUser)
        let operation = formatOperation
        isApplyingFormat = true

        formatTask = Task { [weak self] in
            let formattedBody = await operation(
                sourceDocument.body,
                sourceFormatSettings,
                sourceOptions
            )
            guard let self else { return }
            guard !Task.isCancelled,
                  formatGeneration == generation,
                  documentStore.document.id == sourceDocument.id,
                  documentStore.document.body == sourceDocument.body,
                  settings.formatSettings.validated == sourceFormatSettings,
                  FormatOptions(isPremiumUser: isPremiumUser) == sourceOptions else {
                if formatGeneration == generation {
                    isApplyingFormat = false
                }
                return
            }

            if formattedBody != sourceDocument.body {
                documentStore.updateBody(formattedBody)
            }
            isApplyingFormat = false
        }
    }

    private func schedulePrintSnapshotRefresh() {
        let source = currentPrintSnapshotSource
        guard requestedPrintSnapshotSource != source else { return }

        printSnapshotTask?.cancel()
        printSnapshotGeneration += 1
        let generation = printSnapshotGeneration
        requestedPrintSnapshotSource = source
        isCalculatingPrintSettings = true
        let operation = printSnapshotOperation

        printSnapshotTask = Task { [weak self] in
            let snapshot = await operation(source.body, source.settings)
            guard let self else { return }
            guard !Task.isCancelled,
                  printSnapshotGeneration == generation,
                  currentPrintSnapshotSource == source else {
                return
            }

            printSnapshotSource = source
            printSettingsSnapshot = snapshot
            isCalculatingPrintSettings = false
        }
    }

    nonisolated static func defaultFormatOperation(
        text: String,
        settings: FormatSettings,
        options: FormatOptions
    ) async -> String {
        await Task.detached(priority: .userInitiated) {
            ManuscriptFormatter.formatManuscriptText(
                text,
                settings: settings,
                options: options
            )
        }.value
    }

    nonisolated static func defaultPrintSnapshotOperation(
        body: String,
        settings: EditorSettings
    ) async -> PrintSettingsDisplaySnapshot {
        await Task.detached(priority: .utility) {
            PrintSettingsDisplaySnapshot.calculate(
                body: body,
                settings: settings
            )
        }.value
    }
}

private nonisolated struct PrintSnapshotSource: Equatable {
    let body: String
    let settings: EditorSettings
}
