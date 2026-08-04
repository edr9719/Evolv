import SwiftUI

struct OnboardingFlowView: View {
    @Environment(AppState.self) private var app
    @State private var step: Int = 0

    var body: some View {
        Group {
            ZStack {
                AmbientBackground()
                content
                    .animation(.easeInOut(duration: 0.35), value: step)
            }
        }
        .trackView("OnboardingFlowView")
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: WelcomeCarouselView(onContinue: { step = 1 })
        case 1: ConsistencyEducationView(onContinue: { step = 2 })
        case 2: GoalSelectionView(onContinue: { step = 3 })
        case 3: BodyBasicsView(onContinue: { step = 4 })
        case 4: ExperienceView(onContinue: { step = 5 })
        case 5: MeasurementsView(onContinue: { step = 6 })
        case 6: CadenceView(onContinue: { step = 7 })
        default: BaselineSnapshotView(onContinue: {
            withAnimation(.easeInOut) {
                app.hasCompletedOnboarding = true
                app.save()
            }
        })
        }
    }
}

// MARK: - Welcome

private struct WelcomeCarouselView: View {
    let onContinue: () -> Void
    @State private var page = 0

    private let pages: [(String, String, String)] = [
        ("eye.trianglebadge.exclamationmark", "See what the mirror misses",
         "Most people can't notice their own progress. They see themselves every day. Evolv reveals the changes you can't."),
        ("camera.viewfinder", "Consistent scans, honest insight",
         "Capture your physique on a schedule. Evolv compares scans against your baseline — visually and objectively."),
        ("waveform.path.ecg", "AI that tells the truth",
         "If you're progressing, we'll show it. If you've stalled, we'll say so. No fake hype, no invented gains.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    welcomePage(i)
                        .tag(i)
                        .padding(.horizontal, 28)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? EvolvTheme.accent : EvolvTheme.text.opacity(0.18))
                        .frame(width: i == page ? 22 : 6, height: 6)
                        .animation(.easeInOut(duration: 0.25), value: page)
                }
            }
            .padding(.bottom, 24)

            VStack(spacing: 12) {
                EvolvPrimaryButton(title: page == pages.count - 1 ? "Begin setup" : "Continue", icon: "arrow.right") {
                    if page < pages.count - 1 {
                        withAnimation { page += 1 }
                    } else {
                        onContinue()
                    }
                }
                Text("Takes under 30 seconds")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(EvolvTheme.textFaint)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 36)
        }
    }

    @ViewBuilder
    private func welcomePage(_ i: Int) -> some View {
        let (icon, title, subtitle) = pages[i]
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .fill(EvolvTheme.accent.opacity(0.10))
                    .frame(width: 220, height: 220)
                    .blur(radius: 24)
                Circle()
                    .stroke(EvolvTheme.accent.opacity(0.4), lineWidth: 1)
                    .frame(width: 160, height: 160)
                Circle()
                    .stroke(EvolvTheme.accent.opacity(0.2), lineWidth: 1)
                    .frame(width: 200, height: 200)
                Image(systemName: icon)
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(EvolvTheme.accent)
            }
            VStack(spacing: 14) {
                Text(title)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(EvolvTheme.text)
                Text(subtitle)
                    .font(.system(size: 15, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(EvolvTheme.textMuted)
                    .lineSpacing(3)
                    .padding(.horizontal, 8)
            }
            Spacer()
        }
    }
}

// MARK: - Consistency education

private struct ConsistencyEducationView: View {
    let onContinue: () -> Void

    private let rules: [(String, String, String)] = [
        ("location.fill", "Same location", "Pick one spot. A door frame, a hallway, a corner — return to it every scan."),
        ("sun.max.fill", "Same lighting", "Daylight or a fixed lamp. Avoid shadows that change across scans."),
        ("ruler", "Same distance", "Phone at chest height. Same step count back. The silhouette guide will help."),
        ("figure.stand", "Same poses", "Front, side, back, relaxed. Optional flex poses are saved for showcase only.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("THE ONE THING THAT MATTERS")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(EvolvTheme.accent)
                Text("Consistency beats precision.")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                Text("The more identical your scan conditions, the more Evolv can see real change.")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 24)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(rules.indices, id: \.self) { i in
                        let (icon, title, body) = rules[i]
                        HStack(alignment: .top, spacing: 14) {
                            ZStack {
                                Circle().fill(EvolvTheme.accentDim).frame(width: 40, height: 40)
                                Image(systemName: icon)
                                    .foregroundStyle(EvolvTheme.accent)
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(title)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(EvolvTheme.text)
                                Text(body)
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundStyle(EvolvTheme.textMuted)
                                    .lineSpacing(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(16)
                        .background {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(EvolvTheme.surface)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(EvolvTheme.stroke, lineWidth: 1)
                                }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)

            EvolvPrimaryButton(title: "I understand", icon: "arrow.right", action: onContinue)
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
        }
    }
}

// MARK: - Goal

private struct GoalSelectionView: View {
    @Environment(AppState.self) private var app
    let onContinue: () -> Void
    @State private var selected: FitnessGoal = .muscleGain

    var body: some View {
        OnboardingScaffold(
            kicker: "Step 1 of 4",
            title: "What are you working toward?",
            subtitle: "We'll tailor analysis to your goal."
        ) {
            VStack(spacing: 12) {
                ForEach(FitnessGoal.allCases) { goal in
                    SelectableRow(
                        icon: goal.icon,
                        title: goal.rawValue,
                        subtitle: goal.subtitle,
                        selected: selected == goal
                    ) { selected = goal }
                }
            }
        } cta: {
            EvolvPrimaryButton(title: "Continue", icon: "arrow.right") {
                app.profile.goal = selected
                onContinue()
            }
        }
    }
}

// MARK: - Body basics (height/weight)

private struct BodyBasicsView: View {
    @Environment(AppState.self) private var app
    let onContinue: () -> Void
    @State private var height: Double = 178
    @State private var weight: Double = 76

    var body: some View {
        OnboardingScaffold(
            kicker: "Step 2 of 4",
            title: "Your body basics",
            subtitle: "Used to normalize scans and trends."
        ) {
            VStack(spacing: 12) {
                NumericStepperRow(label: "Height", value: $height, unit: "cm", range: 140...210, step: 1, decimals: 0)
                NumericStepperRow(label: "Weight", value: $weight, unit: "kg", range: 40...180, step: 0.1, decimals: 1)
            }
        } cta: {
            EvolvPrimaryButton(title: "Continue", icon: "arrow.right") {
                app.profile.heightCm = height
                app.profile.weightKg = weight
                onContinue()
            }
        }
    }
}

// MARK: - Experience

private struct ExperienceView: View {
    @Environment(AppState.self) private var app
    let onContinue: () -> Void
    @State private var selected: Experience = .intermediate

    var body: some View {
        OnboardingScaffold(
            kicker: "Step 3 of 4",
            title: "Training experience",
            subtitle: "We calibrate expected change rates to your level."
        ) {
            VStack(spacing: 12) {
                ForEach(Experience.allCases) { e in
                    SelectableRow(
                        icon: e == .beginner ? "leaf.fill" : e == .intermediate ? "bolt.fill" : "flame.fill",
                        title: e.rawValue,
                        subtitle: e.subtitle,
                        selected: selected == e
                    ) { selected = e }
                }
            }
        } cta: {
            EvolvPrimaryButton(title: "Continue", icon: "arrow.right") {
                app.profile.experience = selected
                onContinue()
            }
        }
    }
}

// MARK: - Measurements (optional)

private struct MeasurementsView: View {
    @Environment(AppState.self) private var app
    let onContinue: () -> Void

    // Use optional values so users can choose to fill only some.
    @State private var arms: Double = 36
    @State private var chest: Double = 100
    @State private var waist: Double = 80
    @State private var shoulders: Double = 120
    @State private var thighs: Double = 58

    @State private var armsOn = false
    @State private var chestOn = false
    @State private var waistOn = false
    @State private var shouldersOn = false
    @State private var thighsOn = false

    @State private var showOptional = false
    @State private var guidance: MeasurementGuide? = nil

    var body: some View {
        OnboardingScaffold(
            kicker: "Optional — improves accuracy",
            title: "Add starting measurements",
            subtitle: "All optional. Skip any you don't have a tape for. Consistency matters more than precision.",
            showSkip: true,
            onSkip: onContinue
        ) {
            VStack(spacing: 12) {
                MeasurementRow(
                    label: "Arms", value: $arms, enabled: $armsOn,
                    unit: "cm", range: 25...60, step: 0.5,
                    onHelp: { guidance = .arms }
                )
                MeasurementRow(
                    label: "Chest", value: $chest, enabled: $chestOn,
                    unit: "cm", range: 70...160, step: 0.5,
                    onHelp: { guidance = .chest }
                )
                MeasurementRow(
                    label: "Waist", value: $waist, enabled: $waistOn,
                    unit: "cm", range: 55...140, step: 0.5,
                    onHelp: { guidance = .waist }
                )

                Button {
                    withAnimation(.spring(response: 0.35)) { showOptional.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showOptional ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                        Text(showOptional ? "Hide additional" : "Add shoulders & thighs")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(EvolvTheme.accent)
                    .padding(.top, 2)
                }

                if showOptional {
                    MeasurementRow(
                        label: "Shoulders", value: $shoulders, enabled: $shouldersOn,
                        unit: "cm", range: 80...160, step: 0.5,
                        onHelp: { guidance = .shoulders }
                    )
                    MeasurementRow(
                        label: "Thighs", value: $thighs, enabled: $thighsOn,
                        unit: "cm", range: 35...90, step: 0.5,
                        onHelp: { guidance = .thighs }
                    )
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(EvolvTheme.textFaint)
                        .font(.system(size: 12))
                    Text("Estimated changes are directional, not medical-grade. You can add or update measurements anytime.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(EvolvTheme.textFaint)
                        .lineSpacing(2)
                }
                .padding(.top, 8)
                .padding(.horizontal, 4)
            }
        } cta: {
            EvolvPrimaryButton(title: anyEnabled ? "Save measurements" : "Continue without measurements", icon: "arrow.right") {
                if armsOn { app.profile.arms = arms }
                if chestOn { app.profile.chest = chest }
                if waistOn { app.profile.waist = waist }
                if shouldersOn { app.profile.shoulders = shoulders }
                if thighsOn { app.profile.thighs = thighs }
                onContinue()
            }
        }
        .sheet(item: $guidance) { g in
            MeasurementGuideSheet(guide: g)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(EvolvTheme.background)
        }
    }

    private var anyEnabled: Bool {
        armsOn || chestOn || waistOn || shouldersOn || thighsOn
    }
}

// MARK: - Measurement row (stepper + editable + help)

private struct MeasurementRow: View {
    let label: String
    @Binding var value: Double
    @Binding var enabled: Bool
    let unit: String
    let range: ClosedRange<Double>
    let step: Double
    let onHelp: () -> Void

    @FocusState private var focused: Bool
    @State private var text: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(label)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(enabled ? EvolvTheme.text : EvolvTheme.textMuted)

                Button(action: onHelp) {
                    HStack(spacing: 3) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 11, weight: .semibold))
                        Text("How?")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(EvolvTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(EvolvTheme.accentDim))
                }
                .buttonStyle(.plain)

                Spacer()

                if enabled {
                    stepperControls
                } else {
                    Button("Add") {
                        withAnimation(.easeInOut(duration: 0.2)) { enabled = true }
                        syncText()
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(EvolvTheme.accentDim))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(EvolvTheme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(enabled ? EvolvTheme.accent.opacity(0.4) : EvolvTheme.stroke, lineWidth: 1)
                }
        }
        .onAppear(perform: syncText)
        .onChange(of: value) { _, _ in syncText() }
    }

    @ViewBuilder
    private var stepperControls: some View {
        HStack(spacing: 0) {
            controlButton(systemName: "minus") {
                let next = max(range.lowerBound, value - step)
                value = roundedValue(next)
            }

            ZStack {
                TextField("", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                    .monospacedDigit()
                    .frame(width: 64)
                    .onSubmit { commitText() }
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused { commitText() }
                    }
            }

            Text(unit)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(EvolvTheme.textFaint)
                .padding(.trailing, 4)

            controlButton(systemName: "plus") {
                let next = min(range.upperBound, value + step)
                value = roundedValue(next)
            }
        }
    }

    private func controlButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(EvolvTheme.text)
                .frame(width: 32, height: 32)
                .background(Circle().fill(EvolvTheme.background.opacity(0.7)))
                .overlay(Circle().stroke(EvolvTheme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func syncText() {
        text = format(value)
    }

    private func commitText() {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        if let parsed = Double(normalized) {
            value = roundedValue(min(max(parsed, range.lowerBound), range.upperBound))
        }
        syncText()
    }

    private func roundedValue(_ v: Double) -> Double {
        (v / step).rounded() * step
    }

    private func format(_ v: Double) -> String {
        step < 1 ? String(format: "%.1f", v) : String(format: "%.0f", v)
    }
}

// MARK: - Measurement guidance

private enum MeasurementGuide: String, Identifiable {
    case arms, chest, waist, shoulders, thighs
    var id: String { rawValue }

    var title: String {
        switch self {
        case .arms: "How to measure arms"
        case .chest: "How to measure chest"
        case .waist: "How to measure waist"
        case .shoulders: "How to measure shoulders"
        case .thighs: "How to measure thighs"
        }
    }

    var instruction: String {
        switch self {
        case .arms: "Measure around the widest part of your relaxed upper arm."
        case .chest: "Measure around the fullest part of your chest while relaxed."
        case .waist: "Measure around your natural waist, near the belly button."
        case .shoulders: "Measure around the widest part of your shoulders."
        case .thighs: "Measure around the widest part of your upper thigh."
        }
    }

    /// Tape style and posture cues — keep neutral, not gym-bro.
    var posture: String {
        switch self {
        case .arms: "Arm hanging naturally at your side. Tape snug, not tight. Do not flex."
        case .chest: "Standing tall, arms relaxed. Breathe normally — don't inhale fully."
        case .waist: "Stand relaxed. Don't suck in or push out. Tape parallel to the floor."
        case .shoulders: "Arms relaxed at your sides. Tape level all the way around."
        case .thighs: "Stand with weight even on both legs. Tape horizontal across the upper thigh."
        }
    }
}

private struct MeasurementGuideSheet: View {
    let guide: MeasurementGuide

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("HOW TO MEASURE")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(EvolvTheme.accent)
                Text(guide.title)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 18)

            // Anatomically-clear illustration
            HStack {
                Spacer()
                MeasurementIllustration(guide: guide)
                    .frame(width: 180, height: 200)
                Spacer()
            }
            .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 14) {
                Text(guide.instruction)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                    .lineSpacing(3)

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "figure.stand")
                        .foregroundStyle(EvolvTheme.accent)
                        .font(.system(size: 13))
                        .frame(width: 18, alignment: .center)
                    Text(guide.posture)
                        .font(.system(size: 13.5, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                        .lineSpacing(2)
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "repeat")
                        .foregroundStyle(EvolvTheme.accent)
                        .font(.system(size: 13))
                        .frame(width: 18, alignment: .center)
                    Text("Always measure the same way each time. Consistency matters more than precision.")
                        .font(.system(size: 13.5, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                        .lineSpacing(2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }
}

// MARK: - Measurement illustrations
//
// Each guide gets its own purpose-built drawing so the body part being measured
// is unambiguous. Tape is rendered as two arcs: a dashed back-half (behind body)
// and a solid mint front-half — communicating wrap-around circumference.

private struct MeasurementIllustration: View {
    let guide: MeasurementGuide

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                switch guide {
                case .arms:      ArmsIllustration(size: size)
                case .chest:     ChestIllustration(size: size)
                case .waist:     WaistIllustration(size: size)
                case .shoulders: ShouldersIllustration(size: size)
                case .thighs:    ThighsIllustration(size: size)
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }
}

// Shared visual tokens
private enum IllustrationStyle {
    static let bodyStroke = EvolvTheme.text.opacity(0.55)
    static let bodyLine: CGFloat = 1.6
    static let tapeFront = EvolvTheme.accent
    static let tapeBack = EvolvTheme.accent.opacity(0.45)
    static let tapeWidth: CGFloat = 2.4
    static let backDash: [CGFloat] = [3, 3]

    static var bodyStyle: StrokeStyle { StrokeStyle(lineWidth: bodyLine, lineCap: .round, lineJoin: .round) }
    static var tapeFrontStyle: StrokeStyle { StrokeStyle(lineWidth: tapeWidth, lineCap: .round) }
    static var tapeBackStyle: StrokeStyle { StrokeStyle(lineWidth: tapeWidth - 0.4, lineCap: .round, dash: backDash) }
}

/// Reusable tape ellipse drawn as wrap-around: dashed back arc behind body, solid front arc on top.
private struct WrapTape: View {
    /// Center of the ellipse in absolute points.
    var center: CGPoint
    var radiusX: CGFloat
    var radiusY: CGFloat
    /// If true, draws the dashed back half. If false, draws the solid front half.
    var back: Bool

    var body: some View {
        Path { p in
            let rect = CGRect(x: center.x - radiusX, y: center.y - radiusY,
                              width: radiusX * 2, height: radiusY * 2)
            if back {
                p.move(to: CGPoint(x: rect.minX, y: rect.midY))
                p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
                               control: CGPoint(x: rect.midX, y: rect.minY))
            } else {
                p.move(to: CGPoint(x: rect.minX, y: rect.midY))
                p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
                               control: CGPoint(x: rect.midX, y: rect.maxY))
            }
        }
        .stroke(back ? IllustrationStyle.tapeBack : IllustrationStyle.tapeFront,
                style: back ? IllustrationStyle.tapeBackStyle : IllustrationStyle.tapeFrontStyle)
        .shadow(color: back ? .clear : EvolvTheme.accent.opacity(0.45), radius: back ? 0 : 5)
    }
}

// MARK: Arms — angled arm out from torso, tape wraps the bicep only

private struct ArmsIllustration: View {
    let size: CGSize

    var body: some View {
        let w = size.width, h = size.height
        let cx = w * 0.42
        // Bicep tape center (on the extended right arm)
        let bicepCenter = CGPoint(x: w * 0.78, y: h * 0.42)
        let bicepRX: CGFloat = w * 0.085
        let bicepRY: CGFloat = h * 0.028

        ZStack {
            // Head
            Circle()
                .stroke(IllustrationStyle.bodyStroke, style: IllustrationStyle.bodyStyle)
                .frame(width: w * 0.18, height: w * 0.18)
                .position(x: cx, y: h * 0.13)

            // Torso (3/4 view, suggests one arm out)
            Path { p in
                // Neck
                p.move(to: CGPoint(x: cx - w * 0.04, y: h * 0.21))
                p.addLine(to: CGPoint(x: cx - w * 0.04, y: h * 0.25))
                p.move(to: CGPoint(x: cx + w * 0.04, y: h * 0.21))
                p.addLine(to: CGPoint(x: cx + w * 0.04, y: h * 0.25))

                // Shoulders
                p.move(to: CGPoint(x: cx - w * 0.18, y: h * 0.27))
                p.addQuadCurve(to: CGPoint(x: cx + w * 0.22, y: h * 0.27),
                               control: CGPoint(x: cx, y: h * 0.24))

                // Torso sides
                p.move(to: CGPoint(x: cx - w * 0.18, y: h * 0.27))
                p.addQuadCurve(to: CGPoint(x: cx - w * 0.16, y: h * 0.62),
                               control: CGPoint(x: cx - w * 0.20, y: h * 0.46))
                p.move(to: CGPoint(x: cx + w * 0.22, y: h * 0.27))
                p.addQuadCurve(to: CGPoint(x: cx + w * 0.20, y: h * 0.62),
                               control: CGPoint(x: cx + w * 0.24, y: h * 0.46))

                // Waistline base
                p.move(to: CGPoint(x: cx - w * 0.16, y: h * 0.62))
                p.addLine(to: CGPoint(x: cx + w * 0.20, y: h * 0.62))

                // Left arm hanging
                p.move(to: CGPoint(x: cx - w * 0.18, y: h * 0.28))
                p.addQuadCurve(to: CGPoint(x: cx - w * 0.21, y: h * 0.58),
                               control: CGPoint(x: cx - w * 0.23, y: h * 0.42))

                // Right arm — angled out from body for clarity
                // Upper arm
                p.move(to: CGPoint(x: cx + w * 0.22, y: h * 0.27))
                p.addQuadCurve(to: CGPoint(x: w * 0.86, y: h * 0.45),
                               control: CGPoint(x: w * 0.70, y: h * 0.30))
                // Underside of upper arm
                p.move(to: CGPoint(x: cx + w * 0.24, y: h * 0.34))
                p.addQuadCurve(to: CGPoint(x: w * 0.82, y: h * 0.50),
                               control: CGPoint(x: w * 0.66, y: h * 0.40))
                // Forearm down
                p.move(to: CGPoint(x: w * 0.86, y: h * 0.45))
                p.addQuadCurve(to: CGPoint(x: w * 0.90, y: h * 0.78),
                               control: CGPoint(x: w * 0.94, y: h * 0.62))
                p.move(to: CGPoint(x: w * 0.82, y: h * 0.50))
                p.addQuadCurve(to: CGPoint(x: w * 0.86, y: h * 0.78),
                               control: CGPoint(x: w * 0.90, y: h * 0.64))
            }
            .stroke(IllustrationStyle.bodyStroke, style: IllustrationStyle.bodyStyle)

            // Tape: back dashed first, then front solid on top
            WrapTape(center: bicepCenter, radiusX: bicepRX, radiusY: bicepRY, back: true)
            WrapTape(center: bicepCenter, radiusX: bicepRX, radiusY: bicepRY, back: false)
        }
    }
}

// MARK: Chest — front-facing torso, tape across nipple line

private struct ChestIllustration: View {
    let size: CGSize

    var body: some View {
        let w = size.width, h = size.height
        let cx = w * 0.5
        let chestCenter = CGPoint(x: cx, y: h * 0.36)
        let chestRX: CGFloat = w * 0.26
        let chestRY: CGFloat = h * 0.035

        ZStack {
            Circle()
                .stroke(IllustrationStyle.bodyStroke, style: IllustrationStyle.bodyStyle)
                .frame(width: w * 0.18, height: w * 0.18)
                .position(x: cx, y: h * 0.13)

            Path { p in
                // Neck
                p.move(to: CGPoint(x: cx - w * 0.05, y: h * 0.21))
                p.addLine(to: CGPoint(x: cx - w * 0.05, y: h * 0.25))
                p.move(to: CGPoint(x: cx + w * 0.05, y: h * 0.21))
                p.addLine(to: CGPoint(x: cx + w * 0.05, y: h * 0.25))

                // Shoulders / traps
                p.move(to: CGPoint(x: cx - w * 0.28, y: h * 0.27))
                p.addQuadCurve(to: CGPoint(x: cx + w * 0.28, y: h * 0.27),
                               control: CGPoint(x: cx, y: h * 0.23))

                // Torso sides — wider at chest, narrowing to waist
                p.move(to: CGPoint(x: cx - w * 0.28, y: h * 0.27))
                p.addQuadCurve(to: CGPoint(x: cx - w * 0.20, y: h * 0.62),
                               control: CGPoint(x: cx - w * 0.30, y: h * 0.42))
                p.move(to: CGPoint(x: cx + w * 0.28, y: h * 0.27))
                p.addQuadCurve(to: CGPoint(x: cx + w * 0.20, y: h * 0.62),
                               control: CGPoint(x: cx + w * 0.30, y: h * 0.42))

                // Waist bottom
                p.move(to: CGPoint(x: cx - w * 0.20, y: h * 0.62))
                p.addLine(to: CGPoint(x: cx + w * 0.20, y: h * 0.62))

                // Subtle pec center line
                p.move(to: CGPoint(x: cx, y: h * 0.30))
                p.addLine(to: CGPoint(x: cx, y: h * 0.46))

                // Arms relaxed at sides
                p.move(to: CGPoint(x: cx - w * 0.28, y: h * 0.28))
                p.addQuadCurve(to: CGPoint(x: cx - w * 0.32, y: h * 0.62),
                               control: CGPoint(x: cx - w * 0.34, y: h * 0.44))
                p.move(to: CGPoint(x: cx + w * 0.28, y: h * 0.28))
                p.addQuadCurve(to: CGPoint(x: cx + w * 0.32, y: h * 0.62),
                               control: CGPoint(x: cx + w * 0.34, y: h * 0.44))
            }
            .stroke(IllustrationStyle.bodyStroke, style: IllustrationStyle.bodyStyle)

            WrapTape(center: chestCenter, radiusX: chestRX, radiusY: chestRY, back: true)
            WrapTape(center: chestCenter, radiusX: chestRX, radiusY: chestRY, back: false)
        }
    }
}

// MARK: Waist — clear hourglass narrowing, tape at narrowest

private struct WaistIllustration: View {
    let size: CGSize

    var body: some View {
        let w = size.width, h = size.height
        let cx = w * 0.5
        let waistCenter = CGPoint(x: cx, y: h * 0.52)
        let waistRX: CGFloat = w * 0.18
        let waistRY: CGFloat = h * 0.03

        ZStack {
            Circle()
                .stroke(IllustrationStyle.bodyStroke, style: IllustrationStyle.bodyStyle)
                .frame(width: w * 0.18, height: w * 0.18)
                .position(x: cx, y: h * 0.13)

            Path { p in
                // Neck
                p.move(to: CGPoint(x: cx - w * 0.05, y: h * 0.21))
                p.addLine(to: CGPoint(x: cx - w * 0.05, y: h * 0.25))
                p.move(to: CGPoint(x: cx + w * 0.05, y: h * 0.21))
                p.addLine(to: CGPoint(x: cx + w * 0.05, y: h * 0.25))

                // Shoulders
                p.move(to: CGPoint(x: cx - w * 0.27, y: h * 0.27))
                p.addQuadCurve(to: CGPoint(x: cx + w * 0.27, y: h * 0.27),
                               control: CGPoint(x: cx, y: h * 0.23))

                // Hourglass torso — wide chest, narrow waist, wider hips
                p.move(to: CGPoint(x: cx - w * 0.27, y: h * 0.27))
                p.addCurve(to: CGPoint(x: cx - w * 0.17, y: h * 0.52),
                           control1: CGPoint(x: cx - w * 0.28, y: h * 0.36),
                           control2: CGPoint(x: cx - w * 0.17, y: h * 0.45))
                p.addCurve(to: CGPoint(x: cx - w * 0.24, y: h * 0.74),
                           control1: CGPoint(x: cx - w * 0.17, y: h * 0.60),
                           control2: CGPoint(x: cx - w * 0.24, y: h * 0.66))

                p.move(to: CGPoint(x: cx + w * 0.27, y: h * 0.27))
                p.addCurve(to: CGPoint(x: cx + w * 0.17, y: h * 0.52),
                           control1: CGPoint(x: cx + w * 0.28, y: h * 0.36),
                           control2: CGPoint(x: cx + w * 0.17, y: h * 0.45))
                p.addCurve(to: CGPoint(x: cx + w * 0.24, y: h * 0.74),
                           control1: CGPoint(x: cx + w * 0.17, y: h * 0.60),
                           control2: CGPoint(x: cx + w * 0.24, y: h * 0.66))

                // Hip bottom
                p.move(to: CGPoint(x: cx - w * 0.24, y: h * 0.74))
                p.addLine(to: CGPoint(x: cx + w * 0.24, y: h * 0.74))

                // Belly button cue
                p.addEllipse(in: CGRect(x: cx - 1.2, y: h * 0.55, width: 2.4, height: 2.4))

                // Arms
                p.move(to: CGPoint(x: cx - w * 0.27, y: h * 0.28))
                p.addQuadCurve(to: CGPoint(x: cx - w * 0.30, y: h * 0.58),
                               control: CGPoint(x: cx - w * 0.33, y: h * 0.42))
                p.move(to: CGPoint(x: cx + w * 0.27, y: h * 0.28))
                p.addQuadCurve(to: CGPoint(x: cx + w * 0.30, y: h * 0.58),
                               control: CGPoint(x: cx + w * 0.33, y: h * 0.42))
            }
            .stroke(IllustrationStyle.bodyStroke, style: IllustrationStyle.bodyStyle)

            WrapTape(center: waistCenter, radiusX: waistRX, radiusY: waistRY, back: true)
            WrapTape(center: waistCenter, radiusX: waistRX, radiusY: waistRY, back: false)
        }
    }
}

// MARK: Shoulders — back/3-quarter view, tape across deltoids

private struct ShouldersIllustration: View {
    let size: CGSize

    var body: some View {
        let w = size.width, h = size.height
        let cx = w * 0.5
        // Tape sits right across the deltoid widest point
        let shoulderCenter = CGPoint(x: cx, y: h * 0.30)
        let shoulderRX: CGFloat = w * 0.36
        let shoulderRY: CGFloat = h * 0.045

        ZStack {
            // Head — back of head view (no face cues, just a circle slightly smaller)
            Circle()
                .stroke(IllustrationStyle.bodyStroke, style: IllustrationStyle.bodyStyle)
                .frame(width: w * 0.16, height: w * 0.16)
                .position(x: cx, y: h * 0.13)

            Path { p in
                // Trap line down from neck to shoulders — broader deltoid silhouette
                p.move(to: CGPoint(x: cx - w * 0.06, y: h * 0.21))
                p.addQuadCurve(to: CGPoint(x: cx - w * 0.34, y: h * 0.32),
                               control: CGPoint(x: cx - w * 0.18, y: h * 0.22))
                p.move(to: CGPoint(x: cx + w * 0.06, y: h * 0.21))
                p.addQuadCurve(to: CGPoint(x: cx + w * 0.34, y: h * 0.32),
                               control: CGPoint(x: cx + w * 0.18, y: h * 0.22))

                // Deltoid caps (subtle round to communicate "widest point")
                p.addArc(center: CGPoint(x: cx - w * 0.32, y: h * 0.31),
                         radius: w * 0.05,
                         startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                p.addArc(center: CGPoint(x: cx + w * 0.32, y: h * 0.31),
                         radius: w * 0.05,
                         startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)

                // Upper back contour to waist
                p.move(to: CGPoint(x: cx - w * 0.30, y: h * 0.34))
                p.addQuadCurve(to: CGPoint(x: cx - w * 0.20, y: h * 0.66),
                               control: CGPoint(x: cx - w * 0.28, y: h * 0.50))
                p.move(to: CGPoint(x: cx + w * 0.30, y: h * 0.34))
                p.addQuadCurve(to: CGPoint(x: cx + w * 0.20, y: h * 0.66),
                               control: CGPoint(x: cx + w * 0.28, y: h * 0.50))

                // Waist
                p.move(to: CGPoint(x: cx - w * 0.20, y: h * 0.66))
                p.addLine(to: CGPoint(x: cx + w * 0.20, y: h * 0.66))

                // Spine center line — communicates back view
                p.move(to: CGPoint(x: cx, y: h * 0.34))
                p.addLine(to: CGPoint(x: cx, y: h * 0.62))

                // Arms hanging
                p.move(to: CGPoint(x: cx - w * 0.36, y: h * 0.34))
                p.addQuadCurve(to: CGPoint(x: cx - w * 0.34, y: h * 0.62),
                               control: CGPoint(x: cx - w * 0.40, y: h * 0.48))
                p.move(to: CGPoint(x: cx + w * 0.36, y: h * 0.34))
                p.addQuadCurve(to: CGPoint(x: cx + w * 0.34, y: h * 0.62),
                               control: CGPoint(x: cx + w * 0.40, y: h * 0.48))
            }
            .stroke(IllustrationStyle.bodyStroke, style: IllustrationStyle.bodyStyle)

            // Tape — slightly larger ellipse to look like circumference, not a flat line
            WrapTape(center: shoulderCenter, radiusX: shoulderRX, radiusY: shoulderRY, back: true)
            WrapTape(center: shoulderCenter, radiusX: shoulderRX, radiusY: shoulderRY, back: false)
        }
    }
}

// MARK: Thighs — single leg forward, tape around upper thigh

private struct ThighsIllustration: View {
    let size: CGSize

    var body: some View {
        let w = size.width, h = size.height
        let cx = w * 0.5
        // Tape on the right leg upper thigh
        let thighCenter = CGPoint(x: cx + w * 0.13, y: h * 0.62)
        let thighRX: CGFloat = w * 0.10
        let thighRY: CGFloat = h * 0.028

        ZStack {
            Circle()
                .stroke(IllustrationStyle.bodyStroke, style: IllustrationStyle.bodyStyle)
                .frame(width: w * 0.14, height: w * 0.14)
                .position(x: cx, y: h * 0.10)

            Path { p in
                // Neck
                p.move(to: CGPoint(x: cx - w * 0.04, y: h * 0.16))
                p.addLine(to: CGPoint(x: cx - w * 0.04, y: h * 0.19))
                p.move(to: CGPoint(x: cx + w * 0.04, y: h * 0.16))
                p.addLine(to: CGPoint(x: cx + w * 0.04, y: h * 0.19))

                // Shoulders
                p.move(to: CGPoint(x: cx - w * 0.20, y: h * 0.21))
                p.addQuadCurve(to: CGPoint(x: cx + w * 0.20, y: h * 0.21),
                               control: CGPoint(x: cx, y: h * 0.185))

                // Compact torso
                p.move(to: CGPoint(x: cx - w * 0.20, y: h * 0.21))
                p.addQuadCurve(to: CGPoint(x: cx - w * 0.17, y: h * 0.48),
                               control: CGPoint(x: cx - w * 0.22, y: h * 0.34))
                p.move(to: CGPoint(x: cx + w * 0.20, y: h * 0.21))
                p.addQuadCurve(to: CGPoint(x: cx + w * 0.17, y: h * 0.48),
                               control: CGPoint(x: cx + w * 0.22, y: h * 0.34))

                // Hip line (clearly separates torso from legs)
                p.move(to: CGPoint(x: cx - w * 0.20, y: h * 0.50))
                p.addQuadCurve(to: CGPoint(x: cx + w * 0.20, y: h * 0.50),
                               control: CGPoint(x: cx, y: h * 0.53))
                p.move(to: CGPoint(x: cx - w * 0.17, y: h * 0.48))
                p.addLine(to: CGPoint(x: cx - w * 0.20, y: h * 0.50))
                p.move(to: CGPoint(x: cx + w * 0.17, y: h * 0.48))
                p.addLine(to: CGPoint(x: cx + w * 0.20, y: h * 0.50))

                // LEFT leg — slightly behind, dimmer feel by drawing thinner via shorter strokes
                p.move(to: CGPoint(x: cx - w * 0.18, y: h * 0.52))
                p.addQuadCurve(to: CGPoint(x: cx - w * 0.16, y: h * 0.95),
                               control: CGPoint(x: cx - w * 0.18, y: h * 0.74))
                p.move(to: CGPoint(x: cx - w * 0.04, y: h * 0.54))
                p.addQuadCurve(to: CGPoint(x: cx - w * 0.07, y: h * 0.95),
                               control: CGPoint(x: cx - w * 0.05, y: h * 0.74))

                // RIGHT leg — the measured one, prominent and clearly separated
                // Outer thigh
                p.move(to: CGPoint(x: cx + w * 0.20, y: h * 0.52))
                p.addQuadCurve(to: CGPoint(x: cx + w * 0.22, y: h * 0.95),
                               control: CGPoint(x: cx + w * 0.24, y: h * 0.76))
                // Inner thigh — clearly offset from left leg for separation
                p.move(to: CGPoint(x: cx + w * 0.06, y: h * 0.55))
                p.addQuadCurve(to: CGPoint(x: cx + w * 0.09, y: h * 0.95),
                               control: CGPoint(x: cx + w * 0.07, y: h * 0.76))

                // Subtle crotch separator
                p.move(to: CGPoint(x: cx, y: h * 0.52))
                p.addLine(to: CGPoint(x: cx + w * 0.005, y: h * 0.56))

                // Arms (short, at sides) for context
                p.move(to: CGPoint(x: cx - w * 0.20, y: h * 0.22))
                p.addQuadCurve(to: CGPoint(x: cx - w * 0.23, y: h * 0.48),
                               control: CGPoint(x: cx - w * 0.25, y: h * 0.34))
                p.move(to: CGPoint(x: cx + w * 0.20, y: h * 0.22))
                p.addQuadCurve(to: CGPoint(x: cx + w * 0.27, y: h * 0.48),
                               control: CGPoint(x: cx + w * 0.28, y: h * 0.34))
            }
            .stroke(IllustrationStyle.bodyStroke, style: IllustrationStyle.bodyStyle)

            WrapTape(center: thighCenter, radiusX: thighRX, radiusY: thighRY, back: true)
            WrapTape(center: thighCenter, radiusX: thighRX, radiusY: thighRY, back: false)
        }
    }
}

// MARK: - Cadence

private struct CadenceView: View {
    @Environment(AppState.self) private var app
    let onContinue: () -> Void
    @State private var selected: Cadence = .weekly
    @State private var weekdays: [Int] = [2]
    @State private var dayOfMonth: Int = 1
    @State private var remindersEnabled: Bool = false
    @State private var reminderTime: Date = Calendar.current.date(
        bySettingHour: 20, minute: 0, second: 0, of: Date()
    ) ?? Date()
    @State private var permissionDenied: Bool = false

    var body: some View {
        OnboardingScaffold(
            kicker: "Step 4 of 4",
            title: "How often will you scan?",
            subtitle: "Weekly is recommended — meaningful change shows up between 4–8 weeks."
        ) {
            VStack(spacing: 12) {
                ForEach(Cadence.allCases) { c in
                    SelectableRow(
                        icon: "calendar",
                        title: c.rawValue,
                        subtitle: c.description,
                        selected: selected == c,
                        trailing: c.isRecommended ? "Recommended" : nil
                    ) {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            selected = c
                            normalizeWeekdays()
                        }
                    }
                }

                scheduleCard
                    .transition(.opacity.combined(with: .move(edge: .top)))

                reminderCard
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.3), value: selected)
            .animation(.easeInOut(duration: 0.25), value: remindersEnabled)
        } cta: {
            EvolvPrimaryButton(title: "Review baseline", icon: "arrow.right") {
                normalizeWeekdays()
                app.profile.cadence = selected
                app.profile.scanWeekdays = weekdays
                app.profile.scanWeekday = weekdays.first ?? 2
                app.profile.scanDayOfMonth = dayOfMonth
                app.profile.remindersEnabled = remindersEnabled
                let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
                app.profile.reminderHour = comps.hour ?? 20
                app.profile.reminderMinute = comps.minute ?? 0
                app.save() // triggers NotificationManager.sync
                onContinue()
            }
        }
    }

    private func normalizeWeekdays() {
        switch selected {
        case .daily:
            weekdays = [1,2,3,4,5,6,7]
        case .weekly, .monthly:
            if weekdays.isEmpty { weekdays = [2] }
            else { weekdays = [weekdays.first!] }
        case .biweekly:
            if weekdays.isEmpty { weekdays = [2] }
            weekdays = Array(weekdays.prefix(2))
        }
    }

    // MARK: Schedule

    @ViewBuilder
    private var scheduleCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(EvolvTheme.accent)
                        .font(.system(size: 13))
                    Text(scheduleHeader)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(EvolvTheme.textFaint)
                }

                if selected == .monthly {
                    monthlyPicker
                } else {
                    weekdayPicker
                }

                Text(scheduleHint)
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
                    .lineSpacing(2)
            }
        }
    }

    private var scheduleHeader: String {
        switch selected {
        case .daily:    return "SCAN DAYS"
        case .weekly:   return "PREFERRED WEEKDAY"
        case .biweekly: return "PREFERRED WEEKDAYS"
        case .monthly:  return "PREFERRED DAY OF MONTH"
        }
    }

    private var scheduleHint: String {
        switch selected {
        case .daily:    return "Every day at your chosen reminder time."
        case .biweekly: return "Pick up to two days — Evolv schedules them every other week."
        case .monthly:  return "We'll suggest a scan around this day each month."
        case .weekly:   return "Same day each week keeps lighting and timing consistent."
        }
    }

    private let weekdaySymbols: [(Int, String)] = [
        (1, "S"), (2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S")
    ]

    private var weekdayPicker: some View {
        HStack(spacing: 6) {
            ForEach(weekdaySymbols, id: \.0) { day in
                let isOn = weekdays.contains(day.0)
                let locked = selected == .daily
                Button {
                    handleWeekdayTap(day.0)
                } label: {
                    Text(day.1)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(isOn ? EvolvTheme.background : EvolvTheme.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background {
                            Capsule()
                                .fill(isOn ? EvolvTheme.accent.opacity(locked ? 0.85 : 1) : EvolvTheme.text.opacity(0.06))
                        }
                        .overlay(
                            Capsule().stroke(isOn ? .clear : EvolvTheme.text.opacity(0.10), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(locked)
            }
        }
    }

    private func handleWeekdayTap(_ wd: Int) {
        withAnimation(.easeInOut(duration: 0.18)) {
            switch selected {
            case .daily:
                return
            case .weekly, .monthly:
                weekdays = [wd]
            case .biweekly:
                if let idx = weekdays.firstIndex(of: wd) {
                    if weekdays.count > 1 { weekdays.remove(at: idx) }
                } else {
                    weekdays.append(wd)
                    if weekdays.count > 2 { weekdays.removeFirst() }
                }
            }
        }
    }

    private var monthlyPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Day")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
                Spacer()
                Text("\(dayOfMonth)")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                    .monospacedDigit()
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(1...28, id: \.self) { d in
                    let isOn = dayOfMonth == d
                    Button { withAnimation(.easeInOut(duration: 0.15)) { dayOfMonth = d } } label: {
                        Text("\(d)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(isOn ? EvolvTheme.background : EvolvTheme.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isOn ? EvolvTheme.accent : EvolvTheme.text.opacity(0.05))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Reminder

    private var reminderCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "bell")
                        .foregroundStyle(remindersEnabled ? EvolvTheme.accent : EvolvTheme.textMuted)
                        .font(.system(size: 15))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Want a reminder on your scan day?")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(EvolvTheme.text)
                        Text(reminderSubtitle)
                            .font(.system(size: 12.5, design: .rounded))
                            .foregroundStyle(EvolvTheme.textMuted)
                    }
                    Spacer()
                    Toggle("", isOn: $remindersEnabled)
                        .labelsHidden()
                        .tint(EvolvTheme.accent)
                        .onChange(of: remindersEnabled) { _, newValue in
                            handleReminderToggle(newValue)
                        }
                }

                if remindersEnabled {
                    HStack {
                        Text("Time")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(EvolvTheme.textMuted)
                        Spacer()
                        DatePicker("", selection: $reminderTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .tint(EvolvTheme.accent)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if permissionDenied {
                    Text("Notifications are disabled in iOS Settings. You can enable them anytime in Settings → Evolv → Notifications.")
                        .font(.system(size: 11.5, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                        .lineSpacing(2)
                }
            }
        }
    }

    private var reminderSubtitle: String {
        if permissionDenied { return "Notifications disabled in iOS Settings." }
        return "Optional. Helps you stay consistent."
    }

    private func handleReminderToggle(_ on: Bool) {
        guard on else {
            permissionDenied = false
            return
        }
        Task {
            let status = await NotificationManager.authorizationStatus()
            if status == .notDetermined {
                let granted = await NotificationManager.requestPermission()
                await MainActor.run {
                    if !granted {
                        remindersEnabled = false
                        permissionDenied = true
                    } else {
                        permissionDenied = false
                    }
                }
            } else if status == .denied {
                await MainActor.run {
                    remindersEnabled = false
                    permissionDenied = true
                }
            } else {
                await MainActor.run { permissionDenied = false }
            }
        }
    }
}

// MARK: - Baseline snapshot reveal (honest, data-driven)

private struct BaselineSnapshotView: View {
    @Environment(AppState.self) private var app
    let onContinue: () -> Void
    @State private var revealed = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            ZStack {
                Circle()
                    .fill(EvolvTheme.accent.opacity(0.12))
                    .frame(width: 240, height: 240)
                    .blur(radius: 36)
                    .opacity(revealed ? 1 : 0)
                Circle()
                    .stroke(EvolvTheme.accent.opacity(0.45), lineWidth: 1)
                    .frame(width: 168, height: 168)
                    .scaleEffect(revealed ? 1 : 0.7)
                    .opacity(revealed ? 1 : 0)
                Circle()
                    .stroke(EvolvTheme.accent.opacity(0.18), lineWidth: 1)
                    .frame(width: 220, height: 220)
                    .scaleEffect(revealed ? 1 : 0.7)
                    .opacity(revealed ? 1 : 0)
                Image(systemName: "checkmark")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(EvolvTheme.accent)
                    .opacity(revealed ? 1 : 0)
            }
            .animation(.easeOut(duration: 0.7), value: revealed)
            .padding(.bottom, 18)

            VStack(spacing: 10) {
                Text("BASELINE CAPTURED")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(EvolvTheme.accent)
                Text("You're set up.")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(EvolvTheme.text)
                Text("Evolv will compare every future scan against this starting point.")
                    .font(.system(size: 14, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(EvolvTheme.textMuted)
                    .padding(.horizontal, 28)
                    .lineSpacing(2)
            }
            .padding(.bottom, 22)

            // Real, data-driven readouts
            ScrollView {
                VStack(spacing: 12) {
                    confidenceCard
                    factsCard
                    notesCard
                }
                .padding(.horizontal, 20)
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 14)
                .animation(.easeOut(duration: 0.55).delay(0.25), value: revealed)
            }
            .scrollIndicators(.hidden)

            EvolvPrimaryButton(title: "Enter Evolv", icon: "arrow.right", action: onContinue)
                .padding(.horizontal, 28)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .opacity(revealed ? 1 : 0)
                .animation(.easeOut.delay(0.55), value: revealed)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { revealed = true }
        }
    }

    // MARK: Real confidence derivation

    private var confidence: BaselineConfidence {
        BaselineConfidence.derive(profile: app.profile, scans: app.scans)
    }

    private var confidenceCard: some View {
        let c = confidence
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: c.icon)
                        .foregroundStyle(c.tint)
                    Text("BASELINE CONFIDENCE")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(EvolvTheme.textFaint)
                    Spacer()
                    Text(c.label)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(c.tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(c.tint.opacity(0.15)))
                }
                Text(c.summary)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                    .lineSpacing(3)
                if !c.reasons.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(c.reasons, id: \.self) { reason in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 4))
                                    .foregroundStyle(EvolvTheme.textFaint)
                                    .padding(.top, 7)
                                Text(reason)
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundStyle(EvolvTheme.textMuted)
                                    .lineSpacing(2)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private var factsCard: some View {
        let p = app.profile
        let measurementCount = [p.arms, p.chest, p.waist, p.shoulders, p.thighs].compactMap { $0 }.count
        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("WHAT WE KNOW SO FAR")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(EvolvTheme.textFaint)
                factRow("Goal", value: p.goal.rawValue)
                factRow("Body", value: "\(Int(p.heightCm)) cm · \(formatWeight(p.weightKg)) kg")
                factRow("Experience", value: p.experience.rawValue)
                factRow("Cadence", value: p.cadence.rawValue)
                factRow("Measurements", value: measurementCount == 0 ? "None added" : "\(measurementCount) added")
            }
        }
    }

    private func factRow(_ key: String, value: String) -> some View {
        HStack {
            Text(key)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(EvolvTheme.textMuted)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(EvolvTheme.text)
                .monospacedDigit()
        }
    }

    private var notesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                noteRow(icon: "camera.viewfinder", text: "Your first scan will set the visual baseline Evolv compares against.")
                noteRow(icon: "ruler", text: app.profile.arms == nil && app.profile.chest == nil && app.profile.waist == nil
                        ? "Adding measurements later can improve progress estimates."
                        : "Future measurement entries will refine your estimated changes.")
                noteRow(icon: "calendar", text: "Tracking \(app.profile.cadence.rawValue.lowercased()) typically produces clearer long-term trends.")
            }
        }
    }

    private func noteRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(EvolvTheme.accent)
                .font(.system(size: 12))
                .frame(width: 16)
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(EvolvTheme.textMuted)
                .lineSpacing(2)
        }
    }

    private func formatWeight(_ w: Double) -> String {
        String(format: "%.1f", w)
    }
}

// MARK: - Baseline confidence derivation (real, not fake)

private struct BaselineConfidence {
    enum Level { case high, medium, low }
    let level: Level
    let summary: String
    let reasons: [String]

    var label: String {
        switch level {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }

    var icon: String {
        switch level {
        case .high: "checkmark.seal.fill"
        case .medium: "circle.lefthalf.filled"
        case .low: "exclamationmark.circle"
        }
    }

    var tint: Color {
        switch level {
        case .high: EvolvTheme.accent
        case .medium: EvolvTheme.text.opacity(0.85)
        case .low: Color(red: 0.95, green: 0.78, blue: 0.55)
        }
    }

    static func derive(profile: UserProfile, scans: [Scan]) -> BaselineConfidence {
        var reasons: [String] = []
        var score = 0

        // Profile completeness (height/weight are required and always present)
        score += 2

        // Measurements
        let m = [profile.arms, profile.chest, profile.waist, profile.shoulders, profile.thighs].compactMap { $0 }.count
        if m >= 3 { score += 2; reasons.append("Starting measurements added — change estimates will be sharper.") }
        else if m >= 1 { score += 1; reasons.append("Some measurements added. Adding the rest later will improve estimates.") }
        else { reasons.append("No measurements added yet — visual tracking will still work.") }

        // Photo scans (during onboarding there usually are none; that's expected)
        if let firstScan = scans.first {
            let required: Set<Pose> = Set(Pose.required)
            let covered = Set(firstScan.poses).intersection(required)
            if covered.count == required.count {
                score += 2
                reasons.append("All required scan angles captured (front, side, back).")
            } else if !covered.isEmpty {
                score += 1
                reasons.append("Some scan angles still missing — capture the remaining ones for stronger baseline.")
            }

            if firstScan.lightingScore < 60 {
                score -= 1
                reasons.append("Lighting in your baseline scan was uneven. Match it next time for sharper reads.")
            }
            if firstScan.framingScore < 60 {
                score -= 1
                reasons.append("Framing was slightly off. Same distance and phone height each time helps a lot.")
            }
        } else {
            reasons.append("No baseline photos yet. Your first scan from the home screen will lock that in.")
        }

        let level: Level
        let summary: String
        switch score {
        case 4...:
            level = .high
            summary = "Your baseline has been successfully captured with strong starting data."
        case 2...3:
            level = .medium
            summary = "Your baseline is captured. Accuracy will improve as you complete more of the setup."
        default:
            level = .low
            summary = "Your baseline is recorded, but some inputs are missing. Future scans will become more accurate as consistency improves."
        }

        return BaselineConfidence(level: level, summary: summary, reasons: reasons)
    }
}

// MARK: - Shared scaffold

private struct OnboardingScaffold<Content: View, CTA: View>: View {
    let kicker: String
    let title: String
    let subtitle: String
    var showSkip: Bool = false
    var onSkip: (() -> Void)? = nil
    @ViewBuilder var content: Content
    @ViewBuilder var cta: CTA

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(kicker)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(EvolvTheme.accent)
                Spacer()
                if showSkip, let onSkip {
                    Button("Skip", action: onSkip)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                Text(subtitle)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)
            .padding(.bottom, 24)

            ScrollView {
                content
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)

            cta
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
        }
    }
}

// MARK: - Selectable row

private struct SelectableRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let selected: Bool
    var trailing: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(selected ? EvolvTheme.accent : EvolvTheme.accentDim)
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .foregroundStyle(selected ? EvolvTheme.background : EvolvTheme.accent)
                        .font(.system(size: 16, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(EvolvTheme.text)
                        if let trailing {
                            Text(trailing)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(EvolvTheme.accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(EvolvTheme.accentDim))
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 12.5, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? EvolvTheme.accent : EvolvTheme.textFaint)
                    .font(.system(size: 20))
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(EvolvTheme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(selected ? EvolvTheme.accent.opacity(0.6) : EvolvTheme.stroke, lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Numeric stepper row (used for height/weight on Body Basics)

private struct NumericStepperRow: View {
    let label: String
    @Binding var value: Double
    let unit: String
    let range: ClosedRange<Double>
    let step: Double
    let decimals: Int

    @FocusState private var focused: Bool
    @State private var text: String = ""

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(EvolvTheme.text)
            Spacer()
            HStack(spacing: 0) {
                stepButton("minus") {
                    value = roundedValue(max(range.lowerBound, value - step))
                }
                TextField("", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                    .monospacedDigit()
                    .frame(width: 64)
                    .onSubmit { commit() }
                    .onChange(of: focused) { _, f in if !f { commit() } }
                Text(unit)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(EvolvTheme.textFaint)
                    .padding(.trailing, 4)
                stepButton("plus") {
                    value = roundedValue(min(range.upperBound, value + step))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(EvolvTheme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(EvolvTheme.stroke, lineWidth: 1)
                }
        }
        .onAppear { text = format(value) }
        .onChange(of: value) { _, v in text = format(v) }
    }

    private func stepButton(_ system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(EvolvTheme.text)
                .frame(width: 32, height: 32)
                .background(Circle().fill(EvolvTheme.background.opacity(0.7)))
                .overlay(Circle().stroke(EvolvTheme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func commit() {
        let n = text.replacingOccurrences(of: ",", with: ".")
        if let v = Double(n) {
            value = roundedValue(min(max(v, range.lowerBound), range.upperBound))
        }
        text = format(value)
    }

    private func roundedValue(_ v: Double) -> Double { (v / step).rounded() * step }
    private func format(_ v: Double) -> String { String(format: "%.\(decimals)f", v) }
}

#Preview {
    OnboardingFlowView()
        .environment({ let a = AppState(); a.hasCompletedOnboarding = false; return a }())
}
