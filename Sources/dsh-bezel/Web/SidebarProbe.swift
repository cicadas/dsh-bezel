import Foundation
import WebKit
import BezelCore

/// The complete sidebar, read from a page nobody is looking at.
///
/// The displayed page's sidebar only renders what its own view state shows:
/// a collapsed workspace group renders no session rows, and an expanded one
/// caps at its five most recent. A background conversation that finishes or
/// starts waiting while hidden there is invisible to the displayed page —
/// and to every notification drawn from it.
///
/// This probe is the answer: a second `WKWebView` that loads the same Host
/// page and is never shown to anyone. Its data store is separate and
/// non-persistent, so its clicks (expanding groups, opening overflows)
/// write to a view state of its own — the user's sidebar is untouched. Its
/// empty store also means it restores no selection: it opens no
/// conversation, creates nothing, and selects nothing, which in turn means
/// the Host's per-client completion dots arm for every session without the
/// probe ever clearing one.
///
/// Authorization rides on the credential the displayed page already minted:
/// its cookie is copied from the shared store into the probe's own before
/// the first load. The address is loaded without its token query — the
/// token is single-use in spirit, and re-spending it could rotate the
/// displayed page's cookie out from under it.
@MainActor
final class SidebarProbe: NSObject, WKScriptMessageHandler {
    /// Rows are considered current for this long after a post; past it, the
    /// caller falls back to the displayed page's own (partial) sidebar
    /// rather than act on rows that may no longer exist.
    private static let freshness: TimeInterval = 15
    /// A page that has gone quiet for this long gets reloaded — the Host
    /// restarted, the cookie rotated, the load failed. Rate-limited so a
    /// Host that is genuinely down is retried at most once per window.
    private static let staleReloadAfter: TimeInterval = 30

    private var webView: WKWebView?
    private var address: URL?
    private var rows: [SidebarSession] = []
    private var lastPost: Date?
    private var startedAt: Date?
    private var lastReloadAttempt: Date?

    /// The complete sidebar, when the probe page is alive and posting.
    var freshSidebar: [SidebarSession]? {
        guard let lastPost, Date().timeIntervalSince(lastPost) <= Self.freshness else { return nil }
        return rows
    }

    /// Load the Host page and start posting its sidebar. Safe to call only
    /// once; the caller owns the lifecycle and creates a fresh probe per
    /// connection.
    func start(url: URL) {
        guard webView == nil else { return }
        address = url
        startedAt = Date()

        let store = WKWebsiteDataStore.nonPersistent()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: PageSnapshot.probeScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true,
                in: .page
            )
        )
        configuration.userContentController.add(
            self,
            contentWorld: .page,
            name: PageSnapshot.probeHandlerName
        )
        // A real frame, though the view is never shown or added to a
        // window: the page must lay out as the desktop app it is, not as a
        // zero-width sliver, or the sidebar could render a different
        // breakpoint than the one the user sees.
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 800), configuration: configuration)
        self.webView = webView
        load(with: store)
    }

    /// Tear the page down and forget its rows.
    func stop() {
        if let webView {
            webView.configuration.userContentController.removeAllUserScripts()
            webView.configuration.userContentController.removeScriptMessageHandler(
                forName: PageSnapshot.probeHandlerName
            )
            webView.stopLoading()
        }
        webView = nil
        address = nil
        rows = []
        lastPost = nil
        startedAt = nil
        lastReloadAttempt = nil
    }

    /// Reload a page that has gone quiet. Called from the snapshot path —
    /// once per displayed-page poll — so the check costs nothing on its own.
    func reloadIfStale() {
        guard let webView, let startedAt else { return }
        let now = Date()
        let age = now.timeIntervalSince(startedAt)
        // A first post has never arrived: give the page time to load before
        // judging it (the Host app is not a small page).
        let last = lastPost ?? startedAt
        guard age > Self.staleReloadAfter,
              now.timeIntervalSince(last) > Self.staleReloadAfter,
              lastReloadAttempt.map({ now.timeIntervalSince($0) }) ?? .infinity > Self.staleReloadAfter
        else { return }
        lastReloadAttempt = now
        load(with: webView.configuration.websiteDataStore)
    }

    // MARK: - Loading

    /// Copy the displayed page's credential into this probe's store, then
    /// load the address without its token query.
    private func load(with store: WKWebsiteDataStore) {
        guard let address else { return }
        // The query carries the one-time token; spending it again could
        // rotate the shared cookie. The copied cookie is the credential.
        guard var components = URLComponents(url: address, resolvingAgainstBaseURL: false),
              let clean = ({ components.query = nil; components.fragment = nil; return components.url })()
        else { return }

        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            let host = address.host ?? ""
            let matching = cookies.filter { cookie in
                let domain = cookie.domain.hasPrefix(".")
                    ? String(cookie.domain.dropFirst())
                    : cookie.domain
                return host == domain || host.hasSuffix("." + domain)
            }
            let group = DispatchGroup()
            for cookie in matching {
                group.enter()
                store.httpCookieStore.setCookie(cookie) { group.leave() }
            }
            group.notify(queue: .main) { [weak self] in
                self?.webView?.load(URLRequest(url: clean))
            }
        }
    }

    // MARK: - WKScriptMessageHandler

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let snapshot = PageSnapshot.fromScriptMessage(body)
        else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.rows = snapshot.sidebar
                self.lastPost = Date()
            }
        }
    }
}
