import SwiftUI
import SwiftData

struct CalendarTabView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var context
    @Binding var showProfile: Bool

    @Query private var tasks: [TaskItem]
    @State private var selectedDay = Date()
    @State private var showMonthPicker = false
    @State private var editing: TaskItem?
    @State private var newIn: DaySection?
    @State private var events = CalendarEvents()
    @State private var showConnectTip = true

    private var dayTasks: [TaskItem] {
        tasks.filter { task in
            guard let date = task.date else { return false }
            return date.isSameDay(as: selectedDay)
        }
    }

    private var prayerEntries: [PrayerService.Entry] {
        guard store.prayerSettings.isEnabled else { return [] }
        return store.prayers.entries(for: selectedDay, settings: store.prayerSettings) ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    WeekStrip(selected: $selectedDay,
                              firstWeekdayIsMonday: store.profile.firstWeekdayIsMonday)

                    if showConnectTip && !events.isConnected {
                        TipCard(emoji: "📅",
                                title: "Connect your calendar",
                                message: "Show the events you already have beside today's plan.",
                                onDismiss: { showConnectTip = false },
                                onTap: { Task { await events.requestAccess(); events.refresh(for: selectedDay) } })
                    }

                    ForEach(DaySection.allCases) { section in
                        sectionView(section)
                    }
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.bottom, 40)
            }
            .background(Ink.background)
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { TopBar(showProfile: $showProfile) }
            .sheet(item: $editing) { TaskEditorView(task: $0) }
            .sheet(item: $newIn) { section in
                TaskEditorView(task: nil, presetDate: selectedDay, presetSection: section)
            }
            .sheet(isPresented: $showMonthPicker) {
                MonthPicker(selected: $selectedDay)
                    .presentationDetents([.medium])
            }
            .onAppear { events.refresh(for: selectedDay) }
            .onChange(of: selectedDay) { _, day in events.refresh(for: day) }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text(selectedDay.formatted(.dateTime.weekday(.wide)))
                    .font(Face.display(28))
                Button {
                    showMonthPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedDay.formatted(.dateTime.month(.wide).year()))
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                    }
                    .font(Face.caption.weight(.semibold))
                    .foregroundStyle(Ink.muted)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if !selectedDay.isSameDay(as: .now) {
                Button("Today") { withAnimation(.snappy) { selectedDay = .now } }
                    .font(Face.caption.weight(.bold))
            }
        }
        .padding(.top, 4)
    }

    private func sectionView(_ section: DaySection) -> some View {
        let items = dayTasks.filter { $0.section == section }
        let prayers = prayerEntries.filter { PrayerService.section(for: $0.time) == section }
        let dayEvents = events.items.filter { $0.section == section }
        let count = items.count + prayers.count + dayEvents.count

        return VStack(alignment: .leading, spacing: 8) {
            SectionHeaderRow(title: section.title,
                             symbol: section.symbol,
                             palette: palette(for: section),
                             count: count) {
                newIn = section
            }

            ForEach(prayers) { entry in
                PrayerRow(entry: entry, day: selectedDay)
            }

            ForEach(dayEvents) { event in
                HStack(spacing: 10) {
                    EmojiBubble(emoji: "📆", palette: .sand, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title).font(Face.rowStrong)
                        Text(event.isAllDay ? "All day" : "\(event.start.shortTime) – \(event.end.shortTime)")
                            .font(Face.caption).foregroundStyle(Ink.muted)
                    }
                    Spacer()
                    Text("Calendar").font(Face.caption).foregroundStyle(Ink.muted)
                }
                .padding(.leading, 12).padding(.vertical, 10).padding(.trailing, 12)
                .background(Ink.surface, in: RoundedRectangle(cornerRadius: Metric.rowCorner, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Metric.rowCorner, style: .continuous)
                    .strokeBorder(Ink.line, lineWidth: 1))
            }

            ForEach(items) { task in
                TaskRow(task: task) { editing = task }
            }

            if count == 0 {
                DashedAddRow(title: "Add to \(section.title.lowercased())") { newIn = section }
            }
        }
    }

    private func palette(for section: DaySection) -> Palette {
        switch section {
        case .anytime: return .sand
        case .morning: return .butter
        case .afternoon: return .sky
        case .evening: return .lilac
        }
    }
}

/// The five daily prayers sit in the day like any other row, with a tick that
/// logs them and cancels the remaining nudges.
struct PrayerRow: View {
    @Environment(AppStore.self) private var store
    var entry: PrayerService.Entry
    var day: Date

    private var log: PrayerLog { store.log(for: entry.prayer, on: day) }

    var body: some View {
        HStack(spacing: 10) {
            EmojiBubble(emoji: "🕌", palette: .mint)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(Face.rowStrong)
                HStack(spacing: 6) {
                    Text(entry.time.shortTime)
                    if log.status == .qada { Text("• made up") }
                    if log.status == .missed { Text("• missed") }
                }
                .font(Face.caption).foregroundStyle(Ink.muted)
            }
            Spacer()
            Menu {
                Button("Prayed") { store.mark(entry.prayer, on: day, as: .prayed, scheduledAt: entry.time) }
                Button("Made up (qada)") { store.mark(entry.prayer, on: day, as: .qada, scheduledAt: nil) }
                Button("Missed") { store.mark(entry.prayer, on: day, as: .missed, scheduledAt: nil) }
                if log.status != .pending {
                    Button("Clear") { store.mark(entry.prayer, on: day, as: .pending, scheduledAt: nil) }
                }
            } label: {
                CheckCircleLabel(isDone: log.status == .prayed || log.status == .qada)
            }
        }
        .padding(.leading, 12).padding(.vertical, 10).padding(.trailing, 6)
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: Metric.rowCorner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metric.rowCorner, style: .continuous)
            .strokeBorder(Ink.line, lineWidth: 1))
    }
}

struct CheckCircleLabel: View {
    var isDone: Bool
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isDone ? Palette.mint.ink : Ink.line, lineWidth: 2)
                .frame(width: 24, height: 24)
            if isDone {
                Circle().fill(Palette.mint.ink).frame(width: 24, height: 24)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.mint.fill)
            }
        }
        .frame(width: Metric.minTarget, height: Metric.minTarget)
        .contentShape(Rectangle())
    }
}

struct WeekStrip: View {
    @Binding var selected: Date
    var firstWeekdayIsMonday: Bool

    private var days: [Date] {
        let calendar = Calendar.app(firstWeekdayIsMonday: firstWeekdayIsMonday)
        let weekday = calendar.component(.weekday, from: selected)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let start = selected.adding(days: -offset)
        return (0..<7).map { start.adding(days: $0) }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(days, id: \.timeIntervalSince1970) { day in
                let isSelected = day.isSameDay(as: selected)
                let isToday = day.isSameDay(as: .now)
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selected = day }
                } label: {
                    VStack(spacing: 3) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(Face.caption)
                            .foregroundStyle(isSelected ? Palette.lilac.ink : Ink.muted)
                        Text(day.formatted(.dateTime.day()))
                            .font(Face.rowStrong).monospacedDigit()
                            .foregroundStyle(isSelected ? Palette.lilac.ink : Ink.primary)
                        Circle()
                            .fill(isToday ? Palette.blush.ink : .clear)
                            .frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(isSelected ? Palette.lilac.fill : Ink.surface,
                                in: RoundedRectangle(cornerRadius: Metric.rowCorner, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Metric.rowCorner, style: .continuous)
                        .strokeBorder(isSelected ? .clear : Ink.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

struct MonthPicker: View {
    @Binding var selected: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker("Day", selection: $selected, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Jump to")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
    }
}

