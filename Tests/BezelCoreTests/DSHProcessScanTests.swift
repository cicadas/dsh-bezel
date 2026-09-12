import XCTest
@testable import BezelCore

/// The rule that decides whether the guide says "a dsh process is running".
///
/// Every fixture here is a shape lifted from a real machine: npx's node
/// holding the `.bin/dsh` shim, a Homebrew install, a scoped-package path,
/// and the processes that merely *talk about* dsh and must not count.
final class DSHProcessScanTests: XCTestCase {
    private let selfPID: pid_t = 999_999

    private func parse(_ output: String) -> [DSHProcessScan.Match] {
        DSHProcessScan.parse(output, excluding: selfPID)
    }

    // MARK: - Matching the real shapes

    func testMatchesTheCommandRunDirectly() {
        let matches = parse("  501 /opt/homebrew/bin/dsh --profile web --port 3128\n")
        XCTAssertEqual(matches, [
            DSHProcessScan.Match(pid: 501, command: "/opt/homebrew/bin/dsh --profile web --port 3128", port: 3128),
        ])
    }

    func testMatchesTheBareCommandName() {
        let matches = parse("  501 dsh web\n")
        XCTAssertEqual(matches.map(\.command), ["dsh web"])
        XCTAssertNil(matches[0].port)
    }

    func testMatchesANodeHoldingTheShim() {
        // What `npx @deepseek-ai/dsh` looks like while running: node with
        // the package's bin shim as its script.
        let line = "  502 node /Users/me/.npm/_npx/1e7f6d9597241db0/node_modules/.bin/dsh --profile web --port 0 --no-open"
        XCTAssertEqual(parse(line).count, 1)
    }

    func testMatchesAScopedPackagePathWithoutTheBinShim() {
        // A host runner that execs the JS entry directly still says
        // "@deepseek-ai/dsh" somewhere in its arguments.
        let line = "  503 node /Users/me/.npm/_npx/1e7f6d9597241db0/node_modules/@deepseek-ai/dsh/lib/bin.js --profile web"
        XCTAssertEqual(parse(line).count, 1)
    }

    func testMatchesNpmExec() {
        XCTAssertEqual(parse("  504 npm exec dsh -- web\n").count, 1)
    }

    // MARK: - The processes that must not count

    func testIgnoresProcessesThatMerelyMentionDSH() {
        let output = [
            "  600 grep --color=auto dsh",
            "  601 man dsh",
            "  602 less dsh.log",
            "  603 tail -f /var/log/dsh.log",
            "  604 vi /Users/me/notes/dsh.md",
        ].joined(separator: "\n")
        XCTAssertEqual(parse(output), [])
    }

    func testIgnoresThisAppAndItsOwnNames() {
        let output = [
            "  700 /Users/me/git/yadsh4mac/.build/debug/dsh-bezel",
            "  701 swift run dsh-bezel",
            "  702 open build/DSH Bezel.app",
            "  703 /bin/ps -axo pid=,command=",
        ].joined(separator: "\n")
        XCTAssertEqual(parse(output), [])
    }

    func testIgnoresTheAppsWithinLongerWords() {
        // "dsh" must appear as a whole path component, not a substring.
        let output = [
            "  710 node /Users/me/git/yadsh4mac/server.js",
            "  711 esbuild --bundle=/x/dshort.js",
        ].joined(separator: "\n")
        XCTAssertEqual(parse(output), [])
    }

    func testIgnoresAShellHoldingADSHCommandInOneArgument() {
        // The guide keeps a way to bind anyway; the scan stays conservative
        // rather than mis-reading every `sh -c`.
        XCTAssertEqual(parse("  720 /bin/zsh -l -i -c 'dsh web'\n"), [])
    }

    func testExcludesTheGivenSelfPID() {
        XCTAssertEqual(parse("  999999 /opt/homebrew/bin/dsh web\n"), [])
    }

    // MARK: - Ports

    func testParsesPortInBothSpellings() {
        XCTAssertEqual(parse("  1 /x/dsh --port 3081\n")[0].port, 3081)
        XCTAssertEqual(parse("  2 /x/dsh --port=3082\n")[0].port, 3082)
    }

    func testReportPrefersTheFirstExplicitPortOverZeroAndTheDefault() {
        let report = DSHProcessScan.Report(matches: [
            DSHProcessScan.Match(pid: 1, command: "/x/dsh --port 0", port: 0),
            DSHProcessScan.Match(pid: 2, command: "/y/dsh web", port: nil),
            DSHProcessScan.Match(pid: 3, command: "/z/dsh --port 4567", port: 4567),
        ])
        XCTAssertEqual(report.suggestedPort, 4567)
        XCTAssertEqual(report.suggestedBaseURL, "http://127.0.0.1:4567")
    }

    func testReportFallsBackToTheWebProfilesDefaultPort() {
        XCTAssertEqual(DSHProcessScan.Report(matches: []).suggestedPort, nil)
        XCTAssertEqual(
            DSHProcessScan.Report(matches: []).suggestedBaseURL,
            "http://127.0.0.1:\(DSHProcessScan.Report.defaultWebPort)"
        )
        // `--port 0` is the system choosing; only the child's own output
        // knows the answer, so the default is the better guess.
        let random = DSHProcessScan.Report(matches: [
            DSHProcessScan.Match(pid: 1, command: "/x/dsh --port 0", port: 0),
        ])
        XCTAssertEqual(random.suggestedPort, nil)
    }

    // MARK: - Line parsing

    func testIgnoresLinesWithoutACommand() {
        let output = "  800\n  801   \nnot-a-pid /x/dsh web\n"
        XCTAssertEqual(parse(output), [])
    }

    func testKeepsTheCommandsInternalSpacing() {
        let matches = parse("  501 /x/dsh  --profile   web\n")
        XCTAssertEqual(matches[0].command, "/x/dsh  --profile   web")
    }
}
