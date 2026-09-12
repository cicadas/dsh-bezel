import Foundation

/// One saved dsh Host the app can attach to.
///
/// The record carries only what a connection needs: the Host's HTTP origin and
/// the optional one-shot launch token printed by `dsh web`. The Host exchanges
/// that token for a 30-day signed cookie, so the token is a first-contact
/// credential rather than a durable secret.
public struct DSHHost: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    /// Label shown in the host picker; the origin is used when empty.
    public var name: String
    /// Origin serving the Web UI, for example `http://127.0.0.1:3080`.
    public var baseURL: String
    /// Launch token from `dsh web`; empty once a cookie is the only credential.
    public var token: String
    /// Boot `dsh --profile <profile> --port 0 --no-open` and use the URL it prints.
    public var managed: Bool
    /// Profile name used when `managed` is set.
    public var profile: String
    /// Extra arguments for the managed invocation, separated by whitespace.
    public var extraArguments: String
    /// Explicit `dsh` executable for managed mode; empty means auto-discover.
    ///
    /// Auto-discovery asks the login shell and probes every candidate, but a
    /// GUI bundle cannot be handed environment variables reliably — so the
    /// escape hatch for "my `dsh` is somewhere unusual" has to be a stored
    /// setting rather than `$BEZEL_DSH_PATH`.
    public var dshPath: String
    /// Custom start command for managed mode; empty means the standard
    /// `dsh --profile <profile> --port 0 --no-open` invocation.
    ///
    /// The command is the user's own words, run through their login shell,
    /// and must print the `dsh web: <url>` startup line so the runner can
    /// pick the URL out of it. It exists for launchers this app does not
    /// know how to compose itself — a wrapper script, extra environment
    /// setup, a non-standard profile invocation.
    public var launchCommand: String

    public init(
        id: UUID = UUID(),
        name: String = "",
        baseURL: String = "",
        token: String = "",
        managed: Bool = false,
        profile: String = "web",
        extraArguments: String = "",
        dshPath: String = "",
        launchCommand: String = ""
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.token = token
        self.managed = managed
        self.profile = profile
        self.extraArguments = extraArguments
        self.dshPath = dshPath
        self.launchCommand = launchCommand
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, baseURL, token, managed, profile, extraArguments, dshPath, launchCommand
    }

    /// Decoded field by field, with a default for every key.
    ///
    /// A bookmark written by an older build has to keep working, and one
    /// unrecognised shape must not cost the user every Host they saved: the
    /// synthesized decoder fails the whole array on a single missing key, and
    /// the store used to react to that failure by overwriting the file.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        token = try container.decodeIfPresent(String.self, forKey: .token) ?? ""
        managed = try container.decodeIfPresent(Bool.self, forKey: .managed) ?? false
        profile = try container.decodeIfPresent(String.self, forKey: .profile) ?? "web"
        extraArguments = try container.decodeIfPresent(String.self, forKey: .extraArguments) ?? ""
        dshPath = try container.decodeIfPresent(String.self, forKey: .dshPath) ?? ""
        launchCommand = try container.decodeIfPresent(String.self, forKey: .launchCommand) ?? ""
    }

    /// Origin without path, query, or trailing slash; nil when unparseable.
    public var origin: URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: trimmed),
              components.scheme == "http" || components.scheme == "https",
              let host = components.host, !host.isEmpty else { return nil }
        components.path = ""
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url
    }

    public var isValid: Bool { origin != nil }

    /// URL the WebView loads.
    ///
    /// A configured token rides the root query, the only shape the Host accepts
    /// for minting its cookie. The Host's index authorization redirects a valid
    /// cookie to clean `/` even when the token is stale, so keeping the token in
    /// the URL stays safe across Host restarts.
    public var loadURL: URL? {
        guard let origin else { return nil }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(url: origin, resolvingAgainstBaseURL: false) else { return origin }
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "token", value: trimmed)]
        return components.url
    }

    /// Whitespace-split `extraArguments` for the managed invocation.
    public var argumentList: [String] {
        extraArguments.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
    }

    /// Name to show for this bookmark, falling back to its address.
    ///
    /// A name the user typed is their data and is shown as-is in every
    /// language; only the "no name at all" fallback needs translating.
    public func displayName(in localization: Localization = Localization()) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let origin { return origin.absoluteString }
        return baseURL.isEmpty ? localization.text(.untitledHost) : baseURL
    }
}
