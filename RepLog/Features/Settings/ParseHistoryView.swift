import SwiftUI
import SwiftData

/// Debug aid: raw inputs and exactly what Gemini returned for each.
struct ParseHistoryView: View {
    @Query(sort: \RawLog.timestamp, order: .reverse) private var logs: [RawLog]

    var body: some View {
        List {
            ForEach(logs.prefix(50)) { log in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(log.statusRaw.uppercased())
                            .font(.caption2.bold())
                            .foregroundStyle(color(for: log.status))
                        Spacer()
                        Text(log.timestamp, format: .dateTime.day().month().hour().minute())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(log.input)
                        .font(.subheadline)
                    if let json = log.parsedJSON {
                        Text(json)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if let error = log.errorMessage {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Recent AI parses")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func color(for status: RawLogStatus) -> Color {
        switch status {
        case .parsed: return .green
        case .failed: return .red
        case .pending: return .orange
        case .note: return .secondary
        }
    }
}
