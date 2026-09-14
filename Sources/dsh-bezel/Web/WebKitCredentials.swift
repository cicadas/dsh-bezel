import Foundation
import WebKit
import BezelCore

/// The Web page's credential, read for the notification channel.
///
/// The Host API authorizes with the same signed `dsh-auth-*` cookie the Web
/// page mints, and that cookie lives in this app's WebKit data store — the
/// one place both the page and the feed can reach. Reading it here is the
/// whole bridge between the two: the page keeps minting and owning the
/// credential, the feed just presents it.
///
/// BezelCore itself stays framework-free, so this reader is handed to
/// `HostFeed` as a closure rather than imported there.
enum WebKitCredentials {
    /// A reader that returns the cookies the displayed page's store holds.
    /// All of them: the feed matches them against its origin by authority
    /// itself, so rotation of the cookie's name (it carries an authority
    /// hash) needs no change here.
    static func reader() -> HostFeed.CookieProvider {
        // The store is read where WebKit wants its object touched (the main
        // actor); the answer arrives on WebKit's own queue and is resumed
        // from there.
        let store = WKWebsiteDataStore.default()
        return { _ in
            let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
                Task { @MainActor in
                    store.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
                }
            }
            return cookies
        }
    }
}
