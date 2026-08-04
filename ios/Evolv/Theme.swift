import SwiftUI

enum EvolvTheme {
    // Palette — Obsidian Mint (locked)
    static let background = Color(red: 0.043, green: 0.059, blue: 0.055)   // #0B0F0E
    static let surface    = Color(red: 0.078, green: 0.102, blue: 0.098)   // #141A19
    static let surfaceHi  = Color(red: 0.106, green: 0.137, blue: 0.129)   // ~#1B2320
    static let text       = Color(red: 0.949, green: 0.961, blue: 0.953)   // #F2F5F3
    static let textMuted  = Color(red: 0.949, green: 0.961, blue: 0.953).opacity(0.58)
    static let textFaint  = Color(red: 0.949, green: 0.961, blue: 0.953).opacity(0.32)
    static let accent     = Color(red: 0.482, green: 0.890, blue: 0.702)   // #7BE3B3
    static let accentDim  = Color(red: 0.482, green: 0.890, blue: 0.702).opacity(0.18)
    static let stroke     = Color.white.opacity(0.06)

    // Honesty semantics
    static let improving = Color(red: 0.482, green: 0.890, blue: 0.702)        // mint
    static let stable    = Color(red: 0.92, green: 0.78, blue: 0.42)            // warm amber, restrained
    static let stalled   = Color(red: 0.95, green: 0.45, blue: 0.45)            // muted red

    static func statusColor(_ status: TrendStatus) -> Color {
        switch status {
        case .improving: return improving
        case .stable:    return stable
        case .stalled:   return stalled
        }
    }
}

// MARK: - Reusable surfaces

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 20
    var cornerRadius: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(EvolvTheme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(EvolvTheme.stroke, lineWidth: 1)
                    }
                    .overlay(alignment: .top) {
                        LinearGradient(
                            colors: [Color.white.opacity(0.04), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    }
            }
    }
}

struct AmbientBackground: View {
    var body: some View {
        ZStack {
            EvolvTheme.background.ignoresSafeArea()
            // Soft mint glow top-left
            Circle()
                .fill(EvolvTheme.accent.opacity(0.10))
                .frame(width: 420, height: 420)
                .blur(radius: 90)
                .offset(x: -140, y: -260)
            // Cooler glow bottom-right
            Circle()
                .fill(Color(red: 0.30, green: 0.55, blue: 0.55).opacity(0.10))
                .frame(width: 360, height: 360)
                .blur(radius: 100)
                .offset(x: 160, y: 320)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Typography helpers

extension Font {
    static let evolvDisplay = Font.system(size: 64, weight: .thin, design: .rounded)
    static let evolvHero    = Font.system(size: 34, weight: .semibold, design: .rounded)
    static let evolvTitle   = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let evolvBody    = Font.system(size: 15, weight: .regular, design: .default)
    static let evolvLabel   = Font.system(size: 12, weight: .medium, design: .rounded)
    static let evolvMono    = Font.system(size: 13, weight: .medium, design: .monospaced)
}

// MARK: - Primary CTA

struct EvolvPrimaryButton: View {
    let title: String
    var icon: String? = nil
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                if let icon { Image(systemName: icon).font(.system(size: 14, weight: .semibold)) }
            }
            .foregroundStyle(EvolvTheme.background)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(EvolvTheme.accent)
                    .opacity(enabled ? 1 : 0.35)
            }
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
    }
}

struct EvolvSecondaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(EvolvTheme.text.opacity(0.75))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(EvolvTheme.stroke, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}
