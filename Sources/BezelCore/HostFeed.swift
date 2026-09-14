import Foundation

/// The Host API surface this app subscribes to, and nothing more.
///
/// The Web UI stays the only thing that talks to the Host interactively; this
/// feed exists purely so notifications do not have to watch the page. It
/// consumes two facts off the wire:
///
/// - **Session state.** `session.list` (a unary POST) returns every session
///   with a `running` flag; the Host pushes `api-session/status` on every
///   change. A `running` true→false edge *is* "the task finished" — the same
///   fact the Web UI's own green sidebar dot is derived from.
/// - **Summons.** `approval/request` and `user-questions/request` arrive as
///   waterfall events: the Host is blocked waiting for a client's answer. The
///   Gateway delivers a copy to *every* connected client, and the first
///   client that answers settles it — a client that never answers merely
///   stays in the delivery set. So this feed can listen passively while the
///   Web page keeps its monopoly on answering: the page's decision resolves
///   the waterfall for everyone, and the Gateway then sends a `cancel` frame
///   for that event id, which is this feed's "the waiting ended" edge.
///
/// Everything rides plain JSON text frames over one WebSocket
/// (`/api/remote.mux`) plus ordinary POSTs, authorized by the same
/// `dsh-auth-*` cookie the Web page minted.
public enum SummonsKind: String, Equatable, Sendable {
    /// A tool call is waiting for an approval decision.
    case approval
    /// The Host asked a question (a plan review arrives through the same
    /// gate, marked by a `plan-review` intent inside the request).
    case question
    /// A plan is waiting for review.
    case planReview
}

/// One row of the Host's session list, reduced to what notifications need.
public struct HostSession: Equatable, Sendable {
    /// The Host's identity for the conversation. The same value a summons
    /// frame carries as its agent id.
    public var id: String
    /// The Host's own durable title, when one exists yet. A session that has
    /// not been prompted is untitled; `nil` is normal, not an error.
    public var title: String?
    /// Whether its agent is running right now.
    public var running: Bool

    public init(id: String, title: String?, running: Bool) {
        self.id = id
        self.title = title
        self.running = running
    }
}

/// Why the feed is not currently healthy. Structured, so the wording follows
/// the interface language like every other message.
public enum HostFeedFailure: Equatable, Sendable {
    /// The Host refused the credential. Expected briefly on a first connect
    /// (the page mints the cookie seconds after loading) and permanently when
    /// the 30-day cookie has expired and no token is at hand.
    case unauthorized
    /// Anything else: DNS, refused socket, malformed frame, closed stream.
    case transport(String)
}

/// One fact the feed learned, in the order it learned it.
public enum HostFeedEvent: Equatable, Sendable {
    /// A full session-list snapshot. The first one establishes the baseline;
    /// later ones reconcile titles and catch up on edges missed while the
    /// socket was down.
    case sessions([HostSession])
    /// The Host pushed a running-state change for one session.
    case runningChanged(id: String, running: Bool)
    /// A summons arrived: the Host is blocked waiting for a human decision
    /// about this session.
    case summons(sessionId: String, kind: SummonsKind, eventId: String)
    /// A previously delivered summons was settled by someone else (the Web
    /// page answered, or the request was withdrawn).
    case summonsEnded(eventId: String)
    /// The channel broke. The feed keeps retrying on its own; this is for the
    /// status line.
    case failed(HostFeedFailure)
}

/// The connection state behind the Settings status line.
public enum HostFeedHealth: Equatable, Sendable {
    case idle
    case connecting
    case healthy
    case unauthorized
    case reconnecting
}

// MARK: - Wire parsing

/// Wire frames, parsed tolerantly. Every helper here is pure and unit-tested:
/// the protocol is exactly the part that drifts, so exactly that part is
/// fenced off behind functions that refuse to guess.
enum HostFeedWire {
    /// The internal stream the Gateway forwards allowlisted Host events on.
    static let eventsEndpoint = "$events"
    static let listMethod = "session/list"

    /// The one client-to-Host frame this app ever sends: open the forwarded
    /// event stream. `streamId` is client-chosen and only has to be unique on
    /// this connection.
    static func openFrame(streamId: String) -> String {
        encode([
            "type": .string("open"),
            "streamId": .string(streamId),
            "endpoint": .string(eventsEndpoint),
            "payload": .object(["args": .object([:])]),
        ])
    }

    /// The unary body for `session.list`. The descriptor expects its request
    /// object under `_request`; an empty one returns the full list.
    static func listRequestBody(rpcId: String) -> String {
        encode([
            "type": .string("client-request"),
            "rpcId": .string(rpcId),
            "method": .string(listMethod),
            "payload": .object(["args": .object(["_request": .object([:])])]),
        ])
    }

    /// Parse one server-to-client text frame into the facts this app cares
    /// about. Frames this feature does not consume (the dozens of other
    /// allowlisted events, ready metadata) come back as `nil` — an unknown
    /// frame is normal traffic, never an error.
    static func parseFrame(_ text: String) -> HostFeedEvent? {
        guard let object = jsonObject(text) else { return nil }
        // Event payloads ride inside item frames as `value`; accept an
        // unwrapped frame too, so a future Gateway change that drops the
        // wrapper keeps this working.
        let inner: [String: JSONValue]
        if object["type"]?.string == "item", case .object(let value) = object["value"] ?? .null {
            inner = value
        } else if ["waterfall", "emit", "cancel"].contains(object["type"]?.string) {
            inner = object
        } else {
            return nil
        }
        switch inner["type"]?.string {
        case "emit":
            guard let event = inner["event"]?.string else { return nil }
            return emitEvent(named: event, args: inner["args"]?.array ?? [])
        case "waterfall":
            return waterfallEvent(from: inner)
        case "cancel":
            // A summons was settled elsewhere. The frame carries `eventId`.
            guard let eventId = inner["eventId"]?.string else { return nil }
            return .summonsEnded(eventId: eventId)
        default:
            return nil
        }
    }

    /// Whether this raw frame announces a session the list has not shown yet.
    /// A substring check on the event name, deliberately: its only use is
    /// deciding when to pull the list for a fresh title, and parsing the
    /// whole summary here would duplicate `session.list` decoding.
    static func announcesNewSession(_ text: String) -> Bool {
        text.contains("\"event\":\"api-session/added\"")
            || text.contains("\"event\": \"api-session/added\"")
    }

    /// Emitted (broadcast) Host events. Only `api-session/status` carries a
    /// fact notifications need; everything else is other features' traffic.
    private static func emitEvent(named event: String, args: [JSONValue]) -> HostFeedEvent? {
        guard event == "api-session/status" else { return nil }
        guard args.count >= 2, let id = args[0].string, let running = args[1].bool else { return nil }
        return .runningChanged(id: id, running: running)
    }

    /// A waterfall frame: the Host is blocked waiting for a client answer.
    /// `agentId` is the session the request belongs to (the Host keys agents
    /// by session id), `eventId` is what a later `cancel` frame will quote.
    private static func waterfallEvent(from frame: [String: JSONValue]) -> HostFeedEvent? {
        guard let event = frame["event"]?.string,
              let eventId = frame["eventId"]?.string,
              let sessionId = frame["agentId"]?.string
        else { return nil }
        switch event {
        case "approval/request":
            return .summons(sessionId: sessionId, kind: .approval, eventId: eventId)
        case "user-questions/request":
            // A plan review is a question whose payload marks a
            // `plan-review` intent; an ordinary question is not so marked.
            let kind: SummonsKind = marksPlanReview(frame["request"] ?? .null) ? .planReview : .question
            return .summons(sessionId: sessionId, kind: kind, eventId: eventId)
        default:
            // Some future summons gate: not a fact this build understands.
            return nil
        }
    }

    /// Whether a request payload carries a plan-review marker anywhere. The
    /// Web UI distinguishes its takeover panel by a question whose `intent`
    /// is `plan-review`; walking the whole payload tolerantly means a Host
    /// that moves the marker one level deeper still classifies correctly.
    static func marksPlanReview(_ value: JSONValue) -> Bool {
        switch value {
        case .object(let fields):
            if fields["intent"]?.string == "plan-review" { return true }
            if fields["kind"]?.string == "plan-review" { return true }
            return fields.values.contains { marksPlanReview($0) }
        case .array(let values):
            return values.contains { marksPlanReview($0) }
        case .string(let string):
            return string == "plan-review"
        default:
            return false
        }
    }

    /// Decode a `session.list` response. Tolerant by design: a scalar of the
    /// wrong type or a missing field costs that one row, never the snapshot.
    static func sessions(from data: Data) -> [HostSession]? {
        guard let envelope = jsonObject(Data(data)),
              case .object(let result) = envelope["result"] ?? .null,
              result["ok"]?.bool == true,
              case .object(let value) = result["value"] ?? .null,
              case .array(let items) = value["items"] ?? .null
        else { return nil }
        return items.compactMap { item -> HostSession? in
            guard case .object(let fields) = item, let id = fields["sessionId"]?.string else { return nil }
            let title = fields["title"]?.string
                ?? fields["projections"]?.object?["values"]?.object?["title"]?.string
            return HostSession(id: id, title: title, running: fields["running"]?.bool ?? false)
        }
    }

    private static func jsonObject(_ text: String) -> [String: JSONValue]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return jsonObject(data)
    }

    private static func jsonObject(_ data: Data) -> [String: JSONValue]? {
        guard case .object(let object) = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        return object
    }

    private static func encode(_ value: [String: JSONValue]) -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(JSONValue.object(value)) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

// MARK: - The feed

/// Owns the notification channel to one Host: one WebSocket for pushed
/// events, occasional unary POSTs for the session list.
///
/// All failures are retried in place for as long as the feed is started —
/// most importantly `unauthorized`, because on a first connect the Web page
/// has often not minted the cookie yet; the retry simply catches the moment
/// it appears. Nothing here ever touches the Web page or its view state.
@MainActor
public final class HostFeed {
    /// Who the cookies come from. The WebKit cookie store is the one place
    /// the page's credential lives, but BezelCore stays framework-free, so
    /// the app layer hands in a reader.
    public typealias CookieProvider = @Sendable (URL) async -> [HTTPCookie]

    private let cookieProvider: CookieProvider
    private let onEvent: @MainActor (HostFeedEvent) -> Void
    private let onHealth: @MainActor (HostFeedHealth) -> Void

    private var worker: Task<Void, Never>?
    private var origin: URL?
    /// Consecutive failed attempts, so retries back off instead of spinning
    /// against a Host that is down.
    private var attempts = 0
    /// Set by the socket loop when a frame just made a list pull worthwhile
    /// (a summons naming a session, a finish, a session appearing); consumed
    /// and cleared by the pull loop, throttled.
    private var pullRequested = false
    private var lastPull: Date?

    public init(
        cookieProvider: @escaping CookieProvider,
        onEvent: @escaping @MainActor (HostFeedEvent) -> Void,
        onHealth: @escaping @MainActor (HostFeedHealth) -> Void
    ) {
        self.cookieProvider = cookieProvider
        self.onEvent = onEvent
        self.onHealth = onHealth
    }

    public func start(origin: URL) {
        guard self.origin != origin else { return }
        stop()
        self.origin = origin
        attempts = 0
        onHealth(.connecting)
        worker = Task { [weak self] in await self?.run(origin: origin) }
    }

    public func stop() {
        worker?.cancel()
        worker = nil
        origin = nil
        onHealth(.idle)
    }

    // MARK: - The connection loop

    /// Connect, listen, pull; on any failure, report and retry until stopped.
    /// Every attempt refetches the cookie, so a rotation mid-life is caught
    /// on the next reconnect rather than at the next launch.
    private func run(origin: URL) async {
        while !Task.isCancelled {
            let failure = await attempt(origin: origin)
            if Task.isCancelled { return }
            switch failure {
            case nil:
                attempts = 0
                // A connection that ended without a reported failure — the
                // socket closed cleanly. Treat it like any other break.
                onHealth(.reconnecting)
            case .unauthorized?:
                attempts += 1
                onEvent(.failed(.unauthorized))
                onHealth(.unauthorized)
                // Short and steady: the page mints the cookie at any moment,
                // and when it is truly expired there is no point hammering.
                try? await Task.sleep(nanoseconds: UInt64(Self.unauthorizedRetry * 1_000_000_000))
            case .transport?:
                attempts += 1
                onHealth(.reconnecting)
                let seconds = min(30.0, pow(2.0, Double(min(attempts, 5))))
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            onHealth(.connecting)
        }
    }

    /// One connection attempt, ending when the socket dies. `nil` means the
    /// attempt ended without knowing why (clean close).
    private func attempt(origin: URL) async -> HostFeedFailure? {
        let cookies = await cookieProvider(origin)
        guard !cookies.isEmpty else { return .unauthorized }
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        do {
            try await listen(origin: origin, cookies: cookies, session: session)
            return nil
        } catch is CancellationError {
            return nil
        } catch let failure as FeedFailureError {
            return failure.failure
        } catch {
            return .transport(String(describing: error))
        }
    }

    /// One live connection: open the event stream, then keep receiving and
    /// pulling. Returns when the socket dies.
    private func listen(origin: URL, cookies: [HTTPCookie], session: URLSession) async throws {
        let socket = try await openSocket(origin: origin, cookies: cookies, session: session)
        defer { socket.cancel() }
        onHealth(.healthy)

        // The list pull keeps titles fresh and reconciles running state after
        // gaps. The socket provides the instant edges; the pull is the net.
        let pulls = Task { [weak self] in await self?.pullLoop(origin: origin, cookies: cookies, session: session) }
        defer { pulls.cancel() }

        while !Task.isCancelled {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await socket.receive()
            } catch {
                throw FeedFailureError(.transport(String(describing: error)))
            }
            guard case .string(let text) = message else { continue }
            if HostFeedWire.announcesNewSession(text) { pullRequested = true }
            if let event = HostFeedWire.parseFrame(text) {
                // A summons or a finish is exactly when a fresh title matters.
                if case .summons = event { pullRequested = true }
                if case .runningChanged(_, false) = event { pullRequested = true }
                onEvent(event)
            }
        }
    }

    /// Open the WebSocket and start the event stream on it.
    private func openSocket(origin: URL, cookies: [HTTPCookie], session: URLSession) async throws -> URLSessionWebSocketTask {
        guard let endpoint = webSocketURL(origin: origin) else {
            throw FeedFailureError(.transport("origin has no socket address"))
        }
        var request = URLRequest(url: endpoint)
        request.httpShouldHandleCookies = false
        if let header = Self.cookieHeader(for: origin, cookies: cookies) {
            request.setValue(header, forHTTPHeaderField: "Cookie")
        }
        let socket = session.webSocketTask(with: request)
        socket.resume()
        // Opening the stream makes the handshake outcome deterministic: the
        // first frames are either the stream's ready marker (credential
        // accepted) or a refused socket (credential missing/expired, or the
        // Host is genuinely unreachable — distinguished below by the error).
        socket.send(.string(HostFeedWire.openFrame(streamId: "bezel-events")), completionHandler: { _ in })
        do {
            // A few frames of grace: ready is first in practice, but a
            // broadcast emitted in the same instant must not break the scan.
            for _ in 0..<5 where !Task.isCancelled {
                let message = try await socket.receive()
                guard case .string(let text) = message,
                      let frame = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)),
                      frame.object?["value"]?.object?["type"]?.string == "ready"
                        || frame.object?["type"]?.string == "ready"
                else { continue }
                return socket
            }
            throw FeedFailureError(.transport("event stream did not become ready"))
        } catch let failure as FeedFailureError {
            throw failure
        } catch let error as URLError {
            // The system could not reach the Host at all — transport damage,
            // not a credential problem.
            throw FeedFailureError(.transport(String(describing: error)))
        } catch {
            // The socket opened and was then closed before the stream became
            // ready: the Gateway authorizes the upgrade before accepting it,
            // so this is what a refused credential looks like.
            throw FeedFailureError(.unauthorized)
        }
    }

    /// Pulls the session list: periodically (titles and gap catch-up), plus
    /// on demand shortly after a frame made one worthwhile. Throttled so a
    /// burst of events costs one pull.
    private func pullLoop(origin: URL, cookies: [HTTPCookie], session: URLSession) async {
        lastPull = nil
        while !Task.isCancelled {
            let now = Date()
            let due = now.timeIntervalSince(lastPull ?? .distantPast) >= Self.pullInterval
            if pullRequested, now.timeIntervalSince(lastPull ?? .distantPast) >= Self.refreshThrottle {
                pullRequested = false
                await pullList(origin: origin, cookies: cookies, session: session)
                lastPull = Date()
            } else if due {
                await pullList(origin: origin, cookies: cookies, session: session)
                lastPull = Date()
            }
            try? await Task.sleep(nanoseconds: UInt64(Self.pullTick * 1_000_000_000))
        }
    }

    private func pullList(origin: URL, cookies: [HTTPCookie], session: URLSession) async {
        var base = origin.absoluteString
        if base.hasSuffix("/") { base.removeLast() }
        guard let endpoint = URL(string: base + "/api/session/list") else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if let header = Self.cookieHeader(for: origin, cookies: cookies) {
            request.setValue(header, forHTTPHeaderField: "Cookie")
        }
        request.httpBody = Data(HostFeedWire.listRequestBody(rpcId: UUID().uuidString).utf8)
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                onEvent(.failed(.unauthorized))
                return
            }
            if let sessions = HostFeedWire.sessions(from: data) {
                onEvent(.sessions(sessions))
            }
        } catch is CancellationError {
            return
        } catch {
            onEvent(.failed(.transport(String(describing: error))))
        }
    }

    /// The `Cookie` header for `origin`: the page's own `dsh-auth-*` cookie,
    /// matched by authority exactly as the Host scopes its credentials.
    nonisolated static func cookieHeader(for origin: URL, cookies: [HTTPCookie]) -> String? {
        let host = origin.host ?? ""
        let matching = cookies.filter { cookie in
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return host == domain || host.hasSuffix("." + domain)
        }
        guard !matching.isEmpty else { return nil }
        return matching.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    private func webSocketURL(origin: URL) -> URL? {
        var components = URLComponents(url: origin, resolvingAgainstBaseURL: false)
        let scheme = components?.scheme
        components?.scheme = scheme == "https" ? "wss" : "ws"
        let path = components?.path ?? ""
        components?.path = path.hasSuffix("/") ? path + "api/remote.mux" : path + "/api/remote.mux"
        return components?.url
    }

    /// How often the list is pulled while connected. The socket delivers the
    /// instant facts; this only refreshes titles and catches missed edges.
    static let pullInterval: TimeInterval = 20
    /// The soonest an on-demand pull may follow the previous pull.
    static let refreshThrottle: TimeInterval = 2
    /// The pull loop's tick — how often it *checks* whether a pull is due.
    private static let pullTick: TimeInterval = 0.5
    /// Steady cadence for a refused credential.
    static let unauthorizedRetry: TimeInterval = 5
}

/// Carries a structured failure through the async throwing path without
/// flattening it into a string.
private struct FeedFailureError: Error {
    let failure: HostFeedFailure

    init(_ failure: HostFeedFailure) {
        self.failure = failure
    }
}
