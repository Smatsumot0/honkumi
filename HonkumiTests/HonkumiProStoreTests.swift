import XCTest
@testable import Honkumi

final class HonkumiProStoreTests: XCTestCase {
    func testProProductIDMatchesAppStoreConnectIdentifier() {
        XCTAssertEqual(HonkumiProStore.productID, "app.honkumi.pro")
    }

    func testStoreKitConfigurationUsesProProductID() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRootURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let storeKitURL = projectRootURL
            .appendingPathComponent("Honkumi")
            .appendingPathComponent("Honkumi.storekit")
        let data = try Data(contentsOf: storeKitURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let products = try XCTUnwrap(json["products"] as? [[String: Any]])
        let productIDs = products.compactMap { $0["productID"] as? String }

        XCTAssertTrue(productIDs.contains(HonkumiProStore.productID))
        XCTAssertFalse(productIDs.contains("honkumi.pro"))
    }
}
