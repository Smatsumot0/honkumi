@testable import Honkumi
import XCTest

final class PDFPreflightEmojiWarningTests: XCTestCase {
    func testEmojiAndHeartsProduceOneWarningWithCountsAndReplacements() throws {
        var settings = EditorSettings.default
        settings.colophon.isEnabled = false
        let document = ManuscriptDocument(
            title: "題😀",
            body: "本文💡と❤️",
            settings: settings
        )

        let result = PDFPreflightService().check(
            document: document,
            subscriptionStatus: .free
        )
        let issues = result.issues.filter {
            $0.id == "print.textNormalization.emoji"
        }

        let issue = try XCTUnwrap(issues.first)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issue.severity, .warning)
        XCTAssertTrue(issue.message.contains("合計3件"))
        XCTAssertTrue(issue.message.contains("2件を□"))
        XCTAssertTrue(issue.message.contains("1件を♡"))
        XCTAssertTrue(result.canContinue)
    }

    func testNoEmojiAddsNoReplacementWarning() {
        let document = ManuscriptDocument(title: "題", body: "本文")

        let result = PDFPreflightService().check(
            document: document,
            subscriptionStatus: .free
        )

        XCTAssertFalse(result.issues.contains {
            $0.id == "print.textNormalization.emoji"
        })
    }

    func testHiddenColophonEmojiIsNotCounted() {
        var settings = EditorSettings.default
        settings.colophon.isEnabled = true
        settings.colophon.showsCircleName = false
        settings.colophon.circleName = "非表示😀"
        let document = ManuscriptDocument(
            title: "題",
            body: "本文",
            settings: settings
        )

        let result = PDFPreflightService().check(
            document: document,
            subscriptionStatus: .free
        )

        XCTAssertFalse(result.issues.contains {
            $0.id == "print.textNormalization.emoji"
        })
    }
}
