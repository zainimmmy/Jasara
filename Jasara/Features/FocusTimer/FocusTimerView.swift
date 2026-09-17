import SwiftUI
import UserNotifications
import SwiftData

/// Ring countdown with the task's emoji in the middle. Start it from a task or
/// on its own. XP is 1 per five minutes, capped at 30 a day, and anything under
/// five minutes earns nothing.
struct FocusTimerView: View {
    @Environment(AppStore.self) private var store
    @Binding var showProfile: Bool

    @Query private var tasks: [TaskItem]
    @State private var minutes = 25
    @State private var remaining = 25 * 60
    @State private var running = false
    @State private var linkedTask: TaskItem?
    @State private var timer: Timer?
    @State private var finished = false
    /// While running, the countdown is worked out from this moment rather than
    /// by counting ticks, so switching tabs or locking the phone doesn't lose time.
    @State private var endsAt: Date?
    @Environment(\.scenePhase) private var scenePhase

    private var total: Int { max(minutes * 60, 1) }
    private var fraction: Double { Double(remaining) / Double(total) }
    private var openTasks: [TaskItem] { tasks.filter { !$0.isDone }.prefix(8).map { $0 } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ring
                    controls
                    presets
                    taskPicker
                    footnote
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.bottom, 40)
            }
            .background(Ink.background)
            .navigationTitle("Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { TopBar(showProfile: $showProfile) }
            // Ticks stop while the app is in the background; catch up on return.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { tick() }
            }
        }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Ink.line, lineWidth: 16)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Palette.lilac.ink, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: remaining)
            VStack(spacing: 4) {
                Text(linkedTask?.emoji ?? "⏳").font(.system(size: 34))
                Text(remaining.clockLabel)
                    .font(Face.display(42)).monospacedDigit()
                if let linkedTask {
                    Text(linkedTask.title)
                        .font(Face.caption)
                        .foregroundStyle(Ink.muted)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: 250, height: 250)
        .padding(.top, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(remaining / 60) minutes \(remaining % 60) seconds remaining")
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 54, height: 54)
                    .background(Ink.surface, in: Circle())
                    .foregroundStyle(Ink.muted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reset")

            Button {
                running ? pause() : start()
            } label: {
                Image(systemName: running ? "pause.fill" : "play.fill")
                    .font(.system(size: 24, weight: .bold))
                    .frame(width: 74, height: 74)
                    .background(Palette.lilac.fill, in: Circle())
                    .foregroundStyle(Palette.lilac.ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(running ? "Pause" : "Start")

            Button {
                complete()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 54, height: 54)
                    .background(Ink.surface, in: Circle())
                    .foregroundStyle(Ink.muted)
            }
            .buttonStyle(.plain)
            .disabled(remaining == total)
            .accessibilityLabel("Finish early and bank the time")
        }
    }

    private var presets: some View {
        HStack(spacing: 8) {
            ForEach([5, 15, 25, 45, 60], id: \.self) { option in
                ChipToggle(title: "\(option)m", isOn: minutes == option, palette: .lilac) {
                    minutes = option
                    reset()
                }
            }
        }
    }

    @ViewBuilder
    private var taskPicker: some View {
        if !openTasks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Focus on").font(Face.sectionTitle).foregroundStyle(Ink.muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ChipToggle(title: "Nothing in particular",
                                   isOn: linkedTask == nil, palette: .sand) {
                            linkedTask = nil
                        }
                        ForEach(openTasks) { task in
                            ChipToggle(title: "\(task.emoji) \(task.title)",
                                       isOn: linkedTask?.id == task.id,
                                       palette: task.palette) {
                                linkedTask = task
                                if let duration = task.durationMinutes {
                                    minutes = duration
                                    reset()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footnote: some View {
        Text(finished
             ? "Session banked. \(XPRules.timerPerFiveMinutes) XP per five minutes, up to \(XPRules.timerDailyCap) a day."
             : "1 XP per five minutes, up to \(XPRules.timerDailyCap) a day. Under five minutes earns nothing.")
            .font(Face.caption)
            .foregroundStyle(Ink.muted)
            .multilineTextAlignment(.center)
    }

    // MARK: - Running

    private static let doneNotification = "focus.done"

    private func start() {
        running = true
        finished = false
        endsAt = Date().addingTimeInterval(Double(remaining))
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in tick() }
        scheduleDoneNotification()
    }

    private func tick() {
        guard running, let endsAt else { return }
        remaining = max(0, Int(endsAt.timeIntervalSinceNow.rounded(.up)))
        if remaining == 0 { complete() }
    }

    private func pause() {
        tick()
        running = false
        endsAt = nil
        timer?.invalidate()
        timer = nil
        cancelDoneNotification()
    }

    private func reset() {
        pause()
        remaining = minutes * 60
        finished = false
    }

    private func complete() {
        let elapsed = total - remaining
        pause()
        guard elapsed > 0 else { return }
        store.recordFocus(seconds: elapsed,
                          plannedMinutes: minutes,
                          taskTitle: linkedTask?.title,
                          emoji: linkedTask?.emoji ?? "⏳")
        finished = true
        remaining = minutes * 60
    }

    /// So a session that ends while the phone is locked still says so.
    private func scheduleDoneNotification() {
        guard let endsAt else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(linkedTask?.emoji ?? "⏳") Focus session done"
        content.body = linkedTask.map { "Nice work on \($0.title)." } ?? "Time for a break."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, endsAt.timeIntervalSinceNow),
                                                        repeats: false)
        Task {
            _ = await NotificationScheduler.shared.requestAuthorization()
            try? await UNUserNotificationCenter.current()
                .add(UNNotificationRequest(identifier: Self.doneNotification, content: content, trigger: trigger))
        }
    }

    private func cancelDoneNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.doneNotification])
    }
}
