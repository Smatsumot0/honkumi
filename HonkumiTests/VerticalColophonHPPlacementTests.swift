import CoreGraphics
@testable import Honkumi
import XCTest

final class VerticalColophonHPPlacementTests: XCTestCase {
    func testVisibleURLStartsAtValueOriginAndCentersQROverVisibleURL() {
        let placement = VerticalColophonHPPlacement.make(
            valueX: 100,
            availableWidth: 180,
            urlWidth: 120,
            qrSize: 40,
            bodyMinX: 20,
            bodyMaxX: 300
        )

        XCTAssertEqual(placement.urlX, 100, accuracy: 0.001)
        XCTAssertEqual(placement.qrX, 140, accuracy: 0.001)
        XCTAssertEqual(placement.qrX + 20, placement.urlX + 60, accuracy: 0.001)
    }

    func testLongURLUsesVisibleContainedWidthForQRCentering() {
        let placement = VerticalColophonHPPlacement.make(
            valueX: 100,
            availableWidth: 400,
            urlWidth: 600,
            qrSize: 40,
            bodyMinX: 20,
            bodyMaxX: 280
        )

        XCTAssertEqual(placement.urlX, 100, accuracy: 0.001)
        XCTAssertEqual(placement.qrX, 170, accuracy: 0.001)
        XCTAssertEqual(placement.qrX + 20, 190, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(placement.qrX, 20)
        XCTAssertLessThanOrEqual(placement.qrX + 40, 280)
    }

    func testShortURLKeepsQRCodeInsideValueOrigin() {
        let placement = VerticalColophonHPPlacement.make(
            valueX: 100,
            availableWidth: 180,
            urlWidth: 20,
            qrSize: 40,
            bodyMinX: 20,
            bodyMaxX: 300
        )

        XCTAssertEqual(placement.urlX, 100, accuracy: 0.001)
        XCTAssertEqual(placement.qrX, 100, accuracy: 0.001)
    }
}
