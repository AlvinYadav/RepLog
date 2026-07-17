import SwiftUI
import SwiftData
import PhotosUI

/// The home screen: one page per day. Summary and plan first,
/// raw entries collapsed below, voice/text input pinned at the bottom.
struct JournalView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RawLog.timestamp, order: .reverse) private var logs: [RawLog]
    @Query(sort: \WorkoutSet.timestamp, order: .reverse) private var sets: [WorkoutSet]
    @Query(sort: \FoodEntry.timestamp, order: .reverse) private var foods: [FoodEntry]
    @Query(sort: \BodyWeightEntry.date, order: .reverse) private var weights: [BodyWeightEntry]
    @Query(sort: \SupplementEntry.timestamp, order: .reverse) private var supplements: [SupplementEntry]
    @Query private var profiles: [UserProfile]
    @Query private var exercises: [Exercise]

    @State private var selectedDate = Date()
    @State private var showDatePicker = false
    @State private var entriesExpanded = false
    @State private var draft = ""
    @State private var speech = SpeechRecognizer()
    @State private var showPhotoDialog = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var libraryItem: PhotosPickerItem?
    @FocusState private var inputFocused: Bool
    @State private var editingSet: WorkoutSet?
    @State private var editingFood: FoodEntry?
    @State private var editingWeight: BodyWeightEntry?

    private var calendar: Calendar { .current }
    private var isToday: Bool { calendar.isDateInToday(selectedDate) }
    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    header
                        .gesture(daySwipe)
                    summaryCard
                        .gesture(daySwipe)
                    if isToday {
                        planSection
                            .gesture(daySwipe)
                    }
                    entriesHeader
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))

                entryGroups
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.immediately)
            .safeAreaInset(edge: .bottom) { inputBar }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showDatePicker) { datePickerSheet }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { submitPhoto($0) }
                    .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showLibrary, selection: $libraryItem, matching: .images)
            .onChange(of: libraryItem) {
                guard let item = libraryItem else { return }
                libraryItem = nil
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        submitPhoto(image)
                    }
                }
            }
            .confirmationDialog("Log a meal photo", isPresented: $showPhotoDialog) {
                Button("Take photo") { showCamera = true }
                Button("Choose from library") { showLibrary = true }
            }
            .sheet(item: $editingSet) { SetEditSheet(workoutSet: $0) }
            .sheet(item: $editingFood) { FoodEditSheet(entry: $0) }
            .sheet(item: $editingWeight) { WeightEditSheet(entry: $0) }
            .task {
                LogPipeline.classifyExercisesIfNeeded(context: context)
            }
            .onAppear(perform: configureSpeech)
            .onChange(of: selectedDate) { configureSpeech() }
            .onChange(of: exercises.count) { configureSpeech() }
        }
    }

    // MARK: - Header

    private var dayLabel: String {
        if isToday { return "TODAY" }
        if calendar.isDateInYesterday(selectedDate) { return "YESTERDAY" }
        return selectedDate.formatted(.dateTime.year()).uppercased()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(dayLabel)
                .font(.caption2.weight(.medium))
                .tracking(2.5)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Button { showDatePicker = true } label: {
                    Text(selectedDate, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.system(.title, design: .serif, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                Spacer()
                HStack(spacing: 4) {
                    Button { shiftDay(-1) } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 34, height: 34)
                    }
                    Button { shiftDay(1) } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 34, height: 34)
                    }
                    .disabled(isToday)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                shiftDay(value.translation.width < 0 ? 1 : -1)
            }
    }

    private func shiftDay(_ delta: Int) {
        guard let newDate = calendar.date(byAdding: .day, value: delta, to: selectedDate) else { return }
        guard newDate <= Date() || calendar.isDateInToday(newDate) else { return }
        withAnimation(.snappy) { selectedDate = newDate }
    }

    private var datePickerSheet: some View {
        DatePicker("Date", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
            .datePickerStyle(.graphical)
            .padding()
            .presentationDetents([.medium])
            .onChange(of: selectedDate) { showDatePicker = false }
    }

    // MARK: - Summary

    private var metrics: DayMetrics {
        PlanEngine.metrics(on: selectedDate, foods: foods, sets: sets, weights: weights, supplements: supplements)
    }

    private var summaryCard: some View {
        let m = metrics
        return VStack(alignment: .leading, spacing: 14) {
            macroLine("Calories", Double(m.calories), Double(profile?.dailyCalories ?? 2500), unit: "kcal")
            macroLine("Protein", m.proteinG, Double(profile?.dailyProteinG ?? 150), unit: "g")
            macroLine("Carbs", m.carbsG, Double(profile?.dailyCarbsG ?? 300), unit: "g")
            macroLine("Fat", m.fatG, Double(profile?.dailyFatG ?? 80), unit: "g")
            Divider().padding(.vertical, 2)
            HStack {
                if m.setCount > 0 {
                    Text("\(m.setCount) sets · \(Int(m.volumeKg).formatted()) kg volume")
                } else {
                    Text("No training").foregroundStyle(.secondary)
                }
                Spacer()
                if let kg = m.weightKg {
                    Text(String(format: "%.1f kg", kg))
                }
                if !m.supplements.isEmpty {
                    Text(m.supplements.map { $0.capitalized }.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote.weight(.medium))
            .monospacedDigit()
        }
        .padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func macroLine(_ name: String, _ value: Double, _ target: Double, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(.footnote.weight(.medium))
                Spacer()
                Text("\(Int(value)) / \(Int(target)) \(unit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: geo.size.width * min(value / max(target, 1), 1))
                }
            }
            .frame(height: 4)
        }
    }

    // MARK: - Plan

    private var planLines: [String] {
        PlanEngine.recommendations(
            profile: profile,
            exercises: exercises,
            allSets: sets,
            allSupplements: supplements,
            today: metrics
        )
    }

    @ViewBuilder
    private var planSection: some View {
        let lines = planLines
        VStack(alignment: .leading, spacing: 12) {
            Text("Plan")
                .font(.system(.title3, design: .serif, weight: .semibold))
            if lines.isEmpty {
                Text("On track. Nothing to flag.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle()
                            .fill(.secondary)
                            .frame(width: 4, height: 4)
                            .offset(y: -2)
                        Text(line)
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    // MARK: - Entries

    private enum Item: Identifiable {
        case set(WorkoutSet)
        case food(FoodEntry)
        case weight(BodyWeightEntry)
        case supplement(SupplementEntry)
        case raw(RawLog)

        var id: PersistentIdentifier {
            switch self {
            case .set(let m): return m.persistentModelID
            case .food(let m): return m.persistentModelID
            case .weight(let m): return m.persistentModelID
            case .supplement(let m): return m.persistentModelID
            case .raw(let m): return m.persistentModelID
            }
        }

        var timestamp: Date {
            switch self {
            case .set(let m): return m.timestamp
            case .food(let m): return m.timestamp
            case .weight(let m): return m.date
            case .supplement(let m): return m.timestamp
            case .raw(let m): return m.timestamp
            }
        }
    }

    private var trainingItems: [Item] {
        sets.filter { calendar.isDate($0.timestamp, inSameDayAs: selectedDate) }.map(Item.set)
    }
    private var foodItems: [Item] {
        foods.filter { calendar.isDate($0.timestamp, inSameDayAs: selectedDate) }.map(Item.food)
    }
    private var supplementItems: [Item] {
        supplements.filter { calendar.isDate($0.timestamp, inSameDayAs: selectedDate) }.map(Item.supplement)
    }
    private var weightItems: [Item] {
        weights.filter { calendar.isDate($0.date, inSameDayAs: selectedDate) }.map(Item.weight)
    }
    private var noteItems: [Item] {
        logs.filter { calendar.isDate($0.timestamp, inSameDayAs: selectedDate) && $0.status == .note }.map(Item.raw)
    }
    /// Pending/failed rows: always visible, even collapsed.
    private var actionableItems: [Item] {
        logs.filter {
            calendar.isDate($0.timestamp, inSameDayAs: selectedDate) && ($0.status == .pending || $0.status == .failed)
        }.map(Item.raw)
    }

    private var entryCount: Int {
        trainingItems.count + foodItems.count + supplementItems.count
            + weightItems.count + noteItems.count + actionableItems.count
    }

    private var entriesHeader: some View {
        Button {
            withAnimation(.snappy) { entriesExpanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                Text("Entries")
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("\(entryCount)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(entriesExpanded ? 180 : 0))
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var entryGroups: some View {
        if entryCount == 0 {
            Text("Nothing logged.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 8, trailing: 20))
        } else if entriesExpanded {
            entryGroup("Training", trainingItems)
            entryGroup("Food", foodItems)
            entryGroup("Supplements", supplementItems)
            entryGroup("Weight", weightItems)
            entryGroup("Notes", noteItems + actionableItems)
        } else {
            ForEach(actionableItems) { item in
                row(for: item)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            }
        }
    }

    @ViewBuilder
    private func entryGroup(_ title: String, _ items: [Item]) -> some View {
        if !items.isEmpty {
            Text(title.uppercased())
                .font(.caption2.weight(.medium))
                .tracking(1.5)
                .foregroundStyle(.secondary)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 2, trailing: 20))
            ForEach(items) { item in
                row(for: item)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            }
        }
    }

    @ViewBuilder
    private func row(for item: Item) -> some View {
        Group {
            switch item {
            case .set(let set):
                Button { editingSet = set } label: { WorkoutSetCard(workoutSet: set) }
                    .buttonStyle(.plain)
            case .food(let food):
                Button { editingFood = food } label: { FoodCard(entry: food) }
                    .buttonStyle(.plain)
            case .weight(let weight):
                Button { editingWeight = weight } label: { WeightCard(entry: weight) }
                    .buttonStyle(.plain)
            case .supplement(let supplement):
                SupplementCard(entry: supplement)
            case .raw(let raw):
                RawLogRow(raw: raw) { LogPipeline.retry(raw, context: context) }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { delete(item) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func delete(_ item: Item) {
        switch item {
        case .set(let m): context.delete(m)
        case .food(let m): context.delete(m)
        case .weight(let m): context.delete(m)
        case .supplement(let m): context.delete(m)
        case .raw(let m): context.delete(m)
        }
    }

    // MARK: - Input

    private var entryTimestamp: Date {
        if isToday { return .now }
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: selectedDate) ?? selectedDate
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            if speech.isRecording {
                Text(speech.transcript.isEmpty ? "Listening…" : speech.transcript)
                    .font(.callout)
                    .foregroundStyle(speech.transcript.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
            if let error = speech.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                Button {
                    inputFocused = false
                    speech.toggle()
                } label: {
                    Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(speech.isRecording ? .red : Color(.systemBackground))
                        .frame(width: 44, height: 44)
                        .background(speech.isRecording ? Color(.secondarySystemBackground) : Color.primary, in: Circle())
                        .symbolEffect(.pulse, options: .repeating, isActive: speech.isRecording)
                }
                Button {
                    inputFocused = false
                    showPhotoDialog = true
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .background(Color(.secondarySystemBackground), in: Circle())
                }
                TextField(isToday ? "Log anything…" : "Log for this day…", text: $draft, axis: .vertical)
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit(submit)
                if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: submit) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color(.systemBackground))
                            .frame(width: 44, height: 44)
                            .background(Color.primary, in: Circle())
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { inputFocused = false }
            }
        }
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        LogPipeline.submit(text: text, at: entryTimestamp, context: context)
        draft = ""
        if !entriesExpanded { entriesExpanded = true }
    }

    /// Any text in the draft field rides along as a caption for the photo.
    private func submitPhoto(_ image: UIImage) {
        guard let jpeg = image.geminiJPEG() else { return }
        let caption = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        LogPipeline.submitPhoto(jpeg, caption: caption.isEmpty ? nil : caption, at: entryTimestamp, context: context)
        draft = ""
        if !entriesExpanded { entriesExpanded = true }
    }

    private func configureSpeech() {
        let timestamp = entryTimestamp
        speech.onFinish = { text in
            LogPipeline.submit(text: text, at: timestamp, context: context)
        }
        var vocabulary = exercises.flatMap { [$0.name] + $0.aliases }
        vocabulary += [
            "reps", "rep", "sets", "kilos", "kg", "RDL", "RDLs", "superset", "drop set",
            "bench press", "incline", "deadlift", "lat pulldown", "overhead press",
            "creatine", "protein shake", "pre-workout", "bodyweight", "PR", "scoop", "scoops"
        ]
        speech.vocabulary = vocabulary
    }
}

#Preview {
    JournalView()
        .modelContainer(
            for: [UserProfile.self, Exercise.self, WorkoutSet.self, FoodEntry.self,
                  BodyWeightEntry.self, SupplementEntry.self, RawLog.self],
            inMemory: true
        )
}
