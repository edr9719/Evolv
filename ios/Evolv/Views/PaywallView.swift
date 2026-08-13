import SwiftUI

struct PaywallView: View {
    enum Context {
        case postOnboarding   // first-time, mandatory selection, no close button
        case settings         // upgrade entry from settings, dismissible
    }

    let context: Context

    init(context: Context = .settings) {
        self.context = context
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app

    @State private var selectedPlan: PurchaseService.Plan? = nil
    @State private var purchaseState: PurchaseService.PurchaseState = .idle
    @State private var showRestoreToast: String? = nil

    private var purchase: PurchaseService { PurchaseService.shared }

    var body: some View {
        Group {
            ZStack {
                EvolvTheme.background.ignoresSafeArea()
                ambient

                ScrollView {
                    VStack(spacing: 26) {
                        hero
                            .padding(.top, context == .postOnboarding ? 28 : 20)
                            .padding(.horizontal, 24)

                        featureList
                            .padding(.horizontal, 24)

                        plansSection
                            .padding(.horizontal, 24)

                        ctaSection
                            .padding(.horizontal, 24)
                            .padding(.bottom, 40)
                    }
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .contentMargins(.bottom, 8, for: .scrollContent)

                // Top scrim — fades scrolled content out before it reaches the status bar
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [EvolvTheme.background, EvolvTheme.background.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 64)
                    Spacer()
                }
                .allowsHitTesting(false)
                .ignoresSafeArea(edges: .top)

                // Top chrome
                VStack {
                    HStack {
                        if context == .postOnboarding {
                            Spacer()
                        } else {
                            Spacer()
                            Button { dismiss() } label: {
                                ZStack {
                                    Circle().fill(EvolvTheme.surface).frame(width: 32, height: 32)
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(EvolvTheme.textMuted)
                                }
                            }
                            .padding(.top, 12)
                            .padding(.trailing, 16)
                        }
                    }
                    Spacer()
                }

                if let toast = showRestoreToast {
                    VStack {
                        Spacer()
                        Text(toast)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(EvolvTheme.text)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(EvolvTheme.surface).overlay(Capsule().stroke(EvolvTheme.stroke, lineWidth: 1)))
                            .padding(.bottom, 36)
                            .transition(.opacity)
                    }
                }
            }
        }
        .interactiveDismissDisabled(context == .postOnboarding)
        .trackView("PaywallView")
    }

    private var ambient: some View {
        ZStack {
            Circle()
                .fill(EvolvTheme.accent.opacity(0.18))
                .frame(width: 480, height: 480)
                .blur(radius: 110)
                .offset(x: 0, y: -260)
            Circle()
                .fill(Color(red: 0.30, green: 0.60, blue: 0.55).opacity(0.14))
                .frame(width: 360, height: 360)
                .blur(radius: 100)
                .offset(x: 140, y: 360)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private var hero: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                Image("evolv-logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 68)
                Text("PREMIUM")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(2.0)
                    .foregroundStyle(EvolvTheme.accent)
            }

            Text("See your real\ntransformation.")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(EvolvTheme.text)
                .lineSpacing(2)

            Text("Track your visual evolution honestly — with AI insights that surface real change over time, not hype.")
                .font(.system(size: 14, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(EvolvTheme.textMuted)
                .lineSpacing(4)
                .padding(.horizontal, 20)
        }
    }

    private var featureList: some View {
        GlassCard(padding: 20, cornerRadius: 22) {
            VStack(spacing: 0) {
                featureRow("rectangle.on.rectangle.angled", "Honest transformation timeline", "Side-by-side comparisons that reveal real visual change over weeks and months.")
                Divider().overlay(EvolvTheme.stroke)
                featureRow("sparkles", "Evidence-based progress insight", "Region-by-region visual reads with evidence strength — unsupported regions stay unavailable.")
                Divider().overlay(EvolvTheme.stroke)
                featureRow("calendar", "Consistency guidance", "Quiet reminders and capture cues that keep your trend trustworthy.")
                Divider().overlay(EvolvTheme.stroke)
                featureRow("gauge.with.dots.needle.67percent", "Progress Score over time", "A single honest number that tracks the momentum of your physique.")
            }
        }
    }

    private func featureRow(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(EvolvTheme.accentDim)
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(EvolvTheme.accent)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                Text(subtitle)
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
                    .lineSpacing(3)
            }
            Spacer()
        }
        .padding(.vertical, 11)
    }

    private var plansSection: some View {
        VStack(spacing: 12) {
            Text("Both plans start with a \(PurchaseService.trialDays)-day free trial.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(EvolvTheme.accent)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 4)

            ForEach(PurchaseService.Plan.allCases) { plan in
                PlanCard(plan: plan, selected: selectedPlan == plan) {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedPlan = plan }
                }
            }
        }
    }

    private var ctaSection: some View {
        VStack(spacing: 16) {
            let isLoading: Bool = {
                if case .loading = purchaseState { return true }
                return false
            }()

            Button {
                guard let plan = selectedPlan, !isLoading else { return }
                Task { await beginPurchase(plan) }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(selectedPlan == nil ? EvolvTheme.surface : EvolvTheme.accent)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(selectedPlan == nil ? EvolvTheme.stroke : .clear, lineWidth: 1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                    if isLoading {
                        ProgressView()
                            .tint(EvolvTheme.background)
                    } else {
                        HStack(spacing: 8) {
                            Text(ctaTitle)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            if selectedPlan != nil {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .foregroundStyle(selectedPlan == nil ? EvolvTheme.textMuted : EvolvTheme.background)
                        .padding(.horizontal, 20)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(selectedPlan == nil || isLoading)
            .animation(.easeInOut(duration: 0.2), value: selectedPlan)

            if let plan = selectedPlan {
                Text(trialFootnote(for: plan))
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textFaint)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            } else {
                Text("Choose a plan to continue.")
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textFaint)
            }

            HStack(spacing: 14) {
                Button("Restore") {
                    Task { await beginRestore() }
                }
                .disabled(isLoading)
                Text("·").foregroundStyle(EvolvTheme.textFaint)
                Text("Terms")
                Text("·").foregroundStyle(EvolvTheme.textFaint)
                Text("Privacy")
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(EvolvTheme.textMuted)

            if context == .postOnboarding {
                Text("Cancel anytime during your trial. Your data stays on your device.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(EvolvTheme.textFaint)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            } else {
                Text("Cancel anytime. Your data stays on your device.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(EvolvTheme.textFaint)
            }
        }
    }

    private var ctaTitle: String {
        guard let plan = selectedPlan else { return "Select a plan" }
        return "Start \(PurchaseService.trialDays)-day free trial · \(plan.title)"
    }

    private func trialFootnote(for plan: PurchaseService.Plan) -> String {
        "Free for \(PurchaseService.trialDays) days, then \(plan.price) \(plan.perLabel). Cancel anytime before your trial ends and you won't be charged."
    }

    @MainActor
    private func beginPurchase(_ plan: PurchaseService.Plan) async {
        purchaseState = .loading
        let success = await purchase.purchase(plan)
        purchaseState = purchase.state
        if success {
            app.syncSubscriptionFromPurchaseService()
            if context == .postOnboarding {
                app.markPostOnboardingPaywallSeen()
            } else {
                dismiss()
            }
        }
    }

    @MainActor
    private func beginRestore() async {
        purchaseState = .loading
        let restored = await purchase.restore()
        purchaseState = purchase.state
        if restored {
            app.syncSubscriptionFromPurchaseService()
            if context == .postOnboarding {
                app.markPostOnboardingPaywallSeen()
            } else {
                dismiss()
            }
        } else {
            withAnimation { showRestoreToast = "No purchases to restore on this device." }
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            withAnimation { showRestoreToast = nil }
        }
    }
}

private struct PlanCard: View {
    let plan: PurchaseService.Plan
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(selected ? EvolvTheme.accent : EvolvTheme.stroke, lineWidth: 1.4)
                        .frame(width: 22, height: 22)
                    if selected {
                        Circle().fill(EvolvTheme.accent).frame(width: 12, height: 12)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(EvolvTheme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        if let badge = plan.savingsBadge {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(0.8)
                                .foregroundStyle(EvolvTheme.background)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(EvolvTheme.accent))
                                .layoutPriority(1)
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(plan.price)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.text)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(plan.perLabel)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(EvolvTheme.textFaint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .layoutPriority(1)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(selected ? EvolvTheme.accent.opacity(0.08) : EvolvTheme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(selected ? EvolvTheme.accent.opacity(0.7) : EvolvTheme.stroke, lineWidth: selected ? 1.4 : 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        var parts: [String] = []
        parts.append("\(PurchaseService.trialDays)-day free trial")
        if let eq = plan.equivalentMonthly { parts.append(eq) }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    PaywallView(context: .postOnboarding)
        .environment(AppState())
}
