import SwiftUI

@main
struct EvolvApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .tint(EvolvTheme.accent)
        }
    }
}
