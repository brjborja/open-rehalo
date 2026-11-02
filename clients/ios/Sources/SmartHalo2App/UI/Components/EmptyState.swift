import SwiftUI

/// Centered "nothing here yet" panel: icon, title, message and up to two actions (primary neon +
/// secondary). Used by empty tabs/lists and error states.
///
///     EmptyState(systemImage: "map", title: "No routes yet",
///                message: "Import a GPX from Files or try the demo route.",
///                primary: .init("Import GPX", systemImage: "square.and.arrow.down") { … },
///                secondary: .init("Use demo route") { … })
struct EmptyState: View {
    struct Action {
        let title: LocalizedStringKey
        var systemImage: String? = nil
        let perform: () -> Void

        init(_ title: LocalizedStringKey, systemImage: String? = nil, perform: @escaping () -> Void) {
            self.title = title
            self.systemImage = systemImage
            self.perform = perform
        }
    }

    let systemImage: String
    let title: LocalizedStringKey
    var message: LocalizedStringKey? = nil
    var tint: Color = Theme.accent
    var primary: Action? = nil
    var secondary: Action? = nil

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 88, height: 88)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
                .accessibilityHidden(true)
            VStack(spacing: Theme.Space.s) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.text)
                if let message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textDim)
                }
            }
            .multilineTextAlignment(.center)
            if primary != nil || secondary != nil {
                VStack(spacing: Theme.Space.s) {
                    if let primary {
                        PrimaryButton(primary.title, systemImage: primary.systemImage, action: primary.perform)
                    }
                    if let secondary {
                        PrimaryButton(secondary.title, systemImage: secondary.systemImage,
                                      kind: .secondary, action: secondary.perform)
                    }
                }
                .padding(.top, Theme.Space.s)
            }
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("EmptyState") {
    EmptyState(systemImage: "point.topleft.down.to.point.bottomright.curvepath",
               title: "No routes yet",
               message: "Import a GPX from Files or try the demo route.",
               primary: .init("Import GPX", systemImage: "square.and.arrow.down") {},
               secondary: .init("Use demo route") {})
        .haloScreenBackground()
        .haloTheme()
}
