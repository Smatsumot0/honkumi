import Foundation

enum ProEntitlementState: Equatable {
    case unknown
    case free
    case pro

    var isProUnlocked: Bool {
        self == .pro
    }
}
