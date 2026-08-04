import Foundation

/// Persists ScanAnalysis objects to disk as JSON in Documents/analysis/{scanId}.json.
/// Analysis data is local-only; photos are never sent to any network.
enum AnalysisStore {

    static let currentAnalysisVersion = 1

    // MARK: - Directory

    private static var analysisDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("analysis", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(for scanId: UUID) -> URL {
        analysisDirectory.appendingPathComponent("\(scanId.uuidString).json")
    }

    // MARK: - Save

    /// Persists a ScanAnalysis to disk. Overwrites any existing file for the same scanId.
    static func save(_ analysis: ScanAnalysis) {
        let url = fileURL(for: analysis.id)
        guard let data = try? JSONEncoder().encode(analysis) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Load

    /// Loads a single ScanAnalysis by scan UUID. Returns nil if not found or decode fails.
    static func load(scanId: UUID) -> ScanAnalysis? {
        let url = fileURL(for: scanId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ScanAnalysis.self, from: data)
    }

    /// Loads all persisted ScanAnalysis objects. Silently skips malformed files.
    static func loadAll() -> [ScanAnalysis] {
        let dir = analysisDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }
        return contents
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> ScanAnalysis? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(ScanAnalysis.self, from: data)
            }
    }

    /// Deletes the analysis file for a specific scan. No-op if file doesn't exist.
    static func delete(scanId: UUID) {
        let url = fileURL(for: scanId)
        try? FileManager.default.removeItem(at: url)
    }

    /// Deletes all analysis files. Used on full reset.
    static func deleteAll() {
        let dir = analysisDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return }
        contents.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    // MARK: - Reanalysis check

    /// Returns true if the stored analysis was created with an older version
    /// and should be re-run against updated analysis logic.
    static func needsReanalysis(scanId: UUID) -> Bool {
        guard let analysis = load(scanId: scanId) else { return true }
        return analysis.analysisVersion < currentAnalysisVersion
    }
}
