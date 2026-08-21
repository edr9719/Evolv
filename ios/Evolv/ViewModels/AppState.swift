import Foundation
import SwiftUI

@Observable
final class AppState {
    enum PersistenceError: LocalizedError {
        case couldNotEncode
        case couldNotSave
        case captureRecipeMismatch
        case cameraRequiredForNewBaseline
        case couldNotUpdateBackupPolicy

        var errorDescription: String? {
            switch self {
            case .couldNotEncode: return "Evolv couldn't prepare the updated scan."
            case .couldNotSave: return "Evolv couldn't save the updated scan to this device."
            case .captureRecipeMismatch:
                return "This camera setup does not match your saved capture recipe. Start a new baseline setup or save the photos without analysis."
            case .cameraRequiredForNewBaseline:
                return "A new baseline setup requires front, side, and back photos taken with the same in-app camera."
            case .couldNotUpdateBackupPolicy:
                return "Evolv couldn't update the Apple backup preference. Your previous setting is unchanged."
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
    /// Cached exact baseline-to-latest evidence for Home. Timeline custom
    /// comparisons are still calculated only when the selected pair changes.
    var latestPairComparison: ScanPairComparison? = nil
    /// Cached baseline-referenced history. A repeated pattern requires two
    /// uninterrupted supported observations; scan count alone is insufficient.
    var longitudinalVisualSummary: LongitudinalVisualSummary? = nil
    var analysisPending: Bool = false

    // Persisted under Documents/state.json
    private static var stateURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("evolv-state.json")
    }

    init() {
        load()
        let migratedRecipe = migrateLegacyCaptureRecipeIfPossible()
        try? DeviceBackupPolicy.setLocalOnly(profile.usesLocalOnlyStorage)
        if migratedRecipe { try? persist(scans: scans) }
        validationSessions = (try? ValidationStudyStore.load()) ?? []
        refreshValidationSessionEligibility()
        protectExistingData()
        PurchaseService.shared.bind(to: profile)
        // Re-run canonical scans when evidence rules change; otherwise load the
        // most recent analysis from disk without blocking launch.
        if let firstOutdated = activeCanonicalScans.first(where: { AnalysisStore.needsReanalysis(scanId: $0.id) }) {
            analyzeCanonicalScans(startingAt: firstOutdated.date)
        } else if let latestScanId = activeLatestScan?.id {
            Task { @MainActor [weak self] in
                let analysis = await Task.detached(priority: .background) {
                    AnalysisStore.load(scanId: latestScanId)
                }.value
                self?.latestAnalysis = analysis
                self?.refreshLatestPairComparison()
            }
        }
    }

    var calibrationState: CalibrationState {
        guard let analysis = latestAnalysis, analysis.analysisVersion >= AnalysisStore.currentAnalysisVersion else {
            return activeCanonicalScans.isEmpty ? .noScans : .baselineSet
        }
        return CalibrationState.from(
            tier: analysis.smoothedSignals.reliabilityTier,
            confidence: analysis.confidence.overall,
            scanCount: activeCanonicalScans.count
        )
    }

    /// True when the current product configuration grants full access or an
    /// eventual StoreKit entitlement is active.
    var isPremium: Bool {
        Build17PilotConfiguration.hasFullProductAccess(
            subscriptionActive: PurchaseService.shared.isSubscribed
        )
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
    var activeCaptureRecipe: CaptureRecipe? { profile.captureRecipe }
    var activeCanonicalScans: [Scan] {
        guard let recipeID = activeCaptureRecipe?.id else { return canonicalScans }
        return canonicalScans.filter { $0.captureRecipeID == recipeID }
    }
    var activeBaselineScan: Scan? {
        activeCanonicalScans.first
    }
    var activeLatestScan: Scan? { activeCanonicalScans.last }
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

    /// Returns evidence for exactly the two canonical scans selected by the
    /// user. The result is derived locally and does not replace the canonical
    /// baseline-to-current analysis stored for either scan.
    func comparison(beforeID: UUID?, afterID: UUID?) -> ScanPairComparison? {
        guard let beforeID, let afterID,
              let before = scan(id: beforeID), let after = scan(id: afterID) else { return nil }
        return ScanPairComparisonEngine.compare(
            before: before,
            after: after,
            beforeAnalysis: AnalysisStore.load(scanId: before.id),
            afterAnalysis: AnalysisStore.load(scanId: after.id)
        )
    }

    func comparisonNarrative(
        for comparison: ScanPairComparison?,
        pose: Pose? = nil
    ) -> ComparisonNarrative {
        ComparisonNarrativeEngine.make(
            comparison: comparison,
            pose: pose,
            goal: profile.goal
        )
    }

    var currentProgressNarrative: ComparisonNarrative? {
        guard activeCanonicalScans.count >= 2, let latestPairComparison else { return nil }
        return comparisonNarrative(for: latestPairComparison)
    }

    var currentLongitudinalNarrative: LongitudinalPatternNarrative? {
        LongitudinalVisualEngine.narrative(for: longitudinalVisualSummary)
    }

    func measurement(for scanID: UUID) -> Measurement? {
        MeasurementSignalEngine.measurement(for: scanID, in: measurements)
    }

    func measurementComparison(
        beforeID: UUID?,
        afterID: UUID?,
        visualComparison: ScanPairComparison? = nil
    ) -> ScanPairMeasurementComparison? {
        guard let beforeID, let afterID,
              scan(id: beforeID) != nil, scan(id: afterID) != nil else { return nil }
        return MeasurementSignalEngine.compare(
            beforeScanID: beforeID,
            afterScanID: afterID,
            measurements: measurements,
            visualComparison: visualComparison
        )
    }

    var currentMeasurementComparison: ScanPairMeasurementComparison? {
        guard activeCanonicalScans.count >= 2 else { return nil }
        return measurementComparison(
            beforeID: activeBaselineScan?.id,
            afterID: activeLatestScan?.id,
            visualComparison: latestPairComparison
        )
    }

    func baselineScan(for recipeID: UUID?) -> Scan? {
        canonicalScans.first { $0.captureRecipeID == recipeID }
    }

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
            let anchor = activeLatestScan?.date ?? today
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
        guard let first = activeBaselineScan?.date else { return 0 }
        return max(0, Calendar.current.dateComponents([.weekOfYear], from: first, to: Date()).weekOfYear ?? 0)
    }

    var daysSinceLastScan: Int {
        guard let d = activeLatestScan?.date else { return 0 }
        return Calendar.current.dateComponents([.day], from: d, to: Date()).day ?? 0
    }

    var currentStreak: Int {
        guard !activeCanonicalScans.isEmpty else { return 0 }
        let cal = Calendar.current
        let bucket: Calendar.Component = {
            switch profile.cadence {
            case .daily: return .day
            case .weekly, .biweekly: return .weekOfYear
            case .monthly: return .month
            }
        }()
        let sorted = activeCanonicalScans.map { $0.date }.sorted(by: >)
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
        guard !activeCanonicalScans.isEmpty else {
            return ProgressScore(value: 0, monthlyDelta: 0, weeklyDelta: 0, momentum: "Awaiting baseline")
        }
        guard activeCanonicalScans.count > 1 else {
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

    // MARK: - Weekly AI summary (data-driven, honest)

    var weeklySummary: WeeklySummary {
        if activeCanonicalScans.isEmpty {
            return WeeklySummary(
                headline: "Capture your first scan to begin.",
                detail: "Your first scan becomes the baseline Evolv quietly compares everything against.",
                confidence: .low
            )
        }
        if activeCanonicalScans.count == 1 {
            let recommended = activeLatestScan?.recommendedRepairPoses ?? []
            let detail: String
            if recommended.isEmpty {
                detail = "No progress result is calculated from one scan. Capture another complete upper-body scan to create a comparison."
            } else {
                detail = "Your baseline is saved. Evolv detected a specific capture issue in \(poseList(recommended)); review those photos before the next comparison."
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
            let recommended = activeLatestScan?.recommendedRepairPoses ?? []
            return WeeklySummary(
                headline: "Comparison saved with limited automatic analysis.",
                detail: recommended.isEmpty
                    ? "Unsupported regions were excluded instead of guessed. Your photos remain saved."
                    : "Unsupported regions were excluded. Evolv also detected a specific capture issue in \(poseList(recommended)).",
                confidence: .low
            )
        }

        if activeCanonicalScans.count >= 3,
           let longitudinal = currentLongitudinalNarrative {
            return WeeklySummary(
                headline: longitudinal.headline,
                detail: longitudinal.detail + " " + longitudinal.caveat,
                confidence: longitudinalVisualSummary?.thresholdsValidated == true ? .medium : .low
            )
        }

        if let narrative = currentProgressNarrative {
            let limitation = narrative.limitations.first ?? "Only supported evidence is described."
            return WeeklySummary(
                headline: narrative.headline,
                detail: narrative.detail + " " + limitation,
                confidence: narrative.evidenceStrength
            )
        }

        // Backward-compatible fallback while the exact pair cache is loading.
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
    func addScan(
        captures: [PoseCapture],
        role: ScanRole = .canonical,
        configurationIntent: CaptureConfigurationIntent = .matchActiveRecipe
    ) throws -> UUID {
        guard ScanCaptureValidator.hasAllRequiredPoses(captures) else {
            throw PersistenceError.couldNotSave
        }

        let now = Date()
        let requestedRole: ScanRole = configurationIntent == .documentationOnly
            ? .documentationOnly
            : role
        let resolvedRole = ScanSchedulingPolicy.resolvedRole(
            requested: requestedRole,
            on: now,
            existingScans: scans
        )
        let derivedRecipe = CaptureRecipe.derive(from: captures)
        var candidateProfile = profile
        let recipeID: UUID?

        switch configurationIntent {
        case .matchActiveRecipe:
            if resolvedRole == .canonical,
               let active = activeCaptureRecipe,
               let derivedRecipe,
               !active.isCompatible(with: derivedRecipe) {
                throw PersistenceError.captureRecipeMismatch
            }
            if let active = activeCaptureRecipe {
                recipeID = active.id
            } else if resolvedRole == .canonical, let derivedRecipe {
                candidateProfile.captureRecipe = derivedRecipe
                recipeID = derivedRecipe.id
            } else {
                recipeID = nil
            }
        case .startNewBaseline:
            guard resolvedRole == .canonical, let derivedRecipe else {
                throw PersistenceError.cameraRequiredForNewBaseline
            }
            candidateProfile.captureRecipe = derivedRecipe
            recipeID = derivedRecipe.id
        case .documentationOnly:
            recipeID = activeCaptureRecipe?.id
        }

        let isFirstCanonical = resolvedRole == .canonical
            && !canonicalScans.contains { $0.captureRecipeID == recipeID }
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
                : (resolvedRole == .validationAnchor || resolvedRole == .validationRepeat
                    ? .validationOnly
                    : .documentationOnly),
            captureCompleteness: .complete,
            scanRole: resolvedRole,
            lastModifiedAt: now,
            captureRecipeID: recipeID
        )
        var candidate = scans
        candidate.append(scan)
        try persist(scans: candidate, profile: candidateProfile)
        scans = candidate
        profile = candidateProfile
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
            updated.analysisAvailability = updated.id == baselineScan(for: updated.captureRecipeID)?.id
                ? .baselineOnly
                : .partialEvidence
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
        let candidateMeasurements = measurements.map { measurement -> Measurement in
            guard measurement.scanID == scan.id else { return measurement }
            var unlinked = measurement
            unlinked.scanID = nil
            return unlinked
        }
        guard (try? persist(scans: candidate, measurements: candidateMeasurements)) != nil else { return }
        scans = candidate
        measurements = candidateMeasurements
        PhotoStore.delete(named: scan.captures.map(\.imageFilename))
        AnalysisStore.delete(scanId: scan.id)
        // Update latestAnalysis to the new latest scan's analysis (if any)
        if let newLatestId = activeLatestScan?.id {
            latestAnalysis = AnalysisStore.load(scanId: newLatestId)
        } else {
            latestAnalysis = nil
        }
        refreshLatestPairComparison()
        NotificationManager.sync(with: profile)
        if scan.isCanonicalProgressScan, let firstRemaining = canonicalScans.first {
            analyzeCanonicalScans(startingAt: firstRemaining.date)
        }
        invalidateValidationSession(containing: scan.id, reason: .scanDeletedAfterSet)
    }

    func addMeasurement(_ m: Measurement) {
        try? upsertMeasurement(m)
    }

    /// Persists a measurement atomically. A scan can have only one linked
    /// measurement; editing it replaces the existing record without creating
    /// duplicate facts for the same scan.
    func upsertMeasurement(_ measurement: Measurement) throws {
        var candidate = measurements.filter { existing in
            if existing.id == measurement.id { return false }
            if let scanID = measurement.scanID, existing.scanID == scanID { return false }
            return true
        }
        candidate.append(measurement)
        candidate.sort { $0.date < $1.date }
        try persist(scans: scans, measurements: candidate)
        measurements = candidate
    }

    func deleteMeasurement(id: UUID) throws {
        let candidate = measurements.filter { $0.id != id }
        try persist(scans: scans, measurements: candidate)
        measurements = candidate
    }

    func finishOnboarding(initialMeasurement: Measurement?) {
        if let m = initialMeasurement {
            measurements.append(m)
        }
        hasCompletedOnboarding = true
        save()
    }

    func setLocalOnlyStorage(_ enabled: Bool) throws {
        let previous = profile.usesLocalOnlyStorage
        do {
            try DeviceBackupPolicy.setLocalOnly(enabled)
            var candidateProfile = profile
            candidateProfile.localOnlyStorageEnabled = enabled
            try persist(scans: scans, profile: candidateProfile)
            profile = candidateProfile
        } catch {
            try? DeviceBackupPolicy.setLocalOnly(previous)
            throw PersistenceError.couldNotUpdateBackupPolicy
        }
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
        try? DeviceBackupPolicy.setLocalOnly(false)
        hasCompletedOnboarding = false
        latestAnalysis = nil
        latestPairComparison = nil
        longitudinalVisualSummary = nil
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
        measurements candidateMeasurements: [Measurement]? = nil,
        profile candidateProfile: UserProfile? = nil
    ) throws {
        let p = Persisted(
            profile: candidateProfile ?? profile,
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
        latestPairComparison = nil
        longitudinalVisualSummary = nil
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
        try? DeviceBackupPolicy.applyStoredPreference()
    }

    /// Earlier builds stored camera metadata per photo but had no capture
    /// recipe. Preserve the existing first-baseline behavior by assigning one
    /// stable recipe identifier to the existing canonical history. Individual
    /// mismatched poses are still rejected by the camera-comparability gate.
    @discardableResult
    private func migrateLegacyCaptureRecipeIfPossible() -> Bool {
        guard profile.captureRecipe == nil,
              let first = canonicalScans.first,
              let recipe = CaptureRecipe.derive(from: first.captures) else { return false }
        profile.captureRecipe = recipe
        for index in scans.indices where scans[index].isCanonicalProgressScan {
            scans[index].captureRecipeID = recipe.id
        }
        return true
    }

    // MARK: - Local consistency test

    /// Entry point for the invited five-set protocol. The existing lower-level
    /// starter remains available for deliberately local engineering tests, but
    /// the user-facing official pilot cannot be created without active consent.
    @discardableResult
    func startOfficialValidationSession(
        cameraPosition: CaptureCameraPosition,
        pilotEnrollment: PilotLocalEnrollment? = PilotStudyStore.loadEnrollment(),
        now: Date = Date()
    ) throws -> UUID {
        guard ValidationStudyPolicy.canStartOfficialPilot(enrollment: pilotEnrollment) else {
            throw ValidationStudyError.pilotEnrollmentRequired
        }
        return try startValidationSession(
            cameraPosition: cameraPosition,
            useEligibleCanonical: false,
            pilotEnrollment: pilotEnrollment,
            now: now
        )
    }

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
            completedAt: nil,
            baselinePreflightRequired: !useEligibleCanonical,
            baselinePreflight: nil
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
        if candidate[index].draftSetPreflight?.matches(captures) != true {
            candidate[index].draftSetPreflight = nil
        }
        if setNumber == 1,
           candidate[index].baselinePreflight?.matches(captures) != true {
            candidate[index].baselinePreflight = nil
        }
        try ValidationStudyStore.save(candidate)
        validationSessions = candidate
    }

    func discardValidationDraft(sessionID: UUID) {
        guard let index = validationSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let filenames = validationSessions[index].draftCaptures.map(\.imageFilename)
        var candidate = validationSessions
        candidate[index].draftSetNumber = nil
        candidate[index].draftCaptures = []
        candidate[index].draftSetPreflight = nil
        if candidate[index].nextSetNumber == 1 {
            candidate[index].baselinePreflight = nil
        }
        guard (try? ValidationStudyStore.save(candidate)) != nil else { return }
        validationSessions = candidate
        PhotoStore.delete(named: filenames)
    }

    /// Runs and durably records the same downstream evidence path used by the
    /// final consistency comparison. The result is tied to exact capture IDs so
    /// replacing any photo necessarily requires a fresh check.
    func preflightValidationBaseline(
        sessionID: UUID,
        captures: [PoseCapture],
        now: Date = Date()
    ) async throws -> ValidationBaselinePreflight {
        refreshValidationSessionEligibility(now: now)
        guard let initialIndex = validationSessions.firstIndex(where: { $0.id == sessionID }),
              validationSessions[initialIndex].status == .active,
              validationSessions[initialIndex].nextSetNumber == 1,
              ValidationStudyPolicy.isValidCompletedSet(
                captures,
                position: validationSessions[initialIndex].lockedCameraPosition,
                lockedLensType: validationSessions[initialIndex].lockedLensType
              ) else {
            throw ValidationStudyError.invalidCameraConfiguration
        }

        let preflight = await ValidationConsistencyEngine.preflightBaseline(
            captures: captures,
            scanID: sessionID,
            now: now
        )

        refreshValidationSessionEligibility(now: now)
        guard let freshIndex = validationSessions.firstIndex(where: { $0.id == sessionID }),
              validationSessions[freshIndex].status == .active,
              validationSessions[freshIndex].nextSetNumber == 1,
              validationSessions[freshIndex].draftSetNumber == 1,
              Set(validationSessions[freshIndex].draftCaptures.map(\.id)) == Set(captures.map(\.id)) else {
            throw ValidationStudyError.sessionUnavailable
        }
        var candidate = validationSessions
        candidate[freshIndex].baselinePreflight = preflight
        try ValidationStudyStore.save(candidate)
        validationSessions = candidate
        return preflight
    }

    /// Strictly compares a repeat draft with the exact Set 1 anchor before the
    /// set can be committed. The saved result is invalidated by any capture-ID
    /// change in updateValidationDraft.
    func preflightValidationRepeat(
        sessionID: UUID,
        setNumber: Int,
        captures: [PoseCapture],
        now: Date = Date()
    ) async throws -> ValidationSetPreflight {
        refreshValidationSessionEligibility(now: now)
        guard setNumber > 1,
              let initialIndex = validationSessions.firstIndex(where: { $0.id == sessionID }),
              validationSessions[initialIndex].status == .active,
              validationSessions[initialIndex].nextSetNumber == setNumber,
              let anchorID = validationSessions[initialIndex].anchorScanID,
              let anchor = scan(id: anchorID),
              ValidationStudyPolicy.isValidCompletedSet(
                captures,
                position: validationSessions[initialIndex].lockedCameraPosition,
                lockedLensType: validationSessions[initialIndex].lockedLensType
              ) else {
            throw ValidationStudyError.invalidCameraConfiguration
        }

        let preflight = await ValidationConsistencyEngine.preflightRepeat(
            baselineCaptures: anchor.captures,
            currentCaptures: captures,
            setNumber: setNumber,
            scanID: sessionID,
            now: now
        )

        refreshValidationSessionEligibility(now: now)
        guard let freshIndex = validationSessions.firstIndex(where: { $0.id == sessionID }),
              validationSessions[freshIndex].status == .active,
              validationSessions[freshIndex].nextSetNumber == setNumber,
              validationSessions[freshIndex].draftSetNumber == setNumber,
              Set(validationSessions[freshIndex].draftCaptures.map(\.id)) == Set(captures.map(\.id)) else {
            throw ValidationStudyError.sessionUnavailable
        }
        var candidate = validationSessions
        candidate[freshIndex].draftSetPreflight = preflight
        try ValidationStudyStore.save(candidate)
        validationSessions = candidate
        return preflight
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
        guard ValidationStudyPolicy.hasRequiredBaselineEvidence(
            session: session,
            committingSetNumber: setNumber,
            captures: captures
        ) else {
            throw ValidationStudyError.baselineEvidenceRequired
        }
        let repeatPreflight: ValidationSetPreflight?
        if setNumber > 1 {
            guard ValidationStudyPolicy.hasRequiredRepeatEvidence(
                session: session,
                committingSetNumber: setNumber,
                captures: captures
            ), let checked = session.draftSetPreflight else {
                throw ValidationStudyError.repeatEvidenceRequired
            }
            repeatPreflight = checked
        } else {
            repeatPreflight = nil
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
        session.draftSetPreflight = nil
        session.sets.append(ValidationSetRecord(
            setNumber: setNumber,
            scanID: scan.id,
            completedAt: now,
            conditions: nil,
            comparison: repeatPreflight?.comparison,
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
                if let latestID = self.activeLatestScan?.id,
                   let latest = targets.last(where: { $0.id == latestID }) {
                    self.latestAnalysis = AnalysisStore.load(scanId: latest.id) ?? finalNewestAnalysis
                } else if let latestID = self.activeLatestScan?.id {
                    self.latestAnalysis = AnalysisStore.load(scanId: latestID)
                }
                self.refreshLatestPairComparison()
                self.analysisPending = false
            }
        }
    }

    private func refreshLatestPairComparison() {
        let analyses = Dictionary(uniqueKeysWithValues: activeCanonicalScans.compactMap { scan in
            AnalysisStore.load(scanId: scan.id).map { (scan.id, $0) }
        })
        longitudinalVisualSummary = LongitudinalVisualEngine.evaluate(
            scans: activeCanonicalScans,
            analyses: analyses
        )
        guard let before = activeBaselineScan,
              let after = activeLatestScan,
              before.id != after.id else {
            latestPairComparison = nil
            return
        }
        latestPairComparison = ScanPairComparisonEngine.compare(
            before: before,
            after: after,
            beforeAnalysis: analyses[before.id],
            afterAnalysis: analyses[after.id]
        )
    }
}
