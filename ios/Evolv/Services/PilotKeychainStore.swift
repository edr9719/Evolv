import Foundation
import Security

protocol PilotSecretStoring {
    func participantToken() throws -> String?
    func deletionCode() throws -> String?
    func save(participantToken: String, deletionCode: String) throws
    func enrollmentAttempt() throws -> PilotEnrollmentAttempt?
    func saveEnrollmentAttempt(_ attempt: PilotEnrollmentAttempt) throws
    func deleteEnrollmentAttempt() throws
    func deleteParticipantToken() throws
    func deleteAll() throws
}

struct PilotKeychainStore: PilotSecretStoring {
    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                return "The iPhone Keychain returned error \(status)."
            }
        }
    }

    private enum Account {
        static let participantToken = "pilot-participant-token"
        static let deletionCode = "pilot-deletion-code"
        static let enrollmentAttempt = "pilot-enrollment-attempt-v2"
    }

    private let service = "com.app.evolv.pilot"

    func participantToken() throws -> String? {
        try read(account: Account.participantToken)
    }

    func deletionCode() throws -> String? {
        try read(account: Account.deletionCode)
    }

    func save(participantToken: String, deletionCode: String) throws {
        try upsert(participantToken, account: Account.participantToken)
        do {
            try upsert(deletionCode, account: Account.deletionCode)
        } catch {
            try? delete(account: Account.participantToken)
            throw error
        }
    }

    func enrollmentAttempt() throws -> PilotEnrollmentAttempt? {
        guard let value = try read(account: Account.enrollmentAttempt),
              let data = value.data(using: .utf8) else { return nil }
        do {
            return try JSONDecoder.pilot.decode(PilotEnrollmentAttempt.self, from: data)
        } catch {
            throw PilotStudyError.storageFailed
        }
    }

    func saveEnrollmentAttempt(_ attempt: PilotEnrollmentAttempt) throws {
        do {
            let data = try JSONEncoder.pilot.encode(attempt)
            guard let value = String(data: data, encoding: .utf8) else {
                throw PilotStudyError.storageFailed
            }
            try upsert(value, account: Account.enrollmentAttempt)
        } catch let error as PilotStudyError {
            throw error
        } catch {
            throw PilotStudyError.storageFailed
        }
    }

    func deleteEnrollmentAttempt() throws {
        try delete(account: Account.enrollmentAttempt)
    }

    func deleteParticipantToken() throws {
        try delete(account: Account.participantToken)
    }

    func deleteAll() throws {
        try delete(account: Account.participantToken)
        try delete(account: Account.deletionCode)
        try delete(account: Account.enrollmentAttempt)
    }

    private func read(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedStatus(status)
        }
        return value
    }

    private func upsert(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(updateStatus)
        }
        var insert = query
        insert.merge(update) { _, new in new }
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    private func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }
}
