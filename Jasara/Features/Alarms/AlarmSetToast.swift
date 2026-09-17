import SwiftUI

/// "Alarm set for 7 hr and 30 min from now": a see-through note above the tab
/// bar that shows for a few seconds and fades away on its own. It never blocks
/// taps, and VoiceOver hears it through an announcement instead.
struct AlarmSetToast: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let visibleFor: Duration = .seconds(3)

    var body: some View {
        VStack {
            Spacer()
            if let note = store.alarmSetNote {
                HStack(spacing: 8) {
                    Image(systemName: "alarm.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text(note.text)
                        .font(Face.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Ink.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Ink.primary.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                .padding(.horizontal, Metric.gutter)
                // Sits just above the floating tab bar.
                .padding(.bottom, 96)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .task(id: note.id) {
                    try? await Task.sleep(for: Self.visibleFor)
                    store.dismissAlarmSetNote(note.id)
                }
            }
        }
        .animation(.spring(duration: 0.4), value: store.alarmSetNote)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
