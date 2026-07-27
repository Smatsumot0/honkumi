import Foundation

nonisolated struct PrintSettingsDisplaySnapshot: Equatable {
    let settings: EditorSettings
    let estimatedPageCount: Int
    let showsWideGutterNote: Bool

    static func calculate(body: String, settings: EditorSettings) -> Self {
        let effectiveSettings = RecommendedPrintSettings.effectiveSettings(
            body: body,
            settings: settings
        )
        let estimatedPageCount = RecommendedPrintSettings.estimatedPageCount(
            body: body,
            settings: effectiveSettings
        )

        return Self(
            settings: effectiveSettings,
            estimatedPageCount: estimatedPageCount,
            showsWideGutterNote: effectiveSettings.useRecommendedMargins
                && RecommendedPrintSettings.supportsRecommendations(for: effectiveSettings.pageSize)
                && estimatedPageCount >= 97
        )
    }

    static func initial(settings: EditorSettings) -> Self {
        Self(
            settings: RecommendedPrintSettings.effectiveSettings(
                settings: settings,
                estimatedPageCount: 1
            ),
            estimatedPageCount: 1,
            showsWideGutterNote: false
        )
    }
}
