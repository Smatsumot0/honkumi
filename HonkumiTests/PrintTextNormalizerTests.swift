@testable import Honkumi
import XCTest

final class PrintTextNormalizerTests: XCTestCase {
    func testUnsupportedEmojiBecomesOneWhiteSquareWithoutCross() {
        let result = PrintTextNormalizer.normalize("前😀後", location: nil)

        XCTAssertEqual(result.text, "前□後")
        XCTAssertFalse(result.text.contains("×"))
        XCTAssertEqual(result.replacements.count, 1)
        XCTAssertEqual(result.replacements[0].replacement, "□")
        XCTAssertEqual(result.replacements[0].kind, .unsupportedEmoji)
    }

    func testHeartReplacementRemainsOpenHeart() {
        XCTAssertEqual(
            PrintTextNormalizer.normalize("❤️", location: nil).text,
            "♡"
        )
    }

    func testReportSampleUsesSingleSquare() {
        let report = PrintTextNormalizer.report(
            title: "題😀",
            body: "本文",
            colophon: .default
        )

        XCTAssertEqual(report.unsupportedEmojiReplacementCount, 1)
        XCTAssertTrue(report.sampleLocations.contains("😀→□"))
        XCTAssertFalse(report.sampleLocations.contains("×"))
    }
}
