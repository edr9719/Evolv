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
        case .weekly:   return "Recommended — meaningful change shows weekly"
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

enum Confidence: String, Codable {
    case high, medium, low
    var label: String {
        switch self {
        case .high:   return "High"
        case .medium: return "Medium"
        case .low:    return "Low"
        }
    }
}

/// Pose categories — required for tracking, showcase optional for motivation.
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

    /// Framing expectation used by the quality gate. Standard relaxed poses
    /// only require torso-and-up framing; legs require lower-body framing.
    enum Framing { case torsoUp, fullBody, legsOnly }
    var framing: Framing {
        switch self {
        case .front, .side, .back: return .torsoUp
        case .legs: return .legsOnly
        default: return .fullBody
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
        case .front: return "Waist or upper legs and up. Arms relaxed."
        case .side:  return "Profile view, neutral posture. Waist and up is fine."
        case .back:  return "Same distance and crop as your front shot."
        case .frontDoubleBicep: return "Front view, both arms flexed"
        case .sideChest:        return "Profile, chest forward, arm crossed"
        case .backDoubleBicep:  return "Back view, both arms flexed"
        case .mostMuscular:     return "Crunched front pose"
        case .relaxedAesthetic: return "Natural, slightly turned"
        case .legs:             return "Quads facing forward, slight stance, hands at sides"
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
    var weightKg: Double
    var arms: Double?
    var chest: Double?
    var waist: Double?
    var shoulders: Double?
    var thighs: Double?
}

/// A captured pose within a scan session — stores image data on disk via filename ref.
struct PoseCapture: Identifiable, Codable, Hashable {
    var id = UUID()
    var pose: Pose
    /// Filename inside the app's documents directory.
    var imageFilename: String
    var avgBrightness: Double      // 0–1 — used for lighting consistency
    var aspectRatio: Double        // width / height — used for framing consistency
}

/// A scan session — required poses (always) + optional showcase poses.
struct Scan: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var captures: [PoseCapture]    // includes both standard + showcase
    var consistencyScore: Int      // 0–100 vs prior scans
    var lightingScore: Int         // 0–100
    var framingScore: Int          // 0–100
    var note: String?
    var context: ScanContext? = nil

    var standardCaptures: [PoseCapture] { captures.filter { $0.pose.category == .standard } }
    var showcaseCaptures: [PoseCapture] { captures.filter { $0.pose.category == .showcase } }
    var poses: [Pose] { captures.map(\.pose) }

    func capture(for pose: Pose) -> PoseCapture? {
        captures.first { $0.pose == pose }
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

enum QualityIssue: String, Codable {
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
}

// MARK: - Signals

enum BodyRegion: String, Codable, CaseIterable {
    case shoulders, chest, waist, arms, thighs
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
        case .earlyStage:    return "Early data — patterns forming, not yet reliable"
        case .buildingTrend: return "Building confidence — trends are becoming clearer"
        case .reliableTrend: return "Reliable trend — analysis is fully calibrated"
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

enum DirectionalSignal: String, Codable {
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
}

enum InsightSource: String, Codable {
    case llm, templateFallback
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
        case .buildingTrend(let c):                 return "Building confidence (\(c.label))"
        case .calibrated(let c):                    return "Analysis ready (\(c.label) confidence)"
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
            return "Trends are forming. Keep scanning on schedule for higher confidence."
        case .calibrated:
            return "Analysis is fully calibrated. Insights reflect real physique changes."
        }
    }
}
