import Foundation

/// A transition worth a notification, derived from the Host API feed.
///
/// The feed reports facts; this type decides which of them are news. It is
/// pure and synchronous so every rule — baselines, edges, dedupe — is
/// unit-testable without a network.
public enum NotificationEvent: Equatable, Sendable {
    /// The Host is blocked waiting for a human decision about a session.
    /// Always a summons: it stalls the Host until answered, whatever the app
    /// is showing. `session` names the conversation when the list knows it.
    case waitingForUser(SummonsKind, session: String?)
    /// A session's task finished: its agent's `running` flag dropped. Named
    /// by the session, in the Host's own words for it.
    case turnFinished(session: String?)
}

/// Turns a stream of Host feed events into notification events.
///
/// Two facts shape the rules. First, the *first* list snapshot is a baseline:
/// where things stand is state, not news, so a feed that starts mid-run does
/// not announce every already-running session. Second, edges are the news: a
/// `running` flag falling, a summons arriving, a summons being answered.
public struct SessionEventDetector: Sendable {
    /// Running state as last seen, keyed by session id. Seeded by the first
    /// snapshot; every later fact compares against it.
    private var running: [String: Bool] = [:]
    /// The Host's own titles, so a notification can name its conversation.
    private var titles: [String: String] = [:]
    /// Summons seen but not yet answered, keyed by the Host's event id — the
    /// dedupe key if the Gateway ever redelivers, and the memory of what is
    /// still waiting.
    private var pending: [String: SummonsKind] = [:]
    /// Whether the baseline snapshot has been taken.
    private var baselineEstablished = false

    public init() {}

    /// Forget everything seen so far; the next snapshot is a baseline again.
    /// Called when the feed restarts, because a reconnect may have missed
    /// edges that would otherwise fire against stale state.
    public mutating func reset() {
        running = [:]
        titles = [:]
        pending = [:]
        baselineEstablished = false
    }

    public mutating func advance(_ event: HostFeedEvent) -> [NotificationEvent] {
        switch event {
        case .sessions(let sessions):
            return advance(sessions: sessions)
        case .runningChanged(let id, let isRunning):
            return advance(runningChange: isRunning, for: id)
        case .summons(let sessionId, let kind, let eventId):
            // A redelivered summons is one summons. The Host's event id is
            // the identity; the notification fires once.
            guard pending[eventId] == nil else { return [] }
            pending[eventId] = kind
            // A summons is live news the moment it arrives, baseline or not:
            // the Host is blocked right now, whatever the feed has seen.
            return [.waitingForUser(kind, session: titles[sessionId])]
        case .summonsEnded(let eventId):
            pending.removeValue(forKey: eventId)
            return []
        case .failed:
            return []
        }
    }

    /// One list snapshot. Titles always update; running flags both seed the
    /// baseline and — once past it — catch up on edges the socket missed
    /// while the feed was down.
    private mutating func advance(sessions: [HostSession]) -> [NotificationEvent] {
        var events: [NotificationEvent] = []
        for session in sessions {
            if let title = session.title { titles[session.id] = title }
            if baselineEstablished, running[session.id] == true, !session.running {
                events.append(.turnFinished(session: titles[session.id]))
            }
            running[session.id] = session.running
        }
        if !baselineEstablished { baselineEstablished = true }
        return events
    }

    /// One pushed running-state change. Before the baseline this only seeds
    /// state; after it, a fall is a finish.
    private mutating func advance(runningChange isRunning: Bool, for id: String) -> [NotificationEvent] {
        let wasRunning = running[id] ?? false
        running[id] = isRunning
        if baselineEstablished, wasRunning, !isRunning {
            return [.turnFinished(session: titles[id])]
        }
        return []
    }
}
