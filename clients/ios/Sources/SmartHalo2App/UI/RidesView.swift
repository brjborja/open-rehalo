import SwiftUI

/// Rides history pulled from the self-hosted server (`GET /api/v1/users/rides`).
struct RidesView: View {
    @State private var rides: [SH2PastRide] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        List {
            if loading { HStack { ProgressView(); Text("Loading…") } }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            if !loading && error == nil && rides.isEmpty {
                Text("No rides yet.").foregroundStyle(.secondary)
            }
            ForEach(rides) { ride in
                NavigationLink {
                    RideDetailView(ride: ride)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ride.start ?? ride.stamp ?? "Ride \(ride.id ?? 0)").font(.headline)
                        HStack(spacing: 14) {
                            metric("km", ride.distance.map { $0 / 1000 })
                            metric("min", ride.duration.map { $0 / 60 })
                            metric("km/h", ride.averageSpeed)
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Rides")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func metric(_ unit: String, _ value: Double?) -> some View {
        Group {
            if let v = value { Text("\(v, specifier: "%.1f") \(unit)") }
        }
    }

    private func load() async {
        guard let url = AppSettings.shared.serverURL, let jwt = TokenStore.load(.access) else {
            error = "Not signed in."; return
        }
        loading = true; error = nil
        defer { loading = false }
        do { rides = try await SH2Server(baseURL: url).rides(accessJWT: jwt) }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }
}
