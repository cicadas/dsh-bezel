import AppKit
import Foundation
import Observation
import BezelCore

/// Glue between saved Hosts, the open tabs (`Session` each owning one
/// connection to a Host), and the app-level settings.
@MainActor
@Observable
final class AppState {
    let config = ConfigStore()
    /// Posts page events as macOS notifications. A no-op outside an app
    /// bundle, so the bare `swift run` executable simply never notifies.
    let notifier = Notifier()

    /// The open tabs, one per connection. Never empty: closing the last tab
    /// leaves a fresh blank one, so the connect prompt always has a home.
    private(set) var sessions: [Session] = []
    /// Which tab the window is showing.
    private(set) var selectedSessionID: UUID?

    /// Auto-connect runs at most once per launch, so an explicit disconnect stays.
    @ObservationIgnored private var didAutoConnect = false
    /// Removed in `deinit`: an observer is a registration, and a registration
    /// is undone where it was made.
    @ObservationIgnored private var terminationObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var occlusionObserver: (any NSObjectProtocol)?

    /// The language the menu bar was built from at launch — the value
    /// `mirrorLanguageIntoAppleLanguages()` put in front of macOS. The config
    /// can move on during a session, but the menu bar is already drawn, so
    /// a change only lands there after a restart.
    @ObservationIgnored private let launchLanguage: AppLanguage

    init() {
        launchLanguage = config.language
        // A launcher that will spend most of its life in the background
        // waiting for the Host should be authorized before the first event
        // arrives, not after. The system asks once; a denial is remembered.
        if config.notificationsEnabled {
            notifier.requestAuthorizationIfNeeded()
        }
        // One blank tab to start: the connect prompt lives in it, and the
        // first connection reuses it rather than opening a second tab.
        let first = makeSession()
        sessions = [first]
        selectedSessionID = first.id

        // A managed child must not outlive a normal quit; AppKit delivers this
        // notification before the process exits, and synchronously is required
        // because an async hop would lose the race with termination.
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sessions.forEach { $0.shutdown() } }
        }
        // A renewal may only fire while no window is visible; a visibility
        // change is therefore the moment the check is most worth running.
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sessions.forEach { $0.checkPageRenewal() } }
        }
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
    }

    private func makeSession() -> Session {
        Session(config: config, notifier: notifier)
    }

    // MARK: - Language

    /// The current language as a value to hand to code outside the UI.
    var localization: Localization { Localization(language: config.language) }

    /// Wording for this app's own text, in the current language.
    func text(_ message: Message, _ arguments: String...) -> String {
        localization.text(message, arguments)
    }

    /// The current language as a value to hand to code outside the UI.
    var language: AppLanguage { config.language }

    /// The language the menu bar was built from at launch.
    var needsMenuBarRestart: Bool { config.language != launchLanguage }

    func setLanguage(_ language: AppLanguage) {
        config.setLanguage(language)
    }

    /// Relaunch the app. The menu bar cannot be re-rendered in place, so a
    /// language change lands there on a fresh launch: a detached shell waits
    /// for this instance to be gone, then `open`s the bundle again. The child
    /// shell outlives this process (children are re-parented, not killed),
    /// and the existing quit path still stops the managed Host.
    func restart() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; open \"\(Bundle.main.bundleURL.path)\""]
        do { try task.run() } catch { return }
        NSApp.terminate(nil)
    }

    /// Toggle notifications. Turning them on asks the system for permission
    /// (a granted one is remembered and never re-asked) and brings every
    /// tab's Host channel up; turning them off tears them all down, so a
    /// bezel that is not notifying holds no connection at all. Either way each
    /// detector starts from a fresh baseline on the next start.
    func setNotificationsEnabled(_ enabled: Bool) {
        config.setNotificationsEnabled(enabled)
        if enabled {
            notifier.requestAuthorizationIfNeeded()
            sessions.forEach { $0.updateFeed() }
        } else {
            sessions.forEach { $0.stopFeed() }
        }
    }

    /// Toggle automatic page renewal. Nothing else needs to change here: the
    /// clock runs whenever a Host is attached, and every decision consults
    /// the setting, so flipping it takes effect at the next check.
    func setPageRenewalEnabled(_ enabled: Bool) {
        config.setPageRenewalEnabled(enabled)
    }

    // MARK: - Tabs

    /// The tab the window is showing. The array is never empty, so the first
    /// session is the fallback when the selected id no longer names one.
    var selectedSession: Session {
        sessions.first { $0.id == selectedSessionID } ?? sessions[0]
    }

    func select(_ session: Session) {
        selectedSessionID = session.id
    }

    /// Open a fresh blank tab and bring it to the front.
    func newTab() {
        let session = makeSession()
        sessions.append(session)
        selectedSessionID = session.id
    }

    /// Close a tab, stopping whatever it owns. The last tab is replaced by a
    /// fresh blank one, so the connect prompt never has no home.
    func close(_ session: Session) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        session.detach()
        sessions.remove(at: index)
        if sessions.isEmpty {
            let fresh = makeSession()
            sessions = [fresh]
            selectedSessionID = fresh.id
        } else if selectedSessionID == session.id {
            selectedSessionID = sessions[min(index, sessions.count - 1)].id
        }
    }

    /// Connect `host` into a tab: the selected tab when it is still blank,
    /// any other blank tab, or a new tab when every tab is in use.
    func connect(to host: DSHHost) {
        let session: Session
        if let selected = sessions.first(where: { $0.id == selectedSessionID }), selected.hostID == nil {
            session = selected
        } else if let blank = sessions.first(where: { $0.hostID == nil }) {
            session = blank
            selectedSessionID = blank.id
        } else {
            session = makeSession()
            sessions.append(session)
            selectedSessionID = session.id
        }
        session.attach(to: host)
    }

    /// Attach to the Host currently selected in the picker.
    func connectSelected() {
        guard let host = config.selectedHost else { return }
        connect(to: host)
    }

    /// Drop every tab bound to a bookmark, without closing the tabs. Called
    /// when a bookmark is removed: its managed child must not outlive the
    /// bookmark that described it.
    func closeTabs(forHost id: UUID) {
        for session in sessions where session.hostID == id {
            session.detach()
        }
    }

    // MARK: - Selected-tab proxies

    var attachedHostID: UUID? { selectedSession.hostID }
    var attachedHost: DSHHost? { config.host(id: selectedSession.hostID) }
    var currentURL: URL? { selectedSession.currentURL }
    var web: WebViewState { selectedSession.web }
    var reloadToken: Int { selectedSession.reloadToken }
    var browserURL: URL? { selectedSession.browserURL }
    var runner: LocalHostRunner { selectedSession.runner }
    var statusText: String { selectedSession.statusText }
    var problemText: String? { selectedSession.problemText }
    var runnerDiagnostics: [String] { selectedSession.runnerDiagnostics }
    var channelStatus: String? { selectedSession.channelStatus }

    func reload() { selectedSession.reload() }

    func openInBrowser() { selectedSession.openInBrowser() }

    // MARK: - First-launch guide

    /// Whether the first-launch guide is still due. Read by `MainView` to
    /// decide between the guide and the ordinary interface.
    var showsOnboarding: Bool { !config.onboardingCompleted }

    /// The guide is over — connected through it, or skipped. Remembered, so
    /// it only ever comes back when the config file is deleted.
    func completeOnboarding() {
        config.completeOnboarding()
    }

    /// The guide's "bind" outcome: a bookmark pointing at a dsh this app did
    /// not start, connected immediately.
    ///
    /// Returns the connected Host so the caller can tell a refused address
    /// from a successful bind.
    @discardableResult
    func bindRunningProcess(baseURL: String, token: String) -> DSHHost? {
        let host = config.add(DSHHost(
            name: text(.onboardingBindHostName),
            baseURL: baseURL,
            token: token,
            managed: false
        ))
        connect(to: host)
        return attachedHostID == host.id ? host : nil
    }

    /// The guide's "managed" outcome: the seeded managed Host, pointed at
    /// `command` — empty for the standard automatic invocation.
    ///
    /// The guide reuses the seeded bookmark rather than adding another, so
    /// "how my local dsh starts" stays one setting in one place; clearing the
    /// command in Settings returns it to automatic.
    @discardableResult
    func prepareManagedHost(command: String) -> DSHHost? {
        var host = config.hosts.first(where: { $0.managed })
            ?? config.add(DSHHost(
                name: text(.seedHostName),
                baseURL: "http://127.0.0.1:3080",
                managed: true
            ))
        host.launchCommand = command
        config.update(host)
        return host
    }

    /// Attach what was in use last time, the first time a window appears.
    ///
    /// This is the "remember the last configuration" behaviour: the Host, its
    /// settings and its managed/proxy mode come back from the config file. A
    /// managed Host is started from scratch every launch, since its port and
    /// token are new each run. While the guide is due, nothing auto-connects —
    /// the guide, not the seed, decides the first connection; a skipped guide
    /// lands on the connect prompt, one click away.
    func autoConnectIfNeeded() {
        guard !didAutoConnect else { return }
        didAutoConnect = true
        guard config.onboardingCompleted else { return }
        guard sessions.allSatisfy({ $0.hostID == nil }) else { return }
        guard let remembered = config.host(id: config.lastConnectedHostID) ?? config.selectedHost else { return }
        connect(to: remembered)
    }
}
