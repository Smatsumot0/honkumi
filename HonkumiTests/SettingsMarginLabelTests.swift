import XCTest
@testable import Honkumi

final class SettingsMarginLabelTests: XCTestCase {
    func testPrintMarginLabelsDoNotIncludeYohakuSuffix() {
        XCTAssertEqual(PrintMarginDisplayLabel.top, "天")
        XCTAssertEqual(PrintMarginDisplayLabel.bottom, "地")
        XCTAssertEqual(PrintMarginDisplayLabel.outer, "小口")
        XCTAssertEqual(PrintMarginDisplayLabel.inner, "ノド")
    }
}
