import Foundation
import Observation

/// The one owner of `AppConfig`: loads it, changes it, writes it back.
///
/// Every mutation funnels through `persist()`, so the file on disk is never
/// more than one edit behind and there is no second writer to lose fields to.
@MainActor
@Observable
public final class ConfigStore {
    /// Where the configuration lives, so the UI can show it.
    public let url: URL

    /// The file is there but cannot be parsed. The store carries on with the
    /// default Host and leaves the file alone, so a hand edit that needs a typo
    /// fixed — or a file written by a newer build — stays recoverable.
    public private(set) var dataUnreadable = false
    /// Why it could not be parsed, for the warning in Settings.
    public private(set) var unreadableReason: String?
    /// Set when the last write failed: full disk, read-only home, permissions.
    public private(set) var writeError: String?
    /// The file was written by a newer build than this one.
    ///
    /// It is read and used — that is the point of tolerant decoding — but
    /// never written back, because this build cannot promise to preserve what
    /// it does not know about. Settings says so, and changes made in this
    /// session simply do not persist.
    public private(set) var fileFromNewerBuild = false
    /// The version the file declares, for the warning in Settings.
    public private(set) var fileVersion: Int?

    /// Holding the whole value — rather than one property per setting — is what
    /// keeps a single write path honest, and it is observed as a unit so any
    /// change here redraws whatever reads it.
    private var config: AppConfig

    @ObservationIgnored private let file: ConfigFile

    public init(file: ConfigFile = ConfigFile(url: ConfigFile.defaultURL())) {
        self.file = file
        self.url = file.url

        var needsWrite = false
        switch file.load() {
        case .loaded(let loaded):
            config = loaded
            fileVersion = loaded.version
            fileFromNewerBuild = loaded.isFromANewerBuild
        case .unreadable(let reason):
            config = AppConfig()
            dataUnreadable = true
            unreadableReason = reason
        case .missing:
            // A fresh install: seed it and write the file straight away, so
            // the location is real from the first launch — and a reset is
            // simply "delete the file", with nothing remembered anywhere else.
            config = AppConfig()
            // No file at all is the one honest signal of a first launch, and
            // this branch is the only place that knows it: everything else
            // that builds an `AppConfig` — including the decoder for a file
            // written before the field existed — means "past the guide".
            config.onboardingCompleted = false
            needsWrite = true
        }

        if ConfigStore.repair(&config) { needsWrite = true }
        if needsWrite { persist() }
    }

    /// Make the value self-consistent, reporting whether anything changed.
    ///
    /// A fresh install, and one whose last bookmark was removed, get the
    /// default Host: without one the app has nothing to offer. References to
    /// bookmarks that no longer exist are dropped rather than left dangling.
    private static func repair(_ config: inout AppConfig) -> Bool {
        var changed = false

        if config.hosts.isEmpty {
            config.hosts = [DSHHost(
                name: Localization(language: config.language).text(.seedHostName),
                baseURL: "http://127.0.0.1:3080",
                managed: true
            )]
            changed = true
        }
        // A selection that no longer names an existing bookmark is replaced by
        // the first one; there is always at least one after the branch above.
        if config.selectedHostID == nil || !config.hosts.contains(where: { $0.id == config.selectedHostID }) {
            config.selectedHostID = config.hosts.first?.id
            changed = true
        }
        if let last = config.lastConnectedHostID, !config.hosts.contains(where: { $0.id == last }) {
            config.lastConnectedHostID = nil
            changed = true
        }
        return changed
    }

    // MARK: - Reading

    public var hosts: [DSHHost] { config.hosts }
    public var selectedHostID: UUID? { config.selectedHostID }
    public var lastConnectedHostID: UUID? { config.lastConnectedHostID }
    public var language: AppLanguage { config.language }
    public var notificationsEnabled: Bool { config.notificationsEnabled }
    /// Whether the first-launch guide is still due — a fresh install, or one
    /// whose guide was never finished.
    public var onboardingCompleted: Bool { config.onboardingCompleted }

    public var selectedHost: DSHHost? { host(id: config.selectedHostID) }

    public func host(id: UUID?) -> DSHHost? {
        guard let id else { return nil }
        return config.hosts.first { $0.id == id }
    }

    // MARK: - Writing

    public func select(id: UUID?) {
        guard config.selectedHostID != id else { return }
        config.selectedHostID = id
        persist()
    }

    /// Remember the Host the WebView actually attached to.
    ///
    /// Kept apart from the picker's choice so a launch can reconnect to what
    /// was really in use, whatever the picker was left showing.
    public func noteConnected(id: UUID?) {
        guard config.lastConnectedHostID != id else { return }
        config.lastConnectedHostID = id
        persist()
    }

    public func setLanguage(_ language: AppLanguage) {
        guard config.language != language else { return }
        config.language = language
        persist()
    }

    public func setNotificationsEnabled(_ enabled: Bool) {
        guard config.notificationsEnabled != enabled else { return }
        config.notificationsEnabled = enabled
        persist()
    }

    /// The first-launch guide is over (connected, or skipped): it must not
    /// come back on the next launch uninvited.
    public func completeOnboarding() {
        guard !config.onboardingCompleted else { return }
        config.onboardingCompleted = true
        persist()
    }

    /// Append a given bookmark without selecting it, and return it.
    ///
    /// Unlike `add()` this creates nothing and moves nothing: the caller —
    /// typically the guide, which connects straight away — decides what the
    /// picker should land on.
    @discardableResult
    public func add(_ host: DSHHost) -> DSHHost {
        config.hosts.append(host)
        persist()
        return host
    }

    /// Append a blank bookmark, select it, and return it.
    ///
    /// Named in the language the app is currently in; the user can rename it.
    @discardableResult
    public func add() -> DSHHost {
        let host = DSHHost(
            name: Localization(language: config.language).text(.newHostName),
            baseURL: "http://127.0.0.1:3080"
        )
        config.hosts.append(host)
        config.selectedHostID = host.id
        persist()
        return host
    }

    public func update(_ host: DSHHost) {
        guard let index = config.hosts.firstIndex(where: { $0.id == host.id }),
              config.hosts[index] != host else { return }
        config.hosts[index] = host
        persist()
    }

    public func remove(id: UUID) {
        guard config.hosts.contains(where: { $0.id == id }) else { return }
        config.hosts.removeAll { $0.id == id }
        if config.selectedHostID == id { config.selectedHostID = config.hosts.first?.id }
        if config.lastConnectedHostID == id { config.lastConnectedHostID = nil }
        persist()
    }

    private func persist() {
        // Never write over a file this build could not read: it may hold
        // bookmarks that a typo fix, or a newer build, can still recover.
        guard !dataUnreadable else { return }
        // Nor over one from a newer build. Reading it is right — the user
        // should see their Hosts — but rewriting it would replace fields this
        // build has never heard of with its own idea of the file, while
        // leaving the newer version number in place.
        guard !fileFromNewerBuild else { return }
        do {
            try file.save(config)
            writeError = nil
        } catch {
            writeError = error.localizedDescription
        }
    }
}
