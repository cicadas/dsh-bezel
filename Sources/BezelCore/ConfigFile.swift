import Foundation

/// The JSON file holding `AppConfig`, and the only place it is read or written.
///
/// A file rather than `UserDefaults`: the point is that the user can read it,
/// edit it, copy it to another machine and keep it in version control. It also
/// steps around `cfprefsd`, whose caching is what made the defaults-backed
/// store hand back stale bookmarks during this project's own repairs.
public struct ConfigFile: Sendable {
    /// Overrides the location. Tests use it to stay off the real file, and a
    /// portable install can point it at a directory of its own.
    public static let environmentVariable = "BEZEL_CONFIG"

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `~/Library/Application Support/dsh-bezel/config.json`, unless
    /// `BEZEL_CONFIG` names somewhere else.
    public static func defaultURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory()
    ) -> URL {
        let override = environment[environmentVariable]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let override, !override.isEmpty {
            return URL(fileURLWithPath: ConfigFile.expandingTilde(in: override, home: home))
        }
        return URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/dsh-bezel", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    /// Expands a leading `~` against the given home rather than the process's,
    /// so the location is decided by one value instead of two.
    static func expandingTilde(in path: String, home: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        return home + path.dropFirst()
    }

    public enum LoadOutcome: Equatable, Sendable {
        /// No file yet: a fresh install, or one that has never been written.
        case missing
        case loaded(AppConfig)
        /// A file is there but cannot be read or parsed. Callers must not write
        /// over it: it may be a hand edit that needs a typo fixed, or a file
        /// from a newer build.
        case unreadable(reason: String)
    }

    public func load() -> LoadOutcome {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // "Cannot read" is not "not there": a permissions problem must not
            // look like a fresh install, or the next write would replace a file
            // the user still has.
            let exists = FileManager.default.fileExists(atPath: url.path)
            return exists
                ? .unreadable(reason: error.localizedDescription)
                : .missing
        }
        do {
            return .loaded(try JSONDecoder().decode(AppConfig.self, from: data))
        } catch {
            return .unreadable(reason: ConfigFile.describe(error))
        }
    }

    /// Write the whole configuration.
    ///
    /// Written atomically through a temporary file, so a crash mid-write leaves
    /// the previous file intact rather than a truncated one. The temporary is
    /// owner-only from its first byte — not fixed up afterwards — because the
    /// file can hold a Host's launch token.
    public func save(_ config: AppConfig) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(
            atPath: temporary.path,
            contents: try encode(config),
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: temporary.path])
        }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        // replaceItemAt keeps the original's attributes; whatever the file's
        // history, the result holds a token and ends up owner-only.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// The configuration as the text this file holds.
    public func encode(_ config: AppConfig) throws -> Data {
        try ConfigFile.encodeJSON(config)
    }

    /// JSON in the shape this file uses: stable key order and unescaped
    /// slashes, because the file is meant to be read and diffed by a human.
    public static func encodeJSON(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    /// A one-line description of what is at `url`, for the `--dump-config`
    /// smoke path.
    public func describe() -> String {
        switch load() {
        case .missing:
            return "no config file at \(url.path)"
        case .unreadable(let reason):
            return "config file at \(url.path) cannot be read: \(reason)"
        case .loaded(let config):
            guard let data = try? encode(config), let text = String(data: data, encoding: .utf8) else {
                return "config file at \(url.path) loaded but could not be re-encoded"
            }
            return text
        }
    }

    static func describe(_ error: any Error) -> String {
        guard let decoding = error as? DecodingError else { return error.localizedDescription }
        switch decoding {
        case .keyNotFound(let key, let context):
            return "missing \"\(key.stringValue)\" at \(path(context.codingPath))"
        case .typeMismatch(_, let context),
             .valueNotFound(_, let context),
             .dataCorrupted(let context):
            return "\(path(context.codingPath)): \(context.debugDescription)"
        @unknown default:
            return decoding.localizedDescription
        }
    }

    private static func path(_ codingPath: [any CodingKey]) -> String {
        let joined = codingPath.map(\.stringValue).joined(separator: ".")
        return joined.isEmpty ? "the top level" : joined
    }
}

