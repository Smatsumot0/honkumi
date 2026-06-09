import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PDFPageRenderer {
    static func run() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 4 else {
            fputs("Usage: render-pdf-pages <pdf-path> <output-directory> <comma-separated-pages>\n", stderr)
            Foundation.exit(2)
        }

        let pdfURL = URL(fileURLWithPath: arguments[1])
        let outputDirectoryURL = URL(fileURLWithPath: arguments[2], isDirectory: true)
        let pageNumbers = arguments[3]
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard !pageNumbers.isEmpty else {
            fputs("No pages requested.\n", stderr)
            Foundation.exit(2)
        }

        guard let document = CGPDFDocument(pdfURL as CFURL) else {
            fputs("Could not open PDF: \(pdfURL.path)\n", stderr)
            Foundation.exit(1)
        }

        try FileManager.default.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true)

        for pageNumber in pageNumbers {
            guard pageNumber >= 1, pageNumber <= document.numberOfPages,
                  let page = document.page(at: pageNumber) else {
                fputs("Skipping unavailable page \(pageNumber); PDF has \(document.numberOfPages) pages.\n", stderr)
                continue
            }

            let outputURL = outputDirectoryURL
                .appendingPathComponent("page-\(String(format: "%03d", pageNumber))")
                .appendingPathExtension("png")
            try render(page: page, to: outputURL)
            print(outputURL.path)
        }
    }

    private static func render(page: CGPDFPage, to outputURL: URL) throws {
        let scale: CGFloat = 3
        let mediaBox = page.getBoxRect(.mediaBox)
        let pixelWidth = max(Int((mediaBox.width * scale).rounded(.up)), 1)
        let pixelHeight = max(Int((mediaBox.height * scale).rounded(.up)), 1)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw RenderError.couldNotCreateContext
        }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -mediaBox.minX, y: -mediaBox.minY)
        context.drawPDFPage(page)

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                outputURL as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
              ) else {
            throw RenderError.couldNotCreateImage
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw RenderError.couldNotWriteImage
        }
    }

    private enum RenderError: Error {
        case couldNotCreateContext
        case couldNotCreateImage
        case couldNotWriteImage
    }
}

do {
    try PDFPageRenderer.run()
} catch {
    fputs("PDF page rendering failed: \(error)\n", stderr)
    Foundation.exit(1)
}
