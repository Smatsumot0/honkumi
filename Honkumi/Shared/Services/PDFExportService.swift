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

    func exportPreviewPDF(
        document: ManuscriptDocument,
        subscriptionStatus: SubscriptionStatus = .free,
        previewKind: PreviewPDFKind = .normal,
        generationID: UUID = UUID()
    ) async throws -> URL {
        let exporter = bodyExporter
        return try await Task.detached(priority: .userInitiated) {
            try exporter.exportPreviewPDF(
                document: document,
                subscriptionStatus: subscriptionStatus,
                previewKind: previewKind,
                generationID: generationID
            )
        }.value
    }
}

nonisolated private enum FooterPlacement {
    static let poweredByBodyBottomMultiplier: CGFloat = 0.82
    static let poweredByColophonBottomMultiplier: CGFloat = 0.82
    static let bottomInset: CGFloat = 2
}

nonisolated private enum SpreadPreviewBlankPageStyle {
    static var fillColor: UIColor {
        UIColor(red: 0.055, green: 0.057, blue: 0.065, alpha: 1)
    }
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

nonisolated private struct HorizontalColophonTextLayout {
    let fontSize: CGFloat
    let lineHeight: CGFloat
    let lines: [String]
    let frameWidth: CGFloat
    let textWidth: CGFloat
    let kern: CGFloat

    var lineCount: Int {
        max(lines.count, 1)
    }

    var height: CGFloat {
        lineHeight * CGFloat(lineCount)
    }
}

nonisolated private struct QRCodeMatrix {
    let width: Int
    let height: Int
    let modules: [Bool]

    func isDark(x: Int, y: Int) -> Bool {
        guard x >= 0, x < width, y >= 0, y < height else { return false }
        return modules[y * width + x]
    }
}

nonisolated private enum GlyphVisualCenteringCache {
    private static let cache = NSCache<NSString, NSValue>()

    static func offset(
        text: String,
        font: UIFont,
        rotationDegrees: Double,
        attributes: [NSAttributedString.Key: Any]
    ) -> CGSize {
        let cacheKey = "\(font.fontName)-\(String(format: "%.3f", Double(font.pointSize)))-\(rotationDegrees)-\(text)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached.cgSizeValue
        }

        let offset = measuredOffset(
            text: text,
            font: font,
            rotationDegrees: rotationDegrees,
            attributes: attributes
        )
        cache.setObject(NSValue(cgSize: offset), forKey: cacheKey)
        return offset
    }

    private static func measuredOffset(
        text: String,
        font: UIFont,
        rotationDegrees: Double,
        attributes: [NSAttributedString.Key: Any]
    ) -> CGSize {
        let scale: CGFloat = 3
        let canvasSide = max(font.pointSize * 5, 64)
        let pixelSide = max(Int((canvasSide * scale).rounded(.up)), 1)
        let bytesPerPixel = 4
        let bytesPerRow = pixelSide * bytesPerPixel
        var bitmap = [UInt8](repeating: 0, count: bytesPerRow * pixelSide)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: &bitmap,
            width: pixelSide,
            height: pixelSide,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return .zero
        }

        var drawAttributes = attributes
        drawAttributes[.font] = font
        drawAttributes[.foregroundColor] = UIColor.black
        let attributedText = NSAttributedString(string: text, attributes: drawAttributes)
        let glyphSize = (text as NSString).size(withAttributes: drawAttributes)

        context.scaleBy(x: scale, y: scale)
        UIGraphicsPushContext(context)
        context.saveGState()
        context.translateBy(x: canvasSide / 2, y: canvasSide / 2)
        context.rotate(by: rotationDegrees * .pi / 180)
        attributedText.draw(at: CGPoint(x: -glyphSize.width / 2, y: -glyphSize.height / 2))
        context.restoreGState()
        UIGraphicsPopContext()

        var minX = pixelSide
        var maxX = -1
        for y in 0..<pixelSide {
            let rowStart = y * bytesPerRow
            for x in 0..<pixelSide {
                let alpha = bitmap[rowStart + x * bytesPerPixel + 3]
                guard alpha > 12 else { continue }
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
        }

        guard maxX >= minX else { return .zero }
        let visualCenterX = CGFloat(minX + maxX + 1) / 2
        let canvasCenterX = CGFloat(pixelSide) / 2
        let xOffset = (canvasCenterX - visualCenterX) / scale
        return CGSize(width: xOffset, height: 0)
    }
}

nonisolated private enum RenderedPDFPageKind {
    case content(PreviewPage, displayedPageNumber: Int?)
    case blank
}

nonisolated private struct RenderedPDFPage {
    let kind: RenderedPDFPageKind
    let layoutPageNumber: Int
    let spreadPageNumber: Int
}

nonisolated struct BodyPDFExportService {
    func export(document: ManuscriptDocument, subscriptionStatus: SubscriptionStatus = .free) throws -> URL {
        try export(
            document: document,
            subscriptionStatus: subscriptionStatus,
            to: Self.temporaryExportURL(for: document)
        )
    }

    func exportPreviewPDF(
        document: ManuscriptDocument,
        subscriptionStatus: SubscriptionStatus = .free,
        previewKind: PreviewPDFKind = .normal,
        generationID: UUID
    ) throws -> URL {
        try FileManager.default.createDirectory(
            at: Self.previewDirectoryURL,
            withIntermediateDirectories: true
        )
        return try export(
            document: document,
            subscriptionStatus: subscriptionStatus,
            previewKind: previewKind,
            to: Self.previewURL(for: document, generationID: generationID)
        )
    }

    private func export(
        document: ManuscriptDocument,
        subscriptionStatus: SubscriptionStatus,
        previewKind: PreviewPDFKind = .normal,
        to outputURL: URL
    ) throws -> URL {
        let paginationResult = ManuscriptRenderPipeline.paginationResult(
            for: document,
            subscriptionStatus: subscriptionStatus
        )
        let settings = paginationResult.document.settings.validated
        let pages = paginationResult.pages
        let firstLayout = LayoutCalculator.layout(for: settings, pageNumber: 1)
        let firstGeometry = PDFPrintProduction.pageGeometry(for: firstLayout)
        let pdfTitle = document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Honkumi"
            : document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let rendererFormat = UIGraphicsPDFRendererFormat()
        rendererFormat.documentInfo = PDFPrintProduction.pdfX4Profile.documentInfo(title: pdfTitle)
        try? FileManager.default.removeItem(at: outputURL)

        if previewKind == .spread {
            try writeSpreadPreviewPDF(
                to: outputURL,
                pages: pages,
                settings: settings,
                subscriptionStatus: subscriptionStatus,
                pdfTitle: pdfTitle,
                documentID: document.id,
                rendererFormat: rendererFormat,
                firstGeometry: firstGeometry
            )
            try PDFPrintProduction.normalizePDFVersionHeader(at: outputURL)
            return outputURL
        }

        let renderer = UIGraphicsPDFRenderer(bounds: firstGeometry.mediaBox, format: rendererFormat)

        try renderer.writePDF(to: outputURL) { context in
            if let metadata = PDFPrintProduction.pdfX4Profile.xmpMetadataData(
                title: pdfTitle,
                documentID: document.id
            ) {
                context.cgContext.addDocumentMetadata(metadata as CFData)
            }

            let renderedPages = renderedPages(
                from: pages,
                settings: settings,
                previewKind: previewKind
            )
            let lastContentPageIndex = renderedPages.lastIndex { renderedPage in
                if case .content = renderedPage.kind { return true }
                return false
            }
            for (index, renderedPage) in renderedPages.enumerated() {
                let layout = LayoutCalculator.layout(for: settings, pageNumber: renderedPage.layoutPageNumber)
                let geometry = PDFPrintProduction.pageGeometry(for: layout)

                context.beginPage(withBounds: geometry.mediaBox, pageInfo: geometry.pageInfo)
                guard case let .content(page, displayedPageNumber: displayedPageNumber) = renderedPage.kind else {
                    drawSpreadPreviewBlankPage(in: geometry)
                    if settings.showsCropMarks {
                        drawCropMarks(in: geometry)
                    }
                    continue
                }

                context.cgContext.saveGState()
                context.cgContext.translateBy(x: geometry.trimOffset.width, y: geometry.trimOffset.height)
                draw(
                    page,
                    displayedPageNumber: displayedPageNumber,
                    isLastContentPage: index == lastContentPageIndex,
                    subscriptionStatus: subscriptionStatus,
                    in: layout
                )
                context.cgContext.restoreGState()

                if settings.showsCropMarks {
                    drawCropMarks(in: geometry)
                }
            }
        }

        try PDFPrintProduction.normalizePDFVersionHeader(at: outputURL)
        return outputURL
    }

    private func writeSpreadPreviewPDF(
        to outputURL: URL,
        pages: [PreviewPage],
        settings: EditorSettings,
        subscriptionStatus: SubscriptionStatus,
        pdfTitle: String,
        documentID: UUID,
        rendererFormat: UIGraphicsPDFRendererFormat,
        firstGeometry: PDFPageGeometry
    ) throws {
        let gap = LayoutCalculator.millimetersToPoints(3)
        let spreadBounds = CGRect(
            x: 0,
            y: 0,
            width: firstGeometry.mediaBox.width * 2 + gap,
            height: firstGeometry.mediaBox.height
        )
        let spreadPageInfo = PDFPageGeometry(
            mediaBox: spreadBounds,
            trimBox: spreadBounds,
            bleedBox: spreadBounds,
            cropBox: spreadBounds,
            trimOffset: .zero
        ).pageInfo
        let renderer = UIGraphicsPDFRenderer(bounds: spreadBounds, format: rendererFormat)

        try renderer.writePDF(to: outputURL) { context in
            if let metadata = PDFPrintProduction.pdfX4Profile.xmpMetadataData(
                title: pdfTitle,
                documentID: documentID
            ) {
                context.cgContext.addDocumentMetadata(metadata as CFData)
            }

            let renderedPages = spreadRenderedPages(from: pages, settings: settings)
            let lastContentPageIndex = renderedPages.lastIndex { renderedPage in
                if case .content = renderedPage.kind { return true }
                return false
            }

            for pairStart in stride(from: 0, to: renderedPages.count, by: 2) {
                let leftPage = renderedPages[pairStart]
                let rightPage = renderedPages.indices.contains(pairStart + 1)
                    ? renderedPages[pairStart + 1]
                    : blankRenderedPage(spreadPageNumber: leftPage.spreadPageNumber - 1)

                context.beginPage(withBounds: spreadBounds, pageInfo: spreadPageInfo)
                guard let cgContext = UIGraphicsGetCurrentContext() else { continue }
                cgContext.saveGState()
                cgContext.setFillColor(SpreadPreviewBlankPageStyle.fillColor.cgColor)
                cgContext.fill(spreadBounds)
                cgContext.restoreGState()

                drawRenderedSpreadPreviewPage(
                    leftPage,
                    flatIndex: pairStart,
                    lastContentPageIndex: lastContentPageIndex,
                    settings: settings,
                    subscriptionStatus: subscriptionStatus,
                    at: CGPoint(x: 0, y: 0)
                )
                drawRenderedSpreadPreviewPage(
                    rightPage,
                    flatIndex: pairStart + 1,
                    lastContentPageIndex: lastContentPageIndex,
                    settings: settings,
                    subscriptionStatus: subscriptionStatus,
                    at: CGPoint(x: firstGeometry.mediaBox.width + gap, y: 0)
                )
            }
        }
    }

    private func drawRenderedSpreadPreviewPage(
        _ renderedPage: RenderedPDFPage,
        flatIndex: Int,
        lastContentPageIndex: Int?,
        settings: EditorSettings,
        subscriptionStatus: SubscriptionStatus,
        at origin: CGPoint
    ) {
        let layout = LayoutCalculator.layout(for: settings, pageNumber: renderedPage.layoutPageNumber)
        let geometry = PDFPrintProduction.pageGeometry(for: layout)
        guard let context = UIGraphicsGetCurrentContext() else { return }

        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)

        guard case let .content(page, displayedPageNumber: displayedPageNumber) = renderedPage.kind else {
            drawSpreadPreviewBlankPage(in: geometry)
            context.restoreGState()
            return
        }

        context.setFillColor(UIColor.white.cgColor)
        context.fill(geometry.mediaBox)
        context.saveGState()
        context.translateBy(x: geometry.trimOffset.width, y: geometry.trimOffset.height)
        draw(
            page,
            displayedPageNumber: displayedPageNumber,
            isLastContentPage: flatIndex == lastContentPageIndex,
            subscriptionStatus: subscriptionStatus,
            in: layout
        )
        context.restoreGState()

        if settings.showsCropMarks {
            drawCropMarks(in: geometry)
        }

        context.restoreGState()
    }

    private func renderedPages(
        from pages: [PreviewPage],
        settings: EditorSettings,
        previewKind: PreviewPDFKind
    ) -> [RenderedPDFPage] {
        switch previewKind {
        case .normal:
            normalRenderedPages(from: pages, settings: settings)
        case .spread:
            spreadRenderedPages(from: pages, settings: settings)
        }
    }

    private func normalRenderedPages(
        from pages: [PreviewPage],
        settings: EditorSettings
    ) -> [RenderedPDFPage] {
        var nextDisplayedPageNumber = settings.pageNumberStart
        return pages.enumerated().map { index, page in
            let displayedPageNumber: Int?
            if case .body = page.kind {
                displayedPageNumber = nextDisplayedPageNumber
                nextDisplayedPageNumber += 1
            } else {
                displayedPageNumber = nil
            }

            return RenderedPDFPage(
                kind: .content(page, displayedPageNumber: displayedPageNumber),
                layoutPageNumber: index + 1,
                spreadPageNumber: index + 1
            )
        }
    }

    private func spreadRenderedPages(
        from pages: [PreviewPage],
        settings: EditorSettings
    ) -> [RenderedPDFPage] {
        let contentPages = spreadContentPages(from: pages, settings: settings)
        let contentBySpreadPageNumber = contentPages.reduce(into: [Int: RenderedPDFPage]()) { result, page in
            result[page.spreadPageNumber] = page
        }
        let leftPageNumbers = Set(contentPages.map { page in
            isOddPageNumber(page.spreadPageNumber)
                ? page.spreadPageNumber
                : page.spreadPageNumber + 1
        })

        return leftPageNumbers.sorted().flatMap { leftPageNumber in
            [
                contentBySpreadPageNumber[leftPageNumber]
                    ?? blankRenderedPage(spreadPageNumber: leftPageNumber),
                contentBySpreadPageNumber[leftPageNumber - 1]
                    ?? blankRenderedPage(spreadPageNumber: leftPageNumber - 1)
            ]
        }
    }

    private func spreadContentPages(
        from pages: [PreviewPage],
        settings: EditorSettings
    ) -> [RenderedPDFPage] {
        let displayedPageNumbers = bodyDisplayedPageNumbers(from: pages, settings: settings)
        var contentPages: [RenderedPDFPage] = []
        var index = 0

        while index < pages.count {
            let page = pages[index]
            if let displayedPageNumber = displayedPageNumbers[index] {
                contentPages.append(RenderedPDFPage(
                    kind: .content(page, displayedPageNumber: displayedPageNumber),
                    layoutPageNumber: displayedPageNumber,
                    spreadPageNumber: displayedPageNumber
                ))
                index += 1
                continue
            }

            let runStart = index
            while index < pages.count, displayedPageNumbers[index] == nil {
                index += 1
            }

            let runEnd = index
            let runCount = runEnd - runStart
            let nextBodyPageNumber = displayedPageNumbers[index...].compactMap { $0 }.first
            let previousBodyPageNumber = displayedPageNumbers[..<runStart].compactMap { $0 }.last
            let logicalStartPageNumber: Int

            if let nextBodyPageNumber {
                logicalStartPageNumber = nextBodyPageNumber - runCount
            } else if let previousBodyPageNumber {
                logicalStartPageNumber = previousBodyPageNumber + 1
            } else {
                logicalStartPageNumber = 1
            }

            for offset in 0..<runCount {
                let page = pages[runStart + offset]
                let logicalPageNumber = logicalStartPageNumber + offset
                contentPages.append(RenderedPDFPage(
                    kind: .content(page, displayedPageNumber: nil),
                    layoutPageNumber: layoutPageNumber(matchingParityOf: logicalPageNumber),
                    spreadPageNumber: logicalPageNumber
                ))
            }
        }

        return contentPages
    }

    private func bodyDisplayedPageNumbers(
        from pages: [PreviewPage],
        settings: EditorSettings
    ) -> [Int?] {
        var nextDisplayedPageNumber = settings.pageNumberStart
        return pages.map { page in
            guard case .body = page.kind else { return nil }
            defer { nextDisplayedPageNumber += 1 }
            return nextDisplayedPageNumber
        }
    }

    private func blankRenderedPage(spreadPageNumber: Int) -> RenderedPDFPage {
        RenderedPDFPage(
            kind: .blank,
            layoutPageNumber: layoutPageNumber(matchingParityOf: spreadPageNumber),
            spreadPageNumber: spreadPageNumber
        )
    }

    private func layoutPageNumber(matchingParityOf pageNumber: Int) -> Int {
        if pageNumber > 0 {
            return pageNumber
        }

        return isOddPageNumber(pageNumber) ? 1 : 2
    }

    private func isOddPageNumber(_ pageNumber: Int) -> Bool {
        pageNumber % 2 != 0
    }

    static func temporaryExportURL(for document: ManuscriptDocument) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(Self.safePDFFileName(for: document.title))
            .appendingPathExtension("pdf")
    }

    static var previewDirectoryURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("HonkumiPreviewPDF", isDirectory: true)
    }

    static func previewURL(for document: ManuscriptDocument, generationID: UUID) -> URL {
        previewDirectoryURL
            .appendingPathComponent("\(Self.safePDFFileName(for: document.title))-\(generationID.uuidString)")
            .appendingPathExtension("pdf")
    }

    static func safePDFFileName(for title: String) -> String {
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
        displayedPageNumber: Int?,
        isLastContentPage: Bool,
        subscriptionStatus: SubscriptionStatus,
        in layout: PageLayout
    ) {
        switch page.kind {
        case .body:
            drawVerticalText(
                page.columns,
                pageKind: page.kind,
                isAdditionalFontPackUnlocked: subscriptionStatus == .paid,
                in: layout
            )
        case .tableOfContents:
            drawTableOfContents(
                page,
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

        drawPageNumber(displayedPageNumber, subscriptionStatus: subscriptionStatus, in: layout)

        if shouldShowPoweredByHonkumi(
            page: page,
            isLastContentPage: isLastContentPage,
            subscriptionStatus: subscriptionStatus
        ) {
            drawPoweredByHonkumi(
                on: page,
                displayedPageNumber: displayedPageNumber,
                subscriptionStatus: subscriptionStatus,
                in: layout
            )
        }
    }

    private func drawCropMarks(in geometry: PDFPageGeometry) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        let trimBox = geometry.trimBox
        let length = LayoutCalculator.millimetersToPoints(PDFPrintProduction.cropMarkLengthMillimeters)
        let gap = LayoutCalculator.millimetersToPoints(PDFPrintProduction.cropMarkGapMillimeters)
        let lineWidth = PDFPrintProduction.cropMarkLineWidthPoints

        context.saveGState()
        context.setStrokeColor(gray: 0, alpha: 1)
        context.setLineWidth(lineWidth)
        context.setLineCap(.butt)

        func addLine(from start: CGPoint, to end: CGPoint) {
            context.move(to: start)
            context.addLine(to: end)
        }

        addLine(
            from: CGPoint(x: trimBox.minX - gap - length, y: trimBox.minY),
            to: CGPoint(x: trimBox.minX - gap, y: trimBox.minY)
        )
        addLine(
            from: CGPoint(x: trimBox.minX, y: trimBox.minY - gap - length),
            to: CGPoint(x: trimBox.minX, y: trimBox.minY - gap)
        )

        addLine(
            from: CGPoint(x: trimBox.maxX + gap, y: trimBox.minY),
            to: CGPoint(x: trimBox.maxX + gap + length, y: trimBox.minY)
        )
        addLine(
            from: CGPoint(x: trimBox.maxX, y: trimBox.minY - gap - length),
            to: CGPoint(x: trimBox.maxX, y: trimBox.minY - gap)
        )

        addLine(
            from: CGPoint(x: trimBox.minX - gap - length, y: trimBox.maxY),
            to: CGPoint(x: trimBox.minX - gap, y: trimBox.maxY)
        )
        addLine(
            from: CGPoint(x: trimBox.minX, y: trimBox.maxY + gap),
            to: CGPoint(x: trimBox.minX, y: trimBox.maxY + gap + length)
        )

        addLine(
            from: CGPoint(x: trimBox.maxX + gap, y: trimBox.maxY),
            to: CGPoint(x: trimBox.maxX + gap + length, y: trimBox.maxY)
        )
        addLine(
            from: CGPoint(x: trimBox.maxX, y: trimBox.maxY + gap),
            to: CGPoint(x: trimBox.maxX, y: trimBox.maxY + gap + length)
        )

        context.strokePath()
        context.restoreGState()
    }

    private func drawSpreadPreviewBlankPage(in geometry: PDFPageGeometry) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        context.saveGState()
        context.setFillColor(SpreadPreviewBlankPageStyle.fillColor.cgColor)
        context.fill(geometry.mediaBox)
        context.restoreGState()
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

    private func drawTableOfContents(
        _ page: PreviewPage,
        isAdditionalFontPackUnlocked: Bool,
        in layout: PageLayout
    ) {
        guard !page.tableOfContentsEntries.isEmpty else {
            drawVerticalText(
                page.columns,
                pageKind: .body,
                isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked,
                in: layout
            )
            return
        }

        let baseFontSize = pdfVerticalBodyFontSize(pageKind: .body, in: layout)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: pdfFont(
                size: baseFontSize,
                in: layout,
                isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked
            ),
            .foregroundColor: UIColor.black,
            .kern: layout.settings.characterSpacing
        ]
        let entryStartIndex = max(page.columns.count - page.tableOfContentsEntries.count, 0)

        for displayIndex in 0..<entryStartIndex {
            let sourceColumn = page.columns.indices.contains(displayIndex) ? page.columns[displayIndex] : ""
            drawTableOfContentsStaticColumn(
                sourceColumn,
                displayIndex: displayIndex,
                baseAttributes: attributes,
                isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked,
                in: layout
            )
        }

        for (entryOffset, entry) in page.tableOfContentsEntries.enumerated() {
            drawTableOfContentsEntry(
                entry,
                displayIndex: entryStartIndex + entryOffset,
                baseAttributes: attributes,
                isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked,
                in: layout
            )
        }
    }

    private func drawTableOfContentsStaticColumn(
        _ text: String,
        displayIndex: Int,
        baseAttributes: [NSAttributedString.Key: Any],
        isAdditionalFontPackUnlocked: Bool,
        in layout: PageLayout
    ) {
        guard displayIndex < layout.settings.linesPerPage, !text.isEmpty else { return }

        let rawCells = VerticalTextTypesetter.cells(
            from: text,
            alphanumericOrientation: layout.settings.alphanumericOrientation
        )
        let startRow = text == "目次" && layout.settings.chapterTitleStyle == .centered
            ? max((layout.settings.charactersPerLine - rawCells.count) / 2, 0)
            : 0
        let cells = Array(repeating: [String](), count: startRow) + rawCells
        let x = layout.bodyFrame.maxX - CGFloat(displayIndex + 1) * layout.lineAdvance

        for (rowIndex, characters) in cells.enumerated()
            where rowIndex < layout.settings.charactersPerLine {
            drawVerticalCell(
                characters,
                rowIndex: rowIndex,
                cells: cells,
                x: x,
                rowAdvance: layout.characterAdvance,
                cellHeight: layout.characterAdvance,
                pageKind: .body,
                baseAttributes: baseAttributes,
                isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked,
                in: layout
            )
        }
    }

    private func drawTableOfContentsEntry(
        _ entry: TableOfContentsEntry,
        displayIndex: Int,
        baseAttributes: [NSAttributedString.Key: Any],
        isAdditionalFontPackUnlocked: Bool,
        in layout: PageLayout
    ) {
        guard displayIndex < layout.settings.linesPerPage else { return }

        let characterCount = layout.settings.charactersPerLine
        guard characterCount > 0 else { return }

        let titleCells = VerticalTextTypesetter.cells(
            from: entry.title,
            alphanumericOrientation: layout.settings.alphanumericOrientation
        )
        let pageNumberCells = VerticalTextTypesetter.cells(
            from: VerticalTextTypesetter.horizontalRun(String(entry.pageNumber)),
            alphanumericOrientation: layout.settings.alphanumericOrientation
        )
        let x = layout.bodyFrame.maxX - CGFloat(displayIndex + 1) * layout.lineAdvance
        let gapCellCount = 2
        let pageStartRow = max(characterCount - pageNumberCells.count, 0)
        let maxTitleCellCount = max(pageStartRow - gapCellCount * 2, 0)
        let visibleTitleCells = Array(titleCells.prefix(maxTitleCellCount))
        let leaderStartRow = min(visibleTitleCells.count + gapCellCount, characterCount)
        let leaderEndRow = max(leaderStartRow, pageStartRow - gapCellCount)
        let leader = "︙"
        var cells = Array(repeating: [String](), count: characterCount)
        let pageNumberRows = Set(pageStartRow..<(pageStartRow + pageNumberCells.count))

        for (index, cell) in visibleTitleCells.enumerated() where cells.indices.contains(index) {
            cells[index] = cell
        }

        if leaderStartRow < leaderEndRow {
            for rowIndex in leaderStartRow..<leaderEndRow where cells.indices.contains(rowIndex) {
                cells[rowIndex] = [leader]
            }
        }

        for (offset, cell) in pageNumberCells.enumerated() {
            let rowIndex = pageStartRow + offset
            if cells.indices.contains(rowIndex) {
                cells[rowIndex] = cell
            }
        }

        for (rowIndex, characters) in cells.enumerated() {
            drawVerticalCell(
                characters,
                rowIndex: rowIndex,
                cells: cells,
                x: x,
                rowAdvance: layout.characterAdvance,
                cellHeight: layout.characterAdvance,
                pageKind: .body,
                usesTableOfContentsPageNumberFont: pageNumberRows.contains(rowIndex),
                baseAttributes: baseAttributes,
                isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked,
                in: layout
            )
        }
    }

    private func drawVerticalText(
        _ columns: [String],
        pageKind: PreviewPageKind,
        isAdditionalFontPackUnlocked: Bool,
        in layout: PageLayout
    ) {
        let baseFontSize = pdfVerticalBodyFontSize(pageKind: pageKind, in: layout)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: pdfFont(
                size: baseFontSize,
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
                drawVerticalCell(
                    characters,
                    rowIndex: rowIndex,
                    cells: cells,
                    x: x,
                    rowAdvance: rowAdvance,
                    cellHeight: cellHeight,
                    pageKind: pageKind,
                    baseAttributes: attributes,
                    isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked,
                    in: layout
                )
            }
        }
    }

    private func drawVerticalCell(
        _ characters: [String],
        rowIndex: Int,
        cells: [[String]],
        x: CGFloat,
        rowAdvance: CGFloat,
        cellHeight: CGFloat,
        pageKind: PreviewPageKind,
        usesTableOfContentsPageNumberFont: Bool = false,
        baseAttributes: [NSAttributedString.Key: Any],
        isAdditionalFontPackUnlocked: Bool,
        in layout: PageLayout
    ) {
        guard !characters.isEmpty else { return }

        for (index, character) in characters.enumerated() {
            let glyph = VerticalTextTypesetter.glyph(
                for: character,
                alphanumericOrientation: layout.settings.alphanumericOrientation
            )
            let glyphOffset = VerticalTextTypesetter.glyphOffset(
                glyph: glyph,
                character: character,
                characters: characters,
                index: index,
                columnWidth: layout.lineAdvance,
                rowHeight: cellHeight
            )
            let positionOffset = AppFontCatalog.pdfVerticalGlyphPositionOffset(
                selectedFontId: layout.settings.selectedFontId,
                sourceCharacter: character,
                appliesBodyGlyphAdjustment: pageKind == .body
            )
            let offset = CGSize(
                width: glyphOffset.width + positionOffset.width,
                height: glyphOffset.height + positionOffset.height
            )
            let glyphAttributes = pdfAttributes(
                for: glyph,
                sourceCharacter: character,
                pageKind: pageKind,
                usesTableOfContentsPageNumberFont: usesTableOfContentsPageNumberFont,
                baseAttributes: baseAttributes,
                in: layout,
                isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked
            )
            let cellOrigin = CGPoint(
                x: x,
                y: layout.bodyFrame.minY + CGFloat(rowIndex) * rowAdvance
            )

            let previousCellCharacter = cells.indices.contains(rowIndex - 1) ? cells[rowIndex - 1].first : nil
            let nextCellCharacter = cells.indices.contains(rowIndex + 1) ? cells[rowIndex + 1].first : nil
            if drawManualVerticalSymbolIfNeeded(
                character,
                previousCharacter: previousCellCharacter,
                nextCharacter: nextCellCharacter,
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
                let visualOffset = visualCenteringOffsetIfNeeded(
                    character: character,
                    glyph: glyph,
                    attributes: glyphAttributes
                )
                context.saveGState()
                context.translateBy(
                    x: cellOrigin.x + layout.lineAdvance / 2 + offset.width + visualOffset.width,
                    y: cellOrigin.y + cellHeight / 2 + offset.height + visualOffset.height
                )
                context.rotate(by: glyph.rotationDegrees * .pi / 180)
                attributedText.draw(at: CGPoint(x: -glyphSize.width / 2, y: -glyphSize.height / 2))
                context.restoreGState()
            } else {
                attributedText.draw(at: drawPoint)
            }
        }
    }

    private func drawManualVerticalSymbolIfNeeded(
        _ character: String,
        previousCharacter: String?,
        nextCharacter: String?,
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
        let connectorOverlap = cellHeight * 0.08
        let characterGap = cellHeight * 0.10
        let startInset = previousCharacter.map(VerticalTextTypesetter.isDashConnector) == true
            ? -connectorOverlap
            : characterGap
        let endInset = nextCharacter.map(VerticalTextTypesetter.isDashConnector) == true
            ? -connectorOverlap
            : characterGap
        let startY = max(layout.bodyFrame.minY, cellOrigin.y + startInset)
        let endY = min(layout.bodyFrame.maxY, cellOrigin.y + cellHeight - endInset)
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

    private func drawPageNumber(_ pageNumber: Int?, subscriptionStatus: SubscriptionStatus, in layout: PageLayout) {
        guard let pageNumber else { return }
        let position = layout.effectivePageNumberPosition(isPageNumberFontUnlocked: subscriptionStatus == .paid)
        guard layout.settings.isPageNumberEnabled, position != .hidden else { return }

        let text = "\(pageNumber)" as NSString
        let font = AppFontCatalog.pdfPageNumberUIFont(
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

        var cursorY = startY
        for (entryIndex, entry) in entries.enumerated() {
            if entryIndex > 0 {
                cursorY += 8
            }
            if entry.addsPrecedingSpace {
                cursorY += lineHeight
            }

            let entryHeight = horizontalColophonEntryHeight(
                entry,
                colophon: colophon,
                subscriptionStatus: subscriptionStatus,
                lineHeight: lineHeight,
                valueAttributes: valueAttributes,
                in: layout
            )
            guard cursorY < layout.bodyFrame.maxY - min(lineHeight, entryHeight) else { break }

            if entry.id == "hp" {
                drawHorizontalColophonHPEntry(
                    entry,
                    colophon: colophon,
                    labelWidth: labelWidth,
                    valueX: valueX,
                    y: cursorY,
                    lineHeight: lineHeight,
                    labelAttributes: labelAttributes,
                    valueAttributes: valueAttributes,
                    isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked,
                    in: layout
                )
            } else if entry.id == "creator",
                      subscriptionStatus == .paid,
                      colophon.hasCreatorImage,
                      drawHorizontalCircleLogoCreator(
                        colophon,
                        y: cursorY,
                        lineHeight: lineHeight,
                        valueAttributes: valueAttributes,
                        in: layout
                      ) {
            } else if entry.label.isEmpty {
                let textAttributes = entry.centersInHorizontalLayout
                    ? centeredAttributes(from: valueAttributes)
                    : valueAttributes
                (entry.value as NSString).draw(
                    in: CGRect(x: layout.bodyFrame.minX, y: cursorY, width: layout.bodyFrame.width, height: lineHeight),
                    withAttributes: textAttributes
                )
            } else {
                (entry.label as NSString).draw(
                    in: CGRect(x: layout.bodyFrame.minX, y: cursorY, width: labelWidth, height: lineHeight),
                    withAttributes: labelAttributes
                )
                if shouldFitHorizontalColophonValue(entry) {
                    drawFittedHorizontalColophonValue(
                        entry.value,
                        x: valueX,
                        y: cursorY,
                        maxWidth: layout.bodyFrame.maxX - valueX,
                        baseLineHeight: lineHeight,
                        baseAttributes: valueAttributes,
                        isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked,
                        in: layout
                    )
                } else {
                    (entry.value as NSString).draw(
                        in: CGRect(x: valueX, y: cursorY, width: layout.bodyFrame.maxX - valueX, height: lineHeight),
                        withAttributes: valueAttributes
                    )
                }
            }
            cursorY += entryHeight
            if entry.addsFollowingSpace {
                cursorY += lineHeight
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

        var height: CGFloat = CGFloat(max(entries.count - 1, 0)) * 8
        let font = pdfFont(
            size: layout.fontSize,
            in: layout,
            isAdditionalFontPackUnlocked: subscriptionStatus == .paid
        )
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
        ]

        for entry in entries {
            if entry.addsPrecedingSpace {
                height += lineHeight
            }

            height += horizontalColophonEntryHeight(
                entry,
                colophon: colophon,
                subscriptionStatus: subscriptionStatus,
                lineHeight: lineHeight,
                valueAttributes: valueAttributes,
                in: layout
            )

            if entry.addsFollowingSpace {
                height += lineHeight
            }
        }

        return height
    }

    private func horizontalColophonEntryHeight(
        _ entry: ColophonEntry,
        colophon: ColophonSettings,
        subscriptionStatus: SubscriptionStatus,
        lineHeight: CGFloat,
        valueAttributes: [NSAttributedString.Key: Any],
        in layout: PageLayout
    ) -> CGFloat {
        if entry.id == "hp", !colophon.websiteURL.isEmpty {
            let valueWidth = horizontalColophonValueWidth(in: layout)
            if colophon.showsQRCode {
                let textHeight = colophon.showsWebsiteURL
                    ? fittedHorizontalColophonValueLayout(
                        entry.value,
                        maxWidth: valueWidth,
                        baseLineHeight: lineHeight,
                        isAdditionalFontPackUnlocked: subscriptionStatus == .paid,
                        in: layout
                    ).height
                    : 0
                return horizontalColophonQRCodeSize(in: layout)
                    + (colophon.showsWebsiteURL ? 4 + textHeight : 0)
            }

            return max(
                lineHeight,
                fittedHorizontalColophonValueLayout(
                    entry.value,
                    maxWidth: valueWidth,
                    baseLineHeight: lineHeight,
                    isAdditionalFontPackUnlocked: subscriptionStatus == .paid,
                    in: layout
                ).height
            )
        }

        if entry.id == "creator",
           subscriptionStatus == .paid,
           colophon.hasCreatorImage {
            return max(lineHeight, creatorImageBlockHeight(colophon, lineHeight: lineHeight, in: layout))
        }

        if shouldFitHorizontalColophonValue(entry) {
            return max(
                lineHeight,
                fittedHorizontalColophonValueLayout(
                    entry.value,
                    maxWidth: horizontalColophonValueWidth(in: layout),
                    baseLineHeight: lineHeight,
                    isAdditionalFontPackUnlocked: subscriptionStatus == .paid,
                    in: layout
                ).height
            )
        }

        return lineHeight
    }

    @discardableResult
    private func drawHorizontalColophonHPEntry(
        _ entry: ColophonEntry,
        colophon: ColophonSettings,
        labelWidth: CGFloat,
        valueX: CGFloat,
        y: CGFloat,
        lineHeight: CGFloat,
        labelAttributes: [NSAttributedString.Key: Any],
        valueAttributes: [NSAttributedString.Key: Any],
        isAdditionalFontPackUnlocked: Bool,
        in layout: PageLayout
    ) -> CGFloat {
        (entry.label as NSString).draw(
            in: CGRect(x: layout.bodyFrame.minX, y: y, width: labelWidth, height: lineHeight),
            withAttributes: labelAttributes
        )

        guard colophon.showsQRCode, let qrCode = qrCodeMatrix(for: colophon.websiteURL) else {
            return drawFittedHorizontalColophonValue(
                entry.value,
                x: valueX,
                y: y,
                maxWidth: layout.bodyFrame.maxX - valueX,
                baseLineHeight: lineHeight,
                baseAttributes: valueAttributes,
                isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked,
                in: layout
            )
        }

        let qrSize = horizontalColophonQRCodeSize(in: layout)
        let availableValueWidth = max(layout.bodyFrame.maxX - valueX, 1)
        let valueLayout = fittedHorizontalColophonValueLayout(
            entry.value,
            maxWidth: availableValueWidth,
            baseLineHeight: lineHeight,
            isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked,
            in: layout
        )
        let blockWidth = max(qrSize, min(valueLayout.frameWidth, availableValueWidth))
        let blockX = valueX + max((availableValueWidth - blockWidth) / 2, 0)
        let qrX = blockX + max((blockWidth - qrSize) / 2, 0)
        let urlX = blockX + max((blockWidth - valueLayout.frameWidth) / 2, 0)
        drawQRCode(qrCode, in: CGRect(x: qrX, y: y, width: qrSize, height: qrSize))

        let valueY = y + qrSize + 4
        if colophon.showsWebsiteURL, valueY < layout.bodyFrame.maxY - valueLayout.height {
            drawFittedHorizontalColophonValue(
                entry.value,
                x: urlX,
                y: valueY,
                maxWidth: valueLayout.frameWidth,
                baseLineHeight: valueLayout.lineHeight,
                baseAttributes: valueAttributes,
                isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked,
                in: layout,
                precomputedLayout: valueLayout
            )
        }

        return qrSize + (colophon.showsWebsiteURL ? 4 + valueLayout.height : 0)
    }

    private func horizontalColophonValueWidth(in layout: PageLayout) -> CGFloat {
        let labelWidth = min(layout.bodyFrame.width * 0.28, 72)
        let valueX = layout.bodyFrame.minX + labelWidth + 10
        return max(layout.bodyFrame.maxX - valueX, 1)
    }

    private func shouldFitHorizontalColophonValue(_ entry: ColophonEntry) -> Bool {
        if ["hp", "x", "pixiv", "contact"].contains(entry.id) {
            return true
        }

        return isLongInlineColophonText(entry.value)
    }

    private func fittedHorizontalColophonValueLayout(
        _ text: String,
        maxWidth: CGFloat,
        baseLineHeight: CGFloat,
        isAdditionalFontPackUnlocked: Bool,
        in layout: PageLayout
    ) -> HorizontalColophonTextLayout {
        let maxWidth = max(maxWidth, 1)
        let printableText = printableColophonInlineText(text)
        let baseFontSize = max(layout.fontSize, 6)
        let minimumFontSize: CGFloat = 6
        let fontStep: CGFloat = 0.25

        func width(for text: String, fontSize: CGFloat, kern: CGFloat = 0) -> CGFloat {
            let font = pdfFont(
                size: fontSize,
                in: layout,
                isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked
            )
            var attributes: [NSAttributedString.Key: Any] = [.font: font]
            if abs(kern) > 0.001 {
                attributes[.kern] = kern
            }
            return (text as NSString).size(withAttributes: attributes).width
        }

        func lineHeight(for fontSize: CGFloat) -> CGFloat {
            max(fontSize * 1.35, baseLineHeight * 0.72)
        }

        var oneLineFontSize = baseFontSize
        while oneLineFontSize >= minimumFontSize - 0.001 {
            let oneLineWidth = width(for: printableText, fontSize: oneLineFontSize)
            if oneLineWidth <= maxWidth + 0.5 {
                let resolvedLineHeight = oneLineFontSize == baseFontSize
                    ? baseLineHeight
                    : lineHeight(for: oneLineFontSize)
                return HorizontalColophonTextLayout(
                    fontSize: oneLineFontSize,
                    lineHeight: resolvedLineHeight,
                    lines: [printableText],
                    frameWidth: max(oneLineWidth, 1),
                    textWidth: oneLineWidth,
                    kern: 0
                )
            }
            oneLineFontSize -= fontStep
        }

        let wrappedFontSize = minimumFontSize
        let wrappedFont = pdfFont(
            size: wrappedFontSize,
            in: layout,
            isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked
        )
        let segments = preferredColophonBreakSegments(in: printableText)
        let wrappedLines = colophonLines(
            from: segments,
            maxWidth: maxWidth,
            attributes: [.font: wrappedFont]
        )
        let wrappedWidths = wrappedLines.map {
            width(for: $0, fontSize: wrappedFontSize)
        }
        let naturalWrappedWidth = wrappedWidths.max() ?? maxWidth
        let kern = colophonKernToFit(
            lines: wrappedLines,
            fontSize: wrappedFontSize,
            naturalMaxWidth: naturalWrappedWidth,
            maxWidth: maxWidth,
            isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked,
            in: layout
        )
        let fittedWidths = wrappedLines.map {
            width(for: $0, fontSize: wrappedFontSize, kern: kern)
        }
        let wrappedWidth = fittedWidths.max() ?? maxWidth
        return HorizontalColophonTextLayout(
            fontSize: wrappedFontSize,
            lineHeight: lineHeight(for: wrappedFontSize),
            lines: wrappedLines,
            frameWidth: min(max(wrappedWidth, 1), maxWidth),
            textWidth: min(wrappedWidth, maxWidth),
            kern: kern
        )
    }

    private func printableColophonInlineText(_ text: String) -> String {
        let filteredScalars = text.unicodeScalars.filter { scalar in
            if scalar.value == 0xFFFE || scalar.value == 0xFFFF {
                return false
            }
            return !CharacterSet.controlCharacters.contains(scalar)
        }
        return String(String.UnicodeScalarView(filteredScalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isLongInlineColophonText(_ text: String) -> Bool {
        let printableText = printableColophonInlineText(text)
        guard !printableText.isEmpty else { return false }

        if printableText.contains("://") || printableText.contains("@") {
            return true
        }

        let allowedBreakCharacters: Set<Character> = ["/", ".", "-", "@"]
        var currentASCIIRun = 0
        var longestASCIIRun = 0
        var hasBreakCharacter = false

        for character in printableText {
            if allowedBreakCharacters.contains(character) {
                hasBreakCharacter = true
            }
            if character.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) }) {
                currentASCIIRun += 1
                longestASCIIRun = max(longestASCIIRun, currentASCIIRun)
            } else {
                currentASCIIRun = 0
            }
        }

        return longestASCIIRun >= 16 && hasBreakCharacter
    }

    private func colophonKernToFit(
        lines: [String],
        fontSize: CGFloat,
        naturalMaxWidth: CGFloat,
        maxWidth: CGFloat,
        isAdditionalFontPackUnlocked: Bool,
        in layout: PageLayout
    ) -> CGFloat {
        guard naturalMaxWidth > maxWidth + 0.5 else { return 0 }

        let font = pdfFont(
            size: fontSize,
            in: layout,
            isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked
        )
        guard let widestLine = lines.max(by: { lhs, rhs in
            (lhs as NSString).size(withAttributes: [.font: font]).width
                < (rhs as NSString).size(withAttributes: [.font: font]).width
        }) else {
            return 0
        }

        let characterCount = max(widestLine.count - 1, 1)
        let requiredKern = (maxWidth - naturalMaxWidth) / CGFloat(characterCount)
        return min(0, requiredKern)
    }

    private func preferredColophonBreakSegments(in text: String) -> [String] {
        let text = printableColophonInlineText(text)
        guard !text.isEmpty else { return [""] }
        let breakCharacters: Set<Character> = ["/", ".", "-", "@"]
        var segments: [String] = []
        var current = ""

        for character in text {
            current.append(character)
            if breakCharacters.contains(character) {
                segments.append(current)
                current = ""
            }
        }

        if !current.isEmpty {
            segments.append(current)
        }
        return segments.isEmpty ? [text] : segments
    }

    private func colophonLines(
        from segments: [String],
        maxWidth: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) -> [String] {
        var lines: [String] = []
        var current = ""

        for segment in segments {
            let candidate = current + segment
            let candidateWidth = (candidate as NSString).size(withAttributes: attributes).width
            if !current.isEmpty, candidateWidth > maxWidth + 0.5 {
                lines.append(current)
                current = segment
            } else {
                current = candidate
            }
        }

        if !current.isEmpty {
            lines.append(current)
        }

        return lines.isEmpty ? [""] : lines
    }

    @discardableResult
    private func drawFittedHorizontalColophonValue(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        maxWidth: CGFloat,
        baseLineHeight: CGFloat,
        baseAttributes: [NSAttributedString.Key: Any],
        isAdditionalFontPackUnlocked: Bool,
        in layout: PageLayout,
        precomputedLayout: HorizontalColophonTextLayout? = nil
    ) -> CGFloat {
        let textLayout = precomputedLayout ?? fittedHorizontalColophonValueLayout(
            text,
            maxWidth: maxWidth,
            baseLineHeight: baseLineHeight,
            isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked,
            in: layout
        )
        var attributes = baseAttributes
        attributes[.font] = pdfFont(
            size: textLayout.fontSize,
            in: layout,
            isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked
        )
        if abs(textLayout.kern) > 0.001 {
            attributes[.kern] = textLayout.kern
        } else {
            attributes.removeValue(forKey: .kern)
        }

        let originY = textLayout.lineCount == 1
            ? y + max((baseLineHeight - textLayout.lineHeight) / 2, 0)
            : y
        for (lineIndex, line) in textLayout.lines.enumerated() {
            (line as NSString).draw(
                at: CGPoint(
                    x: x,
                    y: originY + CGFloat(lineIndex) * textLayout.lineHeight
                ),
                withAttributes: attributes
            )
        }

        return max(baseLineHeight, textLayout.height)
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
        drawHighQualityImage(image, in: CGRect(x: x, y: y, width: imageSize.width, height: imageSize.height))

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

    private func drawHighQualityImage(_ image: UIImage, in rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            image.draw(in: rect)
            return
        }

        context.saveGState()
        context.interpolationQuality = .high
        image.draw(in: rect)
        context.restoreGState()
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
        guard let qrCode = qrCodeMatrix(for: colophon.websiteURL) else { return }

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
        drawQRCode(qrCode, in: rect)
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
        displayedPageNumber: Int?,
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
            displayedPageNumber,
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
        _ pageNumber: Int?,
        subscriptionStatus: SubscriptionStatus,
        in layout: PageLayout
    ) -> CGSize? {
        guard let pageNumber else { return nil }
        let position = layout.effectivePageNumberPosition(isPageNumberFontUnlocked: subscriptionStatus == .paid)
        guard layout.settings.isPageNumberEnabled, position != .hidden else { return nil }

        let font = AppFontCatalog.pdfPageNumberUIFont(
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
        isLastContentPage: Bool,
        subscriptionStatus: SubscriptionStatus
    ) -> Bool {
        guard subscriptionStatus.showsPoweredByHonkumi else { return false }

        switch page.kind {
        case .body:
            return isLastContentPage
        case .tableOfContents:
            return false
        case .colophon:
            return true
        }
    }

    private func qrCodeMatrix(for text: String) -> QRCodeMatrix? {
        let trimmedText = printableColophonInlineText(text)
        guard !trimmedText.isEmpty, let data = trimmedText.data(using: .utf8) else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        let extent = outputImage.extent.integral
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width > 0, height > 0 else { return nil }

        let rowBytes = width * 4
        var bitmap = [UInt8](repeating: 0, count: rowBytes * height)
        let context = CIContext()
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        bitmap.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            context.render(
                outputImage,
                toBitmap: baseAddress,
                rowBytes: rowBytes,
                bounds: extent,
                format: .RGBA8,
                colorSpace: colorSpace
            )
        }

        var modules = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * rowBytes + x * 4
                let red = bitmap[offset]
                let green = bitmap[offset + 1]
                let blue = bitmap[offset + 2]
                let alpha = bitmap[offset + 3]
                modules[y * width + x] = alpha > 0 && red < 128 && green < 128 && blue < 128
            }
        }

        return QRCodeMatrix(width: width, height: height, modules: modules)
    }

    private func drawQRCode(_ qrCode: QRCodeMatrix, in rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        guard qrCode.width > 0, qrCode.height > 0 else { return }

        let moduleWidth = rect.width / CGFloat(qrCode.width)
        let moduleHeight = rect.height / CGFloat(qrCode.height)
        let overlap: CGFloat = 0.01

        context.saveGState()
        context.setFillColor(UIColor.black.cgColor)
        context.setShouldAntialias(false)

        for y in 0..<qrCode.height {
            for x in 0..<qrCode.width where qrCode.isDark(x: x, y: y) {
                context.fill(CGRect(
                    x: rect.minX + CGFloat(x) * moduleWidth,
                    y: rect.minY + CGFloat(y) * moduleHeight,
                    width: moduleWidth + overlap,
                    height: moduleHeight + overlap
                ))
            }
        }

        context.restoreGState()
    }

    private func pdfAttributes(
        for glyph: VerticalGlyphLayout,
        sourceCharacter: String,
        pageKind: PreviewPageKind,
        usesTableOfContentsPageNumberFont: Bool,
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

        let baseFontSize = pdfVerticalBodyFontSize(pageKind: pageKind, in: layout)
        let glyphFontSize = AppFontCatalog.pdfVerticalGlyphFontSize(
            selectedFontId: layout.settings.selectedFontId,
            baseSize: baseFontSize,
            glyphScale: glyph.fontScale,
            sourceCharacter: sourceCharacter,
            appliesBodyGlyphAdjustment: pageKind == .body
        )
        if abs(glyphFontSize - baseFontSize) > 0.001 {
            attributes[.font] = pdfFont(
                size: glyphFontSize,
                in: layout,
                isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked
            )
        }

        if usesTableOfContentsPageNumberFont,
           let horizontalText = VerticalTextTypesetter.horizontalRunContent(sourceCharacter),
           horizontalText.allSatisfy(\.isNumber) {
            attributes[.font] = AppFontCatalog.pdfTableOfContentsPageNumberUIFont(
                pageNumberFontId: layout.settings.pageNumberFontId,
                bodyFontId: layout.settings.selectedFontId,
                bodyFontSize: layout.fontSize,
                glyphScale: glyph.fontScale,
                isPageNumberFontUnlocked: isAdditionalFontPackUnlocked
            )
        }
        return attributes
    }

    private func pdfVerticalBodyFontSize(
        pageKind: PreviewPageKind,
        in layout: PageLayout
    ) -> CGFloat {
        switch pageKind {
        case .tableOfContents:
            return layout.fontSize
        case .body, .colophon:
            return layout.fontSize
        }
    }

    private func visualCenteringOffsetIfNeeded(
        character: String,
        glyph: VerticalGlyphLayout,
        attributes: [NSAttributedString.Key: Any]
    ) -> CGSize {
        guard VerticalTextTypesetter.needsVisualCentering(character),
              glyph.rotationDegrees != 0,
              let font = attributes[.font] as? UIFont else {
            return .zero
        }

        return GlyphVisualCenteringCache.offset(
            text: glyph.text,
            font: font,
            rotationDegrees: glyph.rotationDegrees,
            attributes: attributes
        )
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
