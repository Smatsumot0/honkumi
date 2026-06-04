import SwiftUI
import UIKit

struct PreflightResultView: View {
    let result: PreflightResult
    let onReturnToFix: () -> Void
    let onAutoFixAndContinue: () -> Void
    let onIgnoreWarningsAndContinue: () -> Void
    let onCancel: () -> Void

    private var problemIssues: [PreflightIssue] {
        result.issues.filter { $0.severity == .error || $0.severity == .warning }
    }

    private var infoIssues: [PreflightIssue] {
        result.issues.filter { $0.severity == .info }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(result.hasProblems ? "修正が必要な項目があります" : "問題なし")
                            .font(.headline)
                        Text("エラー \(result.errorCount)件 / 警告 \(result.warningCount)件 / 自動修正可能 \(result.autoFixableIssues.count)件")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("問題リスト") {
                    if problemIssues.isEmpty {
                        Text("エラーと警告はありません")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(problemIssues) { issue in
                            issueRow(issue)
                        }
                    }
                }

                if !infoIssues.isEmpty {
                    Section("情報") {
                        ForEach(infoIssues) { issue in
                            issueRow(issue)
                        }
                    }
                }

                Section {
                    Button("戻って修正") {
                        onReturnToFix()
                    }

                    Button("自動修正して続行") {
                        onAutoFixAndContinue()
                    }
                    .disabled(result.autoFixableIssues.isEmpty)

                    Button("警告を無視して続行") {
                        onIgnoreWarningsAndContinue()
                    }
                    .disabled(!result.canContinue)

                    Button("キャンセル", role: .cancel) {
                        onCancel()
                    }
                }
            }
            .navigationTitle("入稿チェック")
            .navigationBarTitleDisplayMode(.inline)
        }
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
                Text(locationDescription)
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
            parts.append("ページ")
        case .colophon:
            parts.append("奥付")
        case .toc:
            parts.append("目次")
        }

        if let pageNumber = location.pageNumber {
            parts.append("\(pageNumber)ページ")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " / ")
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
                PDFActivityViewController(url: exportedPDF.url) {
                    isOpeningShareMenu = false
                }
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
    let onReady: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let viewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        viewController.completionWithItemsHandler = { _, _, _, _ in
            onReady()
        }
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
