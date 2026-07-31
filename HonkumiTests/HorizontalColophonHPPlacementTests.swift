import CoreGraphics
@testable import Honkumi
import XCTest

final class HorizontalColophonHPPlacementTests: XCTestCase {
    func testVisibleURLStartsAtValueOriginAndCentersQROverURL() {
        let placement = HorizontalColophonHPPlacement.make(
            valueX: 100,
            availableWidth: 220,
            urlWidth: 140,
            qrSize: 44,
            showsURL: true,
            bodyMinX: 20,
            bodyMaxX: 340
        )

        XCTAssertEqual(placement.urlX, 100, accuracy: 0.001)
        XCTAssertEqual(placement.qrX, 148, accuracy: 0.001)
        XCTAssertEqual(placement.qrX + 22, placement.urlX + 70, accuracy: 0.001)
    }

    func testQROnlyCentersInValueColumn() {
        let placement = HorizontalColophonHPPlacement.make(
            valueX: 100,
            availableWidth: 220,
            urlWidth: 0,
            qrSize: 44,
            showsURL: false,
            bodyMinX: 20,
            bodyMaxX: 340
        )

        XCTAssertEqual(placement.urlX, 100, accuracy: 0.001)
        XCTAssertEqual(placement.qrX, 188, accuracy: 0.001)
    }

    func testCenteredQRIsClampedInsideBodyFrame() {
        let placement = HorizontalColophonHPPlacement.make(
            valueX: 30,
            availableWidth: 30,
            urlWidth: 4,
            qrSize: 44,
            showsURL: true,
            bodyMinX: 20,
            bodyMaxX: 340
        )

        XCTAssertEqual(placement.qrX, 20, accuracy: 0.001)
    }
}
