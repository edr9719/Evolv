import UIKit

/// Orchestrates the full physique analysis pipeline for a new scan.
/// Photos are NEVER sent to any network service — only InterpretedSignals leave the device.
@MainActor
final class AnalysisPipeline {

    static let shared = AnalysisPipeline()
    private init() {}

    private let proxy = NetworkProxy.shared

    // MARK: - Public API

    /// Runs the full analysis pipeline for a newly captured scan.
    /// Returns a ScanAnalysis — intermediate version saved before LLM; final version saved after.
    func analyzeNewScan(
        scan: Scan,
        allScans: [Scan],
        measurements: [Measurement],
        profile: UserProfile
    ) async -> ScanAnalysis {
        let scanId = scan.id
        let priorAnalyses = AnalysisStore.loadAll()
            .filter { prior in allScans.contains { $0.id == prior.id } }
            .sorted { $0.analyzedAt < $1.analyzedAt }

        // Step 1: Quality gate on all standard captures, pick primary (front) result
        var qualityResult: QualityGateResult = defaultQualityResult()
        for capture in scan.standardCaptures {
            if let image = PhotoStore.loadImage(named: capture.imageFilename) {
                let result = await QualityGateEngine.evaluate(image: image, expectedPose: capture.pose)
                if capture.pose == .front { qualityResult = result }
            }
        }

        // Step 2: CV — pose extraction + silhouette for each standard capture (sequential)
        var extractedPoses: [ExtractedPose] = []
        var silhouetteProfiles: [SilhouetteProfile] = []

        for capture in scan.standardCaptures {
            guard let image = PhotoStore.loadImage(named: capture.imageFilename) else { continue }

            if let pose = try? await BodyPoseExtractor.extract(from: image, pose: capture.pose, scanId: scanId) {
                let normalized = NormalizationEngine.normalize(pose: pose)

                // Compute pose match score vs last scan's same pose
                var withMatch = normalized
                if let priorSamePose = priorAnalyses.last?.extractedPoses.first(where: { $0.pose == capture.pose }) {
                    let score = NormalizationEngine.computePoseMatchScore(a: normalized, b: priorSamePose)
                    withMatch.poseMatchScore = score
                }

                extractedPoses.append(withMatch)

                if let sil = try? await SilhouetteAnalyzer.analyze(image: image, extractedPose: withMatch) {
                    silhouetteProfiles.append(sil)
                }
            }
        }

        // Step 3: Visual signals
        let visualSignals = VisualSignalEngine.compute(
            currentProfiles: silhouetteProfiles,
            allScanAnalyses: priorAnalyses
        )

        // Step 4: Trend smoothing
        let smoothedSignals = TrendSmoothingEngine.smooth(
            allAnalyses: priorAnalyses,
            currentVisualSignals: visualSignals
        )

        // Step 5: Recomposition patterns
        let recompPatterns = RecompositionDetector.detect(
            smoothed: smoothedSignals,
            measurements: measurements,
            goal: profile.goal
        )

        // Step 6: Measurement alignments + confidence
        let interpreted = SignalInterpreter.interpret(
            smoothed: smoothedSignals,
            visualSignals: visualSignals,
            measurements: measurements,
            profile: profile,
            recompositionPatterns: recompPatterns,
            qualityResult: qualityResult,
            allAnalyses: priorAnalyses,
            scanContext: scan.context
        )

        let measurementAlignmentScore = ConfidenceEngine.measurementAgreementScore(
            from: interpreted.measurementAlignment
        )
        let avgPoseMatch = extractedPoses.compactMap(\.poseMatchScore).reduce(0, +)
            / Float(max(1, extractedPoses.compactMap(\.poseMatchScore).count))

        let confidence = ConfidenceEngine.compute(
            scanCount: allScans.count,
            qualityResult: qualityResult,
            poseMatchScore: avgPoseMatch > 0 ? avgPoseMatch : nil,
            measurementAgreementScore: measurementAlignmentScore,
            allAnalyses: priorAnalyses,
            goal: profile.goal,
            recompositionPatterns: recompPatterns
        )

        // Step 7: Build intermediate analysis (no insight yet) and persist
        let intermediate = ScanAnalysis(
            id: scanId,
            analysisVersion: AnalysisStore.currentAnalysisVersion,
            analyzedAt: Date(),
            qualityResult: qualityResult,
            extractedPoses: extractedPoses,
            silhouetteProfiles: silhouetteProfiles,
            visualSignals: visualSignals,
            smoothedSignals: smoothedSignals,
            confidence: confidence,
            interpretedSignals: interpreted,
            generatedInsight: nil
        )
        AnalysisStore.save(intermediate)

        // Step 8: LLM insight (async, non-blocking after intermediate save)
        let insight = await InsightEngine.generateInsight(signals: interpreted, networkProxy: proxy)

        let final_ = ScanAnalysis(
            id: scanId,
            analysisVersion: AnalysisStore.currentAnalysisVersion,
            analyzedAt: intermediate.analyzedAt,
            qualityResult: qualityResult,
            extractedPoses: extractedPoses,
            silhouetteProfiles: silhouetteProfiles,
            visualSignals: visualSignals,
            smoothedSignals: smoothedSignals,
            confidence: confidence,
            interpretedSignals: interpreted,
            generatedInsight: insight
        )
        AnalysisStore.save(final_)

        return final_
    }

    // MARK: - Helpers

    private func defaultQualityResult() -> QualityGateResult {
        QualityGateResult(
            verdict: .pass,
            issues: [],
            blurScore: 100,
            brightnessScore: 0.5,
            coverageScore: 0.7,
            regionalCoverage: [:]
        )
    }
}
