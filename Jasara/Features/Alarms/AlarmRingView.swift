import SwiftUI
import AudioToolbox
import UIKit

/// Picks the right challenge for an alarm. Both the real ring screen and the
/// silent "Try it" preview go through here, so a preview is honestly the same
/// thing the user will face at 6am.
struct ChallengeRunner: View {
    var challenge: Challenge
    var tier: Tier
    var rounds: Int
    var wordCount: Int
    var phrases: [String]
    var onComplete: () -> Void

    var body: some View {
        switch challenge {
        case .math:
            MathChallengeView(tier: tier, rounds: rounds, onComplete: onComplete)
        case .shake:
            ShakeChallengeView(tier: tier, rounds: rounds, onComplete: onComplete)
        case .typing:
            TypingChallengeView(tier: tier, rounds: rounds, wordCount: wordCount,
                                prepared: phrases, onComplete: onComplete)
        case .tiles:
            TileChallengeView(tier: tier, rounds: rounds, onComplete: onComplete)
        case .overstimulated:
            OverstimulatedView(onComplete: onComplete)
        case .nfc, .photo:
            VStack(spacing: 14) {
                Text("Not in this build yet")
                    .font(Face.title(20))
                Text("The \(challenge.title) challenge needs hardware setup. Pick another challenge for now.")
                    .font(Face.caption)
                    .foregroundStyle(Ink.muted)
                    .multilineTextAlignment(.center)
                PrimaryButton(title: "Stop alarm", palette: .mint, action: onComplete)
            }
            .padding(Metric.gutter)
        }
    }
}

struct AlarmRingView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Bindable var alarm: AlarmItem

    @State private var solved = false
    @State private var audio = AlarmAudio()
    @State private var confirmingEmergency = false

    /// Kept in AlarmRuntime, because snoozes taken from the lock screen count too.
    private var snoozes: Int { AlarmRuntime.snoozes(for: alarm.id) }
    private var canSnooze: Bool { snoozes < alarm.effectiveMaxSnoozes }

    var body: some View {
        ZStack {
            Ink.dawn.ignoresSafeArea()
            VStack(spacing: 18) {
                header

                if alarm.mode == .challenge && !solved {
                    ChallengeRunner(challenge: alarm.challenge,
                                    tier: alarm.tier,
                                    rounds: alarm.rounds,
                                    wordCount: alarm.typingWordCount,
                                    phrases: alarm.preparedPhrases) {
                        finish()
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    Spacer()
                    PrimaryButton(title: "Stop", palette: .mint) { finish() }
                        .padding(.horizontal, Metric.gutter)
                }

                footer
            }
            .padding(.top, 30)
        }
        .onAppear { audio.start() }
        .onDisappear { audio.stop() }
        .confirmationDialog("End the alarm without finishing?",
                            isPresented: $confirmingEmergency, titleVisibility: .visible) {
            Button("End alarm", role: .destructive) { emergencyStop() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("No XP, and the wake streak resets. Use it whenever you actually need to.")
        }
        .interactiveDismissDisabled()
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(Date.now.formatted(date: .omitted, time: .shortened))
                .font(Face.display(46)).monospacedDigit()
            Text(alarm.label.isEmpty ? "Alarm" : alarm.label)
                .font(Face.rowStrong)
                .foregroundStyle(Ink.primary.opacity(0.8))
            if snoozes > 0 {
                Text("Snoozed \(snoozes)× — wake XP is now \(XPRules.wakeXP(snoozes: snoozes))")
                    .font(Face.caption)
                    .foregroundStyle(Ink.primary.opacity(0.7))
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if canSnooze {
                Button {
                    snooze()
                } label: {
                    Text("Snooze \(alarm.snoozeMinutes) min  •  −\(XPRules.snoozePenalty) XP")
                        .font(Face.rowStrong)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Ink.surface.opacity(0.85),
                                    in: RoundedRectangle(cornerRadius: Metric.corner, style: .continuous))
                        .foregroundStyle(Ink.primary)
                }
                .buttonStyle(.plain)
            }
            HoldToStopButton { confirmingEmergency = true }
        }
        .padding(.horizontal, Metric.gutter)
        .padding(.bottom, 24)
    }

    // MARK: - Outcomes

    private func finish() {
        solved = true
        audio.stop()
        store.recordWake(alarm: alarm, snoozes: snoozes, emergencyStopped: false)
        store.scheduler.settleWake(for: alarm.id)
        store.ringingAlarmID = nil
        dismiss()
    }

    private func snooze() {
        AlarmRuntime.addSnooze(for: alarm.id)
        audio.stop()
        Task {
            await store.scheduler.scheduleFollowUp(for: alarm,
                                                   after: Double(alarm.snoozeMinutes) * 60)
        }
        store.ringingAlarmID = nil
        dismiss()
    }

    private func emergencyStop() {
        audio.stop()
        store.recordWake(alarm: alarm, snoozes: snoozes, emergencyStopped: true)
        store.scheduler.settleWake(for: alarm.id)
        store.ringingAlarmID = nil
        dismiss()
    }
}

/// Ten seconds of deliberate pressure, then a confirmation. It always works —
/// that's the point. Nothing here blocks the volume buttons or the silent switch.
struct HoldToStopButton: View {
    var onHeld: () -> Void

    @State private var held: Double = 0
    @State private var timer: Timer?
    private let required: Double = 10

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Metric.corner, style: .continuous)
                .fill(Ink.surface.opacity(0.6))
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: Metric.corner, style: .continuous)
                    .fill(Palette.blush.fill)
                    .frame(width: geo.size.width * (held / required))
            }
            .clipShape(RoundedRectangle(cornerRadius: Metric.corner, style: .continuous))
            Text(held > 0 ? "Keep holding… \(Int(required - held))s" : "Hold for emergency stop")
                .font(Face.caption.weight(.semibold))
                .foregroundStyle(Ink.primary.opacity(0.8))
                .monospacedDigit()
        }
        .frame(height: 46)
        .contentShape(Rectangle())
        .onDisappear { cancel() }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in start() }
                .onEnded { _ in cancel() }
        )
        .accessibilityLabel("Emergency stop. Hold for ten seconds.")
        .accessibilityAddTraits(.isButton)
    }

    private func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            held += 0.1
            if held >= required {
                cancel()
                onHeld()
            }
        }
    }

    private func cancel() {
        timer?.invalidate()
        timer = nil
        withAnimation(.easeOut(duration: 0.2)) { held = 0 }
    }
}

/// The silent "Try it" run from the alarm editor, with a skip button, so nobody
/// signs up for Hell tier without seeing what it looks like first.
struct ChallengePreview: View {
    @Environment(\.dismiss) private var dismiss
    var challenge: Challenge
    var tier: Tier
    var rounds: Int
    var wordCount: Int

    var body: some View {
        ZStack {
            Ink.background.ignoresSafeArea()
            VStack(spacing: 12) {
                HStack {
                    Text("Preview — no alarm sound")
                        .font(Face.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Palette.sky.fill, in: Capsule())
                        .foregroundStyle(Palette.sky.ink)
                    Spacer()
                    Button("Skip") { dismiss() }
                        .font(Face.rowStrong)
                        .frame(minWidth: 60, minHeight: Metric.minTarget)
                }
                .padding(.horizontal, Metric.gutter)

                ChallengeRunner(challenge: challenge, tier: tier, rounds: rounds,
                                wordCount: wordCount, phrases: []) {
                    dismiss()
                }
                .frame(maxHeight: .infinity)
            }
            .padding(.top, 12)
        }
    }
}

/// Placeholder audio: a system alert tone on a repeat plus vibration. A licensed
/// clip under 30 seconds replaces this before release, and AlarmKit takes over
/// the ringing itself.
@Observable
final class AlarmAudio {
    private var timer: Timer?

    func start() {
        stop()
        pulse()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pulse()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func pulse() {
        AudioServicesPlayAlertSound(SystemSoundID(1304))
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
}
