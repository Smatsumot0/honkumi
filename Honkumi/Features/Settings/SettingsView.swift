import SwiftUI

struct SettingsView: View {
    @StateObject var viewModel: SettingsViewModel
    private let settingTitleWidth: CGFloat = 112
    private let settingValueWidth: CGFloat = 72

    var body: some View {
        Form {
            Section("用紙") {
                Picker("サイズ", selection: Binding(
                    get: { viewModel.settings.pageSize },
                    set: { viewModel.updatePageSize($0) }
                )) {
                    ForEach(PageSize.selectableCases) { pageSize in
                        Text(pageSize.displayName).tag(pageSize)
                    }
                }
            }

            Section("組版") {
                Picker("フォント", selection: Binding(
                    get: { viewModel.settings.japaneseFont },
                    set: { viewModel.updateJapaneseFont($0) }
                )) {
                    ForEach(JapaneseFont.allCases) { font in
                        Text(font.displayName).tag(font)
                    }
                }

                valueStepper(
                    title: "文字サイズ",
                    value: viewModel.settings.fontSize,
                    range: EditorSettings.fontSizeRange,
                    step: 0.5,
                    format: "%.1f pt",
                    update: viewModel.updateFontSize
                )

                intStepper(
                    title: "1行あたり",
                    value: viewModel.settings.charactersPerLine,
                    unit: "文字",
                    range: EditorSettings.charactersPerLineRange,
                    update: viewModel.updateCharactersPerLine
                )

                intStepper(
                    title: "1ページあたり",
                    value: viewModel.settings.linesPerPage,
                    unit: "行",
                    range: EditorSettings.linesPerPageRange,
                    update: viewModel.updateLinesPerPage
                )
            }

            Section("余白") {
                valueStepper(
                    title: "天",
                    value: viewModel.settings.marginTop,
                    range: EditorSettings.marginTopRange,
                    step: 1,
                    format: "%.0f mm",
                    update: viewModel.updateMarginTop
                )
                valueStepper(
                    title: "地",
                    value: viewModel.settings.marginBottom,
                    range: EditorSettings.marginBottomRange,
                    step: 1,
                    format: "%.0f mm",
                    update: viewModel.updateMarginBottom
                )
                valueStepper(
                    title: "ノド",
                    value: viewModel.settings.marginInner,
                    range: EditorSettings.marginInnerRange,
                    step: 1,
                    format: "%.0f mm",
                    update: viewModel.updateMarginInner
                )
                valueStepper(
                    title: "小口",
                    value: viewModel.settings.marginOuter,
                    range: EditorSettings.marginOuterRange,
                    step: 1,
                    format: "%.0f mm",
                    update: viewModel.updateMarginOuter
                )
            }

            Section("章タイトル") {
                Toggle("章タイトルをページ上部に表示", isOn: Binding(
                    get: { viewModel.settings.showChapterTitle },
                    set: { viewModel.updateShowChapterTitle($0) }
                ))

                Picker("章タイトル表示形式", selection: Binding(
                    get: { viewModel.settings.chapterTitleStyle },
                    set: { viewModel.updateChapterTitleStyle($0) }
                )) {
                    ForEach(ChapterTitleStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .disabled(!viewModel.settings.showChapterTitle)

                Toggle("章の始めに改ページ", isOn: Binding(
                    get: { viewModel.settings.startsChapterOnNewPage },
                    set: { viewModel.updateStartsChapterOnNewPage($0) }
                ))
            }

            Section("目次") {
                Toggle("目次を出力", isOn: Binding(
                    get: { viewModel.settings.showTableOfContents },
                    set: { viewModel.updateShowTableOfContents($0) }
                ))
            }

            Section("ページ番号") {
                Picker("表示位置", selection: Binding(
                    get: { viewModel.settings.pageNumberPosition },
                    set: { viewModel.updatePageNumberPosition($0) }
                )) {
                    ForEach(PageNumberPosition.allCases) { position in
                        Text(position.displayName).tag(position)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private func intStepper(
        title: String,
        value: Int,
        unit: String,
        range: ClosedRange<Int>,
        update: @escaping (Int) -> Void
    ) -> some View {
        Stepper(
            value: Binding(
                get: { value },
                set: { update($0) }
            ),
            in: range
        ) {
            settingLabel(title: title, value: "\(value)\(unit)")
        }
    }

    private func valueStepper(
        title: String,
        value: CGFloat,
        range: ClosedRange<CGFloat>,
        step: CGFloat,
        format: String,
        update: @escaping (CGFloat) -> Void
    ) -> some View {
        Stepper(
            value: Binding(
                get: { value },
                set: { update($0) }
            ),
            in: range,
            step: step
        ) {
            settingLabel(title: title, value: String(format: format, value))
        }
    }

    private func settingLabel(title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: settingTitleWidth, alignment: .leading)

            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: settingValueWidth, alignment: .leading)
        }
    }
}
