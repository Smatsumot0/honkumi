import Foundation

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
