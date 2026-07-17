import SwiftUI
import UIKit

/// Shown after a meal photo is taken/picked: preview it, optionally add
/// context the camera can't see, then send it for analysis.
struct PhotoReviewSheet: View {
    let image: UIImage
    @State private var caption: String
    let onLog: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var captionFocused: Bool

    init(image: UIImage, initialCaption: String = "", onLog: @escaping (String?) -> Void) {
        self.image = image
        self._caption = State(initialValue: initialCaption)
        self.onLog = onLog
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 340)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                TextField(
                    "Add context (optional) — e.g. \"shake is whole milk + 1 scoop whey\"",
                    text: $caption,
                    axis: .vertical
                )
                .font(.subheadline)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .focused($captionFocused)
                Spacer()
            }
            .padding(20)
            .navigationTitle("Log meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Analyze") {
                        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
                        onLog(text.isEmpty ? nil : text)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
