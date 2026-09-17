import SwiftUI
import SwiftData

struct AlarmListView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var context
    @Binding var showProfile: Bool

    @Query(sort: [SortDescriptor(\AlarmItem.hour), SortDescriptor(\AlarmItem.minute)])
    private var allAlarms: [AlarmItem]

    /// Group alarms live in their own section and are managed through the group.
    private var alarms: [AlarmItem] { allAlarms.filter { !$0.isGroupAlarm } }

    @State private var editing: AlarmItem?
    @State private var creating = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    GroupAlarmsSection()
                        .padding(.bottom, 8)

                    SectionHeaderRow(title: "My alarms", symbol: "alarm", palette: .sky,
                                     count: alarms.count, onAdd: { creating = true })
                    if alarms.isEmpty {
                        EmptyHint(emoji: "⏰", text: "No alarms yet.\nAdd one and pick how hard it should be to switch off.")
                    }
                    ForEach(alarms) { alarm in
                        AlarmCard(alarm: alarm,
                                  onEdit: { editing = alarm })
                    }
                    DashedAddRow(title: "Add alarm") { creating = true }

                    Text("Challenge alarms keep ringing until the challenge is solved. Holding the emergency stop for 10 seconds always works — it just ends the streak.")
                        .font(Face.caption)
                        .foregroundStyle(Ink.muted)
                        .padding(.horizontal, 4)
                        .padding(.top, 6)
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.bottom, 40)
            }
            .background(Ink.background)
            .navigationTitle("Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { TopBar(showProfile: $showProfile) }
            .sheet(item: $editing) { AlarmEditorView(alarm: $0) }
            .sheet(isPresented: $creating) { AlarmEditorView(alarm: nil) }
        }
    }
}

struct AlarmCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var context
    @Bindable var alarm: AlarmItem
    var onEdit: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "%d:%02d", displayHour, alarm.minute))
                        .font(Face.display(38)).monospacedDigit()
                        .foregroundStyle(alarm.isEnabled ? Ink.primary : Ink.muted)
                    Text(meridiem).font(Face.rowStrong).foregroundStyle(Ink.muted)
                    Spacer()
                    // A binding rather than onChange, so only a real tap announces
                    // anything, never the app switching a spent one-off off.
                    Toggle("", isOn: Binding(get: { alarm.isEnabled }, set: { on in
                        alarm.isEnabled = on
                        store.save()
                        Task {
                            await store.scheduler.schedule(alarm)
                            if on { store.announceAlarmSet(ringsAt: alarm.nextFireDate()) }
                        }
                    }))
                        .labelsHidden()
                        .tint(Palette.mint.ink)
                        .accessibilityLabel("\(alarm.label) alarm")
                }

                HStack(spacing: 8) {
                    Text(alarm.label.isEmpty ? "Alarm" : alarm.label)
                        .font(Face.rowStrong)
                    Text("•").foregroundStyle(Ink.muted)
                    Text(Weekdays.describe(alarm.weekdaysMask))
                        .font(Face.caption).foregroundStyle(Ink.muted)
                    Spacer()
                }

                HStack(spacing: 6) {
                    if alarm.mode == .challenge {
                        Text("\(alarm.challenge.emoji) \(alarm.challenge.title)")
                            .font(Face.caption.weight(.semibold))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Palette.lilac.fill, in: Capsule())
                            .foregroundStyle(Palette.lilac.ink)
                        if alarm.challenge.supportsTiers {
                            Text("\(alarm.tier.title) • \(alarm.rounds) round\(alarm.rounds == 1 ? "" : "s")")
                                .font(Face.caption.weight(.semibold))
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(alarm.tier.palette.fill, in: Capsule())
                                .foregroundStyle(alarm.tier.palette.ink)
                        }
                    } else {
                        Text("Regular")
                            .font(Face.caption.weight(.semibold))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Palette.sand.fill, in: Capsule())
                            .foregroundStyle(Palette.sand.ink)
                    }
                    Spacer()
                    Text(alarm.effectiveMaxSnoozes == 0 ? "No snooze" : "\(alarm.effectiveMaxSnoozes) × \(alarm.snoozeMinutes)m")
                        .font(Face.caption).foregroundStyle(Ink.muted)
                }
            }
        }
        .opacity(alarm.isEnabled ? 1 : 0.6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .contextMenu {
            Button("Edit", action: onEdit)
            Button("Delete", role: .destructive) {
                store.scheduler.cancel(alarmID: alarm.id)
                context.delete(alarm)
                store.save()
            }
        }
    }

    private var displayHour: Int {
        let hour = alarm.hour % 12
        return hour == 0 ? 12 : hour
    }
    private var meridiem: String { alarm.hour < 12 ? "AM" : "PM" }
}
