import Foundation

nonisolated extension EditorSettings {
    func applyingUserDefaults(
        _ userDefaults: EditorSettings,
        selection: UserDefaultSettingsSelection
    ) -> EditorSettings {
        var applied = validated
        let defaults = userDefaults.validated

        if selection.editor {
            applied.editorFontId = defaults.editorFontId
            applied.editorFontSize = defaults.editorFontSize
        }

        if selection.circle {
            applied.colophon = applied.colophon.applyingPublisherInfo(
                from: defaults.colophon
            )
        }

        if selection.format {
            applied.formatSettings = defaults.formatSettings
        }

        if selection.print {
            applied.pageSize = defaults.pageSize
            applied.selectedFontId = defaults.selectedFontId
            applied.fontSize = defaults.fontSize
            applied.lineSpacing = defaults.lineSpacing
            applied.characterSpacing = defaults.characterSpacing
            applied.charactersPerLine = defaults.charactersPerLine
            applied.linesPerPage = defaults.linesPerPage
            applied.marginTop = defaults.marginTop
            applied.marginBottom = defaults.marginBottom
            applied.marginInner = defaults.marginInner
            applied.marginOuter = defaults.marginOuter
            applied.isPageNumberEnabled = defaults.isPageNumberEnabled
            applied.pageNumberFontId = defaults.pageNumberFontId
            applied.pageNumberSize = defaults.pageNumberSize
            applied.tableOfContentsPageNumberSize = defaults.tableOfContentsPageNumberSize
            applied.pageNumberStart = defaults.pageNumberStart
            applied.pageNumberPosition = defaults.pageNumberPosition
            applied.showPageNumberOnToc = defaults.showPageNumberOnToc
            applied.showPageNumberOnColophon = defaults.showPageNumberOnColophon
            applied.showTableOfContents = defaults.showTableOfContents
            applied.showChapterTitle = defaults.showChapterTitle
            applied.chapterTitleStyle = defaults.chapterTitleStyle
            applied.startsChapterOnNewPage = defaults.startsChapterOnNewPage
            applied.alphanumericOrientation = defaults.alphanumericOrientation
            applied.useRecommendedTypography = defaults.useRecommendedTypography
            applied.useRecommendedMargins = defaults.useRecommendedMargins
            applied.showsCropMarks = defaults.showsCropMarks
        }

        return applied.validated
    }
}
