import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @State private var apiKey = Keychain.get(Keychain.geminiAPIKey) ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Gemini API key") {
                    SecureField("Paste key from aistudio.google.com", text: $apiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: apiKey) {
                            Keychain.set(apiKey, for: Keychain.geminiAPIKey)
                        }
                    if apiKey.isEmpty {
                        Text("Required for AI logging (Phase 2+). Stored only in your device Keychain.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let profile = profiles.first {
                    ProfileSection(profile: profile)
                }

                Section {
                    LabeledContent("Version", value: "0.1.0 (Phase 1)")
                }
            }
            .navigationTitle("Settings")
            .onAppear(perform: ensureProfile)
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
