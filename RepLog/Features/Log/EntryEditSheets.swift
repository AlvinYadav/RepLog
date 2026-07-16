import SwiftUI
import SwiftData

struct SetEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var workoutSet: WorkoutSet

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Exercise") {
                    Text(workoutSet.exercise?.name ?? "—")
                }
                LabeledContent("Weight") {
                    TextField("kg", value: $workoutSet.weightKg, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Reps") {
                    TextField("reps", value: $workoutSet.reps, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                DatePicker("Time", selection: $workoutSet.timestamp)
            }
            .navigationTitle("Edit set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct FoodEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var entry: FoodEntry

    var body: some View {
        NavigationStack {
            Form {
                TextField("Description", text: $entry.foodDescription, axis: .vertical)
                LabeledContent("Calories") {
                    TextField("kcal", value: $entry.calories, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Protein") {
                    TextField("g", value: $entry.proteinG, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Carbs") {
                    TextField("g", value: $entry.carbsG, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Fat") {
                    TextField("g", value: $entry.fatG, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                DatePicker("Time", selection: $entry.timestamp)
            }
            .navigationTitle("Edit food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct WeightEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var entry: BodyWeightEntry

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Weight") {
                    TextField("kg", value: $entry.weightKg, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                DatePicker("Date", selection: $entry.date)
            }
            .navigationTitle("Edit weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
