import CoreImage.CIFilterBuiltins
import Foundation
import UIKit

struct PDFExportService {
    private let bodyExporter = BodyPDFExportService()

    func export(document: ManuscriptDocument, subscriptionStatus: SubscriptionStatus = .free) async throws -> URL {
        try await bodyExporter.export(document: document, subscriptionStatus: subscriptionStatus)
    }
}

private enum FooterPlacement {
    static let pageNumberBottomMultiplier: CGFloat = 0.82
    static let poweredByBodyBottomMultiplier: CGFloat = 0.48
    static let poweredByColophonBottomMultiplier: CGFloat = 0.72
    static let bottomInset: CGFloat = 2
}

private struct VerticalHorizontalColophonMetrics {
    let blockX: CGFloat
    let blockY: CGFloat
    let blockWidth: CGFloat
    let labelWidth: CGFloat
    let valueWidth: CGFloat
    let valueX: CGFloat
    let qrSize: CGFloat
    let lineHeight: CGFloat
}

struct BodyPDFExportService {
    func export(document: ManuscriptDocument, subscriptionStatus: SubscriptionStatus = .free) async throws -> URL {
        let settings = document.settings.validated
        let exportDocument = formattedExportDocument(
            from: document,
            settings: settings,
            subscriptionStatus: subscriptionStatus
        )
        let pages = ManuscriptPaginator.pages(for: exportDocument)
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
                draw(
                    page,
                    pageNumber: index + 1,
                    totalPageCount: pages.count,
                    subscriptionStatus: subscriptionStatus,
                    in: layout
                )
            }
        }

        return outputURL
    }

    private func formattedExportDocument(
        from document: ManuscriptDocument,
        settings: EditorSettings,
        subscriptionStatus: SubscriptionStatus
    ) -> ManuscriptDocument {
        var exportDocument = document
        exportDocument.settings = settings
        exportDocument.body = ManuscriptFormatter.formatManuscriptText(
            document.body,
            settings: settings.formatSettings,
            options: FormatOptions(isPremiumUser: subscriptionStatus == .paid)
        )
        return exportDocument
    }

    private func draw(
        _ page: PreviewPage,
        pageNumber: Int,
        totalPageCount: Int,
        subscriptionStatus: SubscriptionStatus,
        in layout: PageLayout
    ) {
        switch page.kind {
        case .body:
            drawVerticalText(page.columns, in: layout)
        case let .colophon(colophon):
            drawColophonContent(
                colophon,
                columns: page.columns,
                subscriptionStatus: subscriptionStatus,
                in: layout
            )
        }

        if page.kind == .body,
           layout.settings.showChapterTitle,
           let chapterTitle = page.chapterTitle,
           !page.chapterTitlesStartingOnPage.contains(chapterTitle) {
            drawChapterTitle(chapterTitle, in: layout)
        }

        if page.kind == .body {
            drawPageNumber(pageNumber, subscriptionStatus: subscriptionStatus, in: layout)
        }

        if shouldShowPoweredByHonkumi(
            page: page,
            pageNumber: pageNumber,
            totalPageCount: totalPageCount,
            subscriptionStatus: subscriptionStatus
        ) {
            drawPoweredByHonkumi(on: page, in: layout)
        }
    }

    private func drawColophonContent(
        _ colophon: ColophonSettings,
        columns: [String],
        subscriptionStatus: SubscriptionStatus,
        in layout: PageLayout
    ) {
        drawHorizontalColophon(colophon, subscriptionStatus: subscriptionStatus, in: layout)
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

    private func drawPageNumber(_ pageNumber: Int, subscriptionStatus: SubscriptionStatus, in layout: PageLayout) {
        let position = pageNumberPosition(in: layout, subscriptionStatus: subscriptionStatus)
        guard position != .hidden else { return }

        let text = "\(pageNumber)" as NSString
        let font = UIFont.monospacedDigitSystemFont(ofSize: max(layout.fontSize * 0.8, 6), weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.secondaryLabel
        ]
        let size = text.size(withAttributes: attributes)
        let x: CGFloat

        switch position {
        case .hidden:
            return
        case .center:
            x = layout.bodyFrame.midX - size.width / 2
        case .outside:
            x = layout.isOddPage ? layout.bodyFrame.minX : layout.bodyFrame.maxX - size.width
        }

        let y = footerY(
            pageHeight: layout.pageHeight,
            marginBottom: layout.marginBottom,
            multiplier: FooterPlacement.pageNumberBottomMultiplier,
            textHeight: size.height
        )
        text.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
    }

    private func pageNumberPosition(in layout: PageLayout, subscriptionStatus: SubscriptionStatus) -> PageNumberPosition {
        if subscriptionStatus == .free {
            return layout.settings.pageNumberPosition == .hidden ? .hidden : .outside
        }

        return layout.settings.pageNumberPosition
    }

    private func drawHorizontalColophon(
        _ colophon: ColophonSettings,
        subscriptionStatus: SubscriptionStatus,
        in layout: PageLayout
    ) {
        let entries = ManuscriptPaginator.colophonEntries(from: colophon)
        let font = UIFont(name: layout.settings.japaneseFont.postScriptName, size: layout.fontSize)
            ?? UIFont.systemFont(ofSize: layout.fontSize)
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.secondaryLabel
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.label
        ]
        let labelWidth = min(layout.bodyFrame.width * 0.28, 72)
        let valueX = layout.bodyFrame.minX + labelWidth + 10
        let lineHeight = max(layout.fontSize * 1.65, 12)
        let startY = max(
            layout.bodyFrame.minY,
            layout.bodyFrame.maxY - horizontalColophonContentHeight(
                colophon,
                subscriptionStatus: subscriptionStatus,
                lineHeight: lineHeight,
                in: layout
            )
        )

        var rowIndex = 0
        for entry in entries {
            if entry.addsPrecedingSpace {
                rowIndex += 1
            }

            let y = startY + CGFloat(rowIndex) * lineHeight
            guard y < layout.bodyFrame.maxY - lineHeight else { break }

            if entry.id == "hp" {
                rowIndex += drawHorizontalColophonHPEntry(
                    entry,
                    colophon: colophon,
                    labelWidth: labelWidth,
                    valueX: valueX,
                    y: y,
                    lineHeight: lineHeight,
                    labelAttributes: labelAttributes,
                    valueAttributes: valueAttributes,
                    in: layout
                )
            } else if entry.id == "creator",
                      subscriptionStatus == .paid,
                      colophon.hasCreatorImage,
                      drawHorizontalCircleLogoCreator(
                        colophon,
                        y: y,
                        lineHeight: lineHeight,
                        valueAttributes: valueAttributes,
                        in: layout
                      ) {
                rowIndex += max(Int(ceil(creatorImageBlockHeight(colophon, lineHeight: lineHeight, in: layout) / lineHeight)), 1)
            } else if entry.label.isEmpty {
                let textAttributes = entry.centersInHorizontalLayout
                    ? centeredAttributes(from: valueAttributes)
                    : valueAttributes
                (entry.value as NSString).draw(
                    in: CGRect(x: layout.bodyFrame.minX, y: y, width: layout.bodyFrame.width, height: lineHeight),
                    withAttributes: textAttributes
                )
                rowIndex += 1
            } else {
                (entry.label as NSString).draw(
                    in: CGRect(x: layout.bodyFrame.minX, y: y, width: labelWidth, height: lineHeight),
                    withAttributes: labelAttributes
                )
                (entry.value as NSString).draw(
                    in: CGRect(x: valueX, y: y, width: layout.bodyFrame.maxX - valueX, height: lineHeight),
                    withAttributes: valueAttributes
                )
                rowIndex += 1
            }
            if entry.addsFollowingSpace {
                rowIndex += 1
            }
        }
    }

    private func horizontalColophonContentHeight(
        _ colophon: ColophonSettings,
        subscriptionStatus: SubscriptionStatus,
        lineHeight: CGFloat,
        in layout: PageLayout
    ) -> CGFloat {
        let entries = ManuscriptPaginator.colophonEntries(from: colophon)
        guard !entries.isEmpty else { return 0 }

        let qrSize = horizontalColophonQRCodeSize(in: layout)
        var height: CGFloat = CGFloat(max(entries.count - 1, 0)) * 8

        for entry in entries {
            if entry.addsPrecedingSpace {
                height += lineHeight
            }

            if entry.id == "hp", !colophon.websiteURL.isEmpty {
                height += qrSize + 4 + lineHeight
            } else if entry.id == "creator",
                      subscriptionStatus == .paid,
                      colophon.hasCreatorImage {
                height += max(lineHeight, creatorImageBlockHeight(colophon, lineHeight: lineHeight, in: layout))
            } else {
                height += lineHeight
            }

            if entry.addsFollowingSpace {
                height += lineHeight
            }
        }

        return height
    }

    private func drawHorizontalColophonHPEntry(
        _ entry: ColophonEntry,
        colophon: ColophonSettings,
        labelWidth: CGFloat,
        valueX: CGFloat,
        y: CGFloat,
        lineHeight: CGFloat,
        labelAttributes: [NSAttributedString.Key: Any],
        valueAttributes: [NSAttributedString.Key: Any],
        in layout: PageLayout
    ) -> Int {
        (entry.label as NSString).draw(
            in: CGRect(x: layout.bodyFrame.minX, y: y, width: labelWidth, height: lineHeight),
            withAttributes: labelAttributes
        )

        guard let image = qrCodeImage(for: colophon.websiteURL) else {
            (entry.value as NSString).draw(
                in: CGRect(x: valueX, y: y, width: layout.bodyFrame.maxX - valueX, height: lineHeight),
                withAttributes: valueAttributes
            )
            return 1
        }

        let qrSize = horizontalColophonQRCodeSize(in: layout)
        let valueWidth = (entry.value as NSString).size(withAttributes: valueAttributes).width
        let qrX = valueX + max((valueWidth - qrSize) / 2, 0)
        image.draw(in: CGRect(x: qrX, y: y, width: qrSize, height: qrSize))

        let valueY = y + qrSize + 4
        if valueY < layout.bodyFrame.maxY - lineHeight {
            (entry.value as NSString).draw(
                in: CGRect(x: valueX, y: valueY, width: layout.bodyFrame.maxX - valueX, height: lineHeight),
                withAttributes: valueAttributes
            )
        }

        return max(Int(ceil((qrSize + 4 + lineHeight) / lineHeight)), 1)
    }

    @discardableResult
    private func drawHorizontalCircleLogoCreator(
        _ colophon: ColophonSettings,
        y: CGFloat,
        lineHeight: CGFloat,
        valueAttributes: [NSAttributedString.Key: Any],
        in layout: PageLayout
    ) -> Bool {
        guard let data = colophon.circleImageData,
              let image = UIImage(data: data) else { return false }

        let height = creatorImageHeight(in: layout)
        let maxImageWidth = layout.bodyFrame.width * 0.36
        let aspect = image.size.width / max(image.size.height, 1)
        let imageSize = CGSize(width: min(height * aspect, maxImageWidth), height: height)
        let x = layout.bodyFrame.midX - imageSize.width / 2
        image.draw(in: CGRect(x: x, y: y, width: imageSize.width, height: imageSize.height))

        let authorName = colophon.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !authorName.isEmpty {
            (authorName as NSString).draw(
                in: CGRect(
                    x: layout.bodyFrame.minX,
                    y: y + height + 4,
                    width: layout.bodyFrame.width,
                    height: lineHeight
                ),
                withAttributes: centeredAttributes(from: valueAttributes)
            )
        }

        return true
    }

    private func creatorImageBlockHeight(
        _ colophon: ColophonSettings,
        lineHeight: CGFloat,
        in layout: PageLayout
    ) -> CGFloat {
        let hasAuthorName = !colophon.authorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return creatorImageHeight(in: layout) + (hasAuthorName ? 4 + lineHeight : 0)
    }

    private func creatorImageHeight(in layout: PageLayout) -> CGFloat {
        max(layout.fontSize * 2.4, 18)
    }

    private func centeredAttributes(
        from attributes: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        var centeredAttributes = attributes
        centeredAttributes[.paragraphStyle] = paragraphStyle
        return centeredAttributes
    }

    private func drawVerticalColophonQRCode(_ colophon: ColophonSettings, columns: [String], in layout: PageLayout) {
        guard let image = qrCodeImage(for: colophon.websiteURL) else { return }

        let metrics = verticalHorizontalColophonMetrics(in: layout)
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: layout.settings.japaneseFont.postScriptName, size: layout.fontSize)
                ?? UIFont.systemFont(ofSize: layout.fontSize)
        ]
        let urlWidth = (colophon.websiteURL as NSString).size(withAttributes: valueAttributes).width
        let rect = CGRect(
            x: metrics.valueX + max((urlWidth - metrics.qrSize) / 2, 0),
            y: metrics.blockY,
            width: metrics.qrSize,
            height: metrics.qrSize
        )
        image.draw(in: rect)
    }

    private func drawVerticalHorizontalColophonEntries(_ colophon: ColophonSettings, in layout: PageLayout) {
        let entries = ManuscriptPaginator.verticalHorizontalColophonEntries(from: colophon)
        guard !entries.isEmpty else { return }

        let font = UIFont(name: layout.settings.japaneseFont.postScriptName, size: layout.fontSize)
            ?? UIFont.systemFont(ofSize: layout.fontSize)
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.secondaryLabel
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.label
        ]
        let metrics = verticalHorizontalColophonMetrics(in: layout)

        if let hpEntry = entries.first(where: { $0.id == "hp" }) {
            drawVerticalHorizontalColophonRow(
                hpEntry,
                y: metrics.blockY + metrics.qrSize + 4,
                metrics: metrics,
                labelAttributes: labelAttributes,
                valueAttributes: valueAttributes
            )
        }

        var rowIndex = 0
        for entry in entries where entry.id != "hp" {
            drawVerticalHorizontalColophonRow(
                entry,
                y: metrics.blockY + metrics.qrSize + metrics.lineHeight + 18 + CGFloat(rowIndex) * (metrics.lineHeight + 4),
                metrics: metrics,
                labelAttributes: labelAttributes,
                valueAttributes: valueAttributes
            )
            rowIndex += 1
        }
    }

    private func drawVerticalHorizontalColophonRow(
        _ entry: ColophonEntry,
        y: CGFloat,
        metrics: VerticalHorizontalColophonMetrics,
        labelAttributes: [NSAttributedString.Key: Any],
        valueAttributes: [NSAttributedString.Key: Any]
    ) {
        (entry.label as NSString).draw(
            in: CGRect(x: metrics.blockX, y: y, width: metrics.labelWidth, height: metrics.lineHeight),
            withAttributes: labelAttributes
        )
        (entry.value as NSString).draw(
            in: CGRect(
                x: metrics.valueX,
                y: y,
                width: metrics.valueWidth,
                height: metrics.lineHeight
            ),
            withAttributes: valueAttributes
        )
    }

    private func verticalHorizontalColophonMetrics(in layout: PageLayout) -> VerticalHorizontalColophonMetrics {
        let blockX = layout.bodyFrame.minX + layout.bodyFrame.width * 0.08
        let blockY = layout.bodyFrame.minY + layout.bodyFrame.height * 0.12
        let blockWidth = layout.bodyFrame.width * 0.58
        let labelWidth = min(layout.bodyFrame.width * 0.18, 48)
        let lineHeight = max(layout.fontSize * 1.65, 12)
        let qrSize = min(layout.bodyFrame.width * 0.23, layout.bodyFrame.height * 0.18, 58)
        let valueX = blockX + labelWidth + 8

        return VerticalHorizontalColophonMetrics(
            blockX: blockX,
            blockY: blockY,
            blockWidth: blockWidth,
            labelWidth: labelWidth,
            valueWidth: max(blockWidth - labelWidth - 8, 1),
            valueX: valueX,
            qrSize: qrSize,
            lineHeight: lineHeight
        )
    }

    private func horizontalColophonQRCodeSize(in layout: PageLayout) -> CGFloat {
        min(layout.bodyFrame.width * 0.22, 44)
    }

    private func drawPoweredByHonkumi(on page: PreviewPage, in layout: PageLayout) {
        let text = "Powered by Honkumi" as NSString
        let font = UIFont.systemFont(ofSize: max(layout.fontSize * 0.68, 5), weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.tertiaryLabel
        ]
        let size = text.size(withAttributes: attributes)
        let rawY: CGFloat = switch page.kind {
        case .body:
            layout.pageHeight - layout.marginBottom * FooterPlacement.poweredByBodyBottomMultiplier
        case .colophon:
            layout.pageHeight - layout.marginBottom * FooterPlacement.poweredByColophonBottomMultiplier
        }
        let y = clampedFooterY(rawY, pageHeight: layout.pageHeight, textHeight: size.height)
        let x = layout.pageWidth / 2 - size.width / 2

        text.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
    }

    private func footerY(
        pageHeight: CGFloat,
        marginBottom: CGFloat,
        multiplier: CGFloat,
        textHeight: CGFloat
    ) -> CGFloat {
        let rawY = pageHeight - marginBottom * multiplier
        return clampedFooterY(rawY, pageHeight: pageHeight, textHeight: textHeight)
    }

    private func clampedFooterY(_ y: CGFloat, pageHeight: CGFloat, textHeight: CGFloat) -> CGFloat {
        let maxY = pageHeight - textHeight - FooterPlacement.bottomInset
        return min(y, max(FooterPlacement.bottomInset, maxY))
    }

    private func shouldShowPoweredByHonkumi(
        page: PreviewPage,
        pageNumber: Int,
        totalPageCount: Int,
        subscriptionStatus: SubscriptionStatus
    ) -> Bool {
        guard subscriptionStatus.showsPoweredByHonkumi else { return false }

        switch page.kind {
        case .body:
            return pageNumber == totalPageCount
        case .colophon:
            return true
        }
    }

    private func qrCodeImage(for text: String) -> UIImage? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, let data = trimmedText.data(using: .utf8) else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        let transformedImage = outputImage.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext()
        guard let cgImage = context.createCGImage(transformedImage, from: transformedImage.extent) else { return nil }

        return UIImage(cgImage: cgImage)
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
