@testable import Honkumi
import XCTest

final class PrintSettingsDisplaySnapshotTests: XCTestCase {
    func testSnapshotUsesEffectiveSettingsForPageCountAndWideGutterNote() {
        var settings = EditorSettings.default
        settings.useRecommendedTypography = true
        settings.useRecommendedMargins = true
        let body = String(repeating: "本文です。\n", count: 4_000)

        let snapshot = PrintSettingsDisplaySnapshot.calculate(
            body: body,
            settings: settings
        )

        XCTAssertEqual(
            snapshot.estimatedPageCount,
            RecommendedPrintSettings.estimatedPageCount(
                body: body,
                settings: snapshot.settings
            )
        )
        XCTAssertEqual(
            snapshot.showsWideGutterNote,
            snapshot.estimatedPageCount >= 97
        )
    }
}
