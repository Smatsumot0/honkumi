import SwiftUI

struct SettingsView: View {
    @StateObject var viewModel: SettingsViewModel
    @State private var selectedTab: SettingsTab = .print
    @State private var showsPageNumberDesignGuide = false
    private let settingTitleWidth: CGFloat = 112
    private let settingValueWidth: CGFloat = 72

    var body: some View {
        VStack(spacing: 0) {
            Picker("設定カテゴリ", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            .background(.bar)

            switch selectedTab {
            case .print:
                printSettingsForm
            case .format:
                formatSettingsForm
            }
        }
    }

    private var printSettingsForm: some View {
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
                NavigationLink {
                    fontSettingsView
                } label: {
                    HStack {
                        Text("フォント")
                        Spacer()
                        Text(currentFontDisplayName)
                            .font(AppFontCatalog.swiftUIFont(
                                selectedFontId: viewModel.settings.selectedFontId,
                                size: 17,
                                isAdditionalFontPackUnlocked: true
                            ))
                            .foregroundStyle(.secondary)
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

            Section("奥付") {
                Toggle("奥付を追加", isOn: colophonBinding(\.isEnabled))

                if viewModel.isActiveWorkScope, viewModel.settings.colophon.isEnabled {
                    Toggle("発行日を表示", isOn: colophonBinding(\.showsPublicationDate))
                    PublicationDateField(date: publicationDateOptionalBinding)
                        .disabled(!viewModel.settings.colophon.showsPublicationDate)

                    Toggle("印刷所を表示", isOn: colophonBinding(\.showsPrinterName))
                    TextField("印刷所名", text: colophonBinding(\.printerName))
                        .disabled(!viewModel.settings.colophon.showsPrinterName)
                }
            }

            Section("ページ番号") {
                Toggle("ページ番号を表示", isOn: Binding(
                    get: { viewModel.settings.isPageNumberEnabled },
                    set: { viewModel.updateIsPageNumberEnabled($0) }
                ))

                pageNumberFontNavigationRow

                valueStepper(
                    title: "ノンブルサイズ",
                    value: viewModel.settings.pageNumberSize,
                    range: EditorSettings.pageNumberSizeRange,
                    step: 0.5,
                    format: "%.1f pt",
                    update: viewModel.updatePageNumberSize
                )
                .disabled(!viewModel.isPageNumberFontUnlocked)

                Picker("表示位置", selection: Binding(
                    get: {
                        guard viewModel.isPageNumberFontUnlocked else { return .outside }
                        return viewModel.settings.pageNumberPosition == .hidden
                            ? .outside
                            : viewModel.settings.pageNumberPosition
                    },
                    set: { viewModel.updatePageNumberPosition($0) }
                )) {
                    ForEach(PageNumberPosition.allCases.filter { $0 != .hidden }) { position in
                        Text(position.displayName).tag(position)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!viewModel.isPageNumberFontUnlocked || !viewModel.settings.isPageNumberEnabled)
            }
        }
        .alert("ノンブルデザイン設定", isPresented: $showsPageNumberDesignGuide) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("デザイン性の高いノンブル用フォント、サイズ、位置の変更は有料機能です。無料版では本文と同じフォントでページ番号のみを表示します。")
        }
    }

    private var formatSettingsForm: some View {
        Form {
            Section {
                Toggle("本文入力時に自動フォーマット", isOn: Binding(
                    get: { viewModel.settings.formatSettings.enableAutoFormat },
                    set: { newValue in
                        viewModel.updateFormatSettings {
                            $0.enableAutoFormat = newValue
                        }
                    }
                ))

                Text("オンにした項目は、本文入力時に自動で反映されます。\n日本語入力の変換中はフォーマットされず、確定後に反映されます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("無料で使える項目") {
                ForEach(ManuscriptFormatter.freeRules) { rule in
                    formatRuleRow(rule)

                    if rule.id == \.enableNormalizeBlankLines,
                       viewModel.settings.formatSettings.enableNormalizeBlankLines {
                        intStepper(
                            title: "空行の上限",
                            value: viewModel.settings.formatSettings.maxConsecutiveBlankLines,
                            unit: "行",
                            range: EditorSettings.maxConsecutiveBlankLinesRange
                        ) { newValue in
                            viewModel.updateFormatSettings {
                                $0.maxConsecutiveBlankLines = newValue
                            }
                        }
                    }
                }
            }

            Section("有料機能") {
                ForEach(ManuscriptFormatter.premiumRules) { rule in
                    formatRuleRow(rule)
                }
            }
        }
    }

    private var fontSettingsView: some View {
        Form {
            Section("フォント") {
                ForEach(AppFontCatalog.all) { font in
                    fontRow(font)
                }
            }

            Section("フォントライセンス") {
                ForEach(AppFontCatalog.all) { font in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(font.displayName)
                            .font(AppFontCatalog.swiftUIFont(
                                selectedFontId: font.id,
                                size: 15,
                                isAdditionalFontPackUnlocked: true
                            ))
                        Text(font.licenseName)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(font.copyrightText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("フォント設定")
    }

    private var pageNumberFontSettingsView: some View {
        Form {
            Section("本文フォント") {
                Button {
                    viewModel.updatePageNumberFontId(nil)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("本文と同じ")
                                .foregroundStyle(.primary)
                            Text("無料版と同じシンプルなノンブル")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if viewModel.settings.pageNumberFontId == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            ForEach(PageNumberFontCategory.allCases) { category in
                Section(category.displayName) {
                    ForEach(AppFontCatalog.pageNumberFonts(in: category)) { font in
                        pageNumberFontRow(font)
                    }
                }
            }

            Section("フォントライセンス") {
                ForEach(AppFontCatalog.pageNumberFonts) { font in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(font.displayName)
                            .font(AppFontCatalog.pageNumberSwiftUIFont(
                                pageNumberFontId: font.id,
                                bodyFontId: viewModel.settings.selectedFontId,
                                size: 17,
                                isPageNumberFontUnlocked: true
                            ))
                        Text(font.licenseName)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(font.copyrightText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("ノンブルフォント設定")
    }

    private var currentFontDisplayName: String {
        AppFontCatalog.font(id: viewModel.settings.selectedFontId)?.displayName ?? "BIZ UD明朝"
    }

    private var currentPageNumberFontDisplayName: String {
        guard viewModel.isPageNumberFontUnlocked else {
            return "本文と同じ"
        }

        return AppFontCatalog.pageNumberFont(id: viewModel.settings.pageNumberFontId)?.displayName
            ?? "本文と同じ"
    }

    @ViewBuilder
    private var pageNumberFontNavigationRow: some View {
        if viewModel.isPageNumberFontUnlocked {
            NavigationLink {
                pageNumberFontSettingsView
            } label: {
                HStack {
                    Text("ノンブル用フォント")
                    Spacer()
                    Text(currentPageNumberFontDisplayName)
                        .font(AppFontCatalog.pageNumberSwiftUIFont(
                            pageNumberFontId: viewModel.settings.pageNumberFontId,
                            bodyFontId: viewModel.settings.selectedFontId,
                            size: 17,
                            isPageNumberFontUnlocked: true
                        ))
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Button {
                showsPageNumberDesignGuide = true
            } label: {
                HStack {
                    Text("ノンブル用フォント")
                    Spacer()
                    Text("本文と同じ")
                        .foregroundStyle(.secondary)
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
        }
    }

    private func fontRow(_ font: AppFont) -> some View {
        let isSelected = viewModel.settings.selectedFontId == font.id

        return Button {
            viewModel.updateSelectedFontId(font.id)
        } label: {
            HStack(spacing: 12) {
                Text(font.displayName)
                    .font(AppFontCatalog.swiftUIFont(
                        selectedFontId: font.id,
                        size: 17,
                        isAdditionalFontPackUnlocked: true
                    ))
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pageNumberFontRow(_ font: PageNumberFont) -> some View {
        let isSelected = viewModel.settings.pageNumberFontId == font.id

        return Button {
            viewModel.updatePageNumberFontId(font.id)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(font.displayName)
                        .font(AppFontCatalog.pageNumberSwiftUIFont(
                            pageNumberFontId: font.id,
                            bodyFontId: viewModel.settings.selectedFontId,
                            size: 17,
                            isPageNumberFontUnlocked: true
                        ))
                        .foregroundStyle(.primary)

                    Text(font.category.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("0123456789")
                    .font(AppFontCatalog.pageNumberSwiftUIFont(
                        pageNumberFontId: font.id,
                        bodyFontId: viewModel.settings.selectedFontId,
                        size: 15,
                        isPageNumberFontUnlocked: true
                    ))
                    .foregroundStyle(.secondary)

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private func colophonBinding<Value>(_ keyPath: WritableKeyPath<ColophonSettings, Value>) -> Binding<Value> {
        Binding(
            get: { viewModel.settings.colophon[keyPath: keyPath] },
            set: { newValue in
                viewModel.updateColophon { colophon in
                    colophon[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private var publicationDateOptionalBinding: Binding<Date?> {
        Binding(
            get: { viewModel.settings.colophon.publicationDate },
            set: { newValue in
                viewModel.updateColophon { colophon in
                    colophon.publicationDate = newValue
                }
            }
        )
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

    private func formatRuleRow(_ rule: FormatRule) -> some View {
        let isLocked = rule.premium && !viewModel.isPremiumUser

        return Toggle(isOn: Binding(
            get: { viewModel.settings.formatSettings[keyPath: rule.id] },
            set: { viewModel.updateFormatRule(rule.id, isEnabled: $0) }
        )) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(rule.label)
                    if rule.premium {
                        paidFeatureBadge
                    }
                }

                Text(rule.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .disabled(isLocked)
    }

    private var paidFeatureBadge: some View {
        Text("有料")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue, in: Capsule())
    }

}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case print
    case format

    var id: String { rawValue }

    var title: String {
        switch self {
        case .print:
            "印刷設定"
        case .format:
            "フォーマット設定"
        }
    }
}
