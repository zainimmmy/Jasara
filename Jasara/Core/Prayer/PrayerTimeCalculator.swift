import Foundation

/// Calculation method. Auto-selected by region, changeable under Advanced.
enum PrayerMethod: String, CaseIterable, Identifiable, Codable {
    case isna, mwl, egypt, karachi, ummAlQura, dubai

    var id: String { rawValue }
    var title: String {
        switch self {
        case .isna: return "ISNA (North America)"
        case .mwl: return "Muslim World League"
        case .egypt: return "Egyptian General Authority"
        case .karachi: return "University of Karachi"
        case .ummAlQura: return "Umm al-Qura (Makkah)"
        case .dubai: return "Dubai"
        }
    }
    var fajrAngle: Double {
        switch self {
        case .isna: return 15
        case .mwl: return 18
        case .egypt: return 19.5
        case .karachi: return 18
        case .ummAlQura: return 18.5
        case .dubai: return 18.2
        }
    }
    /// Either an angle below the horizon, or a fixed interval after Maghrib.
    var ishaAngle: Double? {
        switch self {
        case .isna: return 15
        case .mwl: return 17
        case .egypt: return 17.5
        case .karachi: return 18
        case .ummAlQura: return nil
        case .dubai: return 18.2
        }
    }
    var ishaIntervalMinutes: Int? { self == .ummAlQura ? 90 : nil }

    /// A sane default for where the phone is, changeable in Advanced settings.
    static func suggested(forLongitude lng: Double, latitude lat: Double) -> PrayerMethod {
        switch (lat, lng) {
        case (10...75, -170...(-30)): return .isna          // the Americas
        case (12...33, 34...60): return .ummAlQura          // Arabian peninsula
        case (20...40, 60...80): return .karachi            // South Asia
        case (22...32, 24...37): return .egypt              // Egypt and around
        default: return .mwl
        }
    }
}

struct DailyPrayerTimes {
    var fajr: Date
    var sunrise: Date
    var dhuhr: Date
    var asr: Date
    var maghrib: Date
    var isha: Date

    func time(for prayer: PrayerName) -> Date {
        switch prayer {
        case .fajr: return fajr
        case .dhuhr: return dhuhr
        case .asr: return asr
        case .maghrib: return maghrib
        case .isha: return isha
        }
    }
}

/// On-device astronomical calculation, so prayer times work with no connection
/// and the user's location never leaves the phone. This is a direct port of the
/// standard sun-position method; swapping in the Adhan Swift package later only
/// needs `times(on:...)` to keep its signature.
enum PrayerTimeCalculator {

    static func times(on day: Date,
                      latitude: Double,
                      longitude: Double,
                      method: PrayerMethod,
                      hanafiAsr: Bool,
                      timeZone: TimeZone = .current) -> DailyPrayerTimes? {

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let startOfDay = cal.startOfDay(for: day)
        let parts = cal.dateComponents([.year, .month, .day], from: startOfDay)
        guard let y = parts.year, let m = parts.month, let d = parts.day else { return nil }

        let jdate = julianDay(year: y, month: m, day: d) - longitude / (15 * 24)
        let tzOffset = Double(timeZone.secondsFromGMT(for: startOfDay)) / 3600
        let shift = tzOffset - longitude / 15

        func declination(_ t: Double) -> Double { sunPosition(jdate + t).declination }
        func noon(_ t: Double) -> Double { 12 - sunPosition(jdate + t).equationOfTime }

        /// Hour angle for the sun sitting `angle` degrees below the horizon.
        func angleTime(_ angle: Double, guess t: Double, before: Bool) -> Double? {
            let decl = declination(t)
            let numerator = -sin(rad(angle)) - sin(rad(decl)) * sin(rad(latitude))
            let denominator = cos(rad(decl)) * cos(rad(latitude))
            let ratio = numerator / denominator
            guard abs(ratio) <= 1 else { return nil }   // sun never reaches it here
            let hours = deg(acos(ratio)) / 15
            return before ? noon(t) - hours : noon(t) + hours
        }

        func asrTime(guess t: Double) -> Double? {
            let shadowFactor = hanafiAsr ? 2.0 : 1.0
            let decl = declination(t)
            let angle = -deg(atan(1 / (shadowFactor + tan(rad(abs(latitude - decl))))))
            return angleTime(angle, guess: t, before: false)
        }

        // Two passes: the first guess is a rough hour, the second refines it.
        var fajr = 5.0 / 24, sunrise = 6.0 / 24, asr = 13.0 / 24, sunset = 18.0 / 24, isha = 18.0 / 24
        var dhuhr = 12.0
        for _ in 0..<2 {
            guard let f = angleTime(method.fajrAngle, guess: fajr, before: true),
                  let sr = angleTime(0.833, guess: sunrise, before: true),
                  let a = asrTime(guess: asr),
                  let ss = angleTime(0.833, guess: sunset, before: false) else { return nil }
            dhuhr = noon(12.0 / 24)
            fajr = f / 24; sunrise = sr / 24; asr = a / 24; sunset = ss / 24
            if let ishaAngle = method.ishaAngle,
               let i = angleTime(ishaAngle, guess: isha, before: false) {
                isha = i / 24
            } else {
                isha = sunset + Double(method.ishaIntervalMinutes ?? 90) / 60 / 24
            }
        }

        func date(_ dayFraction: Double) -> Date {
            startOfDay.addingTimeInterval((dayFraction * 24 + shift) * 3600)
        }

        return DailyPrayerTimes(fajr: date(fajr),
                                sunrise: date(sunrise),
                                dhuhr: startOfDay.addingTimeInterval((dhuhr + shift) * 3600),
                                asr: date(asr),
                                maghrib: date(sunset),
                                isha: date(isha))
    }

    // MARK: - Astronomy

    private static func sunPosition(_ jd: Double) -> (declination: Double, equationOfTime: Double) {
        let d = jd - 2451545.0
        let g = fixAngle(357.529 + 0.98560028 * d)
        let q = fixAngle(280.459 + 0.98564736 * d)
        let l = fixAngle(q + 1.915 * sin(rad(g)) + 0.020 * sin(rad(2 * g)))
        let e = 23.439 - 0.00000036 * d
        let rightAscension = fixHour(deg(atan2(cos(rad(e)) * sin(rad(l)), cos(rad(l)))) / 15)
        let declination = deg(asin(sin(rad(e)) * sin(rad(l))))
        return (declination, q / 15 - rightAscension)
    }

    private static func julianDay(year: Int, month: Int, day: Int) -> Double {
        var y = year, m = month
        if m <= 2 { y -= 1; m += 12 }
        let a = floor(Double(y) / 100)
        let b = 2 - a + floor(a / 4)
        return floor(365.25 * Double(y + 4716)) + floor(30.6001 * Double(m + 1))
            + Double(day) + b - 1524.5
    }

    private static func rad(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func deg(_ radians: Double) -> Double { radians * 180 / .pi }
    private static func fixAngle(_ a: Double) -> Double { let r = a.truncatingRemainder(dividingBy: 360); return r < 0 ? r + 360 : r }
    private static func fixHour(_ h: Double) -> Double { let r = h.truncatingRemainder(dividingBy: 24); return r < 0 ? r + 24 : r }
}
