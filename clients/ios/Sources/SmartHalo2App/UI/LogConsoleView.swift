import SwiftUI
import UIKit

/// Live, auto-scrolling log console. Shows every protocol/BLE step in real time so a stuck or
/// failed connect/recover is diagnosable on the device itself.
struct LogConsoleView: View {
    @ObservedObject private var log = LogStore.shared
    private let height: CGFloat

    init(height: CGFloat = 240) { self.height = height }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Live log", systemImage: "terminal")
                    .font(.caption).bold()
                    .foregroundStyle(Theme.text)
                Spacer()
                Button {
                    UIPasteboard.general.string = log.plainText()
                } label: { Text("Copy").font(.caption) }
                Button(role: .destructive) {
                    log.clear()
                } label: { Text("Clear").font(.caption) }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(log.lines) { line in
                            Text("\(line.time)  \(line.text)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(color(for: line.text))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                        if log.lines.isEmpty {
                            Text("Waiting for activity…")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(6)
                }
                .frame(height: height)
                .background(Theme.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.stroke, lineWidth: 1))
                .onChange(of: log.lines.count) { _, _ in
                    if let last = log.lines.last {
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
    }

    private func color(for text: String) -> Color {
        if text.hasPrefix("✗") { return Theme.danger }
        if text.hasPrefix("←") { return Theme.accent }
        if text.hasPrefix("→") { return Theme.info }
        if text.hasPrefix("recovery:") || text.hasPrefix("handshake:") || text.hasPrefix("alarm:") { return Theme.warn }
        return Theme.text
    }
}
