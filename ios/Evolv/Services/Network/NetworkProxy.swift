import Foundation

/// Sends InterpretedSignals to the Supabase Edge Function proxy and parses GeneratedInsight.
/// Photos and raw measurements are NEVER sent — only the interpreted signal summary.
final class NetworkProxy {

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
        guard let url = endpointURL else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let anonKey = anonKey {
            request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
        }

        let payload = RequestPayload(
            userId: anonymousUserId,
            signals: signals
        )

        guard let body = try? JSONEncoder().encode(payload) else { return nil }
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

    private var anonymousUserId: String {
        let key = "evolv_anon_user_id"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }

    // MARK: - Request Payload

    private struct RequestPayload: Encodable {
        let userId: String
        let signals: InterpretedSignals
    }
}
