import Foundation

nonisolated struct UserDefaultSettingsReviewRequest:
    Identifiable,
    Equatable {
    let workID: UUID
    let revision: Int

    var id: UUID {
        workID
    }
}

nonisolated enum UserDefaultSettingsReviewDecision: Equatable {
    case apply
    case keepCurrent
}

nonisolated struct WorkSelectionResult: Equatable {
    let didSelect: Bool
    let shouldFormat: Bool

    static let unchanged = WorkSelectionResult(
        didSelect: false,
        shouldFormat: false
    )
}
