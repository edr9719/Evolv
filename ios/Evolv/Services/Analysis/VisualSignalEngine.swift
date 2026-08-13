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
        let poseComparisons = currentProfiles.map { current in
            let pose = current.pose
            guard let poseBaseline = allScanAnalyses
                .sorted(by: { $0.analyzedAt < $1.analyzedAt })
                .first(where: { analysis in
                    analysis.silhouetteProfiles.contains { $0.pose == pose }
                }),
                  let baselineProfile = poseBaseline.silhouetteProfiles.first(where: { $0.pose == pose }) else {
                return PoseComparison(
                    pose: pose,
                    availability: .baselineOnly,
                    regions: [],
                    reason: "same_pose_baseline_unavailable"
                )
            }
            let baselineMetadata = cameraMetadata(for: pose, in: poseBaseline)
            return comparePosePair(
                baselineProfile: baselineProfile,
                currentProfile: current,
                baselineCameraMetadata: baselineMetadata,
                currentCameraMetadata: currentCameraMetadata[pose],
                thresholds: thresholds
            )
        }
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
            regionalComparisons: comparisons,
            poseComparisons: poseComparisons
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

    /// Compares one pose only. This is the only path used for showcase
    /// evidence: optional poses never enter relaxed-pose fusion.
    static func comparePosePair(
        baselineProfile: SilhouetteProfile,
        currentProfile: SilhouetteProfile,
        baselineCameraMetadata: CaptureCameraMetadata? = nil,
        currentCameraMetadata: CaptureCameraMetadata? = nil,
        thresholds: AnalysisThresholdSet = .engineeringV1
    ) -> PoseComparison {
        guard baselineProfile.pose == currentProfile.pose else {
            return PoseComparison(
                pose: currentProfile.pose,
                availability: .partialEvidence,
                regions: [],
                reason: "pose_mismatch"
            )
        }

        let pose = currentProfile.pose
        let comparisons = analyticalRegions(for: pose).map { region in
            compareSamePose(
                pose: pose,
                region: region,
                baselineProfile: baselineProfile,
                currentProfile: currentProfile,
                baselineCameraMetadata: baselineCameraMetadata,
                currentCameraMetadata: currentCameraMetadata,
                thresholds: thresholds
            )
        }
        let supported = comparisons.filter { $0.status != .unavailable }
        return PoseComparison(
            pose: pose,
            availability: supported.isEmpty ? .partialEvidence : .comparable,
            regions: comparisons,
            reason: supported.isEmpty ? "no_supported_same_pose_evidence" : nil
        )
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
            switch (baselineCameraMetadata[pose], currentCameraMetadata[pose]) {
            case let (baselineCamera?, currentCamera?):
                guard baselineCamera.isComparable(with: currentCamera) else {
                    contributions.append(unavailable(pose, "camera_configuration_changed"))
                    continue
                }
            case (nil, nil):
                // Preserve legacy-to-legacy decoding. Neither side claims a
                // known camera configuration, so other evidence gates decide.
                break
            default:
                // A known camera capture must never be compared against a
                // library or legacy capture whose camera configuration is
                // unknown.
                contributions.append(unavailable(pose, "camera_configuration_unknown"))
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

    private static func compareSamePose(
        pose: Pose,
        region: BodyRegion,
        baselineProfile: SilhouetteProfile,
        currentProfile: SilhouetteProfile,
        baselineCameraMetadata: CaptureCameraMetadata?,
        currentCameraMetadata: CaptureCameraMetadata?,
        thresholds: AnalysisThresholdSet
    ) -> RegionalComparison {
        let unavailableResult: (String, Float?, Float?) -> RegionalComparison = { reason, baseline, current in
            RegionalComparison(
                region: region,
                status: .unavailable,
                normalizedDelta: nil,
                contributions: [PoseContribution(
                    pose: pose,
                    baselineValue: baseline,
                    currentValue: current,
                    normalizedDelta: nil,
                    poseMatchScore: currentProfile.poseMatchScore,
                    status: .unavailable,
                    reason: reason
                )],
                reason: reason
            )
        }

        switch (baselineCameraMetadata, currentCameraMetadata) {
        case let (baseline?, current?):
            guard baseline.isComparable(with: current) else {
                return unavailableResult("camera_configuration_changed", nil, nil)
            }
        case (nil, nil):
            break // Backward-compatible legacy-to-legacy evidence.
        default:
            return unavailableResult("camera_configuration_unknown", nil, nil)
        }

        guard let baselineValue = featureValue(region, profile: baselineProfile), baselineValue > 0,
              let currentValue = featureValue(region, profile: currentProfile), currentValue > 0 else {
            return unavailableResult("region_feature_unavailable", nil, nil)
        }
        guard let match = currentProfile.poseMatchScore else {
            return unavailableResult("pose_match_unavailable", baselineValue, currentValue)
        }
        guard match >= thresholds.minimumPoseMatch else {
            return unavailableResult("pose_not_comparable", baselineValue, currentValue)
        }

        let raw = (currentValue - baselineValue) / baselineValue
        let delta = abs(raw) < thresholds.stableBand(for: region) ? Float(0) : raw
        let status: RegionalComparisonStatus = delta == 0 ? .stable : (delta > 0 ? .increase : .decrease)
        return RegionalComparison(
            region: region,
            status: status,
            normalizedDelta: delta,
            contributions: [PoseContribution(
                pose: pose,
                baselineValue: baselineValue,
                currentValue: currentValue,
                normalizedDelta: delta,
                poseMatchScore: match,
                status: .supported,
                reason: nil
            )],
            reason: nil
        )
    }

    private static func analyticalRegions(for pose: Pose) -> [BodyRegion] {
        switch pose {
        case .front: return [.shoulders, .chest, .waist, .arms]
        case .side: return [.chest, .waist, .arms]
        case .back: return [.shoulders, .waist, .arms]
        case .frontDoubleBicep: return [.shoulders, .chest, .waist, .arms]
        case .sideChest: return [.chest, .waist, .arms]
        case .backDoubleBicep: return [.shoulders, .waist, .arms]
        case .mostMuscular: return [.shoulders, .chest, .waist, .arms]
        case .relaxedAesthetic: return [.chest, .waist, .arms]
        case .legs: return [.thighs]
        }
    }

    private static func cameraMetadata(for pose: Pose, in analysis: ScanAnalysis) -> CaptureCameraMetadata? {
        guard let raw = analysis.captureCameraMetadata?[pose.rawValue] else { return nil }
        return raw
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
        case .thighs: return profile.regionFeatures?
            .first(where: { $0.region == .thighs && $0.evidenceReason == nil })?
            .normalizedValue
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

/// Produces evidence for the exact pair selected in Timeline. This never
/// rewrites either scan's canonical longitudinal analysis and never mixes
/// camera recipes, scan roles, or analysis versions.
enum ScanPairComparisonEngine {
    static func compare(
        before: Scan,
        after: Scan,
        beforeAnalysis: ScanAnalysis?,
        afterAnalysis: ScanAnalysis?,
        thresholds: AnalysisThresholdSet = .engineeringV1
    ) -> ScanPairComparison {
        let unavailable: (String) -> ScanPairComparison = { reason in
            ScanPairComparison(
                beforeScanID: before.id,
                afterScanID: after.id,
                availability: .partialEvidence,
                relaxedRegions: [],
                poseComparisons: [],
                evidenceStrength: .low,
                reason: reason
            )
        }

        guard before.id != after.id, before.date < after.date else {
            return unavailable("comparison_dates_not_chronological")
        }
        guard before.isCanonicalProgressScan, after.isCanonicalProgressScan else {
            return unavailable("canonical_scans_required")
        }
        switch (before.captureRecipeID, after.captureRecipeID) {
        case let (beforeID?, afterID?) where beforeID == afterID:
            break
        case (nil, nil):
            break
        default:
            return unavailable("capture_recipe_changed")
        }
        guard let beforeAnalysis, let afterAnalysis,
              beforeAnalysis.analysisVersion == AnalysisStore.currentAnalysisVersion,
              afterAnalysis.analysisVersion == AnalysisStore.currentAnalysisVersion else {
            return unavailable("current_analysis_unavailable")
        }

        let beforeMetadata = metadata(from: beforeAnalysis)
        let afterMetadata = metadata(from: afterAnalysis)
        let commonPoses = Pose.allCases.filter { pose in
            before.capture(for: pose) != nil
                && after.capture(for: pose) != nil
                && beforeAnalysis.silhouetteProfiles.contains { $0.pose == pose }
                && afterAnalysis.silhouetteProfiles.contains { $0.pose == pose }
        }

        var adjustedAfter: [SilhouetteProfile] = []
        var poseComparisons: [PoseComparison] = []
        for pose in commonPoses {
            guard let baselineProfile = beforeAnalysis.silhouetteProfiles.first(where: { $0.pose == pose }),
                  var currentProfile = afterAnalysis.silhouetteProfiles.first(where: { $0.pose == pose }) else { continue }
            if let baselinePose = beforeAnalysis.extractedPoses.first(where: { $0.pose == pose }),
               let currentPose = afterAnalysis.extractedPoses.first(where: { $0.pose == pose }) {
                currentProfile.poseMatchScore = NormalizationEngine.computePoseMatchScore(
                    a: baselinePose,
                    b: currentPose
                )
            } else {
                currentProfile.poseMatchScore = nil
            }
            adjustedAfter.append(currentProfile)
            poseComparisons.append(VisualSignalEngine.comparePosePair(
                baselineProfile: baselineProfile,
                currentProfile: currentProfile,
                baselineCameraMetadata: beforeMetadata[pose],
                currentCameraMetadata: afterMetadata[pose],
                thresholds: thresholds
            ))
        }

        let relaxed = VisualSignalEngine.comparePair(
            baselineProfiles: beforeAnalysis.silhouetteProfiles,
            currentProfiles: adjustedAfter,
            baselineCameraMetadata: beforeMetadata,
            currentCameraMetadata: afterMetadata,
            thresholds: thresholds
        )
        let supported = poseComparisons.flatMap(\.supportedRegions)
        let matches = supported.flatMap(\.contributions).compactMap(\.poseMatchScore)
        let strength = evidenceStrength(
            supportedRegionCount: supported.count,
            poseMatches: matches,
            thresholdsValidated: thresholds.isValidated
        )
        let hasAnySupportedEvidence = !supported.isEmpty
        return ScanPairComparison(
            beforeScanID: before.id,
            afterScanID: after.id,
            availability: hasAnySupportedEvidence ? .comparable : .partialEvidence,
            relaxedRegions: relaxed,
            poseComparisons: poseComparisons,
            evidenceStrength: strength,
            reason: hasAnySupportedEvidence ? nil : "no_supported_same_pose_evidence"
        )
    }

    private static func metadata(from analysis: ScanAnalysis) -> [Pose: CaptureCameraMetadata] {
        Dictionary(uniqueKeysWithValues: (analysis.captureCameraMetadata ?? [:]).compactMap { key, value in
            guard let pose = Pose(rawValue: key) else { return nil }
            return (pose, value)
        })
    }

    private static func evidenceStrength(
        supportedRegionCount: Int,
        poseMatches: [Float],
        thresholdsValidated: Bool
    ) -> Confidence {
        guard supportedRegionCount > 0, !poseMatches.isEmpty else { return .low }
        let average = poseMatches.reduce(0, +) / Float(poseMatches.count)
        if thresholdsValidated, supportedRegionCount >= 4, average >= 0.93 { return .high }
        if supportedRegionCount >= 2, average >= 0.85 { return .medium }
        return .low
    }
}
