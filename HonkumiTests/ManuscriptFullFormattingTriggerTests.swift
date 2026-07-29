@testable import Honkumi
import XCTest

final class ManuscriptFullFormattingTriggerTests: XCTestCase {
    func testEnablingAutoFormatRequestsOneFullFormat() {
        var current = baseSnapshot
        current.formatSettings.enableAutoFormat = true
        XCTAssertTrue(trigger(initial: baseSnapshot, current: current))
    }

    func testEnablingAnActiveRuleRequestsFullFormat() {
        var initial = baseSnapshot
        initial.formatSettings.enableAutoFormat = true
        var current = initial
        current.formatSettings.enableNormalizeConsecutiveExclamationQuestion = true
        XCTAssertTrue(trigger(initial: initial, current: current))
    }

    func testChangingEnabledBlankLineLimitRequestsFullFormat() {
        var initial = baseSnapshot
        initial.formatSettings.enableAutoFormat = true
        initial.formatSettings.enableNormalizeBlankLines = true
        var current = initial
        current.formatSettings.maxConsecutiveBlankLines = 3
        XCTAssertTrue(trigger(initial: initial, current: current))
    }

    func testOnlyDisablingRulesDoesNotRequestFullFormat() {
        var initial = baseSnapshot
        initial.formatSettings.enableAutoFormat = true
        initial.formatSettings.enableNormalizePunctuation = true
        var current = initial
        current.formatSettings.enableNormalizePunctuation = false
        XCTAssertFalse(trigger(initial: initial, current: current))
    }

    func testClosingWithAutoFormatOffDoesNotRequestFullFormat() {
        var initial = baseSnapshot
        initial.formatSettings.enableNormalizePunctuation = false
        var current = initial
        current.formatSettings.enableNormalizePunctuation = true
        XCTAssertFalse(trigger(initial: initial, current: current))
    }

    func testUnchangedSettingsDoNotRequestFullFormat() {
        XCTAssertFalse(trigger(initial: baseSnapshot, current: baseSnapshot))
    }

    func testPaidUnlockRequestsFormattingOnlyWhenAnEnabledPremiumRuleExists() {
        var current = baseSnapshot
        current.formatSettings.enableAutoFormat = true
        current.formatSettings.enableNormalizePunctuation = true
        current.formatOptions = FormatOptions(isPremiumUser: true)
        XCTAssertTrue(
            trigger(
                initial: baseSnapshotWith(current, premium: false),
                current: current
            )
        )

        current.formatSettings.enableNormalizePunctuation = false
        XCTAssertFalse(
            ManuscriptFullFormattingTrigger.shouldFormatAfterProUnlock(
                settings: current.formatSettings
            )
        )
    }

    private var baseSnapshot: ManuscriptFormatSessionSnapshot {
        ManuscriptFormatSessionSnapshot(
            documentID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            formatSettings: .default,
            formatOptions: FormatOptions(isPremiumUser: false)
        )
    }

    private func baseSnapshotWith(
        _ snapshot: ManuscriptFormatSessionSnapshot,
        premium: Bool
    ) -> ManuscriptFormatSessionSnapshot {
        ManuscriptFormatSessionSnapshot(
            documentID: snapshot.documentID,
            formatSettings: snapshot.formatSettings,
            formatOptions: FormatOptions(isPremiumUser: premium)
        )
    }

    private func trigger(
        initial: ManuscriptFormatSessionSnapshot,
        current: ManuscriptFormatSessionSnapshot
    ) -> Bool {
        ManuscriptFullFormattingTrigger.shouldFormatAfterSettingsDismissal(
            initial: initial,
            current: current
        )
    }
}
