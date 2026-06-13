import SwiftUI

struct ContentView: View {
    @ObservedObject var documentStore: DocumentStore
    @ObservedObject var proStore: HonkumiProStore
    @State private var showsWorkspace = false
    @State private var presentedSettingsScope: SettingsViewModel.Scope?
    @State private var presentedSettingsInitialTab: SettingsInitialTab = .editor
    @State private var presentedColophonScope: SettingsViewModel.Scope?

    var body: some View {
        NavigationStack {
            WorkListView(
                documentStore: documentStore,
                onSelectWork: {
                    showsWorkspace = true
                },
                onShowDefaultSettings: {
                    presentedSettingsInitialTab = .editor
                    presentedSettingsScope = .userDefault
                },
                onShowDefaultColophonSettings: {
                    presentedColophonScope = .userDefault
                }
            )
            .navigationDestination(isPresented: $showsWorkspace) {
                WorkspaceView(
                    documentStore: documentStore,
                    proStore: proStore,
                    presentedSettingsScope: $presentedSettingsScope,
                    presentedSettingsInitialTab: $presentedSettingsInitialTab
                )
            }
        }
        .sheet(item: $presentedSettingsScope) { scope in
            NavigationStack {
                SettingsView(
                    viewModel: SettingsViewModel(documentStore: documentStore, scope: scope),
                    proStore: proStore,
                    initialTab: presentedSettingsInitialTab
                )
                    .navigationTitle(scope.title)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(item: $presentedColophonScope) { scope in
            NavigationStack {
                ColophonSettingsView(
                    viewModel: SettingsViewModel(documentStore: documentStore, scope: scope),
                    mode: scope.colophonMode,
                    proStore: proStore
                )
                .navigationTitle(scope.colophonTitle)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task {
            proStore.start()
            await proStore.refreshPurchasedStatus()
            documentStore.setProUnlocked(proStore.isProUnlocked)
        }
        .onChange(of: proStore.isProUnlocked) { _, isUnlocked in
            documentStore.setProUnlocked(isUnlocked)
        }
    }
}

private struct WorkspaceView: View {
    @ObservedObject var documentStore: DocumentStore
    @ObservedObject var proStore: HonkumiProStore
    @Binding var presentedSettingsScope: SettingsViewModel.Scope?
    @Binding var presentedSettingsInitialTab: SettingsInitialTab
    @StateObject private var editorViewModel: EditorViewModel
    @StateObject private var previewViewModel: PreviewViewModel
    @State private var selectedSection: AppSection = .editor
    @State private var editorScrollOffset: CGPoint = .zero
    @State private var isEditorChromeVisible = true
    @State private var preflightResult: PreflightResult?
    @State private var exportedPDF: ExportedPDF?
    @State private var exportErrorMessage = ""
    @State private var showsExportError = false
    @State private var isExportingPDF = false

    private let preflightService = PDFPreflightService()
    private let pdfExportService = PDFExportService()
    private let pdfExportAdService = PDFExportAdService()

    init(
        documentStore: DocumentStore,
        proStore: HonkumiProStore,
        presentedSettingsScope: Binding<SettingsViewModel.Scope?>,
        presentedSettingsInitialTab: Binding<SettingsInitialTab>
    ) {
        self.documentStore = documentStore
        self.proStore = proStore
        self._presentedSettingsScope = presentedSettingsScope
        self._presentedSettingsInitialTab = presentedSettingsInitialTab
        self._editorViewModel = StateObject(wrappedValue: EditorViewModel(documentStore: documentStore))
        self._previewViewModel = StateObject(wrappedValue: PreviewViewModel(documentStore: documentStore))
    }

    var body: some View {
        VStack(spacing: 0) {
            if selectedSection != .editor || isEditorChromeVisible {
                sectionTabs
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Group {
                switch selectedSection {
                case .editor:
                    EditorView(
                        viewModel: editorViewModel,
                        scrollOffset: $editorScrollOffset,
                        isEditorChromeVisible: $isEditorChromeVisible
                    )
                case .preview:
                    ZStack {
                        PreviewView(viewModel: previewViewModel, displayMode: .single)
                    }
                case .spreadPreview:
                    ZStack {
                        PreviewView(viewModel: previewViewModel, displayMode: .spread)
                    }
                }
            }
        }
        .navigationTitle(documentStore.document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if selectedSection.isPreview {
                    Button {
                        runPreflightBeforeExport()
                    } label: {
                        if isExportingPDF {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .disabled(isExportingPDF)
                    .accessibilityLabel("PDF出力")
                }

                Button {
                    presentedSettingsInitialTab = selectedSection.isPreview ? .print : .editor
                    presentedSettingsScope = .activeWork
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("設定")
            }
        }
        .sheet(item: $preflightResult) { result in
            PreflightResultView(
                result: result,
                onReturnToFix: {
                    preflightResult = result
                    selectedSection = .editor
                    preflightResult = nil
                },
                onAutoFixAndContinue: {
                    autoFixAndContinue()
                },
                onIgnoreWarningsAndContinue: {
                    guard result.canContinue else { return }
                    preflightResult = nil
                    exportPDF()
                }
            )
        }
        .sheet(item: $exportedPDF) { exportedPDF in
            PDFShareSheetView(exportedPDF: exportedPDF)
        }
        .alert("PDF出力に失敗しました", isPresented: $showsExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage)
        }
        .onAppear {
            updatePreviewActivity(for: selectedSection)
        }
        .onDisappear {
            previewViewModel.setPreviewActive(false)
        }
        .onChange(of: selectedSection) { _, section in
            isEditorChromeVisible = true
            updatePreviewActivity(for: section)
        }
        .animation(.easeInOut(duration: 0.18), value: isEditorChromeVisible)
    }

    private var sectionTabs: some View {
        HStack(spacing: 3) {
            ForEach(AppSection.allCases) { section in
                let isSelected = selectedSection == section
                Button {
                    selectedSection = section
                } label: {
                    Text(section.title)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .background {
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color(.secondarySystemFill) : Color.clear)
                }
                .accessibilityLabel(section.title)
            }
        }
        .padding(2)
        .background(Color(.tertiarySystemFill), in: Capsule(style: .continuous))
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(.bar)
    }

    private func runPreflightBeforeExport() {
        guard !isExportingPDF else { return }
        isExportingPDF = true

        let document = outputDocument()
        let subscriptionStatus = documentStore.subscriptionStatus
        let preflightService = preflightService

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                preflightService.check(
                    document: document,
                    subscriptionStatus: subscriptionStatus
                )
            }.value

            await MainActor.run {
                if result.hasProblems {
                    preflightResult = result
                    isExportingPDF = false
                } else {
                    exportPDF(document: document, isAlreadyExporting: true)
                }
            }
        }
    }

    private func updatePreviewActivity(for section: AppSection) {
        guard let previewKind = section.previewKind else {
            previewViewModel.setPreviewActive(false)
            return
        }

        previewViewModel.setPreviewActive(true, kind: previewKind)
    }

    private func autoFixAndContinue() {
        let fixedDocument = preflightService.autoFixedDocument(
            from: documentStore.document,
            subscriptionStatus: documentStore.subscriptionStatus
        )
        documentStore.updateBody(fixedDocument.body)
        documentStore.updateSettings(fixedDocument.settings)

        let result = preflightService.check(
            document: outputDocument(from: fixedDocument),
            subscriptionStatus: documentStore.subscriptionStatus
        )

        if result.hasProblems {
            preflightResult = result
        } else {
            preflightResult = nil
            exportPDF(document: fixedDocument)
        }
    }

    private func exportPDF(document: ManuscriptDocument? = nil, isAlreadyExporting: Bool = false) {
        guard isAlreadyExporting || !isExportingPDF else { return }
        if !isAlreadyExporting {
            isExportingPDF = true
        }

        let exportDocument = outputDocument(from: document ?? documentStore.document)
        let subscriptionStatus = documentStore.subscriptionStatus

        Task {
            do {
                await pdfExportAdService.presentAdIfNeeded(subscriptionStatus: subscriptionStatus)
                let url = try await pdfExportService.export(
                    document: exportDocument,
                    subscriptionStatus: subscriptionStatus
                )
                await MainActor.run {
                    exportedPDF = ExportedPDF(url: url)
                    isExportingPDF = false
                }
            } catch {
                await MainActor.run {
                    exportErrorMessage = error.localizedDescription
                    showsExportError = true
                    isExportingPDF = false
                }
            }
        }
    }

    private func outputDocument(from document: ManuscriptDocument? = nil) -> ManuscriptDocument {
        (document ?? documentStore.document)
            .applyingPublisherInfo(from: documentStore.userDefaultSettings)
    }
}

private enum AppSection: String, CaseIterable, Identifiable {
    case editor
    case preview
    case spreadPreview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .editor:
            "編集"
        case .preview:
            "プレビュー"
        case .spreadPreview:
            "見開きプレビュー"
        }
    }

    var systemImage: String {
        switch self {
        case .editor:
            "square.and.pencil"
        case .preview:
            "doc.text.magnifyingglass"
        case .spreadPreview:
            "book.pages"
        }
    }

    var isPreview: Bool {
        previewKind != nil
    }

    var previewKind: PreviewPDFKind? {
        switch self {
        case .editor:
            nil
        case .preview:
            .normal
        case .spreadPreview:
            .spread
        }
    }
}

extension SettingsViewModel.Scope: Identifiable {
    var id: String {
        switch self {
        case .activeWork:
            "activeWork"
        case .userDefault:
            "userDefault"
        }
    }

    var colophonTitle: String {
        switch self {
        case .activeWork:
            "奥付設定"
        case .userDefault:
            "発行者情報"
        }
    }

    var colophonMode: ColophonSettingsView.Mode {
        switch self {
        case .activeWork:
            .activeWork
        case .userDefault:
            .userDefault
        }
    }

    var title: String {
        switch self {
        case .activeWork:
            "設定"
        case .userDefault:
            "デフォルト設定"
        }
    }
}
