import SwiftUI

@main
struct EvolvApp: App {
    @State private var appState = AppState()
    @State private var pilotSharing = PilotSubmissionCoordinator.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .tint(EvolvTheme.accent)
                .task {
                    await pilotSharing.retryPending()
                }
        }
    }
}
