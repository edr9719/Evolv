import Foundation
import XCTest
@testable import Evolv

final class PilotEnrollmentTests: XCTestCase {
    private let participantID = UUID(uuidString: "0ecc2686-1111-4111-8111-111111111111")!
    private let studyID = UUID(uuidString: "699b319d-727a-4778-adce-5b540a727576")!
    private let invite = "ABCDE12345ABCDE12345"

    func testHostedBuild18ResponseDecodesExplicitAcronymsCredentialsAndFractionalDates() throws {
        let response = try JSONDecoder.pilot.decode(
            PilotEnrollmentResponse.self,
            from: Data(hostedLegacyResponse.utf8)
        )

        XCTAssertEqual(response.participantID, participantID)
        XCTAssertEqual(response.studyID, studyID)
        XCTAssertEqual(response.studyName, "Evolv founder pilot")
        XCTAssertEqual(response.participantToken, "opaque-participant-token")
        XCTAssertEqual(response.deletionCode, "ABCDE-FGHJK-LMNPQ-RSTUV")
        XCTAssertEqual(
            response.pilotClosesAt.timeIntervalSince1970,
            1_794_240_000.123456,
            accuracy: 0.001
        )
        XCTAssertEqual(
            response.resultsDeleteAfter.timeIntervalSince1970,
            1_825_776_000.654321,
            accuracy: 0.001
        )
    }

    func testEnrollmentRequestUsesVerifiersAndReconstructsLocalCredentials() async throws {
        let transport = EnrollmentTransport(responseBody: hostedMetadataResponse)
        let client = makeClient(transport: transport)
        let attempt = fixedAttempt()

        let response = try await client.enroll(attempt: attempt)

        XCTAssertEqual(response.participantID, participantID)
        XCTAssertEqual(response.participantToken, attempt.participantToken)
        XCTAssertEqual(response.deletionCode, attempt.deletionCode)
        let request = try XCTUnwrap(transport.requests.first)
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String]
        )
        XCTAssertEqual(body["invite_code"], invite)
        XCTAssertEqual(body["enrollment_idempotency_key"], attempt.idempotencyKey.uuidString)
        XCTAssertEqual(body["participant_token_verifier"]?.count, 64)
        XCTAssertEqual(body["recovery_code_verifier"]?.count, 64)
        XCTAssertFalse(String(data: request.httpBody!, encoding: .utf8)!.contains(attempt.participantToken))
        XCTAssertFalse(String(data: request.httpBody!, encoding: .utf8)!.contains(attempt.deletionCode))
    }

    @MainActor
    func testSuccessfulClientFlowPersistsBothCredentialsLocalEnrollmentAndActiveState() async throws {
        let transport = EnrollmentTransport(responseBody: hostedMetadataResponse)
        let secrets = MemoryPilotSecrets()
        let store = MemoryEnrollmentStore()
        let coordinator = PilotSubmissionCoordinator(
            api: makeClient(transport: transport),
            secrets: secrets,
            enrollmentStore: store
        )

        try await coordinator.enroll(inviteCode: invite, consent: consent())

        let originalAttempt = try XCTUnwrap(secrets.lastSavedAttempt)
        XCTAssertEqual(secrets.participant, originalAttempt.participantToken)
        XCTAssertEqual(secrets.recovery, originalAttempt.deletionCode)
        XCTAssertEqual(try secrets.participantToken(), originalAttempt.participantToken)
        XCTAssertEqual(try secrets.deletionCode(), originalAttempt.deletionCode)
        XCTAssertNil(secrets.attempt)
        XCTAssertEqual(store.enrollment?.participantID, participantID)
        XCTAssertEqual(coordinator.enrollment, store.enrollment)
        XCTAssertEqual(coordinator.enrollment?.status, .active)
    }

    @MainActor
    func testInterruptedEnrollmentRetainsAndReusesExactAttempt() async throws {
        let transport = EnrollmentTransport(
            responseBody: hostedMetadataResponse,
            failuresBeforeSuccess: 1
        )
        let secrets = MemoryPilotSecrets()
        let store = MemoryEnrollmentStore()
        let coordinator = PilotSubmissionCoordinator(
            api: makeClient(transport: transport),
            secrets: secrets,
            enrollmentStore: store
        )

        do {
            try await coordinator.enroll(inviteCode: invite, consent: consent())
            XCTFail("The simulated lost response must be retryable")
        } catch {
            XCTAssertEqual(error as? PilotStudyError, .enrollmentRetryable)
        }
        let retained = try XCTUnwrap(secrets.attempt)
        XCTAssertNil(store.enrollment)

        try await coordinator.enroll(inviteCode: invite, consent: consent())

        XCTAssertEqual(transport.requests.count, 2)
        let bodies = try transport.requests.map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap($0.httpBody)) as? [String: String])
        }
        XCTAssertEqual(bodies[0]["enrollment_idempotency_key"], bodies[1]["enrollment_idempotency_key"])
        XCTAssertEqual(bodies[0]["participant_token_verifier"], bodies[1]["participant_token_verifier"])
        XCTAssertEqual(secrets.participant, retained.participantToken)
        XCTAssertEqual(secrets.recovery, retained.deletionCode)
        XCTAssertNil(secrets.attempt)
        XCTAssertEqual(coordinator.enrollment?.participantID, participantID)
    }

    func testInvitationValidationDecodesHostedMetadataWithoutConsumingLocally() async throws {
        let transport = EnrollmentTransport(responseBody: """
        {"status":"valid","study_name":"Evolv founder pilot","pilot_closes_at":"2026-11-09T12:17:57.225391+00:00"}
        """)
        let result = try await makeClient(transport: transport).validateInvitation(inviteCode: invite)

        XCTAssertEqual(result.status, .valid)
        XCTAssertEqual(result.studyName, "Evolv founder pilot")
        XCTAssertEqual(transport.requests.first?.url?.path, "/functions/v1/pilot-api/invites/validate")
        XCTAssertNil(transport.requests.first?.value(forHTTPHeaderField: "X-Evolv-Participant-Token"))
    }

    func testKnownInvitationAndNetworkFailuresMapToActionableErrors() async throws {
        let cases: [(Int, String, PilotStudyError)] = [
            (409, "invite_used", .inviteAlreadyUsed),
            (409, "study_closed", .pilotClosed),
            (409, "study_full", .pilotFull),
            (409, "invite_expired", .inviteExpired),
            (404, "invite_invalid", .invalidInvite),
            (429, "rate_limited", .rateLimited)
        ]
        for (status, code, expected) in cases {
            let transport = EnrollmentTransport(
                responseBody: #"{"code":"\#(code)","message":"safe"}"#,
                statusCode: status
            )
            do {
                _ = try await makeClient(transport: transport).validateInvitation(inviteCode: invite)
                XCTFail("Expected \(expected)")
            } catch {
                XCTAssertEqual(error as? PilotStudyError, expected)
            }
        }

        let offline = EnrollmentTransport(responseBody: "", transportError: URLError(.notConnectedToInternet))
        do {
            _ = try await makeClient(transport: offline).validateInvitation(inviteCode: invite)
            XCTFail("Offline validation must fail")
        } catch {
            XCTAssertEqual(error as? PilotStudyError, .offline)
        }
    }

    func testAuthenticatedSubmissionResponsesDecodeExplicitAcronymKeys() throws {
        let submissionID = UUID(uuidString: "50000000-0000-4000-8000-000000000019")!
        let initialization = try JSONDecoder.pilot.decode(
            PilotSubmissionInitialization.self,
            from: Data(
                #"{"submission_id":"\#(submissionID.uuidString)","uploads":[]}"#.utf8
            )
        )
        XCTAssertEqual(initialization.submissionID, submissionID)
        XCTAssertTrue(initialization.uploads.isEmpty)

        let receipt = try JSONDecoder.pilot.decode(
            PilotSubmissionReceipt.self,
            from: Data(
                #"{"submission_id":"\#(submissionID.uuidString)","receipt_code":"RECEIPT","photo_delete_at":null,"results_delete_at":"2027-08-20T12:17:57.225391+00:00"}"#.utf8
            )
        )
        XCTAssertEqual(receipt.submissionID, submissionID)
        XCTAssertEqual(receipt.receiptCode, "RECEIPT")
    }

    private func makeClient(transport: PilotNetworkTransport) -> PilotAPIClient {
        PilotAPIClient(
            transport: transport,
            baseURL: URL(string: "https://example.test/functions/v1/pilot-api")!,
            publishableKey: "public-test-key",
            networkAllowed: true
        )
    }

    private func fixedAttempt() -> PilotEnrollmentAttempt {
        PilotEnrollmentAttempt(
            normalizedInviteCode: invite,
            idempotencyKey: UUID(uuidString: "10000000-0000-4000-8000-000000000019")!,
            participantToken: "test-participant-token-with-strong-local-entropy",
            deletionCode: "ABCDE-FGHJK-LMNPQ-RSTUV"
        )
    }

    private func consent() -> PilotConsent {
        PilotConsent(
            version: PilotStudyConfiguration.consentVersion,
            adultConfirmed: true,
            shareScope: .resultsOnly,
            acceptedAt: Date(timeIntervalSince1970: 1_776_000_000)
        )
    }

    private var hostedLegacyResponse: String {
        """
        {"participant_id":"\(participantID.uuidString)","study_id":"\(studyID.uuidString)","study_name":"Evolv founder pilot","pilot_closes_at":"2026-11-09T16:00:00.123456+00:00","results_delete_after":"2027-11-09T16:00:00.654321+00:00","participant_token":"opaque-participant-token","deletion_code":"ABCDE-FGHJK-LMNPQ-RSTUV"}
        """
    }

    private var hostedMetadataResponse: String {
        """
        {"participant_id":"\(participantID.uuidString)","study_id":"\(studyID.uuidString)","study_name":"Evolv founder pilot","pilot_closes_at":"2026-11-09T12:17:57.225391+00:00","results_delete_after":"2027-08-20T12:17:57.225391+00:00"}
        """
    }
}

private final class EnrollmentTransport: PilotNetworkTransport, @unchecked Sendable {
    private let responseBody: Data
    private let statusCode: Int
    private var failuresBeforeSuccess: Int
    private let transportError: Error?
    private(set) var requests: [URLRequest] = []

    init(
        responseBody: String,
        statusCode: Int = 200,
        failuresBeforeSuccess: Int = 0,
        transportError: Error? = nil
    ) {
        self.responseBody = Data(responseBody.utf8)
        self.statusCode = statusCode
        self.failuresBeforeSuccess = failuresBeforeSuccess
        self.transportError = transportError
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if let transportError { throw transportError }
        if failuresBeforeSuccess > 0 {
            failuresBeforeSuccess -= 1
            throw URLError(.networkConnectionLost)
        }
        return (
            responseBody,
            HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
        )
    }
}

private final class MemoryPilotSecrets: PilotSecretStoring {
    var participant: String?
    var recovery: String?
    var attempt: PilotEnrollmentAttempt?
    var lastSavedAttempt: PilotEnrollmentAttempt?

    func participantToken() throws -> String? { participant }
    func deletionCode() throws -> String? { recovery }
    func save(participantToken: String, deletionCode: String) throws {
        participant = participantToken
        recovery = deletionCode
    }
    func enrollmentAttempt() throws -> PilotEnrollmentAttempt? { attempt }
    func saveEnrollmentAttempt(_ attempt: PilotEnrollmentAttempt) throws {
        self.attempt = attempt
        lastSavedAttempt = attempt
    }
    func deleteEnrollmentAttempt() throws { attempt = nil }
    func deleteParticipantToken() throws { participant = nil }
    func deleteAll() throws {
        participant = nil
        recovery = nil
        attempt = nil
    }
}

private final class MemoryEnrollmentStore: PilotEnrollmentPersisting {
    var enrollment: PilotLocalEnrollment?
    func loadEnrollment() -> PilotLocalEnrollment? { enrollment }
    func saveEnrollment(_ enrollment: PilotLocalEnrollment?) throws { self.enrollment = enrollment }
}
