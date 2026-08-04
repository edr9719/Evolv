import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Group {
            Group {
                if !app.hasCompletedOnboarding {
                    OnboardingFlowView()
                } else if !app.profile.hasSeenPostOnboardingPaywall {
                    PaywallView(context: .postOnboarding)
                        .transition(.opacity)
                } else {
                    RootTabView()
                }
            }
            .animation(.easeInOut(duration: 0.35), value: app.hasCompletedOnboarding)
            .animation(.easeInOut(duration: 0.35), value: app.profile.hasSeenPostOnboardingPaywall)
        }
        .trackView("ContentView")
    }
}

struct RootTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
            CaptureLaunchView()
                .tabItem { Label("Scan", systemImage: "viewfinder") }
            TimelineView()
                .tabItem { Label("Timeline", systemImage: "rectangle.stack") }
        }
        .tint(EvolvTheme.accent)
    }
}

#Preview {
    ContentView().environment(AppState())
}
