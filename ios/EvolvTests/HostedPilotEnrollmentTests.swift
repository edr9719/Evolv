import Foundation
import XCTest
@testable import Evolv

final class HostedPilotEnrollmentTests: XCTestCase {
    @MainActor
    func testDisposableHostedEnrollmentThroughProductionClient() async throws {
        guard let invite = hostedValue(
                  environmentKey: "EVOLV_HOSTED_ENROLLMENT_INVITE",
                  infoKey: "EVOLV_HOSTED_ENROLLMENT_INVITE"
              ),
              let closedInvite = hostedValue(
                  environmentKey: "EVOLV_HOSTED_CLOSED_INVITE",
                  infoKey: "EVOLV_HOSTED_CLOSED_INVITE"
              ),
              let supabaseURLString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let supabaseURL = URL(string: supabaseURLString),
              let publishableKey = (
                  Bundle.main.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String
                      ?? Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
              ),
              !publishableKey.isEmpty else {
            throw XCTSkip("Disposable hosted enrollment credentials were not supplied by the mandatory runner.")
        }
        let baseURL = supabaseURL.appendingPathComponent("functions/v1/pilot-api")

        let realTransport = PilotURLSessionTransport()
        let droppingTransport = DropFirstEnrollmentResponseTransport(underlying: realTransport)
        let client = PilotAPIClient(
            transport: droppingTransport,
            baseURL: baseURL,
            publishableKey: publishableKey,
            networkAllowed: true
        )
        let secrets = HostedMemorySecrets()
        let enrollmentStore = HostedMemoryEnrollmentStore()
        let coordinator = PilotSubmissionCoordinator(
            api: client,
            secrets: secrets,
            enrollmentStore: enrollmentStore
        )

        let validation = try await client.validateInvitation(inviteCode: invite)
        XCTAssertEqual(validation.status, .valid)
        XCTAssertNil(enrollmentStore.enrollment)

        let consent = PilotConsent(
            version: PilotStudyConfiguration.consentVersion,
            adultConfirmed: true,
            shareScope: .resultsOnly,
            acceptedAt: Date()
        )
        do {
            try await coordinator.enroll(inviteCode: invite, consent: consent)
            XCTFail("The runner must simulate a response lost after the hosted transaction commits.")
        } catch {
            XCTAssertEqual(error as? PilotStudyError, .enrollmentRetryable)
        }
        let retainedAttempt = try XCTUnwrap(secrets.attempt)
        XCTAssertNil(enrollmentStore.enrollment)

        try await coordinator.enroll(inviteCode: invite, consent: consent)
        let enrolled = try XCTUnwrap(coordinator.enrollment)
        XCTAssertEqual(enrollmentStore.enrollment, enrolled)
        XCTAssertEqual(enrolled.status, .active)
        XCTAssertEqual(try secrets.participantToken(), retainedAttempt.participantToken)
        XCTAssertEqual(try secrets.deletionCode(), retainedAttempt.deletionCode)
        XCTAssertNil(secrets.attempt)

        let replay = try await client.enroll(attempt: retainedAttempt)
        XCTAssertEqual(replay.participantID, enrolled.participantID)
        XCTAssertEqual(replay.studyID, enrolled.studyID)

        do {
            _ = try await client.enroll(
                attempt: PilotAPIClient.makeEnrollmentAttempt(inviteCode: invite)
            )
            XCTFail("A consumed invitation must reject a distinct operation.")
        } catch {
            XCTAssertEqual(error as? PilotStudyError, .inviteAlreadyUsed)
        }
        do {
            _ = try await client.validateInvitation(inviteCode: invite)
            XCTFail("Validation must distinguish a used invitation.")
        } catch {
            XCTAssertEqual(error as? PilotStudyError, .inviteAlreadyUsed)
        }
        do {
            _ = try await client.validateInvitation(inviteCode: "NOT-A-REAL-EVOLV-INVITE-0000")
            XCTFail("An unknown invitation must be invalid.")
        } catch {
            XCTAssertEqual(error as? PilotStudyError, .invalidInvite)
        }
        do {
            _ = try await client.validateInvitation(inviteCode: closedInvite)
            XCTFail("A closed study must be reported separately.")
        } catch {
            XCTAssertEqual(error as? PilotStudyError, .pilotClosed)
        }

        let record = resultsOnlyRecord(consent: consent)
        let initialized = try await client.initialize(
            record: record,
            participantToken: retainedAttempt.participantToken
        )
        XCTAssertTrue(initialized.uploads.isEmpty)
        XCTAssertFalse(initialized.submissionID.uuidString.isEmpty)
        let remoteStatus = try await client.status(
            participantToken: retainedAttempt.participantToken
        )
        XCTAssertEqual(remoteStatus, "active")

        // The disposable participant and its submission are removed through
        // the same recovery credential path available to a tester.
        try await client.delete(deletionCode: retainedAttempt.deletionCode)
    }

    private func nonPlaceholder(_ value: String?) -> String? {
        guard let value, !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }

    private func hostedValue(environmentKey: String, infoKey: String) -> String? {
        nonPlaceholder(ProcessInfo.processInfo.environment[environmentKey])
            ?? nonPlaceholder(Bundle.main.object(forInfoDictionaryKey: infoKey) as? String)
    }

    private func resultsOnlyRecord(consent: PilotConsent) -> PilotSubmissionRecord {
        let now = Date()
        let results = PilotResultsPayload(
            schemaVersion: PilotStudyConfiguration.payloadSchemaVersion,
            localSessionID: UUID(),
            sessionResult: "consistent",
            startedAt: now,
            completedAt: now,
            appBuild: "hosted-enrollment-e2e",
            analysisVersion: PilotStudyConfiguration.analysisVersion,
            thresholdSetIdentifier: "engineering-v1",
            deviceModel: "hosted-test-runner",
            operatingSystemVersion: "hosted-test-runner",
            cameraPosition: "front",
            lensType: "wide",
            sets: []
        )
        return PilotSubmissionRecord(
            id: UUID(),
            localSessionID: results.localSessionID,
            remoteSubmissionID: nil,
            idempotencyKey: UUID(),
            status: .queued,
            consent: consent,
            selectedPhotos: [],
            encryptedObjects: [],
            wrappedKey: nil,
            structuredPayload: .consistency(results),
            createdAt: now,
            updatedAt: now,
            receiptCode: nil,
            failureReasonCode: nil
        )
    }
}

private final class DropFirstEnrollmentResponseTransport: PilotNetworkTransport, @unchecked Sendable {
    private let underlying: PilotNetworkTransport
    private var didDropEnrollmentResponse = false

    init(underlying: PilotNetworkTransport) {
        self.underlying = underlying
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let result = try await underlying.send(request)
        if request.url?.path.hasSuffix("/enroll") == true, !didDropEnrollmentResponse {
            didDropEnrollmentResponse = true
            throw URLError(.networkConnectionLost)
        }
        return result
    }
}

private final class HostedMemorySecrets: PilotSecretStoring {
    private var participant: String?
    private var recovery: String?
    var attempt: PilotEnrollmentAttempt?

    func participantToken() throws -> String? { participant }
    func deletionCode() throws -> String? { recovery }
    func save(participantToken: String, deletionCode: String) throws {
        participant = participantToken
        recovery = deletionCode
    }
    func enrollmentAttempt() throws -> PilotEnrollmentAttempt? { attempt }
    func saveEnrollmentAttempt(_ attempt: PilotEnrollmentAttempt) throws { self.attempt = attempt }
    func deleteEnrollmentAttempt() throws { attempt = nil }
    func deleteParticipantToken() throws { participant = nil }
    func deleteAll() throws {
        participant = nil
        recovery = nil
        attempt = nil
    }
}

private final class HostedMemoryEnrollmentStore: PilotEnrollmentPersisting {
    var enrollment: PilotLocalEnrollment?
    func loadEnrollment() -> PilotLocalEnrollment? { enrollment }
    func saveEnrollment(_ enrollment: PilotLocalEnrollment?) throws { self.enrollment = enrollment }
}
