import AppKit
import SwiftUI

/// The dropdown shown when the status item is clicked, mirroring the layout of
/// the Claude desktop app's Settings > Usage panel.
struct MenuContentView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claude Usage")
                .font(.system(size: 13, weight: .semibold))

            switch store.state {
            case .loading:
                message("Loading usage…")
            case .noCredentials:
                message("No Claude Code credentials found. Run `claude` and sign in.")
            case .signedOut:
                message("Sign in to Claude Code")
            case .failed(let description):
                message(description)
            case .loaded(let snapshot):
                loadedBody(snapshot)
            }

            Divider()

            HStack(spacing: 12) {
                Button("Refresh") { store.refresh() }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .font(.system(size: 12))

            if let updated = store.lastUpdated {
                Text("Last updated \(UsageFormat.relativeUpdated(updated))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
    }

    @ViewBuilder
    private func loadedBody(_ snapshot: UsageSnapshot) -> some View {
        if snapshot.limits.isEmpty {
            message("No usage limits reported.")
        } else {
            group("Current session", snapshot.limits(inGroup: "session"))
            group("Weekly limits", snapshot.limits(inGroup: "weekly"))
            ForEach(snapshot.otherGroups, id: \.self) { name in
                group(UsageFormat.humanize(name), snapshot.limits(inGroup: name))
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ limits: [UsageLimit]) -> some View {
        if !limits.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(limits.enumerated()), id: \.offset) { _, limit in
                    usageRow(limit)
                }
            }
        }
    }

    private func usageRow(_ limit: UsageLimit) -> some View {
        let tint = self.tint(for: limit)

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(limit.label)
                    .font(.system(size: 12))
                Spacer()
                Text("\(limit.percent)%")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(tint)
            }

            ProgressBar(fraction: Double(limit.percent) / 100, tint: tint)

            if let resetLine = UsageFormat.resetLine(for: limit) {
                Text(resetLine)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Unrecognized severities fall back to the percent thresholds.
    private func tint(for limit: UsageLimit) -> Color {
        switch limit.severity {
        case "normal": return .accentColor
        case "warning": return .orange
        case "critical": return .red
        default:
            if limit.percent >= 90 { return .red }
            if limit.percent >= 75 { return .orange }
            return .accentColor
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ProgressBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                Capsule()
                    .fill(tint)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 6)
    }
}
