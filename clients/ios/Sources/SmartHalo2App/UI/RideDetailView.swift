import SwiftUI

/// Detail of a single server ride (M5). The server's ride summary has stats but no track points,
/// so a per-ride GPX export / map isn't possible from this payload (documented deferral).
struct RideDetailView: View {
    let ride: SH2PastRide

    var body: some View {
        List {
            Section("Summary") {
                stat("Date", ride.start ?? ride.stamp ?? ride.createdAt)
                stat("Distance", ride.distance.map { String(format: "%.2f km", $0 / 1000) })
                stat("Duration", ride.duration.map(formatDuration))
                stat("Avg speed", ride.averageSpeed.map { String(format: "%.1f km/h", $0) })
                stat("Elevation", ride.elevation.map { String(format: "%.0f m", $0) })
                stat("Calories", ride.calories.map { String(format: "%.0f kcal", $0) })
                stat("CO₂ saved", ride.co2.map { String(format: "%.0f g", $0) })
            }
            Section {
                Text("GPX export isn't available: the server ride summary doesn't include the track. Use Navigation → Import GPX to follow routes.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Ride")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func stat(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty { LabeledContent(label, value: value) }
    }

    private func formatDuration(_ secs: Double) -> String {
        let s = Int(secs)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}
