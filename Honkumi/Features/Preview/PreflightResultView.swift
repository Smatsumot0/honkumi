import SwiftUI
import UIKit

struct PreflightResultView: View {
    let result: PreflightResult
    let onReturnToFix: () -> Void
    let onNavigateToIssue: (PreflightIssue) -> Void
    let onAutoFixAndContinue: () -> Void
    let onIgnoreWarningsAndContinue: () -> Void

    private var problemIssues: [PreflightIssue] {
        result.issues.filter { $0.severity == .error || $0.severity == .warning }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(result.hasProblems ? "修正が必要な項目があります" : "入稿チェック完了")
                            .font(.headline)
                        Text(summaryText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section(result.hasProblems ? "確認項目" : "結果") {
                    if problemIssues.isEmpty {
                        Text("警告はありません。このままPDF出力へ進めます。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(problemIssues) { issue in
                            issueRow(issue)
                        }
                    }
                }
            }
            .navigationTitle("入稿チェック")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                actionFooter
            }
        }
    }

    private var actionFooter: some View {
        VStack(spacing: 10) {
            if result.hasProblems {
                HStack(spacing: 10) {
                    Button {
                        onReturnToFix()
                    } label: {
                        Text("戻って修正")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    if !result.autoFixableIssues.isEmpty {
                        Button {
                            onAutoFixAndContinue()
                        } label: {
                            Text("自動修正")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Button {
                    onIgnoreWarningsAndContinue()
                } label: {
                    Text("警告を無視して続行")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!result.canContinue)
            } else {
                Button {
                    onIgnoreWarningsAndContinue()
                } label: {
                    Text("PDF出力へ進む")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var summaryText: String {
        if result.hasProblems {
            return "エラー \(result.errorCount)件 / 警告 \(result.warningCount)件 / 自動修正可能 \(result.autoFixableIssues.count)件"
        }

        return "修正が必要な項目はありません。"
    }

    private func issueRow(_ issue: PreflightIssue) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(issue.severity.displayName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(severityColor(issue.severity), in: Capsule())

                Text(issue.title)
                    .font(.headline)
            }

            Text(issue.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let locationDescription = locationDescription(issue.location) {
                Text("対象範囲: \(locationDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if issue.isAutoFixable, let autoFixDescription = issue.autoFixDescription {
                Label(autoFixDescription, systemImage: "wand.and.sparkles")
                    .font(.caption)
                    .foregroundStyle(.blue)
            } else if issue.severity != .info {
                Label("手動で確認してください", systemImage: "hand.point.up.left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if canNavigate(to: issue) {
                Button {
                    onNavigateToIssue(issue)
                } label: {
                    Label("該当箇所へ移動", systemImage: "arrow.turn.down.right")
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    private func severityColor(_ severity: PreflightSeverity) -> Color {
        switch severity {
        case .error:
            .red
        case .warning:
            .orange
        case .info:
            .blue
        }
    }

    private func locationDescription(_ location: PreflightIssueLocation?) -> String? {
        guard let location else { return nil }

        var parts: [String] = []
        switch location.type {
        case .text:
            parts.append("本文")
        case .settings:
            parts.append("設定")
        case .page:
            parts.append("本文")
        case .colophon:
            parts.append("奥付")
        case .toc:
            parts.append("設定")
        case .pdf:
            parts.append("PDF")
        }

        if let pageNumber = location.pageNumber {
            parts.append("\(pageNumber)ページ")
        }

        if location.type == .text, let characterRange = location.characterRange {
            parts.append("本文\(characterRange.lowerBound + 1)文字目付近")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }

    private func canNavigate(to issue: PreflightIssue) -> Bool {
        guard let location = issue.location,
              location.type == .text,
              location.characterRange != nil else {
            return false
        }

        return true
    }
}

struct ExportedPDF: Identifiable {
    let id = UUID()
    let url: URL
}

struct PDFShareSheetView: View {
    let exportedPDF: ExportedPDF
    @State private var isPreparingShare = true
    @State private var isOpeningShareMenu = false
    @State private var isShareSheetPresented = false
    @State private var sharePreparationError: String?
    @State private var showsSaveCompleted = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if isPreparingShare {
                    ProgressView()
                        .controlSize(.large)

                    Text("保存準備中")
                        .font(.headline)

                    Text("PDFを保存・共有できる状態にしています。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else if let sharePreparationError {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)

                    Text("PDFの準備に失敗しました")
                        .font(.headline)

                    Text(sharePreparationError)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)

                    Text("PDFの準備ができました")
                        .font(.headline)

                    Button {
                        isOpeningShareMenu = true
                        isShareSheetPresented = true
                    } label: {
                        if isOpeningShareMenu {
                            HStack {
                                ProgressView()
                                Text("メニューを開いています")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Label("保存・共有", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isOpeningShareMenu)
                    .padding(.horizontal)
                }
            }
            .padding()
            .navigationTitle("PDF出力")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: exportedPDF.id) {
                await prepareShare()
            }
            .sheet(isPresented: $isShareSheetPresented, onDismiss: {
                isOpeningShareMenu = false
            }) {
                PDFActivityViewController(url: exportedPDF.url) { completed in
                    isOpeningShareMenu = false
                    if completed {
                        showsSaveCompleted = true
                    }
                }
            }
            .alert("保存が完了しました", isPresented: $showsSaveCompleted) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    @MainActor
    private func prepareShare() async {
        isPreparingShare = true
        sharePreparationError = nil

        do {
            try await Task.detached {
                let url = exportedPDF.url
                let fileManager = FileManager.default
                guard fileManager.fileExists(atPath: url.path) else {
                    throw PDFSharePreparationError.fileNotFound
                }

                let attributes = try fileManager.attributesOfItem(atPath: url.path)
                let fileSize = attributes[.size] as? NSNumber
                guard fileSize?.intValue ?? 0 > 0 else {
                    throw PDFSharePreparationError.emptyFile
                }

                let handle = try FileHandle(forReadingFrom: url)
                defer {
                    try? handle.close()
                }
                _ = try handle.read(upToCount: 1)
            }.value

            isPreparingShare = false
        } catch {
            sharePreparationError = error.localizedDescription
            isPreparingShare = false
        }
    }
}

private enum PDFSharePreparationError: LocalizedError {
    case fileNotFound
    case emptyFile

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            "PDFファイルが見つかりません。もう一度PDF出力を実行してください。"
        case .emptyFile:
            "PDFファイルが空です。もう一度PDF出力を実行してください。"
        }
    }
}

private struct PDFActivityViewController: UIViewControllerRepresentable {
    let url: URL
    let onComplete: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let viewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        viewController.completionWithItemsHandler = { _, completed, _, _ in
            DispatchQueue.main.async {
                onComplete(completed)
            }
        }
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
