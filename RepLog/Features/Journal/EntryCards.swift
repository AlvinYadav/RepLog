import SwiftUI

// Quiet, monochrome entry rows — thin-weight icons, no color noise.

struct WorkoutSetCard: View {
    let workoutSet: WorkoutSet

    var body: some View {
        EntryRow(
            icon: "dumbbell",
            title: workoutSet.exercise?.name ?? "Exercise",
            detail: "\(formatted(workoutSet.weightKg)) kg × \(workoutSet.reps)",
            timestamp: workoutSet.timestamp
        )
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }
}

struct FoodCard: View {
    let entry: FoodEntry

    var body: some View {
        EntryRow(
            icon: "fork.knife",
            title: entry.foodDescription,
            detail: "\(entry.calories) kcal · \(Int(entry.proteinG))P · \(Int(entry.carbsG))C · \(Int(entry.fatG))F",
            timestamp: entry.timestamp,
            thumbnailData: entry.photoData
        )
    }
}

struct WeightCard: View {
    let entry: BodyWeightEntry

    var body: some View {
        EntryRow(
            icon: "scalemass",
            title: String(format: "%.1f kg", entry.weightKg),
            detail: "Body weight",
            timestamp: entry.date
        )
    }
}

struct SupplementCard: View {
    let entry: SupplementEntry

    var body: some View {
        EntryRow(
            icon: "pills",
            title: entry.name,
            detail: entry.amount.map { "Supplement · \($0)" } ?? "Supplement",
            timestamp: entry.timestamp
        )
    }
}

struct WaterCard: View {
    let entry: WaterEntry

    var body: some View {
        EntryRow(
            icon: "drop",
            title: "\(entry.milliliters) ml",
            detail: "Water",
            timestamp: entry.timestamp
        )
    }
}

struct EntryRow: View {
    let icon: String
    let title: String
    let detail: String
    let timestamp: Date
    var thumbnailData: Data? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            if let data = thumbnailData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 6 }
            } else {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            Text(timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct RawLogRow: View {
    let raw: RawLog
    var onRetry: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Group {
                switch raw.status {
                case .pending:
                    ProgressView()
                case .failed:
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(.red)
                default:
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(raw.input)
                    .font(.subheadline)
                if raw.status == .failed, let message = raw.errorMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if raw.status == .failed {
                Button("Retry", action: onRetry)
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .tint(.primary)
            } else {
                Text(raw.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 10)
    }
}
