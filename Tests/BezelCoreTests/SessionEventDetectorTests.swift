import XCTest
@testable import BezelCore

/// The detector's rules are the notification product's behaviour: baselines,
/// edges, dedupe. Everything here is a fact the feed could plausibly deliver
/// in the order it could deliver it.
final class SessionEventDetectorTests: XCTestCase {
    func testFirstSnapshotIsBaselineNotNews() {
        var detector = SessionEventDetector()
        let baseline = detector.advance(.sessions([
            HostSession(id: "a", title: "Already running", running: true),
            HostSession(id: "b", title: "Idle", running: false),
        ]))
        XCTAssertTrue(baseline.isEmpty)
    }

    func testRunningFallIsAFinish() {
        var detector = SessionEventDetector()
        _ = detector.advance(.sessions([HostSession(id: "a", title: "Task", running: true)]))
        XCTAssertEqual(
            detector.advance(.runningChanged(id: "a", running: false)),
            [.turnFinished(session: "Task")]
        )
    }

    func testRunningStartIsNotNews() {
        var detector = SessionEventDetector()
        _ = detector.advance(.sessions([HostSession(id: "a", title: "Task", running: false)]))
        XCTAssertTrue(detector.advance(.runningChanged(id: "a", running: true)).isEmpty)
    }

    func testSnapshotCatchesUpAnEdgeMissedWhileDisconnected() {
        var detector = SessionEventDetector()
        _ = detector.advance(.sessions([HostSession(id: "a", title: "Task", running: true)]))
        XCTAssertEqual(
            detector.advance(.sessions([HostSession(id: "a", title: "Task", running: false)])),
            [.turnFinished(session: "Task")]
        )
    }

    func testTitlesRefreshWithSnapshots() {
        var detector = SessionEventDetector()
        _ = detector.advance(.sessions([HostSession(id: "a", title: nil, running: true)]))
        _ = detector.advance(.sessions([HostSession(id: "a", title: "Named now", running: true)]))
        XCTAssertEqual(
            detector.advance(.runningChanged(id: "a", running: false)),
            [.turnFinished(session: "Named now")]
        )
    }

    func testSummonsNotifiesEvenBeforeBaseline() {
        var detector = SessionEventDetector()
        XCTAssertEqual(
            detector.advance(.summons(sessionId: "a", kind: .approval, eventId: "e1")),
            [.waitingForUser(.approval, session: nil)]
        )
    }

    func testSummonsCarriesTheSessionsTitle() {
        var detector = SessionEventDetector()
        _ = detector.advance(.sessions([HostSession(id: "a", title: "Backend fix", running: true)]))
        XCTAssertEqual(
            detector.advance(.summons(sessionId: "a", kind: .question, eventId: "e1")),
            [.waitingForUser(.question, session: "Backend fix")]
        )
    }

    func testRedeliveredSummonsIsOneSummons() {
        var detector = SessionEventDetector()
        _ = detector.advance(.summons(sessionId: "a", kind: .approval, eventId: "e1"))
        XCTAssertTrue(detector.advance(.summons(sessionId: "a", kind: .approval, eventId: "e1")).isEmpty)
    }

    func testAnsweredSummonsClearsSoANewOneCanFire() {
        var detector = SessionEventDetector()
        _ = detector.advance(.summons(sessionId: "a", kind: .approval, eventId: "e1"))
        XCTAssertTrue(detector.advance(.summonsEnded(eventId: "e1")).isEmpty)
        XCTAssertEqual(
            detector.advance(.summons(sessionId: "a", kind: .approval, eventId: "e2")),
            [.waitingForUser(.approval, session: nil)]
        )
    }

    func testResetRestoresTheBaseline() {
        var detector = SessionEventDetector()
        _ = detector.advance(.sessions([HostSession(id: "a", title: "Task", running: true)]))
        detector.reset()
        XCTAssertTrue(detector.advance(.sessions([HostSession(id: "a", title: "Task", running: false)])).isEmpty)
    }

    func testFailuresAreStateNotNews() {
        var detector = SessionEventDetector()
        XCTAssertTrue(detector.advance(.failed(.transport("boom"))).isEmpty)
        XCTAssertTrue(detector.advance(.failed(.unauthorized)).isEmpty)
    }
}
