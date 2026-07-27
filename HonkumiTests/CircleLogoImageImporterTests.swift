@testable import Honkumi
import UIKit
import XCTest

final class CircleLogoImageImporterTests: XCTestCase {
    func testValidatedImageDataAcceptsPNGData() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let data = try XCTUnwrap(image.pngData())

        XCTAssertEqual(
            try CircleLogoImageImporter.validatedImageData(data),
            data
        )
    }

    func testValidatedImageDataRejectsNonImageBytes() {
        XCTAssertThrowsError(
            try CircleLogoImageImporter.validatedImageData(Data("not an image".utf8))
        ) { error in
            XCTAssertEqual(error as? CircleLogoImageImportError, .invalidImage)
        }
    }

    func testLoadImageDataCopiesBytesFromFile() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(
            try CircleLogoImageImporter.loadImageData(from: url),
            data
        )
    }
}
