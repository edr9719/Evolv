import SwiftUI

// MARK: - Status / Evidence chips

struct StatusChip: View {
    let status: TrendStatus
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(EvolvTheme.statusColor(status))
                .frame(width: 6, height: 6)
            Text(status.label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(EvolvTheme.statusColor(status))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule().fill(EvolvTheme.statusColor(status).opacity(0.12))
        }
    }
}

struct ConfidenceChip: View {
    let confidence: Confidence
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text("Evidence: \(confidence.label.lowercased())")
                .font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .foregroundStyle(EvolvTheme.textMuted)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background {
            Capsule().stroke(EvolvTheme.stroke, lineWidth: 1)
        }
    }
    private var icon: String {
        switch confidence {
        case .high: return "checkmark.seal.fill"
        case .medium: return "circle.lefthalf.filled"
        case .low: return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Progress score ring

struct ProgressScoreRing: View {
    let value: Int
    var size: CGFloat = 220
    var lineWidth: CGFloat = 14

    var body: some View {
        let progress = Double(value) / 100.0
        ZStack {
            Circle()
                .stroke(EvolvTheme.surfaceHi, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [EvolvTheme.accent.opacity(0.5), EvolvTheme.accent, Color(red: 0.6, green: 1, blue: 0.85)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: EvolvTheme.accent.opacity(0.4), radius: 16)
            VStack(spacing: 4) {
                Text("\(value)")
                    .font(.system(size: size * 0.36, weight: .thin, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                    .monospacedDigit()
                Text("PROGRESS SCORE")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(EvolvTheme.textFaint)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Body region diagram

struct BodyRegionDiagram: View {
    /// Map region label -> status for coloring
    let regions: [String: TrendStatus]
    var highlighted: String? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cx = w / 2

            ZStack {
                // Soft glow behind body
                Ellipse()
                    .fill(EvolvTheme.accent.opacity(0.06))
                    .frame(width: w * 0.7, height: h * 0.9)
                    .blur(radius: 30)

                // Head
                Circle()
                    .stroke(EvolvTheme.text.opacity(0.35), lineWidth: 1.4)
                    .frame(width: w * 0.18, height: w * 0.18)
                    .position(x: cx, y: h * 0.08)

                // Torso outline (stylized)
                TorsoShape()
                    .stroke(EvolvTheme.text.opacity(0.35), lineWidth: 1.4)
                    .frame(width: w * 0.62, height: h * 0.55)
                    .position(x: cx, y: h * 0.42)

                // Legs
                LegsShape()
                    .stroke(EvolvTheme.text.opacity(0.30), lineWidth: 1.4)
                    .frame(width: w * 0.42, height: h * 0.32)
                    .position(x: cx, y: h * 0.80)

                // Region dots
                regionDot("Shoulders", color: regions["Shoulders"], pos: CGPoint(x: cx - w * 0.20, y: h * 0.20))
                regionDot("Shoulders R", color: regions["Shoulders"], pos: CGPoint(x: cx + w * 0.20, y: h * 0.20))
                regionDot("Chest", color: regions["Chest"], pos: CGPoint(x: cx, y: h * 0.30))
                regionDot("Arms", color: regions["Arms"], pos: CGPoint(x: cx - w * 0.27, y: h * 0.32))
                regionDot("Arms R", color: regions["Arms"], pos: CGPoint(x: cx + w * 0.27, y: h * 0.32))
                regionDot("Waist", color: regions["Waist"], pos: CGPoint(x: cx, y: h * 0.52))
                regionDot("Back", color: regions["Back"], pos: CGPoint(x: cx + w * 0.10, y: h * 0.40))
            }
        }
    }

    @ViewBuilder
    private func regionDot(_ key: String, color status: TrendStatus?, pos: CGPoint) -> some View {
        let c = status.map(EvolvTheme.statusColor) ?? EvolvTheme.textFaint
        ZStack {
            Circle().fill(c.opacity(0.18)).frame(width: 22, height: 22)
            Circle().fill(c).frame(width: 9, height: 9)
        }
        .position(pos)
        .shadow(color: c.opacity(0.6), radius: 8)
    }
}

private struct TorsoShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: w * 0.18, y: 0))
        p.addQuadCurve(to: CGPoint(x: w * 0.0, y: h * 0.18),
                       control: CGPoint(x: w * 0.04, y: h * 0.04))
        p.addLine(to: CGPoint(x: w * 0.10, y: h * 0.55))
        p.addQuadCurve(to: CGPoint(x: w * 0.22, y: h * 0.95),
                       control: CGPoint(x: w * 0.18, y: h * 0.75))
        p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.95))
        p.addQuadCurve(to: CGPoint(x: w * 0.90, y: h * 0.55),
                       control: CGPoint(x: w * 0.82, y: h * 0.75))
        p.addLine(to: CGPoint(x: w * 1.0, y: h * 0.18))
        p.addQuadCurve(to: CGPoint(x: w * 0.82, y: 0),
                       control: CGPoint(x: w * 0.96, y: h * 0.04))
        p.closeSubpath()
        return p
    }
}

private struct LegsShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        // Left leg
        p.move(to: CGPoint(x: w * 0.15, y: 0))
        p.addLine(to: CGPoint(x: w * 0.30, y: h))
        p.addLine(to: CGPoint(x: w * 0.45, y: h))
        p.addLine(to: CGPoint(x: w * 0.45, y: 0))
        p.closeSubpath()
        // Right leg
        p.move(to: CGPoint(x: w * 0.55, y: 0))
        p.addLine(to: CGPoint(x: w * 0.55, y: h))
        p.addLine(to: CGPoint(x: w * 0.70, y: h))
        p.addLine(to: CGPoint(x: w * 0.85, y: 0))
        p.closeSubpath()
        return p
    }
}

// MARK: - Mini sparkline chart

struct SparklineChart: View {
    let values: [Double]
    var color: Color = EvolvTheme.accent
    var fill: Bool = true

    var body: some View {
        GeometryReader { geo in
            let path = linePath(in: geo.size)
            ZStack {
                if fill {
                    fillPath(in: geo.size)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.35), color.opacity(0.0)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                }
                path
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .shadow(color: color.opacity(0.5), radius: 6)
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let range = max(0.001, maxV - minV)
        return values.enumerated().map { i, v in
            let x = CGFloat(i) / CGFloat(values.count - 1) * size.width
            let y = size.height - CGFloat((v - minV) / range) * size.height
            return CGPoint(x: x, y: y)
        }
    }

    private func linePath(in size: CGSize) -> Path {
        var p = Path()
        let pts = points(in: size)
        guard let first = pts.first else { return p }
        p.move(to: first)
        for pt in pts.dropFirst() { p.addLine(to: pt) }
        return p
    }

    private func fillPath(in size: CGSize) -> Path {
        var p = linePath(in: size)
        let pts = points(in: size)
        guard let last = pts.last, let first = pts.first else { return Path() }
        p.addLine(to: CGPoint(x: last.x, y: size.height))
        p.addLine(to: CGPoint(x: first.x, y: size.height))
        p.closeSubpath()
        return p
    }
}

// MARK: - Section header

struct EvolvSectionHeader: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(EvolvTheme.textFaint)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
            }
        }
    }
}
