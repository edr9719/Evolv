import Foundation

enum PilotStudyStore {
    private struct Archive: Codable {
        var schemaVersion: Int
        var enrollment: PilotLocalEnrollment?
        var submissions: [PilotSubmissionRecord]
    }

    private static let schemaVersion = 1

    static var rootURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Evolv", isDirectory: true)
            .appendingPathComponent("pilot-sharing", isDirectory: true)
    }

    static var archiveURL: URL { rootURL.appendingPathComponent("pilot-state.json") }

    static func loadEnrollment() -> PilotLocalEnrollment? {
        loadArchive().enrollment
    }

    static func loadSubmissions() -> [PilotSubmissionRecord] {
        loadArchive().submissions
    }

    static func saveEnrollment(_ enrollment: PilotLocalEnrollment?) throws {
        var archive = loadArchive()
        archive.enrollment = enrollment
        try save(archive)
    }

    static func saveSubmission(_ submission: PilotSubmissionRecord) throws {
        var archive = loadArchive()
        if let index = archive.submissions.firstIndex(where: { $0.id == submission.id }) {
            archive.submissions[index] = submission
        } else {
            archive.submissions.append(submission)
        }
        try save(archive)
    }

    static func submission(for sessionID: UUID) -> PilotSubmissionRecord? {
        loadArchive().submissions.last { $0.localSessionID == sessionID }
    }

    static func ciphertextURL(submissionID: UUID, objectID: UUID) throws -> URL {
        let directory = rootURL
            .appendingPathComponent("queue", isDirectory: true)
            .appendingPathComponent(submissionID.uuidString.lowercased(), isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            return directory.appendingPathComponent("\(objectID.uuidString.lowercased()).bin")
        } catch {
            throw PilotStudyError.storageFailed
        }
    }

    static func writeCiphertext(_ data: Data, submissionID: UUID, objectID: UUID) throws -> String {
        let url = try ciphertextURL(submissionID: submissionID, objectID: objectID)
        guard data.count <= PilotStudyConfiguration.maximumCiphertextBytes else {
            throw PilotStudyError.payloadRejected
        }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path
            )
            return url.path.replacingOccurrences(of: rootURL.path + "/", with: "")
        } catch {
            throw PilotStudyError.storageFailed
        }
    }

    static func readCiphertext(relativePath: String) throws -> Data {
        let root = rootURL.standardizedFileURL
        let url = root.appendingPathComponent(relativePath).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else { throw PilotStudyError.storageFailed }
        return try Data(contentsOf: url)
    }

    static func removeCiphertexts(for submissionID: UUID) {
        let url = rootURL
            .appendingPathComponent("queue", isDirectory: true)
            .appendingPathComponent(submissionID.uuidString.lowercased(), isDirectory: true)
        try? FileManager.default.removeItem(at: url)
    }

    static func deleteAllLocalSharingData() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    private static func loadArchive() -> Archive {
        guard let data = try? Data(contentsOf: archiveURL),
              let archive = try? JSONDecoder.pilot.decode(Archive.self, from: data),
              archive.schemaVersion == schemaVersion else {
            return Archive(schemaVersion: schemaVersion, enrollment: nil, submissions: [])
        }
        return archive
    }

    private static func save(_ archive: Archive) throws {
        do {
            try FileManager.default.createDirectory(
                at: rootURL,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            let data = try JSONEncoder.pilot.encode(archive)
            try data.write(to: archiveURL, options: [.atomic, .completeFileProtection])
        } catch {
            throw PilotStudyError.storageFailed
        }
    }
}

extension JSONEncoder {
    static var pilot: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var pilot: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = PilotISO8601DateParser.fractional.date(from: value)
                ?? PilotISO8601DateParser.standard.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO 8601 date."
            )
        }
        return decoder
    }
}

private enum PilotISO8601DateParser {
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
