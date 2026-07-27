import Foundation
@testable import Honkumi
import XCTest

final class PageSizeCompatibilityTests: XCTestCase {
    func testOnlySupportedPaperSizesAreSelectable() {
        XCTAssertEqual(PageSize.selectableCases, [.a6, .shinsho, .b6])
    }

    func testLegacyA5AndB5StillDecode() throws {
        XCTAssertEqual(
            try JSONDecoder().decode(PageSize.self, from: Data("\"A5\"".utf8)),
            .a5
        )
        XCTAssertEqual(
            try JSONDecoder().decode(PageSize.self, from: Data("\"B5\"".utf8)),
            .b5
        )
    }

    func testLegacySizesRetainDimensions() {
        XCTAssertEqual(PageSize.a5.widthMillimeters, 148)
        XCTAssertEqual(PageSize.b5.heightMillimeters, 257)
    }
}
