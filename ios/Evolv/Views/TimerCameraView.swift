import SwiftUI
import AVFoundation
import UIKit

enum CameraOperationState: Equatable {
    case preparing
    case ready
    case capturing
    case processing
    case completed
    case error(String)
}

struct CameraCaptureResult {
    let image: UIImage
    let metadata: CaptureCameraMetadata
}

enum CameraPreferenceStore {
    static let key = "evolv.preferredCameraPosition"

    static func load(from defaults: UserDefaults = .standard) -> CaptureCameraPosition {
        guard let rawValue = defaults.string(forKey: key),
              let stored = CaptureCameraPosition(rawValue: rawValue) else {
            return .front
        }
        return stored
    }

    static func save(
        _ position: CaptureCameraPosition,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(position.rawValue, forKey: key)
    }
}

/// Full-screen camera with an auto-shutter countdown timer (3 / 5 / 10 s) and
/// a manual shutter fallback. Designed for hands-free scan capture where the
/// user props their phone against a wall, taps the timer, then walks into frame.
struct TimerCameraView: View {
    @Environment(\.dismiss) private var dismiss
    let pose: Pose
    let previousPhoto: UIImage?
    let previousMetadata: CaptureCameraMetadata?
    let allowsCameraSwitch: Bool
    let onCaptured: (CameraCaptureResult) -> Void

    @StateObject private var camera: CameraController

    @State private var selectedSeconds: Int = 5
    @State private var countdown: Int? = nil
    @State private var isRunning: Bool = false
    @State private var permissionDenied: Bool = false
    @State private var flashOpacity: Double = 0
    @State private var showCaptureError: Bool = false
    @State private var captureWatchdog: Task<Void, Never>? = nil
    @State private var showPreviousOverlay: Bool

    private let timerOptions: [Int] = [3, 5, 10]

    init(
        pose: Pose,
        previousPhoto: UIImage? = nil,
        previousMetadata: CaptureCameraMetadata? = nil,
        preferredPosition: CaptureCameraPosition? = nil,
        allowsCameraSwitch: Bool = true,
        onCaptured: @escaping (CameraCaptureResult) -> Void
    ) {
        self.pose = pose
        self.previousPhoto = previousPhoto
        self.previousMetadata = previousMetadata
        self.allowsCameraSwitch = allowsCameraSwitch
        self.onCaptured = onCaptured
        _camera = StateObject(
            wrappedValue: CameraController(
                initialPosition: preferredPosition ?? CameraPreferenceStore.load(),
                requiresExactPosition: !allowsCameraSwitch
            )
        )
        _showPreviousOverlay = State(initialValue: previousPhoto != nil && previousMetadata != nil)
    }

    var body: some View {
        Group {
            ZStack {
                Color.black.ignoresSafeArea()
            
                CameraCompositePreview(
                    session: camera.session,
                    isMirrored: camera.activePosition == .front,
                    referenceImage: referenceOverlayIsCompatible ? previousPhoto : nil,
                    showsReference: showPreviousOverlay && referenceOverlayIsCompatible
                )
                    .ignoresSafeArea()
                    .opacity(camera.isReady ? 1 : 0)

                // Landmark zones communicate framing without asking the user
                // to match another person's proportions.
                PoseAlignmentGuide(pose: pose)
                    .padding(.horizontal, 38)
                    .padding(.top, 88)
                    .padding(.bottom, 208)
                    .allowsHitTesting(false)
            
                // White flash on capture
                Color.white.opacity(flashOpacity).ignoresSafeArea()
                    .allowsHitTesting(false)
            
                // Countdown overlay
                if let countdown {
                    Text("\(countdown)")
                        .font(.system(size: 140, weight: .light, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 18)
                        .transition(.scale(scale: 1.4).combined(with: .opacity))
                        .id(countdown)
                        .allowsHitTesting(false)
                }
            
            }
            .overlay(alignment: .top) {
                if !permissionDenied {
                    topBar
                        .safeAreaPadding(.top, 8)
                        .zIndex(20)
                }
            }
            .overlay(alignment: .bottom) {
                if !permissionDenied {
                    bottomControls
                        .zIndex(20)
                }
            }
            .overlay {
                if permissionDenied {
                    permissionView
                        .zIndex(30)
                }
            }
            .statusBarHidden()
            .preferredColorScheme(.dark)
            .onAppear {
                camera.start { ready in
                    guard !ready else { return }
                    let authorization = AVCaptureDevice.authorizationStatus(for: .video)
                    if authorization == .denied || authorization == .restricted {
                        permissionDenied = true
                    } else {
                        showCaptureError = true
                    }
                }
            }
            .onDisappear {
                captureWatchdog?.cancel()
                camera.stop()
                cancelCountdown()
            }
            .onChange(of: camera.operationState) { _, state in
                if case .error = state, !permissionDenied {
                    showCaptureError = true
                }
            }
            .alert("Couldn't capture photo", isPresented: $showCaptureError) {
                Button("Try Again") { camera.prepareForRetry() }
                Button("Cancel", role: .cancel) { dismiss() }
            } message: {
                Text(camera.errorMessage ?? "The camera couldn't finish processing the photo. Please try again.")
            }
        }
        .trackView("TimerCameraView")
    }

    // MARK: - Subviews

    private var topBar: some View {
        ZStack {
            VStack(spacing: 2) {
                Text("POSE")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.6))
                Text(pose.label)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
            }

            HStack {
                Button {
                    cancelCountdown()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(.black.opacity(0.66)))
                        .overlay(Circle().stroke(.white.opacity(0.28), lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close camera")

                Spacer()

                if allowsCameraSwitch {
                    Button {
                        cancelCountdown()
                        camera.switchCamera()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.system(size: 14, weight: .bold))
                            Text("Use \(camera.activePosition.opposite.label)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .frame(minWidth: 104, minHeight: 48)
                        .padding(.horizontal, 10)
                        .background(Capsule().fill(.black.opacity(0.66)))
                        .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Switch to \(camera.activePosition.opposite.label.lowercased()) camera")
                    .accessibilityHint("The \(camera.activePosition.label.lowercased()) camera is currently active")
                    .disabled(camera.operationState != .ready)
                } else {
                    Label("\(camera.activePosition.label) locked", systemImage: "lock.fill")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(minWidth: 104, minHeight: 48)
                        .padding(.horizontal, 10)
                        .background(Capsule().fill(.black.opacity(0.66)))
                        .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 1))
                        .accessibilityLabel("\(camera.activePosition.label) camera locked for this consistency test")
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .padding(.horizontal, 16)
    }

    private var bottomControls: some View {
        VStack(spacing: 14) {
            if previousPhoto != nil && referenceOverlayIsCompatible {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showPreviousOverlay.toggle()
                    }
                } label: {
                    VStack(spacing: 3) {
                        Label(
                            showPreviousOverlay ? "Previous photo on" : "Show previous photo",
                            systemImage: showPreviousOverlay ? "square.stack.3d.up.fill" : "square.stack.3d.up"
                        )
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        Text("On-screen only · stored on this iPhone")
                            .font(.system(size: 9.5, design: .rounded))
                            .foregroundStyle(showPreviousOverlay ? Color.black.opacity(0.62) : Color.white.opacity(0.65))
                    }
                    .foregroundStyle(showPreviousOverlay ? Color.black : Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background {
                        Capsule().fill(showPreviousOverlay ? Color.white.opacity(0.90) : Color.black.opacity(0.45))
                    }
                    .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isCapturing)
            } else if previousPhoto != nil && camera.isReady {
                Label("Previous photo hidden · camera setup differs", systemImage: "eye.slash")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.black.opacity(0.48)))
                    .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
            }

            // Timer chips
            HStack(spacing: 10) {
                ForEach(timerOptions, id: \.self) { s in
                    Button {
                        selectedSeconds = s
                    } label: {
                        Text("\(s)s")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(selectedSeconds == s ? .black : .white)
                            .frame(width: 52, height: 36)
                            .background(
                                Capsule().fill(selectedSeconds == s ? .white : .white.opacity(0.18))
                            )
                            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(isRunning || isCapturing)
                }
            }

            // Shutter
            HStack {
                Spacer()
                ZStack {
                    Button {
                        if isCapturing { return }
                        if isRunning { cancelCountdown() } else { startCountdown() }
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(.white, lineWidth: 4)
                                .frame(width: 84, height: 84)
                            Circle()
                                .fill(isCapturing ? Color.gray : (isRunning ? Color.red : Color.white))
                                .frame(width: 68, height: 68)
                            if isCapturing {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(1.2)
                            } else if isRunning {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isCapturing)
                }
                Spacer()
            }

            Text(isCapturing ? "Processing photo…" : (isRunning ? "Tap to cancel" : "Tap shutter to start a \(selectedSeconds)s timer"))
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .animation(.easeInOut(duration: 0.2), value: isCapturing)
                .animation(.easeInOut(duration: 0.2), value: isRunning)
        }
        .padding(.bottom, 36)
    }

    private var permissionView: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.white)
                Text("Camera access is off")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Enable Camera access in Settings to capture scans, or pick a photo from your library instead.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                HStack(spacing: 10) {
                    Button("Close") { dismiss() }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                }
            }
            .padding(28)
        }
    }

    // MARK: - Timer logic

    private func startCountdown() {
        guard camera.isReady else { return }
        isRunning = true
        countdown = selectedSeconds
        tick()
    }

    private func tick() {
        guard let c = countdown else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if c <= 1 {
            // Take photo on next runloop so the "1" frame renders briefly
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                guard isRunning else { return }
                triggerCapture()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                guard isRunning, let cur = countdown, cur > 1 else { return }
                withAnimation(.easeOut(duration: 0.25)) { countdown = cur - 1 }
                tick()
            }
        }
    }

    private func cancelCountdown() {
        isRunning = false
        countdown = nil
    }

    private func triggerCapture() {
        isRunning = false
        countdown = nil
        // Flash
        withAnimation(.easeOut(duration: 0.08)) { flashOpacity = 0.9 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeIn(duration: 0.25)) { flashOpacity = 0 }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        captureWatchdog?.cancel()
        captureWatchdog = Task {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard isCapturing else { return }
                camera.failPendingCapture(message: "The camera took too long to process the photo.")
                showCaptureError = true
            }
        }
        camera.capturePhoto { result in
            captureWatchdog?.cancel()
            guard let result else {
                showCaptureError = true
                return
            }
            onCaptured(result)
            dismiss()
        }
    }

    private var isCapturing: Bool {
        camera.operationState == .capturing || camera.operationState == .processing
    }

    private var referenceOverlayIsCompatible: Bool {
        guard let previousMetadata else { return false }
        return CameraReferencePolicy.canDisplay(
            reference: previousMetadata,
            activePosition: camera.activePosition,
            activeLensType: camera.activeLensType,
            activeZoomFactor: camera.activeZoomFactor
        )
    }
}

enum CameraReferencePolicy {
    static func canDisplay(
        reference: CaptureCameraMetadata,
        activePosition: CaptureCameraPosition,
        activeLensType: String?,
        activeZoomFactor: Float?
    ) -> Bool {
        guard let activeLensType,
              reference.position == activePosition,
              reference.lensType == activeLensType,
              reference.normalizedOrientation == .up else { return false }
        if let referenceZoom = reference.zoomFactor, let activeZoomFactor {
            return abs(referenceZoom - activeZoomFactor) <= 0.01
        }
        return reference.zoomFactor == nil
    }
}

// MARK: - Landmark alignment guide

private struct PoseAlignmentGuide: View {
    let pose: Pose

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(
                        Color.white.opacity(0.38),
                        style: StrokeStyle(lineWidth: 1.25, dash: [7, 7])
                    )

                ForEach(zones) { zone in
                    zoneView(zone, in: proxy.size)
                }
            }
        }
        .overlay(alignment: .top) {
            Text(pose == .legs ? "ALIGN HIPS · KNEES · FEET" : "ALIGN HEAD · SHOULDERS · HIPS · HANDS")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.88))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(.black.opacity(0.40)))
                .offset(y: -13)
        }
        .accessibilityHidden(true)
    }

    private func zoneView(_ zone: AlignmentZone, in size: CGSize) -> some View {
        let width = size.width * zone.width
        let height = size.height * zone.height
        return ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.08))
                .overlay {
                    Ellipse()
                        .stroke(Color.white.opacity(0.72), style: StrokeStyle(lineWidth: 1.25, dash: [5, 4]))
                }
                .frame(width: width, height: height)
            Text(zone.label)
                .font(.system(size: 7.5, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.88))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(.black.opacity(0.32)))
        }
        .position(x: size.width * zone.x, y: size.height * zone.y)
    }

    private var zones: [AlignmentZone] {
        switch pose {
        case .legs:
            return [
                AlignmentZone("HIPS", x: 0.50, y: 0.13, width: 0.46, height: 0.08),
                AlignmentZone("KNEE", x: 0.39, y: 0.50, width: 0.15, height: 0.10),
                AlignmentZone("KNEE", x: 0.61, y: 0.50, width: 0.15, height: 0.10),
                AlignmentZone("FOOT", x: 0.38, y: 0.90, width: 0.20, height: 0.09),
                AlignmentZone("FOOT", x: 0.62, y: 0.90, width: 0.20, height: 0.09)
            ]
        case .side, .sideChest:
            return [
                AlignmentZone("HEAD", x: 0.50, y: 0.13, width: 0.22, height: 0.14),
                AlignmentZone("SHOULDER", x: 0.50, y: 0.34, width: 0.28, height: 0.08),
                AlignmentZone("HIPS", x: 0.50, y: 0.64, width: 0.27, height: 0.08),
                AlignmentZone("HANDS", x: pose == .sideChest ? 0.55 : 0.53, y: pose == .sideChest ? 0.52 : 0.73, width: 0.18, height: 0.11)
            ]
        case .frontDoubleBicep, .backDoubleBicep:
            return [
                AlignmentZone("HAND", x: 0.20, y: 0.17, width: 0.16, height: 0.10),
                AlignmentZone("HEAD", x: 0.50, y: 0.19, width: 0.20, height: 0.13),
                AlignmentZone("HAND", x: 0.80, y: 0.17, width: 0.16, height: 0.10),
                AlignmentZone("SHOULDERS", x: 0.50, y: 0.39, width: 0.58, height: 0.07),
                AlignmentZone("HIPS", x: 0.50, y: 0.70, width: 0.36, height: 0.08)
            ]
        case .mostMuscular:
            return [
                AlignmentZone("HEAD", x: 0.50, y: 0.16, width: 0.21, height: 0.14),
                AlignmentZone("SHOULDERS", x: 0.50, y: 0.37, width: 0.56, height: 0.08),
                AlignmentZone("HANDS", x: 0.50, y: 0.58, width: 0.26, height: 0.11),
                AlignmentZone("HIPS", x: 0.50, y: 0.72, width: 0.36, height: 0.08)
            ]
        default:
            return [
                AlignmentZone("HEAD", x: 0.50, y: 0.13, width: 0.21, height: 0.14),
                AlignmentZone("SHOULDERS", x: 0.50, y: 0.34, width: 0.55, height: 0.08),
                AlignmentZone("HIPS", x: 0.50, y: 0.64, width: 0.38, height: 0.08),
                AlignmentZone("HAND", x: 0.28, y: 0.73, width: 0.14, height: 0.11),
                AlignmentZone("HAND", x: 0.72, y: 0.73, width: 0.14, height: 0.11)
            ]
        }
    }
}

private struct AlignmentZone: Identifiable {
    let label: String
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    var id: String {
        "\(label)-\(x)-\(y)-\(width)-\(height)"
    }

    init(_ label: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.label = label
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

// MARK: - Camera controller

final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "evolv.camera.queue")
    private var currentInput: AVCaptureDeviceInput?
    private var configuredPosition: AVCaptureDevice.Position
    private let requiresExactPosition: Bool
    private var pendingCapture: PendingCapture?
    private let handlerLock = NSLock()

    @Published var isReady: Bool = false
    @Published private(set) var operationState: CameraOperationState = .preparing
    @Published private(set) var activePosition: CaptureCameraPosition
    @Published private(set) var activeLensType: String?
    @Published private(set) var activeZoomFactor: Float?

    private struct PendingCapture {
        let handler: (CameraCaptureResult?) -> Void
        let metadata: CaptureCameraMetadata
    }

    var errorMessage: String? {
        guard case .error(let message) = operationState else { return nil }
        return message
    }

    init(
        initialPosition: CaptureCameraPosition = .front,
        requiresExactPosition: Bool = false
    ) {
        activePosition = initialPosition
        configuredPosition = Self.avPosition(for: initialPosition)
        self.requiresExactPosition = requiresExactPosition
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionWasInterrupted),
            name: AVCaptureSession.wasInterruptedNotification,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRuntimeError),
            name: AVCaptureSession.runtimeErrorNotification,
            object: session
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func start(completion: @escaping (Bool) -> Void) {
        operationState = .preparing
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure(completion: completion)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.configure(completion: completion)
                    } else {
                        self.operationState = .error("Camera access is required to take a photo.")
                        completion(false)
                    }
                }
            }
        default:
            operationState = .error("Camera access is turned off.")
            completion(false)
        }
    }

    func stop() {
        _ = takePendingCapture()
        queue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { self.isReady = false }
        }
    }

    func switchCamera() {
        // Serialize reconfiguration. This also prevents a rapid double tap from
        // removing the input while an earlier switch is still in flight.
        guard operationState == .ready else { return }
        DispatchQueue.main.async { self.isReady = false }
        setState(.preparing)
        queue.async { [weak self] in
            guard let self else { return }
            let previousPosition = self.configuredPosition
            let nextPosition: AVCaptureDevice.Position = previousPosition == .back ? .front : .back
            self.session.beginConfiguration()
            if let current = self.currentInput { self.session.removeInput(current) }
            guard let input = self.makeInput(position: nextPosition), self.session.canAddInput(input) else {
                if let current = self.currentInput, self.session.canAddInput(current) {
                    self.session.addInput(current)
                }
                self.session.commitConfiguration()
                self.configuredPosition = previousPosition
                DispatchQueue.main.async { self.isReady = self.session.isRunning }
                self.setState(.error("The selected camera isn't available."))
                return
            }
            self.session.addInput(input)
            self.currentInput = input
            self.configuredPosition = nextPosition
            self.configureUnmirroredPhotoOutput()
            self.session.commitConfiguration()
            let publicPosition = Self.capturePosition(for: nextPosition)
            DispatchQueue.main.async {
                self.activePosition = publicPosition
                self.activeLensType = input.device.deviceType.rawValue
                self.activeZoomFactor = Float(input.device.videoZoomFactor)
                self.isReady = self.session.isRunning
                CameraPreferenceStore.save(publicPosition)
            }
            self.setState(.ready)
        }
    }

    func capturePhoto(handler: @escaping (CameraCaptureResult?) -> Void) {
        guard operationState == .ready else {
            DispatchQueue.main.async { handler(nil) }
            return
        }
        let position = activePosition
        let lensType = queue.sync {
            currentInput?.device.deviceType.rawValue ?? "unknown"
        }
        let zoomFactor = queue.sync {
            currentInput.map { Float($0.device.videoZoomFactor) }
        }
        let metadata = CaptureCameraMetadata(
            position: position,
            lensType: lensType,
            previewMirrored: position == .front,
            outputMirrored: false,
            sourceOrientation: .up,
            normalizedOrientation: .up,
            zoomFactor: zoomFactor
        )
        handlerLock.lock()
        pendingCapture = PendingCapture(handler: handler, metadata: metadata)
        handlerLock.unlock()
        setState(.capturing)
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        queue.async { [weak self] in
            guard let self else { return }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func prepareForRetry() {
        _ = takePendingCapture()
        if session.isRunning {
            DispatchQueue.main.async { self.isReady = true }
            setState(.ready)
        } else {
            setState(.preparing)
        }
    }

    func failPendingCapture(message: String) {
        let pending = takePendingCapture()
        setState(.error(message))
        DispatchQueue.main.async { pending?.handler(nil) }
    }

    private func configure(completion: @escaping (Bool) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            let preferredPosition = self.configuredPosition
            let fallbackPosition: AVCaptureDevice.Position = preferredPosition == .front ? .back : .front
            let input = self.makeInput(position: preferredPosition)
                ?? (self.requiresExactPosition ? nil : self.makeInput(position: fallbackPosition))
            guard let input, self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                self.setState(.error("Evolv couldn't configure the camera."))
                DispatchQueue.main.async { completion(false) }
                return
            }
            self.session.addInput(input)
            self.currentInput = input
            self.configuredPosition = input.device.position
            guard self.session.canAddOutput(self.photoOutput) else {
                self.session.removeInput(input)
                self.session.commitConfiguration()
                self.setState(.error("Evolv couldn't configure photo capture."))
                DispatchQueue.main.async { completion(false) }
                return
            }
            self.session.addOutput(self.photoOutput)
            self.configureUnmirroredPhotoOutput()
            self.session.commitConfiguration()
            self.session.startRunning()
            let publicPosition = Self.capturePosition(for: input.device.position)
            DispatchQueue.main.async {
                self.activePosition = publicPosition
                self.activeLensType = input.device.deviceType.rawValue
                self.activeZoomFactor = Float(input.device.videoZoomFactor)
                self.isReady = self.session.isRunning
                self.operationState = self.session.isRunning
                    ? .ready
                    : .error("The camera couldn't start.")
                if self.session.isRunning {
                    CameraPreferenceStore.save(publicPosition)
                }
                completion(self.session.isRunning)
            }
        }
    }

    private func makeInput(position: AVCaptureDevice.Position) -> AVCaptureDeviceInput? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: position
        )
        guard let device = discovery.devices.first else { return nil }
        return try? AVCaptureDeviceInput(device: device)
    }

    private func configureUnmirroredPhotoOutput() {
        guard let connection = photoOutput.connection(with: .video),
              connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = false
    }

    // MARK: AVCapturePhotoCaptureDelegate

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings
    ) {
        setState(.processing)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let pending = takePendingCapture()
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data),
              let pending else {
            setState(.error("The camera couldn't process that photo."))
            DispatchQueue.main.async { pending?.handler(nil) }
            return
        }
        var metadata = pending.metadata
        metadata.sourceOrientation = image.imageOrientation.captureOrientation
        metadata.outputMirrored = metadata.sourceOrientation.isMirrored
        setState(.completed)
        let result = CameraCaptureResult(image: image, metadata: metadata)
        DispatchQueue.main.async { pending.handler(result) }
    }

    private var isCapturing: Bool {
        operationState == .capturing || operationState == .processing
    }

    private func takePendingCapture() -> PendingCapture? {
        handlerLock.lock()
        let capture = pendingCapture
        pendingCapture = nil
        handlerLock.unlock()
        return capture
    }

    private func setState(_ state: CameraOperationState) {
        DispatchQueue.main.async {
            self.operationState = state
        }
    }

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        failPendingCapture(message: "The camera was interrupted. Please try again.")
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        failPendingCapture(message: "The camera stopped unexpectedly. Please try again.")
    }

    private static func avPosition(for position: CaptureCameraPosition) -> AVCaptureDevice.Position {
        position == .front ? .front : .back
    }

    private static func capturePosition(for position: AVCaptureDevice.Position) -> CaptureCameraPosition {
        position == .front ? .front : .rear
    }
}

// MARK: - Preview and reference overlay

/// The live camera and previous-photo ghost share one UIKit-backed viewport.
/// This ensures both use identical aspect-fill bounds and the same center-based
/// mirroring transform instead of two independently cropped SwiftUI images.
struct CameraCompositePreview: UIViewRepresentable {
    let session: AVCaptureSession
    let isMirrored: Bool
    let referenceImage: UIImage?
    let showsReference: Bool

    func makeUIView(context: Context) -> CompositePreviewView {
        let view = CompositePreviewView()
        view.configure(
            session: session,
            isMirrored: isMirrored,
            referenceImage: referenceImage,
            showsReference: showsReference
        )
        return view
    }

    func updateUIView(_ uiView: CompositePreviewView, context: Context) {
        uiView.configure(
            session: session,
            isMirrored: isMirrored,
            referenceImage: referenceImage,
            showsReference: showsReference
        )
    }

    final class CompositePreviewView: UIView {
        let videoPreviewLayer = AVCaptureVideoPreviewLayer()
        private let referenceLayer = CALayer()
        private var isMirrored = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            clipsToBounds = true
            videoPreviewLayer.videoGravity = .resizeAspectFill
            layer.addSublayer(videoPreviewLayer)
            referenceLayer.contentsGravity = .resizeAspectFill
            referenceLayer.opacity = 0.22
            referenceLayer.masksToBounds = true
            layer.addSublayer(referenceLayer)
        }

        required init?(coder: NSCoder) { nil }

        func configure(
            session: AVCaptureSession,
            isMirrored: Bool,
            referenceImage: UIImage?,
            showsReference: Bool
        ) {
            videoPreviewLayer.session = session
            self.isMirrored = isMirrored
            referenceLayer.contents = referenceImage?.cgImage
            referenceLayer.isHidden = !showsReference || referenceImage == nil
            setNeedsLayout()
            updateMirroring()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            videoPreviewLayer.frame = bounds
            referenceLayer.bounds = bounds
            referenceLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            referenceLayer.transform = isMirrored
                ? CATransform3DMakeScale(-1, 1, 1)
                : CATransform3DIdentity
            CATransaction.commit()
            updateMirroring()
        }

        private func updateMirroring() {
            guard let connection = videoPreviewLayer.connection,
                  connection.isVideoMirroringSupported else { return }
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = isMirrored
        }
    }
}

private extension UIImage.Orientation {
    var captureOrientation: CaptureImageOrientation {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
