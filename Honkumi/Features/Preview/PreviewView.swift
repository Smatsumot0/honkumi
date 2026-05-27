import SwiftUI

struct PreviewView: View {
    @StateObject var viewModel: PreviewViewModel
    @State private var pageScale: CGFloat = 1
    @State private var gestureScale: CGFloat = 1

    private var pagePreviewScale: CGFloat {
        PreviewStyle.basePageScale * pageScale * gestureScale
    }

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(spacing: 20) {
                ForEach(Array(viewModel.pages.enumerated()), id: \.offset) { index, page in
                    VStack(spacing: 8) {
                        if page.startsAfterPageBreak {
                            pageBreakLabel
                        }

                        pageCard(page, pageNumber: index + 1)
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

    private func pageCard(_ page: PreviewPage, pageNumber: Int) -> some View {
        let layout = viewModel.layout(for: pageNumber)

        return ZStack(alignment: .topLeading) {
            Color(.systemBackground)

            if layout.settings.showChapterTitle, let chapterTitle = page.chapterTitle {
                chapterTitleView(chapterTitle, layout: layout)
            }

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

            pageNumberView(pageNumber, layout: layout)
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
        if layout.settings.pageNumberPosition != .hidden {
            let x = pageNumberXOffset(layout: layout)
            Text("\(pageNumber)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: PreviewStyle.pageNumberWidth * pagePreviewScale)
                .offset(
                    x: x,
                    y: (layout.pageHeight - layout.marginBottom * 0.72) * pagePreviewScale
                )
        }
    }

    private func pageNumberXOffset(layout: PageLayout) -> CGFloat {
        let numberWidth = PreviewStyle.pageNumberWidth * pagePreviewScale

        switch layout.settings.pageNumberPosition {
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
    static let pageBreakLabelBackground = Color(hex: 0xEAEAEA).opacity(0.45)
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
