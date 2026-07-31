import Foundation
import UniformTypeIdentifiers

nonisolated enum CircleLogoImportCopy {
    static let sourceTitle = "サークルロゴの選択方法"
    static let sourceMessage = "アップロード元を選択してください。"
    static let uploadButton = "アップロード"
    static let photoSource = "写真から選択"
    static let fileSource = "ファイルから選択"
    static let cancel = "キャンセル"
}

nonisolated enum CircleLogoImportFileTypes {
    static let allowed: [UTType] = [.image, .svg]
}

nonisolated struct CircleLogoImportPresentation: Equatable {
    enum Destination: Equatable {
        case sourceChooser
        case photoLibrary
        case fileImporter
    }

    private(set) var destination: Destination?

    mutating func present(_ destination: Destination) {
        self.destination = destination
    }

    mutating func dismiss(_ destination: Destination) {
        guard self.destination == destination else { return }
        self.destination = nil
    }

    func isPresented(_ destination: Destination) -> Bool {
        self.destination == destination
    }
}
