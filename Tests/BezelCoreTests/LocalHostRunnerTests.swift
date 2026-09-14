import XCTest
@testable import BezelCore

final class LocalHostRunnerTests: XCTestCase {
    func testParsesAnnouncedURL() {
        let line = "dsh web: http://127.0.0.1:51234/?token=abc123"
        XCTAssertEqual(
            LocalHostRunner.announcedURL(in: line)?.absoluteString,
            "http://127.0.0.1:51234/?token=abc123"
        )
    }

    /// The LAN hint must not be mistaken for the announced URL itself.
    func testParsesAnnouncedURLWhenTheLANHintFollows() {
        let line = "dsh web: http://127.0.0.1:51234/?token=abc123 (LAN: http://10.0.0.5:51234/?token=abc123)"
        XCTAssertEqual(
            LocalHostRunner.announcedURL(in: line)?.absoluteString,
            "http://127.0.0.1:51234/?token=abc123"
        )
    }

    func testIgnoresOutputWithoutAStartupLine() {
        XCTAssertNil(LocalHostRunner.announcedURL(in: "dsh: loading profile web"))
        XCTAssertNil(LocalHostRunner.announcedURL(in: "dsh web: (no url yet)"))
    }

    // MARK: - Connect action

    /// An external Host is only ever attached to, whatever this runner is up to.
    func testAnExternalHostIsOnlyEverConnectedTo() {
        let host = DSHHost(baseURL: "http://127.0.0.1:3080", managed: false)
        XCTAssertEqual(
            LocalHostRunner.connectAction(
                for: host,
                runnerHostID: host.id,
                phase: .running(URL(string: "http://127.0.0.1:53080")!)
            ),
            .connect
        )
    }

    /// A restart is offered exactly while a child *of this Host* is alive; a
    /// child belonging to another Host does not turn a start into a restart.
    func testARestartIsOfferedOnlyWhileThisHostsChildIsAlive() {
        let host = DSHHost(baseURL: "http://127.0.0.1:3080", managed: true)
        let other = DSHHost(baseURL: "http://127.0.0.1:3081", managed: true)
        let url = URL(string: "http://127.0.0.1:53080")!
        XCTAssertEqual(LocalHostRunner.connectAction(for: host, runnerHostID: nil, phase: .starting), .startManaged)
        XCTAssertEqual(LocalHostRunner.connectAction(for: host, runnerHostID: other.id, phase: .running(url)), .startManaged)
        XCTAssertEqual(LocalHostRunner.connectAction(for: host, runnerHostID: host.id, phase: .starting), .restartManaged)
        XCTAssertEqual(LocalHostRunner.connectAction(for: host, runnerHostID: host.id, phase: .running(url)), .restartManaged)
    }

    /// Nothing alive to replace is a fresh launch: from idle, during the
    /// executable search (no child yet), and after a failure alike.
    func testAFreshStartIsOfferedWhenNoChildIsAlive() {
        let host = DSHHost(baseURL: "http://127.0.0.1:3080", managed: true)
        XCTAssertEqual(LocalHostRunner.connectAction(for: host, runnerHostID: host.id, phase: .idle), .startManaged)
        XCTAssertEqual(LocalHostRunner.connectAction(for: host, runnerHostID: host.id, phase: .locating), .startManaged)
        XCTAssertEqual(
            LocalHostRunner.connectAction(for: host, runnerHostID: host.id, phase: .failed(.timedOut(seconds: 30))),
            .startManaged
        )
    }

    /// The instance view of the same fact, across one child's whole life:
    /// start before it exists, restart while it is alive, start again once
    /// `stop()` has taken it down.
    @MainActor
    func testConnectActionFollowsTheChildsLife() async throws {
        let fake = try makeFakeDSH()
        defer { try? FileManager.default.removeItem(at: fake.url.deletingLastPathComponent()) }

        let host = DSHHost(baseURL: "http://127.0.0.1:3080", managed: true, launchCommand: fake.url.path)
        let runner = LocalHostRunner()
        defer { runner.stop() }
        XCTAssertEqual(runner.connectAction(for: host), .startManaged)

        runner.start(host: host) { _ in }
        let announced = await waitFor(30) {
            if case .running = runner.phase { return true }
            return nil
        }
        XCTAssertEqual(announced, true, "expected the fake dsh to announce its URL")
        XCTAssertEqual(runner.connectAction(for: host), .restartManaged)

        runner.stop()
        XCTAssertEqual(runner.connectAction(for: host), .startManaged)
    }

    // MARK: - Live launches

    /// A stand-in for `dsh`: prints the startup line, records its pid, then
    /// stays alive until killed.
    private func makeFakeDSH() throws -> (url: URL, pidFile: URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bezel-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("fake-dsh.sh")
        let pidFile = directory.appendingPathComponent("child.pid")
        try Data("""
        #!/bin/sh
        echo "dsh web: http://127.0.0.1:53080/?token=t"
        echo $$ > '\(pidFile.path)'
        while true; do sleep 5; done
        """.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return (script, pidFile)
    }

    @MainActor
    private func waitFor<T>(_ deadline: TimeInterval, _ body: () async -> T?) async -> T? {
        let end = Date().addingTimeInterval(deadline)
        while Date() < end {
            if let value = await body() { return value }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return nil
    }

    /// The whole manual launch, direct mode: the command runs, its startup
    /// line becomes the running phase's URL, and `stop()` kills the child —
    /// which is the promise managed mode is built on.
    @MainActor
    func testADirectManualCommandRunsAnnouncesAndDiesOnStop() async throws {
        let fake = try makeFakeDSH()
        defer { try? FileManager.default.removeItem(at: fake.url.deletingLastPathComponent()) }

        let runner = LocalHostRunner()
        defer { runner.stop() }
        var announced: URL?
        runner.start(
            host: DSHHost(baseURL: "http://127.0.0.1:3080", managed: true, launchCommand: fake.url.path)
        ) { announced = $0 }

        let phase = await waitFor(30) {
            if case .running = runner.phase { return runner.phase }
            return nil
        }
        guard case .running(let url) = phase else {
            return XCTFail("expected running, got \(runner.phase)")
        }
        XCTAssertEqual(url.absoluteString, "http://127.0.0.1:53080/?token=t")
        XCTAssertEqual(announced?.absoluteString, "http://127.0.0.1:53080/?token=t")

        // The process the runner holds is the script itself, so terminate()
        // reaches it directly.
        let pid = try XCTUnwrap(Int(try String(contentsOf: fake.pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        runner.stop()
        let died = await waitFor(5) {
            kill(pid_t(pid), 0) != 0 ? true : nil
        }
        XCTAssertTrue(died == true, "the child should have died with the runner's stop()")
        if case .idle = runner.phase {} else {
            XCTFail("expected idle after stop, got \(runner.phase)")
        }
    }

    /// The whole manual launch, shell mode: a command with shell syntax runs
    /// through the signal-forwarding wrapper — the URL still arrives, and a
    /// stop() that can only signal the *shell* still takes the child down
    /// with it.
    @MainActor
    func testAShellManualCommandForwardsTheKillToTheChild() async throws {
        let fake = try makeFakeDSH()
        defer { try? FileManager.default.removeItem(at: fake.url.deletingLastPathComponent()) }

        let runner = LocalHostRunner()
        defer { runner.stop() }
        // The leading echo is what forces the shell plan (and proves the
        // wrapper passes the child's output through untouched).
        let command = "echo starting; '\(fake.url.path)' --profile web"
        runner.start(
            host: DSHHost(baseURL: "http://127.0.0.1:3080", managed: true, launchCommand: command)
        ) { _ in }

        let phase = await waitFor(30) {
            if case .running = runner.phase { return runner.phase }
            return nil
        }
        guard case .running(let url) = phase else {
            return XCTFail("expected running, got \(runner.phase)")
        }
        XCTAssertEqual(url.absoluteString, "http://127.0.0.1:53080/?token=t")

        let pid = try XCTUnwrap(Int(try String(contentsOf: fake.pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        runner.stop()
        let died = await waitFor(5) {
            kill(pid_t(pid), 0) != 0 ? true : nil
        }
        XCTAssertTrue(died == true, "the wrapper should have forwarded the stop to the child")
    }

    /// The pipeline case, which is the one the wrapper was getting wrong.
    ///
    /// `$!` after a backgrounded pipeline is its *last* element, so a trap
    /// that signalled `$!` killed the `tee` and left the dsh running — with
    /// the app quit, its child still holding the port. The trap signals the
    /// whole job now, and this is the test that would have caught it.
    @MainActor
    func testAPipelineManualCommandStillTakesTheChildDown() async throws {
        let fake = try makeFakeDSH()
        let log = fake.url.deletingLastPathComponent().appendingPathComponent("tee.log")
        defer { try? FileManager.default.removeItem(at: fake.url.deletingLastPathComponent()) }

        let runner = LocalHostRunner()
        defer { runner.stop() }
        let command = "'\(fake.url.path)' --profile web 2>&1 | tee '\(log.path)'"
        runner.start(
            host: DSHHost(baseURL: "http://127.0.0.1:3080", managed: true, launchCommand: command)
        ) { _ in }

        // The URL still has to arrive: `tee` passes the child's stdout through.
        let phase = await waitFor(30) {
            if case .running = runner.phase { return runner.phase }
            return nil
        }
        guard case .running(let url) = phase else {
            return XCTFail("expected running, got \(runner.phase)")
        }
        XCTAssertEqual(url.absoluteString, "http://127.0.0.1:53080/?token=t")

        let pid = try XCTUnwrap(Int(try String(contentsOf: fake.pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        runner.stop()
        let died = await waitFor(5) {
            kill(pid_t(pid), 0) != 0 ? true : nil
        }
        XCTAssertTrue(died == true, "the dsh in a pipeline must die with the wrapper, not just the tee")
    }

    // MARK: - Custom launch commands

    private func makeExecutable(named name: String, in directory: URL? = nil) throws -> URL {
        let container = directory ?? URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bezel-runner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let file = container.appendingPathComponent(name)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }

    /// A plain command is exec'd directly — that is what makes `terminate()`
    /// reach the dsh itself rather than a shell holding it. The bare name is
    /// resolved along the merged child `PATH` (here: a directory of this
    /// test's own), so the launch does not depend on where the app itself
    /// was started from.
    func testABareNameIsResolvedAlongTheMergedPathAndRunsDirectly() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bezel-runner-\(UUID().uuidString)")
        let dsh = try makeExecutable(named: "dsh", in: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let plan = LocalHostRunner.manualLaunch(
            command: "dsh --profile web --port 0 --no-open",
            loginShell: LoginShell(dshPath: nil, path: directory.path),
            base: ["PATH": "/nonexistent"]
        )
        XCTAssertEqual(
            plan,
            LocalHostRunner.LaunchPlan.direct(executable: dsh.path, arguments: ["--profile", "web", "--port", "0", "--no-open"])
        )
    }

    func testAPathCommandRunsDirectlyWithoutLookup() {
        XCTAssertEqual(
            LocalHostRunner.manualLaunch(command: "\"/opt/my dsh/dsh\" web", base: [:]),
            LocalHostRunner.LaunchPlan.direct(executable: "/opt/my dsh/dsh", arguments: ["web"])
        )
    }

    func testAnUnresolvableBareNameFallsBackToTheShell() {
        let plan = LocalHostRunner.manualLaunch(command: "my-custom-launcher web", base: ["PATH": "/nonexistent"])
        guard case .shell(let script) = plan else {
            return XCTFail("expected a shell plan, got \(String(describing: plan))")
        }
        XCTAssertTrue(script.hasPrefix("my-custom-launcher web &\n"))
    }

    /// Shell syntax must run in a shell — and through the wrapper, so a
    /// SIGTERM to the process the app holds is forwarded to the dsh.
    func testShellSyntaxRunsThroughTheForwardingWrapper() {
        let plan = LocalHostRunner.manualLaunch(command: "cd ~/x && dsh web", base: [:])
        guard case .shell(let script) = plan else {
            return XCTFail("expected a shell plan, got \(String(describing: plan))")
        }
        XCTAssertTrue(script.contains("cd ~/x && dsh web"))
        XCTAssertTrue(script.contains("kill -TERM %%"), script)
        XCTAssertTrue(script.contains("TERM INT HUP EXIT"), script)
    }

    /// The standard invocation the app composes itself: port 0 lets the
    /// system choose, and the URL comes from the child's startup line.
    func testStandardArguments() {
        XCTAssertEqual(
            LocalHostRunner.standardArguments(for: DSHHost(baseURL: "http://127.0.0.1:3080", managed: true)),
            ["--profile", "web", "--port", "0", "--no-open"]
        )
        XCTAssertEqual(
            LocalHostRunner.standardArguments(for: DSHHost(baseURL: "http://127.0.0.1:3080", managed: true, profile: "  ", extraArguments: "--patch ./x.yml")),
            ["--profile", "web", "--port", "0", "--no-open", "--patch", "./x.yml"]
        )
    }

    func testABlankCommandHasNoPlan() {
        XCTAssertNil(LocalHostRunner.manualLaunch(command: "  ", base: [:]))
    }
}
