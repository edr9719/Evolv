import SwiftUI
import UIKit

@main
struct EvolvApp: App {
    @State private var appState: AppState
    @State private var pilotSharing: PilotSubmissionCoordinator

    init() {
        let state = AppState()
        let pilot = PilotSubmissionCoordinator.shared
        #if DEBUG
        EvolvUITestBootstrap.applyIfRequested(to: state, pilot: pilot)
        #endif
        _appState = State(initialValue: state)
        _pilotSharing = State(initialValue: pilot)
    }

    var body: some Scene {
        WindowGroup {
            PrivacyProtectedRoot {
                ContentView()
            }
                .environment(appState)
                .preferredColorScheme(.dark)
                .tint(EvolvTheme.accent)
                .task {
                    await pilotSharing.retryPending()
                }
        }
    }
}

/// Keeps physique photos out of the app-switcher snapshot and tells the user
/// when iOS reports active screen recording or mirroring. iOS does not provide
/// a reliable way to prevent screenshots, so Evolv never claims that it does.
private struct PrivacyProtectedRoot<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isScreenCaptured = false
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
                .privacySensitive()

            if scenePhase != .active {
                ZStack {
                    EvolvTheme.background.ignoresSafeArea()
                    VStack(spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(EvolvTheme.accent)
                        Text("Evolv is private")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(EvolvTheme.text)
                    }
                }
                .transition(.opacity)
                .zIndex(10)
            } else if isScreenCaptured {
                VStack {
                    Label("Screen recording or mirroring is active", systemImage: "record.circle")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.red.opacity(0.88)))
                        .padding(.top, 8)
                    Spacer()
                }
                .allowsHitTesting(false)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(9)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: scenePhase)
        .animation(.easeInOut(duration: 0.18), value: isScreenCaptured)
        .background(SceneCaptureObserver(isCaptured: $isScreenCaptured))
    }
}

/// Uses the scene-scoped capture trait recommended by UIKit. Unlike the
/// deprecated UIScreen flag, this follows the actual app scene on iPad and in
/// multi-window environments.
private struct SceneCaptureObserver: UIViewControllerRepresentable {
    @Binding var isCaptured: Bool

    func makeUIViewController(context: Context) -> ObserverViewController {
        let controller = ObserverViewController()
        controller.onChange = { captured in
            if isCaptured != captured { isCaptured = captured }
        }
        return controller
    }

    func updateUIViewController(_ controller: ObserverViewController, context: Context) {
        controller.onChange = { captured in
            if isCaptured != captured { isCaptured = captured }
        }
    }

    final class ObserverViewController: UIViewController {
        var onChange: ((Bool) -> Void)?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.isHidden = true
            registerForTraitChanges([UITraitSceneCaptureState.self]) {
                (controller: ObserverViewController, _) in
                controller.reportCaptureState()
            }
        }

        override func viewIsAppearing(_ animated: Bool) {
            super.viewIsAppearing(animated)
            reportCaptureState()
        }

        func reportCaptureState() {
            let captured = traitCollection.sceneCaptureState == .active
            guard Thread.isMainThread else {
                DispatchQueue.main.async { [weak self] in self?.onChange?(captured) }
                return
            }
            onChange?(captured)
        }
    }
}
