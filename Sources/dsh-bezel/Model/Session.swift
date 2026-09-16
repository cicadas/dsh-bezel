import AppKit
import Foundation
import Observation
import BezelCore

/// One tab: a single connection to one dsh Host, kept alive alongside the
/// other tabs' connections.
///
/// Everything that used to describe "the connection" now lives here, once per
/// tab — the attached Host, the WebView's URL and state, the optional managed
/// child process, the notification channel, and the page-renewal housekeeping.
/// What stays shared lives on `AppState`: the bookmarks, the language, the
/// notification permission, and the choice of which tab is selected.
@MainActor
@Observable
final class Session: Identifiable {
    let id = UUID()

    /// Shared bookmarks and settings; read, not owned.
    let config: ConfigStore
    /// Shared notification poster; read, not owned.
    let notifier: Notifier

    /// Host the displayed page belongs to; `nil` while this tab is blank.
    private(set) var hostID: UUID?
    /// URL the WebView is asked to display; `nil` shows the connect prompt.
    private(set) var currentURL: URL?
    /// Latest navigation state reported by the WebView.
    private(set) var web = WebViewState()
    /// Bumped to ask the WebView for a reload.
    private(set) var reloadToken = 0

    /// The optional local dsh child this tab owns, when its Host is managed.
    let runner = LocalHostRunner()

    /// Turns Host feed facts into the transitions worth notifying about.
    /// Ignored by Observation: it is machinery, not state a view renders.
    @ObservationIgnored private var detector = SessionEventDetector()
    /// The notification channel to this tab's Host: the Host's own session
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

    init(config: ConfigStore, notifier: Notifier) {
        self.config = config
        self.notifier = notifier
    }

    // MARK: - Wording

    /// The current language as a value to hand to code outside the UI.
    var localization: Localization { Localization(language: config.language) }

    /// Wording for this app's own text, in the current language.
    func text(_ message: Message, _ arguments: String...) -> String {
        localization.text(message, arguments)
    }

    // MARK: - Connection

    var attachedHost: DSHHost? { config.host(id: hostID) }

    /// The tab's label: the Host it is bound to, or the "new tab" placeholder.
    var title: String {
        if let host = attachedHost { return host.displayName(in: localization) }
        return text(.tabNewTab)
    }

    /// Whether the tab should show a spinner: the page is loading, or the
    /// Host is attached but has not produced a URL yet (a managed boot).
    var isLoading: Bool {
        web.isLoading || (hostID != nil && currentURL == nil)
    }

    /// URL for the system browser; carries the token so a fresh browser
    /// session can mint its own cookie.
    var browserURL: URL? { attachedHost?.loadURL ?? currentURL }

    /// Attach the WebView to `host`, starting a local child when it is
    /// managed. The caller (`AppState`) has already picked which tab this
    /// connection lands in; the bookmark selection and "last connected"
    /// memory are global and updated here because the config store is shared.
    func attach(to host: DSHHost) {
        config.select(id: host.id)
        detach()
        guard host.isValid else {
            web = WebViewState(problem: .invalidAddress(host.baseURL))
            return
        }
        hostID = host.id
        web = WebViewState(isLoading: true)
        // Remember the attachment itself, not just the picker: this is what
        // the next launch reconnects to.
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
                guard let self, self.hostID == host.id, self.runner.hostID == host.id else { return }
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
        guard self.hostID == hostID, currentURL == nil, let host = config.host(id: hostID) else { return }
        if occupied.isEmpty {
            runner.start(host: host) { [weak self] url in
                guard let self, self.hostID == hostID, self.runner.hostID == hostID else { return }
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
        hostID = host.id
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

    /// Drop the page and terminate any owned child process, leaving the tab
    /// blank (its connect prompt).
    func detach() {
        runner.stop()
        currentURL = nil
        hostID = nil
        web = WebViewState()
        // A different page (or none) means everything the detector remembers
        // is about a conversation nobody is looking at — and the channel was
        // authorized for a Host this tab is no longer attached to.
        stopFeed()
        stopRenewalClock()
        lastPageLoad = nil
        lastRenewal = nil
        summonsActive = false
        portConflict = nil
        isCheckingPort = false
        // The WebView goes away with the page; a pending find directive must
        // not survive to open a bar over whatever this tab attaches to next.
        findCommand = nil
    }

    /// Tear down every live resource, for app termination.
    func shutdown() {
        runner.stop()
        stopFeed()
        stopRenewalClock()
    }

    func reload() {
        reloadToken &+= 1
        // Nothing to reset here: the notification channel reads the Host's
        // API, not the page, so a page reload is not a gap in its facts.
    }

    // MARK: - Find in page

    /// Latest find directive for this tab's WebView. Observed: MainView hands
    /// it to the representable, whose coordinator applies it when the token
    /// moves. Reset on detach so a stale directive can never act on the next
    /// page this tab connects to.
    private(set) var findCommand: PageFindCommand?
    @ObservationIgnored private var findToken = 0

    /// The match-count line for the find bar, worded in the current language.
    /// Only a live search with matches shows a count; "no matches" stays
    /// silent, the way Safari's bar does — the public search machinery offers
    /// no way to tell an empty query from a fruitless one.
    var findCountText: String? {
        guard web.findBarVisible, let count = web.findMatchCount, count > 0 else { return nil }
        return text(.findMatchesFound, String(count))
    }

    func sendFind(_ action: PageFindCommand.Action) {
        findToken &+= 1
        findCommand = PageFindCommand(token: findToken, action: action)
    }

    func apply(_ state: WebViewState) {
        web = state
        // A clean load — initial navigation or a renewal's reload — restarts
        // the renewal clock: the page's age is its age since it last loaded.
        if !state.isLoading, state.problem == nil, currentURL != nil {
            lastPageLoad = Date()
        }
    }

    func openInBrowser() {
        guard let url = browserURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Notification channel

    /// Bring the Host notification channel in line with what is attached and
    /// what the settings ask for. Idempotent: a channel already on the right
    /// origin stays put, so SwiftUI's re-renders cannot churn the socket.
    func updateFeed() {
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
    func stopFeed() {
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
    func checkPageRenewal() {
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

    /// One line describing the connection for the toolbar and the connect
    /// prompt.
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
