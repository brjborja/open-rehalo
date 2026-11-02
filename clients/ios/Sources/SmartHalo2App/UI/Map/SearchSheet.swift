import SwiftUI
import SwiftData
import MapKit
import UniformTypeIdentifiers

/// The Map tab's one search (UX: "Buscar lugar o ruta"), and how to reach a route now that the map
/// opens empty. As you type: your saved routes that match and Apple's places. With nothing typed:
/// recent routes (▶ starts one right away), recent destinations, and My routes / Import GPX / demo.
/// A route is selected as from the Routes tab; a place becomes the destination pin.
struct SearchSheet: View {
    @ObservedObject var search: PlaceSearch
    let onRoute: (SavedRoute) -> Void
    /// ▶ on a recent route. Called just before the sheet goes away.
    let onNavigate: (SavedRoute) -> Void
    let onPlace: (Destination) -> Void
    let onMyRoutes: () -> Void
    let onImport: (Result<[URL], Error>) -> Void
    /// "Use demo route"; nil when there is none to offer.
    let onDemo: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedRoute.lastActivity, order: .reverse) private var routes: [SavedRoute]
    @EnvironmentObject private var settings: AppSettings
    @FocusState private var focused: Bool
    @State private var resolving = false
    @State private var error: String?
    @State private var showImporter = false

    private var fmt: UnitFormat { settings.unitFormat }
    private var trimmed: String { search.query.trimmingCharacters(in: .whitespaces) }
    private var matchingRoutes: [SavedRoute] {
        guard !trimmed.isEmpty else { return [] }
        return Array(routes.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }.prefix(4))
    }
    private var recentRoutes: [SavedRoute] { Array(routes.filter { $0.lastUsedAt != nil }.prefix(3)) }

    var body: some View {
        VStack(spacing: 0) {
            field
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Space.s) {
                    if let error {
                        Text(verbatim: error).font(.footnote).foregroundStyle(Theme.danger)
                    }
                    if trimmed.isEmpty {
                        recents
                        actions
                        Label("Tip: touch and hold the map to drop a pin.", systemImage: "hand.tap")
                            .font(.footnote)
                            .foregroundStyle(Theme.textDim)
                            .padding(.top, Theme.Space.m)
                    } else {
                        if !matchingRoutes.isEmpty {
                            header("My routes")
                            ForEach(matchingRoutes) { saved in
                                row(systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                                    tint: Theme.accent, title: saved.name,
                                    subtitle: fmt.distance(saved.distance)) {
                                    onRoute(saved)
                                    dismiss()
                                }
                            }
                        }
                        if !search.suggestions.isEmpty {
                            header("Places")
                            ForEach(Array(search.suggestions.enumerated()), id: \.offset) { _, s in
                                row(systemImage: "mappin.circle.fill", tint: Theme.info, title: s.title,
                                    subtitle: s.subtitle.isEmpty ? nil : s.subtitle) { pick(s) }
                            }
                        }
                    }
                }
                .padding(Theme.Space.l)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .overlay { if resolving { ProgressView().controlSize(.large) } }
        .onAppear { focused = true }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.gpx, .xml, .data],
                      allowsMultipleSelection: false) { result in
            onImport(result)
            dismiss()
        }
    }

    private var field: some View {
        HStack(spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textDim)
                TextField("Search a place or a route", text: $search.query)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit { if let first = search.suggestions.first { pick(first) } }
                if !search.query.isEmpty {
                    Button { search.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textDim)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Clear"))
                }
            }
            .padding(.horizontal, Theme.Space.m)
            .frame(minHeight: Theme.minTarget)
            .background(Theme.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke))
            Button("Cancel") { dismiss() }
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.info)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.l)
    }

    @ViewBuilder private var recents: some View {
        if !recentRoutes.isEmpty {
            header("Recent routes")
            ForEach(recentRoutes) { saved in
                row(systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    tint: Theme.accent, title: saved.name, subtitle: summary(saved),
                    trailingSpace: Theme.minTarget + Theme.Space.s) {
                    onRoute(saved)
                    dismiss()
                }
                .overlay(alignment: .trailing) {
                    startButton(saved).padding(.trailing, Theme.Space.s)
                }
            }
        }
        if !search.recents.isEmpty {
            header("Recent destinations")
            ForEach(search.recents) { r in
                row(systemImage: "clock", tint: Theme.textDim, title: r.name, subtitle: r.subtitle) {
                    onPlace(r.destination)
                    dismiss()
                }
            }
        }
    }

    private func startButton(_ saved: SavedRoute) -> some View {
        Button {
            onNavigate(saved)
            dismiss()
        } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: Theme.minTarget, height: Theme.minTarget)
                .background(Theme.accent, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Navigate now"))
    }

    private var actions: some View {
        VStack(spacing: Theme.Space.s) {
            Button("My routes") {
                onMyRoutes()
                dismiss()
            }
            .buttonStyle(.haloSecondary)
            Button { showImporter = true } label: {
                Label("Import GPX", systemImage: "square.and.arrow.down").labelStyle(.titleAndIcon)
            }
            .buttonStyle(.haloSecondary)
            if let onDemo {
                Button {
                    onDemo()
                    dismiss()
                } label: {
                    Label("Use demo route", systemImage: "sparkles").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.haloSecondary)
            }
        }
        .padding(.top, Theme.Space.m)
    }

    private func summary(_ saved: SavedRoute) -> String {
        var parts = [fmt.distance(saved.distance)]
        if let gain = saved.gain { parts.append("↗ " + fmt.elevation(gain)) }
        return parts.joined(separator: " · ")
    }

    private func header(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(Theme.textDim)
            .padding(.top, Theme.Space.s)
    }

    /// `trailingSpace` keeps the text clear of a button laid over the row's end.
    private func row(systemImage: String, tint: Color, title: String, subtitle: String?,
                     trailingSpace: CGFloat = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    if let subtitle {
                        Text(verbatim: subtitle)
                            .font(.footnote)
                            .foregroundStyle(Theme.textDim)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: trailingSpace)
            }
            .padding(.horizontal, Theme.Space.m)
            .frame(minHeight: 56)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .strokeBorder(Theme.stroke))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pick(_ suggestion: MKLocalSearchCompletion) {
        resolving = true
        error = nil
        Task {
            defer { resolving = false }
            do {
                onPlace(try await search.resolve(suggestion))
                dismiss()
            } catch {
                self.error = String(localized: "Couldn't find this place.")
            }
        }
    }
}
