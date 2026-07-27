import Foundation
import UIKit

nonisolated enum CircleLogoImageImportError: LocalizedError, Equatable {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "選択したファイルを画像として読み込めませんでした。"
        }
    }
}

nonisolated enum CircleLogoImageImporter {
    static func validatedImageData(_ data: Data) throws -> Data {
        guard UIImage(data: data) != nil else {
            throw CircleLogoImageImportError.invalidImage
        }

        return data
    }

    static func loadImageData(from url: URL) throws -> Data {
        let hasSecurityScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try validatedImageData(Data(contentsOf: url))
    }
}
