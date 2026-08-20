import XCTest
@testable import Evolv

final class ValidationStudyTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_786_089_600)

    func testProgramIsLimitedToDebugOrTestFlight() {
        XCTAssertTrue(ValidationProgramAvailability.isEnabled(isDebugBuild: true, receiptFilename: nil))
        XCTAssertTrue(ValidationProgramAvailability.isEnabled(isDebugBuild: false, receiptFilename: "sandboxReceipt"))
        XCTAssertFalse(ValidationProgramAvailability.isEnabled(isDebugBuild: false, receiptFilename: "receipt"))
        XCTAssertFalse(ValidationProgramAvailability.isEnabled(isDebugBuild: false, receiptFilename: nil))
    }

    func testRecentCameraOnlyCanonicalCanBecomeSetOne() {
        let scan = scan(
            date: referenceDate.addingTimeInterval(-15 * 60),
            role: .canonical,
            captures: requiredCaptures(position: .front, lens: "wide")
        )

        XCTAssertTrue(ValidationStudyPolicy.eligibleCanonicalAnchor(scan, now: referenceDate))
        XCTAssertEqual(
            ValidationStudyPolicy.cameraConfiguration(for: scan.captures)?.position,
            .front
        )
    }

    func testAnchorRejectsLibraryMixedCameraOldAndAlreadyLinkedScans() {
        let valid = requiredCaptures(position: .rear, lens: "wide")
        var library = valid
        library[1].captureSource = .photoLibrary
        var mixedCamera = valid
        mixedCamera[2].cameraMetadata = camera(position: .front, lens: "wide")
        var linked = scan(date: referenceDate, role: .canonical, captures: valid)
        linked.validationSessionID = UUID()

        XCTAssertFalse(ValidationStudyPolicy.eligibleCanonicalAnchor(
            scan(date: referenceDate, role: .canonical, captures: library),
            now: referenceDate
        ))
        XCTAssertFalse(ValidationStudyPolicy.eligibleCanonicalAnchor(
            scan(date: referenceDate, role: .canonical, captures: mixedCamera),
            now: referenceDate
        ))
        XCTAssertFalse(ValidationStudyPolicy.eligibleCanonicalAnchor(
            scan(date: referenceDate.addingTimeInterval(-61 * 60), role: .canonical, captures: valid),
            now: referenceDate
        ))
        XCTAssertFalse(ValidationStudyPolicy.eligibleCanonicalAnchor(
            scan(date: referenceDate.addingTimeInterval(-31 * 60), role: .canonical, captures: valid),
            now: referenceDate
        ))
        XCTAssertFalse(ValidationStudyPolicy.eligibleCanonicalAnchor(linked, now: referenceDate))
        XCTAssertNil(ValidationStudyPolicy.cameraConfiguration(for: library))
    }

    func testStudySetAllowsExactlyThreeUniqueRequiredCameraCaptures() {
        let required = requiredCaptures(position: .front, lens: "wide")
        var mixedLens = required
        mixedLens[2].cameraMetadata = camera(position: .front, lens: "true-depth")

        XCTAssertTrue(ValidationStudyPolicy.isValidCompletedSet(
            required,
            position: .front,
            lockedLensType: "wide"
        ))
        XCTAssertFalse(ValidationStudyPolicy.isValidCompletedSet(
            required + [capture(.legs, position: .front, lens: "wide")],
            position: .front,
            lockedLensType: "wide"
        ))
        XCTAssertFalse(ValidationStudyPolicy.isValidCompletedSet(
            [required[0], required[0], required[2]],
            position: .front,
            lockedLensType: "wide"
        ))
        XCTAssertFalse(ValidationStudyPolicy.isValidCompletedSet(
            mixedLens,
            position: .front,
            lockedLensType: "wide"
        ))
    }

    func testValidationRolesNeverBecomeProgressScans() {
        let anchor = scan(date: referenceDate, role: .validationAnchor)
        let repeatScan = scan(date: referenceDate, role: .validationRepeat)

        XCTAssertFalse(anchor.isCanonicalProgressScan)
        XCTAssertFalse(repeatScan.isCanonicalProgressScan)
        XCTAssertTrue(anchor.isValidationOnlyScan)
        XCTAssertTrue(repeatScan.isValidationOnlyScan)
        XCTAssertEqual(
            ScanSchedulingPolicy.resolvedRole(
                requested: .validationRepeat,
                on: referenceDate,
                existingScans: [scan(date: referenceDate, role: .canonical)]
            ),
            .validationRepeat
        )
    }

    func testSessionExpiresAfterSixtyMinutesOrDateChangeWithoutDeletingRecords() {
        let session = studySession(setCount: 2)

        XCTAssertEqual(session.eligibility(at: referenceDate.addingTimeInterval(59 * 60)), .eligible)
        XCTAssertEqual(
            session.eligibility(at: referenceDate.addingTimeInterval(61 * 60)),
            .ineligible(.sessionExpired)
        )
        XCTAssertEqual(session.sets.count, 2)
        XCTAssertEqual(session.draftCaptures.count, 1)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(
            session.eligibility(at: referenceDate.addingTimeInterval(24 * 60 * 60), calendar: calendar),
            .ineligible(.dateChanged)
        )
    }

    func testDraftAndCompletedSetsRoundTripInProtectedLocalStore() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("validation-store-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("sessions.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let session = studySession(setCount: 2)

        try ValidationStudyStore.save([session], to: url)
        let decoded = try ValidationStudyStore.load(from: url)

        XCTAssertEqual(decoded, [session])
        XCTAssertEqual(decoded.first?.draftSetNumber, 3)
        XCTAssertEqual(decoded.first?.draftCaptures.count, 1)
        #if targetEnvironment(simulator)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        #else
        XCTAssertEqual(ValidationStudyStore.fileProtection(at: url), .complete)
        #endif
    }

    func testLocalPackageCannotUploadPhotosOrResults() {
        let preview = studySession(setCount: 5).packagePreview

        XCTAssertEqual(preview.shareScope, .localOnly)
        XCTAssertFalse(preview.canUpload)
        XCTAssertEqual(preview.photoCount, 15)
    }

    func testOfficialPilotRequiresActiveEnrollment() {
        XCTAssertFalse(ValidationStudyPolicy.canStartOfficialPilot(enrollment: nil))

        var enrollment = pilotEnrollment(status: .active)
        XCTAssertTrue(ValidationStudyPolicy.canStartOfficialPilot(enrollment: enrollment))

        enrollment.status = .withdrawn
        XCTAssertFalse(ValidationStudyPolicy.canStartOfficialPilot(enrollment: enrollment))
    }

    func testFounderFailurePatternBlocksSetTwoAndTargetsSideAndBack() {
        let captures = requiredCaptures(position: .front, lens: "wide")
        let preflight = ValidationBaselinePreflight(
            checkedAt: referenceDate,
            captureIDs: captures.map(\.id),
            poseEvidence: [
                ValidationPoseEvidence(
                    pose: .front,
                    poseExtracted: true,
                    silhouetteGenerated: true,
                    supportedRegions: [.shoulders, .chest, .waist, .arms]
                ),
                ValidationPoseEvidence(pose: .side, poseExtracted: false, silhouetteGenerated: false, supportedRegions: []),
                ValidationPoseEvidence(pose: .back, poseExtracted: true, silhouetteGenerated: false, supportedRegions: [])
            ],
            diagnostics: [
                diagnostic(set: 1, pose: .side, stage: .hipLandmarks, code: "hip_landmarks_unavailable"),
                diagnostic(set: 1, pose: .back, stage: .hipLandmarks, code: "hip_landmarks_unavailable")
            ]
        )
        var session = studySession(setCount: 0)
        session.baselinePreflightRequired = true
        session.baselinePreflight = preflight

        XCTAssertFalse(preflight.isViable)
        XCTAssertEqual(preflight.posesNeedingRetake, [.side, .back])
        XCTAssertFalse(ValidationStudyPolicy.hasRequiredBaselineEvidence(
            session: session,
            committingSetNumber: 1,
            captures: captures
        ))
        XCTAssertFalse(ValidationStudyPolicy.hasRequiredBaselineEvidence(
            session: session,
            committingSetNumber: 2,
            captures: captures
        ))
    }

    func testViableSetOneCanProceedButReplacingPhotoRequiresNewPreflight() {
        let captures = requiredCaptures(position: .front, lens: "wide")
        let viable = ValidationBaselinePreflight(
            checkedAt: referenceDate,
            captureIDs: captures.map(\.id),
            poseEvidence: Pose.required.map {
                ValidationPoseEvidence(
                    pose: $0,
                    poseExtracted: true,
                    silhouetteGenerated: true,
                    supportedRegions: [.shoulders, .chest, .waist, .arms]
                )
            },
            diagnostics: []
        )
        var session = studySession(setCount: 0)
        session.baselinePreflightRequired = true
        session.baselinePreflight = viable

        XCTAssertTrue(ValidationStudyPolicy.hasRequiredBaselineEvidence(
            session: session,
            committingSetNumber: 1,
            captures: captures
        ))
        XCTAssertTrue(ValidationStudyPolicy.hasRequiredBaselineEvidence(
            session: session,
            committingSetNumber: 2,
            captures: captures
        ))

        var replaced = captures
        replaced[1] = capture(.side, position: .front, lens: "wide")
        XCTAssertFalse(ValidationStudyPolicy.hasRequiredBaselineEvidence(
            session: session,
            committingSetNumber: 1,
            captures: replaced
        ))
    }

    func testBaselineFeatureRequirementsReuseComparisonContract() {
        var profiles = requiredProfiles(match: nil)
        let frontIndex = profiles.firstIndex { $0.pose == .front }!
        profiles[frontIndex].regionFeatures?.removeAll { $0.region == .chest }

        let deficits = VisualSignalEngine.baselineEvidenceDeficits(profiles: profiles)

        XCTAssertEqual(deficits[.front], Set([.chest]))
        XCTAssertNil(deficits[.side])
        XCTAssertNil(deficits[.back])
    }

    func testIdenticalSupportedFeaturesClassifyAsConsistent() {
        let baseline = requiredProfiles(match: nil)
        let current = requiredProfiles(match: 1)
        let comparisons = VisualSignalEngine.comparePair(
            baselineProfiles: baseline,
            currentProfiles: current
        )
        let result = ValidationSetComparison(
            setNumber: 2,
            regionalComparisons: comparisons,
            failures: [:],
            hasSufficientCoreEvidence: coreRegionsAreSupported(comparisons)
        )
        let all = Dictionary(uniqueKeysWithValues: (2...5).map { number in
            var copy = result
            copy.setNumber = number
            return (number, copy)
        })

        XCTAssertTrue(comparisons.filter { $0.region != .arms }.allSatisfy { $0.status == .stable })
        XCTAssertEqual(
            ValidationConsistencyEngine.classify(
                session: completedStudySession(),
                comparisonsBySet: all
            ),
            .consistent
        )
    }

    func testMissingEvidenceIsLimitedNotStable() {
        let unavailable = RegionalComparison(
            region: .waist,
            status: .unavailable,
            normalizedDelta: nil,
            contributions: [],
            reason: "required_pose_evidence_unavailable"
        )
        let results = Dictionary(uniqueKeysWithValues: (2...5).map { number in
            (number, ValidationSetComparison(
                setNumber: number,
                regionalComparisons: [unavailable],
                failures: [:],
                hasSufficientCoreEvidence: false
            ))
        })

        XCTAssertEqual(
            ValidationConsistencyEngine.classify(
                session: completedStudySession(),
                comparisonsBySet: results
            ),
            .limitedEvidence
        )
        XCTAssertNil(unavailable.normalizedDelta)
    }

    func testExpectedDetectorAbstentionIsLimitedRatherThanNeedsReview() {
        let unavailable = RegionalComparison(
            region: .waist,
            status: .unavailable,
            normalizedDelta: nil,
            contributions: [],
            reason: "required_pose_evidence_unavailable"
        )
        let issue = diagnostic(
            set: 1,
            pose: .side,
            stage: .hipLandmarks,
            code: "hip_landmarks_unavailable"
        )
        let results = Dictionary(uniqueKeysWithValues: (2...5).map { number in
            (number, ValidationSetComparison(
                setNumber: number,
                regionalComparisons: [unavailable],
                failures: ["set_1.side.hipLandmarks": "hip_landmarks_unavailable"],
                hasSufficientCoreEvidence: false,
                diagnostics: [issue]
            ))
        })

        XCTAssertEqual(
            ValidationConsistencyEngine.classify(
                session: completedStudySession(),
                comparisonsBySet: results
            ),
            .limitedEvidence
        )
    }

    func testTrueProcessingErrorStillNeedsReview() {
        let issue = ValidationPoseDiagnostic(
            setNumber: 2,
            pose: .front,
            stage: .photoLoading,
            kind: .systemError,
            code: "photo_load_failed",
            affectedRegions: []
        )
        let results = Dictionary(uniqueKeysWithValues: (2...5).map { number in
            (number, ValidationSetComparison(
                setNumber: number,
                regionalComparisons: [],
                failures: ["set_2.front.photoLoading": "photo_load_failed"],
                hasSufficientCoreEvidence: false,
                diagnostics: number == 2 ? [issue] : []
            ))
        })

        XCTAssertEqual(
            ValidationConsistencyEngine.classify(
                session: completedStudySession(),
                comparisonsBySet: results
            ),
            .needsReview
        )
    }

    func testUnexpectedChangeFailureOrRecordedDeviationNeedsReview() {
        let changed = RegionalComparison(
            region: .waist,
            status: .increase,
            normalizedDelta: 0.04,
            contributions: [],
            reason: nil
        )
        let changedResults = Dictionary(uniqueKeysWithValues: (2...5).map { number in
            (number, ValidationSetComparison(
                setNumber: number,
                regionalComparisons: [changed],
                failures: [:],
                hasSufficientCoreEvidence: true
            ))
        })
        XCTAssertEqual(
            ValidationConsistencyEngine.classify(
                session: completedStudySession(),
                comparisonsBySet: changedResults
            ),
            .needsReview
        )

        var failureResults = changedResults
        failureResults[2]?.regionalComparisons = []
        failureResults[2]?.failures = ["front": "pose_extraction_failed"]
        XCTAssertEqual(
            ValidationConsistencyEngine.classify(
                session: completedStudySession(),
                comparisonsBySet: failureResults
            ),
            .needsReview
        )

        var deviationSession = completedStudySession()
        deviationSession.sets[3].conditions = ValidationSetConditions(
            stayedTheSame: false,
            deviations: [.lighting],
            recordedAt: referenceDate
        )
        XCTAssertEqual(
            ValidationConsistencyEngine.classify(
                session: deviationSession,
                comparisonsBySet: [:]
            ),
            .needsReview
        )
    }

    func testLegacyScanDecodesWithoutValidationFields() throws {
        let source = scan(date: referenceDate, role: .canonical)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any]
        )
        object.removeValue(forKey: "validationSessionID")
        object.removeValue(forKey: "validationSetNumber")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(Scan.self, from: legacy)

        XCTAssertNil(decoded.validationSessionID)
        XCTAssertNil(decoded.validationSetNumber)
        XCTAssertEqual(decoded.resolvedRole, .canonical)
    }

    // MARK: - Fixtures

    private func completedStudySession() -> ValidationStudySession {
        var session = studySession(setCount: 5)
        session.draftSetNumber = nil
        session.draftCaptures = []
        return session
    }

    private func studySession(setCount: Int) -> ValidationStudySession {
        let records: [ValidationSetRecord] = setCount == 0 ? [] : (1...setCount).map { number in
            ValidationSetRecord(
                setNumber: number,
                scanID: UUID(),
                completedAt: referenceDate,
                conditions: ValidationSetConditions(
                    stayedTheSame: true,
                    deviations: [],
                    recordedAt: referenceDate
                ),
                comparison: nil,
                usedExistingCanonicalScan: number == 1
            )
        }
        return ValidationStudySession(
            enrollment: ValidationEnrollment(
                enrolledAt: referenceDate,
                programVersion: ValidationStudySession.protocolVersion,
                shareScope: .localOnly,
                consentVersion: nil
            ),
            startedAt: referenceDate,
            expiresAt: referenceDate.addingTimeInterval(ValidationStudySession.maximumDuration),
            status: setCount == 5 ? .evaluating : .active,
            lockedCameraPosition: .front,
            lockedLensType: "wide",
            sets: records,
            draftSetNumber: setCount < 5 ? setCount + 1 : nil,
            draftCaptures: setCount < 5 ? [capture(.front, position: .front, lens: "wide")] : [],
            result: nil,
            statusReasons: [],
            completedAt: nil
        )
    }

    private func scan(
        date: Date,
        role: ScanRole,
        captures: [PoseCapture] = []
    ) -> Scan {
        Scan(
            date: date,
            captures: captures,
            consistencyScore: 0,
            lightingScore: 0,
            framingScore: 0,
            note: nil,
            context: nil,
            analysisAvailability: role == .canonical ? .baselineOnly : .validationOnly,
            captureCompleteness: captures.isEmpty ? .incomplete : .complete,
            scanRole: role,
            lastModifiedAt: date
        )
    }

    private func requiredCaptures(position: CaptureCameraPosition, lens: String) -> [PoseCapture] {
        Pose.required.map { capture($0, position: position, lens: lens) }
    }

    private func capture(
        _ pose: Pose,
        position: CaptureCameraPosition,
        lens: String
    ) -> PoseCapture {
        PoseCapture(
            pose: pose,
            imageFilename: "\(pose.rawValue)-\(UUID().uuidString).jpg",
            avgBrightness: 0.5,
            aspectRatio: 0.75,
            captureSource: .camera,
            assessment: .legacyUnverified(),
            normalizedPixelSize: NormalizedPixelSize(width: 1_200, height: 1_600),
            cameraMetadata: camera(position: position, lens: lens)
        )
    }

    private func camera(position: CaptureCameraPosition, lens: String) -> CaptureCameraMetadata {
        CaptureCameraMetadata(
            position: position,
            lensType: lens,
            previewMirrored: position == .front,
            outputMirrored: false,
            sourceOrientation: .up,
            normalizedOrientation: .up
        )
    }

    private func diagnostic(
        set: Int,
        pose: Pose,
        stage: ValidationEvidenceStage,
        code: String
    ) -> ValidationPoseDiagnostic {
        ValidationPoseDiagnostic(
            setNumber: set,
            pose: pose,
            stage: stage,
            kind: .evidenceUnavailable,
            code: code,
            affectedRegions: []
        )
    }

    private func pilotEnrollment(status: PilotEnrollmentStatus) -> PilotLocalEnrollment {
        PilotLocalEnrollment(
            participantID: UUID(),
            studyID: UUID(),
            studyName: "UI test pilot",
            enrolledAt: referenceDate,
            pilotClosesAt: referenceDate.addingTimeInterval(86_400),
            resultsDeleteAfter: referenceDate.addingTimeInterval(86_400 * 365),
            consent: PilotConsent(
                version: PilotStudyConfiguration.consentVersion,
                adultConfirmed: true,
                shareScope: .resultsOnly,
                acceptedAt: referenceDate
            ),
            status: status
        )
    }

    private func requiredProfiles(match: Float?) -> [SilhouetteProfile] {
        Pose.required.map { pose in
            let allowed: [BodyRegion]
            switch pose {
            case .front: allowed = [.shoulders, .chest, .waist, .arms]
            case .side: allowed = [.chest, .waist, .arms]
            case .back: allowed = [.shoulders, .waist, .arms]
            default: allowed = []
            }
            let values: [BodyRegion: Float] = [
                .shoulders: 0.50,
                .chest: 0.42,
                .waist: 0.30,
                .arms: 0.12
            ]
            let features = allowed.map { region in
                PoseRegionFeature(
                    pose: pose,
                    region: region,
                    normalizedValue: values[region]!,
                    source: region == .arms ? .limbCrossSection : .torsoCrossSection,
                    evidenceReason: nil
                )
            }
            return SilhouetteProfile(
                scanId: UUID(),
                pose: pose,
                widthAtY: [],
                shoulderWidthRatio: values[.shoulders]!,
                chestWidthRatio: values[.chest]!,
                waistWidthRatio: values[.waist]!,
                armMidWidthRatio: values[.arms]!,
                thighMidWidthRatio: 0,
                taperIndex: 0,
                chestToWaistRatio: 1,
                shoulderToWaistRatio: 1,
                hipWidthRatio: nil,
                lowerTorsoWidthRatio: values[.waist]!,
                supportedRegions: allowed,
                regionFeatures: features,
                torsoReferencePixels: 200,
                poseMatchScore: match
            )
        }
    }

    private func coreRegionsAreSupported(_ comparisons: [RegionalComparison]) -> Bool {
        let supported = Set(comparisons.filter { $0.status != .unavailable }.map(\.region))
        return Set([BodyRegion.shoulders, .chest, .waist]).isSubset(of: supported)
    }
}
