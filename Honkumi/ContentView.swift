import SwiftUI

struct ContentView: View {
    @ObservedObject var documentStore: DocumentStore
    @State private var showsWorkspace = false
    @State private var presentedSettingsScope: SettingsViewModel.Scope?
    @State private var presentedColophonScope: SettingsViewModel.Scope?

    var body: some View {
        NavigationStack {
            WorkListView(
                documentStore: documentStore,
                onSelectWork: {
                    showsWorkspace = true
                },
                onShowDefaultSettings: {
                    presentedSettingsScope = .userDefault
                },
                onShowDefaultColophonSettings: {
                    presentedColophonScope = .userDefault
                }
            )
            .navigationDestination(isPresented: $showsWorkspace) {
                WorkspaceView(
                    documentStore: documentStore,
                    presentedSettingsScope: $presentedSettingsScope
                )
            }
        }
        .sheet(item: $presentedSettingsScope) { scope in
            NavigationStack {
                SettingsView(viewModel: SettingsViewModel(documentStore: documentStore, scope: scope))
                    .navigationTitle(scope.title)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(item: $presentedColophonScope) { scope in
            NavigationStack {
                ColophonSettingsView(
                    viewModel: SettingsViewModel(documentStore: documentStore, scope: scope),
                    mode: scope.colophonMode
                )
                .navigationTitle(scope.colophonTitle)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

private struct WorkspaceView: View {
    @ObservedObject var documentStore: DocumentStore
    @Binding var presentedSettingsScope: SettingsViewModel.Scope?
    @StateObject private var editorViewModel: EditorViewModel
    @StateObject private var previewViewModel: PreviewViewModel
    @State private var selectedSection: AppSection = .editor
    @State private var editorScrollOffset: CGPoint = .zero
    @State private var previewPageScale: CGFloat = 1
    @State private var previewFocusedPage = 1
    @State private var previewHorizontalAnchor: CGFloat = 0.5
    @State private var previewScrollOffset: CGPoint = .zero
    @State private var showsFacingPagesPreview = true
    @State private var showsPreviewGuides = true
    @State private var preflightResult: PreflightResult?
    @State private var exportedPDF: ExportedPDF?
    @State private var exportErrorMessage = ""
    @State private var showsExportError = false
    @State private var isExportingPDF = false

    private let preflightService = PDFPreflightService()
    private let pdfExportService = PDFExportService()

    init(documentStore: DocumentStore, presentedSettingsScope: Binding<SettingsViewModel.Scope?>) {
        self.documentStore = documentStore
        self._presentedSettingsScope = presentedSettingsScope
        self._editorViewModel = StateObject(wrappedValue: EditorViewModel(documentStore: documentStore))
        self._previewViewModel = StateObject(wrappedValue: PreviewViewModel(documentStore: documentStore))
    }

    var body: some View {
        VStack(spacing: 0) {
            sectionTabs

            if selectedSection == .preview {
                HStack {
                    Button {
                        showsPreviewGuides.toggle()
                    } label: {
                        Image(systemName: showsPreviewGuides ? "ruler.fill" : "ruler")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 30, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(showsPreviewGuides ? .accentColor : nil)
                    .accessibilityLabel(showsPreviewGuides ? "ガイドを非表示" : "ガイドを表示")

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
                .background(.bar)
            }

            Group {
                switch selectedSection {
                case .editor:
                    EditorView(
                        viewModel: editorViewModel,
                        scrollOffset: $editorScrollOffset
                    )
                case .preview:
                    ZStack {
                        PreviewView(
                            viewModel: previewViewModel,
                            pageScale: $previewPageScale,
                            focusedPage: $previewFocusedPage,
                            horizontalAnchor: $previewHorizontalAnchor,
                            scrollOffset: $previewScrollOffset,
                            showsFacingPages: $showsFacingPagesPreview,
                            showsGuides: $showsPreviewGuides
                        )
                    }
                }
            }
        }
        .navigationTitle(documentStore.document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if selectedSection == .preview {
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
            previewViewModel.setPreviewActive(selectedSection == .preview)
        }
        .onChange(of: selectedSection) { _, section in
            previewViewModel.setPreviewActive(section == .preview)
        }
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
                        .frame(height: 30)
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
        .padding(.horizontal)
        .padding(.vertical, 10)
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .editor:
            "編集"
        case .preview:
            "プレビュー"
        }
    }

    var systemImage: String {
        switch self {
        case .editor:
            "square.and.pencil"
        case .preview:
            "doc.text.magnifyingglass"
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
