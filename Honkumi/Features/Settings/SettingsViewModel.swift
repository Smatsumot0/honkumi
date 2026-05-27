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

    func updatePageSize(_ value: PageSize) {
        var updated = settings
        updated.pageSize = value
        settings = updated
    }

    func updateJapaneseFont(_ value: JapaneseFont) {
        var updated = settings
        updated.japaneseFont = value
        settings = updated
    }

    func updateFontSize(_ value: CGFloat) {
        var updated = settings
        updated.fontSize = value
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

    func updateShowTableOfContents(_ value: Bool) {
        var updated = settings
        updated.showTableOfContents = value
        settings = updated
    }

    func updatePageNumberPosition(_ value: PageNumberPosition) {
        var updated = settings
        updated.pageNumberPosition = value
        settings = updated
    }
}
