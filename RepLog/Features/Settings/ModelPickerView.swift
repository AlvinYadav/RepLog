import SwiftUI

/// Lists the models the user's API key can actually call, fetched live.
struct ModelPickerView: View {
    let title: String
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    @State private var models: [String] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        List {
            if loading {
                HStack {
                    ProgressView()
                    Text("Asking Google which models your key can use…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let error {
                Text(error).foregroundStyle(.red).font(.caption)
                Button("Try again") { Task { await load() } }
            } else {
                ForEach(models, id: \.self) { model in
                    Button {
                        selection = model
                        dismiss()
                    } label: {
                        HStack {
                            Text(model)
                                .foregroundStyle(.primary)
                            Spacer()
                            if model == selection {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = true
        error = nil
        do {
            models = try await GeminiClient.listAvailableModels()
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
