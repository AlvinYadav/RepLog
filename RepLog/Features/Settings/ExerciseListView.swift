import SwiftUI
import SwiftData

struct ExerciseListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var draft = ""

    var body: some View {
        List {
            Section {
                ForEach(exercises) { exercise in
                    NavigationLink {
                        ExerciseDetailView(exercise: exercise)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                            if !exercise.aliases.isEmpty {
                                Text(exercise.aliases.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    for offset in offsets {
                        context.delete(exercises[offset])
                    }
                }
            }
            Section("Add exercise") {
                HStack {
                    TextField("e.g. Incline Dumbbell Press", text: $draft)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationTitle("Exercises")
    }

    private func add() {
        let name = draft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        context.insert(Exercise(name: name))
        draft = ""
    }
}

struct ExerciseDetailView: View {
    @Bindable var exercise: Exercise
    @State private var aliasDraft = ""

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $exercise.name)
            }
            Section("Aliases") {
                ForEach(exercise.aliases, id: \.self) { alias in
                    Text(alias)
                }
                .onDelete { exercise.aliases.remove(atOffsets: $0) }
                HStack {
                    TextField("e.g. incline db", text: $aliasDraft)
                        .autocapitalization(.none)
                        .onSubmit(addAlias)
                    Button("Add", action: addAlias)
                        .disabled(aliasDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Nicknames you use when speaking — helps the AI map onto this exercise.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addAlias() {
        let alias = aliasDraft.trimmingCharacters(in: .whitespaces)
        guard !alias.isEmpty else { return }
        exercise.aliases.append(alias)
        aliasDraft = ""
    }
}
