@testable import Honkumi
import XCTest

@MainActor
final class UserDefaultSettingsReviewTests: XCTestCase {
    func testLegacyZeroRevisionDoesNotRequestImmediateReview() {
        let store = makeStore(commonRevision: 0, reviewedRevision: 0)

        XCTAssertNil(
            store.userDefaultSettingsReviewRequest(for: store.document.id)
        )
    }

    func testOlderWorkRequestsReviewAfterCommonRevisionAdvances() {
        let store = makeStore(commonRevision: 2, reviewedRevision: 1)

        XCTAssertEqual(
            store.userDefaultSettingsReviewRequest(for: store.document.id),
            UserDefaultSettingsReviewRequest(
                workID: store.document.id,
                revision: 2
            )
        )
    }

    func testEditorSelectionChangesOnlyEditorSettings() throws {
        let store = makeStore(commonRevision: 3, reviewedRevision: 1)
        let before = store.document.settings
        var defaults = store.userDefaultSettings
        defaults.editorFontId = "NotoSansJP-Regular"
        defaults.editorFontSize = 18
        defaults.pageSize = .b6
        defaults.formatSettings.enableAutoFormat = true
        defaults.colophon.authorName = "共通作者"
        store.updateUserDefaultSettings(defaults)
        let request = try XCTUnwrap(
            store.userDefaultSettingsReviewRequest(for: store.document.id)
        )

        let result = store.resolveUserDefaultSettingsReview(
            request,
            decision: .apply(UserDefaultSettingsSelection(editor: true))
        )

        XCTAssertTrue(result.didSelect)
        XCTAssertFalse(result.shouldFormat)
        XCTAssertEqual(store.document.settings.editorFontId, "NotoSansJP-Regular")
        XCTAssertEqual(store.document.settings.editorFontSize, 18)
        XCTAssertEqual(store.document.settings.pageSize, before.pageSize)
        XCTAssertEqual(store.document.settings.formatSettings, before.formatSettings)
        XCTAssertEqual(store.document.settings.colophon, before.colophon)
        XCTAssertEqual(
            store.document.reviewedUserDefaultSettingsRevision,
            3
        )
    }

    func testCircleSelectionChangesOnlyPublisherInformation() throws {
        let store = makeStore(commonRevision: 3, reviewedRevision: 1)
        var workSettings = store.document.settings
        workSettings.colophon.isEnabled = true
        workSettings.colophon.workTitle = "作品固有の奥付タイトル"
        workSettings.colophon.publicationDate = Date(timeIntervalSince1970: 1_700_000_000)
        workSettings.colophon.showsPublicationDate = true
        workSettings.colophon.printerName = "作品の印刷所"
        workSettings.colophon.showsPrinterName = true
        store.updateSettings(workSettings)
        let before = store.document.settings

        var defaults = store.userDefaultSettings
        defaults.colophon.publisherName = "共通発行者"
        defaults.colophon.authorName = "共通作者"
        defaults.colophon.circleName = "共通サークル"
        defaults.colophon.authorImageData = Data([0x02])
        defaults.colophon.circleImageData = Data([0x01])
        defaults.colophon.usesCircleImageForCreator = true
        defaults.colophon.showsPublisherName = false
        defaults.colophon.showsAuthorName = false
        defaults.colophon.showsCircleName = false
        defaults.colophon.showsWebsiteURL = false
        defaults.colophon.showsQRCode = false
        defaults.colophon.websiteURL = "https://example.com"
        defaults.colophon.xURL = "https://x.example.com"
        defaults.colophon.pixivURL = "https://pixiv.example.com"
        defaults.colophon.contact = "contact@example.com"
        defaults.colophon.notes = "共通メモ"
        defaults.colophon.isEnabled = false
        defaults.colophon.publicationDate = nil
        defaults.colophon.printerName = "共通の印刷所"
        defaults.pageSize = .b6
        defaults.editorFontSize = 18
        defaults.formatSettings.enableAutoFormat = true
        store.updateUserDefaultSettings(defaults)
        let request = try XCTUnwrap(
            store.userDefaultSettingsReviewRequest(for: store.document.id)
        )

        let result = store.resolveUserDefaultSettingsReview(
            request,
            decision: .apply(UserDefaultSettingsSelection(circle: true))
        )

        XCTAssertTrue(result.didSelect)
        XCTAssertFalse(result.shouldFormat)
        XCTAssertEqual(store.document.settings.colophon.publisherName, "共通発行者")
        XCTAssertEqual(store.document.settings.colophon.authorName, "共通作者")
        XCTAssertEqual(store.document.settings.colophon.circleName, "共通サークル")
        XCTAssertEqual(store.document.settings.colophon.authorImageData, Data([0x02]))
        XCTAssertEqual(store.document.settings.colophon.circleImageData, Data([0x01]))
        XCTAssertTrue(store.document.settings.colophon.usesCircleImageForCreator)
        XCTAssertFalse(store.document.settings.colophon.showsPublisherName)
        XCTAssertFalse(store.document.settings.colophon.showsAuthorName)
        XCTAssertFalse(store.document.settings.colophon.showsCircleName)
        XCTAssertFalse(store.document.settings.colophon.showsWebsiteURL)
        XCTAssertFalse(store.document.settings.colophon.showsQRCode)
        XCTAssertEqual(store.document.settings.colophon.websiteURL, "https://example.com")
        XCTAssertEqual(store.document.settings.colophon.xURL, "https://x.example.com")
        XCTAssertEqual(store.document.settings.colophon.pixivURL, "https://pixiv.example.com")
        XCTAssertEqual(store.document.settings.colophon.contact, "contact@example.com")
        XCTAssertEqual(store.document.settings.colophon.notes, "共通メモ")
        XCTAssertTrue(store.document.settings.colophon.isEnabled)
        XCTAssertEqual(store.document.settings.colophon.workTitle, "作品固有の奥付タイトル")
        XCTAssertEqual(
            store.document.settings.colophon.publicationDate,
            Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertTrue(store.document.settings.colophon.showsPublicationDate)
        XCTAssertEqual(store.document.settings.colophon.printerName, "作品の印刷所")
        XCTAssertTrue(store.document.settings.colophon.showsPrinterName)
        XCTAssertEqual(store.document.settings.pageSize, before.pageSize)
        XCTAssertEqual(store.document.settings.editorFontSize, before.editorFontSize)
        XCTAssertEqual(store.document.settings.formatSettings, before.formatSettings)
    }

    func testFormatSelectionChangesOnlyFormatSettingsAndRequestsFormatting() throws {
        let store = makeStore(commonRevision: 3, reviewedRevision: 1)
        let before = store.document.settings
        var defaults = store.userDefaultSettings
        defaults.formatSettings.enableAutoFormat = true
        defaults.formatSettings.enableIndent = true
        defaults.formatSettings.skipIndentBeforeOpeningQuote = false
        defaults.formatSettings.enableTrimLineSpaces = false
        defaults.formatSettings.enableNormalizeBlankLines = false
        defaults.formatSettings.maxConsecutiveBlankLines = 3
        defaults.formatSettings.enableNormalizePageBreakSpacing = false
        defaults.formatSettings.enableNormalizeConsecutiveExclamationQuestion = true
        defaults.formatSettings.enableNormalizeEllipsis = true
        defaults.formatSettings.enableNormalizeDash = true
        defaults.formatSettings.enableSpaceAfterExclamationQuestion = true
        defaults.formatSettings.enableNormalizePunctuation = true
        defaults.formatSettings.enableNormalizeBrackets = true
        defaults.formatSettings.enableRemovePeriodsBeforeClosingBrackets = true
        defaults.pageSize = .b6
        defaults.editorFontSize = 18
        defaults.colophon.authorName = "共通作者"
        store.updateUserDefaultSettings(defaults)
        let request = try XCTUnwrap(
            store.userDefaultSettingsReviewRequest(for: store.document.id)
        )

        let result = store.resolveUserDefaultSettingsReview(
            request,
            decision: .apply(UserDefaultSettingsSelection(format: true))
        )

        XCTAssertTrue(result.didSelect)
        XCTAssertTrue(result.shouldFormat)
        XCTAssertTrue(store.document.settings.formatSettings.enableAutoFormat)
        XCTAssertTrue(store.document.settings.formatSettings.enableIndent)
        XCTAssertFalse(store.document.settings.formatSettings.skipIndentBeforeOpeningQuote)
        XCTAssertFalse(store.document.settings.formatSettings.enableTrimLineSpaces)
        XCTAssertFalse(store.document.settings.formatSettings.enableNormalizeBlankLines)
        XCTAssertEqual(store.document.settings.formatSettings.maxConsecutiveBlankLines, 3)
        XCTAssertFalse(store.document.settings.formatSettings.enableNormalizePageBreakSpacing)
        XCTAssertTrue(store.document.settings.formatSettings.enableNormalizeConsecutiveExclamationQuestion)
        XCTAssertTrue(store.document.settings.formatSettings.enableNormalizeEllipsis)
        XCTAssertTrue(store.document.settings.formatSettings.enableNormalizeDash)
        XCTAssertTrue(store.document.settings.formatSettings.enableSpaceAfterExclamationQuestion)
        XCTAssertTrue(store.document.settings.formatSettings.enableNormalizePunctuation)
        XCTAssertTrue(store.document.settings.formatSettings.enableNormalizeBrackets)
        XCTAssertTrue(store.document.settings.formatSettings.enableRemovePeriodsBeforeClosingBrackets)
        XCTAssertEqual(store.document.settings.pageSize, before.pageSize)
        XCTAssertEqual(store.document.settings.editorFontSize, before.editorFontSize)
        XCTAssertEqual(store.document.settings.colophon, before.colophon)
    }

    func testFormatSelectionDoesNotRequestFormattingWhenAutoFormatIsOff() throws {
        let store = makeStore(commonRevision: 3, reviewedRevision: 1)
        var defaults = store.userDefaultSettings
        defaults.formatSettings.enableAutoFormat = false
        defaults.formatSettings.enableNormalizePunctuation = true
        store.updateUserDefaultSettings(defaults)
        let request = try XCTUnwrap(
            store.userDefaultSettingsReviewRequest(for: store.document.id)
        )

        let result = store.resolveUserDefaultSettingsReview(
            request,
            decision: .apply(UserDefaultSettingsSelection(format: true))
        )

        XCTAssertTrue(result.didSelect)
        XCTAssertFalse(result.shouldFormat)
        XCTAssertFalse(store.document.settings.formatSettings.enableAutoFormat)
        XCTAssertTrue(store.document.settings.formatSettings.enableNormalizePunctuation)
    }

    func testPrintSelectionChangesOnlyPrintSettingsAndPreservesWorkColophon() throws {
        let store = makeStore(commonRevision: 3, reviewedRevision: 1)
        var workSettings = store.document.settings
        workSettings.colophon.isEnabled = true
        workSettings.colophon.workTitle = "作品固有の奥付タイトル"
        workSettings.colophon.publicationDate = Date(timeIntervalSince1970: 1_700_000_000)
        workSettings.colophon.showsPublicationDate = true
        workSettings.colophon.printerName = "作品の印刷所"
        workSettings.colophon.showsPrinterName = true
        store.updateSettings(workSettings)
        let before = store.document.settings

        var defaults = store.userDefaultSettings
        defaults.pageSize = .b6
        defaults.selectedFontId = "shippori-mincho"
        defaults.fontSize = 10.5
        defaults.lineSpacing = 5
        defaults.characterSpacing = 3
        defaults.charactersPerLine = 40
        defaults.linesPerPage = 20
        defaults.marginTop = 20
        defaults.marginBottom = 21
        defaults.marginInner = 24
        defaults.marginOuter = 20
        defaults.isPageNumberEnabled = false
        defaults.pageNumberFontId = "love-light"
        defaults.pageNumberSize = 11
        defaults.pageNumberStart = 3
        defaults.pageNumberPosition = .center
        defaults.showPageNumberOnToc = false
        defaults.showPageNumberOnColophon = false
        defaults.showTableOfContents = true
        defaults.showChapterTitle = true
        defaults.chapterTitleStyle = .brackets
        defaults.startsChapterOnNewPage = true
        defaults.alphanumericOrientation = .stacked
        defaults.useRecommendedTypography = false
        defaults.useRecommendedMargins = false
        defaults.showsCropMarks = true
        defaults.colophon.isEnabled = false
        defaults.colophon.publicationDate = nil
        defaults.colophon.showsPublicationDate = false
        defaults.colophon.printerName = "共通の印刷所"
        defaults.colophon.showsPrinterName = false
        defaults.editorFontSize = 18
        defaults.formatSettings.enableAutoFormat = true
        store.updateUserDefaultSettings(defaults)
        let request = try XCTUnwrap(
            store.userDefaultSettingsReviewRequest(for: store.document.id)
        )

        let result = store.resolveUserDefaultSettingsReview(
            request,
            decision: .apply(UserDefaultSettingsSelection(print: true))
        )

        XCTAssertTrue(result.didSelect)
        XCTAssertFalse(result.shouldFormat)
        XCTAssertEqual(store.document.settings.pageSize, .b6)
        XCTAssertEqual(store.document.settings.selectedFontId, "shippori-mincho")
        XCTAssertEqual(store.document.settings.fontSize, 10.5)
        XCTAssertEqual(store.document.settings.lineSpacing, 0)
        XCTAssertEqual(store.document.settings.characterSpacing, 0)
        XCTAssertEqual(store.document.settings.charactersPerLine, 40)
        XCTAssertEqual(store.document.settings.linesPerPage, 20)
        XCTAssertEqual(store.document.settings.marginTop, 20)
        XCTAssertEqual(store.document.settings.marginBottom, 21)
        XCTAssertEqual(store.document.settings.marginInner, 24)
        XCTAssertEqual(store.document.settings.marginOuter, 20)
        XCTAssertFalse(store.document.settings.isPageNumberEnabled)
        XCTAssertEqual(store.document.settings.pageNumberFontId, "love-light")
        XCTAssertEqual(store.document.settings.pageNumberSize, 11)
        XCTAssertEqual(store.document.settings.pageNumberStart, 3)
        XCTAssertEqual(store.document.settings.pageNumberPosition, .center)
        XCTAssertFalse(store.document.settings.showPageNumberOnToc)
        XCTAssertFalse(store.document.settings.showPageNumberOnColophon)
        XCTAssertTrue(store.document.settings.showTableOfContents)
        XCTAssertTrue(store.document.settings.showChapterTitle)
        XCTAssertEqual(store.document.settings.chapterTitleStyle, .brackets)
        XCTAssertTrue(store.document.settings.startsChapterOnNewPage)
        XCTAssertEqual(store.document.settings.alphanumericOrientation, .stacked)
        XCTAssertFalse(store.document.settings.useRecommendedTypography)
        XCTAssertFalse(store.document.settings.useRecommendedMargins)
        XCTAssertTrue(store.document.settings.showsCropMarks)
        XCTAssertTrue(store.document.settings.colophon.isEnabled)
        XCTAssertEqual(store.document.settings.colophon.workTitle, "作品固有の奥付タイトル")
        XCTAssertTrue(store.document.settings.colophon.showsPublicationDate)
        XCTAssertTrue(store.document.settings.colophon.showsPrinterName)
        XCTAssertEqual(
            store.document.settings.colophon.publicationDate,
            Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(store.document.settings.colophon.printerName, "作品の印刷所")
        XCTAssertEqual(store.document.settings.editorFontSize, before.editorFontSize)
        XCTAssertEqual(store.document.settings.formatSettings, before.formatSettings)
    }

    func testEmptySelectionDoesNotApplySelectOrReview() throws {
        let store = makeStore(commonRevision: 3, reviewedRevision: 1)
        let request = try XCTUnwrap(
            store.userDefaultSettingsReviewRequest(for: store.document.id)
        )
        let before = store.appData

        let result = store.resolveUserDefaultSettingsReview(
            request,
            decision: .apply(UserDefaultSettingsSelection())
        )

        XCTAssertEqual(result, .unchanged)
        XCTAssertEqual(store.appData, before)
    }

    func testCombinedSelectionAppliesOnlySelectedGroups() throws {
        let store = makeStore(commonRevision: 3, reviewedRevision: 1)
        let before = store.document.settings
        var defaults = store.userDefaultSettings
        defaults.editorFontSize = 18
        defaults.colophon.authorName = "共通作者"
        defaults.pageSize = .b6
        defaults.formatSettings.enableAutoFormat = true
        store.updateUserDefaultSettings(defaults)
        let request = try XCTUnwrap(
            store.userDefaultSettingsReviewRequest(for: store.document.id)
        )

        let result = store.resolveUserDefaultSettingsReview(
            request,
            decision: .apply(
                UserDefaultSettingsSelection(editor: true, circle: true)
            )
        )

        XCTAssertTrue(result.didSelect)
        XCTAssertFalse(result.shouldFormat)
        XCTAssertEqual(store.document.settings.editorFontSize, 18)
        XCTAssertEqual(store.document.settings.colophon.authorName, "共通作者")
        XCTAssertEqual(store.document.settings.pageSize, before.pageSize)
        XCTAssertEqual(store.document.settings.formatSettings, before.formatSettings)
    }

    func testApplyAllCopiesEveryGroupExceptWorkSpecificColophon() throws {
        let store = makeStore(commonRevision: 3, reviewedRevision: 1)
        var workSettings = store.document.settings
        workSettings.colophon.isEnabled = true
        workSettings.colophon.publicationDate = Date(timeIntervalSince1970: 1_700_000_000)
        workSettings.colophon.showsPublicationDate = true
        workSettings.colophon.printerName = "作品の印刷所"
        workSettings.colophon.showsPrinterName = true
        store.updateSettings(workSettings)

        var defaults = store.userDefaultSettings
        defaults.editorFontSize = 18
        defaults.pageSize = .b6
        defaults.marginInner = 24
        defaults.formatSettings.enableAutoFormat = true
        defaults.formatSettings.enableNormalizePunctuation = true
        defaults.colophon.authorName = "共通作者"
        defaults.colophon.isEnabled = false
        defaults.colophon.publicationDate = nil
        defaults.colophon.showsPublicationDate = false
        defaults.colophon.printerName = "共通の印刷所"
        defaults.colophon.showsPrinterName = false
        store.updateUserDefaultSettings(defaults)
        let request = try XCTUnwrap(
            store.userDefaultSettingsReviewRequest(for: store.document.id)
        )

        let result = store.resolveUserDefaultSettingsReview(
            request,
            decision: .apply(.all)
        )

        XCTAssertTrue(result.didSelect)
        XCTAssertTrue(result.shouldFormat)
        XCTAssertEqual(store.document.settings.editorFontSize, 18)
        XCTAssertEqual(store.document.settings.pageSize, .b6)
        XCTAssertEqual(store.document.settings.marginInner, 24)
        XCTAssertTrue(store.document.settings.formatSettings.enableAutoFormat)
        XCTAssertTrue(store.document.settings.formatSettings.enableNormalizePunctuation)
        XCTAssertEqual(store.document.settings.colophon.authorName, "共通作者")
        XCTAssertTrue(store.document.settings.colophon.isEnabled)
        XCTAssertEqual(
            store.document.settings.colophon.publicationDate,
            Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertTrue(store.document.settings.colophon.showsPublicationDate)
        XCTAssertEqual(store.document.settings.colophon.printerName, "作品の印刷所")
        XCTAssertTrue(store.document.settings.colophon.showsPrinterName)
        XCTAssertEqual(store.document.reviewedUserDefaultSettingsRevision, 3)
    }

    func testKeepCurrentPreservesSettingsAndBodyButReviewsRevision() throws {
        let store = makeStore(commonRevision: 3, reviewedRevision: 1)
        let original = store.document
        let request = try XCTUnwrap(
            store.userDefaultSettingsReviewRequest(for: original.id)
        )

        let result = store.resolveUserDefaultSettingsReview(
            request,
            decision: .keepCurrent
        )

        XCTAssertTrue(result.didSelect)
        XCTAssertFalse(result.shouldFormat)
        XCTAssertEqual(store.document.settings, original.settings)
        XCTAssertEqual(store.document.body, original.body)
        XCTAssertEqual(store.document.updatedAt, original.updatedAt)
        XCTAssertEqual(
            store.document.reviewedUserDefaultSettingsRevision,
            3
        )
    }

    func testStaleRequestChangesNothing() {
        let store = makeStore(commonRevision: 3, reviewedRevision: 1)
        let request = UserDefaultSettingsReviewRequest(
            workID: store.document.id,
            revision: 2
        )
        let before = store.appData

        let result = store.resolveUserDefaultSettingsReview(
            request,
            decision: .apply(.all)
        )

        XCTAssertFalse(result.didSelect)
        XCTAssertFalse(result.shouldFormat)
        XCTAssertEqual(store.appData, before)
    }

    func testAlreadyReviewedWorkCanBeSelectedWithoutARequest() {
        let first = ManuscriptDocument(
            title: "First",
            body: "本文",
            reviewedUserDefaultSettingsRevision: 2
        )
        let second = ManuscriptDocument(
            title: "Second",
            body: "本文",
            reviewedUserDefaultSettingsRevision: 2
        )
        let store = DocumentStore(
            appData: AppData(
                version: AppData.currentVersion,
                categories: [.uncategorized],
                works: [first, second],
                userDefaultSettings: .default,
                activeWorkId: first.id,
                subscriptionStatus: .free,
                userDefaultSettingsRevision: 2
            )
        )

        XCTAssertNil(
            store.userDefaultSettingsReviewRequest(for: second.id)
        )
        store.selectWork(id: second.id)
        XCTAssertEqual(store.document.id, second.id)
    }

    private func makeStore(
        commonRevision: Int,
        reviewedRevision: Int
    ) -> DocumentStore {
        var work = ManuscriptDocument(
            title: "作品",
            body: "A,B.",
            reviewedUserDefaultSettingsRevision: reviewedRevision
        )
        work.settings.editorFontSize = 11
        return DocumentStore(
            appData: AppData(
                version: AppData.currentVersion,
                categories: [.uncategorized],
                works: [work],
                userDefaultSettings: .default,
                activeWorkId: work.id,
                subscriptionStatus: .paid,
                userDefaultSettingsRevision: commonRevision
            )
        )
    }
}
