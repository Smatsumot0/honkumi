import Foundation
import UIKit
import UniformTypeIdentifiers
import WebKit

nonisolated enum CircleLogoImageImportError: LocalizedError, Equatable {
    case invalidImage
    case invalidSVG
    case svgConversionFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "選択したファイルを画像として読み込めませんでした。"
        case .invalidSVG:
            return "選択したSVGのサイズまたは内容を読み込めませんでした。"
        case .svgConversionFailed:
            return "選択したSVGをPNG画像へ変換できませんでした。"
        }
    }
}

nonisolated enum CircleLogoImageImporter {
    private static let maximumSVGPixelDimension: CGFloat = 2048

    static func validatedImageData(_ data: Data) throws -> Data {
        guard UIImage(data: data) != nil else {
            throw CircleLogoImageImportError.invalidImage
        }

        return data
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain &&
            error.code == CocoaError.Code.userCancelled.rawValue
    }

    static func importedImageData(
        _ data: Data,
        contentType: UTType?
    ) async throws -> Data {
        if contentType?.conforms(to: .svg) == true {
            return try await pngData(fromSVG: data)
        }
        return try validatedImageData(data)
    }

    static func loadImageData(from url: URL) async throws -> Data {
        let hasSecurityScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        let values = try? url.resourceValues(forKeys: [.contentTypeKey])
        let filenameType = UTType(
            filenameExtension: url.pathExtension.lowercased()
        )
        let contentType =
            filenameType?.conforms(to: .svg) == true
                ? filenameType
                : values?.contentType ?? filenameType
        return try await importedImageData(data, contentType: contentType)
    }

    private static func pngData(fromSVG data: Data) async throws -> Data {
        try await CircleLogoSVGRenderer.pngData(
            from: data,
            maximumPixelDimension: maximumSVGPixelDimension
        )
    }
}

@MainActor
private final class CircleLogoSVGRenderer: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var loadingContinuation: CheckedContinuation<Void, Error>?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 1, height: 1),
            configuration: configuration
        )
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInset = .zero
        webView.scrollView.isScrollEnabled = false
        super.init()
        webView.navigationDelegate = self
    }

    static func pngData(
        from data: Data,
        maximumPixelDimension: CGFloat
    ) async throws -> Data {
        let renderer = CircleLogoSVGRenderer()
        return try await renderer.render(
            data,
            maximumPixelDimension: maximumPixelDimension
        )
    }

    private func render(
        _ data: Data,
        maximumPixelDimension: CGFloat
    ) async throws -> Data {
        let sourceSize = try CircleLogoSVGSizeParser.size(from: data)
        try await load(data)
        let scale = maximumPixelDimension /
            max(sourceSize.width, sourceSize.height)
        let pixelWidth = max(
            Int((sourceSize.width * scale).rounded()),
            1
        )
        let pixelHeight = max(
            Int((sourceSize.height * scale).rounded()),
            1
        )
        let targetSize = CGSize(width: pixelWidth, height: pixelHeight)
        webView.frame = CGRect(origin: .zero, size: targetSize)
        webView.setNeedsLayout()
        webView.layoutIfNeeded()

        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(origin: .zero, size: targetSize)
        configuration.snapshotWidth = NSNumber(value: pixelWidth)
        let snapshot = try await webView.takeSnapshot(
            configuration: configuration
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let rendered = UIGraphicsImageRenderer(
            size: targetSize,
            format: format
        ).image { _ in
            snapshot.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let pngData = rendered.pngData(),
              let image = UIImage(data: pngData)?.cgImage,
              image.width == pixelWidth,
              image.height == pixelHeight else {
            throw CircleLogoImageImportError.svgConversionFailed
        }
        return pngData
    }

    private func load(_ data: Data) async throws {
        let encodedSVG = data.base64EncodedString()
        let html = """
        <!doctype html>
        <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta http-equiv="Content-Security-Policy"
                  content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">
            <style>
              html, body {
                margin: 0;
                width: 100%;
                height: 100%;
                overflow: hidden;
                background: transparent;
              }
              #logo {
                display: block;
                width: 100%;
                height: 100%;
                object-fit: contain;
              }
            </style>
          </head>
          <body>
            <img id="logo" src="data:image/svg+xml;base64,\(encodedSVG)">
          </body>
        </html>
        """

        try await withCheckedThrowingContinuation { continuation in
            loadingContinuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        finishLoading(with: .success(()))
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        finishLoading(with: .failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finishLoading(with: .failure(error))
    }

    private func finishLoading(with result: Result<Void, Error>) {
        guard let continuation = loadingContinuation else { return }
        loadingContinuation = nil
        continuation.resume(with: result)
    }
}

@MainActor
private final class CircleLogoSVGSizeParser: NSObject, XMLParserDelegate {
    private enum RootDimension: Equatable {
        case absolute(CGFloat)
        case relative
        case unspecified
        case invalid

        var absoluteValue: CGFloat? {
            guard case let .absolute(value) = self else { return nil }
            return value
        }
    }

    private var rootSize: CGSize?
    private var foundSVGRoot = false

    static func size(from data: Data) throws -> CGSize {
        let delegate = CircleLogoSVGSizeParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false

        guard parser.parse(),
              delegate.foundSVGRoot,
              let size = delegate.rootSize else {
            throw CircleLogoImageImportError.invalidSVG
        }
        return size
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard !foundSVGRoot else { return }
        foundSVGRoot = true
        guard elementName.split(separator: ":").last == "svg" else {
            return
        }

        let viewBoxSize = Self.viewBoxSize(attributeDict["viewBox"])
        let width = Self.rootDimension(attributeDict["width"])
        let height = Self.rootDimension(attributeDict["height"])

        guard width != .invalid, height != .invalid else { return }

        switch (width.absoluteValue, height.absoluteValue, viewBoxSize) {
        case let (.some(width), .some(height), _):
            rootSize = CGSize(width: width, height: height)
        case let (.some(width), nil, .some(viewBox)):
            rootSize = CGSize(
                width: width,
                height: width * viewBox.height / viewBox.width
            )
        case let (nil, .some(height), .some(viewBox)):
            rootSize = CGSize(
                width: height * viewBox.width / viewBox.height,
                height: height
            )
        case let (nil, nil, .some(viewBox)):
            rootSize = viewBox
        default:
            break
        }
    }

    private static func rootDimension(_ value: String?) -> RootDimension {
        guard let value else { return .unspecified }
        let scanner = Scanner(string: value)
        scanner.locale = Locale(identifier: "en_US_POSIX")
        guard let number = scanner.scanDouble(),
              number.isFinite,
              number > 0 else {
            return .invalid
        }
        let suffix = value[scanner.currentIndex...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if suffix == "%" {
            return .relative
        }

        let multiplier: Double
        switch suffix {
        case "", "px":
            multiplier = 1
        case "pt":
            multiplier = 96 / 72
        case "pc":
            multiplier = 16
        case "in":
            multiplier = 96
        case "cm":
            multiplier = 96 / 2.54
        case "mm":
            multiplier = 96 / 25.4
        case "q":
            multiplier = 96 / 101.6
        default:
            return .invalid
        }
        let result = number * multiplier
        guard result.isFinite, result > 0 else { return .invalid }
        return .absolute(CGFloat(result))
    }

    private static func viewBoxSize(_ value: String?) -> CGSize? {
        guard let value else { return nil }
        let values = value
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Double($0) }
        guard values.count == 4,
              values.allSatisfy(\.isFinite),
              values[2] > 0,
              values[3] > 0 else {
            return nil
        }
        return CGSize(width: values[2], height: values[3])
    }
}
