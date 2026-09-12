import XCTest
@testable import BezelCore

/// The one-shot runner the guide's automatic install goes through.
@MainActor
final class OneShotCommandTests: XCTestCase {
    func testARunReportsItsOutputAndStatus() async {
        let command = OneShotCommand()
        let outcome = await command.run(
            executable: "/bin/sh",
            arguments: ["-c", "echo first; echo second"],
            timeout: 10
        )

        XCTAssertTrue(outcome.succeeded)
        XCTAssertEqual(outcome.status, 0)
        XCTAssertEqual(command.lines, ["first", "second"])
        XCTAssertFalse(command.isRunning)
    }

    func testAFailingRunReportsItsStatus() async {
        let command = OneShotCommand()
        let outcome = await command.run(
            executable: "/bin/sh",
            arguments: ["-c", "echo oops >&2; exit 3"],
            timeout: 10
        )

        XCTAssertFalse(outcome.succeeded)
        XCTAssertEqual(outcome.status, 3)
        XCTAssertEqual(command.lines, ["oops"])
    }

    /// A command that never finishes is ended by the deadline, not waited
    /// out forever — and says so.
    func testARunThatOverrunsItsDeadlineIsTerminated() async {
        let command = OneShotCommand()
        let outcome = await command.run(
            executable: "/bin/sleep",
            arguments: ["30"],
            timeout: 0.2
        )

        XCTAssertFalse(outcome.succeeded)
        XCTAssertTrue(outcome.timedOut)
        XCTAssertFalse(command.isRunning)
    }

    func testACommandThatCannotRunSaysWhy() async {
        let command = OneShotCommand()
        let outcome = await command.run(
            executable: "/nonexistent/bezel-one-shot",
            arguments: [],
            timeout: 10
        )

        XCTAssertFalse(outcome.succeeded)
        XCTAssertNotNil(outcome.launchError)
        XCTAssertFalse(command.isRunning)
    }

    /// A second run must not charge its outcome to the first: the awaiter of
    /// the run in flight is answered, and only the new run's output shows.
    func testASecondRunSupersedesTheOneInFlight() async {
        let command = OneShotCommand()
        let first = Task {
            await command.run(executable: "/bin/sleep", arguments: ["30"], timeout: 30)
        }
        // Let the first run actually start before superseding it.
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(command.isRunning)

        let second = await command.run(
            executable: "/bin/sh",
            arguments: ["-c", "echo second"],
            timeout: 10
        )
        XCTAssertTrue(second.succeeded)

        let firstOutcome = await first.value
        XCTAssertTrue(firstOutcome.cancelled)
        XCTAssertFalse(firstOutcome.succeeded)
        XCTAssertEqual(command.lines, ["second"])
    }

    func testCancelEndsTheRunInFlight() async {
        let command = OneShotCommand()
        let run = Task {
            await command.run(executable: "/bin/sleep", arguments: ["30"], timeout: 30)
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        command.cancel()

        let outcome = await run.value
        XCTAssertFalse(outcome.succeeded)
        XCTAssertFalse(outcome.cancelled)
        XCTAssertFalse(command.isRunning)
    }
}
