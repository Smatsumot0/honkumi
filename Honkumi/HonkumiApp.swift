import SwiftUI

@main
struct HonkumiApp: App {
    @StateObject private var documentStore = DocumentStore()

    init() {
        AppFontCatalog.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(documentStore: documentStore)
        }
    }
}
