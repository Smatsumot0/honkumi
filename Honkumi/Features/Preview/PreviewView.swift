import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct PreviewView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject var viewModel: PreviewViewModel
    @Binding var pageScale: CGFloat
    @Binding var focusedPage: Int
    @Binding var horizontalAnchor: CGFloat
    @Binding var scrollOffset: CGPoint
    @Binding var showsFacingPages: Bool
    @Binding var showsGuides: Bool
    @State private var restoresScrollPosition = true
    @State private var visiblePageLimit = PreviewStyle.initialVisiblePageLimit

    private var pagePreviewScale: CGFloat {
        PreviewStyle.basePageScale
    }

    var body: some View {
        let pages = viewModel.pages
        let pageLimit = displayedPageLimit(totalPageCount: pages.count)
        let visiblePages = Array(pages.prefix(pageLimit))
        let hasMorePages = pageLimit < pages.count

        ZoomablePreviewScrollView(
            zoomScale: $pageScale,
            contentOffset: $scrollOffset,
            minimumZoomScale: PreviewStyle.pageScaleRange.lowerBound,
            maximumZoomScale: PreviewStyle.pageScaleRange.upperBound
        ) {
            Group {
                if showsFacingPages {
                    LazyVStack(spacing: PreviewStyle.facingSpreadSpacing) {
                        ForEach(pageSpreads(for: visiblePages), id: \.firstPageNumber) { spread in
                            HStack(alignment: .top, spacing: PreviewStyle.facingPageSpacing) {
                                ForEach(Array(spread.items.enumerated()), id: \.offset) { _, item in
                                    if let page = item.page, let pageNumber = item.pageNumber {
                                        pageStack(
                                            page,
                                            pageNumber: pageNumber,
                                            totalPageCount: pages.count
                                        )
                                        .id(pageNumber)
                                    } else {
                                        blankPageSlot(referencePageNumber: item.referencePageNumber)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        }

                        if hasMorePages {
                            loadMorePagesTrigger
                        }
                    }
                    .padding(.vertical)
                    .padding(.horizontal, PreviewStyle.facingHorizontalPadding)
                } else {
                    LazyVStack(spacing: 20) {
                        ForEach(Array(visiblePages.enumerated()), id: \.offset) { index, page in
                            pageStack(page, pageNumber: index + 1, totalPageCount: pages.count)
                                .id(index + 1)
                        }

                        if hasMorePages {
                            loadMorePagesTrigger
                        }
                    }
                    .padding()
                }
            }
            .background(PreviewStyle.canvasBackground(colorScheme))
            .frame(minWidth: 1, minHeight: 1, alignment: .top)
            .coordinateSpace(name: PreviewStyle.scrollCoordinateSpaceName)
        }
        .background(PreviewStyle.canvasBackground(colorScheme))
        .overlay(alignment: .top) {
            if viewModel.isPaginating {
                loadingBanner
                    .padding(.top, 12)
            }
        }
        .overlay(alignment: .bottom) {
            if hasMorePages {
                bottomLoadingBanner
                    .padding(.bottom, 14)
            }
        }
        .onAppear {
            restoresScrollPosition = false
        }
        .onChange(of: pages.count) { _, count in
            focusedPage = min(max(focusedPage, 1), max(count, 1))
            visiblePageLimit = min(PreviewStyle.initialVisiblePageLimit, max(count, 1))
        }
    }

    private var loadingBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("プレビューを準備中")
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        .accessibilityLabel("プレビューを準備中")
    }

    private var bottomLoadingBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("読み込み中")
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        .accessibilityLabel("読み込み中")
    }

    private var loadMorePagesTrigger: some View {
        Color.clear
            .frame(height: 1)
            .accessibilityHidden(true)
            .onAppear {
                revealMorePages()
            }
    }

    private func displayedPageLimit(totalPageCount: Int) -> Int {
        guard totalPageCount > 0 else { return 0 }
        var limit = min(max(visiblePageLimit, 1), totalPageCount)
        if showsFacingPages, limit > 1, limit.isMultiple(of: 2), limit < totalPageCount {
            limit += 1
        }
        return min(limit, totalPageCount)
    }

    private func revealMorePages() {
        let nextLimit = min(
            visiblePageLimit + PreviewStyle.visiblePageBatchSize,
            max(viewModel.pages.count, 1)
        )
        guard nextLimit > visiblePageLimit else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            visiblePageLimit = nextLimit
        }
    }

    private var pageBreakLabel: some View {
        Text("ー 改ページ ー")
            .font(.caption2)
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(PreviewStyle.pageBreakLabelBackground, in: Capsule())
            .accessibilityLabel("改ページ")
    }

    private func pageStack(_ page: PreviewPage, pageNumber: Int, totalPageCount: Int) -> some View {
        VStack(spacing: 8) {
            if page.startsAfterPageBreak, !showsFacingPages {
                pageBreakLabel
            }

            pageCard(page, pageNumber: pageNumber, totalPageCount: totalPageCount)
        }
    }

    private func pageSpreads(for pages: [PreviewPage]) -> [PreviewSpread] {
        guard !pages.isEmpty else { return [] }

        var spreads = [
            PreviewSpread(items: [
                PreviewSpreadItem(pageNumber: 1, page: pages[0], referencePageNumber: 1),
                PreviewSpreadItem(pageNumber: nil, page: nil, referencePageNumber: 1)
            ])
        ]

        var evenPageNumber = 2
        while evenPageNumber <= pages.count {
            let oddPageNumber = evenPageNumber + 1
            let rightItem = PreviewSpreadItem(
                pageNumber: evenPageNumber,
                page: pages[evenPageNumber - 1],
                referencePageNumber: evenPageNumber
            )
            let leftItem: PreviewSpreadItem
            if oddPageNumber <= pages.count {
                leftItem = PreviewSpreadItem(
                    pageNumber: oddPageNumber,
                    page: pages[oddPageNumber - 1],
                    referencePageNumber: oddPageNumber
                )
            } else {
                leftItem = PreviewSpreadItem(
                    pageNumber: nil,
                    page: nil,
                    referencePageNumber: evenPageNumber
                )
            }

            spreads.append(PreviewSpread(items: [leftItem, rightItem]))
            evenPageNumber += 2
        }

        return spreads
    }

    private func blankPageSlot(referencePageNumber: Int) -> some View {
        let layout = viewModel.layout(for: referencePageNumber)
        return Color.clear.frame(
            width: layout.pageWidth * pagePreviewScale,
            height: layout.pageHeight * pagePreviewScale
        )
    }

    private func pageCard(_ page: PreviewPage, pageNumber: Int, totalPageCount: Int) -> some View {
        let layout = viewModel.layout(for: pageNumber)

        return ZStack(alignment: .topLeading) {
            PreviewStyle.paperBackground(colorScheme)

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

            pageNumberView(pageNumber, layout: layout)

            if shouldShowPoweredByHonkumi(page: page, pageNumber: pageNumber, totalPageCount: totalPageCount) {
                poweredByHonkumiView(page: page, pageNumber: pageNumber, layout: layout)
            }
        }
        .frame(
            width: layout.pageWidth * pagePreviewScale,
            height: layout.pageHeight * pagePreviewScale,
            alignment: .topLeading
        )
        .overlay(alignment: .topLeading) {
            if showsGuides {
                layoutGuide(layout, pageNumber: pageNumber)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: PreviewStyle.pageCornerRadius)
                .stroke(PreviewStyle.paperBorderColor(colorScheme), lineWidth: PreviewStyle.paperBorderWidth)
        }
        .clipShape(RoundedRectangle(cornerRadius: PreviewStyle.pageCornerRadius))
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
                            .foregroundStyle(.primary)
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
                return colophon.showsQRCode
                    ? qrSize + (colophon.showsWebsiteURL ? 6 * pagePreviewScale + lineHeight : 0)
                    : lineHeight
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

            let authorName = colophon.showsAuthorName
                ? colophon.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
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
        let hasAuthorName = colophon.showsAuthorName
            && !colophon.authorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return creatorImageHeight(layout: layout) + (hasAuthorName ? 4 * pagePreviewScale + lineHeight : 0)
    }

    private func creatorImageHeight(layout: PageLayout) -> CGFloat {
        max(layout.fontSize * 2.4 * pagePreviewScale, 18 * pagePreviewScale)
    }

    @ViewBuilder
    private func verticalColophonQRCodeView(_ colophon: ColophonSettings, layout: PageLayout) -> some View {
        if colophon.showsQRCode, let image = qrCodeImage(for: colophon.websiteURL) {
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
            if colophon.showsWebsiteURL, let hpEntry = entries.first(where: { $0.id == "hp" }) {
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
                        .foregroundStyle(.primary)
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
        if colophon.showsQRCode, let image = qrCodeImage(for: colophon.websiteURL) {
            let fontSize = max(layout.fontSize * pagePreviewScale, 7)
            let size = min(layout.bodyFrame.width * 0.22, 44) * pagePreviewScale
            let urlWidth = (entry.value as NSString).size(withAttributes: [
                .font: UIFont.systemFont(ofSize: fontSize)
            ]).width

            HStack(alignment: .top, spacing: 10 * pagePreviewScale) {
                Text(entry.label)
                    .foregroundStyle(.primary)
                    .frame(width: labelWidth, alignment: .leading)

                VStack(alignment: .leading, spacing: 6 * pagePreviewScale) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                        .padding(.leading, max((urlWidth - size) / 2, 0))
                        .accessibilityLabel("HPのQRコード")
                    if colophon.showsWebsiteURL {
                        Text(entry.value)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10 * pagePreviewScale) {
                Text(entry.label)
                    .foregroundStyle(.primary)
                    .frame(width: labelWidth, alignment: .leading)
                Text(entry.value)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func poweredByHonkumiView(page: PreviewPage, pageNumber: Int, layout: PageLayout) -> some View {
        let text = "Powered by Honkumi"
        let font = AppFontCatalog.uiFont(
            selectedFontId: layout.settings.selectedFontId,
            size: PageLayout.poweredByHonkumiFontSize,
            isAdditionalFontPackUnlocked: viewModel.isAdditionalFontPackUnlocked
        )
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let pageNumberSize = pageNumberTextSizeIfVisible(pageNumber, layout: layout)
        let origin = layout.poweredByHonkumiOrigin(
            textSize: textSize,
            pageNumberTextSize: pageNumberSize
        )
        let frameHeight = max(textSize.height * pagePreviewScale, PreviewStyle.poweredByTextHeight)

        return Text(text)
            .font(AppFontCatalog.swiftUIFont(
                selectedFontId: layout.settings.selectedFontId,
                size: PageLayout.poweredByHonkumiFontSize * pagePreviewScale,
                isAdditionalFontPackUnlocked: viewModel.isAdditionalFontPackUnlocked
            ))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .frame(
                width: layout.pageWidth * pagePreviewScale,
                height: frameHeight,
                alignment: .top
            )
            .offset(x: 0, y: origin.y * pagePreviewScale)
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
            .foregroundStyle(.primary)
            .lineLimit(1)
            .frame(width: layout.bodyFrame.width * pagePreviewScale, alignment: alignment)
            .offset(
                x: layout.bodyFrame.minX * pagePreviewScale,
                y: max((layout.marginTop * 0.5) * pagePreviewScale, 4)
            )
    }

    @ViewBuilder
    private func pageNumberView(_ pageNumber: Int, layout: PageLayout) -> some View {
        let position = layout.effectivePageNumberPosition(isPageNumberFontUnlocked: viewModel.isPageNumberFontUnlocked)
        if layout.settings.isPageNumberEnabled, position != .hidden {
            let unscaledFontSize = layout.effectivePageNumberFontSize(isPageNumberFontUnlocked: viewModel.isPageNumberFontUnlocked)
            let fontSize = unscaledFontSize * pagePreviewScale
            let textSize = pageNumberTextSize(pageNumber, layout: layout)
            let origin = layout.pageNumberOrigin(
                textSize: textSize,
                isPageNumberFontUnlocked: viewModel.isPageNumberFontUnlocked
            )
            let frameWidth = max(textSize.width * pagePreviewScale, PreviewStyle.pageNumberWidth * pagePreviewScale)
            let frameHeight = max(textSize.height * pagePreviewScale, PreviewStyle.pageNumberTextHeight * pagePreviewScale)
            Text("\(pageNumber)")
                .font(AppFontCatalog.pageNumberSwiftUIFont(
                    pageNumberFontId: layout.settings.pageNumberFontId,
                    bodyFontId: layout.settings.selectedFontId,
                    size: fontSize,
                    isPageNumberFontUnlocked: viewModel.isPageNumberFontUnlocked
                ))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(
                    width: frameWidth,
                    height: frameHeight,
                    alignment: .top
                )
                .offset(
                    x: origin.x * pagePreviewScale,
                    y: origin.y * pagePreviewScale
                )
        }
    }

    private func pageNumberTextSizeIfVisible(_ pageNumber: Int, layout: PageLayout) -> CGSize? {
        let position = layout.effectivePageNumberPosition(isPageNumberFontUnlocked: viewModel.isPageNumberFontUnlocked)
        guard layout.settings.isPageNumberEnabled, position != .hidden else { return nil }
        return pageNumberTextSize(pageNumber, layout: layout)
    }

    private func pageNumberTextSize(_ pageNumber: Int, layout: PageLayout) -> CGSize {
        let font = AppFontCatalog.pageNumberUIFont(
            pageNumberFontId: layout.settings.pageNumberFontId,
            bodyFontId: layout.settings.selectedFontId,
            size: layout.effectivePageNumberFontSize(isPageNumberFontUnlocked: viewModel.isPageNumberFontUnlocked),
            isPageNumberFontUnlocked: viewModel.isPageNumberFontUnlocked
        )
        return ("\(pageNumber)" as NSString).size(withAttributes: [.font: font])
    }

    private func clampedFooterYOffset(_ y: CGFloat, pageHeight: CGFloat, textHeight: CGFloat) -> CGFloat {
        let maxY = pageHeight - textHeight - PreviewStyle.footerBottomInset
        return min(y, max(PreviewStyle.footerBottomInset, maxY))
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
                let cells = VerticalTextTypesetter.cells(
                    from: column,
                    alphanumericOrientation: layout.settings.alphanumericOrientation
                )
                let adjustedRowAdvance = VerticalTextTypesetter.adjustedCharacterAdvance(
                    cellCount: cells.count,
                    characterCount: characterCount,
                    bodyHeight: bodyHeight,
                    rowHeight: rowHeight
                )

                ZStack(alignment: .topLeading) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { rowIndex, characters in
                        verticalCell(
                            characters: characters,
                            selectedFontId: layout.settings.selectedFontId,
                            fontSize: visibleFontSize,
                            columnWidth: columnWidth,
                            rowHeight: rowHeight,
                            alphanumericOrientation: layout.settings.alphanumericOrientation
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
        rowHeight: CGFloat,
        alphanumericOrientation: AlphanumericOrientation
    ) -> some View {
        ZStack {
            ForEach(Array(characters.enumerated()), id: \.offset) { index, character in
                let glyph = VerticalTextTypesetter.glyph(
                    for: character,
                    alphanumericOrientation: alphanumericOrientation
                )
                let offset = VerticalTextTypesetter.glyphOffset(
                    glyph: glyph,
                    character: character,
                    characters: characters,
                    index: index,
                    columnWidth: columnWidth,
                    rowHeight: rowHeight
                )

                if VerticalTextTypesetter.isDashConnector(character) {
                    Rectangle()
                        .fill(Color.primary)
                        .frame(
                            width: max(fontSize * 0.08, 0.45 * pagePreviewScale),
                            height: rowHeight * 1.16
                        )
                        .offset(offset)
                } else {
                    Text(glyph.text)
                        .font(AppFontCatalog.swiftUIFont(
                            selectedFontId: selectedFontId,
                            size: fontSize * glyph.fontScale,
                            isAdditionalFontPackUnlocked: viewModel.isAdditionalFontPackUnlocked
                        ))
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: columnWidth, height: rowHeight)
                        .rotationEffect(.degrees(glyph.rotationDegrees))
                        .offset(offset)
                }
            }
        }
        .frame(width: columnWidth, height: rowHeight)
    }

    private func layoutGuide(_ layout: PageLayout, pageNumber: Int) -> some View {
        ZStack(alignment: .topLeading) {
            bodyAreaFill(layout)
            marginGuide(layout)
        }
        .allowsHitTesting(false)
    }

    private func bodyAreaFill(_ layout: PageLayout) -> some View {
        Rectangle()
            .fill(PreviewStyle.bodyAreaFillColor)
            .frame(
                width: layout.bodyFrame.width * pagePreviewScale,
                height: layout.bodyFrame.height * pagePreviewScale
            )
            .offset(
                x: layout.bodyFrame.minX * pagePreviewScale,
                y: layout.bodyFrame.minY * pagePreviewScale
            )
    }

    private func marginGuide(_ layout: PageLayout) -> some View {
        Path { path in
            let pageRect = CGRect(
                x: 0,
                y: 0,
                width: layout.pageWidth * pagePreviewScale,
                height: layout.pageHeight * pagePreviewScale
            )
            let bodyRect = CGRect(
                x: layout.bodyFrame.minX * pagePreviewScale,
                y: layout.bodyFrame.minY * pagePreviewScale,
                width: layout.bodyFrame.width * pagePreviewScale,
                height: layout.bodyFrame.height * pagePreviewScale
            )

            path.addRect(pageRect)
            path.addRect(bodyRect)
            path.move(to: CGPoint(x: bodyRect.minX, y: pageRect.minY))
            path.addLine(to: CGPoint(x: bodyRect.minX, y: pageRect.maxY))
            path.move(to: CGPoint(x: bodyRect.maxX, y: pageRect.minY))
            path.addLine(to: CGPoint(x: bodyRect.maxX, y: pageRect.maxY))
            path.move(to: CGPoint(x: pageRect.minX, y: bodyRect.minY))
            path.addLine(to: CGPoint(x: pageRect.maxX, y: bodyRect.minY))
            path.move(to: CGPoint(x: pageRect.minX, y: bodyRect.maxY))
            path.addLine(to: CGPoint(x: pageRect.maxX, y: bodyRect.maxY))
        }
        .stroke(
            PreviewStyle.marginGuideColor,
            style: StrokeStyle(lineWidth: PreviewStyle.marginGuideWidth)
        )
    }

}

private enum PreviewStyle {
    static let initialVisiblePageLimit = 25
    static let visiblePageBatchSize = 20
    static let basePageScale: CGFloat = 0.52
    static let scrollCoordinateSpaceName = "previewScroll"
    static let pageScaleRange: ClosedRange<CGFloat> = 1...3.2
    static func canvasBackground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0x07090D) : Color(hex: 0x111111)
    }

    static func paperBackground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0x252B34) : Color(hex: 0xF7F5EF)
    }

    static func paperBorderColor(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0x5E6A7A) : Color(hex: 0xC7C1B5)
    }

    static let paperBorderWidth: CGFloat = 0.7
    static let pageCornerRadius: CGFloat = 4
    static let facingPageSpacing: CGFloat = 14
    static let facingSpreadSpacing: CGFloat = 14
    static let facingHorizontalPadding: CGFloat = 20
    static let bodyAreaFillColor = Color(hex: 0x2F80ED).opacity(0.045)
    static let marginGuideColor = Color(hex: 0x2F80ED).opacity(0.72)
    static let marginGuideWidth: CGFloat = 0.75
    static let pageShadowColor = Color.black.opacity(0.28)
    static let pageShadowRadius: CGFloat = 4
    static let pageShadowYOffset: CGFloat = 2
    static let pageNumberWidth: CGFloat = 18
    static let pageNumberTextHeight: CGFloat = 16
    static let poweredByTextHeight: CGFloat = 16
    static let pageNumberBottomMultiplier: CGFloat = 0.82
    static let poweredByBodyBottomMultiplier: CGFloat = 0.82
    static let poweredByColophonBottomMultiplier: CGFloat = 0.82
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
        scrollView.backgroundColor = .clear
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
        if context.coordinator.isUserInteracting(with: scrollView) {
            context.coordinator.needsRootViewRefresh = true
        } else {
            context.coordinator.hostingController.rootView = AnyView(content())
            context.coordinator.needsRootViewRefresh = false
        }
        scrollView.minimumZoomScale = minimumZoomScale
        scrollView.maximumZoomScale = maximumZoomScale

        let clampedZoomScale = zoomScale.clamped(to: minimumZoomScale...maximumZoomScale)
        if !scrollView.isTracking,
           !scrollView.isZooming,
           abs(scrollView.zoomScale - clampedZoomScale) > 0.001 {
            scrollView.setZoomScale(clampedZoomScale, animated: false)
        }

        guard !context.coordinator.isUserInteracting(with: scrollView) else { return }

        DispatchQueue.main.async {
            guard !context.coordinator.isUserInteracting(with: scrollView) else { return }

            let maxOffset = CGPoint(
                x: max(scrollView.contentSize.width - scrollView.bounds.width, 0),
                y: max(scrollView.contentSize.height - scrollView.bounds.height, 0)
            )
            let targetOffset = context.coordinator.didRestoreInitialOffset
                ? CGPoint(
                    x: scrollView.contentOffset.x.clamped(to: 0...maxOffset.x),
                    y: scrollView.contentOffset.y.clamped(to: 0...maxOffset.y)
                )
                : CGPoint(
                    x: contentOffset.x.clamped(to: 0...maxOffset.x),
                    y: contentOffset.y.clamped(to: 0...maxOffset.y)
                )
            context.coordinator.didRestoreInitialOffset = true

            if abs(scrollView.contentOffset.x - targetOffset.x) > 0.5
                || abs(scrollView.contentOffset.y - targetOffset.y) > 0.5 {
                scrollView.setContentOffset(targetOffset, animated: false)
            }

            if abs(contentOffset.x - targetOffset.x) > 0.5
                || abs(contentOffset.y - targetOffset.y) > 0.5 {
                self.contentOffset = targetOffset
            }
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomablePreviewScrollView
        let hostingController: UIHostingController<AnyView>
        var didRestoreInitialOffset = false
        var needsRootViewRefresh = false

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
            refreshRootViewIfNeeded()
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                updateBindings(from: scrollView)
                refreshRootViewIfNeeded()
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            updateBindings(from: scrollView)
            refreshRootViewIfNeeded()
        }

        func isUserInteracting(with scrollView: UIScrollView) -> Bool {
            scrollView.isTracking
                || scrollView.isDragging
                || scrollView.isDecelerating
                || scrollView.isZooming
        }

        private func refreshRootViewIfNeeded() {
            guard needsRootViewRefresh else { return }
            hostingController.rootView = AnyView(parent.content())
            needsRootViewRefresh = false
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

private struct PreviewSpread {
    let items: [PreviewSpreadItem]

    var firstPageNumber: Int {
        items.compactMap(\.pageNumber).first ?? 0
    }
}

private struct PreviewSpreadItem {
    let pageNumber: Int?
    let page: PreviewPage?
    let referencePageNumber: Int
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
