import Foundation

/// Sends InterpretedSignals to the Supabase Edge Function proxy and parses GeneratedInsight.
/// Photos and raw measurements are NEVER sent — only the interpreted signal summary.
protocol InsightRequesting {
    func requestInsight(signals: InterpretedSignals) async -> GeneratedInsight?
}

final class NetworkProxy: InsightRequesting {

    static let shared = NetworkProxy()
    private init() {}

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    // MARK: - Public API

    func requestInsight(signals: InterpretedSignals) async -> GeneratedInsight? {
        guard ProcessInfo.processInfo.environment["EVOLV_ALLOW_NETWORK"] != "0" else {
            return nil
        }
        guard let url = endpointURL else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let anonKey = anonKey {
            request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
        }

        guard let body = try? Self.encodedRequestBody(signals: signals) else { return nil }
        request.httpBody = body

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            return try? JSONDecoder().decode(GeneratedInsight.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Config

    private var endpointURL: URL? {
        guard let base = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              !base.isEmpty else { return nil }
        let clean = base.hasSuffix("/") ? String(base.dropLast()) : base
        return URL(string: "\(clean)/functions/v1/generate-insight")
    }

    private var anonKey: String? {
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
    }

    // MARK: - Request Payload

    private struct RequestPayload: Encodable {
        let signals: InterpretedSignals
    }

    /// Internal so the privacy boundary can be regression-tested without
    /// making a network request.
    static func encodedRequestBody(signals: InterpretedSignals) throws -> Data {
        try JSONEncoder().encode(RequestPayload(signals: signals))
    }
}
