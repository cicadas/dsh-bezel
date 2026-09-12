import AppKit
import Foundation
import Observation
import BezelCore

/// Glue between saved Hosts, the optional local dsh child, and the WebView.
@MainActor
@Observable
final class AppState {
    let config = ConfigStore()
    let runner = LocalHostRunner()
    /// Posts page events as macOS notifications. A no-op outside an app
    /// bundle, so the bare `swift run` executable simply never notifies.
    private let notifier = Notifier()
    /// Turns page snapshots into the transitions worth notifying about.
    @ObservationIgnored private var pageEvents = PageEventDetector()
    /// The hidden page reading the complete sidebar — every workspace
    /// group, every session — for the background the displayed page cannot
    /// see. Its rows replace the displayed page's (partial) ones before
    /// detection. Ignored by Observation: it is machinery, not state a view
    /// renders.
    @ObservationIgnored private var sidebarProbe: SidebarProbe?

    /// Language of this app's own interface, straight from the config file.
    ///
    /// Read by every view through `text(_:)`, which is what makes a change
    /// here redraw them; `Localization` itself holds no state.
    var language: AppLanguage { config.language }

    /// The language the menu bar was built from at launch — the value
    /// `mirrorLanguageIntoAppleLanguages()` put in front of macOS. The config
    /// can move on during a session, but the menu bar is already drawn, so
    /// a change only lands there after a restart.
    @ObservationIgnored private let launchLanguage: AppLanguage
    /// True while the picked language and the menu bar's language disagree.
    var needsMenuBarRestart: Bool { config.language != launchLanguage }

    /// URL the WebView is asked to display; `nil` shows the connect prompt.
    private(set) var currentURL: URL?
    /// Latest navigation state reported by the WebView.
    private(set) var web = WebViewState()
    /// Bumped to ask the WebView for a reload.
    private(set) var reloadToken = 0
    /// Host the displayed page belongs to.
    private(set) var attachedHostID: UUID?

    /// Auto-connect runs at most once per launch, so an explicit disconnect stays.
    @ObservationIgnored private var didAutoConnect = false
    /// Removed in `deinit`: an observer is a registration, and a registration
    /// is undone where it was made.
    @ObservationIgnored private var terminationObserver: (any NSObjectProtocol)?

    init() {
        launchLanguage = config.language
        // A launcher that will spend most of its life in the background
        // waiting for the Host should be authorized before the first event
        // arrives, not after. The system asks once; a denial is remembered.
        if config.notificationsEnabled {
            notifier.requestAuthorizationIfNeeded()
        }
        // A managed child must not outlive a normal quit; AppKit delivers this
        // notification before the process exits, and synchronously is required
        // because an async hop would lose the race with termination.
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.runner.stop() }
        }
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    // MARK: - Language

    /// The current language as a value to hand to code outside the UI.
    var localization: Localization { Localization(language: config.language) }

    /// Wording for this app's own text, in the current language.
    func text(_ message: Message, _ arguments: String...) -> String {
        localization.text(message, arguments)
    }

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
    /// (a granted one is remembered and never re-asked); either way the
    /// detector starts from a fresh baseline, so transitions that happened
    /// while notifications were off can never fire late.
    func setNotificationsEnabled(_ enabled: Bool) {
        config.setNotificationsEnabled(enabled)
        pageEvents.reset()
        if enabled { notifier.requestAuthorizationIfNeeded() }
    }

    // MARK: - Connection

    var attachedHost: DSHHost? { config.host(id: attachedHostID) }

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

    /// URL for the system browser; carries the token so a fresh browser session
    /// can mint its own cookie.
    var browserURL: URL? { attachedHost?.loadURL ?? currentURL }

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
        guard attachedHostID == nil else { return }
        guard let remembered = config.host(id: config.lastConnectedHostID) ?? config.selectedHost else { return }
        connect(to: remembered)
    }

    /// Attach the WebView to `host`, starting a local child when it is managed.
    func connect(to host: DSHHost) {
        config.select(id: host.id)
        detach()
        guard host.isValid else {
            web = WebViewState(problem: .invalidAddress(host.baseURL))
            return
        }
        attachedHostID = host.id
        web = WebViewState(isLoading: true)
        // Remember the attachment itself, not just the picker: this is what the
        // next launch reconnects to.
        config.noteConnected(id: host.id)
        if host.managed {
            runner.start(host: host) { [weak self] url in
                guard let self, self.attachedHostID == host.id, self.runner.hostID == host.id else { return }
                self.currentURL = url
            }
        } else {
            currentURL = host.loadURL
        }
    }

    /// Attach to the Host currently selected in the picker.
    func connectSelected() {
        guard let host = config.selectedHost else { return }
        connect(to: host)
    }

    /// Drop the page and terminate any owned child process.
    func detach() {
        runner.stop()
        currentURL = nil
        attachedHostID = nil
        web = WebViewState()
        // A different page (or none) means everything the detector remembers
        // is about a conversation nobody is looking at — and the probe was
        // authorized for a Host this app is no longer attached to.
        pageEvents.reset()
        stopSidebarProbe()
    }

    func reload() {
        reloadToken &+= 1
        // A reload re-runs the observer script, whose first post is a fresh
        // baseline; the detector must not draw conclusions across the gap.
        pageEvents.reset()
    }

    func apply(_ state: WebViewState) {
        web = state
    }

    // MARK: - Page signals

    /// Feed the observer script's latest snapshot to the detector, and notify
    /// the user about anything that needs them.
    func apply(_ snapshot: PageSnapshot) {
        guard config.notificationsEnabled else {
            pageEvents.reset()
            stopSidebarProbe()
            return
        }
        // The first snapshot means the displayed page is up and authorized,
        // so its cookie exists to copy: the right moment to bring the probe
        // up. From here on every poll also nudges the probe's watchdog.
        if sidebarProbe == nil, let url = currentURL {
            let probe = SidebarProbe()
            probe.start(url: url)
            sidebarProbe = probe
        }
        sidebarProbe?.reloadIfStale()
        // The probe's sidebar is complete (every group expanded); the
        // displayed page's is whatever its view state renders. While the
        // probe is alive and posting, its rows are the background's truth.
        var merged = snapshot
        if let rows = sidebarProbe?.freshSidebar {
            merged = merged.replacingSidebar(rows)
        }
        for event in pageEvents.advance(to: merged) {
            notify(event, sessionTitle: merged.currentSessionTitle)
        }
    }

    /// Tear the probe down; the displayed page's own sidebar is the fallback.
    private func stopSidebarProbe() {
        sidebarProbe?.stop()
        sidebarProbe = nil
    }

    /// The page event as a notification. The message follows the interface
    /// language; the subtitle always names the conversation the event is
    /// about, so no banner is a bare "something happened". The body carries
    /// the one line of content the page can offer: the user's own words for
    /// a finished task.
    private func notify(_ event: PageEvent, sessionTitle: String?) {
        let message: Message
        let subtitle: String?
        let body: String?
        switch event {
        case .attentionNeeded(.approval):
            message = .notificationAttentionApproval
            subtitle = sessionTitle ?? hostName
            body = nil
        case .attentionNeeded(.question):
            message = .notificationAttentionQuestion
            subtitle = sessionTitle ?? hostName
            body = nil
        case .attentionNeeded(.planReview):
            message = .notificationAttentionPlan
            subtitle = sessionTitle ?? hostName
            body = nil
        case .attentionNeeded(.none):
            return
        case .taskFinished(let prompt):
            message = .notificationTaskFinished
            subtitle = sessionTitle
            body = prompt.map(taskLabel)
        case .backgroundTaskFinished(let title):
            message = .notificationBackgroundTaskFinished
            subtitle = title
            body = nil
        case .backgroundAttentionNeeded(let title):
            message = .notificationBackgroundAttention
            subtitle = title
            body = nil
        }
        // A summons must reach the user in any app state — frontmost,
        // background, minimized — because it blocks the Host; a finish is
        // status, and may yield to "the page is already showing it".
        notifier.deliver(title: text(message), subtitle: subtitle, body: body, essential: event.isWaitingForUser)
    }

    /// Which connection a page event is about, when the page itself could
    /// not name the conversation.
    private var hostName: String? {
        attachedHost?.displayName(in: localization)
    }

    /// One line of task identity: whitespace collapsed, bounded to what a
    /// notification banner will actually show.
    private func taskLabel(_ prompt: String) -> String {
        let collapsed = prompt.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.count > 80 ? String(collapsed.prefix(80)) + "…" : collapsed
    }

    func openInBrowser() {
        guard let url = browserURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Status wording

    /// What to show under a failed managed launch: how the search went, then
    /// whatever the child itself printed. Composed here — rather than stored
    /// in the runner — so a language change also re-renders a failure that is
    /// already on screen.
    var runnerDiagnostics: [String] {
        var lines = runner.discovery?.diagnosticLines(localization) ?? []
        let output = runner.recentOutput.suffix(12)
        if !lines.isEmpty, !output.isEmpty { lines.append("") }
        lines.append(contentsOf: output)
        return lines
    }

    /// What went wrong, in the current language, if anything has.
    ///
    /// `.system` is WebKit's own already-localized description; the rest is
    /// this app's wording and therefore follows `language`.
    var problemText: String? {
        switch web.problem {
        case .none: nil
        case .system(let description): description
        case .invalidAddress(let address): text(.invalidAddress, address)
        case .credentialRejected: text(.errorCredentialRejected)
        }
    }

    /// One line describing the connection for the toolbar and the connect prompt.
    var statusText: String {
        if let problemText { return problemText }
        if attachedHost?.managed == true {
            switch runner.phase {
            case .locating: return text(.phaseLocating)
            case .starting: return text(.phaseStarting)
            case .failed(let failure): return failureText(failure)
            default: break
            }
        }
        if currentURL == nil { return text(.statusNotConnected) }
        return web.isLoading ? text(.statusLoading) : (web.title ?? text(.statusConnected))
    }

    func failureText(_ failure: LocalHostRunner.Failure) -> String {
        switch failure {
        case .noRunnableExecutable(let attempts):
            text(.failureNoDSH, String(attempts))
        case .launchFailed(let reason):
            text(.failureLaunchFailed, reason)
        case .exited(let status):
            text(.failureExited, String(status))
        case .exitedBeforeStart(let status):
            text(.failureExitedBeforeStart, String(status))
        case .timedOut(let seconds):
            text(.failureTimedOut, String(seconds))
        }
    }
}
