import SwiftUI
import SwiftData

struct TaskEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Nil means we're creating one.
    var task: TaskItem?
    var presetPriority: Priority = .none
    var presetDate: Date?
    var presetSection: DaySection = .anytime

    @State private var title = ""
    @State private var emoji = "✅"
    @State private var palette = Palette.sky
    @State private var priority = Priority.none
    @State private var notes = ""
    @State private var hasDate = false
    @State private var date = Date()
    @State private var section = DaySection.anytime
    @State private var hasDuration = false
    @State private var duration = 25
    @State private var repeatRule = RepeatRule.never
    @State private var customDays = 0
    @State private var reminderKind = ReminderKind.none
    @State private var reminderDate = Date().addingTimeInterval(3600)
    @State private var autoComplete = true
    @State private var subtasks: [DraftSubtask] = []
    @State private var newSubtask = ""
    @State private var showEmojiPicker = false
    @State private var userPickedEmoji = false

    private var isNew: Bool { task == nil }
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Button { showEmojiPicker = true } label: {
                            EmojiBubble(emoji: emoji, palette: palette, size: 46)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Task icon, \(emoji)")

                        TextField("What needs doing?", text: $title, axis: .vertical)
                            .font(Face.rowStrong)
                            .onChange(of: title) { _, new in
                                // Suggest an icon while typing, but never overrule a choice.
                                guard !userPickedEmoji, isNew,
                                      let hint = EmojiCatalog.suggestion(for: new) else { return }
                                emoji = hint.emoji
                                palette = hint.color
                            }
                    }
                    .padding(.vertical, 4)

                    Picker("Priority", selection: $priority) {
                        ForEach(Priority.displayOrder, id: \.self) { option in
                            Text(option.shortTitle).tag(option)
                        }
                    }
                }

                Section("Subtasks") {
                    ForEach($subtasks) { $subtask in
                        HStack(spacing: 10) {
                            Button {
                                subtask.done.toggle()
                            } label: {
                                Image(systemName: subtask.done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(subtask.done ? palette.ink : Ink.muted)
                            }
                            .buttonStyle(.plain)
                            TextField("Step", text: $subtask.title)
                        }
                    }
                    .onDelete { subtasks.remove(atOffsets: $0) }

                    HStack {
                        Image(systemName: "plus").foregroundStyle(Ink.muted)
                        TextField("Add a step", text: $newSubtask)
                            .onSubmit(addSubtask)
                        if !newSubtask.isEmpty {
                            Button("Add", action: addSubtask)
                        }
                    }
                    if !subtasks.isEmpty {
                        Toggle("Complete the task when every step is done", isOn: $autoComplete)
                    }
                }

                Section("When") {
                    Toggle("Schedule for a day", isOn: $hasDate.animation())
                    if hasDate {
                        DatePicker("Day", selection: $date, displayedComponents: .date)
                        Picker("Part of day", selection: $section) {
                            ForEach(DaySection.allCases) { option in
                                Label(option.title, systemImage: option.symbol).tag(option)
                            }
                        }
                    }
                    Picker("Repeat", selection: $repeatRule) {
                        ForEach(RepeatRule.allCases) { rule in
                            Text(rule.title).tag(rule)
                        }
                    }
                    if repeatRule == .custom {
                        WeekdayPicker(mask: $customDays)
                    }
                    Toggle("Estimate how long", isOn: $hasDuration.animation())
                    if hasDuration {
                        Stepper("\(duration.durationLabel)", value: $duration, in: 5...480, step: 5)
                    }
                }

                Section("Reminder") {
                    Picker("Remind me", selection: $reminderKind.animation()) {
                        ForEach(ReminderKind.allCases, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    if reminderKind != .none {
                        DatePicker("At", selection: $reminderDate)
                        if reminderKind == .alarm {
                            Text("Rings like an alarm, even on silent or in Focus.")
                                .font(Face.caption).foregroundStyle(Ink.muted)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Anything worth remembering", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                if let task {
                    Section {
                        Button("Delete task", role: .destructive) {
                            NotificationScheduler.shared.cancelReminder(for: task)
                            context.delete(task)
                            store.save()
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Ink.background)
            .navigationTitle(isNew ? "New task" : "Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
            .sheet(isPresented: $showEmojiPicker) {
                EmojiPickerView(emoji: $emoji, palette: $palette)
                    .onDisappear { userPickedEmoji = true }
            }
            .onAppear(perform: load)
        }
    }

    // MARK: - Load and save

    private func load() {
        guard let task else {
            priority = presetPriority
            section = presetSection
            if let presetDate {
                hasDate = true
                date = presetDate
            }
            return
        }
        title = task.title
        emoji = task.emoji
        palette = task.palette
        priority = task.priority
        notes = task.notes
        hasDate = task.date != nil
        date = task.date ?? Date()
        section = task.section
        hasDuration = task.durationMinutes != nil
        duration = task.durationMinutes ?? 25
        repeatRule = task.repeatRule
        customDays = task.customDaysMask
        reminderKind = task.reminderKind
        reminderDate = task.reminderDate ?? Date().addingTimeInterval(3600)
        autoComplete = task.autoCompleteWithSubtasks
        subtasks = task.orderedSubtasks.map { DraftSubtask(title: $0.title, done: $0.done) }
        userPickedEmoji = true
    }

    private func addSubtask() {
        let trimmed = newSubtask.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        subtasks.append(DraftSubtask(title: trimmed, done: false))
        newSubtask = ""
    }

    private func save() {
        let target = task ?? TaskItem(title: "", emoji: emoji, color: palette, priority: priority)
        if task == nil { context.insert(target) }

        target.title = title.trimmingCharacters(in: .whitespaces)
        target.emoji = emoji
        target.palette = palette
        target.priority = priority
        target.notes = notes
        target.date = hasDate ? date : nil
        target.section = section
        target.durationMinutes = hasDuration ? duration : nil
        target.repeatRule = repeatRule
        target.customDaysMask = customDays
        target.reminderKind = reminderKind
        target.reminderDate = reminderKind == .none ? nil : reminderDate
        target.reminderChallengeRaw = nil
        target.autoCompleteWithSubtasks = autoComplete
        target.updatedAt = .now

        // Rebuild the subtask list in the order shown.
        for existing in target.subtasks { context.delete(existing) }
        target.subtasks = []
        for (index, item) in subtasks.enumerated() where !item.title.trimmingCharacters(in: .whitespaces).isEmpty {
            let subtask = Subtask(title: item.title, order: index)
            subtask.done = item.done
            subtask.parent = target
            context.insert(subtask)
        }

        store.save()
        Task {
            if target.reminderKind != .none {
                _ = await NotificationScheduler.shared.requestAuthorization()
                await NotificationScheduler.shared.scheduleReminder(for: target)
            } else {
                NotificationScheduler.shared.cancelReminder(for: target)
            }
        }
        dismiss()
    }
}

struct WeekdayPicker: View {
    @Binding var mask: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { weekday in
                let on = Weekdays.contains(mask, weekday: weekday)
                Button {
                    mask = Weekdays.toggle(mask, weekday: weekday)
                } label: {
                    Text(Weekdays.symbols[weekday - 1])
                        .font(Face.caption.weight(.bold))
                        .frame(width: 36, height: 36)
                        .background(on ? Palette.lilac.fill : Ink.surface, in: Circle())
                        .overlay(Circle().strokeBorder(on ? .clear : Ink.line, lineWidth: 1))
                        .foregroundStyle(on ? Palette.lilac.ink : Ink.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Weekdays.names[weekday - 1])
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// An in-flight subtask row. The real `Subtask` models are rebuilt on save, so
/// cancelling an edit never leaves half-written steps behind.
struct DraftSubtask: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var done: Bool
}
