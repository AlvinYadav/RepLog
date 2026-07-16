import SwiftUI
import SwiftData

/// Phase 1: notes-style stream with manual text entry.
/// Phase 2 pipes submissions through Gemini into structured entries.
struct LogView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RawLog.timestamp, order: .reverse) private var logs: [RawLog]
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private var todaysLogs: [RawLog] {
        logs.filter { Calendar.current.isDateInToday($0.timestamp) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if todaysLogs.isEmpty {
                    ContentUnavailableView(
                        "Nothing logged yet",
                        systemImage: "text.bubble",
                        description: Text("Type below — dictation and AI parsing arrive in the next phases.")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(todaysLogs) { log in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(log.input)
                                Text(log.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { offsets in
                            for offset in offsets {
                                context.delete(todaysLogs[offset])
                            }
                        }
                    }
                    .listStyle(.plain)
                }

                HStack(spacing: 12) {
                    TextField("bench 50kg 8 reps / 3 eggs on toast…", text: $draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .focused($inputFocused)
                        .onSubmit(submit)
                    Button(action: submit) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .navigationTitle("Log")
        }
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        context.insert(RawLog(input: text, status: .note))
        draft = ""
    }
}

#Preview {
    LogView()
        .modelContainer(for: RawLog.self, inMemory: true)
}
