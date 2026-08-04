import Foundation
import SwiftUI

@Observable
final class AppState {
    var profile = UserProfile()
    var measurements: [Measurement] = []
    var scans: [Scan] = []
    var hasCompletedOnboarding: Bool = false

    // Analysis state — not persisted in state.json; AnalysisStore owns the JSON files
    var latestAnalysis: ScanAnalysis? = nil
    var analysisPending: Bool = false

    // Persisted under Documents/state.json
    private static var stateURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("evolv-state.json")
    }

    init() {
        load()
        PurchaseService.shared.bind(to: profile)
        // Load the most recent analysis from disk (background to avoid blocking launch)
        if let latestScanId = scans.sorted(by: { $0.date < $1.date }).last?.id {
            Task.detached(priority: .background) { [weak self] in
                let analysis = AnalysisStore.load(scanId: latestScanId)
                await MainActor.run { self?.latestAnalysis = analysis }
            }
        }
    }

    var calibrationState: CalibrationState {
        guard let analysis = latestAnalysis else {
            return scans.isEmpty ? .noScans : .baselineSet
        }
        return CalibrationState.from(
            tier: analysis.smoothedSignals.reliabilityTier,
            confidence: analysis.confidence.overall,
            scanCount: scans.count
        )
    }

    /// True when premium is unlocked (trial or active sub).
    var isPremium: Bool {
        PurchaseService.shared.isSubscribed
    }

    /// Persist current PurchaseService entitlement back into profile.
    func syncSubscriptionFromPurchaseService() {
        profile.subscriptionPlan = PurchaseService.shared.activePlan?.rawValue
        profile.trialEndsAt = PurchaseService.shared.trialEndsAt
        if profile.subscriptionStartedAt == nil && profile.subscriptionPlan != nil {
            profile.subscriptionStartedAt = Date()
        }
        save()
    }

    /// Marks the user as having seen the post-onboarding paywall (whether they purchased or skipped).
    func markPostOnboardingPaywallSeen() {
        profile.hasSeenPostOnboardingPaywall = true
        save()
    }

    // MARK: - Derived data

    var sortedScans: [Scan] { scans.sorted { $0.date < $1.date } }
    var latestScan: Scan? { sortedScans.last }
    var firstScan: Scan? { sortedScans.first }

    var hasAnyScans: Bool { !scans.isEmpty }

    /// Weeks tracked from first scan to today (min 0).
    var weeksTracked: Int {
        guard let first = firstScan?.date else { return 0 }
        return max(0, Calendar.current.dateComponents([.weekOfYear], from: first, to: Date()).weekOfYear ?? 0)
    }

    var daysSinceLastScan: Int {
        guard let d = latestScan?.date else { return 0 }
        return Calendar.current.dateComponents([.day], from: d, to: Date()).day ?? 0
    }

    var currentStreak: Int {
        guard !scans.isEmpty else { return 0 }
        let cal = Calendar.current
        let bucket: Calendar.Component = {
            switch profile.cadence {
            case .daily: return .day
            case .weekly, .biweekly: return .weekOfYear
            case .monthly: return .month
            }
        }()
        let sorted = scans.map { $0.date }.sorted(by: >)
        var streak = 1
        var cursor = sorted[0]
        let step = profile.cadence == .biweekly ? 2 : 1
        for date in sorted.dropFirst() {
            let diff = cal.dateComponents([bucket], from: date, to: cursor).value(for: bucket) ?? 0
            if diff == 0 { continue }
            if diff == step {
                streak += 1
                cursor = date
            } else { break }
        }
        return streak
    }

    // MARK: - Consistency scoring (real, image-derived)

    /// Computes a 0–100 consistency score for a new scan vs the existing baseline scan.
    /// Considers lighting (brightness delta) and framing (aspect ratio delta).
    func computeConsistency(forNew captures: [PoseCapture]) -> (consistency: Int, lighting: Int, framing: Int) {
        guard let baseline = firstScan else {
            // First scan ever — set baseline. Treat as solid but not perfect.
            return (consistency: 80, lighting: 85, framing: 85)
        }
        // Compare each standard pose against the baseline's pose
        var lightingDeltas: [Double] = []
        var framingDeltas: [Double] = []
        for c in captures where c.pose.category == .standard {
            if let base = baseline.capture(for: c.pose) {
                lightingDeltas.append(abs(c.avgBrightness - base.avgBrightness))
                framingDeltas.append(abs(c.aspectRatio - base.aspectRatio))
            }
        }
        if lightingDeltas.isEmpty {
            return (consistency: 70, lighting: 75, framing: 75)
        }
        let avgLightDelta = lightingDeltas.reduce(0, +) / Double(lightingDeltas.count)
        let avgFrameDelta = framingDeltas.reduce(0, +) / Double(framingDeltas.count)

        // Map deltas to scores. 0 delta = 100, larger = lower.
        let lighting = max(30, min(100, Int((1.0 - avgLightDelta * 2.2) * 100)))
        let framing  = max(30, min(100, Int((1.0 - avgFrameDelta * 3.0) * 100)))
        let consistency = Int((Double(lighting) * 0.55 + Double(framing) * 0.45).rounded())
        return (consistency, lighting, framing)
    }

    // MARK: - Progress score (data-driven)

    var progressScore: ProgressScore {
        guard scans.count >= 2,
              let first = firstScan,
              let last = latestScan else {
            if scans.count == 1 {
                return ProgressScore(value: 38, monthlyDelta: 0, weeklyDelta: 0, momentum: "Baseline set")
            }
            return ProgressScore(value: 0, monthlyDelta: 0, weeklyDelta: 0, momentum: "Awaiting baseline")
        }

        let baseW = measurements.first?.weightKg ?? profile.weightKg
        let latestW = measurements.last?.weightKg ?? profile.weightKg
        let weightShift = latestW - baseW

        let consistencyAvg = Double(scans.map(\.consistencyScore).reduce(0, +)) / Double(scans.count)

        let goalAligned: Double = {
            switch profile.goal {
            case .muscleGain: return max(-2, min(2, weightShift)) * 4
            case .fatLoss:    return max(-2, min(2, -weightShift)) * 4
            case .recomp:     return (2 - min(2, abs(weightShift))) * 3
            case .maintain:   return (2 - min(2, abs(weightShift))) * 3
            }
        }()

        let weeks = Double(Calendar.current.dateComponents([.weekOfYear], from: first.date, to: last.date).weekOfYear ?? 0)
        let visual = min(20, weeks * 1.2) * (consistencyAvg / 100.0)

        let raw = 45 + goalAligned + visual + (consistencyAvg - 60) * 0.25
        let value = max(0, min(100, Int(raw.rounded())))

        let sortedS = sortedScans
        let weeklyDelta: Int = {
            guard sortedS.count >= 2 else { return 0 }
            return (sortedS.last!.consistencyScore - sortedS[sortedS.count - 2].consistencyScore) / 6
        }()

        let monthlyDelta: Int = {
            guard sortedS.count >= 4 else { return weeklyDelta * 2 }
            let oldIdx = max(0, sortedS.count - 5)
            return (sortedS.last!.consistencyScore - sortedS[oldIdx].consistencyScore) / 3
        }()

        let momentum: String
        if weeklyDelta > 2 { momentum = "Building" }
        else if weeklyDelta < -2 { momentum = "Slowing" }
        else { momentum = "Steady" }

        return ProgressScore(value: value, monthlyDelta: monthlyDelta, weeklyDelta: weeklyDelta, momentum: momentum)
    }

    // MARK: - Estimated deltas (data-driven, honest)

    var estimatedDeltas: [EstimatedDelta] {
        // Need baseline + recent measurement, otherwise return informational placeholders
        guard let baseline = measurements.first, measurements.count >= 2,
              let latest = measurements.last else {
            if !measurements.isEmpty {
                return [
                    EstimatedDelta(label: "Arms", unit: "cm", value: 0, status: .stable, note: "Add a follow-up measurement to estimate change"),
                    EstimatedDelta(label: "Chest", unit: "cm", value: 0, status: .stable, note: nil),
                    EstimatedDelta(label: "Waist", unit: "cm", value: 0, status: .stable, note: nil)
                ]
            }
            return []
        }

        func delta(_ a: Double?, _ b: Double?) -> Double? {
            guard let a, let b else { return nil }
            return b - a
        }

        var out: [EstimatedDelta] = []
        if let d = delta(baseline.arms, latest.arms) {
            out.append(makeDelta(label: "Arms", unit: "cm", value: d, goalDirection: .up))
        }
        if let d = delta(baseline.chest, latest.chest) {
            out.append(makeDelta(label: "Chest", unit: "cm", value: d, goalDirection: .up))
        }
        if let d = delta(baseline.waist, latest.waist) {
            let dir: GoalDir = (profile.goal == .muscleGain || profile.goal == .maintain) ? .neutral : .down
            out.append(makeDelta(label: "Waist", unit: "cm", value: d, goalDirection: dir))
        }

        // Visual muscularity proxy from time elapsed + scan consistency
        let weeks = Double(Calendar.current.dateComponents([.weekOfYear], from: (firstScan?.date ?? Date()), to: (latestScan?.date ?? Date())).weekOfYear ?? 0)
        let cAvg = scans.isEmpty ? 50 : Double(scans.map(\.consistencyScore).reduce(0, +)) / Double(scans.count)
        let visual = (weeks * 0.5) * (cAvg / 100.0)
        let visualVal = (visual * 10).rounded() / 10
        let visualStatus: TrendStatus = visualVal > 1.5 ? .improving : (visualVal < -0.5 ? .stalled : .stable)
        if scans.count >= 2 {
            out.append(EstimatedDelta(
                label: "Visual muscularity",
                unit: "%",
                value: visualVal,
                status: visualStatus,
                note: visualVal == 0 ? "No detectable visual change yet" : nil
            ))
        }
        return out
    }

    private enum GoalDir { case up, down, neutral }

    private func makeDelta(label: String, unit: String, value: Double, goalDirection: GoalDir) -> EstimatedDelta {
        let rounded = (value * 10).rounded() / 10
        let mag = abs(rounded)
        if mag < 0.2 {
            return EstimatedDelta(label: label, unit: unit, value: rounded, status: .stable, note: "No meaningful change detected")
        }
        let status: TrendStatus
        switch goalDirection {
        case .up:      status = rounded > 0 ? .improving : .stalled
        case .down:    status = rounded < 0 ? .improving : .stalled
        case .neutral: status = mag > 1.5 ? .stalled : .stable
        }
        return EstimatedDelta(label: label, unit: unit, value: rounded, status: status, note: nil)
    }

    // MARK: - Weekly AI summary (data-driven, honest)

    var weeklySummary: WeeklySummary {
        let avgConsistency = scans.isEmpty ? 0 : scans.map(\.consistencyScore).reduce(0, +) / scans.count
        let conf: Confidence = avgConsistency > 78 ? .high : (avgConsistency > 55 ? .medium : .low)

        if scans.isEmpty {
            return WeeklySummary(
                headline: "Capture your first scan to begin.",
                detail: "Your first scan becomes the baseline Evolv quietly compares everything against.",
                confidence: .medium
            )
        }
        if scans.count == 1 {
            return WeeklySummary(
                headline: "Baseline captured.",
                detail: "Keep scan conditions consistent. Meaningful trends typically emerge after 3–4 scans.",
                confidence: .medium
            )
        }

        let latest = latestScan!
        let prev = sortedScans[sortedScans.count - 2]
        let lightingDrop = latest.lightingScore < prev.lightingScore - 12

        if lightingDrop || avgConsistency < 55 {
            return WeeklySummary(
                headline: "Progress visibility is limited due to inconsistent scan conditions.",
                detail: "Lighting or framing has shifted from your baseline. Try matching the same room, time of day, and distance to sharpen the read.",
                confidence: .low
            )
        }

        let deltas = estimatedDeltas
        let p = progressScore

        // Measurement-led narratives
        if let waist = deltas.first(where: { $0.label == "Waist" }), waist.status == .improving,
           profile.goal != .muscleGain {
            return WeeklySummary(
                headline: "Waist measurements decreased while weight remained near baseline.",
                detail: "This pattern often suggests recomposition. Keep training intensity steady to preserve muscle.",
                confidence: conf
            )
        }

        if let arms = deltas.first(where: { $0.label == "Arms" }), arms.status == .improving {
            return WeeklySummary(
                headline: "Your upper body appears slightly fuller than your baseline.",
                detail: "Arms are trending up. Visual change tends to lag measurement change by 2–3 weeks.",
                confidence: conf
            )
        }

        if p.weeklyDelta < -2 || (deltas.allSatisfy { $0.status == .stable } && deltas.count >= 2) {
            return WeeklySummary(
                headline: "No meaningful visual change detected yet.",
                detail: "This isn't unusual — visible physique change is slow. Stay consistent with capture conditions and training load.",
                confidence: conf
            )
        }

        return WeeklySummary(
            headline: "Your physique appears stable this period.",
            detail: "Strength is likely increasing faster than visible muscularity right now. Trust the process.",
            confidence: conf
        )
    }

    // MARK: - Actions

    /// Adds a real scan from captured pose images and triggers background analysis.
    func addScan(captures: [PoseCapture]) {
        let scores = computeConsistency(forNew: captures)
        let scan = Scan(
            date: Date(),
            captures: captures,
            consistencyScore: scores.consistency,
            lightingScore: scores.lighting,
            framingScore: scores.framing,
            note: nil,
            context: nil
        )
        scans.append(scan)
        save()

        // Trigger analysis pipeline asynchronously
        analysisPending = true
        let allScans = scans
        let allMeasurements = measurements
        let userProfile = profile
        Task {
            let analysis = await AnalysisPipeline.shared.analyzeNewScan(
                scan: scan,
                allScans: allScans,
                measurements: allMeasurements,
                profile: userProfile
            )
            await MainActor.run {
                self.latestAnalysis = analysis
                self.analysisPending = false
            }
        }
    }

    /// Updates the scan context (pre-workout, fasted, hydration) on the most recently added scan.
    func updateLatestScanContext(preWorkout: Bool?, fasted: Bool?, hydration: HydrationState?) {
        guard !scans.isEmpty else { return }
        let idx = scans.count - 1
        let scan = scans[idx]
        scans[idx].context = ScanContext(
            timestamp: scan.date,
            timeOfDayCategory: TimeOfDayCategory.inferred(from: scan.date),
            preWorkout: preWorkout,
            fasted: fasted,
            hydrationEstimate: hydration
        )
        save()
    }

    func deleteScan(_ scan: Scan) {
        for c in scan.captures {
            PhotoStore.delete(named: c.imageFilename)
        }
        AnalysisStore.delete(scanId: scan.id)
        scans.removeAll { $0.id == scan.id }
        // Update latestAnalysis to the new latest scan's analysis (if any)
        if let newLatestId = scans.sorted(by: { $0.date < $1.date }).last?.id {
            latestAnalysis = AnalysisStore.load(scanId: newLatestId)
        } else {
            latestAnalysis = nil
        }
        save()
    }

    func addMeasurement(_ m: Measurement) {
        measurements.append(m)
        save()
    }

    func finishOnboarding(initialMeasurement: Measurement?) {
        if let m = initialMeasurement {
            measurements.append(m)
        }
        hasCompletedOnboarding = true
        save()
    }

    func resetAll() {
        // Wipe images and analysis files
        for s in scans {
            for c in s.captures {
                PhotoStore.delete(named: c.imageFilename)
            }
            AnalysisStore.delete(scanId: s.id)
        }
        scans = []
        measurements = []
        profile = UserProfile()
        hasCompletedOnboarding = false
        latestAnalysis = nil
        analysisPending = false
        save()
    }

    // MARK: - Persistence

    private struct Persisted: Codable {
        var profile: UserProfile
        var measurements: [Measurement]
        var scans: [Scan]
        var hasCompletedOnboarding: Bool
    }

    func save() {
        let p = Persisted(profile: profile, measurements: measurements, scans: scans, hasCompletedOnboarding: hasCompletedOnboarding)
        if let data = try? JSONEncoder().encode(p) {
            try? data.write(to: Self.stateURL, options: .atomic)
        }
        NotificationManager.sync(with: profile)
    }

    /// Erase every scan + measurement but keep profile + onboarding state.
    func deleteAllScanData() {
        for s in scans {
            for c in s.captures {
                PhotoStore.delete(named: c.imageFilename)
            }
        }
        scans = []
        measurements = []
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.stateURL),
              let p = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        self.profile = p.profile
        self.measurements = p.measurements
        self.scans = p.scans
        self.hasCompletedOnboarding = p.hasCompletedOnboarding
        PurchaseService.shared.bind(to: profile)
    }
}
