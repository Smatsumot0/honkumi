@testable import Honkumi
import UIKit
import UniformTypeIdentifiers
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

    func testLoadImageDataCopiesBytesFromFile() async throws {
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

        let loadedData = try await CircleLogoImageImporter.loadImageData(
            from: url
        )
        XCTAssertEqual(loadedData, data)
    }

    func testImportedRasterImageKeepsOriginalBytes() async throws {
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 4, height: 3)
        ).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        }
        let data = try XCTUnwrap(
            image.jpegData(compressionQuality: 0.77)
        )

        let importedData = try await CircleLogoImageImporter.importedImageData(
            data,
            contentType: .jpeg
        )
        XCTAssertEqual(importedData, data)
    }

    func testSVGConvertsToPNGWith2048PixelLongEdge() async throws {
        let data = Data(Self.transparentSVG.utf8)

        let pngData = try await CircleLogoImageImporter.importedImageData(
            data,
            contentType: .svg
        )
        let image = try XCTUnwrap(UIImage(data: pngData))
        let cgImage = try XCTUnwrap(image.cgImage)

        XCTAssertEqual(cgImage.width, 1024)
        XCTAssertEqual(cgImage.height, 2048)
        XCTAssertEqual(
            Array(pngData.prefix(8)),
            [137, 80, 78, 71, 13, 10, 26, 10]
        )
        XCTAssertTrue(
            [
                CGImageAlphaInfo.premultipliedFirst,
                .premultipliedLast,
                .first,
                .last
            ].contains(cgImage.alphaInfo)
        )
    }

    func testExtremeSVGAspectRatioKeepsShortEdgeAtLeastOnePixel() async throws {
        let data = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" width="1" height="100000">
          <rect width="1" height="100000" fill="#000000"/>
        </svg>
        """.utf8)

        let pngData = try await CircleLogoImageImporter.importedImageData(
            data,
            contentType: .svg
        )
        let cgImage = try XCTUnwrap(UIImage(data: pngData)?.cgImage)

        XCTAssertEqual(cgImage.width, 1)
        XCTAssertEqual(cgImage.height, 2048)
    }

    func testInvalidSVGThrowsSpecificImportError() async {
        do {
            _ = try await CircleLogoImageImporter.importedImageData(
                Data("<svg width=\"0\" height=\"0\"></svg>".utf8),
                contentType: .svg
            )
            XCTFail("Expected invalid SVG to throw")
        } catch {
            XCTAssertEqual(
                error as? CircleLogoImageImportError,
                .invalidSVG
            )
        }
    }

    private static let transparentSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="10" height="20">
      <rect x="0" y="0" width="5" height="20" fill="#000000"/>
    </svg>
    """
}
