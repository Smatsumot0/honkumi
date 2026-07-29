import SwiftUI

struct ContentView: View {
    @ObservedObject var documentStore: DocumentStore
    @ObservedObject var proStore: HonkumiProStore
    let pdfExportAdService: PDFExportAdService
    @StateObject private var manuscriptFormattingCoordinator: ManuscriptFormattingCoordinator
    @State private var showsWorkspace = false
    @State private var presentedSettingsScope: SettingsViewModel.Scope?
    @State private var presentedSettingsInitialTab: SettingsInitialTab = .editor
    @State private var presentedColophonScope: SettingsViewModel.Scope?
    @State private var activeFormatSettingsSession: ManuscriptFormatSessionSnapshot?

    init(
        documentStore: DocumentStore,
        proStore: HonkumiProStore,
        pdfExportAdService: PDFExportAdService
    ) {
        _documentStore = ObservedObject(wrappedValue: documentStore)
        _proStore = ObservedObject(wrappedValue: proStore)
        self.pdfExportAdService = pdfExportAdService
        _manuscriptFormattingCoordinator = StateObject(
            wrappedValue: ManuscriptFormattingCoordinator(
                documentStore: documentStore
            )
        )
    }

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
                    pdfExportAdService: pdfExportAdService,
                    manuscriptFormattingCoordinator: manuscriptFormattingCoordinator,
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
        .onChange(of: presentedSettingsScope?.id) { oldScopeID, newScopeID in
            if newScopeID == SettingsViewModel.Scope.activeWork.id {
                let document = documentStore.document
                activeFormatSettingsSession = ManuscriptFormatSessionSnapshot(
                    documentID: document.id,
                    formatSettings: document.settings.formatSettings,
                    formatOptions: FormatOptions(
                        isPremiumUser: documentStore.subscriptionStatus == .paid
                    )
                )
            }

            if oldScopeID == SettingsViewModel.Scope.activeWork.id,
               newScopeID == nil,
               let session = activeFormatSettingsSession {
                activeFormatSettingsSession = nil
                manuscriptFormattingCoordinator.settingsDidDismiss(
                    initial: session
                )
            }
        }
        .task {
            proStore.start()
            synchronizeProEntitlement(proStore.entitlementState)
            await proStore.refreshPurchasedStatus()
            synchronizeProEntitlement(proStore.entitlementState)
            if !ProcessInfo.processInfo.isRunningXCTest {
                Task(priority: .utility) {
                    await pdfExportAdService.prepareForAppLaunch()
                }
            }
        }
        .onChange(of: proStore.entitlementState) { _, entitlementState in
            synchronizeProEntitlement(entitlementState)
            if !ProcessInfo.processInfo.isRunningXCTest {
                Task(priority: .utility) {
                    await pdfExportAdService.preloadAdIfEligible()
                }
            }
        }
    }

    private func synchronizeProEntitlement(
        _ entitlementState: ProEntitlementState
    ) {
        let previousStatus = documentStore.subscriptionStatus
        documentStore.setProUnlocked(entitlementState.isProUnlocked)
        pdfExportAdService.updateEntitlementState(entitlementState)

        if previousStatus == .free,
           documentStore.subscriptionStatus == .paid,
           presentedSettingsScope?.id != SettingsViewModel.Scope.activeWork.id {
            manuscriptFormattingCoordinator.proDidUnlockOutsideSettings()
        }
    }
}

private struct WorkspaceView: View {
    @ObservedObject var documentStore: DocumentStore
    @ObservedObject var proStore: HonkumiProStore
    @ObservedObject var manuscriptFormattingCoordinator: ManuscriptFormattingCoordinator
    let pdfExportAdService: PDFExportAdService
    @Binding var presentedSettingsScope: SettingsViewModel.Scope?
    @Binding var presentedSettingsInitialTab: SettingsInitialTab
    @StateObject private var editorViewModel: EditorViewModel
    @StateObject private var previewViewModel: PreviewViewModel
    @State private var pdfExportFlowCoordinator = PDFExportFlowCoordinator()
    @State private var selectedSection: AppSection = .editor
    @State private var editorScrollOffset: CGPoint = .zero
    @State private var editorRequestedSelectedRange: NSRange?
    @State private var isEditorChromeVisible = true
    @State private var preflightResult: PreflightResult?
    @State private var generatedPDFURL: URL?
    @State private var exportedPDF: ExportedPDF?
    @State private var exportErrorMessage = ""
    @State private var showsExportError = false
    @State private var isExportingPDF = false

    private let preflightService = PDFPreflightService()
    private let pdfExportService = PDFExportService()

    init(
        documentStore: DocumentStore,
        proStore: HonkumiProStore,
        pdfExportAdService: PDFExportAdService,
        manuscriptFormattingCoordinator: ManuscriptFormattingCoordinator,
        presentedSettingsScope: Binding<SettingsViewModel.Scope?>,
        presentedSettingsInitialTab: Binding<SettingsInitialTab>
    ) {
        self.documentStore = documentStore
        self.proStore = proStore
        self.manuscriptFormattingCoordinator = manuscriptFormattingCoordinator
        self.pdfExportAdService = pdfExportAdService
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
                        requestedSelectedRange: $editorRequestedSelectedRange,
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
        .overlay {
            if manuscriptFormattingCoordinator.isFormatting {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("フォーマット中")
                        .font(.footnote.weight(.medium))
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .allowsHitTesting(false)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("フォーマット中")
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
                onNavigateToIssue: { issue in
                    navigateToIssue(issue)
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
            previewViewModel.setGenerationSuspended(presentedSettingsScope != nil)
            updatePreviewActivity(for: selectedSection)
        }
        .onDisappear {
            previewViewModel.setPreviewActive(false)
        }
        .onChange(of: selectedSection) { _, section in
            isEditorChromeVisible = true
            updatePreviewActivity(for: section)
        }
        .onChange(of: presentedSettingsScope?.id) { _, scopeID in
            previewViewModel.setGenerationSuspended(scopeID != nil)
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

    private func navigateToIssue(_ issue: PreflightIssue) {
        guard let location = issue.location,
              location.type == .text,
              let characterRange = location.characterRange else {
            return
        }

        selectedSection = .editor
        editorRequestedSelectedRange = NSRange(
            location: max(characterRange.lowerBound, 0),
            length: max(characterRange.count, 0)
        )
        preflightResult = nil
    }

    private func exportPDF(document: ManuscriptDocument? = nil, isAlreadyExporting: Bool = false) {
        guard isAlreadyExporting || !isExportingPDF else { return }
        if !isAlreadyExporting {
            isExportingPDF = true
        }

        let exportDocument = outputDocument(from: document ?? documentStore.document)
        let subscriptionStatus = documentStore.subscriptionStatus
        let entitlementState = proStore.entitlementState

        Task {
            await pdfExportFlowCoordinator.exportAndShare(
                document: exportDocument,
                subscriptionStatus: subscriptionStatus,
                entitlementState: entitlementState,
                pdfExporter: pdfExportService,
                adPresenter: pdfExportAdService,
                storeGeneratedURL: { url in
                    generatedPDFURL = url
                },
                share: { url in
                    exportedPDF = ExportedPDF(url: url)
                    isExportingPDF = false
                },
                handleError: { error in
                    exportErrorMessage = error.localizedDescription
                    showsExportError = true
                    isExportingPDF = false
                }
            )
        }
    }

    private func outputDocument(from document: ManuscriptDocument? = nil) -> ManuscriptDocument {
        document ?? documentStore.document
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

private extension ProcessInfo {
    var isRunningXCTest: Bool {
        environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
    }
}
