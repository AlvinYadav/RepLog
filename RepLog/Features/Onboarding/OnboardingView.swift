import SwiftUI
import SwiftData

/// One-screen first-run setup: API key, favorite exercises, daily targets.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("didOnboard") private var didOnboard = false

    @State private var apiKey = Keychain.get(Keychain.geminiAPIKey) ?? ""
    @State private var exerciseDraft = ""
    @State private var exerciseNames: [String] = []
    @State private var calories = 2500
    @State private var protein = 150
    @State private var goalWeight = 75.0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Log workouts and food by talking. RepLog parses, tracks, and reports.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Gemini API key") {
                    SecureField("Paste key from aistudio.google.com", text: $apiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("Your exercises") {
                    ForEach(exerciseNames, id: \.self) { name in
                        Text(name)
                    }
                    .onDelete { exerciseNames.remove(atOffsets: $0) }
                    HStack {
                        TextField("e.g. Bench Press", text: $exerciseDraft)
                            .onSubmit(addExercise)
                        Button("Add", action: addExercise)
                            .disabled(exerciseDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Text("Your usual lifts — new ones are added automatically whenever you log them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Daily targets") {
                    LabeledContent("Calories") {
                        TextField("kcal", value: $calories, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Protein (g)") {
                        TextField("g", value: $protein, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Goal weight (kg)") {
                        TextField("kg", value: $goalWeight, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .navigationTitle("Welcome")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start", action: finish)
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func addExercise() {
        let name = exerciseDraft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !exerciseNames.contains(where: { $0.lowercased() == name.lowercased() }) else { return }
        exerciseNames.append(name)
        exerciseDraft = ""
    }

    private func finish() {
        Keychain.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: Keychain.geminiAPIKey)
        for name in exerciseNames {
            context.insert(Exercise(name: name))
        }
        let existing = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
        let profile = existing ?? UserProfile()
        profile.dailyCalories = calories
        profile.dailyProteinG = protein
        profile.goalWeightKg = goalWeight
        if existing == nil { context.insert(profile) }
        didOnboard = true
    }
}
