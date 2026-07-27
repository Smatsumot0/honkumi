import CoreGraphics
import Foundation

nonisolated enum ManuscriptTextEditorNavigation {
    static func bottomSelectionRange(for text: String) -> NSRange {
        NSRange(location: (text as NSString).length, length: 0)
    }

    static func maximumContentOffsetY(
        contentHeight: CGFloat,
        viewportHeight: CGFloat,
        adjustedInsetTop: CGFloat,
        adjustedInsetBottom: CGFloat
    ) -> CGFloat {
        max(
            -adjustedInsetTop,
            contentHeight - viewportHeight + adjustedInsetBottom
        )
    }
}
