import Foundation

enum ValidationProgramAvailability {
    /// The local consistency tool is intentionally absent from production App
    /// Store builds. Debug builds and TestFlight's sandbox receipt may show it.
    static var isEnabled: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }

    static func isEnabled(isDebugBuild: Bool, receiptFilename: String?) -> Bool {
        isDebugBuild || receiptFilename == "sandboxReceipt"
    }
}

enum ValidationStudyError: LocalizedError {
    case activeSessionExists
    case pilotEnrollmentRequired
    case eligibleAnchorUnavailable
    case sessionUnavailable
    case sessionIneligible(ValidationDeviationReason)
    case invalidCameraConfiguration
    case baselineEvidenceRequired
    case repeatEvidenceRequired
    case conditionsRequired

    var errorDescription: String? {
        switch self {
        case .activeSessionExists:
            return "Finish or leave the current consistency test before starting another one."
        case .pilotEnrollmentRequired:
            return "Join the invited pilot before starting the official five-set test."
        case .eligibleAnchorUnavailable:
            return "That recent scan can no longer be used as Set 1. Start with a new Set 1 instead."
        case .sessionUnavailable:
            return "This consistency-test session is no longer available."
        case .sessionIneligible(let reason):
            return "This test can no longer continue because \(reason.label.lowercased()). Your completed sets and draft photos remain saved on this iPhone."
        case .invalidCameraConfiguration:
            return "This set did not use the camera and lens locked for the test. The saved draft remains available."
        case .baselineEvidenceRequired:
            return "Set 1 must pass Evolv's comparison-evidence check before the test can continue. Retake the requested pose and try again."
        case .repeatEvidenceRequired:
            return "This set must pass Evolv's Set 1 comparability check before the test can continue. Retake only the requested pose and try again."
        case .conditionsRequired:
            return "Answer the conditions question for the saved set before continuing."
        }
    }
}

enum ValidationShareScope: String, Codable, Hashable {
    /// Local validation remains the default. Pilot sharing is authorized only
    /// through the separate consent and submission flow.
    case localOnly
    case resultsOnly
    case resultsAndSelectedPhotos
}

struct ValidationEnrollment: Identifiable, Codable, Hashable {
    var id = UUID()
    var enrolledAt: Date
    var programVersion: Int
    var shareScope: ValidationShareScope
    var consentVersion: String?
}

enum ValidationSessionStatus: String, Codable, Hashable {
    case active
    case evaluating
    case completed
    case protocolIneligible
    case abandoned
}

enum ValidationConsistencyStatus: String, Codable, Hashable {
    case consistent
    case limitedEvidence
    case needsReview

    var title: String {
        switch self {
        case .consistent: return "Consistent in this session"
        case .limitedEvidence: return "Limited evidence"
        case .needsReview: return "Needs review"
        }
    }

    var detail: String {
        switch self {
        case .consistent:
            return "Evolv found no unexpected visual change in the supported shoulder, upper-torso, and waist comparisons. Arm evidence is reported only when it can be isolated reliably."
        case .limitedEvidence:
            return "Some photos could not be analyzed reliably. Evolv left those comparisons unavailable instead of guessing."
        case .needsReview:
            return "A supported comparison changed unexpectedly, conflicted, used different conditions, or Evolv encountered a true processing problem."
        }
    }
}

enum ValidationDeviationReason: String, Codable, CaseIterable, Hashable, Identifiable {
    case lighting
    case phonePosition
    case clothing
    case interruption
    case other
    case sessionExpired
    case dateChanged
    case scanModifiedAfterSet
    case scanDeletedAfterSet

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lighting: return "Lighting changed"
        case .phonePosition: return "Phone position changed"
        case .clothing: return "Clothing changed"
        case .interruption: return "There was an interruption"
        case .other: return "Something else changed"
        case .sessionExpired: return "More than 60 minutes elapsed"
        case .dateChanged: return "The calendar day changed"
        case .scanModifiedAfterSet: return "A completed set was edited"
        case .scanDeletedAfterSet: return "A completed set was deleted"
        }
    }

    var isUserSelectable: Bool {
        switch self {
        case .lighting, .phonePosition, .clothing, .interruption, .other: return true
        default: return false
        }
    }
}

struct ValidationSetConditions: Codable, Hashable {
    var stayedTheSame: Bool
    var deviations: [ValidationDeviationReason]
    var recordedAt: Date
}

enum ValidationDiagnosticKind: String, Codable, Hashable {
    /// The detector conservatively abstained. This is missing evidence, not an
    /// application malfunction and never becomes a passing result.
    case evidenceUnavailable
    /// Image loading, persistence, or an unexpected pipeline exception failed.
    case systemError
    /// The evidence exists but the controlled-capture contract changed.
    case comparabilityChange
}

enum ValidationEvidenceStage: String, Codable, Hashable {
    case photoLoading
    case poseExtraction
    case hipLandmarks
    case segmentation
    case silhouette
    case regionFeatures
    case comparability
}

/// Privacy-safe, durable diagnostics for one pose at one set. No coordinates,
/// masks, confidence values, filenames, or body descriptions are stored.
struct ValidationPoseDiagnostic: Codable, Hashable, Identifiable {
    var setNumber: Int
    var pose: Pose
    var stage: ValidationEvidenceStage
    var kind: ValidationDiagnosticKind
    var code: String
    var affectedRegions: [BodyRegion]

    var id: String {
        "set_\(setNumber).\(pose.rawValue).\(stage.rawValue).\(code).\(affectedRegions.map(\.rawValue).joined(separator: "-"))"
    }

    var userTitle: String {
        switch code {
        case "hip_landmarks_unavailable":
            return "\(pose.shortLabel) hips weren't detected"
        case "shoulder_landmarks_unavailable":
            return "\(pose.shortLabel) shoulders weren't detected"
        case "body_pose_unavailable":
            return "\(pose.shortLabel) pose couldn't be analyzed"
        case "person_segmentation_unavailable":
            return "\(pose.shortLabel) outline couldn't be separated"
        case "torso_scale_unavailable", "silhouette_evidence_unavailable":
            return "\(pose.shortLabel) torso couldn't be analyzed"
        case "required_region_feature_unavailable":
            if affectedRegions == [.arms] {
                return "\(pose.shortLabel) arms weren't clear enough"
            }
            return "\(pose.shortLabel) comparison evidence was incomplete"
        case "side_angle_differs_from_baseline":
            return "Side angle differs from Set 1"
        case "pose_alignment_differs_from_baseline":
            return "\(pose.shortLabel) alignment differs from Set 1"
        case "pose_alignment_unavailable":
            return "\(pose.shortLabel) alignment couldn't be compared"
        case "camera_configuration_changed":
            return "Camera setup changed"
        case "cross_pose_evidence_conflict":
            return "\(pose.shortLabel) conflicts with the other angles"
        case "photo_load_failed", "image_decode_failed":
            return "\(pose.shortLabel) photo couldn't be opened"
        default:
            return kind == .systemError
                ? "\(pose.shortLabel) processing didn't finish"
                : "\(pose.shortLabel) needs another photo"
        }
    }

    var userGuidance: String {
        switch code {
        case "hip_landmarks_unavailable":
            return "Step back slightly and keep both hip creases and your upper legs clearly inside the frame."
        case "shoulder_landmarks_unavailable":
            return "Keep your complete shoulders inside the frame and stand away from the wall."
        case "body_pose_unavailable":
            return "Show your head through mid-thigh, keep the pose clear, and make sure no body part touches the frame edge."
        case "person_segmentation_unavailable":
            return "Use even front lighting and stand away from the wall so your outline is distinct."
        case "torso_scale_unavailable", "silhouette_evidence_unavailable":
            return "Step back slightly, show your head through mid-thigh, and keep your hips unobstructed."
        case "required_region_feature_unavailable":
            if affectedRegions == [.arms] {
                return "Let your arms hang naturally with visible space between each arm and your torso."
            }
            return "Match the guide, keep your hips and upper legs visible, and avoid connected shadows."
        case "side_angle_differs_from_baseline":
            return "Match Set 1's profile angle. Keep the same shoulder, hip, and arm alignment instead of turning farther toward or away from the camera."
        case "pose_alignment_differs_from_baseline":
            return "Use the Set 1 ghost overlay and match your shoulder, hip, and relaxed-arm position more closely."
        case "pose_alignment_unavailable":
            return "Keep the complete torso, hip region, and relaxed arm visible so Evolv can compare alignment with Set 1."
        case "camera_configuration_changed":
            return "Use the camera and lens locked at the start of this consistency test."
        case "cross_pose_evidence_conflict":
            return "Match Set 1's distance and stance. Keep your torso centered and your arms in the same relaxed position."
        case "photo_load_failed", "image_decode_failed":
            return "Retake this pose so Evolv can save and inspect a fresh photo."
        default:
            return kind == .systemError
                ? "Try the check again. If it repeats, close and reopen Evolv before retaking."
                : "Retake this pose using the on-screen guide."
        }
    }
}

struct ValidationPoseEvidence: Codable, Hashable, Identifiable {
    var pose: Pose
    var poseExtracted: Bool
    var silhouetteGenerated: Bool
    var supportedRegions: [BodyRegion]

    var id: Pose { pose }
}

struct ValidationBaselinePreflight: Codable, Hashable {
    var checkedAt: Date
    var captureIDs: [UUID]
    var poseEvidence: [ValidationPoseEvidence]
    var diagnostics: [ValidationPoseDiagnostic]
    /// Build 20 adds the same privacy-safe geometry/feature summaries used for
    /// repeats so empirical noise can be measured relative to Set 1.
    var repeatabilityMetrics: [ValidationRepeatabilityMetrics]? = nil

    var isViable: Bool { diagnostics.isEmpty }
    var posesNeedingRetake: [Pose] {
        Pose.required.filter { pose in diagnostics.contains { $0.pose == pose } }
    }

    func matches(_ captures: [PoseCapture]) -> Bool {
        Set(captureIDs) == Set(captures.map(\.id))
    }
}

/// Privacy-safe summaries used to study repeatability. These values describe
/// capture geometry and normalized feature output; they contain no landmark
/// coordinates, masks, filenames, or body descriptions and are not included
/// in the pilot network payload.
struct ValidationRepeatabilityMetrics: Codable, Hashable, Identifiable {
    var pose: Pose
    var normalizedFeatureValues: [BodyRegion: Float]
    var normalizedTorsoScale: Float?
    var subjectCenterOffsetX: Float?
    var subjectCenterOffsetY: Float?
    var minimumObservedMargin: Float?
    var torsoRotationDegrees: Float?
    var poseMatchScore: Float?

    var id: Pose { pose }
}

/// Strict Layer-B check for a repeat set. Exact capture IDs prevent a replaced
/// image from inheriting a successful comparison.
struct ValidationSetPreflight: Codable, Hashable {
    var checkedAt: Date
    var setNumber: Int
    var captureIDs: [UUID]
    var comparison: ValidationSetComparison

    var isViable: Bool { comparison.hasSufficientCoreEvidence }
    var actionableDiagnostics: [ValidationPoseDiagnostic] {
        let priority: (ValidationPoseDiagnostic) -> Int = { issue in
            switch issue.code {
            case "side_angle_differs_from_baseline", "pose_alignment_differs_from_baseline": return 0
            case "hip_landmarks_unavailable", "shoulder_landmarks_unavailable": return 1
            case "cross_pose_evidence_conflict": return 2
            case "person_segmentation_unavailable", "silhouette_evidence_unavailable": return 3
            default: return issue.kind == .systemError ? 0 : 4
            }
        }
        return Pose.required.compactMap { pose in
            (comparison.diagnostics ?? [])
                .filter { $0.setNumber == setNumber && $0.pose == pose }
                .min { priority($0) < priority($1) }
        }
    }
    var posesNeedingRetake: [Pose] {
        let diagnostics = comparison.diagnostics ?? []
        return Pose.required.filter { pose in
            diagnostics.contains { $0.setNumber == setNumber && $0.pose == pose }
                || comparison.regionalComparisons.flatMap(\.contributions).contains {
                    $0.pose == pose && $0.status == .unavailable
                }
        }
    }

    func matches(_ captures: [PoseCapture]) -> Bool {
        Set(captureIDs) == Set(captures.map(\.id))
    }
}

struct ValidationSetComparison: Codable, Hashable {
    var setNumber: Int
    var regionalComparisons: [RegionalComparison]
    var failures: [String: String]
    var hasSufficientCoreEvidence: Bool
    var processingDurationMilliseconds: Int? = nil
    /// Optional so Build 17 records remain decodable. New evaluations always
    /// write stage-specific diagnostics with baseline/repeat provenance.
    var diagnostics: [ValidationPoseDiagnostic]? = nil
    /// Optional for backward compatibility; Build 20 writes these summaries
    /// for repeatability calibration without uploading them.
    var repeatabilityMetrics: [ValidationRepeatabilityMetrics]? = nil
}

struct ValidationSetRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var setNumber: Int
    var scanID: UUID
    var completedAt: Date
    var conditions: ValidationSetConditions?
    var comparison: ValidationSetComparison?
    var usedExistingCanonicalScan: Bool
}

struct ValidationLocalPackagePreview: Codable, Hashable {
    var sessionID: UUID
    var completedSetCount: Int
    var comparisonCount: Int
    var resultRecordCount: Int
    var photoCount: Int
    var shareScope: ValidationShareScope

    /// A package preview is descriptive local state and never grants network
    /// permission. PilotSubmissionCoordinator applies the separate consent gate.
    var canUpload: Bool { false }
}

struct ValidationStudySession: Identifiable, Codable, Hashable {
    static let protocolVersion = 1
    static let requiredSetCount = 5
    static let maximumDuration: TimeInterval = 60 * 60
    static let minimumRemainingDurationForExistingAnchor: TimeInterval = 30 * 60

    var id = UUID()
    var enrollment: ValidationEnrollment
    var startedAt: Date
    var expiresAt: Date
    var status: ValidationSessionStatus
    var lockedCameraPosition: CaptureCameraPosition
    var lockedLensType: String?
    var sets: [ValidationSetRecord]
    var draftSetNumber: Int?
    var draftCaptures: [PoseCapture]
    var result: ValidationConsistencyStatus?
    var statusReasons: [ValidationDeviationReason]
    var completedAt: Date?
    var algorithmMetadata: AnalysisAlgorithmMetadata? = nil
    /// Missing on Build 17 sessions. Those records are preserved verbatim;
    /// every newly created Build 18 session requires a viable Set 1.
    var baselinePreflightRequired: Bool? = nil
    var baselinePreflight: ValidationBaselinePreflight? = nil
    /// A strict comparison of the current draft repeat against Set 1. It is
    /// cleared whenever any draft capture changes.
    var draftSetPreflight: ValidationSetPreflight? = nil

    var completedSetCount: Int { sets.count }
    var nextSetNumber: Int { min(Self.requiredSetCount, sets.count + 1) }
    var isComplete: Bool { sets.count == Self.requiredSetCount }
    var requiresBaselinePreflight: Bool { baselinePreflightRequired == true }
    var hasViableBaseline: Bool {
        !requiresBaselinePreflight || baselinePreflight?.isViable == true
    }
    var anchorScanID: UUID? { sets.first(where: { $0.setNumber == 1 })?.scanID }
    var awaitingConditionsSetNumber: Int? {
        sets.sorted(by: { $0.setNumber < $1.setNumber })
            .first(where: { $0.conditions == nil })?.setNumber
    }

    var packagePreview: ValidationLocalPackagePreview {
        ValidationLocalPackagePreview(
            sessionID: id,
            completedSetCount: sets.count,
            comparisonCount: sets.compactMap(\.comparison).count,
            resultRecordCount: sets.reduce(0) { $0 + ($1.comparison?.regionalComparisons.count ?? 0) },
            photoCount: sets.count * Pose.required.count + draftCaptures.count,
            shareScope: enrollment.shareScope
        )
    }

    func eligibility(
        at now: Date,
        calendar: Calendar = .current
    ) -> ValidationSessionEligibility {
        guard calendar.isDate(startedAt, inSameDayAs: now) else {
            return .ineligible(.dateChanged)
        }
        guard now <= expiresAt else {
            return .ineligible(.sessionExpired)
        }
        return .eligible
    }
}

enum ValidationSessionEligibility: Equatable {
    case eligible
    case ineligible(ValidationDeviationReason)
}

enum ValidationStudyPolicy {
    static func canStartOfficialPilot(
        enrollment: PilotLocalEnrollment?
    ) -> Bool {
        enrollment?.status == .active
    }

    static func hasRequiredBaselineEvidence(
        session: ValidationStudySession,
        committingSetNumber setNumber: Int,
        captures: [PoseCapture]
    ) -> Bool {
        guard session.requiresBaselinePreflight else { return true }
        guard let preflight = session.baselinePreflight, preflight.isViable else { return false }
        return setNumber != 1 || preflight.matches(captures)
    }

    static func hasRequiredRepeatEvidence(
        session: ValidationStudySession,
        committingSetNumber setNumber: Int,
        captures: [PoseCapture]
    ) -> Bool {
        guard setNumber > 1,
              let preflight = session.draftSetPreflight else { return false }
        return preflight.setNumber == setNumber
            && preflight.matches(captures)
            && preflight.isViable
    }

    static func isValidDraft(
        _ captures: [PoseCapture],
        position: CaptureCameraPosition,
        lockedLensType: String?
    ) -> Bool {
        guard !captures.isEmpty,
              captures.allSatisfy({ Pose.required.contains($0.pose) }),
              Set(captures.map(\.pose)).count == captures.count,
              let first = captures.first?.cameraMetadata,
              first.position == position,
              lockedLensType == nil || first.lensType == lockedLensType else {
            return false
        }
        return captures.allSatisfy { capture in
            capture.captureSource == .camera
                && capture.cameraMetadata?.isComparable(with: first) == true
        }
    }

    static func isValidCompletedSet(
        _ captures: [PoseCapture],
        position: CaptureCameraPosition,
        lockedLensType: String?
    ) -> Bool {
        captures.count == Pose.required.count
            && Set(captures.map(\.pose)) == Set(Pose.required)
            && isValidDraft(captures, position: position, lockedLensType: lockedLensType)
    }

    static func eligibleCanonicalAnchor(
        _ scan: Scan,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard scan.isCanonicalProgressScan,
              scan.validationSessionID == nil,
              scan.resolvedCaptureCompleteness == .complete,
              calendar.isDate(scan.date, inSameDayAs: now),
              now.timeIntervalSince(scan.date) >= 0,
              now.timeIntervalSince(scan.date)
                <= ValidationStudySession.maximumDuration
                    - ValidationStudySession.minimumRemainingDurationForExistingAnchor else {
            return false
        }
        let required = Pose.required.compactMap { scan.capture(for: $0) }
        guard required.count == Pose.required.count,
              required.allSatisfy({ $0.captureSource == .camera }),
              let firstMetadata = required.first?.cameraMetadata else {
            return false
        }
        return required.allSatisfy { capture in
            guard let metadata = capture.cameraMetadata else { return false }
            return metadata.isComparable(with: firstMetadata)
        }
    }

    static func cameraConfiguration(
        for captures: [PoseCapture]
    ) -> CaptureCameraMetadata? {
        let required = Pose.required.compactMap { pose in captures.first { $0.pose == pose } }
        guard required.count == Pose.required.count,
              required.allSatisfy({ $0.captureSource == .camera }),
              let first = required.first?.cameraMetadata,
              required.allSatisfy({ capture in
                  guard let metadata = capture.cameraMetadata else { return false }
                  return metadata.isComparable(with: first)
              }) else {
            return nil
        }
        return first
    }
}

struct ValidationCaptureContext: Hashable, Identifiable {
    var sessionID: UUID
    var setNumber: Int
    var lockedCameraPosition: CaptureCameraPosition
    var anchorScanID: UUID?
    var initialCaptures: [PoseCapture]

    var id: String { "\(sessionID.uuidString)-\(setNumber)" }
}
