import SwiftUI

@main
struct HonkumiApp: App {
    @StateObject private var documentStore = DocumentStore()
    @StateObject private var proStore = HonkumiProStore()

    init() {
        AppFontCatalog.registerBundledFonts()
        #if DEBUG
        VerticalTypesettingSamplePDFExporter.exportIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView(documentStore: documentStore, proStore: proStore)
        }
    }
}
