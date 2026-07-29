@testable import Honkumi
import XCTest

final class ManuscriptLiveFormatterTests: XCTestCase {
    func testFormatsOnlyTheEditedLine() {
        var settings = FormatSettings.default
        settings.enableAutoFormat = true
        settings.enableNormalizePunctuation = true
        let input = "A,B.\n遠い行,."

        let result = ManuscriptLiveFormatter.format(
            input,
            changedRange: NSRange(location: 0, length: 4),
            selectedRange: NSRange(location: 4, length: 0),
            settings: settings,
            options: FormatOptions(isPremiumUser: true)
        )

        XCTAssertEqual(result.text, "A、B。\n遠い行,.")
        XCTAssertEqual(result.selectedRange, NSRange(location: 4, length: 0))
        XCTAssertLessThan(result.replacementRange.length, (input as NSString).length)
    }

    func testMultiLinePasteFormatsAllPastedLinesButNotRemoteLines() {
        var settings = FormatSettings.default
        settings.enableAutoFormat = true
        settings.enableNormalizePunctuation = true
        settings.enableNormalizeBrackets = true
        let input = "遠い行,\nA,B.\n(C,D.)\n別の遠い行,"
        let changedRange = (input as NSString).range(of: "A,B.\n(C,D.)")

        let result = ManuscriptLiveFormatter.format(
            input,
            changedRange: changedRange,
            selectedRange: NSRange(location: NSMaxRange(changedRange), length: 0),
            settings: settings,
            options: FormatOptions(isPremiumUser: true)
        )

        XCTAssertEqual(result.text, "遠い行,\nA、B。\n（C、D。）\n別の遠い行,")
    }

    func testRemovingPeriodBeforeClosingBracketKeepsCursorAtCommittedInputBoundary() {
        var settings = FormatSettings.default
        settings.enableAutoFormat = true
        settings.enableRemovePeriodsBeforeClosingBrackets = true

        let result = ManuscriptLiveFormatter.format(
            "「てすと。」",
            changedRange: NSRange(location: 4, length: 1),
            selectedRange: NSRange(location: 5, length: 0),
            settings: settings,
            options: FormatOptions(isPremiumUser: true)
        )

        XCTAssertEqual(result.text, "「てすと」")
        XCTAssertEqual(result.selectedRange, NSRange(location: 4, length: 0))
    }

    func testFormatsTheConnectedBlankLineBlockWithoutTouchingRemoteText() {
        var settings = FormatSettings.default
        settings.enableAutoFormat = true
        settings.enableNormalizeBlankLines = true
        settings.maxConsecutiveBlankLines = 1
        let input = "前\n\n\n\n後\n遠い行  "

        let result = ManuscriptLiveFormatter.format(
            input,
            changedRange: NSRange(location: 3, length: 1),
            selectedRange: NSRange(location: 4, length: 0),
            settings: settings,
            options: FormatOptions(isPremiumUser: false)
        )

        XCTAssertEqual(result.text, "前\n\n後\n遠い行  ")
    }

    func testStructuralContextDoesNotApplyInlineRulesToBoundaryLines() {
        var settings = FormatSettings.default
        settings.enableAutoFormat = true
        settings.enableNormalizeBlankLines = true
        settings.maxConsecutiveBlankLines = 1
        settings.enableTrimLineSpaces = true
        settings.enableNormalizePunctuation = true
        let input = "境界,  \n\n\n編集行"

        let result = ManuscriptLiveFormatter.format(
            input,
            changedRange: NSRange(location: 8, length: 1),
            selectedRange: NSRange(location: 9, length: 0),
            settings: settings,
            options: FormatOptions(isPremiumUser: true)
        )

        XCTAssertEqual(result.text, "境界,  \n\n編集行")
    }

    func testFormatsThePageBreakBoundaryBlock() {
        var settings = FormatSettings.default
        settings.enableAutoFormat = true
        settings.enableNormalizePageBreakSpacing = true
        let input = "前\n\n\n[[PAGE_BREAK]]\n\n\n後"

        let result = ManuscriptLiveFormatter.format(
            input,
            changedRange: NSRange(location: 4, length: 14),
            selectedRange: NSRange(location: 18, length: 0),
            settings: settings,
            options: FormatOptions(isPremiumUser: false)
        )

        XCTAssertEqual(result.text, "前\n\n[[PAGE_BREAK]]\n\n後")
    }

    func testDisabledAutoFormatReturnsTheOriginalValue() {
        let input = "A,B."
        let result = ManuscriptLiveFormatter.format(
            input,
            changedRange: NSRange(location: 1, length: 1),
            selectedRange: NSRange(location: 2, length: 0),
            settings: .default,
            options: FormatOptions(isPremiumUser: true)
        )

        XCTAssertEqual(result.text, input)
        XCTAssertEqual(result.selectedRange, NSRange(location: 2, length: 0))
    }

    func testPremiumRuleDoesNotRunForAFreeUser() {
        var settings = FormatSettings.default
        settings.enableAutoFormat = true
        settings.enableNormalizePunctuation = true

        let result = ManuscriptLiveFormatter.format(
            "A,B.",
            changedRange: NSRange(location: 0, length: 4),
            selectedRange: NSRange(location: 4, length: 0),
            settings: settings,
            options: FormatOptions(isPremiumUser: false)
        )

        XCTAssertEqual(result.text, "A,B.")
    }

    func testDeletionRangeFallsBackToTheDeletionPoint() {
        XCTAssertEqual(
            ManuscriptLiveFormatter.postEditChangedRange(
                replacing: NSRange(location: 4, length: 3),
                with: ""
            ),
            NSRange(location: 4, length: 0)
        )
    }

    func testPasteRangeUsesReplacementUTF16Length() {
        XCTAssertEqual(
            ManuscriptLiveFormatter.postEditChangedRange(
                replacing: NSRange(location: 2, length: 1),
                with: "追記😀"
            ),
            NSRange(location: 2, length: 4)
        )
    }
}
