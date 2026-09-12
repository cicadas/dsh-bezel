import AppKit
import UserNotifications

/// Delivers page events as macOS notifications.
///
/// Deliberately dumb: it takes already-translated text and posts it. What to
/// say, and in which language, is decided by `AppState`, which follows the
/// interface language; this type only knows about UserNotifications.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter?

    override init() {
        // The bare `swift run` executable has no bundle identifier, and
        // UserNotifications refuses to work outside an app bundle. Degrade to
        // "no notifications" rather than crash — the README already says the
        // bundle is the real target.
        center = Bundle.main.bundleIdentifier == nil ? nil : .current()
        super.init()
        center?.delegate = self
    }

    /// Ask once, at launch or when the setting turns on. The system remembers
    /// the answer; repeated calls only report the recorded decision.
    func requestAuthorizationIfNeeded() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Post one notification.
    ///
    /// Two classes of event, two courtesies. A summons — the Host waiting on
    /// input or confirmation — is always delivered: frontmost, background,
    /// or minimized. Being frontmost with the page up does not make a
    /// summons redundant, because not every summons is on that page: a
    /// background session waiting for its answer shows nothing there, and a
    /// missed summons stalls the session silently. A status event (a
    /// finish) keeps the older courtesy: while the app is frontmost with
    /// its window up, the page is its own notification, and the banner
    /// would only repeat what is already on screen. No window at all
    /// cannot be "looking at the page"; err toward delivering.
    func deliver(title: String, subtitle: String?, body: String?, essential: Bool) {
        guard let center else { return }
        if !essential {
            let window = NSApp.windows.first(where: { $0.canBecomeMain })
            let pageVisible = NSApp.isActive && (window?.isMiniaturized == false)
            guard !pageVisible else { return }
        }
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle { content.subtitle = subtitle }
        if let body { content.body = body }
        content.sound = .default
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Clicking the notification is the user saying "I'll handle it": bring
    /// the window forward so the page waiting for them is one glance away.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    /// A notification delivered in the instant the app becomes active still
    /// deserves its banner.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
