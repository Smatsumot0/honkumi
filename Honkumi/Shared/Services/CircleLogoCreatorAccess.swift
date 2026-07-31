import Foundation

nonisolated struct CircleLogoCreatorAccess: Equatable {
    private let isPaid: Bool
    private let usesCircleImageForCreator: Bool
    private let hasStoredImage: Bool

    init(colophon: ColophonSettings, isPaid: Bool) {
        self.isPaid = isPaid
        usesCircleImageForCreator = colophon.usesCircleImageForCreator
        hasStoredImage = colophon.circleImageData != nil
    }

    var isCreatorLogoActive: Bool {
        isPaid && usesCircleImageForCreator && hasStoredImage
    }

    var showsIdentityFields: Bool {
        !isCreatorLogoActive
    }

    func canSetUsage(to newValue: Bool) -> Bool {
        isPaid || !newValue
    }

    var canUpload: Bool {
        isPaid
    }

    var canDelete: Bool {
        hasStoredImage
    }

    var showsImportRow: Bool {
        usesCircleImageForCreator || hasStoredImage
    }
}
