import SwiftUI

// MARK: - Units

struct UnitsSettingsView: View {
    @Environment(AppState.self) private var app

    @State private var mass: MassUnit = .kg
    @State private var length: LengthUnit = .cm

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(spacing: 18) {
                    SettingsGroup(
                        header: "Weight",
                        footer: "Used for weight history and progress rate."
                    ) {
                        SegmentedRow(
                            options: MassUnit.allCases,
                            selection: $mass,
                            display: { $0.label.uppercased() },
                            description: { unit in
                                unit == .kg ? "Kilograms" : "Pounds"
                            }
                        )
                        .onChange(of: mass) { _, _ in persist() }
                    }

                    SettingsGroup(
                        header: "Length",
                        footer: "Used for height and body measurements."
                    ) {
                        SegmentedRow(
                            options: LengthUnit.allCases,
                            selection: $length,
                            display: { $0.label.uppercased() },
                            description: { unit in
                                unit == .cm ? "Centimeters" : "Inches"
                            }
                        )
                        .onChange(of: length) { _, _ in persist() }
                    }

                    Text("Internal values never change. Evolv simply displays them in your preferred unit.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(EvolvTheme.textFaint)
                        .padding(.horizontal, 6)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Units")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            mass = app.profile.massUnit
            length = app.profile.lengthUnit
        }
    }

    private func persist() {
        app.profile.massUnit = mass
        app.profile.lengthUnit = length
        app.save()
    }
}

private struct SegmentedRow<T: Hashable & Identifiable>: View {
    let options: [T]
    @Binding var selection: T
    let display: (T) -> String
    let description: (T) -> String

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(options, id: \.self) { opt in
                    let selected = selection == opt
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selection = opt }
                    } label: {
                        Text(display(opt))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(selected ? EvolvTheme.background : EvolvTheme.textMuted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(selected ? EvolvTheme.accent : EvolvTheme.surfaceHi.opacity(0.6))
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(description(selection))
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(EvolvTheme.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }
}
