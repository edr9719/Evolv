import Foundation
import SwiftUI

/// Temporary product-surface policy for the invite-only Build 17 TestFlight.
/// This grants access without creating a subscription or trial. Public-release
/// purchasing and currently unavailable services remain separate future work.
enum Build17PilotConfiguration {
    static let isEnabled = true

    static var grantsFullProductAccess: Bool { isEnabled }
    static var purchaseFlowsAvailable: Bool { !isEnabled }
    static let cloudWrittenInsightsAvailable = false
    static let dataExportAvailable = false

    static let accessMessage = "Pilot access — all Evolv features are unlocked during this TestFlight."

    static func shouldPresentPostOnboardingPaywall(hasSeenPaywall: Bool) -> Bool {
        purchaseFlowsAvailable && !hasSeenPaywall
    }

    static func hasFullProductAccess(subscriptionActive: Bool) -> Bool {
        grantsFullProductAccess || subscriptionActive
    }

    static func allowsCloudWrittenInsights(preferenceEnabled: Bool) -> Bool {
        cloudWrittenInsightsAvailable && preferenceEnabled
    }
}

/// Production-shaped subscription service.
/// Today the purchase flow is mocked locally — there is no real StoreKit transaction.
/// The shape (async purchase, restore, product catalog, entitlement) is designed
/// so the implementation can be swapped to StoreKit 2 (`Product.products(for:)`,
/// `product.purchase()`, `Transaction.currentEntitlements`) without changing callers.
@Observable
final class PurchaseService {

    static let shared = PurchaseService()

    enum Plan: String, CaseIterable, Identifiable, Codable {
        case monthly
        case yearly
        var id: String { rawValue }

        /// Production product identifier (App Store Connect).
        var productID: String {
            switch self {
            case .monthly: return "evolv.premium.monthly"
            case .yearly:  return "evolv.premium.yearly"
            }
        }

        var title: String {
            switch self {
            case .monthly: return "Monthly"
            case .yearly:  return "Yearly"
            }
        }

        var price: String {
            switch self {
            case .monthly: return "$9.99"
            case .yearly:  return "$69.99"
            }
        }

        var perLabel: String {
            switch self {
            case .monthly: return "per month"
            case .yearly:  return "per year"
            }
        }

        var equivalentMonthly: String? {
            switch self {
            case .monthly: return nil
            case .yearly:  return "$5.83 / month"
            }
        }

        var savingsBadge: String? {
            self == .yearly ? "SAVE 42%" : nil
        }
    }

    enum PurchaseState: Equatable {
        case idle
        case loading
        case success(Plan)
        case failed(String)
    }

    static let trialDays: Int = 10

    private(set) var state: PurchaseState = .idle
    private(set) var activePlan: Plan? = nil
    private(set) var trialEndsAt: Date? = nil

    private init() {
        refreshFromPersistedState()
    }

    /// Returns true if the user currently has an active entitlement (including trial window).
    var isSubscribed: Bool {
        guard activePlan != nil else { return false }
        if let trialEnd = trialEndsAt, trialEnd > Date() { return true }
        // Real implementation: check StoreKit Transaction.currentEntitlements
        return activePlan != nil
    }

    /// Pull subscription state from persisted profile. Called on init and after AppState load.
    func bind(to profile: UserProfile) {
        if let raw = profile.subscriptionPlan, let plan = Plan(rawValue: raw) {
            activePlan = plan
        } else {
            activePlan = nil
        }
        trialEndsAt = profile.trialEndsAt
    }

    private func refreshFromPersistedState() {
        // PurchaseService lives independently of AppState; AppState calls `bind(to:)` on launch.
    }

    /// Begins purchase of the selected plan.
    /// Mock implementation: simulates network latency, then grants a 10-day trial entitlement.
    @MainActor
    func purchase(_ plan: Plan) async -> Bool {
        guard Build17PilotConfiguration.purchaseFlowsAvailable else {
            state = .failed("Purchases are unavailable in this pilot build.")
            return false
        }
        state = .loading
        do {
            try await Task.sleep(nanoseconds: 1_200_000_000)
        } catch {
            state = .failed("Purchase cancelled.")
            return false
        }
        // In production: replace with StoreKit 2 flow:
        //   let products = try await Product.products(for: [plan.productID])
        //   let result = try await products.first?.purchase()
        activePlan = plan
        trialEndsAt = Calendar.current.date(byAdding: .day, value: Self.trialDays, to: Date())
        state = .success(plan)
        return true
    }

    /// Restore purchases. Mock implementation: no prior purchase to find on this device.
    @MainActor
    func restore() async -> Bool {
        guard Build17PilotConfiguration.purchaseFlowsAvailable else {
            state = .failed("Purchases are unavailable in this pilot build.")
            return false
        }
        state = .loading
        try? await Task.sleep(nanoseconds: 700_000_000)
        // In production: `try await AppStore.sync()` and re-evaluate Transaction.currentEntitlements
        if activePlan != nil {
            state = .success(activePlan!)
            return true
        }
        state = .failed("No purchases to restore on this device.")
        return false
    }

    @MainActor
    func resetState() { state = .idle }
}
