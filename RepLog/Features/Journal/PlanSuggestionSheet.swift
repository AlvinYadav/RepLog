import SwiftUI
import SwiftData

/// Tapping a Plan line opens this: an actionable, personalized suggestion.
struct PlanSuggestionSheet: View {
    let item: PlanItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var suggestion: String?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(item.text)
                        .font(.system(.title3, design: .serif, weight: .semibold))

                    if loading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Thinking with your logs…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)
                    } else if let suggestion {
                        Text(suggestion)
                            .font(.body)
                            .lineSpacing(4)
                    } else if let error {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                        Button("Try again") { load() }
                            .buttonStyle(.bordered)
                            .tint(.primary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .navigationTitle("Suggestion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        load()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(loading)
                }
            }
            .task { load() }
        }
        .presentationDetents([.medium, .large])
    }

    private func load() {
        loading = true
        error = nil
        suggestion = nil
        Task {
            do {
                suggestion = try await SuggestionEngine.suggest(for: item, context: context)
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
}
