import SwiftUI
import SwiftData

/// Phase 1 placeholder — Swift Charts + weekly AI report land in Phase 5.
struct ProgressTabView: View {
    @Query(sort: \BodyWeightEntry.date, order: .reverse) private var weights: [BodyWeightEntry]

    var body: some View {
        NavigationStack {
            List {
                Section("Body weight history") {
                    if weights.isEmpty {
                        Text("No entries yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(weights) { entry in
                            HStack {
                                Text(entry.date, style: .date)
                                Spacer()
                                Text("\(entry.weightKg, format: .number.precision(.fractionLength(1))) kg")
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                Section {
                    Text("Strength charts and the weekly AI report arrive in Phase 5.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Progress")
        }
    }
}

#Preview {
    ProgressTabView()
        .modelContainer(for: BodyWeightEntry.self, inMemory: true)
}
