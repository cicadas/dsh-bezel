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
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--dump-config") {
            print(ConfigFile(url: ConfigFile.defaultURL()).describe())
            exit(0)
        }
        if arguments.contains("--dump-hosts") {
            print(hostsJSON())
            exit(0)
        }
        mirrorLanguageIntoAppleLanguages()
        BezelApp.main()
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
