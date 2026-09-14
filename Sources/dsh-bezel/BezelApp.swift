import Foundation
import SwiftUI
import BezelCore

/// Entry point.
///
/// The smoke flags are answered before `BezelApp` is built: constructing the
/// scene constructs `AppState`, and with it the store that creates the config
/// file. A flag whose whole purpose is to report what is on disk must not be
/// the thing that puts something there.
@main
enum BezelEntryPoint {
    // `main` is async so the watch-feed diagnostic can await the channel on
    // the main actor instead of blocking the main thread on a semaphore —
    // which would deadlock the very actor it is waiting for.
    static func main() async {
        let arguments = CommandLine.arguments
        if arguments.contains("--dump-config") {
            print(ConfigFile(url: ConfigFile.defaultURL()).describe())
            exit(0)
        }
        if arguments.contains("--dump-hosts") {
            print(hostsJSON())
            exit(0)
        }
        if let url = watchFeedURL(from: arguments) {
            // A diagnostic that needs no UI: spend the URL's token the way a
            // first page load would, then attach the notification channel and
            // print every fact it learns. Ctrl-C stops it.
            await HostFeedCLI.run(url: url)
            exit(0)
        }
        mirrorLanguageIntoAppleLanguages()
        BezelApp.main()
    }

    private static func watchFeedURL(from arguments: [String]) -> URL? {
        guard let index = arguments.firstIndex(of: "--watch-feed"),
              arguments.count > index + 1
        else { return nil }
        return URL(string: arguments[index + 1])
    }

    /// The `--watch-feed` body. Lives in the app target because it prints to
    /// stdout and owns no UI; the channel itself is all BezelCore.
    private enum HostFeedCLI {
        @MainActor
        static func run(url: URL) async {
            // Piped or redirected stdout is block-buffered by default, which
            // would sit on every line until the buffer filled.
            setbuf(stdout, nil)
            let jar = HTTPCookieStorage.shared
            // Spend the token, if the URL still carries one: the Host trades
            // it for the signed cookie this session will reuse.
            if url.query?.hasPrefix("token=") == true {
                let configuration = URLSessionConfiguration.default
                configuration.httpCookieStorage = jar
                let session = URLSession(configuration: configuration)
                _ = try? await session.data(for: URLRequest(url: url))
            }
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.query = nil
            components?.fragment = nil
            guard let origin = components?.url else {
                print("watch-feed: unparseable URL")
                return
            }
            print("watching \(origin) — Ctrl-C to stop")
            let feed = HostFeed(
                cookieProvider: { origin in jar.cookies(for: origin) ?? [] },
                onEvent: { event in print("event: \(event)") },
                onHealth: { health in print("health: \(health)") }
            )
            feed.start(origin: origin)
            // The process is stopped with Ctrl-C; this sleep only keeps the
            // async context alive while the feed works.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_600_000_000_000)
            }
        }
    }

    /// The menu bar is rendered by macOS from the bundle's effective
    /// localization, which it derives from `AppleLanguages` — not from this
    /// app's own setting. Mirroring the configured language into that key
    /// before the UI loads makes the system-owned menus (app, Edit, Window,
    /// Help) follow the Settings choice; the in-app text follows on its own.
    /// The config file stays the source of truth: this runs at every launch,
    /// so editing the setting rewrites the key rather than stacking on it.
    private static func mirrorLanguageIntoAppleLanguages() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let file = ConfigFile(url: ConfigFile.defaultURL())
        let language: AppLanguage
        if case .loaded(let config) = file.load() { language = config.language }
        else { language = .fallback }
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
    }

    /// Bookmarks as the config file holds them, pretty-printed.
    private static func hostsJSON() -> String {
        let file = ConfigFile(url: ConfigFile.defaultURL())
        let hosts: [DSHHost]
        if case .loaded(let config) = file.load() { hosts = config.hosts } else { hosts = [] }
        guard let data = try? ConfigFile.encodeJSON(hosts),
              let text = String(data: data, encoding: .utf8)
        else { return "[]" }
        return text
    }
}

struct BezelApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup("DSH Bezel") {
            MainView()
                .environment(app)
        }
        // A thinner title/toolbar bar: the bezel is chrome around the Host's
        // UI, and the unified-height bar spends vertical space on nothing the
        // page below needs. Measured on this OS: default unified 52pt,
        // compact 40pt with controls (the floor for a window that keeps
        // visible standard controls), 32pt title-only.
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView()
                .environment(app)
                .frame(width: 780, height: 480)
        }
    }
}
