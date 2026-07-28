@testable import Honkumi
import XCTest

final class PDFPreflightEmojiWarningTests: XCTestCase {
    func testEmojiAndHeartsProduceSeparateWarningsWithCountsAndReplacements() throws {
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
        let heartIssue = try XCTUnwrap(result.issues.first {
            $0.id == "print.textNormalization.heart"
        })
        let emojiIssue = try XCTUnwrap(result.issues.first {
            $0.id == "print.textNormalization.unsupportedEmoji"
        })

        XCTAssertEqual(normalizationIssues(in: result).count, 2)
        XCTAssertEqual(heartIssue.severity, .warning)
        XCTAssertTrue(heartIssue.message.contains("1件"))
        XCTAssertTrue(heartIssue.message.contains("♡"))
        XCTAssertEqual(emojiIssue.severity, .warning)
        XCTAssertTrue(emojiIssue.message.contains("2件"))
        XCTAssertTrue(emojiIssue.message.contains("□"))
        XCTAssertTrue(result.canContinue)
    }

    func testHeartOnlyProducesOneHeartWarning() throws {
        let document = ManuscriptDocument(title: "題♡", body: "本文❤️")

        let result = PDFPreflightService().check(
            document: document,
            subscriptionStatus: .free
        )
        let issue = try XCTUnwrap(normalizationIssues(in: result).first)

        XCTAssertEqual(normalizationIssues(in: result).count, 1)
        XCTAssertEqual(issue.id, "print.textNormalization.heart")
        XCTAssertTrue(issue.message.contains("1件"))
        XCTAssertTrue(issue.message.contains("♡"))
    }

    func testUnsupportedEmojiOnlyProducesOneEmojiWarning() throws {
        let document = ManuscriptDocument(title: "題😀", body: "本文💡")

        let result = PDFPreflightService().check(
            document: document,
            subscriptionStatus: .free
        )
        let issue = try XCTUnwrap(normalizationIssues(in: result).first)

        XCTAssertEqual(normalizationIssues(in: result).count, 1)
        XCTAssertEqual(issue.id, "print.textNormalization.unsupportedEmoji")
        XCTAssertTrue(issue.message.contains("2件"))
        XCTAssertTrue(issue.message.contains("□"))
    }

    func testNoEmojiAddsNoReplacementWarnings() {
        let document = ManuscriptDocument(title: "題", body: "本文")

        let result = PDFPreflightService().check(
            document: document,
            subscriptionStatus: .free
        )

        XCTAssertTrue(normalizationIssues(in: result).isEmpty)
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

        XCTAssertTrue(normalizationIssues(in: result).isEmpty)
    }

    private func normalizationIssues(in result: PreflightResult) -> [PreflightIssue] {
        result.issues.filter {
            $0.id == "print.textNormalization.heart" ||
                $0.id == "print.textNormalization.unsupportedEmoji"
        }
    }
}
