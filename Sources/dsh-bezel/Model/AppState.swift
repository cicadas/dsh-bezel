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
    /// Turns Host feed facts into the transitions worth notifying about.
    /// Ignored by Observation: it is machinery, not state a view renders.
    @ObservationIgnored private var detector = SessionEventDetector()
    /// The notification channel to the attached Host: the Host's own session
    /// list and summons events, read over its API, so notifications never
    /// have to watch — or touch — the Web page. Started and stopped with the
    /// connection and the notification setting. Ignored by Observation: it is
    /// machinery, not state a view renders.
    @ObservationIgnored private var feed: HostFeed?
    /// The origin the live feed is attached to, so reconnecting to the same
    /// Host does not tear the channel down for nothing.
    @ObservationIgnored private var feedOrigin: URL?
    /// How the notification channel is doing, for the Settings status line.
    private(set) var feedHealth: HostFeedHealth = .idle
    /// Whether the Host is blocked waiting for the user's answer. Kept from
    /// the feed's raw events (before the detector's dedupe, which folds
    /// redeliveries away) because page renewal must never fire while an
    /// approval or question is open.
    @ObservationIgnored private var summonsActive = false

    // MARK: Page renewal (interval housekeeping)

    /// When the displayed page last finished loading cleanly.
    @ObservationIgnored private var lastPageLoad: Date?
    /// When this mechanism last renewed the page.
    @ObservationIgnored private var lastRenewal: Date?
    /// Periodic renewal check. Runs only while a Host is attached.
    @ObservationIgnored private var renewalClock: Timer?
    /// Fired whenever a window's visibility changes, so a renewal that has
    /// been waiting for the user to hide the window happens within moments of
    /// that, not at the next five-minute tick.
    @ObservationIgnored private var occlusionObserver: (any NSObjectProtocol)?

    /// A managed launch found the bookmark's own port already served by a
    /// running dsh: the question the connect prompt must answer before
    /// anything starts.
    private(set) var portConflict: PortConflict?
    /// True between pressing start on a managed Host and the port check's
    /// answer. No launch has begun yet, so the status line names the check
    /// rather than the runner's phases.
    private(set) var isCheckingPort = false

    /// One pending "this port is already served" question. The matches come
    /// along so the judgment — which process, as `ps` saw it — is shown,
    /// never a black box.
    struct PortConflict: Equatable {
        var hostID: UUID
        var port: Int
        var matches: [DSHProcessScan.Match]
    }

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
        // A renewal may only fire while no window is visible; a visibility
        // change is therefore the moment the check is most worth running.
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPageRenewal() }
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
    /// (a granted one is remembered and never re-asked) and brings the Host
    /// channel up; turning them off tears it down, so a bezel that is not
    /// notifying holds no connection at all. Either way the detector starts
    /// from a fresh baseline on the next start, so transitions that happened
    /// while notifications were off can never fire late.
    func setNotificationsEnabled(_ enabled: Bool) {
        config.setNotificationsEnabled(enabled)
        if enabled {
            notifier.requestAuthorizationIfNeeded()
            updateFeed()
        } else {
            stopFeed()
        }
    }

    /// Toggle automatic page renewal. Nothing else needs to change here: the
    /// clock runs whenever a Host is attached, and every decision consults
    /// the setting, so flipping it takes effect at the next check.
    func setPageRenewalEnabled(_ enabled: Bool) {
        config.setPageRenewalEnabled(enabled)
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
            startManaged(host: host)
        } else {
            currentURL = host.loadURL
            startRenewalClock()
            updateFeed()
        }
    }

    /// Begin a managed launch by asking the process table first: is the
    /// bookmark's own port already served by a running dsh? Starting a second
    /// dsh where one already answers would be the wrong answer to "start
    /// dsh" — the one that is there is the one to attach to.
    ///
    /// The scan reads the whole process table, so it runs off the main actor;
    /// nothing has been launched yet, and `finishManagedLaunch` decides
    /// between the launch and the question once the answer is in.
    private func startManaged(host: DSHHost) {
        guard let port = host.origin?.port else {
            // Nothing meaningful to check (an origin without an explicit
            // port): launch as before.
            runner.start(host: host) { [weak self] url in
                guard let self, self.attachedHostID == host.id, self.runner.hostID == host.id else { return }
                self.currentURL = url
                self.startRenewalClock()
                self.updateFeed()
            }
            return
        }
        isCheckingPort = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let report = DSHProcessScan.scan()
            let occupied = report.matches(occupying: port)
            await MainActor.run { [weak self] in
                self?.finishManagedLaunch(hostID: host.id, port: port, occupied: occupied)
            }
        }
    }

    /// The check's answer, back on the main actor. Only the Host this check
    /// was started for may act: anything else means the user moved on while
    /// `ps` was running, and a stale answer is dropped whole.
    private func finishManagedLaunch(hostID: UUID, port: Int, occupied: [DSHProcessScan.Match]) {
        isCheckingPort = false
        guard attachedHostID == hostID, currentURL == nil, let host = config.host(id: hostID) else { return }
        if occupied.isEmpty {
            runner.start(host: host) { [weak self] url in
                guard let self, self.attachedHostID == hostID, self.runner.hostID == hostID else { return }
                self.currentURL = url
                self.startRenewalClock()
                self.updateFeed()
            }
        } else {
            portConflict = PortConflict(hostID: hostID, port: port, matches: occupied)
        }
    }

    /// The conflict's preferred answer: attach to the dsh that is already
    /// serving the port, launching nothing. The bookmark stays managed — the
    /// next launch that finds the port free starts a child as usual.
    func bindToRunningDSH() {
        guard let conflict = portConflict, let host = config.host(id: conflict.hostID),
              let url = host.origin
        else {
            portConflict = nil
            return
        }
        portConflict = nil
        config.select(id: host.id)
        attachedHostID = host.id
        web = WebViewState(isLoading: true)
        config.noteConnected(id: host.id)
        // `origin`, not `loadURL`: binding rides the cookie the Host already
        // minted, so the one-shot token is never re-spent.
        currentURL = url
        startRenewalClock()
        updateFeed()
    }

    /// Decline both answers: stay on the connect prompt, start nothing.
    func dismissPortConflict() {
        portConflict = nil
    }

    /// Attach to the Host currently selected in the picker.
    func connectSelected() {
        guard let host = config.selectedHost else { return }
        connect(to: host)
    }

    /// What the connect prompt's primary button says for the Host the picker
    /// selects. "Connect" names two different acts here — attaching to a Host
    /// someone else runs, or launching one this app runs — and for the
    /// second, whether the launch is fresh or replaces a child that is
    /// already alive.
    var connectButtonMessage: Message {
        guard let host = config.selectedHost else { return .buttonConnectSelected }
        switch runner.connectAction(for: host) {
        case .connect: return .buttonConnectSelected
        case .startManaged: return .buttonStartDSH
        case .restartManaged: return .buttonRestartDSH
        }
    }

    /// Drop the page and terminate any owned child process.
    func detach() {
        runner.stop()
        currentURL = nil
        attachedHostID = nil
        web = WebViewState()
        // A different page (or none) means everything the detector remembers
        // is about a conversation nobody is looking at — and the channel was
        // authorized for a Host this app is no longer attached to.
        stopFeed()
        stopRenewalClock()
        lastPageLoad = nil
        lastRenewal = nil
        summonsActive = false
        portConflict = nil
        isCheckingPort = false
    }

    func reload() {
        reloadToken &+= 1
        // Nothing to reset here: the notification channel reads the Host's
        // API, not the page, so a page reload is not a gap in its facts.
    }

    func apply(_ state: WebViewState) {
        web = state
        // A clean load — initial navigation or a renewal's reload — restarts
        // the renewal clock: the page's age is its age since it last loaded.
        if !state.isLoading, state.problem == nil, currentURL != nil {
            lastPageLoad = Date()
        }
    }

    // MARK: - Notification channel

    /// Bring the Host notification channel in line with what is attached and
    /// what the settings ask for. Idempotent: a channel already on the right
    /// origin stays put, so SwiftUI's re-renders cannot churn the socket.
    private func updateFeed() {
        guard config.notificationsEnabled, let url = currentURL, let origin = Self.origin(of: url) else {
            stopFeed()
            return
        }
        guard feed == nil || feedOrigin != origin else { return }
        stopFeed()
        feedOrigin = origin
        // A fresh channel knows nothing; the first list snapshot is its
        // baseline, and everything before it is state, not news.
        detector.reset()
        let channel = HostFeed(
            cookieProvider: WebKitCredentials.reader(),
            onEvent: { [weak self] in self?.handle($0) },
            onHealth: { [weak self] in self?.feedHealth = $0 }
        )
        channel.start(origin: origin)
        feed = channel
    }

    /// Tear the channel down and forget its baseline.
    private func stopFeed() {
        feed?.stop()
        feed = nil
        feedOrigin = nil
        detector.reset()
        feedHealth = .idle
        // The knowledge of an open summons dies with the channel: a stale
        // "waiting" would block page renewal forever, and the worst case of
        // the opposite — one renewal while the SPA happens to show a panel —
        // is recoverable, since the Host still holds the pending request.
        summonsActive = false
    }

    /// The authority a page URL points at, without its one-time token: the
    /// notification channel authorizes with the cookie the page minted, so
    /// the token is not part of the channel's identity.
    private static func origin(of url: URL) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        return components?.url
    }

    /// Feed facts in, notifications out. The raw summons frames are also the
    /// renewal mechanism's "the Host is blocked on an answer" signal.
    private func handle(_ event: HostFeedEvent) {
        switch event {
        case .summons: summonsActive = true
        case .summonsEnded: summonsActive = false
        case .sessions, .runningChanged, .failed: break
        }
        for notification in detector.advance(event) {
            notify(notification)
        }
    }

    /// The notification as macOS delivers it. The message follows the
    /// interface language; the subtitle names the conversation the event is
    /// about — the Host's own title for the session — so no banner is a bare
    /// "something happened".
    private func notify(_ event: NotificationEvent) {
        switch event {
        case .waitingForUser(let kind, let session):
            let message: Message
            switch kind {
            case .approval: message = .notificationAttentionApproval
            case .question: message = .notificationAttentionQuestion
            case .planReview: message = .notificationAttentionPlan
            }
            // A summons must reach the user in any app state — frontmost,
            // background, minimized — because it blocks the Host until it is
            // answered.
            notifier.deliver(title: text(message), subtitle: session ?? hostName, body: nil, essential: true)
        case .turnFinished(let session):
            // A finish is status, not a summons: while this app is frontmost
            // with its window up, the page is its own notification.
            notifier.deliver(title: text(.notificationTaskFinished), subtitle: session ?? hostName, body: nil, essential: false)
        }
    }

    /// Which connection a notification is about, when the session list could
    /// not name the conversation (a session that has never been prompted has
    /// no title yet).
    private var hostName: String? {
        attachedHost?.displayName(in: localization)
    }

    // MARK: - Page renewal

    /// Whether the renewal mechanism may act at all: it is a setting, and it
    /// needs a page to renew.
    private var renewalArmed: Bool {
        config.pageRenewalEnabled && currentURL != nil
    }

    /// The five-minute heartbeat, plus opportunistic checks whenever a window
    /// changes visibility. Both funnel into `checkPageRenewal`, which is cheap
    /// to refuse and idempotent.
    private func startRenewalClock() {
        guard renewalClock == nil else { return }
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPageRenewal() }
        }
        RunLoop.main.add(timer, forMode: .common)
        renewalClock = timer
    }

    private func stopRenewalClock() {
        renewalClock?.invalidate()
        renewalClock = nil
    }

    /// Gather the facts one renewal decision needs and act on the answer.
    /// Everything the decision reads is main-actor state; the check is cheap
    /// to refuse and idempotent, so the clock and the occlusion observer both
    /// call it as often as they like.
    private func checkPageRenewal() {
        guard renewalArmed else { return }
        let facts = PageRenewal.Facts(
            now: Date(),
            lastLoad: lastPageLoad,
            windowVisible: NSApp.windows.contains { $0.occlusionState.contains(.visible) },
            summonsActive: summonsActive,
            lastRenewal: lastRenewal
        )
        guard PageRenewal.isDue(facts) else { return }
        // Whatever happens after this, the page is about to be brand new:
        // the cooldown and the load clock both restart now, so a renewal can
        // never re-arm itself into a loop.
        lastRenewal = Date()
        lastPageLoad = Date()
        reloadToken &+= 1
    }

    /// The notification channel's state, worded for Settings. `nil` while
    /// nothing is attached: only states worth a line are worded.
    var channelStatus: String? {
        switch feedHealth {
        case .idle, .connecting: nil
        case .healthy: text(.settingsChannelHealthy)
        case .unauthorized: text(.settingsChannelUnauthorized)
        case .reconnecting: text(.settingsChannelReconnecting)
        }
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
        // The port check runs before any launch, so the runner has nothing
        // to say yet; the check itself is what is happening.
        if isCheckingPort { return text(.phaseCheckingPort) }
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
