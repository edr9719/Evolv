import Foundation

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
    private struct EnrollmentRequest: Encodable { var inviteCode: String }
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

    func enroll(inviteCode: String) async throws -> PilotEnrollmentResponse {
        let normalized = inviteCode.uppercased().filter { $0.isLetter || $0.isNumber }
        guard normalized.count >= 16 else { throw PilotStudyError.invalidInvite }
        return try await post(path: "enroll", body: EnrollmentRequest(inviteCode: normalized), token: nil)
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
            token: participantToken
        )
    }

    func upload(ciphertext: Data, to authorization: PilotUploadAuthorization) async throws {
        var request = URLRequest(url: authorization.signedURL)
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
            token: participantToken
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
        token: String?
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
        let (data, response) = try await transport.send(request)
        guard (200...299).contains(response.statusCode) else {
            let decoder = JSONDecoder.pilot
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let error = try? decoder.decode(ErrorResponse.self, from: data)
            if path == "enroll" && (response.statusCode == 404 || response.statusCode == 409) {
                if error?.code == "study_full" { throw PilotStudyError.pilotFull }
                throw PilotStudyError.invalidInvite
            }
            throw PilotStudyError.serverRejected(error?.message ?? "The study service rejected this request.")
        }
        let decoder = JSONDecoder.pilot
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw PilotStudyError.unavailable
        }
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
