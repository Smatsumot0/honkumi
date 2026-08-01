import CoreGraphics
import Foundation
@testable import Honkumi
import XCTest

final class PageNumberSizeSettingsTests: XCTestCase {
    func testTableOfContentsPageNumberSizeDefaultsToNinePoints() {
        XCTAssertEqual(EditorSettings.default.tableOfContentsPageNumberSize, 9)
    }

    func testTableOfContentsPageNumberSizeRoundTripsAndValidates() throws {
        var settings = EditorSettings.default
        settings.tableOfContentsPageNumberSize = 10.5

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(EditorSettings.self, from: encoded)

        XCTAssertEqual(decoded.tableOfContentsPageNumberSize, 10.5)

        settings.tableOfContentsPageNumberSize = 99
        XCTAssertEqual(settings.validated.tableOfContentsPageNumberSize, 18)

        settings.tableOfContentsPageNumberSize = 1
        XCTAssertEqual(settings.validated.tableOfContentsPageNumberSize, 6)
    }

    func testMissingTableOfContentsPageNumberSizeMigratesFromBodySize() throws {
        var legacySettings = EditorSettings.default
        legacySettings.fontSize = 12.5
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(legacySettings)
            ) as? [String: Any]
        )
        object.removeValue(forKey: "tableOfContentsPageNumberSize")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let migrated = try JSONDecoder().decode(EditorSettings.self, from: legacyData)

        XCTAssertEqual(migrated.tableOfContentsPageNumberSize, 12.5)
    }

    func testMigratedBodySizeIsClampedToTableOfContentsRange() throws {
        var legacySettings = EditorSettings.default
        legacySettings.fontSize = 20
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(legacySettings)
            ) as? [String: Any]
        )
        object.removeValue(forKey: "tableOfContentsPageNumberSize")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let migrated = try JSONDecoder().decode(EditorSettings.self, from: legacyData)

        XCTAssertEqual(migrated.tableOfContentsPageNumberSize, 18)
    }

    func testMigratedBodySizeBelowTableOfContentsRangeIsClampedToMinimum() throws {
        var legacySettings = EditorSettings.default
        legacySettings.fontSize = 5
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(legacySettings)
            ) as? [String: Any]
        )
        object.removeValue(forKey: "tableOfContentsPageNumberSize")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let migrated = try JSONDecoder().decode(EditorSettings.self, from: legacyData)

        XCTAssertEqual(migrated.tableOfContentsPageNumberSize, 6)
    }
}
