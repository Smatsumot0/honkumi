@testable import Honkumi
import XCTest

final class ContentFormattingSessionTests: XCTestCase {
    func testSnapshotCapturesWorkSettingsAndEntitlementAtOpenTime() {
        var document = ManuscriptDocument(title: "Work", body: "本文")
        document.settings.formatSettings.enableAutoFormat = true
        let snapshot = ManuscriptFormatSessionSnapshot(
            documentID: document.id,
            formatSettings: document.settings.formatSettings,
            formatOptions: FormatOptions(isPremiumUser: false)
        )

        document.settings.formatSettings.enableNormalizePunctuation = true

        XCTAssertFalse(snapshot.formatSettings.enableNormalizePunctuation)
        XCTAssertFalse(snapshot.formatOptions.isPremiumUser)
    }
}
