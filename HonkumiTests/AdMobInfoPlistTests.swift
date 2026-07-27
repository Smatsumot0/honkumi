import Foundation
@testable import Honkumi
import XCTest

final class AdMobInfoPlistTests: XCTestCase {
    func testReleaseUsesProductionAdMobIDs() throws {
        let release = try loadConfig(named: "AdMob-Release.xcconfig")

        XCTAssertTrue(
            release.contains(
                "ADMOB_APPLICATION_ID = ca-app-pub-5962190341183783~5710900326"
            )
        )
        XCTAssertTrue(
            release.contains(
                "ADMOB_INTERSTITIAL_AD_UNIT_ID = ca-app-pub-5962190341183783/4969764372"
            )
        )
        XCTAssertFalse(release.contains("ADS_TEST_MODE"))
    }

    func testDebugAndStagingKeepOfficialTestIDsAndTestMode() throws {
        for name in ["AdMob-Debug.xcconfig", "AdMob-Staging.xcconfig"] {
            let config = try loadConfig(named: name)

            XCTAssertTrue(config.contains(PDFExportAdConfiguration.officialTestApplicationID))
            XCTAssertTrue(config.contains(PDFExportAdConfiguration.officialTestInterstitialAdUnitID))
            XCTAssertTrue(config.contains("-D ADS_TEST_MODE"))
            XCTAssertFalse(config.contains("5962190341183783"))
        }
    }

    func testInfoPlistIncludesGoogleAdMobSKAdNetworkIdentifiers() throws {
        let plist = try loadInfoPlist()
        let items = try XCTUnwrap(plist["SKAdNetworkItems"] as? [[String: String]])
        let identifiers = Set(items.compactMap { $0["SKAdNetworkIdentifier"] })

        XCTAssertEqual(identifiers.count, items.count)
        XCTAssertEqual(identifiers, Set(identifiers.map { $0.lowercased() }))

        let expectedIdentifiers: Set<String> = [
            "cstr6suwn9.skadnetwork",
            "4fzdc2evr5.skadnetwork",
            "2fnua5tdw4.skadnetwork",
            "ydx93a7ass.skadnetwork",
            "p78axxw29g.skadnetwork",
            "v72qych5uu.skadnetwork",
            "ludvb6z3bs.skadnetwork",
            "cp8zw746q7.skadnetwork",
            "3sh42y64q3.skadnetwork",
            "c6k4g5qg8m.skadnetwork",
            "s39g8k73mm.skadnetwork",
            "wg4vff78zm.skadnetwork",
            "3qy4746246.skadnetwork",
            "f38h382jlk.skadnetwork",
            "hs6bdukanm.skadnetwork",
            "mlmmfzh3r3.skadnetwork",
            "v4nxqhlyqp.skadnetwork",
            "wzmmz9fp6w.skadnetwork",
            "su67r6k2v3.skadnetwork",
            "yclnxrl5pm.skadnetwork",
            "t38b2kh725.skadnetwork",
            "7ug5zh24hu.skadnetwork",
            "gta9lk7p23.skadnetwork",
            "vutu7akeur.skadnetwork",
            "y5ghdn5j9k.skadnetwork",
            "v9wttpbfk9.skadnetwork",
            "n38lu8286q.skadnetwork",
            "47vhws6wlr.skadnetwork",
            "kbd757ywx3.skadnetwork",
            "9t245vhmpl.skadnetwork",
            "a2p9lx4jpn.skadnetwork",
            "22mmun2rn5.skadnetwork",
            "44jx6755aq.skadnetwork",
            "k674qkevps.skadnetwork",
            "4468km3ulz.skadnetwork",
            "2u9pt9hc89.skadnetwork",
            "8s468mfl3y.skadnetwork",
            "klf5c3l5u5.skadnetwork",
            "ppxm28t8ap.skadnetwork",
            "kbmxgpxpgc.skadnetwork",
            "uw77j35x4d.skadnetwork",
            "578prtvx9j.skadnetwork",
            "4dzt52r2t5.skadnetwork",
            "tl55sbb4fm.skadnetwork",
            "c3frkrj4fj.skadnetwork",
            "e5fvkxwrpn.skadnetwork",
            "8c4e2ghe7u.skadnetwork",
            "3rd42ekr43.skadnetwork",
            "97r2b46745.skadnetwork",
            "3qcr597p9d.skadnetwork"
        ]

        XCTAssertTrue(
            identifiers.isSuperset(of: expectedIdentifiers),
            "Missing SKAdNetwork identifiers: \(expectedIdentifiers.subtracting(identifiers).sorted())"
        )
    }

    private func loadInfoPlist() throws -> [String: Any] {
        let plistURL = projectRoot
            .appendingPathComponent("Honkumi")
            .appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: plistURL)
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(object as? [String: Any])
    }

    private func loadConfig(named name: String) throws -> String {
        let url = projectRoot
            .appendingPathComponent("Honkumi")
            .appendingPathComponent("Config")
            .appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
