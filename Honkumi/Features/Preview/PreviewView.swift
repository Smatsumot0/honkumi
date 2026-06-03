import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct PreviewView: View {
    @StateObject var viewModel: PreviewViewModel
    @Binding var pageScale: CGFloat
    @Binding var focusedPage: Int
    @Binding var horizontalAnchor: CGFloat
    @Binding var scrollOffset: CGPoint
    @State private var restoresScrollPosition = true

    private var pagePreviewScale: CGFloat {
        PreviewStyle.basePageScale
    }

    var body: some View {
        let pages = viewModel.pages

        ZoomablePreviewScrollView(
            zoomScale: $pageScale,
            contentOffset: $scrollOffset,
            minimumZoomScale: PreviewStyle.pageScaleRange.lowerBound,
            maximumZoomScale: PreviewStyle.pageScaleRange.upperBound
        ) {
            ZStack(alignment: .topLeading) {
                Color(.systemGroupedBackground)

                LazyVStack(spacing: 20) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        VStack(spacing: 8) {
                            if page.startsAfterPageBreak {
                                pageBreakLabel
                            }

                            pageCard(page, pageNumber: index + 1, totalPageCount: pages.count)
                        }
                        .id(index + 1)
                        .background(pagePositionReader(pageNumber: index + 1))
                    }
                }
                .padding()
            }
            .frame(minWidth: 1, minHeight: 1, alignment: .top)
            .coordinateSpace(name: PreviewStyle.scrollCoordinateSpaceName)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            restoresScrollPosition = false
        }
        .onChange(of: pages.count) { _, count in
            focusedPage = min(max(focusedPage, 1), max(count, 1))
        }
        .onPreferenceChange(PreviewPagePositionPreferenceKey.self) { positions in
            guard !restoresScrollPosition,
                  let focusedPosition = positions.min(by: { abs($0.value.frame.minY) < abs($1.value.frame.minY) }) else {
                return
            }
            let focused = focusedPosition.key
            let frame = focusedPosition.value.frame
            focusedPage = focused
            if frame.width > 1 {
                horizontalAnchor = (-frame.minX / frame.width).clamped(to: 0...1)
            }
        }
    }

    private func pagePositionReader(pageNumber: Int) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: PreviewPagePositionPreferenceKey.self,
                value: [
                    pageNumber: PreviewPagePosition(
                        frame: proxy.frame(in: .named(PreviewStyle.scrollCoordinateSpaceName))
                    )
                ]
            )
        }
    }

    private var pageBreakLabel: some View {
        Text("ー 改ページ ー")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(PreviewStyle.pageBreakLabelBackground, in: Capsule())
            .accessibilityLabel("改ページ")
    }

    private func pageCard(_ page: PreviewPage, pageNumber: Int, totalPageCount: Int) -> some View {
        let layout = viewModel.layout(for: pageNumber)

        return ZStack(alignment: .topLeading) {
            Color(.systemBackground)

            if page.kind == .body,
               layout.settings.showChapterTitle,
               let chapterTitle = page.chapterTitle,
               !page.chapterTitlesStartingOnPage.contains(chapterTitle) {
                chapterTitleView(chapterTitle, layout: layout)
            }

            switch page.kind {
            case .body:
                verticalText(page.columns, layout: layout)
                    .frame(
                        width: layout.bodyFrame.width * pagePreviewScale,
                        height: layout.bodyFrame.height * pagePreviewScale,
                        alignment: .topTrailing
                    )
                    .offset(
                        x: layout.bodyFrame.minX * pagePreviewScale,
                        y: layout.bodyFrame.minY * pagePreviewScale
                    )
            case let .colophon(colophon):
                colophonContentView(colophon, layout: layout)
            }

            if page.kind == .body {
                pageNumberView(pageNumber, layout: layout)
            }

            if shouldShowPoweredByHonkumi(page: page, pageNumber: pageNumber, totalPageCount: totalPageCount) {
                poweredByHonkumiView(page: page, layout: layout)
            }
        }
        .frame(
            width: layout.pageWidth * pagePreviewScale,
            height: layout.pageHeight * pagePreviewScale,
            alignment: .topLeading
        )
        .overlay(alignment: .topLeading) {
            marginGuide(layout)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(
            color: PreviewStyle.pageShadowColor,
            radius: PreviewStyle.pageShadowRadius,
            x: 0,
            y: PreviewStyle.pageShadowYOffset
        )
    }

    @ViewBuilder
    private func colophonContentView(_ colophon: ColophonSettings, layout: PageLayout) -> some View {
        horizontalColophonView(colophon, layout: layout)
    }

    private func colophonColumns(from colophon: ColophonSettings) -> [String] {
        ManuscriptPaginator.colophonColumns(from: colophon)
    }

    private func horizontalColophonView(_ colophon: ColophonSettings, layout: PageLayout) -> some View {
        let labelWidth = min(layout.bodyFrame.width * 0.28, 72) * pagePreviewScale
        let entries = ManuscriptPaginator.colophonEntries(from: colophon)

        return VStack(alignment: .leading, spacing: 8 * pagePreviewScale) {
            ForEach(entries) { entry in
                if entry.addsPrecedingSpace {
                    Color.clear.frame(height: 8 * pagePreviewScale)
                }

                if entry.id == "hp" {
                    horizontalColophonQRCodeRow(entry, colophon: colophon, labelWidth: labelWidth, layout: layout)
                } else if entry.id == "creator", viewModel.subscriptionStatus == .paid, colophon.hasCreatorImage {
                    horizontalCircleLogoCreator(colophon, layout: layout)
                        .padding(.bottom, entry.addsFollowingSpace ? 12 * pagePreviewScale : 0)
                } else if entry.label.isEmpty {
                    Text(entry.value)
                        .frame(
                            maxWidth: .infinity,
                            alignment: entry.centersInHorizontalLayout ? .center : .leading
                        )
                        .padding(.bottom, entry.addsFollowingSpace ? 12 * pagePreviewScale : 0)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 10 * pagePreviewScale) {
                        Text(entry.label)
                            .foregroundStyle(.secondary)
                            .frame(width: labelWidth, alignment: .leading)
                        Text(entry.value)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.bottom, entry.addsFollowingSpace ? 12 * pagePreviewScale : 0)
                }
            }
        }
        .font(AppFontCatalog.swiftUIFont(
            selectedFontId: layout.settings.selectedFontId,
            size: max(layout.fontSize * pagePreviewScale, 7),
            isAdditionalFontPackUnlocked: viewModel.isAdditionalFontPackUnlocked
        ))
        .frame(
            width: layout.bodyFrame.width * pagePreviewScale,
            height: layout.bodyFrame.height * pagePreviewScale,
            alignment: .topLeading
        )
        .offset(
            x: layout.bodyFrame.minX * pagePreviewScale,
            y: horizontalColophonYOffset(colophon, layout: layout)
        )
    }

    private func horizontalColophonYOffset(_ colophon: ColophonSettings, layout: PageLayout) -> CGFloat {
        let lineHeight = max(layout.fontSize * 1.65, 12) * pagePreviewScale
        let spacing = 8 * pagePreviewScale
        let contentHeight = horizontalColophonContentHeight(
            colophon,
            layout: layout,
            lineHeight: lineHeight,
            spacing: spacing
        )
        let minY = layout.bodyFrame.minY * pagePreviewScale
        let maxY = layout.bodyFrame.maxY * pagePreviewScale
        return min(max(maxY - contentHeight, minY), maxY)
    }

    private func horizontalColophonContentHeight(
        _ colophon: ColophonSettings,
        layout: PageLayout,
        lineHeight: CGFloat,
        spacing: CGFloat
    ) -> CGFloat {
        let entries = ManuscriptPaginator.colophonEntries(from: colophon)
        guard !entries.isEmpty else { return 0 }

        let qrSize = min(layout.bodyFrame.width * 0.22, 44) * pagePreviewScale
        let rowHeights = entries.map { entry -> CGFloat in
            if entry.id == "hp", !colophon.websiteURL.isEmpty {
                return qrSize + 6 * pagePreviewScale + lineHeight
            }

            if entry.id == "creator", viewModel.subscriptionStatus == .paid, colophon.hasCreatorImage {
                return max(lineHeight, creatorImageBlockHeight(colophon, layout: layout, lineHeight: lineHeight))
            }

            return lineHeight
        }
        let precedingSpaces = CGFloat(entries.filter(\.addsPrecedingSpace).count) * 8 * pagePreviewScale
        let followingSpaces = CGFloat(entries.filter(\.addsFollowingSpace).count) * 12 * pagePreviewScale
        let interRowSpacing = CGFloat(max(entries.count - 1, 0)) * spacing

        return rowHeights.reduce(0, +) + precedingSpaces + followingSpaces + interRowSpacing
    }

    private func horizontalCircleLogoCreator(_ colophon: ColophonSettings, layout: PageLayout) -> some View {
        let image = colophon.circleImageData.flatMap(UIImage.init(data:))
        let imageHeight = creatorImageHeight(layout: layout)
        let maxWidth = layout.bodyFrame.width * 0.36 * pagePreviewScale

        return VStack(spacing: 4 * pagePreviewScale) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: maxWidth, maxHeight: imageHeight)
            }

            let authorName = colophon.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !authorName.isEmpty {
                Text(authorName)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func creatorImageBlockHeight(
        _ colophon: ColophonSettings,
        layout: PageLayout,
        lineHeight: CGFloat
    ) -> CGFloat {
        let hasAuthorName = !colophon.authorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return creatorImageHeight(layout: layout) + (hasAuthorName ? 4 * pagePreviewScale + lineHeight : 0)
    }

    private func creatorImageHeight(layout: PageLayout) -> CGFloat {
        max(layout.fontSize * 2.4 * pagePreviewScale, 18 * pagePreviewScale)
    }

    @ViewBuilder
    private func verticalColophonQRCodeView(_ colophon: ColophonSettings, layout: PageLayout) -> some View {
        if let image = qrCodeImage(for: colophon.websiteURL) {
            let metrics = verticalHorizontalColophonMetrics(layout: layout)
            let fontSize = max(layout.fontSize * pagePreviewScale, 7)
            let urlWidth = (colophon.websiteURL as NSString).size(withAttributes: [
                .font: UIFont.systemFont(ofSize: fontSize)
            ]).width
            let qrX = metrics.valueX + max((urlWidth - metrics.qrSize) / 2, 0)

            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: metrics.qrSize, height: metrics.qrSize)
                .offset(x: qrX, y: metrics.blockY)
                .accessibilityLabel("HPのQRコード")
        }
    }

    private func verticalHorizontalColophonEntriesView(_ colophon: ColophonSettings, layout: PageLayout) -> some View {
        let entries = ManuscriptPaginator.verticalHorizontalColophonEntries(from: colophon)
        let metrics = verticalHorizontalColophonMetrics(layout: layout)
        let contactEntries = entries.filter { $0.id != "hp" }

        return ZStack(alignment: .topLeading) {
            if let hpEntry = entries.first(where: { $0.id == "hp" }) {
                verticalHorizontalColophonRow(hpEntry, metrics: metrics)
                    .offset(x: metrics.blockX, y: metrics.blockY + metrics.qrSize + 6 * pagePreviewScale)
            }

            VStack(alignment: .leading, spacing: 6 * pagePreviewScale) {
                ForEach(contactEntries) { entry in
                    verticalHorizontalColophonRow(entry, metrics: metrics)
                }
            }
            .offset(x: metrics.blockX, y: metrics.blockY + metrics.qrSize + metrics.lineHeight + 22 * pagePreviewScale)
        }
    }

    private func verticalHorizontalColophonRow(
        _ entry: ColophonEntry,
        metrics: VerticalHorizontalColophonMetrics
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8 * pagePreviewScale) {
            Text(entry.label)
                        .foregroundStyle(.secondary)
                .frame(width: metrics.labelWidth, alignment: .leading)
            Text(entry.value)
                .frame(width: metrics.valueWidth, alignment: .leading)
        }
        .font(.system(size: metrics.fontSize))
        .frame(width: metrics.blockWidth, height: metrics.lineHeight, alignment: .leading)
    }

    private func verticalHorizontalColophonMetrics(layout: PageLayout) -> VerticalHorizontalColophonMetrics {
        let blockWidth = layout.bodyFrame.width * 0.58 * pagePreviewScale
        let labelWidth = min(layout.bodyFrame.width * 0.18, 48) * pagePreviewScale
        let fontSize = max(layout.fontSize * pagePreviewScale, 7)
        let lineHeight = max(layout.fontSize * 1.65, 12) * pagePreviewScale
        let qrSize = min(layout.bodyFrame.width * 0.23, layout.bodyFrame.height * 0.18, 58) * pagePreviewScale

        return VerticalHorizontalColophonMetrics(
            blockX: layout.bodyFrame.width * 0.08 * pagePreviewScale,
            blockY: layout.bodyFrame.height * 0.12 * pagePreviewScale,
            blockWidth: blockWidth,
            labelWidth: labelWidth,
            valueWidth: max(blockWidth - labelWidth - 8 * pagePreviewScale, 1),
            valueX: layout.bodyFrame.width * 0.08 * pagePreviewScale + labelWidth + 8 * pagePreviewScale,
            qrSize: qrSize,
            lineHeight: lineHeight,
            fontSize: fontSize
        )
    }

    @ViewBuilder
    private func horizontalColophonQRCodeRow(
        _ entry: ColophonEntry,
        colophon: ColophonSettings,
        labelWidth: CGFloat,
        layout: PageLayout
    ) -> some View {
        if let image = qrCodeImage(for: colophon.websiteURL) {
            let fontSize = max(layout.fontSize * pagePreviewScale, 7)
            let size = min(layout.bodyFrame.width * 0.22, 44) * pagePreviewScale
            let urlWidth = (entry.value as NSString).size(withAttributes: [
                .font: UIFont.systemFont(ofSize: fontSize)
            ]).width

            HStack(alignment: .top, spacing: 10 * pagePreviewScale) {
                Text(entry.label)
                    .foregroundStyle(.secondary)
                    .frame(width: labelWidth, alignment: .leading)

                VStack(alignment: .leading, spacing: 6 * pagePreviewScale) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                        .padding(.leading, max((urlWidth - size) / 2, 0))
                        .accessibilityLabel("HPのQRコード")
                    Text(entry.value)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10 * pagePreviewScale) {
                Text(entry.label)
                    .foregroundStyle(.secondary)
                    .frame(width: labelWidth, alignment: .leading)
                Text(entry.value)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func poweredByHonkumiView(page: PreviewPage, layout: PageLayout) -> some View {
        let rawY: CGFloat = switch page.kind {
        case .body:
            layout.pageHeight - layout.marginBottom * PreviewStyle.poweredByBodyBottomMultiplier
        case .colophon:
            layout.pageHeight - layout.marginBottom * PreviewStyle.poweredByColophonBottomMultiplier
        }
        let y = clampedFooterYOffset(
            rawY * pagePreviewScale,
            pageHeight: layout.pageHeight * pagePreviewScale,
            textHeight: PreviewStyle.poweredByTextHeight
        )

        return Text("Powered by Honkumi")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .frame(
                width: layout.pageWidth * pagePreviewScale,
                height: PreviewStyle.poweredByTextHeight,
                alignment: .top
            )
            .offset(x: 0, y: y)
    }

    private func shouldShowPoweredByHonkumi(
        page: PreviewPage,
        pageNumber: Int,
        totalPageCount: Int
    ) -> Bool {
        guard viewModel.subscriptionStatus.showsPoweredByHonkumi else { return false }

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

        let transform = CGAffineTransform(scaleX: 8, y: 8)
        let scaledImage = outputImage.transformed(by: transform)
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }

    private func chapterTitleView(_ title: String, layout: PageLayout) -> some View {
        let alignment: Alignment = layout.isOddPage ? .leading : .trailing

        return Text(title)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(width: layout.bodyFrame.width * pagePreviewScale, alignment: alignment)
            .offset(
                x: layout.bodyFrame.minX * pagePreviewScale,
                y: max((layout.marginTop * 0.5) * pagePreviewScale, 4)
            )
    }

    @ViewBuilder
    private func pageNumberView(_ pageNumber: Int, layout: PageLayout) -> some View {
        let position = pageNumberPosition(layout: layout)
        if position != .hidden {
            let x = pageNumberXOffset(layout: layout, position: position)
            Text("\(pageNumber)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(
                    width: PreviewStyle.pageNumberWidth * pagePreviewScale,
                    height: PreviewStyle.pageNumberTextHeight,
                    alignment: .top
                )
                .offset(
                    x: x,
                    y: pageNumberYOffset(layout: layout)
                )
        }
    }

    private func pageNumberYOffset(layout: PageLayout) -> CGFloat {
        let rawY = (layout.pageHeight - layout.marginBottom * PreviewStyle.pageNumberBottomMultiplier) * pagePreviewScale
        return clampedFooterYOffset(
            rawY,
            pageHeight: layout.pageHeight * pagePreviewScale,
            textHeight: PreviewStyle.pageNumberTextHeight
        )
    }

    private func clampedFooterYOffset(_ y: CGFloat, pageHeight: CGFloat, textHeight: CGFloat) -> CGFloat {
        let maxY = pageHeight - textHeight - PreviewStyle.footerBottomInset
        return min(y, max(PreviewStyle.footerBottomInset, maxY))
    }

    private func pageNumberPosition(layout: PageLayout) -> PageNumberPosition {
        if viewModel.subscriptionStatus == .free {
            return layout.settings.pageNumberPosition == .hidden ? .hidden : .outside
        }

        return layout.settings.pageNumberPosition
    }

    private func pageNumberXOffset(layout: PageLayout, position: PageNumberPosition) -> CGFloat {
        let numberWidth = PreviewStyle.pageNumberWidth * pagePreviewScale

        switch position {
        case .hidden:
            return 0
        case .center:
            return layout.bodyFrame.midX * pagePreviewScale - numberWidth / 2
        case .outside:
            if layout.isOddPage {
                return layout.bodyFrame.minX * pagePreviewScale
            } else {
                return layout.bodyFrame.maxX * pagePreviewScale - numberWidth
            }
        }
    }

    private func verticalText(_ columns: [String], layout: PageLayout) -> some View {
        let lineCount = layout.settings.linesPerPage
        let characterCount = layout.settings.charactersPerLine
        let columnWidth = layout.lineAdvance * pagePreviewScale
        let rowHeight = layout.characterAdvance * pagePreviewScale
        let visibleFontSize = layout.fontSize * pagePreviewScale
        let bodyHeight = layout.bodyFrame.height * pagePreviewScale

        return HStack(alignment: .top, spacing: 0) {
            ForEach((0..<lineCount).reversed(), id: \.self) { displayIndex in
                let column = columns.indices.contains(displayIndex) ? columns[displayIndex] : ""
                let cells = verticalCells(from: column, characterCount: characterCount)
                let adjustedRowAdvance = adjustedCharacterAdvance(
                    cellCount: cells.count,
                    characterCount: characterCount,
                    bodyHeight: bodyHeight,
                    rowHeight: rowHeight
                )

                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        ForEach(0..<characterCount, id: \.self) { _ in
                            Color.clear
                                .frame(width: columnWidth, height: rowHeight)
                                .border(PreviewStyle.gridLineColor, width: PreviewStyle.gridLineWidth)
                        }
                    }

                    ForEach(Array(cells.enumerated()), id: \.offset) { rowIndex, characters in
                        verticalCell(
                            characters: characters,
                            selectedFontId: layout.settings.selectedFontId,
                            fontSize: visibleFontSize,
                            columnWidth: columnWidth,
                            rowHeight: rowHeight
                        )
                        .offset(y: CGFloat(rowIndex) * adjustedRowAdvance)
                    }
                }
                .frame(width: columnWidth, height: bodyHeight, alignment: .top)
            }
        }
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

    private func verticalCell(
        characters: [String],
        selectedFontId: String,
        fontSize: CGFloat,
        columnWidth: CGFloat,
        rowHeight: CGFloat
    ) -> some View {
        ZStack {
            ForEach(Array(characters.enumerated()), id: \.offset) { index, character in
                let glyph = verticalGlyph(for: character)

                Text(glyph.text)
                    .font(AppFontCatalog.swiftUIFont(
                        selectedFontId: selectedFontId,
                        size: fontSize * glyph.fontScale,
                        isAdditionalFontPackUnlocked: viewModel.isAdditionalFontPackUnlocked
                    ))
                    .rotationEffect(.degrees(glyph.rotationDegrees))
                    .offset(glyphOffset(
                        glyph: glyph,
                        character: character,
                        characters: characters,
                        index: index,
                        columnWidth: columnWidth,
                        rowHeight: rowHeight
                    ))
            }
        }
        .frame(width: columnWidth, height: rowHeight)
    }

    private func glyphOffset(
        glyph: VerticalGlyph,
        character: String,
        characters: [String],
        index: Int,
        columnWidth: CGFloat,
        rowHeight: CGFloat
    ) -> CGSize {
        let normalized: CGPoint

        if index > 0, glyph.isPunctuation, characters.first.map(isPunctuation) == false {
            normalized = CGPoint(x: glyph.xOffset, y: 0.38)
        } else if index > 0, isClosingQuote(character), characters.first.map(isPunctuation) == false {
            normalized = CGPoint(x: -0.02, y: 0.34)
        } else if index > 0, isClosingQuote(character), characters.first.map(isPunctuation) == true {
            normalized = CGPoint(x: -0.02, y: 0.34)
        } else {
            normalized = CGPoint(
                x: glyph.xOffset,
                y: glyph.yOffset + overflowYOffset(index: index, glyph: glyph)
            )
        }

        return CGSize(width: normalized.x * columnWidth, height: normalized.y * rowHeight)
    }

    private func verticalCells(from column: String, characterCount: Int) -> [[String]] {
        let characters = column.map(String.init)
        var cells: [[String]] = []
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if isEllipsis(character) {
                cells.append([character])
                index += 1
                while characters.indices.contains(index), isEllipsis(characters[index]) {
                    index += 1
                }
            } else if isPunctuation(character),
               characters.indices.contains(index + 1),
               isClosingQuote(characters[index + 1]) {
                cells.append([character, characters[index + 1]])
                index += 2
            } else {
                cells.append([character])
                index += 1
            }
        }

        return cells
    }

    private func overflowYOffset(index: Int, glyph: VerticalGlyph) -> CGFloat {
        guard index > 0 else { return 0 }
        return glyph.isPunctuation ? 0.38 : -0.18 * CGFloat(index)
    }

    private func verticalGlyph(for character: String) -> VerticalGlyph {
        switch character {
        case "「":
            VerticalGlyph("﹁", fontScale: 0.82)
        case "」":
            VerticalGlyph("﹂", fontScale: 0.82)
        case "『":
            VerticalGlyph("﹃", fontScale: 0.82)
        case "』":
            VerticalGlyph("﹄", fontScale: 0.82)
        case "（":
            VerticalGlyph("︵", fontScale: 0.82)
        case "）":
            VerticalGlyph("︶", fontScale: 0.82)
        case "(":
            VerticalGlyph("︵", fontScale: 0.82)
        case ")":
            VerticalGlyph("︶", fontScale: 0.82)
        case "【":
            VerticalGlyph("︻", fontScale: 0.82)
        case "】":
            VerticalGlyph("︼", fontScale: 0.82)
        case "［", "[":
            VerticalGlyph("﹇", fontScale: 0.82)
        case "］", "]":
            VerticalGlyph("﹈", fontScale: 0.82)
        case "｛", "{":
            VerticalGlyph("︷", fontScale: 0.82)
        case "｝", "}":
            VerticalGlyph("︸", fontScale: 0.82)
        case "〈":
            VerticalGlyph("︿", fontScale: 0.82)
        case "〉":
            VerticalGlyph("﹀", fontScale: 0.82)
        case "《":
            VerticalGlyph("︽", fontScale: 0.82)
        case "》":
            VerticalGlyph("︾", fontScale: 0.82)
        case "…", "‥":
            VerticalGlyph("⋯", rotationDegrees: 90)
        case "、", "。", "､", "｡", "，", "．":
            VerticalGlyph(character, fontScale: 0.66, xOffset: 0.38, yOffset: -0.40, isPunctuation: true)
        case "ぁ", "ぃ", "ぅ", "ぇ", "ぉ", "っ", "ゃ", "ゅ", "ょ",
             "ァ", "ィ", "ゥ", "ェ", "ォ", "ッ", "ャ", "ュ", "ョ":
            VerticalGlyph(character, fontScale: 0.74, xOffset: 0.30, yOffset: -0.32)
        case "―", "─", "—", "ｰ", "ー":
            VerticalGlyph("｜", fontScale: 0.78)
        default:
            VerticalGlyph(character)
        }
    }

    private func isEllipsis(_ character: String) -> Bool {
        ["…", "‥"].contains(character)
    }

    private func isPunctuation(_ character: String) -> Bool {
        ["、", "。", "､", "｡", "，", "．"].contains(character)
    }

    private func isClosingQuote(_ character: String) -> Bool {
        ["」", "』"].contains(character)
    }

    private func isLineStartProhibited(_ character: String) -> Bool {
        [
            "、", "。", "，", "．", "・", "：", "；", "！", "？",
            "」", "』", "）", "】", "》", "〉", "］", "｝"
        ].contains(character)
    }

    private func marginGuide(_ layout: PageLayout) -> some View {
        Path { path in
            path.addRect(CGRect(
                x: layout.bodyFrame.minX * pagePreviewScale,
                y: layout.bodyFrame.minY * pagePreviewScale,
                width: layout.bodyFrame.width * pagePreviewScale,
                height: layout.bodyFrame.height * pagePreviewScale
            ))
        }
        .stroke(
            PreviewStyle.marginGuideColor,
            style: StrokeStyle(lineWidth: PreviewStyle.marginGuideWidth, dash: PreviewStyle.marginGuideDash)
        )
    }
}

private enum PreviewStyle {
    static let basePageScale: CGFloat = 0.7
    static let scrollCoordinateSpaceName = "previewScroll"
    static let pageScaleRange: ClosedRange<CGFloat> = 1...3.2
    static let gridLineColor = Color(hex: 0xEAEAEA).opacity(0.28)
    static let gridLineWidth: CGFloat = 0.5
    static let marginGuideColor = Color(hex: 0xD9D9D9).opacity(0.75)
    static let marginGuideActiveColor = Color.accentColor.opacity(0.35)
    static let marginGuideWidth: CGFloat = 1
    static let marginGuideDash: [CGFloat] = [4, 3]
    static let pageShadowColor = Color.black.opacity(0.06)
    static let pageShadowRadius: CGFloat = 4
    static let pageShadowYOffset: CGFloat = 2
    static let pageNumberWidth: CGFloat = 18
    static let pageNumberTextHeight: CGFloat = 16
    static let poweredByTextHeight: CGFloat = 16
    static let pageNumberBottomMultiplier: CGFloat = 0.82
    static let poweredByBodyBottomMultiplier: CGFloat = 0.48
    static let poweredByColophonBottomMultiplier: CGFloat = 0.72
    static let footerBottomInset: CGFloat = 2
    static let pageBreakLabelBackground = Color(hex: 0xEAEAEA).opacity(0.45)
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
    let fontSize: CGFloat
}

private struct ZoomablePreviewScrollView<Content: View>: UIViewRepresentable {
    @Binding var zoomScale: CGFloat
    @Binding var contentOffset: CGPoint

    let minimumZoomScale: CGFloat
    let maximumZoomScale: CGFloat
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .systemGroupedBackground
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = minimumZoomScale
        scrollView.maximumZoomScale = maximumZoomScale
        scrollView.zoomScale = zoomScale.clamped(to: minimumZoomScale...maximumZoomScale)
        scrollView.bouncesZoom = true
        scrollView.delaysContentTouches = false
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = true

        let hostedView = context.coordinator.hostingController.view!
        hostedView.backgroundColor = .clear
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(hostedView)

        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hostedView.widthAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.widthAnchor),
            hostedView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.hostingController.rootView = AnyView(content())
        scrollView.minimumZoomScale = minimumZoomScale
        scrollView.maximumZoomScale = maximumZoomScale

        let clampedZoomScale = zoomScale.clamped(to: minimumZoomScale...maximumZoomScale)
        if !scrollView.isTracking,
           !scrollView.isZooming,
           abs(scrollView.zoomScale - clampedZoomScale) > 0.001 {
            scrollView.setZoomScale(clampedZoomScale, animated: false)
        }

        guard !context.coordinator.didRestoreInitialOffset else { return }
        context.coordinator.didRestoreInitialOffset = true
        DispatchQueue.main.async {
            let maxOffset = CGPoint(
                x: max(scrollView.contentSize.width - scrollView.bounds.width, 0),
                y: max(scrollView.contentSize.height - scrollView.bounds.height, 0)
            )
            let restoredOffset = CGPoint(
                x: contentOffset.x.clamped(to: 0...maxOffset.x),
                y: contentOffset.y.clamped(to: 0...maxOffset.y)
            )
            scrollView.setContentOffset(restoredOffset, animated: false)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomablePreviewScrollView
        let hostingController: UIHostingController<AnyView>
        var didRestoreInitialOffset = false

        init(parent: ZoomablePreviewScrollView) {
            self.parent = parent
            self.hostingController = UIHostingController(rootView: AnyView(parent.content()))
            super.init()
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostingController.view
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            _ = scrollView
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !scrollView.isTracking,
                  !scrollView.isDragging,
                  !scrollView.isDecelerating,
                  !scrollView.isZooming else {
                return
            }
            updateBindings(from: scrollView)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            updateBindings(from: scrollView)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                updateBindings(from: scrollView)
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            updateBindings(from: scrollView)
        }

        private func updateBindings(from scrollView: UIScrollView) {
            let currentZoomScale = scrollView.zoomScale.clamped(
                to: parent.minimumZoomScale...parent.maximumZoomScale
            )
            if abs(parent.zoomScale - currentZoomScale) > 0.001 {
                parent.zoomScale = currentZoomScale
            }

            let currentOffset = scrollView.contentOffset
            if abs(parent.contentOffset.x - currentOffset.x) > 0.5
                || abs(parent.contentOffset.y - currentOffset.y) > 0.5 {
                parent.contentOffset = currentOffset
            }
        }
    }
}

private struct VerticalGlyph: Equatable {
    let text: String
    let rotationDegrees: Double
    let fontScale: CGFloat
    let xOffset: CGFloat
    let yOffset: CGFloat
    let isPunctuation: Bool

    init(
        _ text: String,
        rotationDegrees: Double = 0,
        fontScale: CGFloat = 1,
        xOffset: CGFloat = 0,
        yOffset: CGFloat = 0,
        isPunctuation: Bool = false
    ) {
        self.text = text
        self.rotationDegrees = rotationDegrees
        self.fontScale = fontScale
        self.xOffset = xOffset
        self.yOffset = yOffset
        self.isPunctuation = isPunctuation
    }
}

private struct PreviewPagePosition: Equatable {
    let frame: CGRect
}

private struct PreviewPagePositionPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: PreviewPagePosition] = [:]

    static func reduce(value: inout [Int: PreviewPagePosition], nextValue: () -> [Int: PreviewPagePosition]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
