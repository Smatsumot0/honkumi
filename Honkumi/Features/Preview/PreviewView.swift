import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct PreviewView: View {
    @StateObject var viewModel: PreviewViewModel
    @State private var pageScale: CGFloat = 1
    @State private var gestureScale: CGFloat = 1

    private var pagePreviewScale: CGFloat {
        PreviewStyle.basePageScale * pageScale * gestureScale
    }

    var body: some View {
        let pages = viewModel.pages

        ScrollView([.vertical, .horizontal]) {
            LazyVStack(spacing: 20) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    VStack(spacing: 8) {
                        if page.startsAfterPageBreak {
                            pageBreakLabel
                        }

                        pageCard(page, pageNumber: index + 1, totalPageCount: pages.count)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .gesture(zoomGesture)
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                gestureScale = value
            }
            .onEnded { value in
                pageScale = (pageScale * value).clamped(to: PreviewStyle.pageScaleRange)
                gestureScale = 1
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
        .font(.system(size: max(layout.fontSize * pagePreviewScale, 7)))
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

        return HStack(alignment: .top, spacing: 0) {
            ForEach((0..<lineCount).reversed(), id: \.self) { displayIndex in
                let column = columns.indices.contains(displayIndex) ? columns[displayIndex] : ""

                VStack(spacing: 0) {
                    ForEach(0..<characterCount, id: \.self) { rowIndex in
                        let glyph = verticalGlyph(for: character(at: rowIndex, in: column))

                        Text(glyph.text)
                            .font(.custom(layout.settings.japaneseFont.postScriptName, size: visibleFontSize * glyph.fontScale))
                            .rotationEffect(.degrees(glyph.rotationDegrees))
                            .offset(x: glyph.xOffset * columnWidth, y: glyph.yOffset * rowHeight)
                            .frame(width: columnWidth, height: rowHeight)
                            .border(PreviewStyle.gridLineColor, width: PreviewStyle.gridLineWidth)
                    }
                }
                .frame(width: columnWidth, height: layout.bodyFrame.height * pagePreviewScale, alignment: .top)
            }
        }
    }

    private func character(at index: Int, in column: String) -> String {
        guard index < column.count else { return "" }
        let stringIndex = column.index(column.startIndex, offsetBy: index)
        return String(column[stringIndex])
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
            VerticalGlyph(character, fontScale: 0.78, xOffset: 0.24, yOffset: -0.26)
        case "―", "─", "—", "ｰ", "ー":
            VerticalGlyph("｜")
        default:
            VerticalGlyph(character)
        }
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

private struct VerticalGlyph: Equatable {
    let text: String
    let rotationDegrees: Double
    let fontScale: CGFloat
    let xOffset: CGFloat
    let yOffset: CGFloat

    init(
        _ text: String,
        rotationDegrees: Double = 0,
        fontScale: CGFloat = 1,
        xOffset: CGFloat = 0,
        yOffset: CGFloat = 0
    ) {
        self.text = text
        self.rotationDegrees = rotationDegrees
        self.fontScale = fontScale
        self.xOffset = xOffset
        self.yOffset = yOffset
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
