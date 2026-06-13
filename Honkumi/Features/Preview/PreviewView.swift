import PDFKit
import SwiftUI
import UIKit

struct PreviewView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: PreviewViewModel
    let displayMode: PreviewPDFDisplayMode

    var body: some View {
        ZStack {
            PreviewPDFStyle.canvasBackground(colorScheme)
                .ignoresSafeArea()

            if let previewPDFURL = viewModel.previewPDFURL {
                PDFKitPreviewView(
                    url: previewPDFURL,
                    displayMode: displayMode,
                    backgroundColor: PreviewPDFStyle.uiCanvasBackground(colorScheme)
                )
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    if viewModel.isGeneratingPDF {
                        loadingBanner
                            .padding(.top, 12)
                    }
                }
            } else if let generationErrorMessage = viewModel.generationErrorMessage {
                errorView(message: generationErrorMessage)
            } else {
                loadingView
            }
        }
        .background(PreviewPDFStyle.canvasBackground(colorScheme))
        .onAppear {
            viewModel.preparePreviewIfNeeded(for: displayMode.previewKind)
        }
        .onChange(of: displayMode) { _, mode in
            viewModel.preparePreviewIfNeeded(for: mode.previewKind)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("PDFプレビューを生成中")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .accessibilityElement(children: .combine)
    }

    private var loadingBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("PDFプレビューを更新中")
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.orange)

            Text("PDFプレビューを表示できません")
                .font(.headline)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                viewModel.preparePreviewIfNeeded(for: displayMode.previewKind)
            } label: {
                Label("再生成", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(22)
        .frame(maxWidth: 360)
        .accessibilityElement(children: .contain)
    }
}

enum PreviewPDFDisplayMode: String, Equatable, Identifiable {
    case single
    case spread

    var id: String { rawValue }

    var pdfDisplayMode: PDFDisplayMode {
        switch self {
        case .single:
            .singlePageContinuous
        case .spread:
            .singlePageContinuous
        }
    }

    var previewKind: PreviewPDFKind {
        switch self {
        case .single:
            .normal
        case .spread:
            .spread
        }
    }
}

private struct PDFKitPreviewView: UIViewRepresentable {
    let url: URL
    let displayMode: PreviewPDFDisplayMode
    let backgroundColor: UIColor

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        configure(pdfView)
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        configure(pdfView)

        let needsDocumentLoad = context.coordinator.currentURL != url || pdfView.document == nil
        let needsDisplayModeRefresh = context.coordinator.currentDisplayMode != displayMode
        guard needsDocumentLoad || needsDisplayModeRefresh else {
            return
        }

        if needsDocumentLoad {
            loadDocument(into: pdfView, context: context)
        } else {
            context.coordinator.currentDisplayMode = displayMode
            refitDocument(in: pdfView)
        }
    }

    static func dismantleUIView(_ pdfView: PDFView, coordinator: Coordinator) {
        pdfView.document = nil
        coordinator.currentURL = nil
        coordinator.currentDisplayMode = nil
    }

    private func configure(_ pdfView: PDFView) {
        pdfView.backgroundColor = backgroundColor
        pdfView.displayMode = displayMode.pdfDisplayMode
        pdfView.displayDirection = .vertical
        pdfView.displaysAsBook = false
        pdfView.displaysPageBreaks = true
        pdfView.pageBreakMargins = UIEdgeInsets(top: 14, left: 0, bottom: 14, right: 0)
        pdfView.autoScales = true
        pdfView.minScaleFactor = 0.25
        pdfView.maxScaleFactor = 6

        if let scrollView = firstScrollView(in: pdfView) {
            scrollView.backgroundColor = backgroundColor
            scrollView.alwaysBounceVertical = true
            scrollView.alwaysBounceHorizontal = false
            scrollView.showsVerticalScrollIndicator = true
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.delaysContentTouches = false
            scrollView.canCancelContentTouches = true
            scrollView.decelerationRate = .normal
        }
    }

    private func loadDocument(into pdfView: PDFView, context: Context) {
        guard FileManager.default.fileExists(atPath: url.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.int64Value > 0,
              let document = PDFDocument(url: url),
              document.pageCount > 0
        else {
            pdfView.document = nil
            context.coordinator.currentURL = nil
            return
        }

        pdfView.document = document
        context.coordinator.currentURL = url
        context.coordinator.currentDisplayMode = displayMode

        refitDocument(in: pdfView, goesToFirstPage: true)
    }

    private func refitDocument(in pdfView: PDFView, goesToFirstPage: Bool = false) {
        let document = pdfView.document
        let currentPage = pdfView.currentPage
        DispatchQueue.main.async {
            guard pdfView.document === document else { return }
            pdfView.autoScales = true
            let fitScale = pdfView.scaleFactorForSizeToFit
            if fitScale.isFinite, fitScale > 0 {
                pdfView.minScaleFactor = max(fitScale * 0.75, 0.2)
                pdfView.maxScaleFactor = max(fitScale * 5, 4)
                pdfView.scaleFactor = fitScale
            }

            if goesToFirstPage, let firstPage = document?.page(at: 0) {
                pdfView.go(to: firstPage)
            } else if let currentPage {
                pdfView.go(to: currentPage)
            }
        }
    }

    private func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView {
            return scrollView
        }

        for subview in view.subviews {
            if let scrollView = firstScrollView(in: subview) {
                return scrollView
            }
        }

        return nil
    }

    final class Coordinator {
        var currentURL: URL?
        var currentDisplayMode: PreviewPDFDisplayMode?
    }
}

private enum PreviewPDFStyle {
    static func canvasBackground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.055, green: 0.057, blue: 0.065)
            : Color(.secondarySystemGroupedBackground)
    }

    static func uiCanvasBackground(_ colorScheme: ColorScheme) -> UIColor {
        colorScheme == .dark
            ? UIColor(red: 0.055, green: 0.057, blue: 0.065, alpha: 1)
            : UIColor.secondarySystemGroupedBackground
    }
}
