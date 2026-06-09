import CoreGraphics
import Foundation

nonisolated struct PageLayout: Equatable {
    let pageNumber: Int
    let pageSize: PageSize
    let pageWidth: CGFloat
    let pageHeight: CGFloat
    let bodyFrame: CGRect
    let marginTop: CGFloat
    let marginBottom: CGFloat
    let marginInner: CGFloat
    let marginOuter: CGFloat
    let lineAdvance: CGFloat
    let characterAdvance: CGFloat
    let fontSize: CGFloat
    let settings: EditorSettings

    var isOddPage: Bool {
        pageNumber % 2 == 1
    }

    func effectivePageNumberPosition(isPageNumberFontUnlocked: Bool) -> PageNumberPosition {
        guard settings.isPageNumberEnabled else { return .hidden }
        guard settings.pageNumberPosition != .hidden else { return .hidden }
        guard isPageNumberFontUnlocked else { return .outside }
        return settings.pageNumberPosition
    }

    func effectivePageNumberFontSize(isPageNumberFontUnlocked: Bool) -> CGFloat {
        if isPageNumberFontUnlocked {
            return max(settings.pageNumberSize, 6)
        }

        return max(EditorSettings.default.pageNumberSize, 6)
    }

    func pageNumberOrigin(textSize: CGSize, isPageNumberFontUnlocked: Bool) -> CGPoint {
        switch effectivePageNumberPosition(isPageNumberFontUnlocked: isPageNumberFontUnlocked) {
        case .hidden:
            return .zero
        case .center:
            return CGPoint(
                x: bodyFrame.midX - textSize.width / 2,
                y: pageNumberY(textHeight: textSize.height)
            )
        case .outside:
            let rawX = isOddPage ? bodyFrame.minX : bodyFrame.maxX - textSize.width
            return CGPoint(
                x: clampedFooterX(rawX, textWidth: textSize.width),
                y: pageNumberY(textHeight: textSize.height)
            )
        }
    }

    func poweredByHonkumiOrigin(
        textSize: CGSize,
        pageNumberTextSize: CGSize?
    ) -> CGPoint {
        let maxY = pageHeight - Self.poweredByBottomInset - textSize.height
        let pageNumberBottom = pageNumberTextSize.map {
            pageNumberY(textHeight: $0.height) + $0.height
        }
        let minY = pageNumberBottom.map {
            $0 + Self.footerItemGap
        } ?? bodyFrame.maxY + Self.poweredByBodyGap
        let y = max(maxY, minY)

        return CGPoint(
            x: pageWidth / 2 - textSize.width / 2,
            y: clampedFooterY(y, textHeight: textSize.height, bottomInset: Self.poweredByBottomInset)
        )
    }

    private func pageNumberY(textHeight: CGFloat) -> CGFloat {
        let preferredY = bodyFrame.maxY + Self.pageNumberBodyGap
        return clampedFooterY(preferredY, textHeight: textHeight, bottomInset: Self.pageNumberBottomInset)
    }

    private func clampedFooterY(
        _ y: CGFloat,
        textHeight: CGFloat,
        bottomInset: CGFloat
    ) -> CGFloat {
        let minY = bodyFrame.maxY + Self.minimumFooterBodyGap
        let maxY = pageHeight - textHeight - bottomInset
        guard minY <= maxY else {
            return max(Self.minimumPageEdgeInset, maxY)
        }

        return min(max(y, minY), maxY)
    }

    private func clampedFooterX(_ x: CGFloat, textWidth: CGFloat) -> CGFloat {
        let inset = Self.minimumPageEdgeInset
        let maxX = pageWidth - textWidth - inset
        return min(x, max(inset, maxX))
    }

    static let poweredByHonkumiFontSize: CGFloat = 7

    private static let minimumFooterBodyGap = LayoutCalculator.millimetersToPoints(4)
    private static let pageNumberBodyGap = LayoutCalculator.millimetersToPoints(4.5)
    private static let poweredByBodyGap = LayoutCalculator.millimetersToPoints(7)
    private static let footerItemGap = LayoutCalculator.millimetersToPoints(1.6)
    private static let minimumPageEdgeInset = LayoutCalculator.millimetersToPoints(3)
    private static let pageNumberBottomInset = LayoutCalculator.millimetersToPoints(4)
    private static let poweredByBottomInset = LayoutCalculator.millimetersToPoints(2)
}
