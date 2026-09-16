import Foundation
import CoreLocation
import MapKit
import Observation

/// Resolves the five daily prayers for a given day from the user's settings.
/// Automatic mode calculates on device; manual mode uses the times the user
/// copied off their masjid timetable. Masjid offsets apply to both.
@Observable
final class PrayerService {
    var coordinate: CLLocationCoordinate2D?
    var placeName: String?
    var authorization: CLAuthorizationStatus = .notDetermined
    var lastError: String?

    private let manager = CLLocationManager()
    /// The delegate lives in its own NSObject so the observable model stays a
    /// plain Swift class.
    private var delegate: LocationDelegate?

    init() {
        let delegate = LocationDelegate()
        delegate.owner = self
        manager.delegate = delegate
        manager.desiredAccuracy = kCLLocationAccuracyKilometer   // a city is plenty
        self.delegate = delegate
        authorization = manager.authorizationStatus
    }

    /// "While Using" only. Prayer times are the sole reason we ever ask.
    func requestLocation() {
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    fileprivate func apply(_ location: CLLocation) {
        coordinate = location.coordinate
        Task { await resolvePlaceName(for: location) }
    }

    private func resolvePlaceName(for location: CLLocation) async {
        guard let request = MKReverseGeocodingRequest(location: location) else { return }
        let items = try? await request.mapItems
        placeName = items?.first?.name
    }

    fileprivate func authorizationChanged(_ status: CLAuthorizationStatus) {
        authorization = status
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
    }

    private final class LocationDelegate: NSObject, CLLocationManagerDelegate {
        weak var owner: PrayerService?

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            owner?.authorizationChanged(manager.authorizationStatus)
        }

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard let location = locations.last else { return }
            owner?.apply(location)
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            owner?.lastError = "Couldn't read your location. You can type your city instead."
        }
    }

    // MARK: - Times

    struct Entry: Identifiable {
        var prayer: PrayerName
        var time: Date
        var isJumuah: Bool
        var id: Int { prayer.rawValue }
        var title: String { isJumuah ? "Jumu'ah" : prayer.title }
    }

    /// Nil when automatic mode has no location yet — the UI then offers manual entry.
    func entries(for day: Date, settings: PrayerSettings) -> [Entry]? {
        let calendar = Calendar.current
        let isFriday = calendar.component(.weekday, from: day) == 6

        var base: [PrayerName: Date] = [:]
        if settings.manualTimes {
            for prayer in PrayerName.allCases {
                let minutes = settings.manualMinutes.indices.contains(prayer.rawValue)
                    ? settings.manualMinutes[prayer.rawValue] : 0
                base[prayer] = Date.today(atMinutes: minutes, on: day)
            }
        } else {
            let lat = settings.latitude ?? coordinate?.latitude
            let lng = settings.longitude ?? coordinate?.longitude
            guard let lat, let lng,
                  let times = PrayerTimeCalculator.times(on: day,
                                                         latitude: lat,
                                                         longitude: lng,
                                                         method: settings.method,
                                                         hanafiAsr: settings.hanafiAsr)
            else { return nil }
            for prayer in PrayerName.allCases { base[prayer] = times.time(for: prayer) }
        }

        return PrayerName.allCases.compactMap { prayer in
            guard var time = base[prayer] else { return nil }
            let offset = settings.offsets.indices.contains(prayer.rawValue) ? settings.offsets[prayer.rawValue] : 0
            time = time.addingTimeInterval(Double(offset) * 60)
            var jumuah = false
            if prayer == .dhuhr, isFriday, settings.jumuahEnabled {
                time = Date.today(atMinutes: settings.jumuahMinutes, on: day)
                jumuah = true
            }
            return Entry(prayer: prayer, time: time, isJumuah: jumuah)
        }
    }

    /// Which day section a prayer lands in, so it can be slotted into the calendar.
    static func section(for time: Date) -> DaySection {
        DaySection.forHour(Calendar.current.component(.hour, from: time))
    }

    static let disclaimer = "Times are calculated estimates. Confirm with your local masjid."
}
