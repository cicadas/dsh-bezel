import XCTest
@testable import BezelCore

/// Every rule of `PageRenewal` is a promise about when the app will and will
/// not reload the page behind the user's back. These tests are those
/// promises, fact by fact.
final class PageRenewalTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func facts(
        now: Date,
        lastLoad: Date? = nil,
        visible: Bool = false,
        summons: Bool = false,
        lastRenewal: Date? = nil
    ) -> PageRenewal.Facts {
        PageRenewal.Facts(
            now: now,
            lastLoad: lastLoad,
            windowVisible: visible,
            summonsActive: summons,
            lastRenewal: lastRenewal
        )
    }

    func testNothingLoadedMeansNothingToRenew() {
        XCTAssertFalse(PageRenewal.isDue(facts(now: now)))
    }

    func testAFreshPageStays() {
        let loaded = facts(now: now, lastLoad: now.addingTimeInterval(-3600))
        XCTAssertFalse(PageRenewal.isDue(loaded))
    }

    func testADayOldPageRenews() {
        let aged = facts(now: now, lastLoad: now.addingTimeInterval(-(PageRenewal.interval + 60)))
        XCTAssertTrue(PageRenewal.isDue(aged))
    }

    func testAVisibleWindowIsNeverTornDown() {
        // The page may hold an unsent composer draft; a reload the user can
        // see is a reload that can destroy it. The renewal waits in the
        // background, as asked.
        let visible = facts(
            now: now,
            lastLoad: now.addingTimeInterval(-(PageRenewal.interval * 2)),
            visible: true
        )
        XCTAssertFalse(PageRenewal.isDue(visible))
    }

    func testAnOpenSummonsBeatsTheHousekeeping() {
        let waiting = facts(
            now: now,
            lastLoad: now.addingTimeInterval(-(PageRenewal.interval * 2)),
            summons: true
        )
        XCTAssertFalse(PageRenewal.isDue(waiting))
    }

    func testTheCooldownCapsRenewalRate() {
        let recent = facts(
            now: now,
            lastLoad: now.addingTimeInterval(-(PageRenewal.interval * 2)),
            lastRenewal: now.addingTimeInterval(-1800)
        )
        XCTAssertFalse(PageRenewal.isDue(recent))
        // And once the hour has passed, the same facts do renew.
        let settled = facts(
            now: now,
            lastLoad: now.addingTimeInterval(-(PageRenewal.interval * 2)),
            lastRenewal: now.addingTimeInterval(-(PageRenewal.cooldown + 60))
        )
        XCTAssertTrue(PageRenewal.isDue(settled))
    }
}
