import SwiftUI
import SwiftData

/// Notes-style stream: everything logged today, newest first.
/// Submissions run through LogPipeline → Gemini → typed cards.
struct LogView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RawLog.timestamp, order: .reverse) private var logs: [RawLog]
    @Query(sort: \WorkoutSet.timestamp, order: .reverse) private var sets: [WorkoutSet]
    @Query(sort: \FoodEntry.timestamp, order: .reverse) private var foods: [FoodEntry]
    @Query(sort: \BodyWeightEntry.date, order: .reverse) private var weights: [BodyWeightEntry]

    @State private var draft = ""
    @FocusState private var inputFocused: Bool
    @State private var editingSet: WorkoutSet?
    @State private var editingFood: FoodEntry?
    @State private var editingWeight: BodyWeightEntry?

    private enum Item: Identifiable {
        case set(WorkoutSet)
        case food(FoodEntry)
        case weight(BodyWeightEntry)
        case raw(RawLog)

        var id: PersistentIdentifier {
            switch self {
            case .set(let m): return m.persistentModelID
            case .food(let m): return m.persistentModelID
            case .weight(let m): return m.persistentModelID
            case .raw(let m): return m.persistentModelID
            }
        }

        var timestamp: Date {
            switch self {
            case .set(let m): return m.timestamp
            case .food(let m): return m.timestamp
            case .weight(let m): return m.date
            case .raw(let m): return m.timestamp
            }
        }
    }

    private var todaysItems: [Item] {
        let calendar = Calendar.current
        var items: [Item] = []
        items += sets.filter { calendar.isDateInToday($0.timestamp) }.map(Item.set)
        items += foods.filter { calendar.isDateInToday($0.timestamp) }.map(Item.food)
        items += weights.filter { calendar.isDateInToday($0.date) }.map(Item.weight)
        // Parsed raw logs already appear as their typed entries; show only actionable rows.
        items += logs.filter { calendar.isDateInToday($0.timestamp) && $0.status != .parsed }.map(Item.raw)
        return items.sorted { $0.timestamp > $1.timestamp }
    }

    private var latestClarification: String? {
        logs.first { Calendar.current.isDateInToday($0.timestamp) && $0.status == .parsed && $0.clarification != nil }?
            .clarification
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let question = latestClarification {
                    Label(question, systemImage: "questionmark.bubble")
                        .font(.footnote)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.yellow.opacity(0.15))
                }

                if todaysItems.isEmpty {
                    ContentUnavailableView(
                        "Nothing logged yet",
                        systemImage: "text.bubble",
                        description: Text("Try: \"bench 50 kilos for 8\" or \"3 eggs on toast\"")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(todaysItems) { item in
                            row(for: item)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { delete(item) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollDismissesKeyboard(.immediately)
                }

                inputBar
            }
            .navigationTitle("Log")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { inputFocused = false }
                }
            }
            .sheet(item: $editingSet) { SetEditSheet(workoutSet: $0) }
            .sheet(item: $editingFood) { FoodEditSheet(entry: $0) }
            .sheet(item: $editingWeight) { WeightEditSheet(entry: $0) }
        }
    }

    @ViewBuilder
    private func row(for item: Item) -> some View {
        switch item {
        case .set(let set):
            Button { editingSet = set } label: { WorkoutSetCard(workoutSet: set) }
                .buttonStyle(.plain)
        case .food(let food):
            Button { editingFood = food } label: { FoodCard(entry: food) }
                .buttonStyle(.plain)
        case .weight(let weight):
            Button { editingWeight = weight } label: { WeightCard(entry: weight) }
                .buttonStyle(.plain)
        case .raw(let raw):
            RawLogRow(raw: raw) { LogPipeline.retry(raw, context: context) }
        }
    }

    private func delete(_ item: Item) {
        switch item {
        case .set(let m): context.delete(m)
        case .food(let m): context.delete(m)
        case .weight(let m): context.delete(m)
        case .raw(let m): context.delete(m)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("bench 50kg 8 reps / 3 eggs on toast…", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit(submit)
            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        LogPipeline.submit(text: text, context: context)
        draft = ""
    }
}

// MARK: - Cards

struct WorkoutSetCard: View {
    let workoutSet: WorkoutSet

    var body: some View {
        HStack {
            Image(systemName: "dumbbell.fill")
                .foregroundStyle(.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(workoutSet.exercise?.name ?? "Exercise")
                    .fontWeight(.medium)
                Text("\(formatted(workoutSet.weightKg)) kg × \(workoutSet.reps)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Text(workoutSet.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }
}

struct FoodCard: View {
    let entry: FoodEntry

    var body: some View {
        HStack {
            Image(systemName: "fork.knife")
                .foregroundStyle(.orange)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.foodDescription)
                    .fontWeight(.medium)
                    .lineLimit(2)
                Text("\(entry.calories) kcal · \(Int(entry.proteinG))P · \(Int(entry.carbsG))C · \(Int(entry.fatG))F")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Text(entry.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

struct WeightCard: View {
    let entry: BodyWeightEntry

    var body: some View {
        HStack {
            Image(systemName: "scalemass.fill")
                .foregroundStyle(.purple)
                .frame(width: 28)
            Text("\(entry.weightKg, format: .number.precision(.fractionLength(1))) kg")
                .fontWeight(.medium)
                .monospacedDigit()
            Spacer()
            Text(entry.date, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

struct RawLogRow: View {
    let raw: RawLog
    var onRetry: () -> Void

    var body: some View {
        HStack {
            switch raw.status {
            case .pending:
                ProgressView().frame(width: 28)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .frame(width: 28)
            default:
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(raw.input)
                if raw.status == .failed, let message = raw.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer()
            if raw.status == .failed {
                Button("Retry", action: onRetry)
                    .font(.caption)
                    .buttonStyle(.bordered)
            } else {
                Text(raw.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
