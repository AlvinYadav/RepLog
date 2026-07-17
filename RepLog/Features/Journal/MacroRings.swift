import SwiftUI

/// Apple-Health-style progress ring, monochrome to match the app.
struct MacroRing: View {
    let label: String
    let value: Double
    let target: Double
    var size: CGFloat = 50
    var lineWidth: CGFloat = 5

    private var fraction: Double { min(value / max(target, 1), 1) }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        Color.primary.opacity(fraction >= 1 ? 0.9 : 0.6),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(Int(value))")
                    .font(.system(size: size * 0.27, weight: .semibold, design: .serif))
                    .monospacedDigit()
            }
            .frame(width: size, height: size)
            .animation(.snappy, value: fraction)
            Text(label)
                .font(.system(.caption2, design: .serif))
                .foregroundStyle(.secondary)
        }
    }
}

/// Larger centerpiece ring for calories, showing value over target.
struct CaloriesRing: View {
    let value: Double
    let target: Double
    var size: CGFloat = 96

    private var fraction: Double { min(value / max(target, 1), 1) }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        Color.primary.opacity(fraction >= 1 ? 0.9 : 0.65),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text("\(Int(value))")
                        .font(.system(size: 23, weight: .semibold, design: .serif))
                        .monospacedDigit()
                    Text("/ \(Int(target))")
                        .font(.system(.caption2, design: .serif))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(width: size, height: size)
            .animation(.snappy, value: fraction)
            Text("kcal")
                .font(.system(.caption2, design: .serif))
                .foregroundStyle(.secondary)
        }
    }
}
