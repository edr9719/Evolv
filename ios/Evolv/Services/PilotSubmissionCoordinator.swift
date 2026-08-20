import Foundation
import Observation
import UIKit

enum PilotResultsBuilder {
    static func make(
        session: ValidationStudySession,
        scans: [Scan]
    ) throws -> PilotResultsPayload {
        guard session.status == .completed, session.isComplete else {
            throw PilotStudyError.sessionNotComplete
        }
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return PilotResultsPayload(
            schemaVersion: PilotStudyConfiguration.payloadSchemaVersion,
            localSessionID: session.id,
            sessionResult: session.result?.rawValue ?? "unavailable",
            startedAt: session.startedAt,
            completedAt: session.completedAt,
            appBuild: build,
            analysisVersion: session.algorithmMetadata?.analysisVersion,
            thresholdSetIdentifier: session.algorithmMetadata?.thresholdSetIdentifier,
            deviceModel: DeviceDescriptor.hardwareModel,
            operatingSystemVersion: UIDevice.current.systemVersion,
            cameraPosition: session.lockedCameraPosition.rawValue,
            lensType: session.lockedLensType,
            sets: session.sets.sorted(by: { $0.setNumber < $1.setNumber }).map { record in
                let comparison = record.comparison
                return PilotSetResult(
                    setNumber: record.setNumber,
                    completedAt: record.completedAt,
                    conditionsStayedTheSame: record.conditions?.stayedTheSame,
                    deviationReasonCodes: record.conditions?.deviations.map(\.rawValue).sorted() ?? [],
                    hasSufficientCoreEvidence: comparison?.hasSufficientCoreEvidence,
                    processingDurationMilliseconds: comparison?.processingDurationMilliseconds,
                    failureReasonCodesByPose: comparison?.failures ?? [:],
                    regions: comparison?.regionalComparisons.map { region in
                        PilotRegionResult(
                            region: region.region.rawValue,
                            status: region.status.rawValue,
                            fusedDelta: region.normalizedDelta,
                            unavailableReasonCode: region.reason,
                            contributions: region.contributions.map { contribution in
                                PilotPoseResult(
                                    pose: contribution.pose.rawValue,
                                    baselineValue: contribution.baselineValue,
                                    currentValue: contribution.currentValue,
                                    normalizedDelta: contribution.normalizedDelta,
                                    poseMatchScore: contribution.poseMatchScore,
                                    status: contribution.status.rawValue,
                                    reasonCode: contribution.reason
                                )
                            }
                        )
                    } ?? []
                )
            }
        )
    }

    static func photoChoices(
        session: ValidationStudySession,
        scans: [Scan]
    ) -> [PilotPhotoChoice] {
        let scansByID = Dictionary(uniqueKeysWithValues: scans.map { ($0.id, $0) })
        return session.sets.sorted(by: { $0.setNumber < $1.setNumber }).flatMap { record in
            guard let scan = scansByID[record.scanID] else { return [PilotPhotoChoice]() }
            return Pose.required.compactMap { pose in
                scan.capture(for: pose).map {
                    PilotPhotoChoice(
                        captureID: $0.id,
                        scanID: scan.id,
                        setNumber: record.setNumber,
                        pose: pose
                    )
                }
            }
        }
    }
}

enum PilotProgressResultsBuilder {
    static func make(scan: Scan, analysis: ScanAnalysis) throws -> PilotProgressPayload {
        guard scan.isCanonicalProgressScan,
              scan.validationSessionID == nil,
              analysis.id == scan.id else {
            throw PilotStudyError.payloadRejected
        }
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let cameraMetadata = scan.standardCaptures.compactMap(\.cameraMetadata)
        let positions = Set(cameraMetadata.map(\.position))
        let lenses = Set(cameraMetadata.compactMap(\.lensType))
        let cameraPosition = positions.count == 1 ? positions.first?.rawValue ?? "unknown" : "mixed_or_unknown"
        let lensType = lenses.count == 1 ? lenses.first : nil
        let regions = (analysis.visualSignals.regionalComparisons ?? []).map { region in
            PilotRegionResult(
                region: region.region.rawValue,
                status: region.status.rawValue,
                fusedDelta: region.normalizedDelta,
                unavailableReasonCode: region.reason,
                contributions: region.contributions.map { contribution in
                    PilotPoseResult(
                        pose: contribution.pose.rawValue,
                        baselineValue: contribution.baselineValue,
                        currentValue: contribution.currentValue,
                        normalizedDelta: contribution.normalizedDelta,
                        poseMatchScore: contribution.poseMatchScore,
                        status: contribution.status.rawValue,
                        reasonCode: contribution.reason
                    )
                }
            )
        }
        return PilotProgressPayload(
            schemaVersion: PilotStudyConfiguration.payloadSchemaVersion,
            contributionType: .progressScan,
            localSessionID: scan.id,
            sessionResult: analysis.analysisAvailability?.rawValue ?? "unavailable",
            startedAt: scan.date,
            completedAt: analysis.analyzedAt,
            appBuild: build,
            analysisVersion: analysis.analysisVersion,
            thresholdSetIdentifier: analysis.algorithmMetadata?.thresholdSetIdentifier,
            deviceModel: DeviceDescriptor.hardwareModel,
            operatingSystemVersion: UIDevice.current.systemVersion,
            cameraPosition: cameraPosition,
            lensType: lensType,
            regions: regions,
            failureReasonCodesByPose: analysis.poseFailures ?? [:]
        )
    }

    static func photoChoices(scan: Scan) -> [PilotPhotoChoice] {
        Pose.required.compactMap { pose in
            scan.capture(for: pose).map {
                PilotPhotoChoice(
                    captureID: $0.id,
                    scanID: scan.id,
                    setNumber: 1,
                    pose: pose
                )
            }
        }
    }
}

protocol PilotEnrollmentPersisting {
    func loadEnrollment() -> PilotLocalEnrollment?
    func saveEnrollment(_ enrollment: PilotLocalEnrollment?) throws
}

struct PilotEnrollmentStore: PilotEnrollmentPersisting {
    func loadEnrollment() -> PilotLocalEnrollment? { PilotStudyStore.loadEnrollment() }
    func saveEnrollment(_ enrollment: PilotLocalEnrollment?) throws {
        try PilotStudyStore.saveEnrollment(enrollment)
    }
}

@MainActor
@Observable
final class PilotSubmissionCoordinator {
    static let shared = PilotSubmissionCoordinator()

    private(set) var enrollment: PilotLocalEnrollment?
    private(set) var submissions: [PilotSubmissionRecord]
    private(set) var isWorking = false
    private(set) var lastMessage: String?

    private let api: PilotAPIClient
    private let secrets: PilotSecretStoring
    private let enrollmentStore: PilotEnrollmentPersisting

    var hasCompletedConsistencySubmission: Bool {
        submissions.contains {
            $0.status == .completed && $0.structuredPayload.contributionType == .consistencyTest
        }
    }

    var ongoingMode: PilotOngoingContributionMode? { enrollment?.ongoingConsent?.mode }

    init(
        api: PilotAPIClient = PilotAPIClient(),
        secrets: PilotSecretStoring = PilotKeychainStore(),
        enrollmentStore: PilotEnrollmentPersisting = PilotEnrollmentStore()
    ) {
        self.api = api
        self.secrets = secrets
        self.enrollmentStore = enrollmentStore
        self.enrollment = enrollmentStore.loadEnrollment()
        self.submissions = PilotStudyStore.loadSubmissions()
    }

    #if DEBUG
    /// In-memory state seam for application UI tests. It never writes pilot
    /// enrollment, tokens, invitation codes, or submissions to disk.
    func configureForUITesting(
        enrollment: PilotLocalEnrollment?,
        submissions: [PilotSubmissionRecord] = []
    ) {
        self.enrollment = enrollment
        self.submissions = submissions
        isWorking = false
        lastMessage = nil
    }
    #endif

    func enroll(inviteCode: String, consent: PilotConsent) async throws {
        guard consent.adultConfirmed else { throw PilotStudyError.adultConfirmationRequired }
        isWorking = true
        defer { isWorking = false }
        let normalized = PilotAPIClient.normalizeInviteCode(inviteCode)
        let attempt: PilotEnrollmentAttempt
        if let saved = try secrets.enrollmentAttempt() {
            guard saved.normalizedInviteCode == normalized else {
                throw PilotStudyError.serverRejected(
                    "Finish retrying the invitation already saved on this iPhone before using a different code."
                )
            }
            attempt = saved
        } else {
            attempt = try PilotAPIClient.makeEnrollmentAttempt(inviteCode: normalized)
            // This write must complete before the request. It is the recovery
            // anchor if the server commits but the response is interrupted.
            try secrets.saveEnrollmentAttempt(attempt)
        }
        let response = try await api.enroll(attempt: attempt)
        try secrets.save(
            participantToken: response.participantToken,
            deletionCode: response.deletionCode
        )
        let local = PilotLocalEnrollment(
            participantID: response.participantID,
            studyID: response.studyID,
            studyName: response.studyName,
            enrolledAt: Date(),
            pilotClosesAt: response.pilotClosesAt,
            resultsDeleteAfter: response.resultsDeleteAfter,
            consent: consent,
            status: .active
        )
        try enrollmentStore.saveEnrollment(local)
        enrollment = local
        // Cleanup should not turn a fully persisted enrollment into a visible
        // failure. deleteAll() also clears a rare stale attempt on withdrawal.
        try? secrets.deleteEnrollmentAttempt()
        lastMessage = "Pilot access saved on this iPhone."
    }

    func validateInvitation(_ inviteCode: String) async throws -> PilotInvitationValidation {
        isWorking = true
        defer { isWorking = false }
        #if DEBUG
        if let fixture = ProcessInfo.processInfo.environment["EVOLV_UI_TEST_INVITE_VALIDATION"] {
            switch fixture {
            case "valid":
                return PilotInvitationValidation(
                    status: .valid,
                    studyName: "UI test pilot",
                    pilotClosesAt: Date().addingTimeInterval(86_400)
                )
            case "used": throw PilotStudyError.inviteAlreadyUsed
            case "closed": throw PilotStudyError.pilotClosed
            case "invalid": throw PilotStudyError.invalidInvite
            case "offline": throw PilotStudyError.offline
            default: break
            }
        }
        #endif
        return try await api.validateInvitation(inviteCode: inviteCode)
    }

    func updateConsent(_ consent: PilotConsent) throws {
        guard consent.adultConfirmed else { throw PilotStudyError.adultConfirmationRequired }
        guard var enrollment else { throw PilotStudyError.consentRequired }
        enrollment.consent = consent
        try enrollmentStore.saveEnrollment(enrollment)
        self.enrollment = enrollment
    }

    func enableOngoingContribution(_ mode: PilotOngoingContributionMode, now: Date = Date()) throws {
        guard PilotOngoingContributionPolicy.canEnable(
            enrollment: enrollment,
            hasCompletedConsistencySubmission: hasCompletedConsistencySubmission,
            now: now
        ), var enrollment else {
            throw PilotStudyError.ongoingContributionUnavailable
        }
        enrollment.ongoingConsent = PilotOngoingConsent(
            version: PilotStudyConfiguration.ongoingConsentVersion,
            mode: mode,
            acceptedAt: now
        )
        try enrollmentStore.saveEnrollment(enrollment)
        self.enrollment = enrollment
        lastMessage = mode == .resultsOnly
            ? "Future progress-scan results will be shared. Photos remain on this iPhone."
            : "Evolv will ask before sharing each future progress scan."
    }

    func disableOngoingContribution() async throws {
        guard var enrollment else { throw PilotStudyError.consentRequired }
        isWorking = true
        defer { isWorking = false }
        // Revoke future authorization locally first. A network failure must never
        // leave automatic contribution enabled on this iPhone.
        enrollment.ongoingConsent = nil
        try enrollmentStore.saveEnrollment(enrollment)
        self.enrollment = enrollment
        let pendingProgress = submissions.filter {
            $0.status != .completed
                && $0.status != .deleted
                && $0.structuredPayload.contributionType == .progressScan
        }
        var cancellationPending = false
        for record in pendingProgress {
            do {
                try await cancelPending(record)
            } catch {
                cancellationPending = true
                markFailed(recordID: record.id, reason: "cancellation_pending")
            }
        }
        lastMessage = cancellationPending
            ? "Future contribution is off. A pending server cancellation will retry when Evolv is online."
            : "Future contribution is off. Previously shared data is unchanged."
    }

    @discardableResult
    func prepareAndSubmit(
        session: ValidationStudySession,
        scans: [Scan],
        consent: PilotConsent,
        selectedPhotos: Set<UUID>,
        photoApprovalConfirmed: Bool
    ) async throws -> PilotSubmissionRecord {
        guard enrollment?.status == .active else { throw PilotStudyError.consentRequired }
        let approvedSelectionCount = consent.shareScope == .resultsAndSelectedPhotos
            ? selectedPhotos.count
            : 0
        try PilotConsentPolicy.validate(
            consent: consent,
            selectedPhotoCount: approvedSelectionCount,
            photoApprovalConfirmed: photoApprovalConfirmed
        )
        try updateConsent(consent)

        isWorking = true
        defer { isWorking = false }
        let allChoices = PilotResultsBuilder.photoChoices(session: session, scans: scans)
        let choices = consent.shareScope == .resultsAndSelectedPhotos
            ? allChoices.filter { selectedPhotos.contains($0.captureID) }
            : []
        guard choices.count <= PilotStudyConfiguration.maximumPhotoCount else {
            throw PilotStudyError.payloadRejected
        }

        let payload = try PilotResultsBuilder.make(session: session, scans: scans)
        let captureMap = Dictionary(uniqueKeysWithValues: scans.flatMap(\.captures).map { ($0.id, $0) })
        let record = try await prepareSubmission(
            localSessionID: session.id,
            payload: .consistency(payload),
            consent: consent,
            choices: choices,
            captureMap: captureMap
        )
        lastMessage = choices.isEmpty
            ? "Results shared. No photos were uploaded."
            : "Results and \(choices.count) selected photo\(choices.count == 1 ? "" : "s") shared securely."
        return record
    }

    @discardableResult
    func prepareProgressAndSubmit(
        scan: Scan,
        analysis: ScanAnalysis,
        shareScope: PilotShareScope,
        selectedPhotos: Set<UUID>,
        photoApprovalConfirmed: Bool
    ) async throws -> PilotSubmissionRecord {
        guard PilotOngoingContributionPolicy.canContribute(
            enrollment: enrollment,
            hasCompletedConsistencySubmission: hasCompletedConsistencySubmission,
            scan: scan,
            analysis: analysis
        ), let mode = ongoingMode else {
            throw PilotStudyError.ongoingContributionUnavailable
        }
        if mode == .resultsOnly && (shareScope != .resultsOnly || !selectedPhotos.isEmpty) {
            throw PilotStudyError.payloadRejected
        }
        let allChoices = PilotProgressResultsBuilder.photoChoices(scan: scan)
        let choices = shareScope == .resultsAndSelectedPhotos
            ? allChoices.filter { selectedPhotos.contains($0.captureID) }
            : []
        guard let ongoingConsent = enrollment?.ongoingConsent else {
            throw PilotStudyError.ongoingContributionUnavailable
        }
        let consent = PilotConsent(
            version: PilotStudyConfiguration.ongoingConsentVersion,
            adultConfirmed: true,
            shareScope: shareScope,
            // Automatic results-only sharing relies on the durable opt-in time.
            // Ask-every-scan records the participant's fresh per-scan approval.
            acceptedAt: mode == .resultsOnly ? ongoingConsent.acceptedAt : Date()
        )
        try PilotConsentPolicy.validate(
            consent: consent,
            selectedPhotoCount: choices.count,
            photoApprovalConfirmed: photoApprovalConfirmed
        )
        isWorking = true
        defer { isWorking = false }
        let payload = try PilotProgressResultsBuilder.make(scan: scan, analysis: analysis)
        let captureMap = Dictionary(uniqueKeysWithValues: scan.captures.map { ($0.id, $0) })
        let record = try await prepareSubmission(
            localSessionID: scan.id,
            payload: .progress(payload),
            consent: consent,
            choices: choices,
            captureMap: captureMap
        )
        lastMessage = choices.isEmpty
            ? "This scan's results were shared. No photos were uploaded."
            : "This scan's results and \(choices.count) selected photo\(choices.count == 1 ? "" : "s") were shared securely."
        return record
    }

    func submitAutomaticOngoingResultsIfEligible(scan: Scan, analysis: ScanAnalysis) async {
        guard !isWorking, ongoingMode == .resultsOnly else { return }
        do {
            _ = try await prepareProgressAndSubmit(
                scan: scan,
                analysis: analysis,
                shareScope: .resultsOnly,
                selectedPhotos: [],
                photoApprovalConfirmed: false
            )
        } catch PilotStudyError.ongoingContributionUnavailable {
            return
        } catch {
            // A prepared record remains encrypted/queued locally and retryPending
            // will resume it. Avoid interrupting the user's analysis UI.
        }
    }

    func retryPending() async {
        guard !isWorking, (try? secrets.participantToken()) != nil else { return }
        isWorking = true
        defer { isWorking = false }
        let pending = submissions.filter { $0.status == .queued || $0.status == .failed || $0.status == .uploading }
        for record in pending {
            do {
                if record.structuredPayload.contributionType == .progressScan,
                   enrollment?.ongoingConsent == nil {
                    try await cancelPending(record)
                } else {
                    _ = try await upload(record)
                }
            } catch {
                markFailed(recordID: record.id, reason: Self.reasonCode(for: error))
            }
        }
    }

    func refreshRemoteStatus() async throws -> String {
        guard let token = try secrets.participantToken() else {
            throw PilotStudyError.participantTokenMissing
        }
        return try await api.status(participantToken: token)
    }

    func deletionCode() -> String? {
        try? secrets.deletionCode()
    }

    func withdraw() async throws {
        guard let token = try secrets.participantToken() else {
            throw PilotStudyError.participantTokenMissing
        }
        isWorking = true
        defer { isWorking = false }
        try await api.withdraw(participantToken: token)
        if var local = enrollment {
            local.status = .withdrawn
            try enrollmentStore.saveEnrollment(local)
            enrollment = local
        }
        try secrets.deleteParticipantToken()
        submissions.indices.forEach { index in
            PilotStudyStore.removeCiphertexts(for: submissions[index].id)
            submissions[index].status = .deleted
            try? PilotStudyStore.saveSubmission(submissions[index])
        }
        reload()
        lastMessage = "Shared pilot data was deleted. Timeline photos remain on this iPhone."
    }

    func deleteWithRecoveryCode(_ code: String) async throws {
        isWorking = true
        defer { isWorking = false }
        try await api.delete(deletionCode: code)
        try? secrets.deleteAll()
        PilotStudyStore.deleteAllLocalSharingData()
        enrollment = nil
        submissions = []
        lastMessage = "Shared pilot data was deleted. Local scans were not changed."
    }

    private func prepareSubmission(
        localSessionID: UUID,
        payload: PilotStructuredPayload,
        consent: PilotConsent,
        choices: [PilotPhotoChoice],
        captureMap: [UUID: PoseCapture]
    ) async throws -> PilotSubmissionRecord {
        if let existing = submissions.last(where: {
            $0.localSessionID == localSessionID && $0.status != .deleted
        }) {
            if existing.status == .completed { return existing }
            let sameSelection = Set(existing.selectedPhotos.map(\.captureID)) == Set(choices.map(\.captureID))
                && existing.consent.shareScope == consent.shareScope
                && existing.structuredPayload.contributionType == payload.contributionType
            if sameSelection {
                do {
                    return try await upload(existing)
                } catch {
                    markFailed(recordID: existing.id, reason: Self.reasonCode(for: error))
                    throw error
                }
            }
            try await cancelPending(existing)
        }

        let id = UUID()
        var encryptedObjects: [PilotEncryptedObject] = []
        var wrappedKey: PilotWrappedKeyEnvelope?
        do {
            if !choices.isEmpty {
                let key = PilotCrypto.makeSubmissionKey()
                wrappedKey = try PilotCrypto.wrap(submissionKey: key)
                for choice in choices {
                    guard let capture = captureMap[choice.captureID],
                          let image = PhotoStore.loadImage(named: capture.imageFilename) else {
                        throw PilotStudyError.photoUnavailable
                    }
                    let plaintext = try PilotCrypto.normalizedJPEG(from: image)
                    let encrypted = try PilotCrypto.encryptPhoto(plaintext, using: key)
                    let objectID = UUID()
                    let relative = try PilotStudyStore.writeCiphertext(
                        encrypted.ciphertext,
                        submissionID: id,
                        objectID: objectID
                    )
                    encryptedObjects.append(PilotEncryptedObject(
                        id: objectID,
                        captureID: choice.captureID,
                        setNumber: choice.setNumber,
                        pose: choice.pose,
                        relativeCiphertextPath: relative,
                        ciphertextSHA256: encrypted.sha256,
                        ciphertextByteCount: encrypted.ciphertext.count
                    ))
                }
            }
        } catch {
            PilotStudyStore.removeCiphertexts(for: id)
            throw error
        }

        var record = PilotSubmissionRecord(
            id: id,
            localSessionID: localSessionID,
            remoteSubmissionID: nil,
            idempotencyKey: UUID(),
            status: .queued,
            consent: consent,
            selectedPhotos: choices,
            encryptedObjects: encryptedObjects,
            wrappedKey: wrappedKey,
            structuredPayload: payload,
            createdAt: Date(),
            updatedAt: Date(),
            receiptCode: nil,
            failureReasonCode: nil
        )
        try PilotStudyStore.saveSubmission(record)
        reload()
        do {
            record = try await upload(record)
            return record
        } catch {
            markFailed(recordID: record.id, reason: Self.reasonCode(for: error))
            throw error
        }
    }

    private func upload(_ original: PilotSubmissionRecord) async throws -> PilotSubmissionRecord {
        guard let token = try secrets.participantToken() else {
            throw PilotStudyError.participantTokenMissing
        }
        var record = original
        record.status = .uploading
        record.updatedAt = Date()
        record.failureReasonCode = nil
        try PilotStudyStore.saveSubmission(record)
        reload()

        let initialized = try await api.initialize(record: record, participantToken: token)
        record.remoteSubmissionID = initialized.submissionID
        record.updatedAt = Date()
        try PilotStudyStore.saveSubmission(record)
        reload()
        let authorizations = Dictionary(uniqueKeysWithValues: initialized.uploads.map { ($0.objectID, $0) })
        guard authorizations.count == record.encryptedObjects.count else {
            throw PilotStudyError.payloadRejected
        }
        for object in record.encryptedObjects {
            guard let authorization = authorizations[object.id] else {
                throw PilotStudyError.payloadRejected
            }
            if authorization.alreadyUploaded {
                guard authorization.signedURL == nil else {
                    throw PilotStudyError.payloadRejected
                }
                continue
            }
            let ciphertext = try PilotStudyStore.readCiphertext(relativePath: object.relativeCiphertextPath)
            guard ciphertext.count == object.ciphertextByteCount,
                  PilotCrypto.sha256Hex(ciphertext) == object.ciphertextSHA256 else {
                throw PilotStudyError.storageFailed
            }
            try await api.upload(ciphertext: ciphertext, to: authorization)
        }
        let receipt = try await api.complete(
            submissionID: initialized.submissionID,
            idempotencyKey: record.idempotencyKey,
            participantToken: token
        )
        record.status = .completed
        record.updatedAt = Date()
        record.receiptCode = receipt.receiptCode
        try PilotStudyStore.saveSubmission(record)
        PilotStudyStore.removeCiphertexts(for: record.id)
        reload()
        return record
    }

    private func cancelPending(_ original: PilotSubmissionRecord) async throws {
        var record = original
        // If initialization never reached the server there is nothing remote to
        // delete. Do not create a server record merely in order to cancel it.
        if let remoteID = record.remoteSubmissionID {
            guard let token = try secrets.participantToken() else {
                throw PilotStudyError.participantTokenMissing
            }
            try await api.cancel(submissionID: remoteID, participantToken: token)
        }
        record.status = .deleted
        record.updatedAt = Date()
        try PilotStudyStore.saveSubmission(record)
        PilotStudyStore.removeCiphertexts(for: record.id)
        reload()
    }

    private func markFailed(recordID: UUID, reason: String) {
        guard let index = submissions.firstIndex(where: { $0.id == recordID }) else { return }
        var record = submissions[index]
        record.status = .failed
        record.updatedAt = Date()
        record.failureReasonCode = reason
        try? PilotStudyStore.saveSubmission(record)
        reload()
    }

    private func reload() {
        enrollment = enrollmentStore.loadEnrollment()
        submissions = PilotStudyStore.loadSubmissions()
    }

    private static func reasonCode(for error: Error) -> String {
        switch error {
        case PilotStudyError.participantTokenMissing: return "participant_token_missing"
        case PilotStudyError.photoUnavailable: return "selected_photo_unavailable"
        case PilotStudyError.storageFailed: return "local_storage_failed"
        case PilotStudyError.payloadRejected: return "payload_rejected"
        default: return "network_or_service_failure"
        }
    }
}

private enum DeviceDescriptor {
    static var hardwareModel: String {
        var system = utsname()
        uname(&system)
        return withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }
}
