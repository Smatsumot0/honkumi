import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    enum Scope {
        case activeWork
        case userDefault
    }

    @Published private(set) var document: ManuscriptDocument
    @Published private(set) var userDefaultSettings: EditorSettings

    private let documentStore: DocumentStore
    private let scope: Scope

    init(documentStore: DocumentStore, scope: Scope = .activeWork) {
        self.documentStore = documentStore
        self.scope = scope
        self.document = documentStore.document
        self.userDefaultSettings = documentStore.userDefaultSettings

        documentStore.$document
            .assign(to: &$document)

        documentStore.$appData
            .map(\.userDefaultSettings)
            .assign(to: &$userDefaultSettings)
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
        RecommendedPrintSettings.effectiveSettings(
            body: printRecommendationBody,
            settings: settings
        )
    }

    var estimatedPrintPageCount: Int {
        RecommendedPrintSettings.estimatedPageCount(
            body: printRecommendationBody,
            settings: printSettingsForDisplay
        )
    }

    private var printRecommendationBody: String {
        switch scope {
        case .activeWork:
            document.body
        case .userDefault:
            document.body
        }
    }

    func updateUseRecommendedPrintSettings(_ value: Bool) {
        var updated = settings
        if updated.useRecommendedPrintSettings,
           !value,
           Self.hasDefaultManualPrintFields(updated) {
            updated = Self.copyManualPrintFields(from: printSettingsForDisplay, to: updated)
        }
        updated.useRecommendedPrintSettings = value
        settings = updated
    }

    private static func hasDefaultManualPrintFields(_ settings: EditorSettings) -> Bool {
        let defaults = EditorSettings.default
        return settings.selectedFontId == defaults.selectedFontId
            && settings.fontSize == defaults.fontSize
            && settings.lineSpacing == defaults.lineSpacing
            && settings.characterSpacing == defaults.characterSpacing
            && settings.charactersPerLine == defaults.charactersPerLine
            && settings.linesPerPage == defaults.linesPerPage
            && settings.marginTop == defaults.marginTop
            && settings.marginBottom == defaults.marginBottom
            && settings.marginInner == defaults.marginInner
            && settings.marginOuter == defaults.marginOuter
    }

    private static func copyManualPrintFields(
        from recommended: EditorSettings,
        to settings: EditorSettings
    ) -> EditorSettings {
        var updated = settings
        updated.selectedFontId = recommended.selectedFontId
        updated.fontSize = recommended.fontSize
        updated.lineSpacing = recommended.lineSpacing
        updated.characterSpacing = recommended.characterSpacing
        updated.charactersPerLine = recommended.charactersPerLine
        updated.linesPerPage = recommended.linesPerPage
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
        updated.fontSize = value
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
        updated.lineSpacing = value
        settings = updated
    }

    func updateCharacterSpacing(_ value: CGFloat) {
        var updated = settings
        updated.characterSpacing = value
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

        applyFormatIfAutoFormatWasEnabled(previousSettings: previousSettings, updatedSettings: updated)
    }

    func updateFormatRule(_ keyPath: WritableKeyPath<FormatSettings, Bool>, isEnabled: Bool) {
        updateFormatSettings { formatSettings in
            formatSettings[keyPath: keyPath] = isEnabled
        }
    }

    private func applyFormatIfAutoFormatWasEnabled(
        previousSettings: EditorSettings,
        updatedSettings: EditorSettings
    ) {
        guard scope == .activeWork else { return }
        guard !previousSettings.formatSettings.enableAutoFormat,
              updatedSettings.formatSettings.enableAutoFormat else { return }

        let formattedBody = ManuscriptFormatter.formatManuscriptText(
            document.body,
            settings: updatedSettings.validated.formatSettings,
            options: FormatOptions(isPremiumUser: isPremiumUser)
        )
        guard formattedBody != document.body else { return }

        documentStore.updateBody(formattedBody)
    }
}
