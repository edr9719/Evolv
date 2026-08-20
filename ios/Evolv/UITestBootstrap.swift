#if DEBUG
import Foundation

/// Deterministic, in-memory launch scenarios for EvolvUITests. Production and
/// Release builds do not compile this implementation, and no scenario writes
/// consent, photos, invitation codes, or participant credentials to storage.
@MainActor
enum EvolvUITestBootstrap {
    static func applyIfRequested(
        to app: AppState,
        pilot: PilotSubmissionCoordinator
    ) {
        guard let scenario = ProcessInfo.processInfo.environment["EVOLV_UI_TEST_SCENARIO"] else {
            return
        }

        app.hasCompletedOnboarding = true
        app.profile.hasSeenPostOnboardingPaywall = true
        app.scans = []
        app.validationSessions = []

        switch scenario {
        case "enrolled":
            pilot.configureForUITesting(enrollment: enrollment())
        case "completed-local":
            pilot.configureForUITesting(enrollment: nil)
            app.validationSessions = [completedLocalSession()]
        default:
            pilot.configureForUITesting(enrollment: nil)
        }
    }

    private static func enrollment() -> PilotLocalEnrollment {
        let now = Date()
        return PilotLocalEnrollment(
            participantID: UUID(uuidString: "00000000-0000-0000-0000-000000000018")!,
            studyID: UUID(uuidString: "00000000-0000-0000-0000-000000000117")!,
            studyName: "Evolv UI test pilot",
            enrolledAt: now,
            pilotClosesAt: now.addingTimeInterval(86_400 * 30),
            resultsDeleteAfter: now.addingTimeInterval(86_400 * 365),
            consent: PilotConsent(
                version: PilotStudyConfiguration.consentVersion,
                adultConfirmed: true,
                shareScope: .resultsOnly,
                acceptedAt: now
            ),
            status: .active
        )
    }

    private static func completedLocalSession() -> ValidationStudySession {
        let now = Date()
        let records = (1...ValidationStudySession.requiredSetCount).map { number in
            ValidationSetRecord(
                setNumber: number,
                scanID: UUID(),
                completedAt: now,
                conditions: ValidationSetConditions(
                    stayedTheSame: true,
                    deviations: [],
                    recordedAt: now
                ),
                comparison: ValidationSetComparison(
                    setNumber: number,
                    regionalComparisons: [],
                    failures: [:],
                    hasSufficientCoreEvidence: false,
                    diagnostics: []
                ),
                usedExistingCanonicalScan: false
            )
        }
        return ValidationStudySession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000017")!,
            enrollment: ValidationEnrollment(
                enrolledAt: now,
                programVersion: ValidationStudySession.protocolVersion,
                shareScope: .localOnly,
                consentVersion: nil
            ),
            startedAt: now,
            expiresAt: now.addingTimeInterval(ValidationStudySession.maximumDuration),
            status: .completed,
            lockedCameraPosition: .front,
            lockedLensType: "AVCaptureDeviceTypeBuiltInWideAngleCamera",
            sets: records,
            draftSetNumber: nil,
            draftCaptures: [],
            result: .limitedEvidence,
            statusReasons: [],
            completedAt: now,
            baselinePreflightRequired: nil,
            baselinePreflight: nil
        )
    }
}
#endif
