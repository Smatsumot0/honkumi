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
        return settings.pageNumberPosition == .hidden ? .hidden : .outside
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

    private func pageNumberY(textHeight: CGFloat) -> CGFloat {
        let rawY = pageHeight - marginBottom * 1.02 - textHeight * 0.15
        return clampedFooterY(rawY, textHeight: textHeight)
    }

    private func clampedFooterY(_ y: CGFloat, textHeight: CGFloat) -> CGFloat {
        let inset: CGFloat = 2
        let maxY = pageHeight - textHeight - inset
        return min(y, max(inset, maxY))
    }

    private func clampedFooterX(_ x: CGFloat, textWidth: CGFloat) -> CGFloat {
        let inset: CGFloat = 2
        let maxX = pageWidth - textWidth - inset
        return min(x, max(inset, maxX))
    }
}
