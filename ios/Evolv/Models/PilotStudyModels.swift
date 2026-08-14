import Foundation

enum PilotStudyConfiguration {
    static let consentVersion = "pilot-consent-v1"
    static let ongoingConsentVersion = "pilot-ongoing-v1"
    static let payloadSchemaVersion = 1
    static let analysisVersion = AnalysisStore.currentAnalysisVersion
    static let maximumPhotoCount = ValidationStudySession.requiredSetCount * Pose.required.count
    static let maximumCiphertextBytes = 5 * 1_024 * 1_024
    static let keyAgreementPublicKeyVersion = "pilot-p256-v1"

    /// Uncompressed ANSI X9.63 representation of the pilot's P-256 public key.
    /// The corresponding private key is deliberately not part of the app,
    /// repository, Supabase project, or TestFlight archive.
    static let keyAgreementPublicKeyBase64 = "BKn+qZLp0Du5cDKUoU4P3JKXjBJ6myLN4pSMePL7IQhw+GeRHj/8bh+QkZ/j1BRBitwsgezPQUsM6J10qJgsy+A="
}

enum PilotContributionType: String, Codable, Hashable {
    case consistencyTest = "consistency_test"
    case progressScan = "progress_scan"
}

enum PilotOngoingContributionMode: String, Codable, CaseIterable, Hashable, Identifiable {
    case resultsOnly = "results_only"
    case askEveryScan = "ask_every_scan"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .resultsOnly: return "Share future results"
        case .askEveryScan: return "Ask after each scan"
        }
    }

    var detail: String {
        switch self {
        case .resultsOnly:
            return "Future progress-scan results are shared after on-device analysis. Photos are never included."
        case .askEveryScan:
            return "Nothing is shared automatically. Review each future scan and decide whether to include results only or selected photos."
        }
    }
}

struct PilotOngoingConsent: Codable, Hashable {
    var version: String
    var mode: PilotOngoingContributionMode
    var acceptedAt: Date
}

enum PilotShareScope: String, Codable, CaseIterable, Hashable, Identifiable {
    case resultsOnly = "results_only"
    case resultsAndSelectedPhotos = "results_and_selected_photos"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .resultsOnly: return "Results only"
        case .resultsAndSelectedPhotos: return "Results and selected photos"
        }
    }

    var detail: String {
        switch self {
        case .resultsOnly:
            return "Shares Evolv's calculated consistency results and test conditions. No photos are uploaded."
        case .resultsAndSelectedPhotos:
            return "You choose individual photos after the test. Photos you do not select stay only on this iPhone."
        }
    }

    var validationScope: ValidationShareScope {
        switch self {
        case .resultsOnly: return .resultsOnly
        case .resultsAndSelectedPhotos: return .resultsAndSelectedPhotos
        }
    }
}

struct PilotConsent: Codable, Hashable {
    var version: String
    var adultConfirmed: Bool
    var shareScope: PilotShareScope
    var acceptedAt: Date
}

enum PilotConsentPolicy {
    static func validate(
        consent: PilotConsent,
        selectedPhotoCount: Int,
        photoApprovalConfirmed: Bool
    ) throws {
        guard consent.adultConfirmed else { throw PilotStudyError.adultConfirmationRequired }
        guard selectedPhotoCount >= 0,
              selectedPhotoCount <= PilotStudyConfiguration.maximumPhotoCount else {
            throw PilotStudyError.payloadRejected
        }
        switch consent.shareScope {
        case .resultsOnly:
            guard selectedPhotoCount == 0 else { throw PilotStudyError.payloadRejected }
        case .resultsAndSelectedPhotos:
            guard photoApprovalConfirmed, selectedPhotoCount > 0 else {
                throw PilotStudyError.photoSelectionRequired
            }
        }
    }
}

enum PilotOngoingContributionPolicy {
    static func canEnable(
        enrollment: PilotLocalEnrollment?,
        hasCompletedConsistencySubmission: Bool,
        now: Date = Date()
    ) -> Bool {
        guard let enrollment else { return false }
        return enrollment.status == .active
            && enrollment.pilotClosesAt > now
            && hasCompletedConsistencySubmission
    }

    static func canContribute(
        enrollment: PilotLocalEnrollment?,
        hasCompletedConsistencySubmission: Bool,
        scan: Scan,
        analysis: ScanAnalysis
    ) -> Bool {
        guard canEnable(
            enrollment: enrollment,
            hasCompletedConsistencySubmission: hasCompletedConsistencySubmission,
            now: analysis.analyzedAt
        ), let consent = enrollment?.ongoingConsent else { return false }
        return consent.version == PilotStudyConfiguration.ongoingConsentVersion
            && scan.isCanonicalProgressScan
            && scan.validationSessionID == nil
            && scan.resolvedCaptureCompleteness == .complete
            && ScanCaptureValidator.hasAllRequiredPoses(scan.captures)
            && scan.date >= consent.acceptedAt
            && analysis.analyzedAt >= consent.acceptedAt
            && analysis.analyzedAt >= scan.date
            && analysis.id == scan.id
            && analysis.analysisVersion == AnalysisStore.currentAnalysisVersion
    }
}

enum PilotEnrollmentStatus: String, Codable, Hashable {
    case active
    case withdrawn
    case deleted
}

struct PilotLocalEnrollment: Identifiable, Codable, Hashable {
    var id: UUID { participantID }
    var participantID: UUID
    var studyID: UUID
    var studyName: String
    var enrolledAt: Date
    var pilotClosesAt: Date
    var resultsDeleteAfter: Date
    var consent: PilotConsent
    var status: PilotEnrollmentStatus
    var ongoingConsent: PilotOngoingConsent? = nil
}

struct PilotPhotoChoice: Identifiable, Codable, Hashable {
    var id: UUID { captureID }
    var captureID: UUID
    var scanID: UUID
    var setNumber: Int
    var pose: Pose
}

enum PilotSubmissionStatus: String, Codable, Hashable {
    case preparing
    case queued
    case uploading
    case completed
    case failed
    case deleted

    var title: String {
        switch self {
        case .preparing: return "Preparing securely"
        case .queued: return "Waiting to upload"
        case .uploading: return "Uploading"
        case .completed: return "Shared"
        case .failed: return "Needs retry"
        case .deleted: return "Deleted"
        }
    }
}

struct PilotEncryptedObject: Identifiable, Codable, Hashable {
    var id: UUID
    var captureID: UUID
    var setNumber: Int
    var pose: Pose
    var relativeCiphertextPath: String
    var ciphertextSHA256: String
    var ciphertextByteCount: Int
}

struct PilotWrappedKeyEnvelope: Codable, Hashable {
    var algorithm: String
    var publicKeyVersion: String
    var ephemeralPublicKeyBase64: String
    var saltBase64: String
    var sealedKeyBase64: String
}

struct PilotSubmissionRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var localSessionID: UUID
    var remoteSubmissionID: UUID?
    var idempotencyKey: UUID
    var status: PilotSubmissionStatus
    var consent: PilotConsent
    var selectedPhotos: [PilotPhotoChoice]
    var encryptedObjects: [PilotEncryptedObject]
    var wrappedKey: PilotWrappedKeyEnvelope?
    var structuredPayload: PilotStructuredPayload
    var createdAt: Date
    var updatedAt: Date
    var receiptCode: String?
    var failureReasonCode: String?
}

enum PilotStructuredPayload: Codable, Hashable {
    case consistency(PilotResultsPayload)
    case progress(PilotProgressPayload)

    var contributionType: PilotContributionType {
        switch self {
        case .consistency: return .consistencyTest
        case .progress: return .progressScan
        }
    }

    private enum CodingError: Error { case unsupportedPayload }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let progress = try? container.decode(PilotProgressPayload.self),
           progress.contributionType == .progressScan {
            self = .progress(progress)
        } else if let consistency = try? container.decode(PilotResultsPayload.self) {
            self = .consistency(consistency)
        } else {
            throw CodingError.unsupportedPayload
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .consistency(let payload): try container.encode(payload)
        case .progress(let payload): try container.encode(payload)
        }
    }
}

struct PilotResultsPayload: Codable, Hashable {
    var schemaVersion: Int
    var localSessionID: UUID
    var sessionResult: String
    var startedAt: Date
    var completedAt: Date?
    var appBuild: String
    var analysisVersion: Int?
    var thresholdSetIdentifier: String?
    var deviceModel: String
    var operatingSystemVersion: String
    var cameraPosition: String
    var lensType: String?
    var sets: [PilotSetResult]
}

struct PilotProgressPayload: Codable, Hashable {
    var schemaVersion: Int
    var contributionType: PilotContributionType
    var localSessionID: UUID
    var sessionResult: String
    var startedAt: Date
    var completedAt: Date
    var appBuild: String
    var analysisVersion: Int
    var thresholdSetIdentifier: String?
    var deviceModel: String
    var operatingSystemVersion: String
    var cameraPosition: String
    var lensType: String?
    var regions: [PilotRegionResult]
    var failureReasonCodesByPose: [String: String]
}

struct PilotSetResult: Codable, Hashable {
    var setNumber: Int
    var completedAt: Date
    var conditionsStayedTheSame: Bool?
    var deviationReasonCodes: [String]
    var hasSufficientCoreEvidence: Bool?
    var processingDurationMilliseconds: Int?
    var failureReasonCodesByPose: [String: String]
    var regions: [PilotRegionResult]
}

struct PilotRegionResult: Codable, Hashable {
    var region: String
    var status: String
    var fusedDelta: Float?
    var unavailableReasonCode: String?
    var contributions: [PilotPoseResult]
}

struct PilotPoseResult: Codable, Hashable {
    var pose: String
    var baselineValue: Float?
    var currentValue: Float?
    var normalizedDelta: Float?
    var poseMatchScore: Float?
    var status: String
    var reasonCode: String?
}

struct PilotUploadAuthorization: Codable, Hashable {
    var objectID: UUID
    var signedURL: URL?
    var alreadyUploaded: Bool

    init(objectID: UUID, signedURL: URL?, alreadyUploaded: Bool = false) {
        self.objectID = objectID
        self.signedURL = signedURL
        self.alreadyUploaded = alreadyUploaded
    }

    private enum CodingKeys: String, CodingKey {
        // PilotAPIClient applies convertFromSnakeCase before matching these
        // keys, which normalizes object_id/signed_url to objectId/signedUrl.
        case objectID = "objectId"
        case signedURL = "signedUrl"
        case alreadyUploaded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        objectID = try container.decode(UUID.self, forKey: .objectID)
        signedURL = try container.decodeIfPresent(URL.self, forKey: .signedURL)
        alreadyUploaded = try container.decodeIfPresent(Bool.self, forKey: .alreadyUploaded) ?? false
        guard alreadyUploaded != (signedURL != nil) else {
            throw DecodingError.dataCorruptedError(
                forKey: .alreadyUploaded,
                in: container,
                debugDescription: "Pilot upload state must be either already uploaded or authorized for upload."
            )
        }
    }
}

struct PilotEnrollmentResponse: Codable, Hashable {
    var participantID: UUID
    var studyID: UUID
    var studyName: String
    var pilotClosesAt: Date
    var resultsDeleteAfter: Date
    var participantToken: String
    var deletionCode: String
}

struct PilotSubmissionInitialization: Codable, Hashable {
    var submissionID: UUID
    var uploads: [PilotUploadAuthorization]
}

struct PilotSubmissionReceipt: Codable, Hashable {
    var submissionID: UUID
    var receiptCode: String
    var photoDeleteAt: Date?
    var resultsDeleteAt: Date
}

enum PilotStudyError: LocalizedError, Equatable {
    case unavailable
    case invalidInvite
    case pilotFull
    case consentRequired
    case adultConfirmationRequired
    case photoSelectionRequired
    case participantTokenMissing
    case sessionNotComplete
    case ongoingContributionUnavailable
    case photoUnavailable
    case invalidStudyKey
    case payloadRejected
    case uploadFailed
    case serverRejected(String)
    case storageFailed

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Pilot sharing is unavailable right now. Please try again later."
        case .invalidInvite: return "That invite code is invalid, expired, or has already been used."
        case .pilotFull: return "This pilot has reached its participant limit."
        case .consentRequired: return "Choose what you want to share before continuing."
        case .adultConfirmationRequired: return "You must confirm that you are 18 or older to join this pilot."
        case .photoSelectionRequired: return "Select at least one photo, or switch to Results only."
        case .participantTokenMissing: return "This iPhone no longer has the pilot access token. Use your deletion code if you want Evolv to remove shared data."
        case .sessionNotComplete: return "Finish all five sets before sharing this test."
        case .ongoingContributionUnavailable: return "Complete and share the invited consistency test before enabling future contribution."
        case .photoUnavailable: return "One of the selected photos is no longer available on this iPhone. Deselect it and try again."
        case .invalidStudyKey: return "Evolv could not prepare photo encryption for this pilot."
        case .payloadRejected: return "The study service rejected the results package. Nothing new was shared."
        case .uploadFailed: return "The secure upload did not finish. Evolv kept an encrypted retry package on this iPhone."
        case .serverRejected(let message): return message
        case .storageFailed: return "Evolv could not securely save the pending submission on this iPhone."
        }
    }
}
