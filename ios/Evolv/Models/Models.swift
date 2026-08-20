import Foundation
import SwiftUI

// MARK: - Enums

enum FitnessGoal: String, CaseIterable, Identifiable, Codable {
    case muscleGain = "Muscle Gain"
    case fatLoss = "Fat Loss"
    case recomp = "Recomposition"
    case maintain = "Maintain Physique"
    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .muscleGain: return "Build size and strength over time"
        case .fatLoss:    return "Reduce body fat while preserving muscle"
        case .recomp:     return "Lose fat and gain muscle at the same time"
        case .maintain:   return "Hold your current physique and track consistency"
        }
    }
    var icon: String {
        switch self {
        case .muscleGain: return "figure.strengthtraining.traditional"
        case .fatLoss:    return "flame"
        case .recomp:     return "arrow.triangle.2.circlepath"
        case .maintain:   return "checkmark.shield"
        }
    }
}

enum Experience: String, CaseIterable, Identifiable, Codable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
    var id: String { rawValue }
    var subtitle: String {
        switch self {
        case .beginner:     return "Less than 1 year of consistent training"
        case .intermediate: return "1–3 years training with steady progress"
        case .advanced:     return "3+ years, dialed-in routine and form"
        }
    }
}

enum MassUnit: String, CaseIterable, Identifiable, Codable {
    case kg, lb
    var id: String { rawValue }
    var label: String { self == .kg ? "kg" : "lb" }
}

enum LengthUnit: String, CaseIterable, Identifiable, Codable {
    case cm, inch
    var id: String { rawValue }
    var label: String { self == .cm ? "cm" : "in" }
}

enum Cadence: String, CaseIterable, Identifiable, Codable {
    case daily = "Daily"
    case weekly = "Weekly"
    case biweekly = "Biweekly"
    case monthly = "Monthly"
    var id: String { rawValue }
    var description: String {
        switch self {
        case .daily:    return "Best for short challenges or cuts"
        case .weekly:   return "Recommended for consistent long-term tracking"
        case .biweekly: return "Lighter cadence, still captures trends"
        case .monthly:  return "Long-term physique documentation"
        }
    }
    var isRecommended: Bool { self == .weekly }
}

enum TrendStatus: String, Codable {
    case improving, stable, stalled
    var label: String {
        switch self {
        case .improving: return "Improving"
        case .stable:    return "Stable"
        case .stalled:   return "Stalled"
        }
    }
}

enum Confidence: String, Codable, Hashable {
    case high, medium, low
    var label: String {
        switch self {
        case .high:   return "High"
        case .medium: return "Medium"
        case .low:    return "Low"
        }
    }
}

/// Pose categories — relaxed poses are required; showcase poses are optional.
/// Optional does not mean ignored: when the same optional pose exists in both
/// scans, Evolv may produce a separate same-pose visual comparison for it.
enum PoseCategory: String, Codable { case standard, showcase }

enum Pose: String, CaseIterable, Codable, Identifiable {
    // Required (standard)
    case front
    case side
    case back
    // Optional (showcase)
    case frontDoubleBicep
    case sideChest
    case backDoubleBicep
    case mostMuscular
    case relaxedAesthetic
    case legs

    var id: String { rawValue }

    var category: PoseCategory {
        switch self {
        case .front, .side, .back: return .standard
        default: return .showcase
        }
    }

    /// Framing expectation used by the quality gate. Relaxed poses include the
    /// upper legs because reliable hip evidence is required downstream.
    enum Framing { case torsoUp, fullBody, legsOnly }
    var framing: Framing {
        switch self {
        case .front, .side, .back,
             .frontDoubleBicep, .sideChest, .backDoubleBicep,
             .mostMuscular, .relaxedAesthetic:
            return .torsoUp
        case .legs: return .legsOnly
        }
    }

    static let required: [Pose] = [.front, .side, .back]
    static let showcase: [Pose] = [.frontDoubleBicep, .sideChest, .backDoubleBicep, .mostMuscular, .relaxedAesthetic, .legs]

    var label: String {
        switch self {
        case .front: return "Front relaxed"
        case .side:  return "Side relaxed"
        case .back:  return "Back relaxed"
        case .frontDoubleBicep: return "Front double bicep"
        case .sideChest:        return "Side chest"
        case .backDoubleBicep:  return "Back double bicep"
        case .mostMuscular:     return "Most muscular"
        case .relaxedAesthetic: return "Relaxed aesthetic"
        case .legs:             return "Legs"
        }
    }

    var shortLabel: String {
        switch self {
        case .front: return "Front"
        case .side:  return "Side"
        case .back:  return "Back"
        case .frontDoubleBicep: return "Front DB"
        case .sideChest:        return "Side chest"
        case .backDoubleBicep:  return "Back DB"
        case .mostMuscular:     return "Most muscular"
        case .relaxedAesthetic: return "Aesthetic"
        case .legs:             return "Legs"
        }
    }

    var subtitle: String {
        switch self {
        case .front: return "Head through mid-thigh. Keep both hip creases, upper legs, and relaxed arms visible."
        case .side:  return "True profile, head through mid-thigh. Keep the hip crease, upper legs, and relaxed arm visible."
        case .back:  return "Head through mid-thigh. Keep both hips and upper legs visible at the front photo's distance."
        case .frontDoubleBicep: return "Hands through upper thighs. Keep both elbows inside the frame."
        case .sideChest:        return "Head through upper thighs. Keep the complete arm position visible."
        case .backDoubleBicep:  return "Hands through upper thighs. Keep both elbows inside the frame."
        case .mostMuscular:     return "Head through upper thighs. Keep both hands and elbows visible."
        case .relaxedAesthetic: return "Head through upper thighs. Use the same three-quarter angle each time."
        case .legs:             return "Waist through feet. Keep both knees, ankles, and feet visible."
        }
    }

    /// Static instructional photos bundled with the app. They demonstrate
    /// composition only and are never used as analytical body targets.
    var referenceAssetName: String {
        switch self {
        case .front:             return "pose-reference-front-relaxed"
        case .side:              return "pose-reference-side-relaxed"
        case .back:              return "pose-reference-back-relaxed"
        case .frontDoubleBicep:  return "pose-reference-front-double-biceps"
        case .sideChest:         return "pose-reference-side-chest"
        case .backDoubleBicep:   return "pose-reference-back-double-biceps"
        case .mostMuscular:      return "pose-reference-most-muscular"
        case .relaxedAesthetic:  return "pose-reference-relaxed-aesthetic"
        case .legs:              return "pose-reference-legs"
        }
    }

    var referenceFramingText: String {
        switch self {
        case .frontDoubleBicep, .backDoubleBicep:
            return "Raised hands through upper thighs"
        case .legs:
            return "Waist through feet"
        case .front, .side, .back:
            return "Head through mid-thigh"
        default:
            return "Head through upper thighs"
        }
    }

    var cameraHeightText: String {
        switch self {
        case .front, .side, .back, .legs:
            return "Phone at waist height"
        default:
            return "Phone at lower-chest height"
        }
    }

    func reviewChecklist(matchingPrevious: Bool) -> [String] {
        let matchText = matchingPrevious ? "Angle matches previous photo" : "Angle matches pose example"
        switch self {
        case .legs:
            return [
                "Waist and both feet visible",
                "Knees and ankles unobstructed",
                "No strong connected shadow",
                matchingPrevious ? "Stance matches previous photo" : "Stance matches pose example"
            ]
        case .frontDoubleBicep, .backDoubleBicep:
            return [
                "Hands, elbows, and hips visible",
                "Both arms clear of frame edges",
                "No strong connected shadow",
                matchText
            ]
        case .sideChest, .mostMuscular:
            return [
                "Head, hips, hands, and elbows visible",
                "Torso is not hidden by the arms",
                "No strong connected shadow",
                matchText
            ]
        default:
            return [
                "Head, hip creases, and upper thighs visible",
                "Arms separated from torso",
                "No strong connected shadow",
                matchText
            ]
        }
    }

    var icon: String {
        switch self {
        case .front, .frontDoubleBicep, .mostMuscular, .relaxedAesthetic: return "figure.stand"
        case .side, .sideChest: return "figure.walk"
        case .back, .backDoubleBicep: return "figure.stand.line.dotted.figure.stand"
        case .legs: return "figure.run"
        }
    }
}

// MARK: - Data models

struct UserProfile: Codable {
    var goal: FitnessGoal = .muscleGain
    var heightCm: Double = 178
    var weightKg: Double = 76
    var experience: Experience = .intermediate
    var cadence: Cadence = .weekly

    // Optional baseline measurements (cm)
    var arms: Double? = nil
    var chest: Double? = nil
    var waist: Double? = nil
    var shoulders: Double? = nil
    var thighs: Double? = nil

    // Scan schedule
    /// Selected scan weekdays (Calendar weekday: 1=Sun ... 7=Sat).
    /// - Daily: always all 7 days (1...7)
    /// - Weekly: exactly 1 day
    /// - Biweekly: 1 or 2 days
    /// - Monthly: 1 day (used as fallback preferred weekday)
    var scanWeekdays: [Int] = [2]
    /// Legacy single-weekday field. Still persisted so existing data continues to load.
    var scanWeekday: Int = 2
    var scanDayOfMonth: Int = 1       // 1...28
    var biweeklyOffset: Int = 0       // 0 = this week, 1 = next week

    // Reminders
    var remindersEnabled: Bool = false
    var reminderHour: Int = 20        // 24h
    var reminderMinute: Int = 0

    // Units (display only — storage is always kg/cm internally)
    var massUnit: MassUnit = .kg
    var lengthUnit: LengthUnit = .cm

    // Subscription
    var subscriptionPlan: String? = nil      // "monthly" | "yearly" | nil
    var subscriptionStartedAt: Date? = nil
    var trialEndsAt: Date? = nil
    var hasSeenPostOnboardingPaywall: Bool = false
    /// Cloud-written wording is opt-in. A nil value belongs to a profile saved
    /// before the preference existed and is treated as disabled.
    var cloudInsightsEnabled: Bool? = nil
    /// The active camera setup used by canonical progress scans. Optional so
    /// profiles created before capture recipes existed remain decodable.
    var captureRecipe: CaptureRecipe? = nil
    /// False/nil keeps Apple's normal device-backup behavior. Enabling this
    /// excludes Evolv's Documents data from Apple device backups.
    var localOnlyStorageEnabled: Bool? = nil

    var usesCloudInsights: Bool { cloudInsightsEnabled == true }
    var usesLocalOnlyStorage: Bool { localOnlyStorageEnabled == true }

    /// Returns the weekdays the user actually wants reminders on, given cadence.
    var effectiveScanWeekdays: [Int] {
        switch cadence {
        case .daily:
            return [1,2,3,4,5,6,7]
        case .weekly:
            if let first = scanWeekdays.first { return [first] }
            return [scanWeekday]
        case .biweekly:
            let raw = scanWeekdays.isEmpty ? [scanWeekday] : scanWeekdays
            return Array(raw.prefix(2))
        case .monthly:
            if let first = scanWeekdays.first { return [first] }
            return [scanWeekday]
        }
    }
}

struct Measurement: Identifiable, Codable {
    var id = UUID()
    var date: Date
    /// Nil means the user deliberately skipped weight for this entry. Legacy
    /// JSON numbers continue to decode unchanged.
    var weightKg: Double?
    var arms: Double?
    var chest: Double?
    var waist: Double?
    var shoulders: Double?
    var thighs: Double?
    /// An explicit link to the scan this measurement describes. Older entries
    /// remain valid trend data, but are not inferred onto a scan by date.
    var scanID: UUID? = nil
}

enum CaptureSource: String, Codable, Hashable {
    case camera
    case photoLibrary
    case legacy
}

enum CaptureCameraPosition: String, Codable, CaseIterable, Hashable {
    case front
    case rear

    var label: String { self == .front ? "Front" : "Rear" }
    var opposite: CaptureCameraPosition { self == .front ? .rear : .front }
}

enum CaptureImageOrientation: String, Codable, Hashable {
    case up
    case down
    case left
    case right
    case upMirrored
    case downMirrored
    case leftMirrored
    case rightMirrored

    var isMirrored: Bool {
        switch self {
        case .upMirrored, .downMirrored, .leftMirrored, .rightMirrored: return true
        default: return false
        }
    }
}

/// Privacy-safe camera information needed to reproduce capture conditions.
/// The lens type is a model name such as `AVCaptureDeviceTypeBuiltInWideAngleCamera`,
/// never a device-unique identifier.
struct CaptureCameraMetadata: Codable, Hashable {
    var position: CaptureCameraPosition
    var lensType: String
    var previewMirrored: Bool
    var outputMirrored: Bool
    var sourceOrientation: CaptureImageOrientation
    var normalizedOrientation: CaptureImageOrientation = .up
    /// Persisted when available so digital zoom cannot silently alter scale.
    /// Nil belongs to captures created before this metadata was recorded.
    var zoomFactor: Float? = nil

    /// A missing metadata record belongs to a legacy or library capture and is
    /// handled by the caller as unknown. Two known camera captures are only
    /// comparable when both their optical position and lens type match.
    func isComparable(with other: CaptureCameraMetadata) -> Bool {
        guard position == other.position,
              lensType == other.lensType,
              normalizedOrientation == other.normalizedOrientation else { return false }
        if let zoomFactor, let otherZoom = other.zoomFactor {
            return abs(zoomFactor - otherZoom) <= 0.01
        }
        return true
    }
}

/// A reproducible, privacy-safe camera configuration. The identifier also
/// serves as the first-generation baseline-era identifier; Phase 2 can attach
/// verification state without rewriting existing scans.
struct CaptureRecipe: Identifiable, Codable, Hashable {
    var id = UUID()
    var createdAt = Date()
    var cameraPosition: CaptureCameraPosition
    var lensType: String
    var zoomFactor: Float?
    var normalizedOrientation: CaptureImageOrientation

    func isCompatible(with metadata: CaptureCameraMetadata) -> Bool {
        guard cameraPosition == metadata.position,
              lensType == metadata.lensType,
              normalizedOrientation == metadata.normalizedOrientation else { return false }
        if let zoomFactor, let capturedZoom = metadata.zoomFactor {
            return abs(zoomFactor - capturedZoom) <= 0.01
        }
        return zoomFactor == nil
    }

    func isCompatible(with other: CaptureRecipe) -> Bool {
        guard cameraPosition == other.cameraPosition,
              lensType == other.lensType,
              normalizedOrientation == other.normalizedOrientation else { return false }
        switch (zoomFactor, other.zoomFactor) {
        case let (lhs?, rhs?): return abs(lhs - rhs) <= 0.01
        case (nil, nil): return true
        default: return false
        }
    }

    static func derive(from captures: [PoseCapture]) -> CaptureRecipe? {
        let required = Pose.required.compactMap { pose in captures.first { $0.pose == pose } }
        guard required.count == Pose.required.count,
              required.allSatisfy({ $0.captureSource == .camera }),
              let first = required.first?.cameraMetadata,
              required.allSatisfy({ capture in
                  guard let metadata = capture.cameraMetadata else { return false }
                  return metadata.isComparable(with: first)
              }) else { return nil }
        return CaptureRecipe(
            cameraPosition: first.position,
            lensType: first.lensType,
            zoomFactor: first.zoomFactor,
            normalizedOrientation: first.normalizedOrientation
        )
    }
}

enum CaptureConfigurationIntent: Hashable {
    case matchActiveRecipe
    case startNewBaseline
    case documentationOnly
}

enum CaptureVerificationStatus: String, Codable, Hashable {
    case ready
    case reviewRecommended
    case unavailable

    var label: String {
        switch self {
        case .ready: return "Pose check verified"
        case .reviewRecommended: return "Review recommended"
        case .unavailable: return "Could not verify automatically"
        }
    }
}

enum CaptureRegion: String, Codable, CaseIterable, Hashable {
    case shoulders
    case chest
    case waist
    case arms
    case sideTorso
    case lowerBody
}

enum RegionEvidenceState: String, Codable, Hashable {
    case supported
    case unavailable
}

struct RegionEvidence: Codable, Hashable {
    var state: RegionEvidenceState
    var reason: String?

    static let supported = RegionEvidence(state: .supported, reason: nil)

    static func unavailable(_ reason: String) -> RegionEvidence {
        RegionEvidence(state: .unavailable, reason: reason)
    }
}

struct NormalizedPixelSize: Codable, Hashable {
    var width: Int
    var height: Int
}

/// A conservative, persisted record of what the app could actually verify.
/// An unavailable automatic check is intentionally distinct from a quality warning.
struct CaptureAssessment: Codable, Hashable {
    var status: CaptureVerificationStatus
    var confirmedIssues: [QualityIssue]
    var regionEvidence: [CaptureRegion: RegionEvidence]
    var userOverrodeRecommendation: Bool
    var brightnessScore: Float
    var coverageScore: Float
    /// A privacy-safe reason code for an unavailable automatic check. Optional
    /// so assessments saved by earlier builds remain decodable.
    var automaticCheckReason: String? = nil

    var hasSupportedUpperBodyEvidence: Bool {
        let required: [CaptureRegion] = [.chest, .waist]
        return required.allSatisfy { regionEvidence[$0]?.state == .supported }
    }

    static func legacyUnverified(brightness: Float = 0.5) -> CaptureAssessment {
        CaptureAssessment(
            status: .unavailable,
            confirmedIssues: [],
            regionEvidence: Dictionary(uniqueKeysWithValues: CaptureRegion.allCases.map {
                ($0, .unavailable("legacy_capture_not_verified"))
            }),
            userOverrodeRecommendation: false,
            brightnessScore: brightness,
            coverageScore: 0,
            automaticCheckReason: "legacy_capture_not_verified"
        )
    }

    var automaticStatusTitle: String {
        switch status {
        case .ready: return "Pose landmarks detected"
        case .reviewRecommended:
            if confirmedIssues.contains(.tooDark) { return "Extremely dark" }
            if confirmedIssues.contains(.overexposed) { return "Heavily overexposed" }
            return "Review recommended"
        case .unavailable: return "Could not verify automatically"
        }
    }

    var automaticStatusDetail: String {
        switch status {
        case .ready:
            return "Required pose landmarks were detected. Review the pose yourself before using it."
        case .reviewRecommended:
            if confirmedIssues.contains(.tooDark) {
                return "The photo is extremely dark and may hide body contours."
            }
            if confirmedIssues.contains(.overexposed) {
                return "The photo is heavily overexposed and may erase body contours."
            }
            return "A specific image issue may limit automatic analysis."
        case .unavailable:
            switch automaticCheckReason {
            case "automatic_check_timed_out":
                return "The automatic check timed out. This does not mean the photo is poor."
            case "image_decode_failed":
                return "The automatic check could not read this image."
            case "required_torso_landmarks_not_verified", "body_landmarks_not_verified":
                return "Body landmarks could not be confirmed. This does not mean the photo is poor."
            case "side_torso_landmarks_not_verified":
                return "A complete visible shoulder-to-hip line could not be confirmed. Side profiles are harder to detect, and this does not mean the photo is poor."
            case "lower_body_landmarks_not_verified":
                return "Complete hip-to-ankle landmarks could not be confirmed. This does not mean the photo is poor."
            case "legacy_capture_not_verified":
                return "This photo was saved before automatic evidence details were available."
            default:
                return "Evolv could not verify this photo automatically. This does not mean the photo is poor."
            }
        }
    }
}

enum AnalysisAvailability: String, Codable, Hashable {
    case baselineOnly
    case comparable
    case partialEvidence
    case processingFailed
    case documentationOnly
    case validationOnly

    var label: String {
        switch self {
        case .baselineOnly: return "Baseline"
        case .comparable: return "Comparable"
        case .partialEvidence: return "Limited automatic analysis"
        case .processingFailed: return "Analysis unavailable"
        case .documentationOnly: return "Same-day extra"
        case .validationOnly: return "Consistency test"
        }
    }
}

enum ScanCaptureCompleteness: String, Codable, Hashable {
    case complete
    case incomplete
}

enum ScanRole: String, Codable, Hashable {
    case canonical
    case sameDayExtra
    case documentationOnly
    case validationAnchor
    case validationRepeat

    var label: String {
        switch self {
        case .canonical: return "Progress scan"
        case .sameDayExtra: return "Same-day extra"
        case .documentationOnly: return "Photos only"
        case .validationAnchor: return "Consistency anchor"
        case .validationRepeat: return "Consistency repeat"
        }
    }
}

enum ScanSchedulingPolicy {
    /// Keeps one canonical progress record per calendar day. Additional scans
    /// are still retained as documentation, but cannot silently enter trends.
    static func resolvedRole(
        requested: ScanRole,
        on date: Date,
        existingScans: [Scan],
        calendar: Calendar = .current
    ) -> ScanRole {
        guard requested == .canonical else { return requested }
        let alreadyHasCanonical = existingScans.contains { scan in
            scan.isCanonicalProgressScan && calendar.isDate(scan.date, inSameDayAs: date)
        }
        return alreadyHasCanonical ? .sameDayExtra : .canonical
    }
}

/// A captured pose within a scan session — stores image data on disk via filename ref.
struct PoseCapture: Identifiable, Codable, Hashable {
    var id = UUID()
    var pose: Pose
    /// Filename inside the app's documents directory.
    var imageFilename: String
    var avgBrightness: Double      // 0–1 — used for lighting consistency
    var aspectRatio: Double        // width / height — used for framing consistency
    /// Optional so scans created by earlier app versions remain decodable.
    var captureSource: CaptureSource? = nil
    var assessment: CaptureAssessment? = nil
    var normalizedPixelSize: NormalizedPixelSize? = nil
    var cameraMetadata: CaptureCameraMetadata? = nil
}

/// A scan session — required poses (always) + optional showcase poses.
struct Scan: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var captures: [PoseCapture]    // includes both standard + showcase
    var consistencyScore: Int      // Legacy only; new scans store 0
    var lightingScore: Int         // Legacy only; new scans store 0
    var framingScore: Int          // Legacy only; new scans store 0
    var note: String?
    var context: ScanContext? = nil
    /// Replaces the legacy numeric scan-condition scores in current UI.
    var analysisAvailability: AnalysisAvailability? = nil
    /// Optional additions preserve decoding of scans created by older builds.
    var captureCompleteness: ScanCaptureCompleteness? = nil
    var scanRole: ScanRole? = nil
    var lastModifiedAt: Date? = nil
    /// Present only when this scan is part of a local five-set consistency test.
    /// Optional fields preserve decoding of every scan saved before Phase 2.
    var validationSessionID: UUID? = nil
    var validationSetNumber: Int? = nil
    /// Canonical scans with the same non-nil identifier share a camera setup.
    /// Nil represents legacy scans for which no complete recipe was available.
    var captureRecipeID: UUID? = nil

    var standardCaptures: [PoseCapture] { captures.filter { $0.pose.category == .standard } }
    var showcaseCaptures: [PoseCapture] { captures.filter { $0.pose.category == .showcase } }
    var poses: [Pose] { captures.map(\.pose) }
    var resolvedCaptureCompleteness: ScanCaptureCompleteness {
        captureCompleteness ?? (ScanCaptureValidator.hasAllRequiredPoses(captures) ? .complete : .incomplete)
    }
    var resolvedRole: ScanRole { scanRole ?? .canonical }
    var isCanonicalProgressScan: Bool { resolvedRole == .canonical }
    var isValidationOnlyScan: Bool {
        resolvedRole == .validationAnchor || resolvedRole == .validationRepeat
    }
    var automaticallyVerifiedPoses: [Pose] {
        standardCaptures.compactMap { $0.assessment?.status == .ready ? $0.pose : nil }
    }
    var automaticCheckUnavailablePoses: [Pose] {
        standardCaptures.compactMap { $0.assessment?.status == .unavailable ? $0.pose : nil }
    }
    var reviewRecommendedPoses: [Pose] {
        standardCaptures.compactMap { $0.assessment?.status == .reviewRecommended ? $0.pose : nil }
    }
    var recommendedRepairPoses: [Pose] {
        Pose.required.filter { pose in
            guard let capture = capture(for: pose) else { return true }
            return capture.assessment?.status == .reviewRecommended
        }
    }

    func capture(for pose: Pose) -> PoseCapture? {
        captures.first { $0.pose == pose }
    }
}

enum ScanCaptureValidator {
    static func hasAllRequiredPoses(_ captures: [PoseCapture]) -> Bool {
        let captured = Set(captures.filter { $0.pose.category == .standard }.map(\.pose))
        return captured == Set(Pose.required)
    }

    static func hasComparableUpperBodyEvidence(_ captures: [PoseCapture]) -> Bool {
        var assessments: [Pose: CaptureAssessment] = [:]
        for capture in captures {
            if let assessment = capture.assessment { assessments[capture.pose] = assessment }
        }
        return hasComparableUpperBodyEvidence(assessments)
    }

    static func hasComparableUpperBodyEvidence(_ assessments: [Pose: CaptureAssessment]) -> Bool {
        func supports(_ pose: Pose, _ regions: [CaptureRegion]) -> Bool {
            guard let assessment = assessments[pose] else { return false }
            return regions.allSatisfy { assessment.regionEvidence[$0]?.state == .supported }
        }

        // This remains a strict helper for callers that truly need full evidence.
        // Scan completeness and baseline validity must never depend on it.
        return supports(.front, [.shoulders, .chest, .waist, .arms])
            && supports(.side, [.chest, .waist, .arms, .sideTorso])
            && supports(.back, [.shoulders, .chest, .waist, .arms])
    }
}

enum ScanCaptureMerge {
    /// Produces the complete capture set for a targeted repair while also
    /// returning only superseded app-owned files for post-persist cleanup.
    static func replacing(
        _ existing: [PoseCapture],
        with replacements: [PoseCapture]
    ) -> (captures: [PoseCapture], supersededFilenames: [String]) {
        var replacementByPose: [Pose: PoseCapture] = [:]
        replacements.forEach { replacementByPose[$0.pose] = $0 }
        let superseded = existing.compactMap { capture in
            replacementByPose[capture.pose] == nil ? nil : capture.imageFilename
        }
        var merged = existing.filter { replacementByPose[$0.pose] == nil }
        merged.append(contentsOf: replacementByPose.values)
        merged.sort { lhs, rhs in
            let left = Pose.allCases.firstIndex(of: lhs.pose) ?? Int.max
            let right = Pose.allCases.firstIndex(of: rhs.pose) ?? Int.max
            return left < right
        }
        return (merged, superseded)
    }
}

struct EstimatedDelta: Identifiable, Codable {
    var id = UUID()
    var label: String         // "Arms"
    var unit: String          // "cm" or "%"
    var value: Double         // can be 0 or negative
    var status: TrendStatus
    var note: String?         // e.g. "No meaningful change detected"
}

struct ProgressScore: Codable {
    var value: Int            // 0–100
    var monthlyDelta: Int     // can be negative
    var weeklyDelta: Int
    var momentum: String      // "Building", "Maintaining", "Slowing"
}

struct WeeklySummary: Codable {
    var headline: String
    var detail: String
    var confidence: Confidence
}

// MARK: - Scan Context

enum TimeOfDayCategory: String, Codable {
    case morning, afternoon, evening, night

    static func inferred(from date: Date) -> TimeOfDayCategory {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<21: return .evening
        default: return .night
        }
    }
}

enum HydrationState: String, Codable {
    case low, normal, high, unknown
}

struct ScanContext: Codable {
    var timestamp: Date
    var timeOfDayCategory: TimeOfDayCategory
    var preWorkout: Bool?
    var fasted: Bool?
    var hydrationEstimate: HydrationState?
}

// MARK: - Quality Gate

enum QualityIssue: String, Codable, Hashable {
    case blurry
    case tooDark
    case overexposed
    case bodyNotFramed
    case missingLandmarks
    case poseMismatch
    case looseClothingWarning
    case mirrorSelfieDetected
    case tooFarAway
    case partialCoverage
    case insufficientCoverage

    var userMessage: String {
        switch self {
        case .blurry:               return "Image is too blurry — steady the camera"
        case .tooDark:              return "Too dark — find better lighting"
        case .overexposed:          return "Too bright — reduce direct light behind you"
        case .bodyNotFramed:        return "Full body not visible — step back and center yourself"
        case .missingLandmarks:     return "Can't detect body landmarks — try a different angle"
        case .poseMismatch:         return "Pose doesn't match the required position"
        case .looseClothingWarning: return "Loose clothing may reduce accuracy"
        case .mirrorSelfieDetected: return "Mirror selfies affect accuracy — try direct camera"
        case .tooFarAway:           return "Too far away — move closer to the camera"
        case .partialCoverage:      return "Partial body visible — ensure full body is in frame"
        case .insufficientCoverage: return "Body coverage too low for reliable analysis"
        }
    }

    var isHardReject: Bool { false }

    var retakeHint: String {
        switch self {
        case .blurry:               return "Hold steady or use the timer to avoid shake."
        case .tooDark:              return "Move to a brighter spot or turn on more lights."
        case .overexposed:          return "Avoid strong light directly behind you."
        case .bodyNotFramed,
             .missingLandmarks,
             .insufficientCoverage: return "Step back so your upper body fills the frame."
        case .partialCoverage:      return "Make sure your head and torso are both visible."
        case .tooFarAway:           return "Move a little closer to the camera."
        case .mirrorSelfieDetected: return "Face the camera directly instead of a mirror."
        case .poseMismatch:         return "Match the silhouette shown on screen."
        case .looseClothingWarning: return "Fitted clothing gives more accurate results."
        }
    }
}

enum QualityVerdict: Codable {
    case pass
    case warning([QualityIssue])
    case rejected([QualityIssue])

    private enum CodingKeys: String, CodingKey { case type, issues }
    private enum VerdictType: String, Codable { case pass, warning, rejected }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pass:
            try c.encode(VerdictType.pass, forKey: .type)
            try c.encode([QualityIssue](), forKey: .issues)
        case .warning(let issues):
            try c.encode(VerdictType.warning, forKey: .type)
            try c.encode(issues, forKey: .issues)
        case .rejected(let issues):
            try c.encode(VerdictType.rejected, forKey: .type)
            try c.encode(issues, forKey: .issues)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type_ = try c.decode(VerdictType.self, forKey: .type)
        let issues = try c.decode([QualityIssue].self, forKey: .issues)
        switch type_ {
        case .pass:     self = .pass
        case .warning:  self = .warning(issues)
        case .rejected: self = .rejected(issues)
        }
    }
}

struct QualityGateResult: Codable {
    var verdict: QualityVerdict
    var issues: [QualityIssue]
    var blurScore: Float
    var brightnessScore: Float
    var coverageScore: Float
    var regionalCoverage: [String: Float]
}

// MARK: - CV Extraction

struct NormalizedLandmark: Codable {
    var joint: String
    var x: Float
    var y: Float
    var confidence: Float
}

struct ExtractedPose: Codable {
    var scanId: UUID
    var pose: Pose
    var landmarks: [NormalizedLandmark]
    var bodyHeightPx: Float
    var poseMatchScore: Float?
}

struct SilhouetteProfile: Codable {
    var scanId: UUID
    var pose: Pose
    var widthAtY: [Float]            // 100 normalized Y levels, width/bodyHeightPx
    var shoulderWidthRatio: Float
    var chestWidthRatio: Float
    var waistWidthRatio: Float
    var armMidWidthRatio: Float
    var thighMidWidthRatio: Float
    var taperIndex: Float            // (shoulderWidth - waistWidth) / shoulderWidth
    var chestToWaistRatio: Float
    var shoulderToWaistRatio: Float
    var hipWidthRatio: Float?        // populated for side / back poses
    var lowerTorsoWidthRatio: Float
    /// Optional for backward compatibility. New analyses only emit signals for
    /// regions whose anatomical landmarks and mask samples were both present.
    var supportedRegions: [BodyRegion]? = nil
    /// Analysis-v4 person-aligned measurements. Older scalar fields remain so
    /// saved version-3 JSON can still be decoded before reanalysis.
    var regionFeatures: [PoseRegionFeature]? = nil
    var torsoReferencePixels: Float? = nil
    var poseMatchScore: Float? = nil
}

// MARK: - Signals

enum BodyRegion: String, Codable, CaseIterable, Hashable {
    case shoulders, chest, waist, arms, thighs

    var visualLabel: String {
        switch self {
        case .shoulders: return "Shoulder silhouette"
        case .chest: return "Upper-torso silhouette"
        case .waist: return "Waist silhouette"
        case .arms: return "Arm silhouette thickness"
        case .thighs: return "Thigh measurement"
        }
    }
}

extension BodyRegion {
    /// A pose-aware label. The same normalized feature must not be described as
    /// relaxed and flexed evidence interchangeably.
    func visualLabel(for pose: Pose?) -> String {
        guard let pose else { return visualLabel }
        switch (pose, self) {
        case (.frontDoubleBicep, .arms), (.backDoubleBicep, .arms):
            return "Flexed upper-arm silhouette"
        case (.sideChest, .arms), (.mostMuscular, .arms):
            return "Flexed arm silhouette"
        case (.sideChest, .chest):
            return "Side-chest silhouette"
        case (.backDoubleBicep, .shoulders):
            return "Flexed back-and-shoulder silhouette"
        case (.legs, .thighs):
            return "Thigh silhouette thickness"
        default:
            return visualLabel
        }
    }
}

enum PoseRegionFeatureSource: String, Codable, Hashable {
    case torsoCrossSection
    case limbCrossSection
    case legacyWidth
}

struct PoseRegionFeature: Codable, Hashable {
    var pose: Pose
    var region: BodyRegion
    var normalizedValue: Float
    var source: PoseRegionFeatureSource
    var evidenceReason: String?
}

enum PoseContributionStatus: String, Codable, Hashable {
    case supported
    case unavailable
}

struct PoseContribution: Codable, Hashable {
    var pose: Pose
    var baselineValue: Float?
    var currentValue: Float?
    var normalizedDelta: Float?
    var poseMatchScore: Float?
    var status: PoseContributionStatus
    var reason: String?
}

enum RegionalComparisonStatus: String, Codable, Hashable {
    case stable
    case increase
    case decrease
    case unavailable
}

struct RegionalComparison: Codable, Hashable {
    var region: BodyRegion
    var status: RegionalComparisonStatus
    var normalizedDelta: Float?
    var contributions: [PoseContribution]
    var reason: String?
}

/// A same-pose comparison. These results stay separate from the mandatory
/// relaxed-pose fusion, preventing a flexed or angled pose from changing the
/// relaxed upper-body result.
struct PoseComparison: Codable, Hashable {
    var pose: Pose
    var availability: AnalysisAvailability
    var regions: [RegionalComparison]
    var reason: String?

    var supportedRegions: [RegionalComparison] {
        regions.filter { $0.status != .unavailable }
    }
}

/// A runtime comparison for the exact two scans selected by the user. It is
/// intentionally derived from stored local evidence rather than persisted as
/// if it were the canonical longitudinal result.
struct ScanPairComparison: Hashable {
    var beforeScanID: UUID
    var afterScanID: UUID
    var availability: AnalysisAvailability
    var relaxedRegions: [RegionalComparison]
    var poseComparisons: [PoseComparison]
    var evidenceStrength: Confidence
    var reason: String?

    func comparison(for pose: Pose) -> PoseComparison? {
        poseComparisons.first { $0.pose == pose }
    }

    func evidenceStrength(for pose: Pose) -> Confidence {
        let regions = pose.category == .standard
            ? relaxedRegions.filter { $0.status != .unavailable }
            : comparison(for: pose)?.supportedRegions ?? []
        let matches = regions.flatMap(\.contributions).compactMap(\.poseMatchScore)
        guard !regions.isEmpty, !matches.isEmpty else { return .low }
        let average = matches.reduce(0, +) / Float(matches.count)
        // Provisional thresholds can describe moderate evidence support, but
        // cannot earn a high label until a validated threshold set is stored.
        return regions.count >= 2 && average >= 0.85 ? .medium : .low
    }
}

/// The conclusion Evolv may draw from an exact scan pair. This is deliberately
/// narrower than a fitness outcome: a supported silhouette difference is not
/// automatically body progress, muscle gain, or fat loss.
enum ComparisonNarrativeStatus: String, Codable, Hashable {
    case stable
    case differenceDetected
    case limited
    case unavailable
}

/// One authoritative, evidence-backed statement used by both Home and
/// Timeline. A nil pose means the result came from fused relaxed-pose evidence;
/// an optional pose always remains isolated from that fusion.
struct ComparisonNarrativeFinding: Identifiable, Codable, Hashable {
    var pose: Pose?
    var region: BodyRegion
    var status: RegionalComparisonStatus
    var normalizedDelta: Float?
    var evidenceStrength: Confidence
    var goalAlignment: GoalAlignment
    var statement: String

    var id: String {
        "\(pose?.rawValue ?? "relaxed")-\(region.rawValue)"
    }
}

/// A local interpretation of `ScanPairComparison`. It contains no image data,
/// landmarks, inferred tissue labels, or fabricated physical measurements.
struct ComparisonNarrative: Codable, Hashable {
    var status: ComparisonNarrativeStatus
    var headline: String
    var detail: String
    var findings: [ComparisonNarrativeFinding]
    var limitations: [String]
    var evidenceStrength: Confidence
    var thresholdSetIdentifier: String
    var thresholdsValidated: Bool
}

enum GoalAlignment: String, Codable, Hashable {
    case favorable
    case unfavorable
    case neutral
    case notApplicable
}

struct AnalysisAlgorithmMetadata: Codable, Hashable {
    var analysisVersion: Int
    var bodyPoseRevision: Int
    var personSegmentationRevision: Int
    var operatingSystemVersion: String
    var thresholdSetIdentifier: String
}

struct AnalysisThresholdSet: Codable, Hashable {
    var identifier: String
    var stableBands: [BodyRegion: Float]
    var conflictLimits: [BodyRegion: Float]
    var minimumPoseMatch: Float
    var provenance: String
    var sampleSize: Int
    var isValidated: Bool

    func stableBand(for region: BodyRegion) -> Float {
        stableBands[region] ?? 0.008
    }

    func conflictLimit(for region: BodyRegion) -> Float {
        conflictLimits[region] ?? 0.016
    }

    static let engineeringV1 = AnalysisThresholdSet(
        identifier: "engineering-v1",
        stableBands: [
            .shoulders: 0.018,
            .chest: 0.028,
            .waist: 0.028,
            .arms: 0.008,
            .thighs: 0.008
        ],
        conflictLimits: Dictionary(uniqueKeysWithValues: BodyRegion.allCases.map { ($0, 0.016) }),
        minimumPoseMatch: 0.85,
        provenance: "public_fixture_transform_floor_plus_provisional_engineering",
        sampleSize: 0,
        isValidated: false
    )
}

enum ReliabilityTier: String, Codable {
    case noData, baseline, earlyStage, buildingTrend, reliableTrend

    static func tier(for scanCount: Int) -> ReliabilityTier {
        switch scanCount {
        case 0:       return .noData
        case 1:       return .baseline
        case 2..<4:   return .earlyStage
        case 4..<8:   return .buildingTrend
        default:      return .reliableTrend
        }
    }

    var displayMessage: String {
        switch self {
        case .noData:        return "Scan to begin tracking"
        case .baseline:      return "Baseline captured — scan again to start detecting changes"
        case .earlyStage:    return "Early evidence — keep matching your capture conditions"
        case .buildingTrend: return "Evidence is building across comparable scans"
        case .reliableTrend: return "A longer comparison history is available"
        }
    }

    var minimumScansNeeded: Int {
        switch self {
        case .noData, .baseline: return 4
        case .earlyStage:        return 2
        case .buildingTrend:     return 1
        case .reliableTrend:     return 0
        }
    }
}

enum DirectionalSignal: String, Codable, Hashable {
    case strongPositive, moderatePositive, minimalPositive, neutral
    case minimalNegative, moderateNegative, strongNegative, unclear
}

enum MeasurementAlignment: String, Codable {
    case agreementPositive, agreementNegative
    case conflictVisualUpMeasureDown, conflictVisualDownMeasureUp
    case measurementOnly, visualOnly, noData
}

enum RecompositionPattern: String, Codable {
    case waistNarrowingArmsStable
    case silhouetteImprovementWeightStable
    case torsoNarrowingUpperBodyStable
    case taperImprovementNoSizeChange
    case upperGrowthWaistStableOrDown
    case allRegionsStable
}

struct RegionalDelta: Codable {
    var region: BodyRegion
    var normalizedDelta: Float
    var fromScanCount: Int
}

struct FatLossSignalSet: Codable {
    var waistNarrowing: Float
    var taperIndexDelta: Float
    var chestToWaistRatioDelta: Float
    var lowerTorsoNarrowing: Float
    var shoulderToWaistRatioDelta: Float
}

struct VisualSignalSet: Codable {
    var deltas: [RegionalDelta]
    var fatLossSignals: FatLossSignalSet?
    var reliabilityTier: ReliabilityTier
    var regionalComparisons: [RegionalComparison]? = nil
    /// Same-pose evidence for required and optional photos. Optional so every
    /// analysis created before version 6 remains decodable.
    var poseComparisons: [PoseComparison]? = nil
}

struct SmoothedSignalSet: Codable {
    var smoothedDeltas: [String: Float]
    var smoothedTaperDelta: Float
    var smoothedProportionDelta: Float
    var reliabilityTier: ReliabilityTier
    var scanCount: Int
}

struct ConfidenceScore: Codable {
    var overall: Confidence
    var rawScore: Float
    var regionalCoverage: [String: Float]
    var poseMatchScore: Float
    var lightingConsistency: Float
    var measurementAgreement: Float
    var hasSufficientEvidence: Bool? = nil
}

// MARK: - Interpreted Signals (payload to LLM)

struct InterpretedSignals: Codable {
    var scanCount: Int
    var weeksTracked: Int
    var reliabilityTier: ReliabilityTier
    var goal: FitnessGoal
    var overallConfidence: Confidence
    var signals: [String: DirectionalSignal]
    var taperSignal: DirectionalSignal
    var proportionSignal: DirectionalSignal
    var measurementAlignment: [String: MeasurementAlignment]
    var recompositionPatterns: [RecompositionPattern]
    var scanQualityNotes: [String]
    var signalConflicts: [String]
    var contextNotes: [String]
    var unavailableRegions: [String: String]? = nil
    var analysisAvailability: AnalysisAvailability? = nil
    var goalAlignments: [String: GoalAlignment]? = nil
    var signalSemanticsVersion: Int? = 2
    var thresholdSetIdentifier: String? = nil
    var thresholdsValidated: Bool? = nil
}

enum InsightSource: String, Codable, Equatable {
    case llm, templateFallback

    var label: String {
        switch self {
        case .llm: return "Cloud-written from derived signals"
        case .templateFallback: return "Generated on device"
        }
    }
}

struct GeneratedInsight: Codable {
    var headline: String
    var detail: String
    var caveat: String
    var regionNotes: [String: String]
    var momentum: String
    var confidence: Confidence
    var generatedAt: Date
    var source: InsightSource
}

struct ScanAnalysis: Identifiable, Codable {
    var id: UUID
    var analysisVersion: Int
    var analyzedAt: Date
    var qualityResult: QualityGateResult
    var extractedPoses: [ExtractedPose]
    var silhouetteProfiles: [SilhouetteProfile]
    var visualSignals: VisualSignalSet
    var smoothedSignals: SmoothedSignalSet
    var confidence: ConfidenceScore
    var interpretedSignals: InterpretedSignals
    var generatedInsight: GeneratedInsight?
    /// New per-pose evidence. Optional so version-1 analysis JSON still loads.
    var captureAssessments: [String: CaptureAssessment]? = nil
    var analysisAvailability: AnalysisAvailability? = nil
    var poseFailures: [String: String]? = nil
    var algorithmMetadata: AnalysisAlgorithmMetadata? = nil
    /// Camera metadata is persisted with the analysis so later comparisons can
    /// enforce matching optics without reopening or inferring from the photos.
    var captureCameraMetadata: [String: CaptureCameraMetadata]? = nil
}

struct AnalysisRunReport: Codable {
    var fixtureIdentifier: String
    var generatedAt: Date
    var metadata: AnalysisAlgorithmMetadata
    var availability: AnalysisAvailability
    var regionalComparisons: [RegionalComparison]
    var signals: [String: DirectionalSignal]
    var headline: String
    var processingDurationSeconds: Double
    var failures: [String: String]
    var poseFeatures: [PoseRegionFeature] = []
    var poseMatchScores: [String: Float] = [:]
    var stageTimingsSeconds: [String: Double] = [:]
    var wording: GeneratedInsight? = nil
    var comparisonNarrative: ComparisonNarrative? = nil
}

// MARK: - Calibration UX

enum CalibrationState {
    case noScans
    case baselineSet
    case earlyCalibration(scanCount: Int, targetCount: Int)
    case buildingTrend(confidence: Confidence)
    case calibrated(confidence: Confidence)

    static func from(tier: ReliabilityTier, confidence: Confidence, scanCount: Int) -> CalibrationState {
        switch tier {
        case .noData:        return .noScans
        case .baseline:      return .baselineSet
        case .earlyStage:    return .earlyCalibration(scanCount: scanCount, targetCount: 4)
        case .buildingTrend: return .buildingTrend(confidence: confidence)
        case .reliableTrend: return .calibrated(confidence: confidence)
        }
    }

    var headline: String {
        switch self {
        case .noScans:                              return "Start your first scan"
        case .baselineSet:                          return "Baseline captured"
        case .earlyCalibration(let n, let t):       return "Calibrating (\(n)/\(t) scans)"
        case .buildingTrend(let c):                 return "Building evidence (\(c.label))"
        case .calibrated(let c):                    return "Comparison evidence: \(c.label)"
        }
    }

    var subtext: String {
        switch self {
        case .noScans:
            return "Capture your first scan to begin tracking your physique."
        case .baselineSet:
            return "Scan again soon — changes need a reference point to be measured."
        case .earlyCalibration(let n, let t):
            return "\(t - n) more scan\(t - n == 1 ? "" : "s") needed before trend analysis activates."
        case .buildingTrend:
            return "Trends are forming. Keep scanning under matching conditions for stronger evidence."
        case .calibrated:
            return "Comparable visual evidence is available. Evolv still reports only what the photos support."
        }
    }
}
