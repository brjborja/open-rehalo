import SwiftUI

/// A route summary: thumbnail (map snapshot or placeholder), name, source line and a stats row
/// (distance · ↗ gain · ETA). All values arrive pre-formatted (see `UnitFormat`). Use it as the
/// label of a `NavigationLink`/`Button`, or pass `trailing` content (e.g. "Change" button).
///
///     RouteCard(name: r.name, subtitle: "Wikiloc",
///               distance: fmt.distance(r.length), gain: fmt.elevation(r.gain),
///               eta: fmt.duration(r.eta), thumbnail: snapshot.map(Image.init(uiImage:)))
struct RouteCard<Trailing: View>: View {
    let name: String
    var subtitle: String? = nil
    var distance: String? = nil
    var gain: String? = nil
    var eta: String? = nil
    var thumbnail: Image? = nil
    var compact: Bool = false
    var isSelected: Bool = false
    let trailing: () -> Trailing

    init(name: String,
         subtitle: String? = nil,
         distance: String? = nil,
         gain: String? = nil,
         eta: String? = nil,
         thumbnail: Image? = nil,
         compact: Bool = false,
         isSelected: Bool = false,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.name = name
        self.subtitle = subtitle
        self.distance = distance
        self.gain = gain
        self.eta = eta
        self.thumbnail = thumbnail
        self.compact = compact
        self.isSelected = isSelected
        self.trailing = trailing
    }

    private var thumbSize: CGFloat { compact ? 56 : 72 }

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            thumb
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: name)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textDim)
                        .lineLimit(1)
                }
                statsRow
            }
            Spacer(minLength: 0)
            trailing()
        }
        .haloCard(padding: Theme.Space.m,
                  stroke: isSelected ? Theme.accent.opacity(0.7) : Theme.stroke)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var thumb: some View {
        Group {
            if let thumbnail {
                thumbnail.resizable().scaledToFill()
            } else {
                ZStack {
                    Theme.surface2
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .frame(width: thumbSize, height: thumbSize)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private struct Stat: Identifiable {
        let id: String      // SF Symbol name (unique per row)
        let text: String
        let primary: Bool
    }

    private var stats: [Stat] {
        var out: [Stat] = []
        if let distance { out.append(Stat(id: "arrow.left.and.right", text: distance, primary: true)) }
        if let gain { out.append(Stat(id: "arrow.up.right", text: gain, primary: false)) }
        if let eta { out.append(Stat(id: "clock", text: eta, primary: false)) }
        return out
    }

    @ViewBuilder private var statsRow: some View {
        if !stats.isEmpty {
            HStack(spacing: Theme.Space.m) {
                ForEach(stats) { stat in
                    HStack(spacing: 3) {
                        Image(systemName: stat.id).font(.caption2.weight(.semibold))
                        Text(verbatim: stat.text).font(Theme.metricFont(.subheadline, weight: .semibold))
                    }
                    .foregroundStyle(stat.primary ? Theme.text : Theme.textDim)
                }
            }
            .lineLimit(1)
        }
    }
}

extension RouteCard where Trailing == EmptyView {
    init(name: String,
         subtitle: String? = nil,
         distance: String? = nil,
         gain: String? = nil,
         eta: String? = nil,
         thumbnail: Image? = nil,
         compact: Bool = false,
         isSelected: Bool = false) {
        self.init(name: name, subtitle: subtitle, distance: distance, gain: gain, eta: eta,
                  thumbnail: thumbnail, compact: compact, isSelected: isSelected) { EmptyView() }
    }
}

#Preview("RouteCard") {
    VStack(spacing: 12) {
        RouteCard(name: "Demo · City centre", subtitle: "Included in the app",
                  distance: "9.4 km", gain: "60 m", eta: "38 min", isSelected: true)
        RouteCard(name: "Anillo verde — tramo norte", subtitle: "Wikiloc",
                  distance: "24.1 km", gain: "210 m", eta: "1 h 32 min") {
            Image(systemName: "chevron.right").foregroundStyle(Theme.textDim)
        }
        RouteCard(name: "Short", distance: "2.0 km", compact: true)
    }
    .padding()
    .frame(maxHeight: .infinity)
    .haloScreenBackground()
    .haloTheme()
}
