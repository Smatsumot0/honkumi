@testable import Honkumi
import XCTest

final class ManuscriptFormatterTests: XCTestCase {
    func testApprovedPremiumExamplesAreNormalized() {
        let input = """
        「てすと。」
        「てすと！てすと」
        (てすと)
        「てすと,」
        「てすと､」
        「てすと，」
        「てすと...」
        「てすと…」
        """
        let expected = """
        「てすと」
        「てすと！　てすと」
        （てすと）
        「てすと、」
        「てすと、」
        「てすと、」
        「てすと……」
        「てすと……」
        """

        XCTAssertEqual(
            ManuscriptFormatter.formatManuscriptText(
                input,
                settings: enabledPremiumSettings(),
                options: FormatOptions(isPremiumUser: true)
            ),
            expected
        )
    }

    func testTwoOrMoreMixedDashCharactersBecomeOneDoubleDash() {
        var settings = FormatSettings.default
        settings.enableAutoFormat = true
        settings.enableNormalizeDash = true

        XCTAssertEqual(
            ManuscriptFormatter.formatManuscriptText(
                "単独―／二つ──／混在━―／三つーーー",
                settings: settings,
                options: FormatOptions(isPremiumUser: true)
            ),
            "単独―／二つ――／混在――／三つ――"
        )
    }

    func testPremiumRulesRemainInactiveForFreeUser() {
        let input = "A,B. (てすと) ... ━―！次"

        XCTAssertEqual(
            ManuscriptFormatter.formatManuscriptText(
                input,
                settings: enabledPremiumSettings(),
                options: FormatOptions(isPremiumUser: false)
            ),
            input
        )
    }

    private func enabledPremiumSettings() -> FormatSettings {
        var settings = FormatSettings.default
        settings.enableAutoFormat = true
        settings.enableNormalizeEllipsis = true
        settings.enableNormalizeDash = true
        settings.enableSpaceAfterExclamationQuestion = true
        settings.enableNormalizePunctuation = true
        settings.enableNormalizeBrackets = true
        settings.enableRemovePeriodsBeforeClosingBrackets = true
        return settings
    }
}
