import Foundation

/// Open-Meteo's `minutely_15` precipitation (`timeformat=unixtime`). Each time is the END of its
/// 15 minutes, and the list starts with a slot that is already over.
public struct RainForecast: Equatable, Sendable {
    public struct Slot: Equatable, Sendable {
        public let end: Date
        public let millimetres: Double
    }

    /// Length of a slot, seconds.
    public static let slotLength: TimeInterval = 15 * 60

    public let slots: [Slot]

    private struct Response: Decodable {
        struct Minutely: Decodable {
            let time: [TimeInterval]
            let precipitation: [Double?]
        }
        let minutely_15: Minutely
    }

    /// Nil when the reply isn't a forecast (an API error, say).
    public init?(json: Data) {
        guard let minutely = try? JSONDecoder().decode(Response.self, from: json).minutely_15 else { return nil }
        let slots = zip(minutely.time, minutely.precipitation).compactMap { time, mm in
            mm.map { Slot(end: Date(timeIntervalSince1970: time), millimetres: $0) }
        }
        guard !slots.isEmpty else { return nil }
        self.slots = slots
    }

    /// Minutes until the first slot of rain, rounded up to 5; 0 = already raining; nil = dry for
    /// the next `window` seconds. Below `threshold` mm per slot it's drizzle at most.
    public func minutesToRain(at now: Date, within window: TimeInterval = 30 * 60,
                              threshold: Double = 0.2) -> Int? {
        guard let slot = slots.first(where: { $0.end > now && $0.millimetres >= threshold }) else { return nil }
        let wait = slot.end.timeIntervalSince(now) - Self.slotLength
        guard wait <= window else { return nil }
        return wait <= 0 ? 0 : Int((wait / 300).rounded(.up)) * 5
    }
}

/// One alert per spell of rain: another needs a dry forecast, at least `gap` after the last alert.
public struct RainWatch: Sendable {
    private var armed = true
    private var lastAlert: Date?
    private let gap: TimeInterval

    public init(gap: TimeInterval = 30 * 60) { self.gap = gap }

    /// Feed `RainForecast.minutesToRain`; true = alert the rider now.
    public mutating func shouldAlert(minutes: Int?, at now: Date) -> Bool {
        guard minutes != nil else {
            if lastAlert.map({ now.timeIntervalSince($0) >= gap }) ?? true { armed = true }
            return false
        }
        guard armed else { return false }
        armed = false
        lastAlert = now
        return true
    }
}
