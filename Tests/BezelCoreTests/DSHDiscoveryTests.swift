import XCTest
@testable import BezelCore

final class DSHDiscoveryTests: XCTestCase {
    // MARK: - Login shell probe

    func testProbeParsingReadsBothValues() {
        let output = "<<<dsh-probe>>>\n/Users/me/.local/bin/dsh\n/usr/local/bin:/usr/bin\n"
        let shell = LoginShell.parse(output)
        XCTAssertEqual(shell?.dshPath, "/Users/me/.local/bin/dsh")
        XCTAssertEqual(shell?.path, "/usr/local/bin:/usr/bin")
    }

    func testProbeParsingIgnoresChatterPrintedBeforeTheSentinel() {
        // An rc file that prints on stdout must not be mistaken for the answer.
        let output = "Welcome to zsh!\nconda initialized\n<<<dsh-probe>>>\n/opt/bin/dsh\n/opt/bin:/usr/bin\n"
        let shell = LoginShell.parse(output)
        XCTAssertEqual(shell?.dshPath, "/opt/bin/dsh")
        XCTAssertEqual(shell?.path, "/opt/bin:/usr/bin")
    }

    func testProbeParsingTreatsNoDSHAsNilButKeepsPATH() {
        let shell = LoginShell.parse("<<<dsh-probe>>>\n\n/usr/bin:/bin\n")
        XCTAssertNil(shell?.dshPath)
        XCTAssertEqual(shell?.path, "/usr/bin:/bin")
    }

    func testProbeParsingWithoutSentinelIsNil() {
        XCTAssertNil(LoginShell.parse("dsh: command not found\n"))
        XCTAssertNil(LoginShell.parse(""))
    }

    /// A truncated probe still yields what it did report; the PATH simply
    /// stays unknown and the caller falls back to the conventional
    /// directories, which is strictly better than discarding the answer.
    func testProbeParsingKeepsDSHWhenThePATHLineIsMissing() {
        let shell = LoginShell.parse("<<<dsh-probe>>>\n/only/one/line\n")
        XCTAssertEqual(shell?.dshPath, "/only/one/line")
        XCTAssertNil(shell?.path)
    }

    // MARK: - Candidate ordering

    private func host(dshPath: String = "") -> DSHHost {
        DSHHost(name: "t", baseURL: "http://127.0.0.1:3080", managed: true, dshPath: dshPath)
    }

    func testCandidatesPreferTheMostSpecificSource() {
        let shell = LoginShell(dshPath: "/shell/dsh", path: "/shell/bin")
        let candidates = DSHDiscovery.candidates(
            host: host(dshPath: "/bookmark/dsh"),
            environment: ["PATH": "/app/bin", "BEZEL_DSH_PATH": "/env/dsh"],
            loginShell: shell,
            path: DSHDiscovery.childPath(base: ["PATH": "/app/bin"], loginShell: shell, pathAdditions: []),
            wellKnown: DSHDiscovery.wellKnownDirectories(home: "/home/me")
        )
        XCTAssertEqual(
            Array(candidates.prefix(5)),
            [
                DSHCandidate(executable: "/bookmark/dsh", origin: .hostSetting),
                DSHCandidate(executable: "/env/dsh", origin: .environmentOverride),
                DSHCandidate(executable: "/shell/dsh", origin: .loginShell),
                // A directory the login shell's PATH contributed is labelled
                // as such, not as an app PATH hit.
                DSHCandidate(executable: "/shell/bin/dsh", origin: .loginShell),
                DSHCandidate(executable: "/app/bin/dsh", origin: .appPath),
            ]
        )
        // Conventional directories come last, and include where Homebrew puts
        // node on Apple silicon.
        XCTAssertTrue(candidates.contains(DSHCandidate(executable: "/opt/homebrew/bin/dsh", origin: .wellKnown)))
        XCTAssertEqual(candidates.last?.origin, .wellKnown)
    }

    func testCandidatesDeduplicateKeepingTheHigherPriorityOrigin() {
        let shell = LoginShell(dshPath: "/same/dsh", path: "/same")
        let candidates = DSHDiscovery.candidates(
            host: host(dshPath: "/same/dsh"),
            environment: ["PATH": "/same", "BEZEL_DSH_PATH": "/same/dsh"],
            loginShell: shell,
            path: DSHDiscovery.childPath(base: ["PATH": "/same"], loginShell: shell, pathAdditions: []),
            wellKnown: []
        )
        let matches = candidates.filter { $0.executable == "/same/dsh" }
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.origin, .hostSetting)
    }

    func testCandidatesSkipBlankSettings() {
        let candidates = DSHDiscovery.candidates(
            host: host(dshPath: "   "),
            environment: ["PATH": ""],
            loginShell: nil,
            path: DSHDiscovery.childPath(base: ["PATH": ""], pathAdditions: []),
            wellKnown: []
        )
        XCTAssertFalse(candidates.contains { $0.executable.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    /// A directory merged into the child PATH as a conventional install
    /// location must not masquerade as an "app PATH" hit: diagnostics label
    /// the candidate by where the directory actually came from.
    func testMergedDirectoriesKeepTheirOwnOrigin() {
        let candidates = DSHDiscovery.candidates(
            host: host(),
            environment: [:],
            loginShell: nil,
            path: DSHDiscovery.childPath(
                base: ["PATH": "/app/bin"],
                loginShell: LoginShell(dshPath: nil, path: "/shell/bin"),
                pathAdditions: ["/opt/homebrew/bin"]
            ),
            wellKnown: []
        )
        XCTAssertEqual(
            candidates.map(\.executable),
            ["/shell/bin/dsh", "/app/bin/dsh", "/opt/homebrew/bin/dsh"]
        )
        XCTAssertEqual(
            candidates.map(\.origin),
            [.loginShell, .appPath, .wellKnown]
        )
    }

    // MARK: - Child environment

    func testChildEnvironmentMergesShellPathThenAppPathThenConventional() {
        let environment = DSHDiscovery.childEnvironment(
            base: ["HOME": "/home/me", "PATH": "/app/bin:/shared"],
            loginShell: LoginShell(dshPath: nil, path: "/shell/bin:/shared"),
            pathAdditions: ["/well/known"]
        )
        // Shell entries first (that is what the user's terminal would use),
        // then inherited entries, then interpreter directories; duplicates
        // dropped, first occurrence wins.
        XCTAssertEqual(environment["PATH"], "/shell/bin:/shared:/app/bin:/well/known")
        XCTAssertEqual(environment["HOME"], "/home/me")
    }

    func testWellKnownDirectoriesCoverHomebrewAndLocalBin() {
        let directories = DSHDiscovery.wellKnownDirectories(home: "/home/me")
        XCTAssertTrue(directories.contains("/opt/homebrew/bin"))
        XCTAssertTrue(directories.contains("/home/me/.local/bin"))
        XCTAssertTrue(directories.contains("/home/me/bin"))
    }

    /// The directories injected into the child's `PATH` are the ones that
    /// supply an *interpreter*. Injecting a directory that only holds another
    /// `dsh` lets a launcher that scans `PATH` hand the launch to a broken
    /// wrapper instead of running itself.
    func testPathAdditionsExcludeDirectoriesThatOnlyHoldAnotherDSH() {
        let additions = DSHDiscovery.pathAdditions(home: "/home/me")
        XCTAssertTrue(additions.contains("/opt/homebrew/bin"))
        XCTAssertFalse(additions.contains("/home/me/.local/bin"))
        XCTAssertFalse(additions.contains("/home/me/bin"))
        // The candidate list keeps them, though: a dsh sitting there is still
        // worth running directly.
        let candidates = DSHDiscovery.candidates(
            host: host(),
            environment: [:],
            loginShell: nil,
            path: DSHDiscovery.childPath(base: ["PATH": "/usr/bin"], pathAdditions: additions),
            wellKnown: DSHDiscovery.wellKnownDirectories(home: "/home/me")
        )
        XCTAssertTrue(candidates.contains(DSHCandidate(executable: "/home/me/.local/bin/dsh", origin: .wellKnown)))
        XCTAssertTrue(candidates.contains(DSHCandidate(executable: "/home/me/bin/dsh", origin: .wellKnown)))
    }

    // MARK: - Executable lookup

    /// `findExecutable` walks the merged child `PATH` in the same order the
    /// managed child itself gets — that order is the whole point of reusing
    /// it for the guide's `npm`.
    func testFindExecutableWalksTheMergedPathInOrder() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bezel-findexec-\(UUID().uuidString)")
        let shellDirectory = directory.appendingPathComponent("shell-bin")
        let appDirectory = directory.appendingPathComponent("app-bin")
        let inShell = try makeExecutable(named: "probe-tool", in: shellDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try makeExecutable(named: "probe-tool", in: appDirectory)

        let found = DSHDiscovery.findExecutable(
            named: "probe-tool",
            base: ["PATH": appDirectory.path],
            loginShell: LoginShell(dshPath: nil, path: shellDirectory.path),
            pathAdditions: []
        )
        XCTAssertEqual(found, inShell.path)
    }

    func testFindExecutableReturnsNilWhenNowhereOnThePath() {
        XCTAssertNil(DSHDiscovery.findExecutable(
            named: "bezel-no-such-tool-anywhere",
            base: ["PATH": "/nonexistent"],
            loginShell: nil,
            pathAdditions: []
        ))
        // A name with a separator is not a name to look up.
        XCTAssertNil(DSHDiscovery.findExecutable(named: "/bin/ls", base: [:], loginShell: nil, pathAdditions: []))
    }

    // MARK: - Search

    /// The regression this whole file exists for: a candidate that exists and
    /// has the execute bit set but cannot actually run must not stop the
    /// search. Every `dsh` on a real machine is a shim whose interpreter may
    /// be unreachable.
    func testLocateSkipsACandidateThatExistsButDoesNotRun() throws {
        let first = try makeExecutable(named: "first-dsh")
        let second = try makeExecutable(named: "second-dsh")
        defer { try? FileManager.default.removeItem(at: first.deletingLastPathComponent()) }

        let report = DSHDiscovery.locate(
            host: host(dshPath: first.path),
            environment: ["PATH": "/nonexistent"],
            loginShell: LoginShell(dshPath: second.path, path: "/nonexistent"),
            wellKnown: [],
            pathAdditions: [],
            // Only the second candidate is runnable.
            probe: { path, _ in path == second.path }
        )

        XCTAssertEqual(report.chosen?.executable, second.path)
        XCTAssertEqual(report.chosen?.origin, .loginShell)
        XCTAssertEqual(report.attempts.first?.reason, .didNotRun)
        XCTAssertEqual(report.attempts.first?.candidate.executable, first.path)
        XCTAssertEqual(report.attempts.last?.reason, .selected)
    }

    func testLocateReportsEveryAttemptWhenNothingRuns() throws {
        let only = try makeExecutable(named: "only-dsh")
        defer { try? FileManager.default.removeItem(at: only.deletingLastPathComponent()) }

        let report = DSHDiscovery.locate(
            host: host(dshPath: only.path),
            environment: ["PATH": "/nonexistent"],
            loginShell: nil,
            wellKnown: [],
            pathAdditions: [],
            probe: { _, _ in false }
        )

        XCTAssertNil(report.chosen)
        XCTAssertEqual(report.attempts.first?.reason, .didNotRun)
        // A missing file is reported as such rather than probed.
        XCTAssertTrue(report.attempts.dropFirst().allSatisfy { $0.reason == .notExecutable })
        // Wording belongs to LocalizationTests; here the shape matters.
        let lines = report.diagnosticLines(Localization())
        XCTAssertTrue(lines.contains { $0.contains(only.path) })
        XCTAssertTrue(lines.contains { $0.contains("/nonexistent") })
    }

    func testDiagnosticLinesNameTheChosenSource() throws {
        let runnable = try makeExecutable(named: "chosen-dsh")
        defer { try? FileManager.default.removeItem(at: runnable.deletingLastPathComponent()) }

        let report = DSHDiscovery.locate(
            host: host(dshPath: runnable.path),
            environment: ["PATH": "/nonexistent"],
            loginShell: nil,
            wellKnown: [],
            pathAdditions: [],
            probe: { path, _ in path == runnable.path }
        )

        // Named in the requested language, and naming its source.
        let rebuilt = DSHDiscovery.Report(
            chosen: report.chosen,
            environment: report.environment,
            attempts: report.attempts
        )
        let localization = Localization(language: .simplifiedChinese)
        XCTAssertEqual(
            rebuilt.diagnosticLines(localization).first,
            "dsh: \(runnable.path)（来源：Host 设置）"
        )
    }

    /// The probe is handed the merged environment, not the app's own: that is
    /// what makes a shim with an unreachable interpreter resolvable at all.
    func testProbeReceivesTheMergedEnvironment() throws {
        let runnable = try makeExecutable(named: "env-dsh")
        defer { try? FileManager.default.removeItem(at: runnable.deletingLastPathComponent()) }

        var seen: [String: String] = [:]
        _ = DSHDiscovery.locate(
            host: host(dshPath: runnable.path),
            environment: ["PATH": "/app/bin"],
            loginShell: LoginShell(dshPath: nil, path: "/shell/bin"),
            wellKnown: DSHDiscovery.wellKnownDirectories(home: "/home/me"),
            probe: { _, environment in
                seen = environment
                return true
            }
        )

        let path = try XCTUnwrap(seen["PATH"])
        XCTAssertTrue(path.hasPrefix("/shell/bin:/app/bin"))
        XCTAssertTrue(path.contains("/opt/homebrew/bin"))
    }

    /// The search is bounded as a whole: candidates the budget does not reach
    /// are recorded as skipped rather than keeping the app "locating" for
    /// minutes on a machine full of broken candidates.
    func testCandidatesBeyondTheBudgetAreSkippedNotProbed() throws {
        let runnable = try makeExecutable(named: "budget-dsh")
        defer { try? FileManager.default.removeItem(at: runnable.deletingLastPathComponent()) }

        var probed = 0
        let report = DSHDiscovery.locate(
            host: host(dshPath: runnable.path),
            environment: ["PATH": "/nonexistent"],
            loginShell: nil,
            wellKnown: [],
            pathAdditions: [],
            budget: 0,
            probe: { _, _ in
                probed += 1
                return true
            }
        )

        XCTAssertNil(report.chosen)
        XCTAssertEqual(probed, 0)
        XCTAssertEqual(report.attempts.first?.reason, .skipped)
        XCTAssertTrue(report.attempts.allSatisfy { $0.reason == .skipped || $0.reason == .notExecutable })
    }

    private func makeExecutable(named name: String, in directory: URL? = nil) throws -> URL {
        let container = directory ?? URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bezel-discovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let file = container.appendingPathComponent(name)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }
}
