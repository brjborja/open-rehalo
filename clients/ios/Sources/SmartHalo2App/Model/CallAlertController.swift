import CallKit
import Combine
import Foundation

/// Shows incoming calls on the Halo (the official app's `AssistantController`). iOS has no phone
/// state broadcast, so `CXCallObserver` stands in for `PhoneStateListener`: it needs no entitlement
/// but gives no caller, and it can't wake a suspended app. Navigating or on a ride the app keeps
/// running and reacts at once; otherwise the next event from the ring (`DeviceController.handleUp`,
/// about every 60 s) gets a look at the calls. A closed app can't alert.
@MainActor
final class CallAlertController: NSObject, ObservableObject, CXCallObserverDelegate {
    static let shared = CallAlertController()

    /// "Test alert" in the Halo tab is running.
    @Published private(set) var testing = false

    private let observer = CXCallObserver()
    private var bag = Set<AnyCancellable>()
    private var activated = false

    /// Call once at launch (`SmartHalo2App.init`).
    func activate() {
        guard !activated else { return }
        activated = true
        observer.setDelegate(self, queue: .main)
        // A ring that connects while the phone is ringing still gets the alert. `$state` fires before
        // the new value lands: read it afterwards.
        HaloConnection.shared.$state
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &bag)
    }

    nonisolated func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        MainActor.assumeIsolated { refresh() }
    }

    /// Bring the ring in line with the calls and the settings.
    func refresh() {
        let connection = HaloConnection.shared
        guard let ring = connection.controller else { return }
        let settings = AppSettings.shared
        let wanted = testing || (settings.callAlerts && isRinging)
        if wanted, !ring.callAlertActive, connection.state == .connected {
            ring.showIncomingCall(sound: settings.callAlertSound)
        } else if !wanted, ring.callAlertActive {
            ring.clearIncomingCall()
        }
    }

    /// Run the alert for a few seconds, without a call.
    func test() {
        guard !testing else { return }
        testing = true
        refresh()
        Task {
            try? await Task.sleep(for: .seconds(6))
            testing = false
            refresh()
        }
    }

    private var isRinging: Bool {
        observer.calls.contains { !$0.isOutgoing && !$0.hasConnected && !$0.hasEnded }
    }
}
