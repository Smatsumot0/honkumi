@testable import Honkumi
import XCTest

final class CommonSettingsRevisionCodingTests: XCTestCase {
    func testLegacyAppDataWithoutRevisionDecodesAsZero() throws {
        let document = ManuscriptDocument(title: "Legacy", body: "本文")
        let appData = AppData(
            version: 1,
            categories: [.uncategorized],
            works: [document],
            userDefaultSettings: .default,
            activeWorkId: document.id,
            subscriptionStatus: .free
        )
        let legacyData = try removingKeys(
            ["userDefaultSettingsRevision"],
            from: JSONEncoder().encode(appData)
        )

        let decoded = try JSONDecoder().decode(AppData.self, from: legacyData)

        XCTAssertEqual(decoded.userDefaultSettingsRevision, 0)
    }

    func testLegacyWorkWithoutReviewedRevisionDecodesAsZero() throws {
        let document = ManuscriptDocument(title: "Legacy", body: "本文")
        let legacyData = try removingKeys(
            ["reviewedUserDefaultSettingsRevision"],
            from: JSONEncoder().encode(document)
        )

        let decoded = try JSONDecoder().decode(
            ManuscriptDocument.self,
            from: legacyData
        )

        XCTAssertEqual(decoded.reviewedUserDefaultSettingsRevision, 0)
    }

    func testRevisionFieldsRoundTrip() throws {
        let document = ManuscriptDocument(
            title: "Current",
            body: "本文",
            reviewedUserDefaultSettingsRevision: 7
        )
        let appData = AppData(
            version: AppData.currentVersion,
            categories: [.uncategorized],
            works: [document],
            userDefaultSettings: .default,
            activeWorkId: document.id,
            subscriptionStatus: .free,
            userDefaultSettingsRevision: 9
        )

        let decoded = try JSONDecoder().decode(
            AppData.self,
            from: JSONEncoder().encode(appData)
        )

        XCTAssertEqual(decoded.userDefaultSettingsRevision, 9)
        XCTAssertEqual(
            decoded.works.first?.reviewedUserDefaultSettingsRevision,
            7
        )
    }

    private func removingKeys(_ keys: [String], from data: Data) throws -> Data {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        for key in keys {
            object.removeValue(forKey: key)
        }
        if var works = object["works"] as? [[String: Any]] {
            for index in works.indices {
                for key in keys {
                    works[index].removeValue(forKey: key)
                }
            }
            object["works"] = works
        }
        return try JSONSerialization.data(withJSONObject: object)
    }
}
