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

nonisolated struct UserDefaultSettingsSelection: Equatable {
    var editor: Bool
    var circle: Bool
    var format: Bool
    var print: Bool

    init(
        editor: Bool = false,
        circle: Bool = false,
        format: Bool = false,
        print: Bool = false
    ) {
        self.editor = editor
        self.circle = circle
        self.format = format
        self.print = print
    }

    static let all = UserDefaultSettingsSelection(
        editor: true,
        circle: true,
        format: true,
        print: true
    )

    var isEmpty: Bool {
        !editor && !circle && !format && !print
    }
}

nonisolated enum UserDefaultSettingsReviewDecision: Equatable {
    case apply(UserDefaultSettingsSelection)
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
