import Foundation

/// Computes per-region visual deltas from silhouette profiles across scan history.
enum VisualSignalEngine {

    // Minimum scan counts before a region's delta is considered signal (not noise)
    private static let minScans: [BodyRegion: Int] = [
        .shoulders: 3, .chest: 3, .waist: 3, .arms: 3, .thighs: 4
    ]

    /// Noise floor: changes smaller than this are treated as zero (expressed as ratio)
    private static let noiseFloor: Float = 0.008

    // MARK: - Public API

    static func compute(
        currentProfiles: [SilhouetteProfile],
        allScanAnalyses: [ScanAnalysis]
    ) -> VisualSignalSet {
        let tier = ReliabilityTier.tier(for: allScanAnalyses.count + 1)

        // Only use front-pose profiles for left-right symmetric measurements
        let frontProfiles = allScanAnalyses.compactMap { a in
            a.silhouetteProfiles.first { $0.pose == .front }
        }
        let currentFront = currentProfiles.first { $0.pose == .front }

        var deltas: [RegionalDelta] = []

        for region in BodyRegion.allCases {
            let required = minScans[region] ?? 3
            if allScanAnalyses.count + 1 < required { continue }
            guard let baseline = frontProfiles.first else { continue }
            guard let current  = currentFront else { continue }

            let delta = computeDelta(
                region: region,
                current: current,
                baseline: baseline,
                history: frontProfiles
            )

            if abs(delta) >= noiseFloor {
                deltas.append(RegionalDelta(
                    region: region,
                    normalizedDelta: delta,
                    fromScanCount: allScanAnalyses.count + 1
                ))
            }
        }

        // Fat loss signals require front + side profiles
        let sideProfiles = allScanAnalyses.compactMap { a in
            a.silhouetteProfiles.first { $0.pose == .side }
        }
        let fatLossSignals = computeFatLossSignals(
            currentFront: currentFront,
            currentSide: currentProfiles.first { $0.pose == .side },
            baselineFront: frontProfiles.first,
            baselineSide: sideProfiles.first
        )

        return VisualSignalSet(deltas: deltas, fatLossSignals: fatLossSignals, reliabilityTier: tier)
    }

    // MARK: - Regional Delta

    private static func computeDelta(
        region: BodyRegion,
        current: SilhouetteProfile,
        baseline: SilhouetteProfile,
        history: [SilhouetteProfile]
    ) -> Float {
        let cVal = regionValue(region, profile: current)
        let bVal = regionValue(region, profile: baseline)
        guard bVal > 0 else { return 0 }
        return (cVal - bVal) / bVal
    }

    private static func regionValue(_ region: BodyRegion, profile: SilhouetteProfile) -> Float {
        switch region {
        case .shoulders: return profile.shoulderWidthRatio
        case .chest:     return profile.chestWidthRatio
        case .waist:     return profile.waistWidthRatio
        case .arms:      return profile.armMidWidthRatio
        case .thighs:    return profile.thighMidWidthRatio
        }
    }

    // MARK: - Fat Loss Signals

    private static func computeFatLossSignals(
        currentFront: SilhouetteProfile?,
        currentSide: SilhouetteProfile?,
        baselineFront: SilhouetteProfile?,
        baselineSide: SilhouetteProfile?
    ) -> FatLossSignalSet? {
        guard let cf = currentFront, let bf = baselineFront else { return nil }

        let waistNarrowing       = bf.waistWidthRatio  > 0 ? (cf.waistWidthRatio  - bf.waistWidthRatio)  / bf.waistWidthRatio  : 0
        let taperDelta           = cf.taperIndex       - bf.taperIndex
        let chestToWaistDelta    = cf.chestToWaistRatio - bf.chestToWaistRatio
        let shoulderToWaistDelta = cf.shoulderToWaistRatio - bf.shoulderToWaistRatio

        // Lower torso narrowing uses side profile if available, else front waist
        let lowerTorsoNarrowing: Float
        if let cs = currentSide, let bs = baselineSide, bs.lowerTorsoWidthRatio > 0 {
            lowerTorsoNarrowing = (cs.lowerTorsoWidthRatio - bs.lowerTorsoWidthRatio) / bs.lowerTorsoWidthRatio
        } else {
            lowerTorsoNarrowing = waistNarrowing
        }

        return FatLossSignalSet(
            waistNarrowing: waistNarrowing,
            taperIndexDelta: taperDelta,
            chestToWaistRatioDelta: chestToWaistDelta,
            lowerTorsoNarrowing: lowerTorsoNarrowing,
            shoulderToWaistRatioDelta: shoulderToWaistDelta
        )
    }
}
