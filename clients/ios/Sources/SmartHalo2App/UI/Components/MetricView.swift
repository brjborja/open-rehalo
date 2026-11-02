import SwiftUI

/// A big number + its unit + an optional caption, in SF Pro Rounded with monospaced digits.
/// Scales with Dynamic Type (`@ScaledMetric`). Feed it `UnitFormat.Parts`:
///
///     MetricView(fmt.speedParts(speed), label: "speed")
///     MetricView(value: "43", unit: "%", label: "done", size: .medium)
///
/// VoiceOver reads "value unit, label" unless an explicit `accessibilityValue` is given.
struct MetricView: View {
    enum Size {
        case small, medium, large, hero
        var base: CGFloat {
            switch self {
            case .small: return 22
            case .medium: return 32
            case .large: return 44
            case .hero: return 64
            }
        }
    }

    let value: String
    var unit: String = ""
    var label: LocalizedStringKey? = nil
    var size: Size = .large
    var alignment: HorizontalAlignment = .leading
    var valueColor: Color = Theme.text
    var accessibilityValue: String? = nil

    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    init(value: String,
         unit: String = "",
         label: LocalizedStringKey? = nil,
         size: Size = .large,
         alignment: HorizontalAlignment = .leading,
         valueColor: Color = Theme.text,
         accessibilityValue: String? = nil) {
        self.value = value
        self.unit = unit
        self.label = label
        self.size = size
        self.alignment = alignment
        self.valueColor = valueColor
        self.accessibilityValue = accessibilityValue
    }

    init(_ parts: UnitFormat.Parts,
         label: LocalizedStringKey? = nil,
         size: Size = .large,
         alignment: HorizontalAlignment = .leading,
         valueColor: Color = Theme.text) {
        self.init(value: parts.value, unit: parts.unit, label: label, size: size,
                  alignment: alignment, valueColor: valueColor)
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(Theme.metricFont(size: size.base * scale))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                if !unit.isEmpty {
                    Text(unit)
                        .font(Theme.metricFont(size: max(13, size.base * 0.36) * scale, weight: .semibold))
                        .foregroundStyle(Theme.textDim)
                        .lineLimit(1)
                }
            }
            if let label {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.map { Text($0) } ?? Text(verbatim: ""))
        .accessibilityValue(Text(verbatim: accessibilityValue ?? (unit.isEmpty ? value : "\(value) \(unit)")))
    }
}

#Preview("MetricView") {
    let fmt = UnitFormat(units: .metric)
    return VStack(alignment: .leading, spacing: 24) {
        MetricView(value: "350", unit: "m", size: .hero)
        HStack(spacing: 28) {
            MetricView(fmt.speedParts(6.8), label: "speed")
            MetricView(fmt.distanceParts(18_100), label: "remaining")
            MetricView(value: "43", unit: "%", label: "done")
        }
        MetricView(fmt.elevationParts(142), label: "climb", size: .small)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .haloScreenBackground()
    .haloTheme()
}
