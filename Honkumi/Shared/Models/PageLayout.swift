import CoreGraphics
import Foundation

struct PageLayout: Equatable {
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
}
