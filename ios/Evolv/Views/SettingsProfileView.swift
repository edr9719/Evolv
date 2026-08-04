import SwiftUI

// MARK: - Profile

struct ProfileSettingsView: View {
    @Environment(AppState.self) private var app

    @State private var heightCm: Double = 178
    @State private var weightKg: Double = 76
    @State private var goal: FitnessGoal = .muscleGain
    @State private var experience: Experience = .intermediate
    @State private var arms: Double? = nil
    @State private var chest: Double? = nil
    @State private var waist: Double? = nil
    @State private var shoulders: Double? = nil
    @State private var thighs: Double? = nil

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(spacing: 18) {
                    SettingsGroup(header: "Basics") {
                        ProfileSliderRow(
                            label: "Height",
                            valueText: UnitFormatter.displayHeight(heightCm, unit: app.profile.lengthUnit),
                            value: $heightCm,
                            range: 140...210,
                            step: 1
                        )
                        SettingsDivider()
                        ProfileSliderRow(
                            label: "Weight",
                            valueText: UnitFormatter.displayMass(weightKg, unit: app.profile.massUnit),
                            value: $weightKg,
                            range: 35...200,
                            step: 0.1
                        )
                    }

                    SettingsGroup(header: "Goal & Experience", footer: "Changes to your goal subtly tune how insights are written.") {
                        InlinePickerRow(
                            label: "Goal",
                            options: FitnessGoal.allCases,
                            selection: $goal,
                            display: { $0.rawValue }
                        )
                        SettingsDivider()
                        InlinePickerRow(
                            label: "Experience",
                            options: Experience.allCases,
                            selection: $experience,
                            display: { $0.rawValue }
                        )
                    }

                    SettingsGroup(
                        header: "Baseline measurements",
                        footer: "Optional. Used to estimate directional change over time."
                    ) {
                        OptionalLengthRow(label: "Arms", value: $arms, lengthUnit: app.profile.lengthUnit)
                        SettingsDivider()
                        OptionalLengthRow(label: "Chest", value: $chest, lengthUnit: app.profile.lengthUnit)
                        SettingsDivider()
                        OptionalLengthRow(label: "Waist", value: $waist, lengthUnit: app.profile.lengthUnit)
                        SettingsDivider()
                        OptionalLengthRow(label: "Shoulders", value: $shoulders, lengthUnit: app.profile.lengthUnit)
                        SettingsDivider()
                        OptionalLengthRow(label: "Thighs", value: $thighs, lengthUnit: app.profile.lengthUnit)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadFromProfile)
        .onDisappear(perform: persist)
    }

    private func loadFromProfile() {
        heightCm = app.profile.heightCm
        weightKg = app.profile.weightKg
        goal = app.profile.goal
        experience = app.profile.experience
        arms = app.profile.arms
        chest = app.profile.chest
        waist = app.profile.waist
        shoulders = app.profile.shoulders
        thighs = app.profile.thighs
    }

    private func persist() {
        app.profile.heightCm = heightCm
        app.profile.weightKg = weightKg
        app.profile.goal = goal
        app.profile.experience = experience
        app.profile.arms = arms
        app.profile.chest = chest
        app.profile.waist = waist
        app.profile.shoulders = shoulders
        app.profile.thighs = thighs
        app.save()
    }
}

// MARK: - Profile rows

private struct ProfileSliderRow: View {
    let label: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                Spacer()
                Text(valueText)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.accent)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step).tint(EvolvTheme.accent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

private struct InlinePickerRow<T: Hashable & Identifiable>: View {
    let label: String
    let options: [T]
    @Binding var selection: T
    let display: (T) -> String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(EvolvTheme.text)
            Spacer()
            Menu {
                ForEach(options, id: \.self) { opt in
                    Button(display(opt)) { selection = opt }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(display(selection))
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.accent)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(EvolvTheme.accent)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

private struct OptionalLengthRow: View {
    let label: String
    @Binding var value: Double?
    let lengthUnit: LengthUnit

    @State private var editing = false
    @State private var draft: Double = 35

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(EvolvTheme.text)
            Spacer()
            if let v = value {
                Text(UnitFormatter.displayLength(v, unit: lengthUnit))
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                    .monospacedDigit()
                Button {
                    draft = v
                    editing = true
                } label: {
                    Text("Edit")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.accent)
                }
                .buttonStyle(.plain)
                Button {
                    withAnimation { value = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(EvolvTheme.textFaint)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(EvolvTheme.surfaceHi))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    let defaultCm: Double = {
                        switch label {
                        case "Arms": return 35
                        case "Chest": return 100
                        case "Waist": return 80
                        case "Shoulders": return 120
                        case "Thighs": return 55
                        default: return 50
                        }
                    }()
                    draft = defaultCm
                    editing = true
                } label: {
                    Text("Add")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(EvolvTheme.accent.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .sheet(isPresented: $editing) {
            MeasurementEditorSheet(
                title: label,
                cmValue: $draft,
                lengthUnit: lengthUnit
            ) {
                value = draft
            }
            .presentationDetents([.height(280)])
        }
    }
}

private struct MeasurementEditorSheet: View {
    let title: String
    @Binding var cmValue: Double
    let lengthUnit: LengthUnit
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var displayValue: Double = 0

    var body: some View {
        ZStack {
            EvolvTheme.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Capsule().fill(EvolvTheme.stroke).frame(width: 36, height: 4).padding(.top, 8)
                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: lengthUnit == .cm ? "%.1f" : "%.2f", displayValue))
                        .font(.system(size: 42, weight: .thin, design: .rounded))
                        .foregroundStyle(EvolvTheme.text)
                        .monospacedDigit()
                    Text(lengthUnit.label)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(EvolvTheme.textFaint)
                }
                Slider(
                    value: $displayValue,
                    in: UnitFormatter.bodyPartRange(unit: lengthUnit),
                    step: UnitFormatter.bodyPartStep(unit: lengthUnit)
                )
                .tint(EvolvTheme.accent)
                .padding(.horizontal, 24)

                EvolvPrimaryButton(title: "Save") {
                    cmValue = UnitFormatter.toCm(displayValue, unit: lengthUnit)
                    onSave()
                    dismiss()
                }
                .padding(.horizontal, 24)
                Spacer()
            }
        }
        .onAppear {
            displayValue = UnitFormatter.displayLengthNumber(cmValue, unit: lengthUnit)
        }
    }
}
