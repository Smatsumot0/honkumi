import SwiftUI

enum SettingsInitialTab {
    case editor
    case print
}

struct SettingsView: View {
    @StateObject var viewModel: SettingsViewModel
    @ObservedObject var proStore: HonkumiProStore
    @State private var selectedTab: SettingsTab
    @State private var isProPurchasePresented = false
    @State private var presentedProFeature: HonkumiProFeature?
    private let settingTitleWidth: CGFloat = 112
    private let settingValueWidth: CGFloat = 72

    init(
        viewModel: SettingsViewModel,
        proStore: HonkumiProStore,
        initialTab: SettingsInitialTab = .editor
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.proStore = proStore
        _selectedTab = State(initialValue: initialTab == .print ? .print : .editor)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("設定カテゴリ", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            switch selectedTab {
            case .editor:
                editorSettingsForm
            case .format:
                formatSettingsForm
            case .print:
                printSettingsForm
            }
        }
        .sheet(isPresented: $isProPurchasePresented) {
            HonkumiProPurchaseView(proStore: proStore, feature: presentedProFeature)
        }
        .alert(item: purchaseMessageBinding) { message in
            Alert(
                title: Text(message.title),
                message: Text(message.body),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private var printSettingsForm: some View {
        let printSettings = viewModel.printSettingsForDisplay
        let usesRecommendedPrintSettings = viewModel.settings.useRecommendedPrintSettings

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

            Section("推奨設定") {
                Toggle(isOn: Binding(
                    get: { viewModel.settings.useRecommendedPrintSettings },
                    set: { viewModel.updateUseRecommendedPrintSettings($0) }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("推奨設定を使用")
                        Text(usesRecommendedPrintSettings
                            ? "用紙サイズとページ数に合わせて、印刷向けの安全な余白・組版設定を自動適用します。"
                            : "推奨設定をオフにすると、余白・文字サイズ・行数・文字数などを手動で調整できます。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                if usesRecommendedPrintSettings {
                    LabeledContent("想定ページ数", value: "\(viewModel.estimatedPrintPageCount)ページ")
                    LabeledContent("本文フォント", value: currentFontDisplayName)
                }
            }

            Section("PDF出力") {
                Toggle(isOn: Binding(
                    get: { viewModel.settings.showsCropMarks },
                    set: { viewModel.updateShowsCropMarks($0) }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("トンボ")
                        Text("印刷所から指定がある場合、仕上がり位置を示すトンボをPDFに追加します。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                Text("印刷所指定がある場合のみONにしてください")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
                                selectedFontId: printSettings.selectedFontId,
                                size: 17,
                                isAdditionalFontPackUnlocked: true
                            ))
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(usesRecommendedPrintSettings)

                valueStepper(
                    title: "文字サイズ",
                    value: printSettings.fontSize,
                    range: EditorSettings.fontSizeRange,
                    step: 0.5,
                    format: "%.1f pt",
                    update: viewModel.updateFontSize
                )
                .disabled(usesRecommendedPrintSettings)

                intStepper(
                    title: "1行あたり",
                    value: printSettings.charactersPerLine,
                    unit: "文字",
                    range: EditorSettings.charactersPerLineRange,
                    update: viewModel.updateCharactersPerLine
                )
                .disabled(usesRecommendedPrintSettings)

                intStepper(
                    title: "1ページあたり",
                    value: printSettings.linesPerPage,
                    unit: "行",
                    range: EditorSettings.linesPerPageRange,
                    update: viewModel.updateLinesPerPage
                )
                .disabled(usesRecommendedPrintSettings)

                valueStepper(
                    title: "字間",
                    value: printSettings.characterSpacing,
                    range: EditorSettings.characterSpacingRange,
                    step: 0.1,
                    format: "%.1f pt",
                    update: viewModel.updateCharacterSpacing
                )
                .disabled(usesRecommendedPrintSettings)

                valueStepper(
                    title: "行間",
                    value: printSettings.lineSpacing,
                    range: EditorSettings.lineSpacingRange,
                    step: 0.5,
                    format: "%.1f pt",
                    update: viewModel.updateLineSpacing
                )
                .disabled(usesRecommendedPrintSettings)
            }

            Section("余白") {
                valueStepper(
                    title: "天",
                    value: printSettings.marginTop,
                    range: EditorSettings.marginTopRange,
                    step: 1,
                    format: "%.0f mm",
                    update: viewModel.updateMarginTop
                )
                .disabled(usesRecommendedPrintSettings)
                valueStepper(
                    title: "地",
                    value: printSettings.marginBottom,
                    range: EditorSettings.marginBottomRange,
                    step: 1,
                    format: "%.0f mm",
                    update: viewModel.updateMarginBottom
                )
                .disabled(usesRecommendedPrintSettings)
                valueStepper(
                    title: "ノド",
                    value: printSettings.marginInner,
                    range: EditorSettings.marginInnerRange,
                    step: 1,
                    format: "%.0f mm",
                    update: viewModel.updateMarginInner
                )
                .disabled(usesRecommendedPrintSettings)
                valueStepper(
                    title: "小口",
                    value: printSettings.marginOuter,
                    range: EditorSettings.marginOuterRange,
                    step: 1,
                    format: "%.0f mm",
                    update: viewModel.updateMarginOuter
                )
                .disabled(usesRecommendedPrintSettings)
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

                intStepper(
                    title: "開始番号",
                    value: viewModel.settings.pageNumberStart,
                    unit: "",
                    range: EditorSettings.pageNumberStartRange,
                    update: viewModel.updatePageNumberStart
                )

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
        .listSectionSpacing(.compact)
    }

    private var editorSettingsForm: some View {
        Form {
            honkumiProSection

            Section("編集画面") {
                NavigationLink {
                    editorFontSettingsView
                } label: {
                    HStack {
                        Text("フォント")
                        Spacer()
                        Text(currentEditorFontDisplayName)
                            .font(AppFontCatalog.swiftUIFont(
                                selectedFontId: viewModel.settings.editorFontId,
                                size: 16,
                                isAdditionalFontPackUnlocked: true
                            ))
                            .foregroundStyle(.secondary)
                    }
                }

                valueStepper(
                    title: "文字サイズ",
                    value: viewModel.settings.editorFontSize,
                    range: EditorSettings.editorFontSizeRange,
                    step: 0.5,
                    format: "%.1f pt",
                    update: viewModel.updateEditorFontSize
                )
            }
        }
        .listSectionSpacing(.compact)
    }

    private var honkumiProSection: some View {
        Section("Honkumi Pro") {
            if proStore.isProUnlocked {
                Label("Honkumi Pro 購入済み", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                Button {
                    presentProPurchase(feature: nil)
                } label: {
                    HStack {
                        Label("Honkumi Proを購入", systemImage: "lock.open")
                        Spacer()
                        if proStore.isLoadingProducts {
                            ProgressView()
                        } else if !proStore.displayPrice.isEmpty {
                            Text(proStore.displayPrice)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }

            Button {
                Task {
                    await proStore.restorePurchases()
                }
            } label: {
                HStack {
                    Text("購入を復元")
                    Spacer()
                    if proStore.isRestoring {
                        ProgressView()
                    }
                }
            }
            .disabled(proStore.isBusy)
        }
    }

    private var formatSettingsForm: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { viewModel.settings.formatSettings.enableAutoFormat },
                    set: { newValue in
                        viewModel.updateFormatSettings {
                            $0.enableAutoFormat = newValue
                        }
                    }
                )) {
                    Text("本文入力時に自動フォーマット")
                }

                Text("オンにした場合、本文入力時に自動でフォーマットされます。オフの場合、プレビュー・PDF出力時も本文を変更せずに表示します。")
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
        .listSectionSpacing(.compact)
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

    private var editorFontSettingsView: some View {
        Form {
            Section("フォント") {
                ForEach(AppFontCatalog.all) { font in
                    editorFontRow(font)
                }
            }

            Section("フォントライセンス") {
                ForEach(AppFontCatalog.all) { font in
                    VStack(alignment: .leading, spacing: 3) {
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
                    .padding(.vertical, 2)
                }
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle("エディタフォント設定")
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

                        if viewModel.settings.pageNumberFontId == nil || !viewModel.isPageNumberFontUnlocked {
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
        AppFontCatalog.font(id: viewModel.printSettingsForDisplay.selectedFontId)?.displayName ?? "BIZ UD明朝"
    }

    private var currentEditorFontDisplayName: String {
        AppFontCatalog.font(id: viewModel.settings.editorFontId)?.displayName ?? "BIZ UD明朝"
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
                        isPageNumberFontUnlocked: viewModel.isPageNumberFontUnlocked
                    ))
                    .foregroundStyle(.secondary)
                if !viewModel.isPageNumberFontUnlocked {
                    paidFeatureBadge
                }
            }
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

    private func editorFontRow(_ font: AppFont) -> some View {
        let isSelected = viewModel.settings.editorFontId == font.id

        return Button {
            viewModel.updateEditorFontId(font.id)
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
        let isLocked = !viewModel.isPageNumberFontUnlocked
        let isSelected = viewModel.isPageNumberFontUnlocked && viewModel.settings.pageNumberFontId == font.id

        return Button {
            guard !isLocked else {
                presentProPurchase(feature: .pageNumberFonts)
                return
            }
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
                } else if isLocked {
                    paidFeatureBadge
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
            set: { newValue in
                guard !isLocked else {
                    presentProPurchase(feature: .formatting)
                    return
                }
                viewModel.updateFormatRule(rule.id, isEnabled: newValue)
            }
        )) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(rule.label)
                        .foregroundStyle(.primary)
                    if rule.premium && !viewModel.isPremiumUser {
                        paidFeatureBadge
                    }
                }

                Text(rule.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        .opacity(isLocked ? 0.82 : 1)
    }

    private var paidFeatureBadge: some View {
        Label("有料", systemImage: "lock.fill")
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.blue, in: Capsule())
    }

    private var purchaseMessageBinding: Binding<HonkumiProPurchaseMessage?> {
        Binding(
            get: { proStore.purchaseMessage },
            set: { _ in proStore.clearPurchaseMessage() }
        )
    }

    private func presentProPurchase(feature: HonkumiProFeature?) {
        presentedProFeature = feature
        isProPurchasePresented = true
    }

}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case editor
    case format
    case print

    var id: String { rawValue }

    var title: String {
        switch self {
        case .print:
            "印刷設定"
        case .editor:
            "エディタ設定"
        case .format:
            "フォーマット"
        }
    }
}
