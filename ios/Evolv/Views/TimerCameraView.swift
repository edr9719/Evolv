import SwiftUI
import AVFoundation
import UIKit

/// Full-screen camera with an auto-shutter countdown timer (3 / 5 / 10 s) and
/// a manual shutter fallback. Designed for hands-free scan capture where the
/// user props their phone against a wall, taps the timer, then walks into frame.
struct TimerCameraView: View {
    @Environment(\.dismiss) private var dismiss
    let pose: Pose
    let onCaptured: (UIImage) -> Void

    @StateObject private var camera = CameraController()

    @State private var selectedSeconds: Int = 5
    @State private var countdown: Int? = nil
    @State private var isRunning: Bool = false
    @State private var isCapturing: Bool = false
    @State private var permissionDenied: Bool = false
    @State private var flashOpacity: Double = 0
    @State private var showCaptureError: Bool = false

    private let timerOptions: [Int] = [3, 5, 10]

    var body: some View {
        Group {
            ZStack {
                Color.black.ignoresSafeArea()
            
                CameraPreviewView(session: camera.session)
                    .ignoresSafeArea()
                    .opacity(camera.isReady ? 1 : 0)
            
                // Pose framing guide — keep faint so it doesn't dominate
                SilhouetteHint(pose: pose)
                    .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
                    .frame(width: 220, height: 440)
                    .padding(.bottom, 80)
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
            
                VStack {
                    topBar
                    Spacer()
                    bottomControls
                }
            
                if permissionDenied {
                    permissionView
                }
            }
            .statusBarHidden()
            .preferredColorScheme(.dark)
            .onAppear { camera.start { granted in if !granted { permissionDenied = true } } }
            .onDisappear { camera.stop(); cancelCountdown() }
            .alert("Couldn't capture photo", isPresented: $showCaptureError) {
                Button("Try Again", role: .cancel) {}
            } message: {
                Text("The camera couldn't save the photo. Tap the shutter to try again.")
            }
        }
        .trackView("TimerCameraView")
    }

    // MARK: - Subviews

    private var topBar: some View {
        HStack {
            Button {
                cancelCountdown()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Circle().fill(.black.opacity(0.45)))
            }
            Spacer()
            VStack(spacing: 2) {
                Text("POSE")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.6))
                Text(pose.label)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
            }
            Spacer()
            Button {
                camera.switchCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Circle().fill(.black.opacity(0.45)))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var bottomControls: some View {
        VStack(spacing: 18) {
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

            Text(isCapturing ? "Saving…" : (isRunning ? "Tap to cancel" : "Tap shutter to start a \(selectedSeconds)s timer"))
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
        isCapturing = true
        // Flash
        withAnimation(.easeOut(duration: 0.08)) { flashOpacity = 0.9 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeIn(duration: 0.25)) { flashOpacity = 0 }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        camera.capturePhoto { image in
            isCapturing = false
            guard let image else {
                showCaptureError = true
                return
            }
            onCaptured(image)
            dismiss()
        }
    }
}

// MARK: - Silhouette hint

private struct SilhouetteHint: Shape {
    let pose: Pose
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        let isSide = (pose == .side || pose == .sideChest)
        let flexed = (pose == .frontDoubleBicep || pose == .backDoubleBicep || pose == .mostMuscular)
        // Head
        p.addEllipse(in: CGRect(x: w * 0.38, y: 0, width: w * 0.24, height: w * 0.24))
        let neckY = w * 0.24
        let shoulderSpread: CGFloat = isSide ? 0.16 : (flexed ? 0.56 : 0.40)
        let waistSpread: CGFloat = isSide ? 0.14 : 0.24
        let hipSpread: CGFloat = isSide ? 0.16 : 0.30
        let cx = w / 2
        let shL = cx - w * shoulderSpread / 2
        let shR = cx + w * shoulderSpread / 2
        let wL = cx - w * waistSpread / 2
        let wR = cx + w * waistSpread / 2
        let hL = cx - w * hipSpread / 2
        let hR = cx + w * hipSpread / 2
        p.move(to: CGPoint(x: shL, y: neckY + 4))
        p.addQuadCurve(to: CGPoint(x: wL, y: h * 0.55), control: CGPoint(x: shL - 6, y: h * 0.35))
        p.addQuadCurve(to: CGPoint(x: hL, y: h * 0.70), control: CGPoint(x: wL - 4, y: h * 0.62))
        p.addLine(to: CGPoint(x: cx - w * 0.06, y: h))
        p.addLine(to: CGPoint(x: cx + w * 0.06, y: h))
        p.addLine(to: CGPoint(x: hR, y: h * 0.70))
        p.addQuadCurve(to: CGPoint(x: wR, y: h * 0.55), control: CGPoint(x: wR + 4, y: h * 0.62))
        p.addQuadCurve(to: CGPoint(x: shR, y: neckY + 4), control: CGPoint(x: shR + 6, y: h * 0.35))
        return p
    }
}

// MARK: - Camera controller

final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "evolv.camera.queue")
    private var currentInput: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .back
    private var captureHandler: ((UIImage?) -> Void)?

    @Published var isReady: Bool = false

    func start(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure(); completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.configure() }
                    completion(granted)
                }
            }
        default:
            completion(false)
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func switchCamera() {
        queue.async { [weak self] in
            guard let self else { return }
            self.position = (self.position == .back) ? .front : .back
            self.session.beginConfiguration()
            if let current = self.currentInput { self.session.removeInput(current) }
            if let input = self.makeInput(position: self.position) {
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.currentInput = input
                }
            }
            self.session.commitConfiguration()
        }
    }

    func capturePhoto(handler: @escaping (UIImage?) -> Void) {
        captureHandler = handler
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        queue.async { [weak self] in
            self?.photoOutput.capturePhoto(with: settings, delegate: self!)
        }
    }

    private func configure() {
        queue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            if let input = self.makeInput(position: self.position) {
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.currentInput = input
                }
            }
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }
            self.session.commitConfiguration()
            self.session.startRunning()
            DispatchQueue.main.async { self.isReady = true }
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

    // MARK: AVCapturePhotoCaptureDelegate

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        defer { captureHandler = nil }
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            DispatchQueue.main.async { self.captureHandler?(nil) }
            return
        }
        DispatchQueue.main.async { self.captureHandler?(image) }
    }
}

// MARK: - Preview

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoPreviewLayer.session = session
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
