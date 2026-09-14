import AppKit
import SwiftUI
import WebKit
import BezelCore

/// Navigation facts reported by the embedded WebView.
struct WebViewState: Equatable {
    /// Something worth showing the user.
    ///
    /// Only the system's own error text is carried as a string: WebKit has
    /// already localized it, and it is not ours to re-translate. Everything
    /// this app words itself stays a case, so the banner follows a language
    /// change like the rest of the interface.
    enum Problem: Equatable {
        /// WebKit's own description of a failed navigation.
        case system(String)
        /// The bookmark's address could not be parsed into an origin.
        case invalidAddress(String)
        /// The Host answered 401: unknown token and no usable cookie.
        case credentialRejected
    }

    var isLoading = false
    var title: String?
    var problem: Problem?
}

/// Hosts one dsh Host's own Web UI inside a `WKWebView`.
///
/// Purely a display: nothing is injected into the page, nothing is read back
/// from it, and its view state is the page's own business. Notifications are
/// served by the Host API channel (`HostFeed`), which never touches this
/// view.
struct WebView: NSViewRepresentable {
    /// URL to display; `nil` shows nothing.
    let url: URL?
    /// Bump to reload the page currently displayed.
    let reloadToken: Int
    /// Delivered on the main queue after each navigation change.
    let onState: (WebViewState) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onState: onState) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // The signed browser cookie must outlive the Host process that minted
        // it, so the persistent store is required; an ephemeral store would
        // drop the 30-day credential on quit.
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        // Without a uiDelegate WebKit silently drops every new-window request,
        // so the Host's `target="_blank"` links — markdown links and URL cards
        // render them — were simply dead clicks.
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.attach(webView)
        context.coordinator.apply(url: url, reloadToken: reloadToken)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onState = onState
        context.coordinator.apply(url: url, reloadToken: reloadToken)
    }

    /// Drives one WebView and forwards its navigation state to SwiftUI.
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var onState: (WebViewState) -> Void
        private weak var webView: WKWebView?
        private var loadedURL: URL?
        private var appliedReloadToken = -1
        private var state = WebViewState()
        /// Whether the navigation in flight was answered 401 on the main frame.
        ///
        /// `decidePolicyFor` runs before `didFinish`, and a rejected page still
        /// "finishes" loading — with the Host's rejection body — so the problem
        /// has to be recorded here and reasserted in `didFinish`. Clearing it
        /// unconditionally there wiped the banner before any publish could show it.
        private var authRejected = false

        init(onState: @escaping (WebViewState) -> Void) {
            self.onState = onState
        }

        func attach(_ webView: WKWebView) {
            self.webView = webView
        }

        /// Load `url`, or reload when only the reload counter moved.
        func apply(url: URL?, reloadToken: Int) {
            guard let webView, let url else { return }
            if loadedURL != url {
                loadedURL = url
                appliedReloadToken = reloadToken
                state = WebViewState(isLoading: true)
                authRejected = false
                publish()
                webView.load(URLRequest(url: url))
                return
            }
            guard reloadToken != appliedReloadToken else { return }
            appliedReloadToken = reloadToken
            state.isLoading = true
            state.problem = nil
            authRejected = false
            publish()
            webView.reload()
        }

        private func publish() {
            let snapshot = state
            // Navigation callbacks can arrive inside a SwiftUI update; defer so
            // reporting never mutates observed state mid-render.
            DispatchQueue.main.async { [weak self] in self?.onState(snapshot) }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            state.isLoading = true
            state.problem = nil
            authRejected = false
            publish()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            state.isLoading = false
            state.title = webView.title
            // A 401 page finishes loading too, with the Host's rejection body;
            // only a page that was not rejected counts as clean.
            state.problem = authRejected ? .credentialRejected : nil
            publish()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            report(error)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            if navigationResponse.isForMainFrame,
               let http = navigationResponse.response as? HTTPURLResponse,
               http.statusCode == 401 {
                // Only the main frame rejecting counts: a 401 from some
                // embedded resource is not the Host refusing this client.
                authRejected = true
                state.problem = .credentialRejected
            }
            decisionHandler(.allow)
        }

        /// This app hosts exactly one page: a request for a new window —
        /// `target="_blank"`, `window.open` — is an external link at heart,
        /// and the system browser is where the user expects to read it.
        /// Returning `nil` keeps the WebView itself single-page.
        ///
        /// Only `http`/`https` are handed to the system. A page-driven
        /// new-window request is not a reason to launch a helper for some
        /// other scheme, and the Host renders external links as plain web
        /// URLs anyway.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil,
               let url = navigationAction.request.url,
               url.scheme == "http" || url.scheme == "https" {
                NSWorkspace.shared.open(url)
            }
            return nil
        }

        private func report(_ error: Error) {
            let nsError = error as NSError
            // -999 is WebKit's cancellation, raised whenever a load supersedes another.
            guard nsError.code != NSURLErrorCancelled else { return }
            state.isLoading = false
            state.problem = .system(nsError.localizedDescription)
            authRejected = false
            publish()
        }
    }
}
