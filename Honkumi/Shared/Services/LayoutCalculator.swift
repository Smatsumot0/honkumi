import CoreGraphics
import Foundation

nonisolated enum LayoutCalculator {
    static let millimetersPerInch: CGFloat = 25.4
    static let pointsPerInch: CGFloat = 72

    static func millimetersToPoints(_ millimeters: CGFloat) -> CGFloat {
        millimeters * pointsPerInch / millimetersPerInch
    }

    static func layout(for settings: EditorSettings, pageNumber: Int) -> PageLayout {
        let validatedSettings = settings.validated
        let pageWidth = millimetersToPoints(validatedSettings.pageSize.widthMillimeters)
        let pageHeight = millimetersToPoints(validatedSettings.pageSize.heightMillimeters)
        let marginTop = millimetersToPoints(validatedSettings.marginTop)
        let marginBottom = millimetersToPoints(validatedSettings.marginBottom)
        let marginInner = millimetersToPoints(validatedSettings.marginInner)
        let marginOuter = millimetersToPoints(validatedSettings.marginOuter)
        let bodyWidth = max(pageWidth - marginInner - marginOuter, 1)
        let bodyHeight = max(pageHeight - marginTop - marginBottom, 1)
        let isOddPage = pageNumber % 2 == 1
        let bodyX = isOddPage ? marginOuter : marginInner
        let bodyFrame = CGRect(x: bodyX, y: marginTop, width: bodyWidth, height: bodyHeight)
        let lineAdvance = bodyWidth / CGFloat(validatedSettings.linesPerPage)
        let characterAdvance = bodyHeight / CGFloat(validatedSettings.charactersPerLine)
        let fontSize = validatedFontSize(
            requestedFontSize: validatedSettings.fontSize,
            lineAdvance: lineAdvance,
            characterAdvance: characterAdvance
        )

        return PageLayout(
            pageNumber: pageNumber,
            pageSize: validatedSettings.pageSize,
            pageWidth: pageWidth,
            pageHeight: pageHeight,
            bodyFrame: bodyFrame,
            marginTop: marginTop,
            marginBottom: marginBottom,
            marginInner: marginInner,
            marginOuter: marginOuter,
            lineAdvance: lineAdvance,
            characterAdvance: characterAdvance,
            fontSize: fontSize,
            settings: validatedSettings
        )
    }

    private static func validatedFontSize(
        requestedFontSize: CGFloat,
        lineAdvance: CGFloat,
        characterAdvance: CGFloat
    ) -> CGFloat {
        let minimumFontSize = EditorSettings.fontSizeRange.lowerBound
        let smallestAdvance = min(lineAdvance, characterAdvance)
        let largestNaturalFontSize = smallestAdvance / 0.72
        let clampedNaturalFontSize = max(minimumFontSize, largestNaturalFontSize)

        return min(requestedFontSize, clampedNaturalFontSize)
    }
}
