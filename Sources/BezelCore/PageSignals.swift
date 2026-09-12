import Foundation

/// One session row of the Host's sidebar: the page's own live status for a
/// conversation — running, waiting for the user, or finished and not yet
/// looked at. The Host maintains these for every session it knows, not just
/// the displayed one, which is what makes the background observable at all.
public struct SidebarSession: Equatable, Sendable {
    /// The row's title — the page's name for the conversation.
    public var title: String
    /// The row's status dot: `ongoing` while its agent runs, `warning` while
    /// it waits for the user, `done` for the Host's "completed" reminder —
    /// armed exactly when a session that was running went idle off-screen
    /// and nobody has opened it since. `nil` is a row with no dot: idle.
    public var state: SidebarState?
    /// Whether this row is the conversation the page is displaying; those
    /// rows belong to the page's own events, not the background's.
    public var selected: Bool

    public init(title: String, state: SidebarState?, selected: Bool) {
        self.title = title
        self.state = state
        self.selected = selected
    }
}

/// The statuses the Host's sidebar renders as a dot, verbatim from its own
/// `data-state` attribute.
public enum SidebarState: String, Equatable, Sendable {
    case ongoing
    case warning
    case error
    case done
}

/// What the Host's Web UI reports about itself, read from the DOM it renders.
///
/// The bezel does not understand the protocol, so it watches the display.
/// "The turn finished" is read from the row the Host itself renders only for
/// an ended turn: the actions row under the final answer — copy, fork, usage,
/// feedback — whose container is published the moment the turn's `turn/end`
/// event arrives, and only when a finalized text answer exists to hang it
/// under. Watching that row makes this app's "finished" the same fact the
/// Host's UI acted on, not an inference from streaming markers going quiet.
///
/// The attention panels (approval, question, plan review) are read the same
/// way, from the Web UI's own semantic attributes (`data-approval-key`,
/// `data-question-key`, `data-plan-review-key`) — reading them is
/// observation, not interception: nothing is modified and nothing is routed
/// through this app. If a future Host stops rendering them, the signals
/// simply stop arriving; the connection itself is unaffected.
public struct PageSnapshot: Equatable, Sendable {
    /// What the page is waiting for the user to do.
    public enum Attention: String, Equatable, Sendable {
        case none
        /// A tool call is waiting for an approval decision.
        case approval
        /// The Host asked the user a question.
        case question
        /// A plan is waiting for review.
        case planReview
    }

    /// The Host's own number for the newest ended turn on screen: the value
    /// of the last `data-turn-tail` attribute. `nil` when no ended turn's
    /// actions row is rendered — which is exactly what an in-flight turn
    /// looks like from the outside.
    public var turnTail: String?
    /// The user message that started the newest ended turn, in the user's
    /// own words — the task's name for itself. Read only in the poll where
    /// the turn-tail value changes, so the frame that reports a finish is
    /// the frame that can say which task finished.
    public var prompt: String?
    /// Anchor keys (`data-chat-anchor-key`) of the newest few content rows —
    /// rows that are not a turn-tail — newest first.
    ///
    /// Keys are durable per session: they survive reloads, and a key present
    /// in two consecutive snapshots means the page is still showing the same
    /// conversation. The window is a few rows wide so it can bridge a turn
    /// that starts and ends entirely between two polls.
    public var recentContentTails: [String]
    public var attention: Attention
    /// The Host's own live view of every conversation — the session rows of
    /// its sidebar — including the ones running in the background, off this
    /// page. Empty when the sidebar is collapsed: the rows are simply not in
    /// the DOM, and the background goes dark here.
    public var sidebar: [SidebarSession]
    /// `document.title`, verbatim. The Host sets it to
    /// "<conversation title> — <product name>", which keeps naming the open
    /// conversation even when the sidebar is collapsed and its rows — and
    /// with them the selected row's title — are not in the DOM.
    public var pageTitle: String?

    public init(
        attention: Attention,
        turnTail: String?,
        recentContentTails: [String],
        prompt: String? = nil,
        sidebar: [SidebarSession] = [],
        pageTitle: String? = nil
    ) {
        self.attention = attention
        self.turnTail = turnTail
        self.recentContentTails = recentContentTails
        self.prompt = prompt
        self.sidebar = sidebar
        self.pageTitle = pageTitle
    }

    /// The conversation this page is showing, by name.
    ///
    /// The selected sidebar row is the authority — it is the Host's own name
    /// for the open conversation. When the sidebar is collapsed, the window
    /// title stands in: the Host renders it as
    /// "<conversation title> — <product name>", so the segment before the
    /// last separator is the title. A title with no separator is the bare
    /// product name — the no-session view — and names nothing.
    public var currentSessionTitle: String? {
        if let selected = sidebar.first(where: \.selected)?.title {
            return selected
        }
        guard let title = pageTitle,
              let range = title.range(of: " — ", options: .backwards)
        else { return nil }
        let trimmed = title[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The same snapshot, reading its sidebar from elsewhere.
    ///
    /// The hidden probe page supplies the complete session list — every
    /// workspace group expanded, every overflow opened — while the displayed
    /// page keeps every other field: its own conversation, panels and title
    /// are what the page-channel events are drawn from.
    public func replacingSidebar(_ sidebar: [SidebarSession]) -> PageSnapshot {
        var copy = self
        copy.sidebar = sidebar
        return copy
    }

    /// Decode the payload the observer script posts.
    ///
    /// Returns `nil` for a malformed payload: a broken or foreign script must
    /// fail silent, not crash the page bridge.
    public static func fromScriptMessage(_ body: [String: Any]) -> PageSnapshot? {
        guard let attentionRaw = body["attention"] as? String,
              let attention = Attention(rawValue: attentionRaw)
        else { return nil }
        // JavaScript null crosses the bridge as NSNull; cast-optional handles
        // both that and a missing key, and both mean "no tail on screen".
        let turnTail = body["turnTail"] as? String
        let prompt = body["prompt"] as? String
        // An array that is absent or holds something that is not a string
        // reads as "no rows known"; the guard above already refused payloads
        // without a usable attention.
        let recentContentTails = body["recentContentTails"] as? [String] ?? []
        // Sidebar rows, one per session the Host tracks. A row that is
        // malformed or carries a status this build does not know is skipped:
        // an unreadable row must not corrupt the readable ones.
        var sidebar: [SidebarSession] = []
        if let rows = body["sidebar"] as? [[String: Any]] {
            for row in rows {
                guard let title = row["title"] as? String, !title.isEmpty else { continue }
                let selected = row["selected"] as? Bool ?? false
                let state = row["state"] as? String
                guard let state else {
                    sidebar.append(SidebarSession(title: title, state: nil, selected: selected))
                    continue
                }
                guard let state = SidebarState(rawValue: state) else { continue }
                sidebar.append(SidebarSession(title: title, state: state, selected: selected))
            }
        }
        return PageSnapshot(
            attention: attention,
            turnTail: turnTail,
            recentContentTails: recentContentTails,
            prompt: prompt,
            sidebar: sidebar,
            pageTitle: body["pageTitle"] as? String
        )
    }

    /// The name the observer script posts to, and the app listens for.
    public static let scriptHandlerName = "bezelSignals"
    /// The name the sidebar probe script posts to. A separate channel, so
    /// the probe's snapshots can never be mistaken for the displayed page's.
    public static let probeHandlerName = "bezelProbe"

    /// The observer, injected into the Host's page at document end.
    ///
    /// A plain one-second poll: each pass is a handful of `querySelector`
    /// calls, and a poll cannot miss a panel that mounts and unmounts between
    /// mutations the way a naive `MutationObserver` summary can. The guard
    /// keeps a reinjected script (a reload re-runs user scripts) from
    /// stacking intervals.
    public static var observerScript: String {
        script(postingTo: scriptHandlerName, expandingSidebar: false)
    }

    /// The same observer, for the hidden probe page.
    ///
    /// The probe exists because the Host's sidebar only renders the rows the
    /// user's own view state shows: a collapsed workspace group renders no
    /// session rows at all, and an expanded one caps at its five most
    /// recent. The displayed page must not have its view state touched, so
    /// a second, never-shown page carries the complete sidebar — and there,
    /// nobody is watching, so the script is free to expand every group and
    /// open every "N more" overflow before scanning. A click re-renders
    /// asynchronously, so each pass clicks what is still collapsed and scans
    /// what the previous pass opened; the view converges within a few polls,
    /// and the click targets (matched by `aria-expanded="false"`) drop out
    /// on their own once everything is open.
    public static var probeScript: String {
        script(postingTo: probeHandlerName, expandingSidebar: true)
    }

    static func script(postingTo handlerName: String, expandingSidebar: Bool) -> String {
        #"""
    (function() {
        if (window.__bezelSignalsInstalled) return;
        window.__bezelSignalsInstalled = true;

        var EXPANDING = \#(expandingSidebar);

        var ATTENTION = [
            ["[data-approval-key]", "approval"],
            ["[data-question-key]", "question"],
            ["[data-plan-review-key]", "planReview"]
        ];
        var promptReadFor = null;

        function snapshot() {
            var attention = "none";
            for (var i = 0; i < ATTENTION.length; i++) {
                if (document.querySelector(ATTENTION[i][0])) {
                    attention = ATTENTION[i][1];
                    break;
                }
            }
            // The actions row of the newest ended turn. Old turns keep theirs
            // further up, so the last one in document order is the latest.
            var turnTail = null;
            var tails = document.querySelectorAll("[data-turn-tail]");
            if (tails.length > 0) turnTail = tails[tails.length - 1].getAttribute("data-turn-tail");
            // The newest content rows, skipping turn-tail rows: their keys are
            // the page's conversation identity for the detector.
            var recent = [];
            var rows = document.querySelectorAll("[data-chat-anchor-key]");
            for (var i = rows.length - 1; i >= 0 && recent.length < 4; i--) {
                if (!rows[i].hasAttribute("data-turn-tail")) {
                    recent.push(rows[i].getAttribute("data-chat-anchor-key"));
                }
            }
            // The user message that started the ended turn — read only when
            // the tail value changes, so the finish frame carries its own
            // task's name. The row is matched by the Host's own turn number,
            // which it stamps on both markers.
            var prompt = null;
            if (turnTail !== null && turnTail !== promptReadFor) {
                prompt = promptOf(turnTail);
                if (prompt !== null) promptReadFor = turnTail;
            }
            // Session rows of the sidebar — the page's live view of every
            // conversation, the background ones included. Their status dot
            // is the Host's own fact: "ongoing" while running, "warning"
            // while waiting for the user, "done" for a session that finished
            // off-screen and has not been opened since. The rows exist only
            // while the sidebar is expanded; collapsed, this list is simply
            // empty and the detector reads "nothing to report from the
            // background".
            var sidebar = [];
            var sessionRows = document.querySelectorAll('[role="treeitem"]');
            for (var i = 0; i < sessionRows.length; i++) {
                var row = sessionRows[i];
                // Session rows always carry aria-selected, read or not; the
                // page's other treeitems (a subagent lineage row marks itself
                // aria-disabled instead) are not sessions, and a subagent's
                // own running dot must not masquerade as a background one.
                if (!row.hasAttribute("aria-selected")) continue;
                var dot = row.querySelector("[data-state]");
                var title = "";
                for (var j = 0; j < row.children.length; j++) {
                    // The first child with text that is not the status slot
                    // is the title; the slot is the one holding the dot, and
                    // it is empty when the row shows no dot at all.
                    if (row.children[j].querySelector("[data-state]")) continue;
                    if ((row.children[j].textContent || "").trim() === "") continue;
                    title = row.children[j].textContent || "";
                    break;
                }
                title = title.replace(/\s+/g, " ").trim();
                if (title === "") continue;
                sidebar.push({
                    title: Array.from(title).slice(0, 120).join(""),
                    state: dot === null ? null : dot.getAttribute("data-state"),
                    selected: row.getAttribute("aria-selected") === "true"
                });
            }
            return {
                attention: attention,
                turnTail: turnTail,
                recentContentTails: recent,
                prompt: prompt,
                pageTitle: document.title || "",
                sidebar: sidebar
            };
        }

        // The text of the user row that started the given turn. The row's
        // last element child is the actions row (clock, copy button) — it
        // says when, not what, so everything before it is the task. A turn
        // whose user row is off-screen falls back to the newest user row:
        // the best remaining label for "which task".
        function promptOf(turn) {
            if (!/^[0-9]+$/.test(turn)) return null;
            var row = document.querySelector('[data-chat-flow-kind="user"][data-chat-turn="' + turn + '"]');
            if (row === null) {
                var users = document.querySelectorAll('[data-chat-flow-kind="user"]');
                if (users.length === 0) return null;
                row = users[users.length - 1];
            }
            var message = row.firstElementChild;
            var text = "";
            if (message !== null && message.childElementCount > 1) {
                for (var i = 0; i < message.childElementCount - 1; i++) {
                    text += message.children[i].textContent + " ";
                }
            } else {
                text = row.textContent;
            }
            text = text.replace(/\s+/g, " ").trim();
            return text === "" ? null : Array.from(text).slice(0, 200).join("");
        }

        // The probe page's one extra duty: open every part of the sidebar
        // the Host renders on demand — collapsed workspace groups, and the
        // per-group "N more" overflow that caps an expanded group at its
        // five most recent sessions. Both toggles carry
        // aria-expanded="false" while closed, so the selectors match only
        // what still needs opening, and a group header is itself the toggle
        // (the Host wires its click to the expand/collapse action).
        function expand() {
            var closed = document.querySelectorAll('[role="treeitem"][aria-expanded="false"]');
            for (var i = 0; i < closed.length; i++) closed[i].click();
            var overflow = document.querySelectorAll('[role="tree"] button[aria-expanded="false"]');
            for (var i = 0; i < overflow.length; i++) overflow[i].click();
        }

        function post() {
            try {
                if (EXPANDING) expand();
                window.webkit.messageHandlers.\#(handlerName).postMessage(snapshot());
            } catch (error) {
                /* No handler registered — nothing this script can do. */
            }
        }

        post();
        setInterval(post, 1000);
    })();
    """#
    }
}

/// A change in the page worth telling the user about.
public enum PageEvent: Equatable, Sendable {
    /// The Host is waiting for the user: an approval, a question, or a plan
    /// review appeared on screen.
    case attentionNeeded(PageSnapshot.Attention)
    /// A turn ended: the actions row the Host renders under the final answer
    /// (copy, fork, usage, feedback) appeared for a turn that had none. The
    /// prompt is the user message that started that turn — the task's name
    /// for itself, in the user's words.
    case taskFinished(prompt: String?)
    /// A conversation not on this page finished its task: the Host armed its
    /// own "completed" reminder for it — the dot that appears exactly when a
    /// session that was running went idle off-screen and nobody has opened
    /// it since. The title is the sidebar row's name for that conversation.
    case backgroundTaskFinished(title: String)
    /// A conversation not on this page is waiting for the user: its sidebar
    /// row shows the waiting dot. The kind of waiting (approval, question,
    /// plan review) is not separable from the dot; the title names the
    /// conversation that wants attention.
    case backgroundAttentionNeeded(title: String)
}

public extension PageEvent {
    /// Whether the Host is blocked on the user — an approval, a question, a
    /// plan review, on this page or in the background. Such an event is a
    /// summons: it must reach the user whatever the app's own visibility,
    /// because a missed answer stalls the session silently, and the visible
    /// page does not cover every source — a background session waiting for
    /// its answer shows nothing on it at all.
    var isWaitingForUser: Bool {
        switch self {
        case .attentionNeeded(.approval), .attentionNeeded(.question), .attentionNeeded(.planReview), .backgroundAttentionNeeded:
            return true
        case .attentionNeeded(.none), .taskFinished, .backgroundTaskFinished:
            return false
        }
    }
}

/// Turns a stream of page snapshots into the transitions worth notifying.
///
/// Pure, so the edge cases — the baseline after a load, a conversation switch
/// masquerading as a finished turn, a fast turn that starts and ends between
/// two polls — are unit-testable without a WebView.
public struct PageEventDetector: Sendable {
    private var previous: PageSnapshot?

    public init() {}

    /// Forget everything seen so far; the next snapshot is a baseline again.
    public mutating func reset() {
        previous = nil
    }

    public mutating func advance(to next: PageSnapshot) -> [PageEvent] {
        defer { previous = next }

        // The first snapshot after a load only says where things stand.
        guard let previous else { return [] }

        var events: [PageEvent] = []
        if previous.attention == .none, next.attention != .none {
            events.append(.attentionNeeded(next.attention))
        }
        // A turn-tail the previous snapshot did not show, in a conversation
        // that is still the same one: the Host renders that row only once the
        // turn has ended, so a new value is the finish itself. Continuity is
        // what separates "a new turn ended here" from "the page switched to
        // another conversation": a switch replaces every row, while a turn
        // that ends leaves the rows above it standing — including the row
        // that was newest a second ago. A turn that begins and ends inside
        // one poll interval is covered too, by the window width rather than
        // by the newest row alone.
        //
        // A panel waiting for the user is page state, not a diff — it stays
        // reportable even when the rows moved, and outranks the finish: a
        // bare "finished" would understate a turn that ended on a question.
        if events.isEmpty,
           let endedTurn = next.turnTail,
           endedTurn != previous.turnTail,
           let newestRowOfPrevious = previous.recentContentTails.first,
           next.recentContentTails.contains(newestRowOfPrevious) {
            events.append(.taskFinished(prompt: next.prompt))
        }
        // Edges on the sidebar's session rows — the background, which the
        // displayed conversation cannot show. Only rows present in both
        // frames count: a row that just appeared (a page load, the sidebar
        // being expanded, a rename) is state, not news — the Host's own
        // "completed" reminder arms on a running-to-idle edge of an
        // unselected session, so a dot's first sighting after a gap is
        // history, not an event. Selected rows are the displayed page's
        // business: its panels and turn-tail cover those without a second
        // notification, and a row the user just switched away from is given
        // one frame of grace for the same reason.
        if !previous.sidebar.isEmpty {
            var before: [String: SidebarSession] = [:]
            for row in previous.sidebar where before[row.title] == nil {
                before[row.title] = row
            }
            // The displayed conversation is excluded by name as well as by
            // selection: the probe page's sidebar names every session but
            // selects none (it opens nothing), so the row matching the
            // displayed page's current conversation is told apart by title
            // alone — and left to the page channel, which reports it with
            // the turn's own words instead of a bare dot.
            let current = next.currentSessionTitle
            for row in next.sidebar {
                guard !row.selected, let prior = before[row.title], !prior.selected else { continue }
                if row.title == current { continue }
                if row.state == .done, prior.state != .done {
                    events.append(.backgroundTaskFinished(title: row.title))
                } else if row.state == .warning, prior.state != .warning {
                    events.append(.backgroundAttentionNeeded(title: row.title))
                }
            }
        }
        return events
    }
}
