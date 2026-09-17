import SwiftUI
import SwiftData

struct AlarmEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var alarm: AlarmItem?

    @State private var time = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now) ?? .now
    @State private var label = "Alarm"
    @State private var days = 0
    @State private var mode = AlarmMode.regular
    @State private var challenge = Challenge.math
    @State private var tier = Tier.normal
    @State private var rounds = 3
    @State private var wordCount = 6
    @State private var snoozeEnabled = true
    @State private var snoozeMinutes = 9
    @State private var maxSnoozes = 3
    @State private var showExplainer = false
    @State private var previewing = false

    private var isNew: Bool { alarm == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    TextField("Label", text: $label)
                }

                Section("Repeat") {
                    WeekdayPicker(mask: $days)
                        .padding(.vertical, 4)
                    Text(Weekdays.describe(days))
                        .font(Face.caption).foregroundStyle(Ink.muted)
                }

                Section("How it stops") {
                    Picker("Mode", selection: $mode.animation()) {
                        Text("Regular").tag(AlarmMode.regular)
                        Text("Challenge").tag(AlarmMode.challenge)
                    }
                    .pickerStyle(.segmented)

                    if mode == .challenge {
                        Picker("Challenge", selection: $challenge.animation()) {
                            ForEach(Challenge.allCases) { option in
                                HStack {
                                    Text("\(option.emoji)  \(option.title)")
                                    if !option.isImplemented { Text("— coming soon") }
                                }
                                .tag(option)
                            }
                        }
                        Text(challenge.blurb).font(Face.caption).foregroundStyle(Ink.muted)

                        if !challenge.isImplemented {
                            Label("NFC and Photo challenges need hardware setup and aren't in this build yet.",
                                  systemImage: "exclamationmark.triangle")
                                .font(Face.caption)
                                .foregroundStyle(Palette.butter.ink)
                        }

                        if challenge.supportsTiers {
                            Picker("Difficulty", selection: $tier) {
                                ForEach(Tier.allCases) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                            tierPreview
                            Stepper("Rounds: \(rounds)", value: $rounds, in: 1...100)
                            if challenge == .typing {
                                Stepper("Words per phrase: \(wordCount)", value: $wordCount, in: 2...50)
                            }
                            HStack {
                                Text("Tier bonus")
                                Spacer()
                                Text("+\(tier.xpBonus) XP").foregroundStyle(Ink.muted).monospacedDigit()
                            }
                            .font(Face.caption)
                        }

                        if challenge == .overstimulated {
                            Label("No snooze, no shortcuts, about two to three minutes of nonsense. It's a joke — nothing you tap is stored or sent anywhere.",
                                  systemImage: "theatermasks")
                                .font(Face.caption).foregroundStyle(Ink.muted)
                        }

                        if challenge.isImplemented {
                            Button {
                                previewing = true
                            } label: {
                                Label("Try it (silent)", systemImage: "play.circle")
                            }
                        }
                    }
                }

                Section("Snooze") {
                    Toggle("Allow snooze", isOn: $snoozeEnabled.animation())
                    if snoozeEnabled {
                        Stepper("Every \(snoozeMinutes) minutes", value: $snoozeMinutes, in: 1...30)
                        Stepper("Up to \(maxSnoozes) times", value: $maxSnoozes, in: 1...10)
                        if let cap = tier.snoozeCap, mode == .challenge, challenge.supportsTiers, cap < maxSnoozes {
                            Text("\(tier.title) caps this at \(cap == 0 ? "no snoozes" : "\(cap)").")
                                .font(Face.caption).foregroundStyle(Palette.butter.ink)
                        }
                    }
                    Text("Each snooze costs 5 XP, and waking never drops below \(XPRules.wakeFloor).")
                        .font(Face.caption).foregroundStyle(Ink.muted)
                }

                if let alarm {
                    Section {
                        Button("Delete alarm", role: .destructive) {
                            store.scheduler.cancel(alarmID: alarm.id)
                            context.delete(alarm)
                            store.save()
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Ink.background)
            .navigationTitle(isNew ? "New alarm" : "Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .sheet(isPresented: $showExplainer) { ChallengeExplainer() }
            .fullScreenCover(isPresented: $previewing) {
                ChallengePreview(challenge: challenge, tier: tier, rounds: min(rounds, 2), wordCount: wordCount)
            }
            .onAppear(perform: load)
            .onChange(of: mode) { _, new in
                if new == .challenge && !store.profile.seenChallengeExplainer {
                    showExplainer = true
                    store.profile.seenChallengeExplainer = true
                    store.save()
                }
            }
        }
    }

    @ViewBuilder
    private var tierPreview: some View {
        switch challenge {
        case .math:
            LabeledContent("Example", value: ChallengeCatalog.mathPreview(tier))
                .font(Face.caption)
        case .shake:
            LabeledContent("Shake force", value: String(format: "%.1f g", ChallengeCatalog.shakeThreshold(tier)))
                .font(Face.caption)
        case .tiles:
            let spec = ChallengeCatalog.tileSpec(tier)
            LabeledContent("Grid", value: "\(spec.gridSize)×\(spec.gridSize), \(spec.litTiles) tiles, \(String(format: "%.2f", spec.showSeconds))s")
                .font(Face.caption)
        case .typing:
            VStack(alignment: .leading, spacing: 2) {
                Text("Example").font(Face.caption).foregroundStyle(Ink.muted)
                Text(ChallengeCatalog.typingPreview(tier))
                    .font(Face.caption).italic()
            }
        default:
            EmptyView()
        }
    }

    private func load() {
        guard let alarm else {
            challenge = store.profile.defaultChallenge
            tier = store.profile.defaultTier
            return
        }
        time = Calendar.current.date(bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: .now) ?? .now
        label = alarm.label
        days = alarm.weekdaysMask
        mode = alarm.mode
        challenge = alarm.challenge
        tier = alarm.tier
        rounds = alarm.rounds
        wordCount = alarm.typingWordCount
        snoozeEnabled = alarm.snoozeEnabled
        snoozeMinutes = alarm.snoozeMinutes
        maxSnoozes = alarm.maxSnoozes
    }

    private func save() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let target = alarm ?? AlarmItem(hour: components.hour ?? 7, minute: components.minute ?? 0)
        if alarm == nil { context.insert(target) }

        target.hour = components.hour ?? 7
        target.minute = components.minute ?? 0
        target.label = label
        target.weekdaysMask = days
        target.mode = mode
        target.challenge = challenge
        target.tier = tier
        target.rounds = rounds
        target.typingWordCount = wordCount
        target.snoozeEnabled = snoozeEnabled
        target.snoozeMinutes = snoozeMinutes
        target.maxSnoozes = maxSnoozes
        target.isEnabled = true
        target.updatedAt = .now
        // Phrases are built now, not at 6am.
        target.preparedPhrases = PhraseFactory.prepare(for: target)

        store.save()
        Task {
            _ = await store.scheduler.requestAuthorization()
            await store.scheduler.schedule(target)
            store.announceAlarmSet(ringsAt: target.nextFireDate())
        }
        dismiss()
    }
}

/// Shown once, the first time someone builds a challenge alarm, because an alarm
/// you can't switch off is a frightening surprise if nobody warned you.
struct ChallengeExplainer: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("How challenge alarms work").font(Face.display(26))
                    bullet("⏰", "The alarm rings at the time you set, and the system stop button always appears.")
                    bullet("🧠", "If you stop it before the challenge is done, the app re-arms and rings again about a minute later.")
                    bullet("✅", "Finish the challenge and it stops for good, logs the wake and pays out XP.")
                    bullet("🆘", "Emergency stop: hold the button for 10 seconds and confirm. It always works. No XP, and the wake streak resets.")
                    bullet("🔊", "Volume and the silent switch keep working normally. Nothing is ever blocked.")
                }
                .padding(Metric.gutter)
            }
            .background(Ink.background)
            .navigationTitle("Before you start")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Got it") { dismiss() } } }
        }
    }

    private func bullet(_ emoji: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(emoji).font(.system(size: 20))
            Text(text).font(Face.row).foregroundStyle(Ink.primary)
        }
    }
}
