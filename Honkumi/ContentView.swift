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
            .navigationTitle("作品")
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
    @State private var selectedSection: AppSection = .editor
    @State private var previewPageScale: CGFloat = 1
    @State private var previewFocusedPage = 1
    @State private var previewHorizontalAnchor: CGFloat = 0.5
    @State private var previewScrollOffset: CGPoint = .zero

    var body: some View {
        VStack(spacing: 0) {
            Picker("画面切り替え", selection: $selectedSection) {
                ForEach(AppSection.allCases) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)

            Group {
                switch selectedSection {
                case .editor:
                    EditorView(viewModel: EditorViewModel(documentStore: documentStore))
                case .preview:
                    PreviewView(
                        viewModel: PreviewViewModel(documentStore: documentStore),
                        pageScale: $previewPageScale,
                        focusedPage: $previewFocusedPage,
                        horizontalAnchor: $previewHorizontalAnchor,
                        scrollOffset: $previewScrollOffset
                    )
                }
            }
        }
        .navigationTitle(documentStore.document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presentedSettingsScope = .activeWork
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("設定")
            }
        }
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
