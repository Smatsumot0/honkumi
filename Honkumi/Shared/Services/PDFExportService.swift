import Foundation
import UIKit

struct PDFExportService {
    private let bodyExporter = BodyPDFExportService()

    func export(document: ManuscriptDocument) async throws -> URL {
        try await bodyExporter.export(document: document)
    }
}

struct BodyPDFExportService {
    func export(document: ManuscriptDocument) async throws -> URL {
        let settings = document.settings.validated
        let pages = ManuscriptPaginator.pages(for: document)
        let firstLayout = LayoutCalculator.layout(for: settings, pageNumber: 1)
        let bounds = CGRect(x: 0, y: 0, width: firstLayout.pageWidth, height: firstLayout.pageHeight)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(document.id.uuidString)
            .appendingPathExtension("pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)

        try renderer.writePDF(to: outputURL) { context in
            for (index, page) in pages.enumerated() {
                let layout = LayoutCalculator.layout(for: settings, pageNumber: index + 1)
                context.beginPage()
                draw(page, pageNumber: index + 1, in: layout)
            }
        }

        return outputURL
    }

    private func draw(_ page: PreviewPage, pageNumber: Int, in layout: PageLayout) {
        drawVerticalText(page.columns, in: layout)

        if layout.settings.showChapterTitle, let chapterTitle = page.chapterTitle {
            drawChapterTitle(chapterTitle, in: layout)
        }

        drawPageNumber(pageNumber, in: layout)
    }

    private func drawVerticalText(_ columns: [String], in layout: PageLayout) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: layout.settings.japaneseFont.postScriptName, size: layout.fontSize)
                ?? UIFont.systemFont(ofSize: layout.fontSize),
            .kern: layout.settings.characterSpacing
        ]
        let lineCount = layout.settings.linesPerPage
        let characterCount = layout.settings.charactersPerLine

        for displayIndex in (0..<lineCount).reversed() {
            let sourceColumn = columns.indices.contains(displayIndex) ? columns[displayIndex] : ""
            let columnOffset = lineCount - 1 - displayIndex
            let x = layout.bodyFrame.maxX - CGFloat(columnOffset + 1) * layout.lineAdvance

            for rowIndex in 0..<characterCount {
                let character = character(at: rowIndex, in: sourceColumn)
                guard !character.isEmpty else { continue }

                let glyph = pdfGlyph(for: character)
                let rect = CGRect(
                    x: x,
                    y: layout.bodyFrame.minY + CGFloat(rowIndex) * layout.characterAdvance,
                    width: layout.lineAdvance,
                    height: layout.characterAdvance
                )
                let attributedText = NSAttributedString(string: glyph, attributes: attributes)
                attributedText.draw(in: rect)
            }
        }
    }

    private func drawChapterTitle(_ title: String, in layout: PageLayout) {
        let font = UIFont(name: layout.settings.japaneseFont.postScriptName, size: max(layout.fontSize * 0.8, 6))
            ?? UIFont.systemFont(ofSize: max(layout.fontSize * 0.8, 6))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.secondaryLabel
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        let x = layout.isOddPage ? layout.bodyFrame.minX : layout.bodyFrame.maxX - size.width
        let y = max(layout.marginTop * 0.5, 4)
        (title as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
    }

    private func drawPageNumber(_ pageNumber: Int, in layout: PageLayout) {
        guard layout.settings.pageNumberPosition != .hidden else { return }

        let text = "\(pageNumber)" as NSString
        let font = UIFont.monospacedDigitSystemFont(ofSize: max(layout.fontSize * 0.8, 6), weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.secondaryLabel
        ]
        let size = text.size(withAttributes: attributes)
        let x: CGFloat

        switch layout.settings.pageNumberPosition {
        case .hidden:
            return
        case .center:
            x = layout.bodyFrame.midX - size.width / 2
        case .outside:
            x = layout.isOddPage ? layout.bodyFrame.minX : layout.bodyFrame.maxX - size.width
        }

        let y = layout.pageHeight - layout.marginBottom * 0.72
        text.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
    }

    private func character(at index: Int, in column: String) -> String {
        guard index < column.count else { return "" }
        let stringIndex = column.index(column.startIndex, offsetBy: index)
        return String(column[stringIndex])
    }

    private func pdfGlyph(for character: String) -> String {
        switch character {
        case "「":
            "﹁"
        case "」":
            "﹂"
        case "『":
            "﹃"
        case "』":
            "﹄"
        case "（", "(":
            "︵"
        case "）", ")":
            "︶"
        case "【":
            "︻"
        case "】":
            "︼"
        case "［", "[":
            "﹇"
        case "］", "]":
            "﹈"
        case "｛", "{":
            "︷"
        case "｝", "}":
            "︸"
        case "〈":
            "︿"
        case "〉":
            "﹀"
        case "《":
            "︽"
        case "》":
            "︾"
        case "…", "‥":
            "⋯"
        case "―", "─", "—", "ｰ", "ー":
            "｜"
        default:
            character
        }
    }
}

struct CoverPDFExportService {
    func exportCover() async throws -> URL {
        throw PDFExportError.notImplemented
    }
}

struct PDFMergeService {
    func merge(_ urls: [URL]) async throws -> URL {
        _ = urls
        throw PDFExportError.notImplemented
    }
}

enum PDFExportError: LocalizedError {
    case notImplemented

    var errorDescription: String? {
        "PDF export is not implemented yet."
    }
}
