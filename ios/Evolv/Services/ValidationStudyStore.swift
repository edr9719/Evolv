import Foundation

enum ValidationStudyStore {
    enum StoreError: LocalizedError {
        case couldNotEncode
        case couldNotWrite
        case invalidData

        var errorDescription: String? {
            switch self {
            case .couldNotEncode: return "Evolv couldn't prepare the consistency-test session."
            case .couldNotWrite: return "Evolv couldn't save the consistency-test session on this iPhone."
            case .invalidData: return "The saved consistency-test session could not be read."
            }
        }
    }

    private struct Archive: Codable {
        var schemaVersion: Int
        var sessions: [ValidationStudySession]
    }

    private static let schemaVersion = 1

    static var liveURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support
            .appendingPathComponent("Evolv", isDirectory: true)
            .appendingPathComponent("validation-sessions.json")
    }

    static func load(from url: URL = liveURL) throws -> [ValidationStudySession] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            let archive = try JSONDecoder().decode(Archive.self, from: data)
            guard archive.schemaVersion == schemaVersion else {
                throw StoreError.invalidData
            }
            return archive.sessions
        } catch {
            throw StoreError.invalidData
        }
    }

    static func save(
        _ sessions: [ValidationStudySession],
        to url: URL = liveURL
    ) throws {
        let archive = Archive(schemaVersion: schemaVersion, sessions: sessions)
        guard let data = try? JSONEncoder().encode(archive) else {
            throw StoreError.couldNotEncode
        }
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path
            )
        } catch {
            throw StoreError.couldNotWrite
        }
    }

    static func deleteAll(at url: URL = liveURL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func protectExistingFile(at url: URL = liveURL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
    }

    static func fileProtection(at url: URL = liveURL) -> FileProtectionType? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return attributes[.protectionKey] as? FileProtectionType
    }
}
