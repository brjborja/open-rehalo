import Foundation

/// Decoded reply of `alarmReport` {3,0}. Port of the official app's `AlarmReport(byte[])`:
/// `[RET_OK, armed, triggerCount, vigilant, mode]`. `triggerCount` = times the alarm sounded since
/// the previous report: the firmware zeroes it on every read (`sendReport`, AlarmTask.c) (the app expects 5 bytes; we accept ≥ 4 so a
/// shorter firmware reply still yields the useful fields).
public struct AlarmReport: Equatable, Sendable {
    public let isArmed: Bool
    /// How many times the alarm has sounded (the ring's own counter).
    public let triggerCount: Int
    public let isVigilant: Bool

    public init(isArmed: Bool, triggerCount: Int, isVigilant: Bool) {
        self.isArmed = isArmed
        self.triggerCount = triggerCount
        self.isVigilant = isVigilant
    }

    /// Parse a full reply (return code included). Nil when the reply isn't an OK report.
    public init?(reply: Data) {
        let b = [UInt8](reply)
        guard b.count >= 4, b[0] == ReturnCode.ok.rawValue else { return nil }
        isArmed = b[1] == 1
        triggerCount = Int(b[2])
        isVigilant = b[3] == 1
    }
}

/// Decoded reply of `getState` {4,1}. Port of the STM firmware's `returnState`
/// (SystemUtilitiesTask.c): `[RET_OK, stateOfCharge, charging, compass(2), lightReady,
/// lightShowing, temperature, plugged, travelMode]`. The firmware estimates the charge from the
/// battery voltage in 10 % steps; the temperature is the accelerometer's die sensor (°C, reads warm).
public struct DeviceState: Equatable, Sendable {
    /// Battery, 0…100 %.
    public let stateOfCharge: Int
    public let charging: Bool
    public let lightOn: Bool?
    public let temperature: Int?
    public let plugged: Bool?

    public init(stateOfCharge: Int, charging: Bool, lightOn: Bool? = nil, temperature: Int? = nil,
                plugged: Bool? = nil) {
        self.stateOfCharge = stateOfCharge
        self.charging = charging
        self.lightOn = lightOn
        self.temperature = temperature
        self.plugged = plugged
    }

    /// Parse a full reply (return code included). Nil when it isn't an OK state reply.
    public init?(reply: Data) {
        let b = [UInt8](reply)
        guard b.count >= 3, b[0] == ReturnCode.ok.rawValue, b[1] <= 100 else { return nil }
        stateOfCharge = Int(b[1])
        charging = b[2] == 1
        lightOn = b.count > 6 ? b[6] == 1 : nil
        temperature = b.count > 7 ? Int(Int8(bitPattern: b[7])) : nil
        plugged = b.count > 8 ? b[8] == 1 : nil
    }
}

/// Unsolicited device → central message on the UP channel (`Session.setNotificationHandler`).
/// Port of `BleNotificationController.onNewBleNotification` (first byte = type).
public enum UpNotification: Equatable, Sendable {
    /// Type 0: touch gesture, as a string of `s` (short) / `l` (long) taps.
    case touch(String)
    /// Type 2: the ring's accelerometer reports movement (`true`) or rest (`false`).
    case movement(Bool)
    /// Type 3: front light state changed (e.g. toggled by a touch on the ring).
    case light(isOn: Bool, settingOn: Bool, fromTouch: Bool?)
    /// Type 4: battery report, sent every ~60 s (`send_battery_level`): `[4, soc, temperature
    /// (int8 °C), plugged]`. Fields are nil on a shorter frame (the app then re-reads `getState`).
    case deviceInfo(stateOfCharge: Int?, temperature: Int?, plugged: Bool?)
    /// Type 5: carousel moved to a widget index.
    case carouselPosition(UInt8)
    /// Type 0xF8 (-8): STM32 log line.
    case log(String)
    case unknown(Data)

    public init(_ data: Data) {
        let b = [UInt8](data)
        guard let type = b.first else { self = .unknown(data); return }
        switch type {
        case 0 where b.count == 3 && (1...32).contains(b[2]):
            let mask = Int(b[1])
            self = .touch(String((0..<Int(b[2])).map { (mask >> $0) & 1 == 1 ? "l" : "s" }))
        case 2 where b.count == 2 && b[1] <= 1:
            self = .movement(b[1] == 1)
        case 3 where b.count >= 3:
            self = .light(isOn: b[2] == 1, settingOn: b[1] == 1,
                          fromTouch: b.count > 3 ? b[3] == 1 : nil)
        case 4:
            self = .deviceInfo(stateOfCharge: b.count > 1 && b[1] <= 100 ? Int(b[1]) : nil,
                               temperature: b.count > 2 ? Int(Int8(bitPattern: b[2])) : nil,
                               plugged: b.count > 3 ? b[3] == 1 : nil)
        case 5 where b.count >= 2:
            self = .carouselPosition(b[1])
        case 0xF8:
            // The app drops the last byte (NUL terminator).
            let body = b.count > 2 ? Array(b[1..<(b.count - 1)]) : []
            self = .log(String(decoding: body, as: UTF8.self))
        default:
            self = .unknown(data)
        }
    }
}
