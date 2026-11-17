import AppKit
import SwiftUI

/// The dropdown shown when the status item is clicked, mirroring the layout of
/// the Claude desktop app's Settings > Usage panel.
struct MenuContentView: View {
    enum Layout: String, CaseIterable {
        case byWindow = "Sessions & weekly"
        case byTool = "By company"
    }

    @ObservedObject var store: UsageStore
    /// Called when the content changes height, so the hosting menu item can resize.
    var onResize: () -> Void = {}
    @AppStorage("layout") private var layout = Layout.byTool

    private var claudeSnapshot: UsageSnapshot? {
        if case .loaded(let snapshot) = store.state { return snapshot }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch layout {
            case .byTool: byToolBody
            case .byWindow: byWindowBody
            }

            Divider()

            Picker("Layout", selection: $layout) {
                ForEach(Layout.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: layout) { _ in DispatchQueue.main.async(execute: onResize) }

            HStack(spacing: 12) {
                Button("Refresh") { store.refresh(userInitiated: true) }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .font(.system(size: 12))

            VStack(alignment: .leading, spacing: 2) {
                if let updated = store.lastUpdated {
                    Text("Last updated \(UsageFormat.relativeUpdated(updated))")
                }
                if let notice = store.notice {
                    Text(notice)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
    }

    @ViewBuilder
    private var byToolBody: some View {
        heading("✳ Claude Usage")
        claudeStatus
        if let claudeSnapshot {
            loadedBody(claudeSnapshot)
        }

        if let codex = store.codex {
            Divider()
            heading(">_ Codex Usage")
            loadedBody(codex.snapshot)
            codexStaleNote
        }
    }

    @ViewBuilder
    private var byWindowBody: some View {
        let claude = claudeSnapshot
        let codex = store.codex?.snapshot

        claudeStatus
        group("Current session",
              (claude?.limits(inGroup: "session") ?? []).map { ("✳ Claude", $0) }
              + (codex?.limits(inGroup: "session") ?? []).map { (">_ Codex", $0) })
        group("Weekly limits",
              (claude?.limits(inGroup: "weekly") ?? []).map { ("✳ \($0.label)", $0) }
              + (codex?.limits(inGroup: "weekly") ?? []).map { (">_ Codex", $0) })
        if let claude {
            ForEach(claude.otherGroups, id: \.self) { name in
                group(UsageFormat.humanize(name), claude.limits(inGroup: name).map { ("✳ \($0.label)", $0) })
            }
        }
        codexStaleNote
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.system(size: 13, weight: .semibold))
    }

    @ViewBuilder
    private var codexStaleNote: some View {
        if let recordedAt = store.codex?.recordedAt {
            Text("Codex live numbers unavailable, from its last activity \(UsageFormat.relativeUpdated(recordedAt))")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    /// Explains why Claude has no numbers; empty once they load.
    @ViewBuilder
    private var claudeStatus: some View {
        switch store.state {
        case .loading:
            message("Loading usage…")
        case .noCredentials:
            message("No Claude Code credentials found. Run `claude` and sign in.")
        case .keychainDenied:
            message("Keychain access was denied. Unlock your login keychain, or allow ClaudeUsageMenuBar in Keychain Access.")
        case .malformedCredentials:
            message("Stored Claude Code credentials aren't in the expected format. Run `claude` to sign in again.")
        case .signedOut:
            message("Sign in to Claude Code")
        case .failed(let description):
            message(description)
        case .loaded:
            EmptyView()
        }
    }

    @ViewBuilder
    private func loadedBody(_ snapshot: UsageSnapshot) -> some View {
        if snapshot.limits.isEmpty {
            message("No usage limits reported.")
        } else {
            group("Current session", snapshot.limits(inGroup: "session").map { ($0.label, $0) })
            group("Weekly limits", snapshot.limits(inGroup: "weekly").map { ($0.label, $0) })
            ForEach(snapshot.otherGroups, id: \.self) { name in
                group(UsageFormat.humanize(name), snapshot.limits(inGroup: name).map { ($0.label, $0) })
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ rows: [(title: String, limit: UsageLimit)]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    usageRow(row.title, row.limit)
                }
            }
        }
    }

    private func usageRow(_ title: String, _ limit: UsageLimit) -> some View {
        let tint = self.tint(for: limit)

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
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

            if let pace = limit.weeklyPace {
                Text(UsageFormat.paceLine(for: pace))
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
