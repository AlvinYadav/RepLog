import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @State private var apiKey = Keychain.get(Keychain.geminiAPIKey) ?? ""
    @AppStorage("parseModel") private var parseModel = "gemini-flash-latest"
    @AppStorage("reportModel") private var reportModel = "gemini-pro-latest"
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Gemini API key") {
                    SecureField("Paste key from aistudio.google.com", text: $apiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: apiKey) {
                            Keychain.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: Keychain.geminiAPIKey)
                        }
                    Button {
                        testConnection()
                    } label: {
                        if testing {
                            ProgressView()
                        } else {
                            Text("Test connection")
                        }
                    }
                    .disabled(apiKey.isEmpty || testing)
                    if let testResult {
                        Text(testResult)
                            .font(.caption)
                            .foregroundStyle(testResult.hasPrefix("✓") ? .green : .red)
                    }
                }

                Section("Models") {
                    LabeledContent("Logging") {
                        TextField("model id", text: $parseModel)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Reports") {
                        TextField("model id", text: $reportModel)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .multilineTextAlignment(.trailing)
                    }
                    Text("Fast model for everyday parsing; stronger model for photo macros and weekly reports.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Exercises") {
                    NavigationLink("Manage exercises") {
                        ExerciseListView()
                    }
                }

                if let profile = profiles.first {
                    ProfileSection(profile: profile)
                }

                Section {
                    LabeledContent("Version", value: "0.2.0 (Phase 2)")
                }
            }
            .navigationTitle("Settings")
            .onAppear(perform: ensureProfile)
        }
    }

    private func testConnection() {
        testing = true
        testResult = nil
        Task {
            let result = await GeminiClient.testConnection(model: parseModel)
            switch result {
            case .success: testResult = "✓ Connected — \(parseModel) responded."
            case .failure(let error): testResult = error.localizedDescription
            }
            testing = false
        }
    }

    private func ensureProfile() {
        if profiles.isEmpty {
            context.insert(UserProfile())
        }
    }
}

private struct ProfileSection: View {
    @Bindable var profile: UserProfile

    var body: some View {
        Section("Profile") {
            LabeledContent("Height") {
                TextField("cm", value: $profile.heightCm, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Goal weight") {
                TextField("kg", value: $profile.goalWeightKg, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
        }
        Section("Daily targets") {
            LabeledContent("Calories") {
                TextField("kcal", value: $profile.dailyCalories, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Protein") {
                TextField("g", value: $profile.dailyProteinG, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Carbs") {
                TextField("g", value: $profile.dailyCarbsG, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Fat") {
                TextField("g", value: $profile.dailyFatG, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: UserProfile.self, inMemory: true)
}
