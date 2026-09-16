import SwiftUI
import CoreLocation
import MapKit

struct PrayerSetupView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var manual = false
    @State private var hanafi = false
    @State private var method = PrayerMethod.isna
    @State private var offsets = [0, 0, 0, 0, 0]
    @State private var manualMinutes = [300, 780, 960, 1110, 1230]
    @State private var jumuah = false
    @State private var jumuahMinutes = 810
    @State private var reminder = ReminderKind.notification
    @State private var nudge = 15
    @State private var countsForXP = false
    @State private var showAdvanced = false
    @State private var cityQuery = ""
    @State private var cityError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Time source") {
                    Picker("Times come from", selection: $manual.animation()) {
                        Text("My location").tag(false)
                        Text("My masjid's timetable").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if manual {
                        ForEach(PrayerName.allCases) { prayer in
                            DatePicker(prayer.title,
                                       selection: binding(for: prayer),
                                       displayedComponents: .hourAndMinute)
                        }
                        Label("Masjid times shift through the year. Check the timetable again each season.",
                              systemImage: "calendar.badge.exclamationmark")
                            .font(Face.caption).foregroundStyle(Ink.muted)
                    } else {
                        locationRow
                    }
                }

                Section("Asr") {
                    Picker("Method", selection: $hanafi) {
                        Text("Standard").tag(false)
                        Text("Hanafi").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Masjid adjustment") {
                    ForEach(PrayerName.allCases) { prayer in
                        Stepper(value: Binding(
                            get: { offsets[prayer.rawValue] },
                            set: { offsets[prayer.rawValue] = $0 }
                        ), in: -30...30) {
                            HStack {
                                Text(prayer.title)
                                Spacer()
                                Text(offsetLabel(offsets[prayer.rawValue]))
                                    .foregroundStyle(Ink.muted).monospacedDigit()
                            }
                        }
                    }
                }

                Section("Jumu'ah") {
                    Toggle("Show Jumu'ah on Fridays", isOn: $jumuah.animation())
                    if jumuah {
                        DatePicker("Time", selection: Binding(
                            get: { Date.today(atMinutes: jumuahMinutes) },
                            set: { jumuahMinutes = $0.minutesSinceMidnight }
                        ), displayedComponents: .hourAndMinute)
                        Text("Every masjid sets its own, so this one is yours to type in.")
                            .font(Face.caption).foregroundStyle(Ink.muted)
                    }
                }

                Section("Reminders") {
                    Picker("Style", selection: $reminder) {
                        Text("Notification").tag(ReminderKind.notification)
                        Text("Alarm").tag(ReminderKind.alarm)
                        Text("None").tag(ReminderKind.none)
                    }
                    Stepper("Nudge every \(nudge) minutes", value: $nudge, in: 5...30, step: 5)
                    Text("Nudges stop as soon as you mark the prayer, or when the next one begins. At most \(NotificationBudget.maxNudgesPerPrayer) per prayer.")
                        .font(Face.caption).foregroundStyle(Ink.muted)
                }

                Section("XP and streaks") {
                    Toggle("Count prayers toward XP", isOn: $countsForXP)
                    Text("Off by default. Some people would rather not gamify worship, and that's the right default to pick for them.")
                        .font(Face.caption).foregroundStyle(Ink.muted)
                }

                Section {
                    DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                        Picker("Calculation method", selection: $method) {
                            ForEach(PrayerMethod.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                    }
                } footer: {
                    Text(PrayerService.disclaimer)
                }

                if store.prayerSettings.isEnabled {
                    Section {
                        Button("Turn off prayer tracking", role: .destructive) {
                            store.prayerSettings.isEnabled = false
                            NotificationScheduler.shared.cancelPrayers()
                            store.save()
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Ink.background)
            .navigationTitle("Daily prayers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear(perform: load)
        }
    }

    private var locationRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(store.prayerSettings.placeName
                     ?? store.prayers.placeName
                     ?? "No location yet")
                    .font(Face.row)
                Spacer()
                Button("Use my location") {
                    // Asked for here, at first use, with the reason on screen.
                    store.prayers.requestLocation()
                }
                .font(Face.caption.weight(.bold))
            }
            Text("Used only to work out prayer times on this phone. It never leaves the device.")
                .font(Face.caption).foregroundStyle(Ink.muted)

            HStack {
                TextField("Or type a city", text: $cityQuery)
                    .textInputAutocapitalization(.words)
                Button("Find") { lookUpCity() }
                    .font(Face.caption.weight(.bold))
                    .disabled(cityQuery.isEmpty)
            }
            if let cityError {
                Text(cityError).font(Face.caption).foregroundStyle(Palette.blush.ink)
            }
        }
    }

    // MARK: - Helpers

    private func binding(for prayer: PrayerName) -> Binding<Date> {
        Binding(
            get: { Date.today(atMinutes: manualMinutes[prayer.rawValue]) },
            set: { manualMinutes[prayer.rawValue] = $0.minutesSinceMidnight }
        )
    }

    private func offsetLabel(_ minutes: Int) -> String {
        minutes == 0 ? "On time" : (minutes > 0 ? "+\(minutes) min" : "\(minutes) min")
    }

    /// Manual city entry for anyone who declines location, which has to stay a
    /// first-class path rather than a dead end.
    private func lookUpCity() {
        cityError = nil
        Task {
            guard let request = MKGeocodingRequest(addressString: cityQuery),
                  let item = try? await request.mapItems.first else {
                cityError = "Couldn't find that place. Try the nearest city."
                return
            }
            let coordinate = item.location.coordinate
            let settings = store.prayerSettings
            settings.latitude = coordinate.latitude
            settings.longitude = coordinate.longitude
            settings.placeName = item.name ?? cityQuery
            method = PrayerMethod.suggested(forLongitude: coordinate.longitude,
                                            latitude: coordinate.latitude)
            store.save()
        }
    }

    private func load() {
        let settings = store.prayerSettings
        manual = settings.manualTimes
        hanafi = settings.hanafiAsr
        method = settings.method
        offsets = settings.offsets.count == 5 ? settings.offsets : [0, 0, 0, 0, 0]
        manualMinutes = settings.manualMinutes.count == 5 ? settings.manualMinutes : [300, 780, 960, 1110, 1230]
        jumuah = settings.jumuahEnabled
        jumuahMinutes = settings.jumuahMinutes
        reminder = settings.reminderKind
        nudge = settings.nudgeIntervalMinutes
        countsForXP = settings.countsForXP
        if settings.latitude == nil, let coordinate = store.prayers.coordinate {
            settings.latitude = coordinate.latitude
            settings.longitude = coordinate.longitude
            settings.placeName = store.prayers.placeName
            method = PrayerMethod.suggested(forLongitude: coordinate.longitude,
                                            latitude: coordinate.latitude)
        }
    }

    private func save() {
        let settings = store.prayerSettings
        settings.manualTimes = manual
        settings.hanafiAsr = hanafi
        settings.method = method
        settings.offsets = offsets
        settings.manualMinutes = manualMinutes
        settings.jumuahEnabled = jumuah
        settings.jumuahMinutes = jumuahMinutes
        settings.reminderKind = reminder
        settings.nudgeIntervalMinutes = nudge
        settings.countsForXP = countsForXP
        settings.isEnabled = true
        store.save()

        Task {
            if reminder != .none {
                _ = await NotificationScheduler.shared.requestAuthorization()
            }
            if let entries = store.prayers.entries(for: .now, settings: settings), reminder != .none {
                await NotificationScheduler.shared.schedulePrayers(entries, settings: settings)
            }
        }
        dismiss()
    }
}
