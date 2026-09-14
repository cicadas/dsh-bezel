import Foundation

/// When the displayed page should be renewed — reloaded — by the app itself.
///
/// A WebKit content process sheds nothing on its own: a page left up for
/// days accumulates renderer memory the Host's SPA never reclaims, however
/// well the page behaves. The display is also now the only thing that
/// degrades with age — the notification channel reads the Host's API, so a
/// reload costs nothing but a blink: the feed keeps running through it, and
/// the page reattaches to the same Host.
///
/// Every rule lives here as a pure function of explicit facts, so the
/// behaviour is testable and the caller merely gathers facts:
///
/// - **One day per load.** The interval is the whole trigger: a page that
///   has been up for a day is renewed the first time the rest of the rules
///   allow it.
/// - **Never while the Host is blocked on an answer.** Whether the SPA
///   replays a pending summons after a reload is the page's business, not
///   something this app can promise — an open approval or question outranks
///   the housekeeping.
/// - **Only while no window is visible.** A reload discards page state, and
///   an unsent composer draft is the one thing the page holds that cannot be
///   reconstructed. Hidden or minimized only — the user asked for the
///   renewal to happen in the background, and this is what "background"
///   means without touching the page.
/// - **At most one renewal per hour.** A freshly loaded page has nothing to
///   shed, and a monitor must not oscillate; it also means a renewal that
///   had to wait for the user to hide the window fires within moments of
///   that, and then stays quiet.
public enum PageRenewal {
    /// How long one load of the page may live before it is renewed.
    public static let interval: TimeInterval = 24 * 3600
    /// How long after a renewal no renewal may fire again.
    public static let cooldown: TimeInterval = 3600

    /// The facts one decision needs. `lastLoad` being `nil` means nothing
    /// has ever finished loading, so there is nothing to renew.
    public struct Facts {
        public var now: Date
        public var lastLoad: Date?
        /// Whether any window of this app is visible on screen right now.
        public var windowVisible: Bool
        /// Whether the Host is waiting for the user's answer (an approval, a
        /// question, a plan review).
        public var summonsActive: Bool
        /// When this mechanism last renewed the page.
        public var lastRenewal: Date?

        public init(
            now: Date,
            lastLoad: Date?,
            windowVisible: Bool,
            summonsActive: Bool,
            lastRenewal: Date?
        ) {
            self.now = now
            self.lastLoad = lastLoad
            self.windowVisible = windowVisible
            self.summonsActive = summonsActive
            self.lastRenewal = lastRenewal
        }
    }

    /// Whether the page is due for renewal given these facts.
    public static func isDue(_ facts: Facts) -> Bool {
        guard !facts.summonsActive else { return false }
        guard !facts.windowVisible else { return false }
        if let renewed = facts.lastRenewal, facts.now.timeIntervalSince(renewed) < cooldown {
            return false
        }
        guard let loaded = facts.lastLoad else { return false }
        return facts.now.timeIntervalSince(loaded) >= interval
    }
}
