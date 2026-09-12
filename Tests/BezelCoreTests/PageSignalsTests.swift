import XCTest
@testable import BezelCore

/// The page-signal snapshot and the transitions derived from it.
final class PageSignalsTests: XCTestCase {
    // MARK: - Decoding the observer script's payload

    func testAValidPayloadDecodes() {
        let snapshot = PageSnapshot.fromScriptMessage([
            "attention": "question",
            "turnTail": "7",
            "recentContentTails": ["node-9", "node-8"],
            "prompt": "帮我重启app",
            "sidebar": [
                ["title": "打包发布版", "state": NSNull(), "selected": true],
                ["title": "后台任务", "state": "ongoing", "selected": false]
            ]
        ])

        XCTAssertEqual(
            snapshot,
            PageSnapshot(
                attention: .question,
                turnTail: "7",
                recentContentTails: ["node-9", "node-8"],
                prompt: "帮我重启app",
                sidebar: [
                    SidebarSession(title: "打包发布版", state: nil, selected: true),
                    SidebarSession(title: "后台任务", state: .ongoing, selected: false)
                ]
            )
        )
    }

    /// A sidebar row that is malformed, or carries a status this build does
    /// not know, is skipped — one unreadable row must not corrupt the rest.
    /// Rows are absent entirely when the sidebar is collapsed.
    func testSidebarRowsDecodeLeniently() {
        let snapshot = PageSnapshot.fromScriptMessage([
            "attention": "none",
            "sidebar": [
                ["title": "好的行", "state": "done", "selected": false],
                ["state": "ongoing"],
                ["title": "未知状态", "state": "paused", "selected": false],
                ["title": "无点行", "selected": false]
            ]
        ])

        XCTAssertEqual(snapshot?.sidebar, [
            SidebarSession(title: "好的行", state: .done, selected: false),
            SidebarSession(title: "无点行", state: nil, selected: false)
        ])
        XCTAssertEqual(PageSnapshot.fromScriptMessage(["attention": "none"])?.sidebar, [])
    }

    /// JavaScript null crosses the bridge as `NSNull`; both it and a missing
    /// key must read as "no tail on screen", and a missing array as "no rows".
    func testATaillessPayloadDecodes() {
        let withNulls = PageSnapshot.fromScriptMessage([
            "attention": "none",
            "turnTail": NSNull(),
            "recentContentTails": [],
            "prompt": NSNull()
        ])
        let withMissingKeys = PageSnapshot.fromScriptMessage(["attention": "none"])

        XCTAssertEqual(withNulls, PageSnapshot(attention: .none, turnTail: nil, recentContentTails: []))
        XCTAssertEqual(withMissingKeys, withNulls)
    }

    /// A foreign or broken script must fail silent, not crash the bridge.
    func testAMalformedPayloadIsRefused() {
        XCTAssertNil(PageSnapshot.fromScriptMessage([:]))
        XCTAssertNil(PageSnapshot.fromScriptMessage(["turnTail": "7"]))
        XCTAssertNil(PageSnapshot.fromScriptMessage(["attention": "surprise", "turnTail": "7"]))
        XCTAssertNil(PageSnapshot.fromScriptMessage(["attention": 3, "turnTail": "7"]))
    }

    /// Renaming the handler or the markers without touching the script (or
    /// vice versa) must be caught here, where it is cheap.
    func testTheObserverScriptPostsToTheHandlerItNames() {
        XCTAssertTrue(PageSnapshot.observerScript.contains(PageSnapshot.scriptHandlerName))
        XCTAssertTrue(PageSnapshot.observerScript.contains("[data-turn-tail]"))
        XCTAssertTrue(PageSnapshot.observerScript.contains("[data-chat-anchor-key]"))
        XCTAssertTrue(PageSnapshot.observerScript.contains("[data-chat-flow-kind=\"user\"]"))
        XCTAssertTrue(PageSnapshot.observerScript.contains("[role=\"treeitem\"]"))
    }

    // MARK: - The detector

    private func snapshot(
        attention: PageSnapshot.Attention = .none,
        turnTail: String? = nil,
        recent: [String] = ["m6"],
        prompt: String? = nil,
        sidebar: [SidebarSession] = [],
        pageTitle: String? = nil
    ) -> PageSnapshot {
        PageSnapshot(
            attention: attention,
            turnTail: turnTail,
            recentContentTails: recent,
            prompt: prompt,
            sidebar: sidebar,
            pageTitle: pageTitle
        )
    }

    private func row(
        _ title: String,
        _ state: SidebarState?,
        selected: Bool = false
    ) -> SidebarSession {
        SidebarSession(title: title, state: state, selected: selected)
    }

    /// Whatever the first snapshot says is where things stand, not a change.
    func testTheFirstSnapshotEstablishesTheBaseline() {
        var detector = PageEventDetector()

        XCTAssertEqual(detector.advance(to: snapshot(attention: .question, turnTail: "9")), [])
        XCTAssertEqual(detector.advance(to: snapshot(attention: .question, turnTail: "9")), [])
    }

    func testAttentionAppearingIsNotified() {
        var detector = PageEventDetector()
        detector.advance(to: snapshot())

        XCTAssertEqual(detector.advance(to: snapshot(attention: .approval)), [.attentionNeeded(.approval)])
        // Still there: one summons is enough.
        XCTAssertEqual(detector.advance(to: snapshot(attention: .approval)), [])
    }

    /// approval → question without an answered moment in between: the user
    /// was already summoned for that interruption.
    func testAttentionChangingKindAloneStaysSilent() {
        var detector = PageEventDetector()
        detector.advance(to: snapshot(attention: .approval))

        XCTAssertEqual(detector.advance(to: snapshot(attention: .question)), [])
    }

    /// Answered, then asked again: the second wait is a new summons.
    func testAttentionReappearingAfterAClearMomentNotifiesAgain() {
        var detector = PageEventDetector()
        detector.advance(to: snapshot(attention: .question))
        detector.advance(to: snapshot())

        XCTAssertEqual(detector.advance(to: snapshot(attention: .question)), [.attentionNeeded(.question)])
    }

    /// The turn-tail row is itself a new chat row, so its mounting moves the
    /// newest row — the finish must not be swallowed by that, which is why
    /// continuity is judged by the previous newest row surviving, not by the
    /// newest row standing still.
    func testATurnEndingIsNotifiedEvenThoughTheTailRowIsNew() {
        var detector = PageEventDetector()
        detector.advance(to: snapshot(turnTail: "5", recent: ["m6"]))

        XCTAssertEqual(detector.advance(to: snapshot(turnTail: "6", recent: ["m6"])), [.taskFinished(prompt: nil)])
    }

    /// A turn that starts and ends between two polls: the snapshot jumps from
    /// one finished turn to the next, with the new turn's rows in between.
    /// The previous newest row is still on screen, one window further up.
    func testATurnThatStartsAndEndsInsideOnePollIsNotified() {
        var detector = PageEventDetector()
        detector.advance(to: snapshot(turnTail: "6", recent: ["m6"]))

        XCTAssertEqual(
            detector.advance(to: snapshot(turnTail: "7", recent: ["m7", "u7", "m6"])),
            [.taskFinished(prompt: nil)]
        )
    }

    /// A page that switched conversations replaces every row: no key of the
    /// old conversation survives, so a turn-tail value appearing there is not
    /// this conversation's finish — whatever its number.
    func testAConversationSwitchNeverReportsAFinishedTurn() {
        var detector = PageEventDetector()
        detector.advance(to: snapshot(turnTail: "6", recent: ["m6"]))

        XCTAssertEqual(detector.advance(to: snapshot(turnTail: "9", recent: ["x9", "u9"])), [])
        // A different conversation that happens to sit at the same turn
        // number: the value not changing already says nothing ended here.
        XCTAssertEqual(detector.advance(to: snapshot(turnTail: "6", recent: ["x6", "u6"])), [])
    }

    /// A new turn starting only adds rows; the newest ended turn on screen is
    /// still the old one, so there is nothing to report.
    func testATurnStartingIsNotAnEvent() {
        var detector = PageEventDetector()
        detector.advance(to: snapshot(turnTail: "6", recent: ["m6"]))

        XCTAssertEqual(detector.advance(to: snapshot(turnTail: "6", recent: ["u7"])), [])
    }

    /// The tail row leaving the screen (a scroll that virtualizes it away)
    /// is not a finish; neither is it an event of any kind.
    func testTheTailDisappearingIsNotAnEvent() {
        var detector = PageEventDetector()
        detector.advance(to: snapshot(turnTail: "6", recent: ["m6"]))

        XCTAssertEqual(detector.advance(to: snapshot(turnTail: nil, recent: ["m6"])), [])
    }

    /// The turn ending while the Host waits for the user is one event, and
    /// the more informative one: "finished" alone would understate it.
    func testAttentionOutranksTheFinish() {
        var detector = PageEventDetector()
        detector.advance(to: snapshot(turnTail: "5", recent: ["m6"]))

        XCTAssertEqual(
            detector.advance(to: snapshot(attention: .planReview, turnTail: "6", recent: ["m6"])),
            [.attentionNeeded(.planReview)]
        )
    }

    /// A snapshot with no rows at all cannot vouch for any conversation, so
    /// a tail appearing after it is not attributed to a finish here.
    func testAPreviousSnapshotWithoutRowsBlocksTheFinish() {
        var detector = PageEventDetector()
        detector.advance(to: snapshot(turnTail: nil, recent: []))

        XCTAssertEqual(detector.advance(to: snapshot(turnTail: "1", recent: ["m1", "u1"])), [])
    }

    func testResetForcesANewBaseline() {
        var detector = PageEventDetector()
        detector.advance(to: snapshot(turnTail: "5", recent: ["m6"]))
        detector.reset()

        XCTAssertEqual(detector.advance(to: snapshot(turnTail: "6", recent: ["m6"])), [])
    }

    /// Two turns in one conversation: two finish events, separated by the
    /// silent start of the second.
    func testConsecutiveTurnsEachNotifyTheirOwnFinish() {
        var detector = PageEventDetector()
        detector.advance(to: snapshot(turnTail: "5", recent: ["m6"]))

        XCTAssertEqual(detector.advance(to: snapshot(turnTail: "6", recent: ["m6"])), [.taskFinished(prompt: nil)])
        XCTAssertEqual(detector.advance(to: snapshot(turnTail: "6", recent: ["u7"])), [])
        XCTAssertEqual(detector.advance(to: snapshot(turnTail: "6", recent: ["m7"])), [])
        XCTAssertEqual(detector.advance(to: snapshot(turnTail: "7", recent: ["m7"])), [.taskFinished(prompt: nil)])
    }

    /// The finish event carries the prompt read in the same poll — the frame
    /// that reports "this turn ended" is the frame that can say which task
    /// it was.
    func testTheFinishCarriesTheTaskPrompt() {
        var detector = PageEventDetector()
        detector.advance(to: snapshot(turnTail: "5", recent: ["m6"]))

        XCTAssertEqual(
            detector.advance(to: snapshot(turnTail: "6", recent: ["m6"], prompt: "帮我把这个应用打包成正式发布版")),
            [.taskFinished(prompt: "帮我把这个应用打包成正式发布版")]
        )
    }

    /// The prompt of the baseline (a page loaded showing an ended turn) is
    /// state, not news: it must not leak out as a finish event.
    func testABaselinePromptIsNotAResult() {
        var detector = PageEventDetector()
        detector.advance(to: snapshot(turnTail: "6", recent: ["m6"], prompt: "帮我重启app"))

        XCTAssertEqual(detector.advance(to: snapshot(turnTail: "6", recent: ["m7"], prompt: "帮我重启app")), [])
    }

    /// A conversation switch carries the other conversation's prompt in its
    /// snapshot; swallowed along with the would-be finish, it never surfaces.
    func testASwitchedConversationsPromptNeverSurfaces() {
        var detector = PageEventDetector()
        detector.advance(to: snapshot(turnTail: "6", recent: ["m6"], prompt: "帮我重启app"))

        XCTAssertEqual(detector.advance(to: snapshot(turnTail: "9", recent: ["x9", "u9"], prompt: "另一个任务")), [])
    }

    // MARK: - The background (sidebar rows)

    /// A background session's dot going from running to the Host's own
    /// "completed" reminder is a finish, and the row's title says which
    /// conversation finished.
    func testABackgroundSessionFinishingIsNotifiedWithTitle() {
        var detector = PageEventDetector()
        detector.advance(to: snapshot(recent: [], sidebar: [row("后台任务", .ongoing)]))

        XCTAssertEqual(
            detector.advance(to: snapshot(recent: [], sidebar: [row("后台任务", .done)])),
            [.backgroundTaskFinished(title: "后台任务")]
        )
    }

    /// A background session's waiting dot appearing is a summons; the title
    /// says which conversation is waiting.
    func testABackgroundSessionStartingToWaitIsNotifiedWithTitle() {
        var detector = PageEventDetector()
        detector.advance(to: snapshot(recent: [], sidebar: [row("后台任务", .ongoing)]))

        XCTAssertEqual(
            detector.advance(to: snapshot(recent: [], sidebar: [row("后台任务", .warning)])),
            [.backgroundAttentionNeeded(title: "后台任务")]
        )
    }

    /// A session that finishes while it waited reports the finish, not the
    /// already-known wait: one event for one occurrence.
    func testABackgroundWaitEndingInFinishReportsOnlyTheFinish() {
        var detector = PageEventDetector()
        detector.advance(to: snapshot(recent: [], sidebar: [row("后台任务", .warning)]))

        XCTAssertEqual(
            detector.advance(to: snapshot(recent: [], sidebar: [row("后台任务", .done)])),
            [.backgroundTaskFinished(title: "后台任务")]
        )
    }

    /// Whatever the first snapshot shows — a reminder left over from before
    /// the app started, a session already waiting — is where things stand.
    func testSidebarBaselineIsNotNews() {
        var detector = PageEventDetector()
        detector.advance(to: snapshot(recent: [], sidebar: [row("后台任务", .done), row("另一个", .warning)]))

        XCTAssertEqual(detector.advance(to: snapshot(recent: [], sidebar: [row("后台任务", .done)])), [])
    }

    /// The selected row is the displayed page's business; its own panels and
    /// turn-tail cover it, so the sidebar must not duplicate them.
    func testTheSelectedRowNeverReportsBackgroundEvents() {
        var detector = PageEventDetector()
        detector.advance(to: snapshot(recent: [], sidebar: [row("当前会话", .ongoing, selected: true)]))

        XCTAssertEqual(
            detector.advance(to: snapshot(recent: [], sidebar: [row("当前会话", .done, selected: true)])),
            []
        )
    }

    /// A row that just appeared — the sidebar being expanded, a page load, a
    /// rename — is state, not news, even when it carries the reminder dot.
    func testARowAppearingWithADotIsNotNews() {
        var detector = PageEventDetector()
        detector.advance(to: snapshot(recent: [], sidebar: [row("旧名", .done)]))

        // Rename: the old title vanishes, a new one arrives already done.
        XCTAssertEqual(detector.advance(to: snapshot(recent: [], sidebar: [row("新名", .done)])), [])
        // Sidebar expanded (empty before): every row is a first sighting.
        XCTAssertEqual(
            detector.advance(to: snapshot(recent: [], sidebar: [row("又出现了", .warning), row("新名", .done)])),
            []
        )
    }

    /// A row the user just switched away from gets one frame of grace: its
    /// finish in the same frame as the switch is the page's event, and the
    /// page's conversation-continuity guard has already said "same page".
    /// From the next frame on, it is background like any other.
    func testARowJustDeselectedIsGivenAFrameOfGrace() {
        var detector = PageEventDetector()
        detector.advance(to: snapshot(recent: [], sidebar: [row("A", .ongoing, selected: true)]))

        XCTAssertEqual(
            detector.advance(to: snapshot(recent: [], sidebar: [row("A", .done, selected: false), row("B", nil, selected: true)])),
            []
        )
        XCTAssertEqual(
            detector.advance(to: snapshot(recent: [], sidebar: [row("A", .done, selected: false), row("B", nil, selected: true)])),
            []
        )
    }

    /// Two background tasks in a row: two finishes, each with its own title.
    func testConsecutiveBackgroundTasksEachNotify() {
        var detector = PageEventDetector()
        detector.advance(to: snapshot(recent: [], sidebar: [row("甲", .ongoing), row("乙", .ongoing)]))

        XCTAssertEqual(
            detector.advance(to: snapshot(recent: [], sidebar: [row("甲", .done), row("乙", .ongoing)])),
            [.backgroundTaskFinished(title: "甲")]
        )
        XCTAssertEqual(
            detector.advance(to: snapshot(recent: [], sidebar: [row("甲", .done), row("乙", .ongoing)])),
            []
        )
        XCTAssertEqual(
            detector.advance(to: snapshot(recent: [], sidebar: [row("甲", .done), row("乙", .done)])),
            [.backgroundTaskFinished(title: "乙")]
        )
    }

    /// The reminder dot persisting (the user has not opened the session) does
    /// not re-notify; running again disarms it, and its next finish is news.
    func testAPersistingReminderDoesNotRenotifyAndARerunRearms() {
        var detector = PageEventDetector()
        detector.advance(to: snapshot(recent: [], sidebar: [row("后台任务", .ongoing)]))
        detector.advance(to: snapshot(recent: [], sidebar: [row("后台任务", .done)]))
        detector.advance(to: snapshot(recent: [], sidebar: [row("后台任务", .done)]))

        detector.advance(to: snapshot(recent: [], sidebar: [row("后台任务", .ongoing)]))
        XCTAssertEqual(
            detector.advance(to: snapshot(recent: [], sidebar: [row("后台任务", .done)])),
            [.backgroundTaskFinished(title: "后台任务")]
        )
    }

    /// The background's events and the page's own can land in one frame; each
    /// is its own notification.
    func testPageAndBackgroundEventsCoexist() {
        var detector = PageEventDetector()
        detector.advance(to: snapshot(turnTail: "5", recent: ["m6"], sidebar: [row("后台", .ongoing)]))

        XCTAssertEqual(
            detector.advance(to: snapshot(turnTail: "6", recent: ["m6"], prompt: "当前任务", sidebar: [row("后台", .done)])),
            [.taskFinished(prompt: "当前任务"), .backgroundTaskFinished(title: "后台")]
        )
    }

    // MARK: - The two classes of event

    /// Every event that blocks the Host on the user is a summons, whatever
    /// app state it finds — frontmost, background, minimized. Finishes are
    /// status reports, not summons.
    func testSummonsAreDistinguishableFromStatus() {
        XCTAssertTrue(PageEvent.attentionNeeded(.approval).isWaitingForUser)
        XCTAssertTrue(PageEvent.attentionNeeded(.question).isWaitingForUser)
        XCTAssertTrue(PageEvent.attentionNeeded(.planReview).isWaitingForUser)
        XCTAssertTrue(PageEvent.backgroundAttentionNeeded(title: "后台会话").isWaitingForUser)

        XCTAssertFalse(PageEvent.attentionNeeded(.none).isWaitingForUser)
        XCTAssertFalse(PageEvent.taskFinished(prompt: "任务").isWaitingForUser)
        XCTAssertFalse(PageEvent.backgroundTaskFinished(title: "后台任务").isWaitingForUser)
    }

    // MARK: - The displayed conversation's name

    /// The selected sidebar row is the Host's own name for the conversation
    /// the page is showing; the window title only stands in when the sidebar
    /// offers no selection.
    func testCurrentSessionTitlePrefersTheSelectedRow() {
        let snapshot = snapshot(
            sidebar: [row("别的会话", .ongoing), row("当前会话", .ongoing, selected: true)],
            pageTitle: "别的会话 — DSH"
        )

        XCTAssertEqual(snapshot.currentSessionTitle, "当前会话")
    }

    /// The Host renders the window title as
    /// "<conversation title> — <product name>": the segment before the last
    /// separator names the conversation, a title with no separator is the
    /// bare product name of the no-session view and names nothing.
    func testCurrentSessionTitleFallsBackToTheWindowTitle() {
        XCTAssertEqual(snapshot(pageTitle: "修复构建 — DSH").currentSessionTitle, "修复构建")
        // A session title that itself contains the separator keeps it.
        XCTAssertEqual(snapshot(pageTitle: "a — b — DSH").currentSessionTitle, "a — b")
        XCTAssertNil(snapshot(pageTitle: "DSH").currentSessionTitle)
        XCTAssertNil(snapshot(pageTitle: nil).currentSessionTitle)
        XCTAssertNil(snapshot(pageTitle: "   ").currentSessionTitle)
    }

    // MARK: - The probe's complete sidebar

    /// The probe page names every session but selects none; the displayed
    /// page's conversation is told apart by title and left to the page
    /// channel, which reports it with the turn's own words.
    func testTheDisplayedConversationsDotIsThePageChannelsBusiness() {
        var detector = PageEventDetector()
        detector.advance(to: snapshot(
            sidebar: [row("当前会话", .ongoing), row("后台会话", .ongoing)],
            pageTitle: "当前会话 — DSH"
        ))

        XCTAssertEqual(detector.advance(to: snapshot(
            sidebar: [row("当前会话", .done), row("后台会话", .done)],
            pageTitle: "当前会话 — DSH"
        )), [.backgroundTaskFinished(title: "后台会话")])

        // The same rule holds for a waiting dot: one summons, from the page
        // channel, not two.
        detector.advance(to: snapshot(
            sidebar: [row("当前会话", .ongoing), row("后台会话", .ongoing)],
            pageTitle: "当前会话 — DSH"
        ))
        XCTAssertEqual(detector.advance(to: snapshot(
            sidebar: [row("当前会话", .warning), row("后台会话", .warning)],
            pageTitle: "当前会话 — DSH"
        )), [.backgroundAttentionNeeded(title: "后台会话")])
    }

    /// A selected row is still the displayed page's own business when the
    /// probe is not feeding — the title rule and the selection rule agree.
    func testASelectedRowStaysTheDisplayedPagesBusiness() {
        var detector = PageEventDetector()
        detector.advance(to: snapshot(
            sidebar: [row("当前会话", .ongoing, selected: true), row("后台会话", .ongoing)]
        ))

        XCTAssertEqual(detector.advance(to: snapshot(
            sidebar: [row("当前会话", .done, selected: true), row("后台会话", .done)]
        )), [.backgroundTaskFinished(title: "后台会话")])
    }

    /// The probe's rows replace the displayed page's; every other field —
    /// the conversation, the panels, the window title — stays the displayed
    /// page's own reading.
    func testReplacingSidebarSwapsOnlyTheRows() {
        let original = snapshot(
            attention: .question,
            turnTail: "9",
            recent: ["k1", "k2"],
            prompt: "任务",
            sidebar: [row("部分视野", .ongoing)],
            pageTitle: "当前会话 — DSH"
        )

        let merged = original.replacingSidebar([row("全部视野", .done), row("当前会话", .ongoing)])

        XCTAssertEqual(merged.sidebar, [row("全部视野", .done), row("当前会话", .ongoing)])
        XCTAssertEqual(merged.attention, .question)
        XCTAssertEqual(merged.turnTail, "9")
        XCTAssertEqual(merged.recentContentTails, ["k1", "k2"])
        XCTAssertEqual(merged.prompt, "任务")
        XCTAssertEqual(merged.currentSessionTitle, "当前会话")
    }

    /// The probe script is the observer plus one duty: it opens what the
    /// sidebar renders on demand — collapsed groups, per-group overflows —
    /// and it posts on its own channel. The displayed page's observer
    /// never clicks anything.
    func testTheProbeScriptExpandsAndPostsOnItsOwnChannel() {
        XCTAssertTrue(PageSnapshot.probeScript.contains(PageSnapshot.probeHandlerName))
        XCTAssertTrue(PageSnapshot.probeScript.contains("var EXPANDING = true"))

        XCTAssertTrue(PageSnapshot.observerScript.contains(PageSnapshot.scriptHandlerName))
        XCTAssertTrue(PageSnapshot.observerScript.contains("var EXPANDING = false"))
        XCTAssertFalse(PageSnapshot.observerScript.contains(PageSnapshot.probeHandlerName))
        XCTAssertNotEqual(PageSnapshot.probeScript, PageSnapshot.observerScript)
    }
}
