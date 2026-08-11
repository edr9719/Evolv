import Foundation

/// Computes literal, person-normalized visual deltas. Supported zero values are
/// deliberately retained so "stable" is not confused with missing evidence.
enum VisualSignalEngine {
    static func compute(
        currentProfiles: [SilhouetteProfile],
        allScanAnalyses: [ScanAnalysis],
        currentCameraMetadata: [Pose: CaptureCameraMetadata] = [:],
        thresholds: AnalysisThresholdSet = .engineeringV1
    ) -> VisualSignalSet {
        let scanCount = allScanAnalyses.count + 1
        let tier = ReliabilityTier.tier(for: scanCount)
        guard let baselineAnalysis = allScanAnalyses.sorted(by: { $0.analyzedAt < $1.analyzedAt }).first else {
            return VisualSignalSet(deltas: [], fatLossSignals: nil, reliabilityTier: tier, regionalComparisons: [])
        }
        let baselineProfiles = baselineAnalysis.silhouetteProfiles
        let baselineCameraMetadata: [Pose: CaptureCameraMetadata] = Dictionary(uniqueKeysWithValues:
            (baselineAnalysis.captureCameraMetadata ?? [:]).compactMap { key, metadata -> (Pose, CaptureCameraMetadata)? in
                guard let pose = Pose(rawValue: key) else { return nil }
                return (pose, metadata)
            }
        )

        let comparisons = comparePair(
            baselineProfiles: baselineProfiles,
            currentProfiles: currentProfiles,
            baselineCameraMetadata: baselineCameraMetadata,
            currentCameraMetadata: currentCameraMetadata,
            thresholds: thresholds
        )
        let deltas = comparisons.compactMap { comparison -> RegionalDelta? in
            guard comparison.status != .unavailable, let delta = comparison.normalizedDelta else { return nil }
            return RegionalDelta(region: comparison.region, normalizedDelta: delta, fromScanCount: scanCount)
        }

        let value: (BodyRegion) -> Float? = { region in
            comparisons.first { $0.region == region && $0.status != .unavailable }?.normalizedDelta
        }
        let fatLossSignals: FatLossSignalSet?
        if let waist = value(.waist), let shoulders = value(.shoulders), let chest = value(.chest) {
            fatLossSignals = FatLossSignalSet(
                waistNarrowing: waist,
                taperIndexDelta: shoulders - waist,
                chestToWaistRatioDelta: chest - waist,
                lowerTorsoNarrowing: waist,
                shoulderToWaistRatioDelta: shoulders - waist
            )
        } else {
            fatLossSignals = nil
        }

        return VisualSignalSet(
            deltas: deltas,
            fatLossSignals: fatLossSignals,
            reliabilityTier: tier,
            regionalComparisons: comparisons
        )
    }

    /// Direct anchor-to-repeat comparison for the local consistency protocol.
    /// This deliberately bypasses longitudinal smoothing and insight wording.
    static func comparePair(
        baselineProfiles: [SilhouetteProfile],
        currentProfiles: [SilhouetteProfile],
        baselineCameraMetadata: [Pose: CaptureCameraMetadata] = [:],
        currentCameraMetadata: [Pose: CaptureCameraMetadata] = [:],
        thresholds: AnalysisThresholdSet = .engineeringV1
    ) -> [RegionalComparison] {
        [BodyRegion.shoulders, .chest, .waist, .arms].map { region in
            compare(
                region: region,
                baselineProfiles: baselineProfiles,
                currentProfiles: currentProfiles,
                baselineCameraMetadata: baselineCameraMetadata,
                currentCameraMetadata: currentCameraMetadata,
                thresholds: thresholds
            )
        }
    }

    private static func compare(
        region: BodyRegion,
        baselineProfiles: [SilhouetteProfile],
        currentProfiles: [SilhouetteProfile],
        baselineCameraMetadata: [Pose: CaptureCameraMetadata],
        currentCameraMetadata: [Pose: CaptureCameraMetadata],
        thresholds: AnalysisThresholdSet
    ) -> RegionalComparison {
        let expected = expectedPoses(for: region)
        var contributions: [PoseContribution] = []

        for pose in Pose.required {
            let isExpected = expected.required.contains(pose) || expected.optional.contains(pose)
            guard isExpected else { continue }
            guard let baseline = baselineProfiles.first(where: { $0.pose == pose }) else {
                contributions.append(unavailable(pose, "baseline_feature_unavailable"))
                continue
            }
            guard let current = currentProfiles.first(where: { $0.pose == pose }) else {
                contributions.append(unavailable(pose, "current_feature_unavailable"))
                continue
            }
            if let baselineCamera = baselineCameraMetadata[pose],
               let currentCamera = currentCameraMetadata[pose],
               !baselineCamera.isComparable(with: currentCamera) {
                contributions.append(unavailable(pose, "camera_configuration_changed"))
                continue
            }
            guard let baselineValue = featureValue(region, profile: baseline), baselineValue > 0,
                  let currentValue = featureValue(region, profile: current), currentValue > 0 else {
                contributions.append(unavailable(pose, "region_feature_unavailable"))
                continue
            }
            guard let match = current.poseMatchScore else {
                contributions.append(PoseContribution(
                    pose: pose,
                    baselineValue: baselineValue,
                    currentValue: currentValue,
                    normalizedDelta: nil,
                    poseMatchScore: nil,
                    status: .unavailable,
                    reason: "pose_match_unavailable"
                ))
                continue
            }
            guard match >= thresholds.minimumPoseMatch else {
                contributions.append(PoseContribution(
                    pose: pose,
                    baselineValue: baselineValue,
                    currentValue: currentValue,
                    normalizedDelta: nil,
                    poseMatchScore: match,
                    status: .unavailable,
                    reason: "pose_not_comparable"
                ))
                continue
            }
            let raw = (currentValue - baselineValue) / baselineValue
            let clamped = abs(raw) < thresholds.stableBand(for: region) ? Float(0) : raw
            contributions.append(PoseContribution(
                pose: pose,
                baselineValue: baselineValue,
                currentValue: currentValue,
                normalizedDelta: clamped,
                poseMatchScore: match,
                status: .supported,
                reason: nil
            ))
        }

        let supported = contributions.filter { $0.status == .supported }
        let supportedPoses = Set(supported.map(\.pose))
        let requiredSatisfied: Bool
        if region == .arms {
            requiredSatisfied = supportedPoses.intersection(Set(Pose.required)).count >= 2
        } else {
            requiredSatisfied = Set(expected.required).isSubset(of: supportedPoses)
        }
        guard requiredSatisfied else {
            return RegionalComparison(
                region: region,
                status: .unavailable,
                normalizedDelta: nil,
                contributions: contributions,
                reason: "required_pose_evidence_unavailable"
            )
        }

        let values = supported.compactMap(\.normalizedDelta)
        guard !values.isEmpty else {
            return RegionalComparison(region: region, status: .unavailable, normalizedDelta: nil, contributions: contributions, reason: "no_supported_pose_delta")
        }
        let hasIncrease = values.contains { $0 > 0 }
        let hasDecrease = values.contains { $0 < 0 }
        let spread = (values.max() ?? 0) - (values.min() ?? 0)
        guard !(hasIncrease && hasDecrease), spread <= thresholds.conflictLimit(for: region) else {
            return RegionalComparison(
                region: region,
                status: .unavailable,
                normalizedDelta: nil,
                contributions: contributions,
                reason: "cross_pose_conflict"
            )
        }

        let fused = median(values)
        let status: RegionalComparisonStatus = fused == 0 ? .stable : (fused > 0 ? .increase : .decrease)
        return RegionalComparison(
            region: region,
            status: status,
            normalizedDelta: fused,
            contributions: contributions,
            reason: nil
        )
    }

    private static func expectedPoses(for region: BodyRegion) -> (required: [Pose], optional: [Pose]) {
        switch region {
        case .shoulders: return ([.front, .back], [])
        case .chest: return ([.front, .side], [])
        case .waist: return ([.front, .side], [.back])
        case .arms: return ([], [.front, .side, .back])
        case .thighs: return ([], [])
        }
    }

    private static func featureValue(_ region: BodyRegion, profile: SilhouetteProfile) -> Float? {
        if let features = profile.regionFeatures {
            return features.first(where: { $0.region == region && $0.evidenceReason == nil })?.normalizedValue
        }
        // Legacy scalar values are read only when the complete v4 feature list
        // is absent. A missing v4 region is unavailable, never a request to fall
        // back to an older measurement definition.
        guard profile.supportedRegions?.contains(region) == true else { return nil }
        switch region {
        case .shoulders: return profile.shoulderWidthRatio
        case .chest: return profile.chestWidthRatio
        case .waist: return profile.waistWidthRatio
        case .arms: return profile.armMidWidthRatio
        case .thighs: return nil
        }
    }

    private static func unavailable(_ pose: Pose, _ reason: String) -> PoseContribution {
        PoseContribution(
            pose: pose,
            baselineValue: nil,
            currentValue: nil,
            normalizedDelta: nil,
            poseMatchScore: nil,
            status: .unavailable,
            reason: reason
        )
    }

    private static func median(_ values: [Float]) -> Float {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        if sorted.count.isMultiple(of: 2) {
            return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        }
        return sorted[sorted.count / 2]
    }
}
