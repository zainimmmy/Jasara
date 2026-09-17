import SwiftUI
import SwiftData

struct TodoView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var context
    @Binding var showProfile: Bool

    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @State private var editing: TaskItem?
    @State private var newTaskPriority: Priority?
    @State private var suggestionSeed = Int.random(in: 0...999)
    @State private var showPrayerSetup = false
    @State private var showDone = false
    @State private var showUpcoming = false

    /// To do is about now: anything undated, overdue, or for today.
    private var open: [TaskItem] {
        let tomorrow = Date().startOfDay.adding(days: 1)
        return tasks.filter { !$0.isDone && ($0.date.map { $0 < tomorrow } ?? true) }
    }
    /// Planned for later, including the next copy of a repeating task.
    private var upcoming: [TaskItem] {
        let tomorrow = Date().startOfDay.adding(days: 1)
        return tasks
            .filter { !$0.isDone && ($0.date.map { $0 >= tomorrow } ?? false) }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }
    private var doneToday: [TaskItem] {
        tasks.filter { task in
            guard let completedAt = task.completedAt else { return false }
            return completedAt.isSameDay(as: .now)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(Priority.displayOrder, id: \.self) { priority in
                        let items = open.filter { $0.priority == priority }
                        if !items.isEmpty || priority == .none {
                            section(priority, items)
                        }
                    }

                    if !upcoming.isEmpty { upcomingSection }
                    if !doneToday.isEmpty { doneSection }
                    suggestions
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.bottom, 40)
            }
            .background(Ink.background)
            .navigationTitle("To do")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { TopBar(showProfile: $showProfile) }
            .sheet(item: $editing) { task in
                TaskEditorView(task: task)
            }
            .sheet(item: $newTaskPriority) { priority in
                TaskEditorView(task: nil, presetPriority: priority)
            }
            .sheet(isPresented: $showPrayerSetup) { PrayerSetupView() }
        }
    }

    private func section(_ priority: Priority, _ items: [TaskItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderRow(title: priority.title,
                             symbol: nil,
                             palette: priority.palette,
                             count: items.count) {
                newTaskPriority = priority
            }
            ForEach(items) { task in
                TaskRow(task: task, showsPriorityDot: false) { editing = task }
                    .contextMenu { rowMenu(task) }
            }
            DashedAddRow(title: priority == .none ? "Add task" : "Add \(priority.shortTitle.lowercased()) priority task") {
                newTaskPriority = priority
            }
        }
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { showUpcoming.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Upcoming").font(Face.sectionTitle).foregroundStyle(Ink.muted)
                    Text("\(upcoming.count)")
                        .font(Face.caption.weight(.bold))
                        .foregroundStyle(Ink.muted)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .rotationEffect(.degrees(showUpcoming ? 0 : -90))
                        .foregroundStyle(Ink.muted)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)

            if showUpcoming {
                ForEach(upcoming) { task in
                    VStack(alignment: .leading, spacing: 4) {
                        if let date = task.date {
                            Text(date.formatted(.dateTime.weekday(.wide).day().month()))
                                .font(Face.caption).foregroundStyle(Ink.muted)
                                .padding(.horizontal, 4)
                        }
                        TaskRow(task: task) { editing = task }
                            .contextMenu { rowMenu(task) }
                    }
                }
            }
        }
    }

    private var doneSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { showDone.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Done today").font(Face.sectionTitle).foregroundStyle(Ink.muted)
                    Text("\(doneToday.count)")
                        .font(Face.caption.weight(.bold))
                        .foregroundStyle(Ink.muted)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .rotationEffect(.degrees(showDone ? 0 : -90))
                        .foregroundStyle(Ink.muted)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)

            if showDone {
                ForEach(doneToday) { task in
                    TaskRow(task: task) { editing = task }
                }
            }
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Suggested").font(Face.sectionTitle).foregroundStyle(Ink.muted)
                Spacer()
                Button {
                    withAnimation(.snappy) { suggestionSeed += 1 }
                    store.tap()
                } label: {
                    Image(systemName: "arrow.trianglehead.2.clockwise")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Ink.muted)
                        .frame(width: Metric.minTarget, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show different suggestions")
            }
            .padding(.horizontal, 4)

            ForEach(SuggestedTask.sample(seed: suggestionSeed,
                                         includePrayers: !store.prayerSettings.isEnabled)) { suggestion in
                Button {
                    add(suggestion)
                } label: {
                    HStack(spacing: 10) {
                        EmojiBubble(emoji: suggestion.emoji, palette: suggestion.color, size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(suggestion.title).font(Face.row)
                            if let minutes = suggestion.minutes {
                                Text(minutes.durationLabel).font(Face.caption).foregroundStyle(Ink.muted)
                            } else if suggestion.opensPrayerSetup {
                                Text("Sets up prayer times and reminders")
                                    .font(Face.caption).foregroundStyle(Ink.muted)
                            }
                        }
                        Spacer()
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Ink.muted)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(Ink.surface.opacity(0.6),
                                in: RoundedRectangle(cornerRadius: Metric.rowCorner, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private func rowMenu(_ task: TaskItem) -> some View {
        Button("Edit") { editing = task }
        Menu("Priority") {
            ForEach(Priority.displayOrder, id: \.self) { priority in
                Button(priority.shortTitle) {
                    withAnimation(.snappy) { task.priority = priority }
                    store.save()
                }
            }
        }
        Button("Delete", role: .destructive) {
            NotificationScheduler.shared.cancelReminder(for: task)
            context.delete(task)
            store.save()
        }
    }

    private func add(_ suggestion: SuggestedTask) {
        store.tap()
        guard !suggestion.opensPrayerSetup else {
            showPrayerSetup = true
            return
        }
        let task = suggestion.makeTask()
        context.insert(task)
        store.save()
    }
}

