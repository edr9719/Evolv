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
    case eligibleAnchorUnavailable
    case sessionUnavailable
    case sessionIneligible(ValidationDeviationReason)
    case invalidCameraConfiguration
    case conditionsRequired

    var errorDescription: String? {
        switch self {
        case .activeSessionExists:
            return "Finish or leave the current consistency test before starting another one."
        case .eligibleAnchorUnavailable:
            return "That recent scan can no longer be used as Set 1. Start with a new Set 1 instead."
        case .sessionUnavailable:
            return "This consistency-test session is no longer available."
        case .sessionIneligible(let reason):
            return "This test can no longer continue because \(reason.label.lowercased()). Your completed sets and draft photos remain saved on this iPhone."
        case .invalidCameraConfiguration:
            return "This set did not use the camera and lens locked for the test. The saved draft remains available."
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
            return "Evolv found no unexpected visual change across the four same-session comparisons."
        case .limitedEvidence:
            return "No change was detected, but some required comparison evidence was unavailable."
        case .needsReview:
            return "At least one comparison changed unexpectedly, conflicted, failed processing, or had a recorded condition change."
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

struct ValidationSetComparison: Codable, Hashable {
    var setNumber: Int
    var regionalComparisons: [RegionalComparison]
    var failures: [String: String]
    var hasSufficientCoreEvidence: Bool
    var processingDurationMilliseconds: Int? = nil
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

    var completedSetCount: Int { sets.count }
    var nextSetNumber: Int { min(Self.requiredSetCount, sets.count + 1) }
    var isComplete: Bool { sets.count == Self.requiredSetCount }
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
