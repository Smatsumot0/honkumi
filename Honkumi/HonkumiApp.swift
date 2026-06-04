import SwiftUI

@main
struct HonkumiApp: App {
    @StateObject private var documentStore = DocumentStore()

    var body: some Scene {
        WindowGroup {
            ContentView(documentStore: documentStore)
        }
    }
}
