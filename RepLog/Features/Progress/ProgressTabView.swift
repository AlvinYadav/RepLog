import SwiftUI
import SwiftData
import Charts

struct ProgressTabView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutSet.timestamp) private var sets: [WorkoutSet]
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]
    @Query(sort: \WeeklyReport.createdAt, order: .reverse) private var reports: [WeeklyReport]
    @Query private var profiles: [UserProfile]

    @State private var selectedExercise = ""
    @State private var generating = false
    @State private var reportError: String?

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    Text("Progress")
                        .font(.system(.title, design: .serif, weight: .semibold))
                    strengthSection
                    weightSection
                    reportSection
                }
                .padding(20)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Strength

    private var exerciseNames: [String] {
        var seen = Set<String>()
        return sets.reversed().compactMap { set in
            guard let name = set.exercise?.name, !seen.contains(name) else { return nil }
            seen.insert(name)
            return name
        }
    }

    private func topSetPoints(for name: String) -> [Point] {
        let calendar = Calendar.current
        var byDay: [Date: Double] = [:]
        for set in sets where set.exercise?.name == name {
            let day = calendar.startOfDay(for: set.timestamp)
            byDay[day] = max(byDay[day] ?? 0, set.weightKg)
        }
        return byDay.keys.sorted().map { Point(date: $0, value: byDay[$0]!) }
    }

    @ViewBuilder
    private var strengthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Strength")
                    .font(.system(.title3, design: .serif, weight: .semibold))
                Spacer()
                if !exerciseNames.isEmpty {
                    Menu {
                        ForEach(exerciseNames, id: \.self) { name in
                            Button(name) { selectedExercise = name }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedExercise.isEmpty ? (exerciseNames.first ?? "") : selectedExercise)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    }
                }
            }

            let name = selectedExercise.isEmpty ? (exerciseNames.first ?? "") : selectedExercise
            let points = topSetPoints(for: name)
            if points.count < 2 {
                Text("Log \(name.isEmpty ? "an exercise" : name) on a few different days to see a trend.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Chart(points) { point in
                    LineMark(x: .value("Date", point.date), y: .value("kg", point.value))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", point.date), y: .value("kg", point.value))
                }
                .foregroundStyle(Color.primary.opacity(0.75))
                .chartYAxisLabel("top set kg", alignment: .trailing)
                .frame(height: 190)
            }
        }
    }

    // MARK: - Body weight

    @ViewBuilder
    private var weightSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Body weight")
                .font(.system(.title3, design: .serif, weight: .semibold))
            if weights.count < 2 {
                Text("Log your weight on a few mornings to see the trend.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                let goal = profiles.first?.goalWeightKg
                Chart {
                    ForEach(weights.map { Point(date: $0.date, value: $0.weightKg) }) { point in
                        LineMark(x: .value("Date", point.date), y: .value("kg", point.value))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Date", point.date), y: .value("kg", point.value))
                    }
                    if let goal {
                        RuleMark(y: .value("Goal", goal))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(.secondary)
                            .annotation(position: .top, alignment: .trailing) {
                                Text("goal \(Int(goal)) kg")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .foregroundStyle(Color.primary.opacity(0.75))
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 190)
            }
        }
    }

    // MARK: - Weekly report

    @ViewBuilder
    private var reportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Weekly report")
                    .font(.system(.title3, design: .serif, weight: .semibold))
                Spacer()
                Button {
                    generateReport()
                } label: {
                    if generating {
                        ProgressView()
                    } else {
                        Text(currentWeekReport == nil ? "Generate" : "Refresh")
                            .font(.footnote.weight(.medium))
                    }
                }
                .buttonStyle(.bordered)
                .tint(.primary)
                .disabled(generating)
            }

            if let error = reportError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if reports.isEmpty && reportError == nil {
                Text("A short coach's review of your week — food, training, and what to fix next.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(reports.prefix(4)) { report in
                reportCard(report)
            }
        }
    }

    @ViewBuilder
    private func reportCard(_ report: WeeklyReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Week of \(report.weekStart.formatted(.dateTime.day().month(.wide)))")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            if let content = try? JSONDecoder().decode(ReportContent.self, from: Data(report.text.utf8)) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(content.tiles, id: \.self) { tile in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tile.value)
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                            Text(tile.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                Text(content.summary)
                    .font(.subheadline)
                    .lineSpacing(3)
                reportList("On track", content.onTrack, symbol: "checkmark")
                reportList("Focus", content.focus, symbol: "exclamationmark")
                reportList("Next week", content.actions, symbol: "arrow.right")
            } else {
                Text(report.text)
                    .font(.subheadline)
                    .lineSpacing(3)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func reportList(_ title: String, _ items: [String], symbol: String) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased())
                    .font(.caption2.weight(.medium))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: symbol)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(item)
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    private var currentWeekReport: WeeklyReport? {
        let weekStart = ReportEngine.currentWeekStart()
        return reports.first { Calendar.current.isDate($0.weekStart, inSameDayAs: weekStart) }
    }

    private func generateReport() {
        generating = true
        reportError = nil
        Task {
            do {
                _ = try await ReportEngine.generate(context: context)
            } catch {
                reportError = error.localizedDescription
            }
            generating = false
        }
    }
}

#Preview {
    ProgressTabView()
        .modelContainer(
            for: [UserProfile.self, Exercise.self, WorkoutSet.self, FoodEntry.self,
                  BodyWeightEntry.self, SupplementEntry.self, WeeklyReport.self, RawLog.self],
            inMemory: true
        )
}
