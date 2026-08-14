import AppKit
import SwiftUI

enum UsageState {
    case loading
    case noCredentials
    case keychainDenied
    case malformedCredentials
    case signedOut
    case failed(String)
    case loaded(UsageSnapshot)
}

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var state: UsageState = .loading
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var notice: String?

    private let client = UsageClient()
    private var inFlight: Task<Void, Never>?
    private var lastRequestStarted: Date?
    private var lastSnapshot: UsageSnapshot?
    private var throttleStreak = 0
    private var nextAllowedRequest: Date?

    private let minimumRequestInterval: TimeInterval = 5
    private let maximumBackoff: TimeInterval = 900

    /// Coalesces onto an in-flight request and rate-limits the rest, so opening
    /// the menu or clicking Refresh repeatedly cannot burst requests at the API.
    /// The `/api/oauth/usage` budget is shared with the `claude` CLI and the
    /// desktop app, so a backoff also holds off the timer after a 429. An
    /// explicit Refresh is deliberate and bypasses that backoff.
    func refresh(userInitiated: Bool = false) {
        guard inFlight == nil else { return }

        let now = Date()
        if let last = lastRequestStarted, now.timeIntervalSince(last) < minimumRequestInterval {
            return
        }
        if !userInitiated, let next = nextAllowedRequest, now < next {
            return
        }

        lastRequestStarted = now
        inFlight = Task { [weak self] in
            guard let self else { return }
            defer { self.inFlight = nil }
            do {
                let snapshot = try await self.client.fetch()
                self.lastSnapshot = snapshot
                self.state = .loaded(snapshot)
                self.lastUpdated = Date()
                self.notice = nil
                self.throttleStreak = 0
                self.nextAllowedRequest = nil
            } catch {
                self.apply(error)
            }
        }
    }

    private func apply(_ error: Error) {
        switch error {
        case UsageError.rateLimited(let retryAfter):
            throttleStreak += 1
            let backoff = 60 * pow(2, Double(throttleStreak - 1))
            let requested = (retryAfter?.isFinite ?? false) ? retryAfter! : backoff
            nextAllowedRequest = Date().addingTimeInterval(min(requested, maximumBackoff))
            degrade(to: "Rate limited by the API — showing the last reading.")
        case UsageError.network(let description):
            degrade(to: description)
        default:
            throttleStreak = 0
            nextAllowedRequest = nil
            state = Self.state(for: error)
            notice = nil
        }
    }

    /// A transient failure keeps the last good snapshot on screen instead of
    /// blanking the panel and the menu bar title; the notice says why the
    /// numbers are stale. Before any successful read there is nothing to keep.
    private func degrade(to notice: String) {
        if let lastSnapshot {
            state = .loaded(lastSnapshot)
            self.notice = notice
        } else {
            state = .failed(notice)
            self.notice = nil
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
        case UsageError.keychainDenied: return .keychainDenied
        case UsageError.malformedCredentials: return .malformedCredentials
        case UsageError.keychainFailure(let status): return .failed("Keychain unavailable (OSStatus \(status))")
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
