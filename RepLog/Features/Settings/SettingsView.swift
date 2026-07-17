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
    @State private var healthConnected = false
    @State private var reviewing = false
    @State private var reviewError: String?
    @State private var suggestion: TargetSuggestion?
    @State private var exportURL: URL?
    @AppStorage("waterRemindersOn") private var waterRemindersOn = false

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
                    NavigationLink {
                        ModelPickerView(title: "Logging model", selection: $parseModel)
                    } label: {
                        LabeledContent("Logging", value: parseModel)
                    }
                    NavigationLink {
                        ModelPickerView(title: "Reports model", selection: $reportModel)
                    } label: {
                        LabeledContent("Reports", value: reportModel)
                    }
                    Text("Free-tier tip: the newest '-latest' models have tiny daily quotas (~20 requests). For logging, pick an older versioned Flash or a Lite model — they allow ~1,500/day and respond faster.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Exercises") {
                    NavigationLink("Manage exercises") {
                        ExerciseListView()
                    }
                }

                Section("Diagnostics") {
                    NavigationLink("Recent AI parses") {
                        ParseHistoryView()
                    }
                }

                if let profile = profiles.first {
                    ProfileSection(profile: profile)
                    targetReviewSection(profile: profile)
                }

                Section("Reminders") {
                    Toggle("Water reminders (3× a day)", isOn: $waterRemindersOn)
                        .onChange(of: waterRemindersOn) {
                            if waterRemindersOn {
                                Task {
                                    let granted = await NotificationService.enableWaterReminders()
                                    if !granted { waterRemindersOn = false }
                                }
                            } else {
                                NotificationService.disableWaterReminders()
                            }
                        }
                    Text("Quiet nudges at 11:00, 15:00, and 19:00. No sound, no spam.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Apple Health") {
                    Button(healthConnected ? "Connected ✓" : "Connect Apple Health") {
                        Task {
                            healthConnected = await HealthService.shared.requestAuthorization()
                        }
                    }
                    .disabled(healthConnected)
                    Text("Steps and active energy feed into your weekly report.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Data") {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Share export", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button(exportURL == nil ? "Export all data (JSON)" : "Re-export") {
                        exportURL = try? Exporter.exportJSON(context: context)
                    }
                    Text("Everything you've logged, as one JSON file. Save it to Files/iCloud Drive as a backup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    LabeledContent("Version", value: "0.6.0")
                }
            }
            .navigationTitle("Settings")
            .onAppear(perform: ensureProfile)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                        )
                    }
                }
            }
            .sheet(item: $suggestion) { suggestion in
                TargetSuggestionSheet(suggestion: suggestion, profile: profiles.first)
            }
        }
    }

    @ViewBuilder
    private func targetReviewSection(profile: UserProfile) -> some View {
        Section {
            Button {
                reviewTargets()
            } label: {
                if reviewing {
                    ProgressView()
                } else {
                    Text("Review targets with AI")
                }
            }
            .disabled(reviewing)
            if let error = reviewError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Text("Current defaults assume a 170 cm lean bulk: ≈2,500 kcal (maintenance plus a ~400 kcal surplus) and protein at ~2.2 g per kg. After a week of logging, the AI can tune these to your actual intake, weight trend, and training.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func reviewTargets() {
        reviewing = true
        reviewError = nil
        Task {
            do {
                suggestion = try await TargetAdvisor.suggest(context: context)
            } catch {
                reviewError = error.localizedDescription
            }
            reviewing = false
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
            LabeledContent("Fiber") {
                TextField("g", value: $profile.dailyFiberG, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Water") {
                TextField("ml", value: $profile.dailyWaterMl, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

struct TargetSuggestionSheet: View {
    let suggestion: TargetSuggestion
    let profile: UserProfile?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Suggested daily targets") {
                    comparisonRow("Calories", current: profile?.dailyCalories, proposed: suggestion.calories, unit: "kcal")
                    comparisonRow("Protein", current: profile?.dailyProteinG, proposed: suggestion.proteinG, unit: "g")
                    comparisonRow("Carbs", current: profile?.dailyCarbsG, proposed: suggestion.carbsG, unit: "g")
                    comparisonRow("Fat", current: profile?.dailyFatG, proposed: suggestion.fatG, unit: "g")
                    comparisonRow("Fiber", current: profile?.dailyFiberG, proposed: suggestion.fiberG, unit: "g")
                }
                Section("Why") {
                    Text(suggestion.rationale)
                        .font(.subheadline)
                }
            }
            .navigationTitle("AI target review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        if let profile {
                            profile.dailyCalories = suggestion.calories
                            profile.dailyProteinG = suggestion.proteinG
                            profile.dailyCarbsG = suggestion.carbsG
                            profile.dailyFatG = suggestion.fatG
                            profile.dailyFiberG = suggestion.fiberG
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func comparisonRow(_ name: String, current: Int?, proposed: Int, unit: String) -> some View {
        LabeledContent(name) {
            HStack(spacing: 6) {
                if let current, current != proposed {
                    Text("\(current)")
                        .strikethrough()
                        .foregroundStyle(.tertiary)
                }
                Text("\(proposed) \(unit)")
                    .fontWeight(.medium)
            }
            .monospacedDigit()
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: UserProfile.self, inMemory: true)
}
