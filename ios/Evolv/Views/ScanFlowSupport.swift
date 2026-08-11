import SwiftUI

struct CaptureRequest: Identifiable {
    let id = UUID()
    var role: ScanRole = .canonical
    var repairScanID: UUID? = nil
    var poses: [Pose]? = nil

    static var newCanonical: CaptureRequest { CaptureRequest() }
    static var sameDayExtra: CaptureRequest { CaptureRequest(role: .sameDayExtra) }

    static func repair(scanID: UUID, poses: [Pose]) -> CaptureRequest {
        CaptureRequest(role: .canonical, repairScanID: scanID, poses: poses)
    }
}

struct ScanDetailRequest: Identifiable {
    let id: UUID
}

struct ScanStartOptionsSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    let scanID: UUID
    let onCapture: (CaptureRequest) -> Void
    let onView: (UUID) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                if let scan = app.scan(id: scanID) {
                    ScrollView {
                        VStack(spacing: 20) {
                            Image(systemName: scan.recommendedRepairPoses.isEmpty
                                  ? "checkmark.circle.fill"
                                  : "viewfinder.circle")
                                .font(.system(size: 46, weight: .light))
                                .foregroundStyle(EvolvTheme.accent)
                                .padding(.top, 20)

                            VStack(spacing: 8) {
                                Text(scan.recommendedRepairPoses.isEmpty
                                     ? "You already scanned today"
                                     : "Today's progress scan is already saved")
                                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                                    .foregroundStyle(EvolvTheme.text)
                                    .multilineTextAlignment(.center)
                                Text(message(for: scan))
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundStyle(EvolvTheme.textMuted)
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(3)
                            }

                            if let next = app.nextRecommendedScanDate {
                                Text("Next recommended scan: \(next.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(EvolvTheme.textMuted)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Capsule().stroke(EvolvTheme.stroke, lineWidth: 1))
                            }

                            VStack(spacing: 12) {
                                if !scan.recommendedRepairPoses.isEmpty {
                                    EvolvPrimaryButton(title: "Improve today's scan", icon: "camera.fill") {
                                        choose(.repair(scanID: scan.id, poses: scan.recommendedRepairPoses))
                                    }
                                } else {
                                    EvolvPrimaryButton(title: "View today's scan", icon: "photo.on.rectangle") {
                                        dismiss()
                                        onView(scan.id)
                                    }
                                }

                                Button {
                                    if scan.recommendedRepairPoses.isEmpty {
                                        choose(.repair(scanID: scan.id, poses: Pose.required))
                                    } else {
                                        dismiss()
                                        onView(scan.id)
                                    }
                                } label: {
                                    Text(scan.recommendedRepairPoses.isEmpty
                                         ? "Replace today's three poses"
                                         : "Review today's scan")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(EvolvTheme.text)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 50)
                                        .background {
                                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                                .fill(EvolvTheme.surface)
                                                .overlay(RoundedRectangle(cornerRadius: 17).stroke(EvolvTheme.stroke, lineWidth: 1))
                                        }
                                }
                                .buttonStyle(.plain)

                                Button {
                                    choose(.sameDayExtra)
                                } label: {
                                    Text("Start a separate scan anyway")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(EvolvTheme.textMuted)
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 4)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle("Today's scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }.tint(EvolvTheme.accent)
                }
            }
        }
    }

    private func message(for scan: Scan) -> String {
        if scan.recommendedRepairPoses.isEmpty {
            return "It was captured at \(scan.date.formatted(date: .omitted, time: .shortened)). Same-day differences often come from lighting, hydration, posture, or workout pump—not physique progress."
        }
        let names = naturalPoseList(scan.recommendedRepairPoses)
        let noun = scan.recommendedRepairPoses.count == 1 ? "photo is" : "photos are"
        return "The \(names) \(noun) saved, but Evolv could not verify the framing automatically. Retaking \(scan.recommendedRepairPoses.count == 1 ? "it" : "them") may make this scan usable for future comparisons. This does not mean the saved photo\(scan.recommendedRepairPoses.count == 1 ? " is" : "s are") poor."
    }

    private func naturalPoseList(_ poses: [Pose]) -> String {
        let labels = poses.map { $0.shortLabel.lowercased() }
        if labels.count <= 1 { return labels.first ?? "selected" }
        if labels.count == 2 { return labels.joined(separator: " and ") }
        return labels.dropLast().joined(separator: ", ") + ", and " + (labels.last ?? "")
    }

    private func choose(_ request: CaptureRequest) {
        dismiss()
        onCapture(request)
    }
}

struct ScanRepairPickerSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    let scanID: UUID
    let onStart: ([Pose]) -> Void
    @State private var selection: Set<Pose>

    init(scanID: UUID, initiallySelected: [Pose], onStart: @escaping ([Pose]) -> Void) {
        self.scanID = scanID
        self.onStart = onStart
        _selection = State(initialValue: Set(initiallySelected.isEmpty ? Pose.required : initiallySelected))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                VStack(spacing: 16) {
                    Text("These photos are already saved. Choose only the angles you want Evolv to try verifying again; every unselected photo will remain unchanged.")
                        .font(.system(size: 13.5, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 24)
                        .padding(.top, 12)

                    if let scan = app.scan(id: scanID) {
                        VStack(spacing: 10) {
                            ForEach(Pose.required) { pose in
                                let capture = scan.capture(for: pose)
                                Button {
                                    if selection.contains(pose) { selection.remove(pose) }
                                    else { selection.insert(pose) }
                                } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: selection.contains(pose) ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 19))
                                            .foregroundStyle(selection.contains(pose) ? EvolvTheme.accent : EvolvTheme.textFaint)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(pose.label)
                                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                                .foregroundStyle(EvolvTheme.text)
                                            Text(capture?.assessment?.automaticStatusTitle ?? "Automatic check unavailable")
                                                .font(.system(size: 12, design: .rounded))
                                                .foregroundStyle(EvolvTheme.textMuted)
                                        }
                                        Spacer()
                                    }
                                    .padding(15)
                                    .background {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(EvolvTheme.surface)
                                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(EvolvTheme.stroke, lineWidth: 1))
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    Spacer()
                    EvolvPrimaryButton(
                        title: selection.isEmpty ? "Select at least one pose" : "Replace \(selection.count) photo\(selection.count == 1 ? "" : "s")",
                        icon: "camera.fill",
                        enabled: !selection.isEmpty
                    ) {
                        let poses = Pose.required.filter(selection.contains)
                        dismiss()
                        onStart(poses)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Improve scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }.tint(EvolvTheme.accent)
                }
            }
        }
    }
}
