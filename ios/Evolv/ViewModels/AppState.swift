import Foundation
import SwiftUI

@Observable
final class AppState {
    enum PersistenceError: LocalizedError {
        case couldNotEncode
        case couldNotSave

        var errorDescription: String? {
            switch self {
            case .couldNotEncode: return "Evolv couldn't prepare the updated scan."
            case .couldNotSave: return "Evolv couldn't save the updated scan to this device."
            }
        }
    }

    var profile = UserProfile()
    var measurements: [Measurement] = []
    var scans: [Scan] = []
    var validationSessions: [ValidationStudySession] = []
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
        validationSessions = (try? ValidationStudyStore.load()) ?? []
        refreshValidationSessionEligibility()
        protectExistingData()
        PurchaseService.shared.bind(to: profile)
        // Re-run canonical scans when evidence rules change; otherwise load the
        // most recent analysis from disk without blocking launch.
        if let firstOutdated = canonicalScans.first(where: { AnalysisStore.needsReanalysis(scanId: $0.id) }) {
            analyzeCanonicalScans(startingAt: firstOutdated.date)
        } else if let latestScanId = canonicalScans.last?.id {
            Task { @MainActor [weak self] in
                let analysis = await Task.detached(priority: .background) {
                    AnalysisStore.load(scanId: latestScanId)
                }.value
                self?.latestAnalysis = analysis
            }
        }
    }

    var calibrationState: CalibrationState {
        guard let analysis = latestAnalysis, analysis.analysisVersion >= AnalysisStore.currentAnalysisVersion else {
            return canonicalScans.isEmpty ? .noScans : .baselineSet
        }
        return CalibrationState.from(
            tier: analysis.smoothedSignals.reliabilityTier,
            confidence: analysis.confidence.overall,
            scanCount: canonicalScans.count
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
    var canonicalScans: [Scan] {
        sortedScans.filter(\.isCanonicalProgressScan)
    }
    var latestScan: Scan? { canonicalScans.last }
    var firstScan: Scan? { canonicalScans.first }
    var latestStoredScan: Scan? { sortedScans.last }
    var latestValidationSession: ValidationStudySession? {
        validationSessions.max { $0.startedAt < $1.startedAt }
    }
    var activeValidationSession: ValidationStudySession? {
        validationSessions
            .filter { $0.status == .active || $0.status == .evaluating }
            .max { $0.startedAt < $1.startedAt }
    }

    var hasAnyScans: Bool { !scans.isEmpty }

    func scan(id: UUID) -> Scan? { scans.first { $0.id == id } }

    func canonicalScan(on date: Date, calendar: Calendar = .current) -> Scan? {
        canonicalScans.last { calendar.isDate($0.date, inSameDayAs: date) }
    }

    var todayCanonicalScan: Scan? { canonicalScan(on: Date()) }

    func eligibleValidationAnchor(now: Date = Date()) -> Scan? {
        guard let scan = canonicalScan(on: now),
              ValidationStudyPolicy.eligibleCanonicalAnchor(scan, now: now) else {
            return nil
        }
        return scan
    }

    var nextRecommendedScanDate: Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        switch profile.cadence {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: today)
        case .weekly:
            let weekday = profile.effectiveScanWeekdays.first ?? profile.scanWeekday
            var components = DateComponents()
            components.weekday = weekday
            return calendar.nextDate(
                after: today,
                matching: components,
                matchingPolicy: .nextTime,
                direction: .forward
            )
        case .biweekly:
            let anchor = latestScan?.date ?? today
            return calendar.date(byAdding: .day, value: 14, to: calendar.startOfDay(for: anchor))
        case .monthly:
            let base = calendar.date(byAdding: .month, value: 1, to: today) ?? today
            var components = calendar.dateComponents([.year, .month], from: base)
            components.day = min(28, max(1, profile.scanDayOfMonth))
            return calendar.date(from: components)
        }
    }

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
        guard !canonicalScans.isEmpty else { return 0 }
        let cal = Calendar.current
        let bucket: Calendar.Component = {
            switch profile.cadence {
            case .daily: return .day
            case .weekly, .biweekly: return .weekOfYear
            case .monthly: return .month
            }
        }()
        let sorted = canonicalScans.map { $0.date }.sorted(by: >)
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

    // MARK: - Legacy score compatibility

    /// Numeric scores are retained only so old JSON remains decodable. Aspect
    /// ratio is not body framing, so new scans never invent these values.
    func computeConsistency(forNew captures: [PoseCapture]) -> (consistency: Int, lighting: Int, framing: Int) {
        (consistency: 0, lighting: 0, framing: 0)
    }

    // MARK: - Progress score (data-driven)

    var progressScore: ProgressScore {
        guard !canonicalScans.isEmpty else {
            return ProgressScore(value: 0, monthlyDelta: 0, weeklyDelta: 0, momentum: "Awaiting baseline")
        }
        guard canonicalScans.count > 1 else {
            return ProgressScore(value: 0, monthlyDelta: 0, weeklyDelta: 0, momentum: "Baseline set")
        }
        guard let analysis = latestAnalysis,
              analysis.analysisAvailability == .comparable,
              analysis.confidence.hasSufficientEvidence == true else {
            return ProgressScore(value: 0, monthlyDelta: 0, weeklyDelta: 0, momentum: "Building evidence")
        }
        return ProgressScore(
            value: Int((analysis.confidence.rawScore * 100).rounded()),
            monthlyDelta: 0,
            weeklyDelta: 0,
            momentum: "Evidence ready"
        )
    }

    // MARK: - Estimated deltas (data-driven, honest)

    var estimatedDeltas: [EstimatedDelta] {
        // Need baseline + recent measurement, otherwise return informational placeholders
        guard let baseline = measurements.first, measurements.count >= 2,
              let latest = measurements.last else { return [] }

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
        if let d = delta(baseline.thighs, latest.thighs) {
            out.append(makeDelta(label: "Thighs (measurement)", unit: "cm", value: d, goalDirection: .up))
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
        if canonicalScans.isEmpty {
            return WeeklySummary(
                headline: "Capture your first scan to begin.",
                detail: "Your first scan becomes the baseline Evolv quietly compares everything against.",
                confidence: .low
            )
        }
        if canonicalScans.count == 1 {
            let unavailable = latestScan?.recommendedRepairPoses ?? []
            let detail: String
            if unavailable.isEmpty {
                detail = "No progress result is calculated from one scan. Capture another complete upper-body scan to create a comparison."
            } else {
                detail = "Your baseline is saved. Automatic checks were unavailable for \(poseList(unavailable)); this does not mean those photos are poor."
            }
            return WeeklySummary(
                headline: "Baseline captured.",
                detail: detail,
                confidence: .low
            )
        }
        if analysisPending {
            return WeeklySummary(
                headline: "Analyzing supported regions.",
                detail: "Evolv will leave any region without enough evidence unavailable instead of guessing.",
                confidence: .low
            )
        }
        guard let analysis = latestAnalysis else {
            return WeeklySummary(
                headline: "Analysis is unavailable.",
                detail: "Your photos remain saved, but Evolv has not produced a supported progress result.",
                confidence: .low
            )
        }

        guard analysis.analysisVersion >= AnalysisStore.currentAnalysisVersion else {
            return WeeklySummary(
                headline: "Capture a new verified baseline.",
                detail: "Older scans remain saved, but their legacy quality scores are not treated as current evidence.",
                confidence: .low
            )
        }

        if analysis.analysisAvailability == .partialEvidence || analysis.analysisAvailability == .processingFailed {
            let unavailable = latestScan?.recommendedRepairPoses ?? []
            return WeeklySummary(
                headline: "Comparison saved with limited automatic analysis.",
                detail: unavailable.isEmpty
                    ? "Unsupported regions were excluded instead of guessed. Your photos remain saved."
                    : "Unsupported regions were excluded. You can review \(poseList(unavailable)) without replacing the rest of this scan.",
                confidence: .low
            )
        }

        if let insight = analysis.generatedInsight {
            return WeeklySummary(
                headline: insight.headline,
                detail: insight.detail,
                confidence: analysis.confidence.hasSufficientEvidence == true ? insight.confidence : .low
            )
        }

        return WeeklySummary(
            headline: "Building comparable evidence.",
            detail: "No supported progress claim is available yet.",
            confidence: .low
        )
    }

    // MARK: - Actions

    private func poseList(_ poses: [Pose]) -> String {
        let labels = poses.map(\.shortLabel)
        if labels.count <= 1 { return labels.first ?? "the affected pose" }
        if labels.count == 2 { return labels.joined(separator: " and ") }
        return labels.dropLast().joined(separator: ", ") + ", and " + (labels.last ?? "")
    }

    /// Adds a complete scan. Same-day extras are saved for documentation but
    /// are intentionally excluded from progress analysis.
    @discardableResult
    func addScan(captures: [PoseCapture], role: ScanRole = .canonical) throws -> UUID {
        guard ScanCaptureValidator.hasAllRequiredPoses(captures) else {
            throw PersistenceError.couldNotSave
        }

        let now = Date()
        let resolvedRole = ScanSchedulingPolicy.resolvedRole(
            requested: role,
            on: now,
            existingScans: scans
        )
        let isFirstCanonical = canonicalScans.isEmpty && resolvedRole == .canonical
        let scan = Scan(
            date: now,
            captures: captures,
            consistencyScore: 0,
            lightingScore: 0,
            framingScore: 0,
            note: nil,
            context: nil,
            analysisAvailability: resolvedRole == .canonical
                ? (isFirstCanonical ? .baselineOnly : .partialEvidence)
                : (resolvedRole == .sameDayExtra ? .documentationOnly : .validationOnly),
            captureCompleteness: .complete,
            scanRole: resolvedRole,
            lastModifiedAt: now
        )
        var candidate = scans
        candidate.append(scan)
        try persist(scans: candidate)
        scans = candidate
        NotificationManager.sync(with: profile)

        if resolvedRole == .canonical { analyzeCanonicalScans(startingAt: scan.date) }
        return scan.id
    }

    /// Atomically replaces selected poses. Existing files remain referenced
    /// until the updated state file is safely on disk.
    @discardableResult
    func replaceCaptures(in scanID: UUID, with replacements: [PoseCapture]) throws -> Scan {
        guard let index = scans.firstIndex(where: { $0.id == scanID }), !replacements.isEmpty else {
            throw PersistenceError.couldNotSave
        }
        var updated = scans[index]
        let merge = ScanCaptureMerge.replacing(updated.captures, with: replacements)
        updated.captures = merge.captures
        updated.captureCompleteness = ScanCaptureValidator.hasAllRequiredPoses(updated.captures) ? .complete : .incomplete
        updated.lastModifiedAt = Date()
        if updated.isCanonicalProgressScan {
            updated.analysisAvailability = updated.id == firstScan?.id ? .baselineOnly : .partialEvidence
        }

        var candidate = scans
        candidate[index] = updated
        try persist(scans: candidate)
        scans = candidate
        PhotoStore.delete(named: merge.supersededFilenames)
        NotificationManager.sync(with: profile)

        if updated.isCanonicalProgressScan {
            analyzeCanonicalScans(startingAt: updated.date)
        }
        invalidateValidationSession(containing: updated.id, reason: .scanModifiedAfterSet)
        return updated
    }

    /// Updates the scan context (pre-workout, fasted, hydration) on the most recently added scan.
    func updateLatestScanContext(preWorkout: Bool?, fasted: Bool?, hydration: HydrationState?) {
        guard let id = latestStoredScan?.id else { return }
        updateScanContext(scanID: id, preWorkout: preWorkout, fasted: fasted, hydration: hydration)
    }

    func updateScanContext(scanID: UUID, preWorkout: Bool?, fasted: Bool?, hydration: HydrationState?) {
        guard let idx = scans.firstIndex(where: { $0.id == scanID }) else { return }
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
        let candidate = scans.filter { $0.id != scan.id }
        guard (try? persist(scans: candidate)) != nil else { return }
        scans = candidate
        PhotoStore.delete(named: scan.captures.map(\.imageFilename))
        AnalysisStore.delete(scanId: scan.id)
        // Update latestAnalysis to the new latest scan's analysis (if any)
        if let newLatestId = canonicalScans.last?.id {
            latestAnalysis = AnalysisStore.load(scanId: newLatestId)
        } else {
            latestAnalysis = nil
        }
        NotificationManager.sync(with: profile)
        if scan.isCanonicalProgressScan, let firstRemaining = canonicalScans.first {
            analyzeCanonicalScans(startingAt: firstRemaining.date)
        }
        invalidateValidationSession(containing: scan.id, reason: .scanDeletedAfterSet)
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
        deleteValidationDraftPhotos()
        validationSessions = []
        ValidationStudyStore.deleteAll()
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
        try? persist(scans: scans)
        NotificationManager.sync(with: profile)
    }

    private func persist(
        scans candidateScans: [Scan],
        measurements candidateMeasurements: [Measurement]? = nil
    ) throws {
        let p = Persisted(
            profile: profile,
            measurements: candidateMeasurements ?? measurements,
            scans: candidateScans,
            hasCompletedOnboarding: hasCompletedOnboarding
        )
        guard let data = try? JSONEncoder().encode(p) else {
            throw PersistenceError.couldNotEncode
        }
        do {
            try data.write(to: Self.stateURL, options: [.atomic, .completeFileProtection])
        } catch {
            throw PersistenceError.couldNotSave
        }
    }

    /// Erase every scan + measurement but keep profile + onboarding state.
    func deleteAllScanData() {
        let storedScans = scans
        guard (try? persist(scans: [], measurements: [])) != nil else { return }
        for s in storedScans { PhotoStore.delete(named: s.captures.map(\.imageFilename)) }
        AnalysisStore.deleteAll()
        deleteValidationDraftPhotos()
        validationSessions = []
        ValidationStudyStore.deleteAll()
        scans = []
        measurements = []
        latestAnalysis = nil
        analysisPending = false
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

    private func protectExistingData() {
        PhotoStore.protectExistingFiles()
        AnalysisStore.protectExistingFiles()
        ValidationStudyStore.protectExistingFile()
        if FileManager.default.fileExists(atPath: Self.stateURL.path) {
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: Self.stateURL.path
            )
        }
    }

    // MARK: - Local consistency test

    @discardableResult
    func startValidationSession(
        cameraPosition: CaptureCameraPosition,
        useEligibleCanonical: Bool,
        pilotEnrollment: PilotLocalEnrollment? = PilotStudyStore.loadEnrollment(),
        now: Date = Date()
    ) throws -> UUID {
        refreshValidationSessionEligibility(now: now)
        guard activeValidationSession == nil else {
            throw ValidationStudyError.activeSessionExists
        }

        var candidateScans = scans
        var records: [ValidationSetRecord] = []
        var lockedLensType: String?
        var protocolStartedAt = now
        let sessionID = UUID()

        if useEligibleCanonical {
            guard let anchor = eligibleValidationAnchor(now: now),
                  let metadata = ValidationStudyPolicy.cameraConfiguration(for: anchor.captures),
                  metadata.position == cameraPosition,
                  let scanIndex = candidateScans.firstIndex(where: { $0.id == anchor.id }) else {
                throw ValidationStudyError.eligibleAnchorUnavailable
            }
            candidateScans[scanIndex].validationSessionID = sessionID
            candidateScans[scanIndex].validationSetNumber = 1
            candidateScans[scanIndex].lastModifiedAt = now
            records.append(ValidationSetRecord(
                setNumber: 1,
                scanID: anchor.id,
                completedAt: anchor.date,
                conditions: nil,
                comparison: nil,
                usedExistingCanonicalScan: true
            ))
            lockedLensType = metadata.lensType
            protocolStartedAt = anchor.date
        }

        let session = ValidationStudySession(
            id: sessionID,
            enrollment: ValidationEnrollment(
                enrolledAt: now,
                programVersion: ValidationStudySession.protocolVersion,
                shareScope: pilotEnrollment?.status == .active
                    ? pilotEnrollment?.consent.shareScope.validationScope ?? .localOnly
                    : .localOnly,
                consentVersion: pilotEnrollment?.status == .active
                    ? pilotEnrollment?.consent.version
                    : nil
            ),
            startedAt: protocolStartedAt,
            expiresAt: protocolStartedAt.addingTimeInterval(ValidationStudySession.maximumDuration),
            status: .active,
            lockedCameraPosition: cameraPosition,
            lockedLensType: lockedLensType,
            sets: records,
            draftSetNumber: nil,
            draftCaptures: [],
            result: nil,
            statusReasons: [],
            completedAt: nil
        )
        let candidateSessions = validationSessions + [session]

        if useEligibleCanonical {
            try persist(scans: candidateScans)
        }
        do {
            try ValidationStudyStore.save(candidateSessions)
        } catch {
            if useEligibleCanonical { try? persist(scans: scans) }
            throw error
        }
        scans = candidateScans
        validationSessions = candidateSessions
        return sessionID
    }

    func validationSession(id: UUID) -> ValidationStudySession? {
        validationSessions.first { $0.id == id }
    }

    func validationScans(sessionID: UUID) -> [Scan] {
        scans
            .filter { $0.validationSessionID == sessionID }
            .sorted { ($0.validationSetNumber ?? 0) < ($1.validationSetNumber ?? 0) }
    }

    func validationCaptureContext(sessionID: UUID) -> ValidationCaptureContext? {
        refreshValidationSessionEligibility()
        guard let session = validationSession(id: sessionID),
              session.status == .active,
              session.awaitingConditionsSetNumber == nil,
              !session.isComplete else { return nil }
        let setNumber = session.nextSetNumber
        let initial = session.draftSetNumber == setNumber ? session.draftCaptures : []
        return ValidationCaptureContext(
            sessionID: session.id,
            setNumber: setNumber,
            lockedCameraPosition: session.lockedCameraPosition,
            anchorScanID: session.anchorScanID,
            initialCaptures: initial
        )
    }

    func updateValidationDraft(
        sessionID: UUID,
        setNumber: Int,
        captures: [PoseCapture]
    ) throws {
        refreshValidationSessionEligibility()
        guard let index = validationSessions.firstIndex(where: { $0.id == sessionID }) else {
            throw ValidationStudyError.sessionUnavailable
        }
        guard validationSessions[index].status == .active else {
            let reason = validationSessions[index].statusReasons.last ?? .sessionExpired
            throw ValidationStudyError.sessionIneligible(reason)
        }
        guard validationSessions[index].nextSetNumber == setNumber,
              ValidationStudyPolicy.isValidDraft(
                  captures,
                  position: validationSessions[index].lockedCameraPosition,
                  lockedLensType: validationSessions[index].lockedLensType
              ) else {
            throw ValidationStudyError.invalidCameraConfiguration
        }
        var candidate = validationSessions
        candidate[index].draftSetNumber = setNumber
        candidate[index].draftCaptures = captures
        try ValidationStudyStore.save(candidate)
        validationSessions = candidate
    }

    func discardValidationDraft(sessionID: UUID) {
        guard let index = validationSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let filenames = validationSessions[index].draftCaptures.map(\.imageFilename)
        var candidate = validationSessions
        candidate[index].draftSetNumber = nil
        candidate[index].draftCaptures = []
        guard (try? ValidationStudyStore.save(candidate)) != nil else { return }
        validationSessions = candidate
        PhotoStore.delete(named: filenames)
    }

    @discardableResult
    func addValidationSet(
        sessionID: UUID,
        setNumber: Int,
        captures: [PoseCapture],
        now: Date = Date()
    ) throws -> UUID {
        refreshValidationSessionEligibility(now: now)
        guard let sessionIndex = validationSessions.firstIndex(where: { $0.id == sessionID }) else {
            throw ValidationStudyError.sessionUnavailable
        }
        var session = validationSessions[sessionIndex]
        guard session.status == .active else {
            let reason = session.statusReasons.last ?? .sessionExpired
            throw ValidationStudyError.sessionIneligible(reason)
        }
        guard ValidationStudyPolicy.isValidCompletedSet(
                  captures,
                  position: session.lockedCameraPosition,
                  lockedLensType: session.lockedLensType
              ),
              let configuration = ValidationStudyPolicy.cameraConfiguration(for: captures),
              session.awaitingConditionsSetNumber == nil,
              session.nextSetNumber == setNumber,
              configuration.position == session.lockedCameraPosition,
              session.lockedLensType == nil || session.lockedLensType == configuration.lensType else {
            throw ValidationStudyError.invalidCameraConfiguration
        }

        let role: ScanRole
        if setNumber == 1 {
            role = canonicalScan(on: now) == nil ? .canonical : .validationAnchor
        } else {
            role = .validationRepeat
        }
        let isFirstCanonical = canonicalScans.isEmpty && role == .canonical
        let scan = Scan(
            date: now,
            captures: captures,
            consistencyScore: 0,
            lightingScore: 0,
            framingScore: 0,
            note: nil,
            context: nil,
            analysisAvailability: role == .canonical
                ? (isFirstCanonical ? .baselineOnly : .partialEvidence)
                : .validationOnly,
            captureCompleteness: .complete,
            scanRole: role,
            lastModifiedAt: now,
            validationSessionID: sessionID,
            validationSetNumber: setNumber
        )

        var candidateScans = scans
        candidateScans.append(scan)
        session.lockedLensType = configuration.lensType
        session.draftSetNumber = nil
        session.draftCaptures = []
        session.sets.append(ValidationSetRecord(
            setNumber: setNumber,
            scanID: scan.id,
            completedAt: now,
            conditions: nil,
            comparison: nil,
            usedExistingCanonicalScan: false
        ))
        var candidateSessions = validationSessions
        candidateSessions[sessionIndex] = session

        try persist(scans: candidateScans)
        do {
            try ValidationStudyStore.save(candidateSessions)
        } catch {
            try? persist(scans: scans)
            throw error
        }
        scans = candidateScans
        validationSessions = candidateSessions
        NotificationManager.sync(with: profile)
        // Keep the five-set capture protocol free from competing background
        // Vision work. If Set 1 is today's canonical scan, it is analyzed only
        // after the local consistency evaluation has finished.
        return scan.id
    }

    func recordValidationConditions(
        sessionID: UUID,
        setNumber: Int,
        stayedTheSame: Bool,
        deviations: [ValidationDeviationReason],
        now: Date = Date()
    ) throws {
        refreshValidationSessionEligibility(now: now)
        guard let sessionIndex = validationSessions.firstIndex(where: { $0.id == sessionID }) else {
            throw ValidationStudyError.sessionUnavailable
        }
        guard validationSessions[sessionIndex].status == .active else {
            let reason = validationSessions[sessionIndex].statusReasons.last ?? .sessionExpired
            throw ValidationStudyError.sessionIneligible(reason)
        }
        guard
              let setIndex = validationSessions[sessionIndex].sets.firstIndex(where: { $0.setNumber == setNumber }),
              validationSessions[sessionIndex].sets[setIndex].conditions == nil,
              stayedTheSame || !deviations.isEmpty else {
            throw ValidationStudyError.conditionsRequired
        }
        var candidate = validationSessions
        candidate[sessionIndex].sets[setIndex].conditions = ValidationSetConditions(
            stayedTheSame: stayedTheSame,
            deviations: stayedTheSame ? [] : deviations.filter(\.isUserSelectable),
            recordedAt: now
        )
        if candidate[sessionIndex].isComplete {
            candidate[sessionIndex].status = .evaluating
        }
        try ValidationStudyStore.save(candidate)
        validationSessions = candidate
    }

    func evaluateValidationSession(sessionID: UUID, now: Date = Date()) async throws {
        guard let index = validationSessions.firstIndex(where: { $0.id == sessionID }),
              validationSessions[index].isComplete,
              validationSessions[index].sets.allSatisfy({ $0.conditions != nil }) else {
            throw PersistenceError.couldNotSave
        }
        var evaluating = validationSessions
        evaluating[index].status = .evaluating
        try ValidationStudyStore.save(evaluating)
        validationSessions = evaluating

        let snapshot = evaluating[index]
        let evaluation = await ValidationConsistencyEngine.evaluate(
            session: snapshot,
            scans: scans,
            now: now
        )
        guard let freshIndex = validationSessions.firstIndex(where: { $0.id == sessionID }) else {
            throw PersistenceError.couldNotSave
        }
        var completed = validationSessions
        for setIndex in completed[freshIndex].sets.indices {
            let number = completed[freshIndex].sets[setIndex].setNumber
            completed[freshIndex].sets[setIndex].comparison = evaluation.comparisonsBySet[number]
        }
        completed[freshIndex].result = evaluation.status
        completed[freshIndex].algorithmMetadata = evaluation.metadata
        completed[freshIndex].status = .completed
        completed[freshIndex].completedAt = now
        try ValidationStudyStore.save(completed)
        validationSessions = completed
        if let anchorID = completed[freshIndex].anchorScanID,
           let anchor = scan(id: anchorID),
           anchor.isCanonicalProgressScan,
           AnalysisStore.needsReanalysis(scanId: anchorID) {
            analyzeCanonicalScans(startingAt: anchor.date)
        }
    }

    func refreshValidationSessionEligibility(now: Date = Date()) {
        var candidate = validationSessions
        var changed = false
        for index in candidate.indices where candidate[index].status == .active {
            if case .ineligible(let reason) = candidate[index].eligibility(at: now) {
                candidate[index].status = .protocolIneligible
                if !candidate[index].statusReasons.contains(reason) {
                    candidate[index].statusReasons.append(reason)
                }
                candidate[index].result = .needsReview
                changed = true
            }
        }
        guard changed, (try? ValidationStudyStore.save(candidate)) != nil else { return }
        validationSessions = candidate
    }

    @discardableResult
    func startAnotherValidationSession(
        cameraPosition: CaptureCameraPosition,
        now: Date = Date()
    ) throws -> UUID {
        refreshValidationSessionEligibility(now: now)
        if let active = activeValidationSession,
           let index = validationSessions.firstIndex(where: { $0.id == active.id }) {
            var candidate = validationSessions
            candidate[index].status = .abandoned
            try ValidationStudyStore.save(candidate)
            validationSessions = candidate
        }
        return try startValidationSession(
            cameraPosition: cameraPosition,
            useEligibleCanonical: false,
            now: now
        )
    }

    private func invalidateValidationSession(
        containing scanID: UUID,
        reason: ValidationDeviationReason
    ) {
        guard let index = validationSessions.firstIndex(where: { session in
            session.sets.contains { $0.scanID == scanID }
        }) else { return }
        var candidate = validationSessions
        candidate[index].status = .protocolIneligible
        candidate[index].result = .needsReview
        if !candidate[index].statusReasons.contains(reason) {
            candidate[index].statusReasons.append(reason)
        }
        guard (try? ValidationStudyStore.save(candidate)) != nil else { return }
        validationSessions = candidate
    }

    private func deleteValidationDraftPhotos() {
        PhotoStore.delete(named: validationSessions.flatMap { $0.draftCaptures.map(\.imageFilename) })
    }

    private func analyzeCanonicalScans(startingAt date: Date) {
        let eligible = canonicalScans
        let targets = eligible.filter { $0.date >= date }.sorted { $0.date < $1.date }
        guard !targets.isEmpty else { return }
        analysisPending = true
        let allMeasurements = measurements
        let userProfile = profile

        Task {
            var newestAnalysis: ScanAnalysis?
            for target in targets {
                let analysis = await AnalysisPipeline.shared.analyzeNewScan(
                    scan: target,
                    allScans: eligible,
                    measurements: allMeasurements,
                    profile: userProfile
                )
                newestAnalysis = analysis
                await MainActor.run {
                    if let index = self.scans.firstIndex(where: { $0.id == target.id }) {
                        self.scans[index].analysisAvailability = analysis.analysisAvailability
                        self.scans[index].lastModifiedAt = Date()
                        self.save()
                    }
                }
                await PilotSubmissionCoordinator.shared.submitAutomaticOngoingResultsIfEligible(
                    scan: target,
                    analysis: analysis
                )
            }
            let finalNewestAnalysis = newestAnalysis
            await MainActor.run {
                if let latestID = self.latestScan?.id,
                   let latest = targets.last(where: { $0.id == latestID }) {
                    self.latestAnalysis = AnalysisStore.load(scanId: latest.id) ?? finalNewestAnalysis
                } else if let latestID = self.latestScan?.id {
                    self.latestAnalysis = AnalysisStore.load(scanId: latestID)
                }
                self.analysisPending = false
            }
        }
    }
}
