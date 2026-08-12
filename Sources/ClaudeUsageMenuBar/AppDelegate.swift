import AppKit
import SwiftUI

enum UsageState {
    case loading
    case noCredentials
    case signedOut
    case failed(String)
    case loaded(UsageSnapshot)
}

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var state: UsageState = .loading
    @Published private(set) var lastUpdated: Date?

    private let client = UsageClient()
    private var inFlight: Task<Void, Never>?

    func refresh() {
        inFlight?.cancel()
        inFlight = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await self.client.fetch()
                guard !Task.isCancelled else { return }
                self.state = .loaded(snapshot)
                self.lastUpdated = Date()
            } catch {
                guard !Task.isCancelled else { return }
                self.state = Self.state(for: error)
            }
        }
    }

    /// The menu bar title: ring glyph, percent, and time until the session
    /// limit resets.
    var menuBarTitle: String {
        guard case .loaded(let snapshot) = state, let session = snapshot.sessionLimit else {
            return "◌"
        }

        var title = "\(UsageFormat.ringGlyph(forPercent: session.percent)) \(session.percent)%"
        if let remaining = session.timeRemaining {
            title += " · \(UsageFormat.compactRemaining(remaining))"
        }
        return title
    }

    private static func state(for error: Error) -> UsageState {
        switch error {
        case UsageError.noCredentials: return .noCredentials
        case UsageError.signedOut: return .signedOut
        case UsageError.network(let description): return .failed(description)
        case UsageError.decoding(let description): return .failed("Unreadable response: \(description)")
        case UsageError.badResponse(let code): return .failed("Request failed (HTTP \(code))")
        default: return .failed(error.localizedDescription)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = UsageStore()
    private var statusItem: NSStatusItem!
    private var contentItem: NSMenuItem!
    private var refreshTimer: Timer?
    private var titleObservation: Task<Void, Never>?

    private let refreshInterval: TimeInterval = 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)

        let menu = NSMenu()
        menu.delegate = self

        let hostingView = NSHostingView(rootView: MenuContentView(store: store))
        hostingView.frame = NSRect(origin: .zero, size: hostingView.fittingSize)

        contentItem = NSMenuItem()
        contentItem.view = hostingView
        menu.addItem(contentItem)
        statusItem.menu = menu

        observeTitle()
        store.refresh()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.store.refresh() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        titleObservation?.cancel()
        titleObservation = nil
    }

    func menuWillOpen(_ menu: NSMenu) {
        store.refresh()
        if let hostingView = contentItem.view {
            hostingView.frame = NSRect(origin: .zero, size: hostingView.fittingSize)
        }
    }

    private func observeTitle() {
        titleObservation = Task { [weak self] in
            guard let self else { return }
            for await _ in self.store.$state.values {
                self.statusItem.button?.title = self.store.menuBarTitle
            }
        }
    }
}
