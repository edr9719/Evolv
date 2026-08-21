import CryptoKit
import Foundation
import Security

protocol PilotNetworkTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct PilotURLSessionTransport: PilotNetworkTransport {
    private let session: URLSession

    init(session: URLSession = PilotURLSessionTransport.makeSession()) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PilotStudyError.unavailable }
        return (data, http)
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = true
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }
}

struct PilotAPIClient {
    private struct ErrorResponse: Decodable { var code: String?; var message: String? }
    private struct InvitationRequest: Encodable { var inviteCode: String }
    private struct EnrollmentRequest: Encodable {
        var inviteCode: String
        var enrollmentIdempotencyKey: UUID
        var participantTokenVerifier: String
        var recoveryCodeVerifier: String
    }
    private struct InitializationRequest: Encodable {
        var clientSubmissionID: UUID
        var idempotencyKey: UUID
        var consent: PilotConsent
        var results: PilotStructuredPayload
        var wrappedKey: PilotWrappedKeyEnvelope?
        var objects: [ObjectRequest]
    }
    private struct ObjectRequest: Encodable {
        var objectID: UUID
        var setNumber: Int
        var pose: String
        var sha256: String
        var byteCount: Int
    }
    private struct CompletionRequest: Encodable {
        var submissionID: UUID
        var idempotencyKey: UUID
    }
    private struct CodeRequest: Encodable { var deletionCode: String }
    private struct StatusResponse: Decodable { var status: String }
    private struct DeleteResponse: Decodable { var deleted: Bool }

    private let transport: PilotNetworkTransport
    private let baseURL: URL?
    private let publishableKey: String?
    private let networkAllowed: Bool

    init(
        transport: PilotNetworkTransport = PilotURLSessionTransport(),
        baseURL: URL? = PilotAPIClient.configuredBaseURL,
        publishableKey: String? = PilotAPIClient.configuredPublishableKey,
        networkAllowed: Bool = ProcessInfo.processInfo.environment["EVOLV_ALLOW_NETWORK"] != "0"
    ) {
        self.transport = transport
        self.baseURL = baseURL
        self.publishableKey = publishableKey
        self.networkAllowed = networkAllowed
    }

    func validateInvitation(inviteCode: String) async throws -> PilotInvitationValidation {
        let normalized = Self.normalizeInviteCode(inviteCode)
        guard normalized.count >= 16 else { throw PilotStudyError.invalidInvite }
        return try await post(
            path: "invites/validate",
            body: InvitationRequest(inviteCode: normalized),
            token: nil,
            explicitSnakeCaseResponse: true
        )
    }

    func enroll(attempt: PilotEnrollmentAttempt) async throws -> PilotEnrollmentResponse {
        let normalized = Self.normalizeInviteCode(attempt.normalizedInviteCode)
        guard normalized.count >= 16, normalized == attempt.normalizedInviteCode else {
            throw PilotStudyError.invalidInvite
        }
        let metadata: PilotEnrollmentMetadataResponse = try await post(
            path: "enroll",
            body: EnrollmentRequest(
                inviteCode: normalized,
                enrollmentIdempotencyKey: attempt.idempotencyKey,
                participantTokenVerifier: Self.sha256Hex(attempt.participantToken),
                recoveryCodeVerifier: Self.sha256Hex(Self.normalizeInviteCode(attempt.deletionCode))
            ),
            token: nil,
            explicitSnakeCaseResponse: true
        )
        return PilotEnrollmentResponse(
            participantID: metadata.participantID,
            studyID: metadata.studyID,
            studyName: metadata.studyName,
            pilotClosesAt: metadata.pilotClosesAt,
            resultsDeleteAfter: metadata.resultsDeleteAfter,
            participantToken: attempt.participantToken,
            deletionCode: attempt.deletionCode
        )
    }

    static func makeEnrollmentAttempt(inviteCode: String) throws -> PilotEnrollmentAttempt {
        let normalized = normalizeInviteCode(inviteCode)
        guard normalized.count >= 16 else { throw PilotStudyError.invalidInvite }
        return PilotEnrollmentAttempt(
            normalizedInviteCode: normalized,
            idempotencyKey: UUID(),
            participantToken: try secureToken(byteCount: 32),
            deletionCode: try secureRecoveryCode(characterCount: 20)
        )
    }

    func initialize(
        record: PilotSubmissionRecord,
        participantToken: String
    ) async throws -> PilotSubmissionInitialization {
        let objects = record.encryptedObjects.map {
            ObjectRequest(
                objectID: $0.id,
                setNumber: $0.setNumber,
                pose: $0.pose.rawValue,
                sha256: $0.ciphertextSHA256,
                byteCount: $0.ciphertextByteCount
            )
        }
        return try await post(
            path: "submissions/init",
            body: InitializationRequest(
                clientSubmissionID: record.id,
                idempotencyKey: record.idempotencyKey,
                consent: record.consent,
                results: record.structuredPayload,
                wrappedKey: record.wrappedKey,
                objects: objects
            ),
            token: participantToken,
            explicitSnakeCaseResponse: true
        )
    }

    func upload(ciphertext: Data, to authorization: PilotUploadAuthorization) async throws {
        guard !authorization.alreadyUploaded, let signedURL = authorization.signedURL else {
            throw PilotStudyError.payloadRejected
        }
        var request = URLRequest(url: signedURL)
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("false", forHTTPHeaderField: "x-upsert")
        request.httpBody = ciphertext
        let (_, response) = try await transport.send(request)
        guard (200...299).contains(response.statusCode) || response.statusCode == 409 else {
            throw PilotStudyError.uploadFailed
        }
    }

    func complete(
        submissionID: UUID,
        idempotencyKey: UUID,
        participantToken: String
    ) async throws -> PilotSubmissionReceipt {
        try await post(
            path: "submissions/complete",
            body: CompletionRequest(submissionID: submissionID, idempotencyKey: idempotencyKey),
            token: participantToken,
            explicitSnakeCaseResponse: true
        )
    }

    func cancel(submissionID: UUID, participantToken: String) async throws {
        let response: DeleteResponse = try await post(
            path: "submissions/cancel",
            body: SubmissionRequest(submissionID: submissionID),
            token: participantToken
        )
        guard response.deleted else { throw PilotStudyError.unavailable }
    }

    func status(participantToken: String) async throws -> String {
        let response: StatusResponse = try await post(
            path: "status",
            body: EmptyRequest(),
            token: participantToken
        )
        return response.status
    }

    func withdraw(participantToken: String) async throws {
        let response: DeleteResponse = try await post(
            path: "withdraw",
            body: EmptyRequest(),
            token: participantToken
        )
        guard response.deleted else { throw PilotStudyError.unavailable }
    }

    func delete(deletionCode: String) async throws {
        let normalized = deletionCode.uppercased().filter { $0.isLetter || $0.isNumber }
        let response: DeleteResponse = try await post(
            path: "delete",
            body: CodeRequest(deletionCode: normalized),
            token: nil
        )
        guard response.deleted else { throw PilotStudyError.unavailable }
    }

    private struct EmptyRequest: Encodable {}
    private struct SubmissionRequest: Encodable { var submissionID: UUID }

    private func post<Request: Encodable, Response: Decodable>(
        path: String,
        body: Request,
        token: String?,
        explicitSnakeCaseResponse: Bool = false
    ) async throws -> Response {
        guard networkAllowed,
              let baseURL,
              let publishableKey,
              !publishableKey.isEmpty else {
            throw PilotStudyError.unavailable
        }
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(publishableKey)", forHTTPHeaderField: "Authorization")
        if let token { request.setValue(token, forHTTPHeaderField: "X-Evolv-Participant-Token") }
        let encoder = JSONEncoder.pilot
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as PilotStudyError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                 .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff:
                throw path == "enroll" ? PilotStudyError.enrollmentRetryable : PilotStudyError.offline
            case .timedOut:
                throw path == "enroll" ? PilotStudyError.enrollmentRetryable : PilotStudyError.offline
            default:
                throw path == "enroll" ? PilotStudyError.enrollmentRetryable : PilotStudyError.unavailable
            }
        } catch {
            throw path == "enroll" ? PilotStudyError.enrollmentRetryable : PilotStudyError.unavailable
        }
        guard (200...299).contains(response.statusCode) else {
            let decoder = JSONDecoder.pilot
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let error = try? decoder.decode(ErrorResponse.self, from: data)
            if path == "enroll" || path == "invites/validate" {
                switch error?.code {
                case "invite_used": throw PilotStudyError.inviteAlreadyUsed
                case "invite_expired": throw PilotStudyError.inviteExpired
                case "study_closed": throw PilotStudyError.pilotClosed
                case "study_full": throw PilotStudyError.pilotFull
                case "rate_limited": throw PilotStudyError.rateLimited
                case "invite_invalid", "invite_unavailable": throw PilotStudyError.invalidInvite
                case "enrollment_idempotency_conflict":
                    throw PilotStudyError.serverRejected("This saved enrollment attempt no longer matches the invitation. Contact the pilot organizer.")
                default:
                    if response.statusCode == 429 { throw PilotStudyError.rateLimited }
                    if response.statusCode == 404 || response.statusCode == 409 {
                        throw PilotStudyError.invalidInvite
                    }
                }
            }
            let code = error?.code ?? "service_rejected"
            throw PilotStudyError.serviceRejected(
                code: code,
                message: error?.message ?? "The study service rejected this request."
            )
        }
        let decoder = JSONDecoder.pilot
        if !explicitSnakeCaseResponse {
            decoder.keyDecodingStrategy = .convertFromSnakeCase
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw path == "enroll" ? PilotStudyError.responseInvalid : PilotStudyError.unavailable
        }
    }

    static func normalizeInviteCode(_ value: String) -> String {
        value.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func secureToken(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw PilotStudyError.storageFailed
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func secureRecoveryCode(characterCount: Int) throws -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var characters: [Character] = []
        while characters.count < characterCount {
            var byte: UInt8 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, 1, &byte) == errSecSuccess else {
                throw PilotStudyError.storageFailed
            }
            // 224 is the largest multiple of the 32-character alphabet below 256.
            guard byte < 224 else { continue }
            characters.append(alphabet[Int(byte) % alphabet.count])
        }
        return stride(from: 0, to: characters.count, by: 5)
            .map { String(characters[$0..<min($0 + 5, characters.count)]) }
            .joined(separator: "-")
    }

    private static var configuredBaseURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let base = URL(string: value) else { return nil }
        return base.appendingPathComponent("functions/v1/pilot-api")
    }

    private static var configuredPublishableKey: String? {
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
    }
}
