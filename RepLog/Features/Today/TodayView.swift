import SwiftUI
import SwiftData

struct TodayView: View {
    @Query private var profiles: [UserProfile]
    @Query private var foods: [FoodEntry]
    @Query private var sets: [WorkoutSet]
    @Query private var weights: [BodyWeightEntry]

    private var profile: UserProfile? { profiles.first }
    private var todaysFoods: [FoodEntry] { foods.filter { Calendar.current.isDateInToday($0.timestamp) } }
    private var todaysSets: [WorkoutSet] { sets.filter { Calendar.current.isDateInToday($0.timestamp) } }
    private var latestWeight: BodyWeightEntry? { weights.max(by: { $0.date < $1.date }) }

    private var calories: Int { todaysFoods.reduce(0) { $0 + $1.calories } }
    private var protein: Double { todaysFoods.reduce(0) { $0 + $1.proteinG } }
    private var carbs: Double { todaysFoods.reduce(0) { $0 + $1.carbsG } }
    private var fat: Double { todaysFoods.reduce(0) { $0 + $1.fatG } }

    var body: some View {
        NavigationStack {
            List {
                Section("Nutrition") {
                    macroRow("Calories", value: Double(calories), target: Double(profile?.dailyCalories ?? 2500), unit: "kcal")
                    macroRow("Protein", value: protein, target: Double(profile?.dailyProteinG ?? 150), unit: "g")
                    macroRow("Carbs", value: carbs, target: Double(profile?.dailyCarbsG ?? 300), unit: "g")
                    macroRow("Fat", value: fat, target: Double(profile?.dailyFatG ?? 80), unit: "g")
                }
                Section("Training") {
                    if todaysSets.isEmpty {
                        Text("No sets logged today").foregroundStyle(.secondary)
                    } else {
                        Text("\(todaysSets.count) sets · \(Int(todaysSets.reduce(0) { $0 + $1.weightKg * Double($1.reps) })) kg total volume")
                    }
                }
                Section("Body weight") {
                    if let latest = latestWeight {
                        HStack {
                            Text(latest.weightKg, format: .number.precision(.fractionLength(1)))
                            Text("kg")
                            Spacer()
                            Text(latest.date, style: .date).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No weight logged yet").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Today")
        }
    }

    private func macroRow(_ name: String, value: Double, target: Double, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                Spacer()
                Text("\(Int(value)) / \(Int(target)) \(unit)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: min(value, target), total: max(target, 1))
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    TodayView()
        .modelContainer(for: [UserProfile.self, FoodEntry.self, WorkoutSet.self, BodyWeightEntry.self], inMemory: true)
}
