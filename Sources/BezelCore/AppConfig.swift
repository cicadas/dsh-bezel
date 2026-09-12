import Foundation

/// Everything the app remembers between launches.
///
/// One value, one file: the bookmarks, which Host the picker is on, which Host
/// the WebView was last attached to, and the interface language. Keeping them
/// together is what makes a single write path possible — two independent stores
/// sharing one file would each rewrite the other's fields away.
public struct AppConfig: Equatable, Sendable {
    /// Marks the shape of the file. Readers deliberately do not refuse a higher
    /// number: an older build should show what it can parse rather than treat
    /// the whole file as corrupt.
    public static let currentVersion = 1

    public var version: Int
    public var language: AppLanguage
    public var hosts: [DSHHost]
    /// Host highlighted in the picker.
    public var selectedHostID: UUID?
    /// Host the WebView was attached to when the app was last used. This is
    /// what a fresh launch reconnects to.
    public var lastConnectedHostID: UUID?
    /// Whether page events may become macOS notifications.
    public var notificationsEnabled: Bool
    /// Whether the first-launch guide has been finished (or skipped).
    ///
    /// The default is `true` and the *decoder's* default for a file that
    /// predates the field is `true` too: a bookmark file written by an older
    /// build belongs to someone who is long past their first launch, and the
    /// guide must not ambush them on upgrade. Only a fresh install — no file
    /// at all — starts out `false`, and only the store's `.missing` branch
    /// knows that.
    public var onboardingCompleted: Bool

    /// Top-level keys this build has no field for, carried through untouched.
    ///
    /// This is what makes "a file from a newer build still loads" true of
    /// *writing* as well as reading. Reading tolerated the unknown keys but
    /// dropped them, so the first ordinary save — changing the language,
    /// picking a Host — wrote the file back without them while leaving
    /// `version` at the newer number: a file that still claimed to be new,
    /// with the new part quietly gone.
    public var unknownFields: [String: JSONValue]

    public init(
        version: Int = AppConfig.currentVersion,
        language: AppLanguage = .fallback,
        hosts: [DSHHost] = [],
        selectedHostID: UUID? = nil,
        lastConnectedHostID: UUID? = nil,
        notificationsEnabled: Bool = true,
        onboardingCompleted: Bool = true,
        unknownFields: [String: JSONValue] = [:]
    ) {
        self.version = version
        self.language = language
        self.hosts = hosts
        self.selectedHostID = selectedHostID
        self.lastConnectedHostID = lastConnectedHostID
        self.notificationsEnabled = notificationsEnabled
        self.onboardingCompleted = onboardingCompleted
        self.unknownFields = unknownFields
    }

    /// Whether the file was written by a build newer than this one.
    ///
    /// The store uses it to decide it may read but must not write: a rewrite
    /// would be this build's understanding of a file it only partly
    /// understands.
    public var isFromANewerBuild: Bool { version > AppConfig.currentVersion }
}

extension AppConfig: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, language, hosts, selectedHostID, lastConnectedHostID, notificationsEnabled, onboardingCompleted
    }

    /// Decoded field by field, like `DSHHost`.
    ///
    /// The asymmetry is deliberate. A scalar this build cannot read is not
    /// worth failing over — the default is used and the rest of the file still
    /// loads. `hosts` is decoded strictly, because losing bookmarks silently is
    /// the one outcome worth refusing to write for: a failure there makes the
    /// whole file "unreadable", which the store reports and never overwrites.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? container.decode(Int.self, forKey: .version)) ?? AppConfig.currentVersion
        language = (try? container.decode(AppLanguage.self, forKey: .language)) ?? .fallback
        hosts = try container.decodeIfPresent([DSHHost].self, forKey: .hosts) ?? []
        selectedHostID = try? container.decode(UUID.self, forKey: .selectedHostID)
        lastConnectedHostID = try? container.decode(UUID.self, forKey: .lastConnectedHostID)
        notificationsEnabled = (try? container.decode(Bool.self, forKey: .notificationsEnabled)) ?? true
        // Absent means the file predates the guide, and such a user has
        // already set the app up — see the property's documentation.
        onboardingCompleted = (try? container.decode(Bool.self, forKey: .onboardingCompleted)) ?? true
        unknownFields = try AppConfig.decodeUnknownFields(from: decoder)
    }

    /// Every top-level key that is not one of this build's own, kept verbatim.
    private static func decodeUnknownFields(from decoder: any Decoder) throws -> [String: JSONValue] {
        let known = Set(CodingKeys.allCases.map(\.stringValue))
        let container = try decoder.container(keyedBy: JSONCodingKey.self)
        var unknown: [String: JSONValue] = [:]
        for key in container.allKeys where !known.contains(key.stringValue) {
            unknown[key.stringValue] = try? container.decode(JSONValue.self, forKey: key)
        }
        return unknown
    }

    /// Encoded field by field so the carried-through keys can be written back
    /// beside them. This build's own fields win a name collision: they are the
    /// ones it actually edited.
    public func encode(to encoder: any Encoder) throws {
        var unknownContainer = encoder.container(keyedBy: JSONCodingKey.self)
        let known = Set(CodingKeys.allCases.map(\.stringValue))
        for (key, value) in unknownFields where !known.contains(key) {
            try unknownContainer.encode(value, forKey: JSONCodingKey(key))
        }

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(language, forKey: .language)
        try container.encode(hosts, forKey: .hosts)
        try container.encodeIfPresent(selectedHostID, forKey: .selectedHostID)
        try container.encodeIfPresent(lastConnectedHostID, forKey: .lastConnectedHostID)
        try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try container.encode(onboardingCompleted, forKey: .onboardingCompleted)
    }
}
