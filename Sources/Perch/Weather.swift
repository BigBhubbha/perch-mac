// Weather from Open-Meteo. Free, no key, no account. Refreshes every 30 minutes.
import Foundation
import SwiftUI

struct WeatherNow: Equatable {
    var temp: Double
    var high: Double
    var low: Double
    var code: Int
    var isDay: Bool
    var rainChance: Int
    var hours: [(Date, Double, Int)]

    static func == (a: WeatherNow, b: WeatherNow) -> Bool {
        a.temp == b.temp && a.code == b.code && a.high == b.high && a.low == b.low && a.hours.count == b.hours.count
    }

    var symbol: String { Self.symbol(code, day: isDay) }
    var words: String { Self.words(code) }

    static func symbol(_ c: Int, day: Bool) -> String {
        switch c {
        case 0: return day ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return day ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func words(_ c: Int) -> String {
        switch c {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51...57: return "Drizzle"
        case 61...67: return "Rain"
        case 71...77: return "Snow"
        case 80...82: return "Showers"
        case 85, 86: return "Snow showers"
        case 95...99: return "Thunderstorms"
        default: return "Cloudy"
        }
    }

    static func tint(_ c: Int, day: Bool) -> Color {
        switch c {
        case 0, 1: return day ? Ink.amber : Color(red: 0.75, green: 0.78, blue: 1.0)
        case 61...67, 80...82, 51...57: return Ink.sky
        case 95...99: return Color(red: 0.74, green: 0.62, blue: 1.0)
        default: return Ink.text2
        }
    }
}

@MainActor
final class WeatherCenter: ObservableObject {
    @Published private(set) var now: WeatherNow?
    @Published private(set) var failed = false
    private var timer: Timer?
    private var lastFetch = Date.distantPast

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer?.tolerance = 60
    }

    func refreshIfStale() {
        if Date().timeIntervalSince(lastFetch) > 20 * 60 { refresh() }
    }

    func refresh() {
        let p = Prefs.shared
        let unit = p.fahrenheit ? "fahrenheit" : "celsius"
        let s = "https://api.open-meteo.com/v1/forecast?latitude=\(p.weatherLat)&longitude=\(p.weatherLon)&current=temperature_2m,weather_code,is_day&hourly=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max&temperature_unit=\(unit)&timezone=auto&forecast_days=2"
        guard let url = URL(string: s) else { return }
        lastFetch = Date()
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let w = try Self.parse(data)
                self.now = w; self.failed = false
            } catch {
                self.failed = true
            }
        }
    }

    nonisolated static func parse(_ data: Data) throws -> WeatherNow {
        struct R: Decodable {
            struct Cur: Decodable { let temperature_2m: Double; let weather_code: Int; let is_day: Int }
            struct Hourly: Decodable { let time: [String]; let temperature_2m: [Double]; let weather_code: [Int] }
            struct Daily: Decodable { let temperature_2m_max: [Double]; let temperature_2m_min: [Double]; let precipitation_probability_max: [Int?] }
            let current: Cur; let hourly: Hourly; let daily: Daily; let utc_offset_seconds: Int
        }
        let r = try JSONDecoder().decode(R.self, from: data)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.timeZone = TimeZone(secondsFromGMT: r.utc_offset_seconds)
        let now = Date()
        var hours: [(Date, Double, Int)] = []
        for (i, t) in r.hourly.time.enumerated() {
            guard let d = f.date(from: t), d > now.addingTimeInterval(-1800), hours.count < 6 else { continue }
            hours.append((d, r.hourly.temperature_2m[i], r.hourly.weather_code[i]))
        }
        return WeatherNow(temp: r.current.temperature_2m, high: r.daily.temperature_2m_max.first ?? 0,
                          low: r.daily.temperature_2m_min.first ?? 0, code: r.current.weather_code,
                          isDay: r.current.is_day == 1, rainChance: (r.daily.precipitation_probability_max.first ?? 0) ?? 0,
                          hours: hours)
    }

    /// Finds a city with Open-Meteo's geocoder. Returns (name, lat, lon).
    static func geocode(_ name: String) async -> (String, Double, Double)? {
        let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        guard let url = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(q)&count=1&language=en&format=json") else { return nil }
        struct G: Decodable { struct Row: Decodable { let name: String; let latitude: Double; let longitude: Double; let admin1: String? }; let results: [Row]? }
        guard let res = try? await URLSession.shared.data(from: url),
              let g = try? JSONDecoder().decode(G.self, from: res.0), let r = g.results?.first else { return nil }
        return (r.admin1.map { "\(r.name), \($0)" } ?? r.name, r.latitude, r.longitude)
    }

    func preview(_ w: WeatherNow) { now = w }
}
