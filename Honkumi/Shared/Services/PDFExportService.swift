import CoreImage.CIFilterBuiltins
import Foundation
import UIKit

nonisolated struct PDFExportService {
    private let bodyExporter = BodyPDFExportService()

    func export(document: ManuscriptDocument, subscriptionStatus: SubscriptionStatus = .free) async throws -> URL {
        let exporter = bodyExporter
        return try await Task.detached(priority: .userInitiated) {
            try exporter.export(document: document, subscriptionStatus: subscriptionStatus)
        }.value
    }
}

nonisolated private enum FooterPlacement {
    static let poweredByBodyBottomMultiplier: CGFloat = 0.82
    static let poweredByColophonBottomMultiplier: CGFloat = 0.82
    static let bottomInset: CGFloat = 2
}

nonisolated private struct VerticalHorizontalColophonMetrics {
    let blockX: CGFloat
    let blockY: CGFloat
    let blockWidth: CGFloat
    let labelWidth: CGFloat
    let valueWidth: CGFloat
    let valueX: CGFloat
    let qrSize: CGFloat
    let lineHeight: CGFloat
}

nonisolated struct BodyPDFExportService {
    func export(document: ManuscriptDocument, subscriptionStatus: SubscriptionStatus = .free) throws -> URL {
        let paginationResult = ManuscriptRenderPipeline.paginationResult(
            for: document,
            subscriptionStatus: subscriptionStatus
        )
        let settings = paginationResult.document.settings.validated
        let pages = paginationResult.pages
        let firstLayout = LayoutCalculator.layout(for: settings, pageNumber: 1)
        let bounds = CGRect(x: 0, y: 0, width: firstLayout.pageWidth, height: firstLayout.pageHeight)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(Self.safePDFFileName(for: document.title))
            .appendingPathExtension("pdf")
        try? FileManager.default.removeItem(at: outputURL)
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

    private static func safePDFFileName(for title: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmedTitle.isEmpty ? "Honkumi" : trimmedTitle
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)
        let sanitizedName = baseName
            .components(separatedBy: invalidCharacters)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return fileSystemSafeFileNameComponent(sanitizedName.isEmpty ? "Honkumi" : sanitizedName)
    }

    private static func fileSystemSafeFileNameComponent(_ name: String) -> String {
        let maxBaseNameByteCount = 220
        guard name.utf8.count > maxBaseNameByteCount else { return name }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyyMMdd"
        let suffix = "_\(formatter.string(from: Date()))"
        let maxPrefixByteCount = max(maxBaseNameByteCount - suffix.utf8.count, 1)
        var prefix = ""

        for character in name {
            let candidate = prefix + String(character)
            guard candidate.utf8.count <= maxPrefixByteCount else { break }
            prefix = candidate
        }

        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmedPrefix.isEmpty ? "Honkumi" : trimmedPrefix) + suffix
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
            drawVerticalText(
                page.columns,
                isAdditionalFontPackUnlocked: subscriptionStatus == .paid,
                in: layout
            )
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
            drawChapterTitle(
                chapterTitle,
                isAdditionalFontPackUnlocked: subscriptionStatus == .paid,
                in: layout
            )
        }

        drawPageNumber(pageNumber, subscriptionStatus: subscriptionStatus, in: layout)

        if shouldShowPoweredByHonkumi(
            page: page,
            pageNumber: pageNumber,
            totalPageCount: totalPageCount,
            subscriptionStatus: subscriptionStatus
        ) {
            drawPoweredByHonkumi(
                on: page,
                pageNumber: pageNumber,
                subscriptionStatus: subscriptionStatus,
                in: layout
            )
        }
    }

    private func drawColophonContent(
        _ colophon: ColophonSettings,
        columns: [String],
        subscriptionStatus: SubscriptionStatus,
        in layout: PageLayout
    ) {
        drawHorizontalColophon(
            colophon,
            subscriptionStatus: subscriptionStatus,
            isAdditionalFontPackUnlocked: subscriptionStatus == .paid,
            in: layout
        )
    }

    private func drawVerticalText(
        _ columns: [String],
        isAdditionalFontPackUnlocked: Bool,
        in layout: PageLayout
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: pdfFont(
                size: layout.fontSize,
                in: layout,
                isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked
            ),
            .foregroundColor: UIColor.black,
            .kern: layout.settings.characterSpacing
        ]
        let lineCount = layout.settings.linesPerPage
        let characterCount = layout.settings.charactersPerLine
        let cellHeight = layout.characterAdvance

        for displayIndex in (0..<lineCount).reversed() {
            let sourceColumn = columns.indices.contains(displayIndex) ? columns[displayIndex] : ""
            let cells = VerticalTextTypesetter.cells(
                from: sourceColumn,
                alphanumericOrientation: layout.settings.alphanumericOrientation
            )
            let rowAdvance = VerticalTextTypesetter.adjustedCharacterAdvance(
                cellCount: cells.count,
                characterCount: characterCount,
                bodyHeight: layout.bodyFrame.height,
                rowHeight: layout.characterAdvance
            )
            let x = layout.bodyFrame.maxX - CGFloat(displayIndex + 1) * layout.lineAdvance

            for (rowIndex, characters) in cells.enumerated() {
                for (index, character) in characters.enumerated() {
                    let glyph = VerticalTextTypesetter.glyph(
                        for: character,
                        alphanumericOrientation: layout.settings.alphanumericOrientation
                    )
                    let offset = VerticalTextTypesetter.glyphOffset(
                        glyph: glyph,
                        character: character,
                        characters: characters,
                        index: index,
                        columnWidth: layout.lineAdvance,
                        rowHeight: cellHeight
                    )
                    let glyphAttributes = pdfAttributes(
                        for: glyph,
                        baseAttributes: attributes,
                        in: layout,
                        isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked
                    )
                    let cellOrigin = CGPoint(
                        x: x,
                        y: layout.bodyFrame.minY + CGFloat(rowIndex) * rowAdvance
                    )

                    if drawManualVerticalSymbolIfNeeded(
                        character,
                        cellOrigin: cellOrigin,
                        offset: offset,
                        cellHeight: cellHeight,
                        in: layout
                    ) {
                        continue
                    }

                    let attributedText = NSAttributedString(string: glyph.text, attributes: glyphAttributes)
                    let glyphSize = (glyph.text as NSString).size(withAttributes: glyphAttributes)
                    let drawPoint = CGPoint(
                        x: cellOrigin.x + (layout.lineAdvance - glyphSize.width) / 2 + offset.width,
                        y: cellOrigin.y + (cellHeight - glyphSize.height) / 2 + offset.height
                    )

                    if glyph.rotationDegrees == 0 {
                        if VerticalTextTypesetter.isAlphanumericRun(glyph.text) {
                            drawCenteredUprightGlyph(
                                glyph.text,
                                attributes: glyphAttributes,
                                glyphSize: glyphSize,
                                cellOrigin: cellOrigin,
                                offset: offset,
                                cellHeight: cellHeight,
                                in: layout
                            )
                        } else {
                            attributedText.draw(at: drawPoint)
                        }
                    } else if let context = UIGraphicsGetCurrentContext() {
                        context.saveGState()
                        context.translateBy(
                            x: cellOrigin.x + layout.lineAdvance / 2 + offset.width,
                            y: cellOrigin.y + cellHeight / 2 + offset.height
                        )
                        context.rotate(by: glyph.rotationDegrees * .pi / 180)
                        attributedText.draw(at: CGPoint(x: -glyphSize.width / 2, y: -glyphSize.height / 2))
                        context.restoreGState()
                    } else {
                        attributedText.draw(at: drawPoint)
                    }
                }
            }
        }
    }

    private func drawManualVerticalSymbolIfNeeded(
        _ character: String,
        cellOrigin: CGPoint,
        offset: CGSize,
        cellHeight: CGFloat,
        in layout: PageLayout
    ) -> Bool {
        guard VerticalTextTypesetter.isDashConnector(character),
              let context = UIGraphicsGetCurrentContext() else {
            return false
        }

        let centerX = cellOrigin.x + layout.lineAdvance / 2 + offset.width
        let overlap = cellHeight * 0.08
        let startY = max(layout.bodyFrame.minY, cellOrigin.y - overlap)
        let endY = min(layout.bodyFrame.maxY, cellOrigin.y + cellHeight + overlap)
        let lineWidth = switch character {
        case "━":
            max(layout.fontSize * 0.13, 0.7)
        default:
            max(layout.fontSize * 0.08, 0.45)
        }

        context.saveGState()
        context.setStrokeColor(UIColor.black.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.butt)
        context.move(to: CGPoint(x: centerX, y: startY))
        context.addLine(to: CGPoint(x: centerX, y: endY))
        context.strokePath()
        context.restoreGState()
        return true
    }

    private func drawCenteredUprightGlyph(
        _ text: String,
        attributes: [NSAttributedString.Key: Any],
        glyphSize: CGSize,
        cellOrigin: CGPoint,
        offset: CGSize,
        cellHeight: CGFloat,
        in layout: PageLayout
    ) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        var centeredAttributes = attributes
        centeredAttributes[.paragraphStyle] = paragraphStyle
        centeredAttributes.removeValue(forKey: .verticalGlyphForm)

        let rect = CGRect(
            x: cellOrigin.x + offset.width,
            y: cellOrigin.y + (cellHeight - glyphSize.height) / 2 + offset.height,
            width: layout.lineAdvance,
            height: max(glyphSize.height * 1.15, 1)
        )
        (text as NSString).draw(in: rect, withAttributes: centeredAttributes)
    }

    private func adjustedCharacterAdvance(
        cellCount: Int,
        characterCount: Int,
        bodyHeight: CGFloat,
        rowHeight: CGFloat
    ) -> CGFloat {
        guard cellCount > 1 else { return rowHeight }
        guard cellCount > characterCount || cellCount >= characterCount - 2 else {
            return rowHeight
        }

        return max((bodyHeight - rowHeight) / CGFloat(cellCount - 1), 1)
    }

    private func drawChapterTitle(
        _ title: String,
        isAdditionalFontPackUnlocked: Bool,
        in layout: PageLayout
    ) {
        let font = pdfFont(
            size: max(layout.fontSize * 0.8, 6),
            in: layout,
            isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        let x = layout.isOddPage ? layout.bodyFrame.minX : layout.bodyFrame.maxX - size.width
        let y = max(layout.marginTop * 0.5, 4)
        (title as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
    }

    private func drawPageNumber(_ pageNumber: Int, subscriptionStatus: SubscriptionStatus, in layout: PageLayout) {
        let position = layout.effectivePageNumberPosition(isPageNumberFontUnlocked: subscriptionStatus == .paid)
        guard layout.settings.isPageNumberEnabled, position != .hidden else { return }

        let text = "\(pageNumber)" as NSString
        let font = AppFontCatalog.pageNumberUIFont(
            pageNumberFontId: layout.settings.pageNumberFontId,
            bodyFontId: layout.settings.selectedFontId,
            size: layout.effectivePageNumberFontSize(isPageNumberFontUnlocked: subscriptionStatus == .paid),
            isPageNumberFontUnlocked: subscriptionStatus == .paid
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
        ]
        let size = text.size(withAttributes: attributes)
        let origin = layout.pageNumberOrigin(textSize: size, isPageNumberFontUnlocked: subscriptionStatus == .paid)
        text.draw(at: origin, withAttributes: attributes)
    }

    private func drawHorizontalColophon(
        _ colophon: ColophonSettings,
        subscriptionStatus: SubscriptionStatus,
        isAdditionalFontPackUnlocked: Bool,
        in layout: PageLayout
    ) {
        let entries = ManuscriptPaginator.colophonEntries(from: colophon)
        let font = pdfFont(
            size: layout.fontSize,
            in: layout,
            isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked
        )
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
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
                height += colophon.showsQRCode
                    ? qrSize + (colophon.showsWebsiteURL ? 4 + lineHeight : 0)
                    : lineHeight
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

        guard colophon.showsQRCode, let image = qrCodeImage(for: colophon.websiteURL) else {
            (entry.value as NSString).draw(
                in: CGRect(x: valueX, y: y, width: layout.bodyFrame.maxX - valueX, height: lineHeight),
                withAttributes: valueAttributes
            )
            return 1
        }

        let qrSize = horizontalColophonQRCodeSize(in: layout)
        let urlWidth = (entry.value as NSString).size(withAttributes: valueAttributes).width
        let availableValueWidth = max(layout.bodyFrame.maxX - valueX, 1)
        let blockWidth = max(qrSize, urlWidth)
        let blockX = valueX + max((availableValueWidth - blockWidth) / 2, 0)
        let qrX = blockX + max((blockWidth - qrSize) / 2, 0)
        let urlX = blockX + max((blockWidth - urlWidth) / 2, 0)
        image.draw(in: CGRect(x: qrX, y: y, width: qrSize, height: qrSize))

        let valueY = y + qrSize + 4
        if colophon.showsWebsiteURL, valueY < layout.bodyFrame.maxY - lineHeight {
            (entry.value as NSString).draw(
                in: CGRect(x: urlX, y: valueY, width: max(urlWidth, 1), height: lineHeight),
                withAttributes: valueAttributes
            )
        }

        let occupiedHeight = qrSize + (colophon.showsWebsiteURL ? 4 + lineHeight : 0)
        return max(Int(ceil(occupiedHeight / lineHeight)), 1)
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

        let authorName = colophon.showsAuthorName
            ? colophon.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
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
        let hasAuthorName = colophon.showsAuthorName
            && !colophon.authorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        guard colophon.showsQRCode else { return }
        guard let image = qrCodeImage(for: colophon.websiteURL) else { return }

        let metrics = verticalHorizontalColophonMetrics(in: layout)
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: pdfFont(
                size: layout.fontSize,
                in: layout,
                isAdditionalFontPackUnlocked: true
            )
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

        let font = pdfFont(
            size: layout.fontSize,
            in: layout,
            isAdditionalFontPackUnlocked: true
        )
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
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

    private func drawPoweredByHonkumi(
        on page: PreviewPage,
        pageNumber: Int,
        subscriptionStatus: SubscriptionStatus,
        in layout: PageLayout
    ) {
        let text = "Powered by Honkumi" as NSString
        let font = pdfFont(
            size: PageLayout.poweredByHonkumiFontSize,
            in: layout,
            isAdditionalFontPackUnlocked: subscriptionStatus == .paid
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
        ]
        let size = text.size(withAttributes: attributes)
        let pageNumberSize = pageNumberTextSizeIfVisible(
            pageNumber,
            subscriptionStatus: subscriptionStatus,
            in: layout
        )
        let origin = layout.poweredByHonkumiOrigin(
            textSize: size,
            pageNumberTextSize: pageNumberSize
        )

        text.draw(at: origin, withAttributes: attributes)
    }

    private func pageNumberTextSizeIfVisible(
        _ pageNumber: Int,
        subscriptionStatus: SubscriptionStatus,
        in layout: PageLayout
    ) -> CGSize? {
        let position = layout.effectivePageNumberPosition(isPageNumberFontUnlocked: subscriptionStatus == .paid)
        guard layout.settings.isPageNumberEnabled, position != .hidden else { return nil }

        let font = AppFontCatalog.pageNumberUIFont(
            pageNumberFontId: layout.settings.pageNumberFontId,
            bodyFontId: layout.settings.selectedFontId,
            size: layout.effectivePageNumberFontSize(isPageNumberFontUnlocked: subscriptionStatus == .paid),
            isPageNumberFontUnlocked: subscriptionStatus == .paid
        )
        return ("\(pageNumber)" as NSString).size(withAttributes: [.font: font])
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

    private func pdfAttributes(
        for glyph: VerticalGlyphLayout,
        baseAttributes: [NSAttributedString.Key: Any],
        in layout: PageLayout,
        isAdditionalFontPackUnlocked: Bool
    ) -> [NSAttributedString.Key: Any] {
        var attributes = baseAttributes
        if glyph.rotationDegrees != 0
            || glyph.text.count > 1
            || VerticalTextTypesetter.isAlphanumericRun(glyph.text) {
            attributes.removeValue(forKey: .verticalGlyphForm)
        }

        if glyph.disablesCharacterSpacing {
            attributes.removeValue(forKey: .kern)
        }

        if glyph.fontScale != 1 {
            attributes[.font] = pdfFont(
                size: layout.fontSize * glyph.fontScale,
                in: layout,
                isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked
            )
        }
        return attributes
    }

    private func pdfFont(
        size: CGFloat,
        in layout: PageLayout,
        isAdditionalFontPackUnlocked: Bool
    ) -> UIFont {
        AppFontCatalog.uiFont(
            selectedFontId: layout.settings.selectedFontId,
            size: size,
            isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked
        )
    }
}

nonisolated struct CoverPDFExportService {
    func exportCover() async throws -> URL {
        throw PDFExportError.notImplemented
    }
}

nonisolated struct PDFMergeService {
    func merge(_ urls: [URL]) async throws -> URL {
        _ = urls
        throw PDFExportError.notImplemented
    }
}

nonisolated enum PDFExportError: LocalizedError {
    case notImplemented

    var errorDescription: String? {
        "PDF export is not implemented yet."
    }
}
