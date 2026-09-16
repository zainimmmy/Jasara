import SwiftUI

/// One task line, shared by the To do list and the Calendar so a task looks the
/// same wherever it shows up.
struct TaskRow: View {
    @Environment(AppStore.self) private var store
    @Bindable var task: TaskItem
    var showsPriorityDot = true
    var onOpen: () -> Void

    @State private var expanded = false

    private var hasSubtasks: Bool { !task.subtasks.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                EmojiBubble(emoji: task.emoji, palette: task.palette)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if showsPriorityDot, task.priority != .none {
                            Circle().fill(task.priority.palette.ink)
                                .frame(width: 7, height: 7)
                                .accessibilityLabel("\(task.priority.shortTitle) priority")
                        }
                        Text(task.title)
                            .font(Face.rowStrong)
                            .strikethrough(task.isDone, color: Ink.muted)
                            .foregroundStyle(task.isDone ? Ink.muted : Ink.primary)
                            .lineLimit(2)
                    }
                    HStack(spacing: 8) {
                        if let minutes = task.durationMinutes {
                            Label(minutes.durationLabel, systemImage: "clock")
                                .labelStyle(.titleAndIcon)
                        }
                        if let reminder = task.reminderDate, task.reminderKind != .none {
                            Label(reminder.shortTime,
                                  systemImage: task.reminderKind == .alarm ? "alarm" : "bell")
                        }
                        if hasSubtasks {
                            Text("\(task.doneSubtasks)/\(task.subtasks.count)")
                        }
                        if task.repeatRule != .never {
                            Image(systemName: "repeat")
                        }
                    }
                    .font(Face.caption)
                    .foregroundStyle(Ink.muted)
                }

                Spacer(minLength: 4)

                if hasSubtasks {
                    Button {
                        withAnimation(.snappy(duration: 0.22)) { expanded.toggle() }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .rotationEffect(.degrees(expanded ? 0 : -90))
                            .foregroundStyle(Ink.muted)
                            .frame(width: 32, height: Metric.minTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(expanded ? "Hide subtasks" : "Show subtasks")
                }

                CheckCircle(isDone: task.isDone, palette: task.palette) {
                    withAnimation(.snappy) { store.toggle(task) }
                }
            }
            .padding(.leading, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)

            if hasSubtasks {
                SubtaskProgressBar(done: task.doneSubtasks, total: task.subtasks.count, palette: task.palette)
                    .padding(.horizontal, 12)
                    .padding(.bottom, expanded ? 6 : 10)
            }

            if expanded {
                VStack(spacing: 0) {
                    ForEach(task.orderedSubtasks) { subtask in
                        HStack(spacing: 10) {
                            CheckCircle(isDone: subtask.done, palette: task.palette) {
                                withAnimation(.snappy) { store.toggle(subtask) }
                            }
                            Text(subtask.title)
                                .font(Face.row)
                                .strikethrough(subtask.done, color: Ink.muted)
                                .foregroundStyle(subtask.done ? Ink.muted : Ink.primary)
                            Spacer()
                        }
                        .padding(.leading, 8)
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: Metric.rowCorner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metric.rowCorner, style: .continuous)
            .strokeBorder(Ink.line, lineWidth: 1))
    }
}

struct SubtaskProgressBar: View {
    var done: Int
    var total: Int
    var palette: Palette

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.line).frame(height: 5)
                Capsule().fill(palette.ink.opacity(0.85))
                    .frame(width: geo.size.width * fraction, height: 5)
            }
        }
        .frame(height: 5)
        .accessibilityLabel("\(done) of \(total) subtasks done")
    }

    private var fraction: Double {
        total == 0 ? 0 : Double(done) / Double(total)
    }
}
