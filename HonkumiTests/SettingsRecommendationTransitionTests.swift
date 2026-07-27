@testable import Honkumi
import XCTest

@MainActor
final class SettingsRecommendationTransitionTests: XCTestCase {
    func testTurningOffRecommendedTypographyCopiesDisplayedValuesOverNonDefaultManualValues() {
        var document = ManuscriptDocument(title: "Typography", body: longBody)
        document.settings.pageSize = .a6
        document.settings.useRecommendedTypography = true
        document.settings.fontSize = 19
        document.settings.charactersPerLine = 25
        document.settings.linesPerPage = 12
        let viewModel = makeViewModel(document: document)
        let displayed = viewModel.printSettingsForDisplay

        viewModel.updateUseRecommendedTypography(false)

        XCTAssertFalse(viewModel.settings.useRecommendedTypography)
        XCTAssertEqual(viewModel.settings.fontSize, displayed.fontSize)
        XCTAssertEqual(viewModel.settings.charactersPerLine, displayed.charactersPerLine)
        XCTAssertEqual(viewModel.settings.linesPerPage, displayed.linesPerPage)
    }

    func testTurningOffRecommendedMarginsCopiesDisplayedValuesOverNonDefaultManualValues() {
        var document = ManuscriptDocument(title: "Margins", body: longBody)
        document.settings.pageSize = .a6
        document.settings.useRecommendedMargins = true
        document.settings.marginTop = 30
        document.settings.marginBottom = 29
        document.settings.marginInner = 28
        document.settings.marginOuter = 24
        let viewModel = makeViewModel(document: document)
        let displayed = viewModel.printSettingsForDisplay

        viewModel.updateUseRecommendedMargins(false)

        XCTAssertFalse(viewModel.settings.useRecommendedMargins)
        XCTAssertEqual(viewModel.settings.marginTop, displayed.marginTop)
        XCTAssertEqual(viewModel.settings.marginBottom, displayed.marginBottom)
        XCTAssertEqual(viewModel.settings.marginInner, displayed.marginInner)
        XCTAssertEqual(viewModel.settings.marginOuter, displayed.marginOuter)
    }

    func testUnsupportedLegacySizeOnlyTurnsOffRecommendedTypography() {
        var document = ManuscriptDocument(title: "Legacy", body: longBody)
        document.settings.pageSize = .a5
        document.settings.useRecommendedTypography = true
        document.settings.fontSize = 19
        document.settings.charactersPerLine = 25
        document.settings.linesPerPage = 12
        let viewModel = makeViewModel(document: document)
        let before = viewModel.settings

        viewModel.updateUseRecommendedTypography(false)

        XCTAssertFalse(viewModel.settings.useRecommendedTypography)
        XCTAssertEqual(viewModel.settings.fontSize, before.fontSize)
        XCTAssertEqual(viewModel.settings.charactersPerLine, before.charactersPerLine)
        XCTAssertEqual(viewModel.settings.linesPerPage, before.linesPerPage)
    }

    func testUnsupportedLegacySizeOnlyTurnsOffRecommendedMargins() {
        var document = ManuscriptDocument(title: "Legacy", body: longBody)
        document.settings.pageSize = .b5
        document.settings.useRecommendedMargins = true
        document.settings.marginTop = 30
        document.settings.marginBottom = 29
        document.settings.marginInner = 28
        document.settings.marginOuter = 24
        let viewModel = makeViewModel(document: document)
        let before = viewModel.settings

        viewModel.updateUseRecommendedMargins(false)

        XCTAssertFalse(viewModel.settings.useRecommendedMargins)
        XCTAssertEqual(viewModel.settings.marginTop, before.marginTop)
        XCTAssertEqual(viewModel.settings.marginBottom, before.marginBottom)
        XCTAssertEqual(viewModel.settings.marginInner, before.marginInner)
        XCTAssertEqual(viewModel.settings.marginOuter, before.marginOuter)
    }

    func testTransitionsOtherThanOnToOffDoNotOverwriteManualTypography() {
        var document = ManuscriptDocument(title: "Transitions", body: longBody)
        document.settings.pageSize = .a6
        document.settings.useRecommendedTypography = false
        document.settings.fontSize = 19
        document.settings.charactersPerLine = 25
        document.settings.linesPerPage = 12
        let viewModel = makeViewModel(document: document)

        viewModel.updateUseRecommendedTypography(false)
        XCTAssertEqual(viewModel.settings.fontSize, 19)

        viewModel.updateUseRecommendedTypography(true)
        XCTAssertEqual(viewModel.settings.fontSize, 19)

        viewModel.updateUseRecommendedTypography(true)
        XCTAssertEqual(viewModel.settings.fontSize, 19)
    }

    private var longBody: String {
        String(repeating: "長い本文です。", count: 5_000)
    }

    private func makeViewModel(document: ManuscriptDocument) -> SettingsViewModel {
        let store = DocumentStore(
            appData: AppData(
                version: AppData.currentVersion,
                categories: [.uncategorized],
                works: [document],
                userDefaultSettings: .default,
                activeWorkId: document.id,
                subscriptionStatus: .free
            )
        )
        return SettingsViewModel(documentStore: store)
    }
}
