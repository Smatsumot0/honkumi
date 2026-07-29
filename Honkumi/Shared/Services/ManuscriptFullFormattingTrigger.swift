import Foundation

nonisolated struct ManuscriptFormatSessionSnapshot: Equatable {
    let documentID: UUID
    var formatSettings: FormatSettings
    var formatOptions: FormatOptions
}

nonisolated enum ManuscriptFullFormattingTrigger {
    static func shouldFormatAfterSettingsDismissal(
        initial: ManuscriptFormatSessionSnapshot,
        current: ManuscriptFormatSessionSnapshot
    ) -> Bool {
        guard initial.documentID == current.documentID else { return false }
        let settings = current.formatSettings.validated
        guard settings.enableAutoFormat else { return false }
        if !initial.formatSettings.enableAutoFormat { return true }

        let enabledRuleWasAdded = ManuscriptFormatter.rules.contains {
            !initial.formatSettings[keyPath: $0.id] &&
                settings[keyPath: $0.id] &&
                (!$0.premium || current.formatOptions.isPremiumUser)
        }
        if enabledRuleWasAdded { return true }

        if initial.formatSettings.maxConsecutiveBlankLines !=
            settings.maxConsecutiveBlankLines,
            settings.enableNormalizeBlankLines {
            return true
        }

        return !initial.formatOptions.isPremiumUser &&
            current.formatOptions.isPremiumUser &&
            shouldFormatAfterProUnlock(settings: settings)
    }

    static func shouldFormatAfterProUnlock(settings: FormatSettings) -> Bool {
        let settings = settings.validated
        guard settings.enableAutoFormat else { return false }
        return ManuscriptFormatter.premiumRules.contains {
            settings[keyPath: $0.id]
        }
    }
}
