import CryptoKit
import XCTest
@testable import Evolv

final class PilotSharingTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_786_089_600)

    func testResultsOnlyIsDefaultAndRejectsAnyPhotoObject() {
        XCTAssertEqual(PilotShareScope.allCases.first, .resultsOnly)
        let consent = PilotConsent(
            version: PilotStudyConfiguration.consentVersion,
            adultConfirmed: true,
            shareScope: .resultsOnly,
            acceptedAt: referenceDate
        )
        XCTAssertNoThrow(try PilotConsentPolicy.validate(
            consent: consent,
            selectedPhotoCount: 0,
            photoApprovalConfirmed: false
        ))
        XCTAssertThrowsError(try PilotConsentPolicy.validate(
            consent: consent,
            selectedPhotoCount: 1,
            photoApprovalConfirmed: true
        ))
    }

    func testPhotoScopeRequiresAdultIndividualSelectionAndApproval() {
        var consent = PilotConsent(
            version: PilotStudyConfiguration.consentVersion,
            adultConfirmed: false,
            shareScope: .resultsAndSelectedPhotos,
            acceptedAt: referenceDate
        )
        XCTAssertThrowsError(try PilotConsentPolicy.validate(
            consent: consent,
            selectedPhotoCount: 1,
            photoApprovalConfirmed: true
        )) { XCTAssertEqual($0 as? PilotStudyError, .adultConfirmationRequired) }
        consent.adultConfirmed = true
        XCTAssertThrowsError(try PilotConsentPolicy.validate(
            consent: consent,
            selectedPhotoCount: 0,
            photoApprovalConfirmed: true
        )) { XCTAssertEqual($0 as? PilotStudyError, .photoSelectionRequired) }
        XCTAssertThrowsError(try PilotConsentPolicy.validate(
            consent: consent,
            selectedPhotoCount: 1,
            photoApprovalConfirmed: false
        )) { XCTAssertEqual($0 as? PilotStudyError, .photoSelectionRequired) }
        XCTAssertNoThrow(try PilotConsentPolicy.validate(
            consent: consent,
            selectedPhotoCount: 1,
            photoApprovalConfirmed: true
        ))
    }

    func testPhotoCiphertextAndWrappedKeyDecryptOnlyWithPrivateKey() throws {
        let researcherPrivate = P256.KeyAgreement.PrivateKey()
        let contentKey = PilotCrypto.makeSubmissionKey()
        let plaintext = Data("private-fixture-photo".utf8)
        let encrypted = try PilotCrypto.encryptPhoto(plaintext, using: contentKey)
        XCTAssertNotEqual(encrypted.ciphertext, plaintext)
        XCTAssertEqual(encrypted.sha256, PilotCrypto.sha256Hex(encrypted.ciphertext))

        let envelope = try PilotCrypto.wrap(
            submissionKey: contentKey,
            publicKeyBase64: researcherPrivate.publicKey.x963Representation.base64EncodedString()
        )
        let ephemeral = try P256.KeyAgreement.PublicKey(
            x963Representation: XCTUnwrap(Data(base64Encoded: envelope.ephemeralPublicKeyBase64))
        )
        let shared = try researcherPrivate.sharedSecretFromKeyAgreement(with: ephemeral)
        let wrappingKey = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: try XCTUnwrap(Data(base64Encoded: envelope.saltBase64)),
            sharedInfo: Data("evolv-pilot-wrap-v1".utf8),
            outputByteCount: 32
        )
        let sealedKey = try AES.GCM.SealedBox(
            combined: XCTUnwrap(Data(base64Encoded: envelope.sealedKeyBase64))
        )
        let recoveredRawKey = try AES.GCM.open(sealedKey, using: wrappingKey)
        let recoveredKey = SymmetricKey(data: recoveredRawKey)
        let sealedPhoto = try AES.GCM.SealedBox(combined: encrypted.ciphertext)
        XCTAssertEqual(try AES.GCM.open(sealedPhoto, using: recoveredKey), plaintext)

        let wrongKey = PilotCrypto.makeSubmissionKey()
        XCTAssertThrowsError(try AES.GCM.open(sealedPhoto, using: wrongKey))
    }

    func testStructuredPilotPayloadContainsAllowlistedEvidenceNotRawCaptureData() throws {
        let payload = try PilotResultsBuilder.make(session: completedSession(), scans: [])
        let encoder = JSONEncoder.pilot
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(payload)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8)).lowercased()

        XCTAssertTrue(text.contains("pose_match_score"))
        XCTAssertTrue(text.contains("processing_duration_milliseconds"))
        for forbidden in ["image_filename", "landmark", "person_mask", "raw_weight", "email", "location"] {
            XCTAssertFalse(text.contains(forbidden), "Payload leaked forbidden field: \(forbidden)")
        }
    }

    func testSignedUploadUsesPUTAndCiphertextContentType() async throws {
        let spy = PilotTransportSpy()
        let client = PilotAPIClient(
            transport: spy,
            baseURL: URL(string: "https://example.test/functions/v1/pilot-api")!,
            publishableKey: "public-test-key",
            networkAllowed: true
        )
        let bytes = Data([1, 2, 3, 4])
        try await client.upload(
            ciphertext: bytes,
            to: PilotUploadAuthorization(
                objectID: UUID(),
                signedURL: URL(string: "https://storage.example.test/object/upload/sign/test?token=opaque")!,
                alreadyUploaded: false
            )
        )
        let request = try XCTUnwrap(spy.lastRequest)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/octet-stream")
        XCTAssertEqual(request.httpBody, bytes)
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Evolv-Participant-Token"))
    }

    func testUploadAuthorizationDecodesMissingAndAlreadyUploadedStates() throws {
        let objectID = UUID()
        let decoder = JSONDecoder.pilot
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let upload = try decoder.decode(
            PilotUploadAuthorization.self,
            from: Data(#"{"object_id":"\#(objectID.uuidString)","signed_url":"https://storage.example.test/upload","already_uploaded":false}"#.utf8)
        )
        XCTAssertFalse(upload.alreadyUploaded)
        XCTAssertNotNil(upload.signedURL)

        let existing = try decoder.decode(
            PilotUploadAuthorization.self,
            from: Data(#"{"object_id":"\#(objectID.uuidString)","already_uploaded":true}"#.utf8)
        )
        XCTAssertTrue(existing.alreadyUploaded)
        XCTAssertNil(existing.signedURL)
    }

    func testUploadAuthorizationRejectsAmbiguousServerState() {
        let objectID = UUID()
        let decoder = JSONDecoder.pilot
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        XCTAssertThrowsError(try decoder.decode(
            PilotUploadAuthorization.self,
            from: Data(#"{"object_id":"\#(objectID.uuidString)","already_uploaded":false}"#.utf8)
        ))
        XCTAssertThrowsError(try decoder.decode(
            PilotUploadAuthorization.self,
            from: Data(#"{"object_id":"\#(objectID.uuidString)","signed_url":"https://storage.example.test/upload","already_uploaded":true}"#.utf8)
        ))
    }

    func testAlreadyUploadedObjectCannotBeSentToUploadTransport() async {
        let spy = PilotTransportSpy()
        let client = PilotAPIClient(
            transport: spy,
            baseURL: URL(string: "https://example.test/functions/v1/pilot-api")!,
            publishableKey: "public-test-key",
            networkAllowed: true
        )

        do {
            try await client.upload(
                ciphertext: Data([1, 2, 3]),
                to: PilotUploadAuthorization(objectID: UUID(), signedURL: nil, alreadyUploaded: true)
            )
            XCTFail("An already-uploaded object should bypass upload transport")
        } catch {
            XCTAssertEqual(error as? PilotStudyError, .payloadRejected)
        }
        XCTAssertNil(spy.lastRequest)
    }

    func testCancelUsesParticipantAuthenticationAndExactSubmissionID() async throws {
        let spy = PilotJSONTransportSpy(responseBody: #"{"deleted":true}"#)
        let client = PilotAPIClient(
            transport: spy,
            baseURL: URL(string: "https://example.test/functions/v1/pilot-api")!,
            publishableKey: "public-test-key",
            networkAllowed: true
        )
        let submissionID = UUID()

        try await client.cancel(
            submissionID: submissionID,
            participantToken: "opaque-participant-token"
        )

        let request = try XCTUnwrap(spy.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/functions/v1/pilot-api/submissions/cancel")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-Evolv-Participant-Token"),
            "opaque-participant-token"
        )
        let body = try XCTUnwrap(request.httpBody)
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(decoded["submission_id"].flatMap(UUID.init(uuidString:)), submissionID)
    }

    func testEnrollmentReportsAFullCohortSeparatelyFromAnInvalidInvite() async {
        let spy = PilotJSONTransportSpy(
            responseBody: #"{"code":"study_full","message":"This pilot has reached its participant limit."}"#,
            statusCode: 409
        )
        let client = PilotAPIClient(
            transport: spy,
            baseURL: URL(string: "https://example.test/functions/v1/pilot-api")!,
            publishableKey: "public-test-key",
            networkAllowed: true
        )

        do {
            _ = try await client.enroll(inviteCode: "ABCDE12345ABCDE12345")
            XCTFail("A full cohort should reject enrollment")
        } catch {
            XCTAssertEqual(error as? PilotStudyError, .pilotFull)
        }
    }

    func testLegacyComparisonDecodesWithoutTiming() throws {
        let data = Data(#"{"setNumber":2,"regionalComparisons":[],"failures":{},"hasSufficientCoreEvidence":false}"#.utf8)
        let decoded = try JSONDecoder().decode(ValidationSetComparison.self, from: data)
        XCTAssertNil(decoded.processingDurationMilliseconds)
    }

    func testLegacyConsistencySubmissionPayloadDecodesWithoutWrapperDiscriminator() throws {
        let legacy = try PilotResultsBuilder.make(session: completedSession(), scans: [])
        let data = try JSONEncoder.pilot.encode(legacy)
        let decoded = try JSONDecoder.pilot.decode(PilotStructuredPayload.self, from: data)

        XCTAssertEqual(decoded.contributionType, .consistencyTest)
        guard case .consistency(let payload) = decoded else {
            return XCTFail("Legacy payload was not preserved as a consistency contribution")
        }
        XCTAssertEqual(payload.localSessionID, legacy.localSessionID)
    }

    func testOngoingContributionRequiresCompletedPilotAndASeparateFutureOptIn() {
        var enrollment = activeEnrollment(ongoingConsent: nil)
        XCTAssertFalse(PilotOngoingContributionPolicy.canEnable(
            enrollment: enrollment,
            hasCompletedConsistencySubmission: false,
            now: referenceDate
        ))
        XCTAssertTrue(PilotOngoingContributionPolicy.canEnable(
            enrollment: enrollment,
            hasCompletedConsistencySubmission: true,
            now: referenceDate
        ))

        enrollment.ongoingConsent = PilotOngoingConsent(
            version: PilotStudyConfiguration.ongoingConsentVersion,
            mode: .resultsOnly,
            acceptedAt: referenceDate
        )
        XCTAssertNotNil(enrollment.ongoingConsent)
    }

    func testOngoingPolicyAllowsOnlyCompleteFutureCanonicalScansWithCurrentAnalysis() {
        let enrollment = activeEnrollment(ongoingConsent: PilotOngoingConsent(
            version: PilotStudyConfiguration.ongoingConsentVersion,
            mode: .askEveryScan,
            acceptedAt: referenceDate
        ))
        var scan = progressScan(date: referenceDate.addingTimeInterval(60))
        var analysis = progressAnalysis(
            id: scan.id,
            analyzedAt: referenceDate.addingTimeInterval(90)
        )
        XCTAssertTrue(PilotOngoingContributionPolicy.canContribute(
            enrollment: enrollment,
            hasCompletedConsistencySubmission: true,
            scan: scan,
            analysis: analysis
        ))

        scan.scanRole = .sameDayExtra
        XCTAssertFalse(PilotOngoingContributionPolicy.canContribute(
            enrollment: enrollment,
            hasCompletedConsistencySubmission: true,
            scan: scan,
            analysis: analysis
        ))
        scan.scanRole = .canonical
        scan.captureCompleteness = .incomplete
        XCTAssertFalse(PilotOngoingContributionPolicy.canContribute(
            enrollment: enrollment,
            hasCompletedConsistencySubmission: true,
            scan: scan,
            analysis: analysis
        ))
        scan.captureCompleteness = .complete
        analysis.analysisVersion = AnalysisStore.currentAnalysisVersion - 1
        XCTAssertFalse(PilotOngoingContributionPolicy.canContribute(
            enrollment: enrollment,
            hasCompletedConsistencySubmission: true,
            scan: scan,
            analysis: analysis
        ))
    }

    func testProgressPayloadUsesDerivedAllowlistAndNeverIncludesPhotoData() throws {
        let scan = progressScan(date: referenceDate.addingTimeInterval(60))
        let analysis = progressAnalysis(id: scan.id, analyzedAt: referenceDate.addingTimeInterval(90))
        let payload = try PilotProgressResultsBuilder.make(scan: scan, analysis: analysis)
        let encoder = JSONEncoder.pilot
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(payload)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8)).lowercased()

        XCTAssertTrue(text.contains("progress_scan"))
        XCTAssertTrue(text.contains("regions"))
        for forbidden in ["image_filename", "capture_id", "landmark", "person_mask", "raw_weight", "email", "location"] {
            XCTAssertFalse(text.contains(forbidden), "Progress payload leaked forbidden field: \(forbidden)")
        }
    }

    private func completedSession() -> ValidationStudySession {
        let comparison = ValidationSetComparison(
            setNumber: 2,
            regionalComparisons: [RegionalComparison(
                region: .waist,
                status: .stable,
                normalizedDelta: 0,
                contributions: [PoseContribution(
                    pose: .front,
                    baselineValue: 0.5,
                    currentValue: 0.5,
                    normalizedDelta: 0,
                    poseMatchScore: 0.98,
                    status: .supported,
                    reason: nil
                )],
                reason: nil
            )],
            failures: [:],
            hasSufficientCoreEvidence: true,
            processingDurationMilliseconds: 125
        )
        let sets = (1...5).map { number in
            ValidationSetRecord(
                setNumber: number,
                scanID: UUID(),
                completedAt: referenceDate.addingTimeInterval(Double(number)),
                conditions: ValidationSetConditions(stayedTheSame: true, deviations: [], recordedAt: referenceDate),
                comparison: number == 1 ? nil : comparison,
                usedExistingCanonicalScan: false
            )
        }
        return ValidationStudySession(
            enrollment: ValidationEnrollment(
                enrolledAt: referenceDate,
                programVersion: 1,
                shareScope: .resultsOnly,
                consentVersion: PilotStudyConfiguration.consentVersion
            ),
            startedAt: referenceDate,
            expiresAt: referenceDate.addingTimeInterval(3_600),
            status: .completed,
            lockedCameraPosition: .front,
            lockedLensType: "wide",
            sets: sets,
            draftSetNumber: nil,
            draftCaptures: [],
            result: .consistent,
            statusReasons: [],
            completedAt: referenceDate.addingTimeInterval(1_000),
            algorithmMetadata: AnalysisAlgorithmMetadata(
                analysisVersion: PilotStudyConfiguration.analysisVersion,
                bodyPoseRevision: 1,
                personSegmentationRevision: 1,
                operatingSystemVersion: "test-os",
                thresholdSetIdentifier: "engineering-v1"
            )
        )
    }

    func testPilotPayloadVersionTracksTheAnalysisEngine() throws {
        let payload = try PilotResultsBuilder.make(session: completedSession(), scans: [])

        XCTAssertEqual(PilotStudyConfiguration.analysisVersion, AnalysisStore.currentAnalysisVersion)
        XCTAssertEqual(payload.analysisVersion, AnalysisStore.currentAnalysisVersion)
    }

    private func activeEnrollment(ongoingConsent: PilotOngoingConsent?) -> PilotLocalEnrollment {
        PilotLocalEnrollment(
            participantID: UUID(),
            studyID: UUID(),
            studyName: "Test pilot",
            enrolledAt: referenceDate.addingTimeInterval(-60),
            pilotClosesAt: referenceDate.addingTimeInterval(86_400),
            resultsDeleteAfter: referenceDate.addingTimeInterval(31_536_000),
            consent: PilotConsent(
                version: PilotStudyConfiguration.consentVersion,
                adultConfirmed: true,
                shareScope: .resultsOnly,
                acceptedAt: referenceDate.addingTimeInterval(-60)
            ),
            status: .active,
            ongoingConsent: ongoingConsent
        )
    }

    private func progressScan(date: Date) -> Scan {
        Scan(
            date: date,
            captures: Pose.required.map { pose in
                PoseCapture(
                    pose: pose,
                    imageFilename: "private-local-\(pose.rawValue).jpg",
                    avgBrightness: 0.5,
                    aspectRatio: 0.75,
                    captureSource: .camera,
                    assessment: .legacyUnverified(),
                    normalizedPixelSize: NormalizedPixelSize(width: 1_200, height: 1_600),
                    cameraMetadata: CaptureCameraMetadata(
                        position: .front,
                        lensType: "wide",
                        previewMirrored: true,
                        outputMirrored: false,
                        sourceOrientation: .up,
                        normalizedOrientation: .up
                    )
                )
            },
            consistencyScore: 0,
            lightingScore: 0,
            framingScore: 0,
            note: nil,
            context: nil,
            analysisAvailability: .comparable,
            captureCompleteness: .complete,
            scanRole: .canonical,
            lastModifiedAt: date
        )
    }

    private func progressAnalysis(id: UUID, analyzedAt: Date) -> ScanAnalysis {
        let region = RegionalComparison(
            region: .waist,
            status: .stable,
            normalizedDelta: 0,
            contributions: [PoseContribution(
                pose: .front,
                baselineValue: 0.5,
                currentValue: 0.5,
                normalizedDelta: 0,
                poseMatchScore: 0.99,
                status: .supported,
                reason: nil
            )],
            reason: nil
        )
        return ScanAnalysis(
            id: id,
            analysisVersion: AnalysisStore.currentAnalysisVersion,
            analyzedAt: analyzedAt,
            qualityResult: QualityGateResult(
                verdict: .pass,
                issues: [],
                blurScore: 0,
                brightnessScore: 0.5,
                coverageScore: 1,
                regionalCoverage: [:]
            ),
            extractedPoses: [],
            silhouetteProfiles: [],
            visualSignals: VisualSignalSet(
                deltas: [],
                fatLossSignals: nil,
                reliabilityTier: .earlyStage,
                regionalComparisons: [region]
            ),
            smoothedSignals: SmoothedSignalSet(
                smoothedDeltas: [:],
                smoothedTaperDelta: 0,
                smoothedProportionDelta: 0,
                reliabilityTier: .earlyStage,
                scanCount: 2
            ),
            confidence: ConfidenceScore(
                overall: .low,
                rawScore: 0,
                regionalCoverage: [:],
                poseMatchScore: 0,
                lightingConsistency: 0,
                measurementAgreement: 0,
                hasSufficientEvidence: true
            ),
            interpretedSignals: InterpretedSignals(
                scanCount: 2,
                weeksTracked: 1,
                reliabilityTier: .earlyStage,
                goal: .maintain,
                overallConfidence: .low,
                signals: [:],
                taperSignal: .neutral,
                proportionSignal: .neutral,
                measurementAlignment: [:],
                recompositionPatterns: [],
                scanQualityNotes: [],
                signalConflicts: [],
                contextNotes: []
            ),
            analysisAvailability: .comparable,
            poseFailures: [:],
            algorithmMetadata: AnalysisAlgorithmMetadata(
                analysisVersion: AnalysisStore.currentAnalysisVersion,
                bodyPoseRevision: 1,
                personSegmentationRevision: 1,
                operatingSystemVersion: "test-os",
                thresholdSetIdentifier: "engineering-v1"
            )
        )
    }
}

private final class PilotTransportSpy: PilotNetworkTransport, @unchecked Sendable {
    private(set) var lastRequest: URLRequest?

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [:]
        )!
        return (Data(), response)
    }
}

private final class PilotJSONTransportSpy: PilotNetworkTransport, @unchecked Sendable {
    private let responseBody: Data
    private let statusCode: Int
    private(set) var lastRequest: URLRequest?

    init(responseBody: String, statusCode: Int = 200) {
        self.responseBody = Data(responseBody.utf8)
        self.statusCode = statusCode
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: [:]
        )!
        return (responseBody, response)
    }
}
