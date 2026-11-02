import Foundation
import UserNotifications
import SH2Protocol

/// Local notifications from the Halo: low battery. (The alarm recap is shown in the Halo tab, as
/// in the official app, not notified.) Tapping one opens the Halo tab.
///
/// - `activate()` must run at launch (it's called from `SmartHalo2App.init`) so a tap on a
///   notification that cold-launches the app is still routed.
/// - Permission is requested in context: when the low-battery alert is turned on and (M11) from
///   the onboarding permissions step — both through `requestAuthorization()`.
@MainActor
final class AlarmNotifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = AlarmNotifier()

    nonisolated static let categoryAlarm = "sh2.alarm"

    /// Current notification permission (refresh with `refreshStatus()`).
    @Published private(set) var status: UNAuthorizationStatus = .notDetermined

    private var center: UNUserNotificationCenter { .current() }

    private override init() { super.init() }

    /// Install as the notification-center delegate. Idempotent.
    func activate() {
        center.delegate = self
        Task { await refreshStatus() }
    }

    func refreshStatus() async {
        status = await center.notificationSettings().authorizationStatus
    }

    /// Ask for permission if it hasn't been decided yet. Returns true if alerts are allowed.
    @discardableResult
    func requestAuthorization() async -> Bool {
        await refreshStatus()
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshStatus()
        }
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    /// "Halo battery at 20 %".
    func postLowBattery(level: Int, haloName: String) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(haloName) battery at \(level)%")
        content.body = String(localized: "Charge it soon so the light and the alarm keep working.")
        content.sound = .default
        content.categoryIdentifier = Self.categoryAlarm
        post(content, id: "sh2.battery.low")
    }

    private func post(_ content: UNMutableNotificationContent, id: String) {
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request) { error in
            if let error { SH2Log.log("notification: couldn't post — \(error.localizedDescription)") }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show the banner even while the app is in the foreground.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    /// Tap → Halo tab (root), with the alarm recap / battery figures.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let isAlarm = response.notification.request.content.categoryIdentifier == AlarmNotifier.categoryAlarm
        if isAlarm { Task { @MainActor in AppRouter.shared.showHaloHome() } }
        completionHandler()
    }
}
