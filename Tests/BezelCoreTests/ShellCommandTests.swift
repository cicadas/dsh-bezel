import XCTest
@testable import BezelCore

final class ShellCommandTests: XCTestCase {
    // MARK: - Word splitting

    func testSplitsAPlainInvocation() {
        XCTAssertEqual(
            ShellCommand.words("dsh --profile web --port 0 --no-open"),
            ["dsh", "--profile", "web", "--port", "0", "--no-open"]
        )
    }

    func testCollapsesRepeatedSeparators() {
        XCTAssertEqual(ShellCommand.words("  dsh   web\t--no-open\n"), ["dsh", "web", "--no-open"])
    }

    func testHonoursSingleQuotesAroundSpaces() {
        XCTAssertEqual(
            ShellCommand.words("\"/opt/my dsh/dsh\" web --patch './a b.yml'"),
            ["/opt/my dsh/dsh", "web", "--patch", "./a b.yml"]
        )
    }

    func testEscapedQuoteInsideDoubleQuotes() {
        XCTAssertEqual(ShellCommand.words("say \"a \\\"b\\\" c\""), ["say", "a \"b\" c"])
    }

    /// `\\` inside double quotes is one backslash, as in every shell; every
    /// other backslash there is literal, so a Windows-style path survives.
    func testBackslashEscapesItselfInsideDoubleQuotes() {
        XCTAssertEqual(ShellCommand.words(#""a\\b""#), ["a\\b"])
        XCTAssertEqual(ShellCommand.words(#""C:\dir\x""#), [#"C:\dir\x"#])
    }

    func testBackslashMakesTheNextCharacterLiteral() {
        XCTAssertEqual(ShellCommand.words("dsh --patch a\\ b.yml"), ["dsh", "--patch", "a b.yml"])
    }

    func testAnEmptyLineIsNotAWordList() {
        XCTAssertNil(ShellCommand.words(""))
        XCTAssertNil(ShellCommand.words("   "))
        XCTAssertNil(ShellCommand.words("\n\n"))
    }

    // MARK: - The syntax that needs a real shell

    func testShellSyntaxIsRejectedRatherThanMisread() {
        for command in [
            "cd ~/x && dsh web",
            "dsh web | tee log",
            "dsh web; echo done",
            "dsh web &",
            "DSH_HOME=/x dsh web",
            "dsh web > log 2>&1",
            "dsh web # comment",
            "dsh --patch ~/p.yml",
            "dsh --patch ./*.yml",
            "echo $HOME && dsh web",
            "dsh --patch ./{a,b}.yml",
        ] {
            XCTAssertNil(ShellCommand.words(command), "should need a shell: \(command)")
        }
    }

    /// A line break separates commands, so a line list is a shell program —
    /// never one flattened argv. Treating `\n` as plain whitespace turned
    /// "cd /x" + "dsh web" into `cd /x dsh web`, which then failed to launch
    /// instead of falling back to the shell; CRLF text was rejected correctly
    /// while the same text with LF endings was not.
    func testAMultiLineCommandNeedsAShellRatherThanBeingFlattened() {
        XCTAssertNil(ShellCommand.words("cd /tmp/x\ndsh web"))
        XCTAssertNil(ShellCommand.words("dsh web\r\nrm -rf /tmp/x"))
        XCTAssertNil(ShellCommand.words("dsh web\nrm -rf /tmp/x"))
    }

    /// Whitespace *around* the command is not syntax, so a command that
    /// merely arrived with a trailing newline is still a plain word list.
    func testSurroundingWhitespaceIsTrimmedRatherThanRejected() {
        XCTAssertEqual(ShellCommand.words("  dsh web --no-open \n"), ["dsh", "web", "--no-open"])
        XCTAssertEqual(ShellCommand.words("\ndsh web\n"), ["dsh", "web"])
    }

    func testAnUnterminatedQuoteIsRejected() {
        XCTAssertNil(ShellCommand.words("dsh 'web"))
        XCTAssertNil(ShellCommand.words("dsh \"web"))
        XCTAssertNil(ShellCommand.words("dsh web\\"))
    }

    // MARK: - The forwarding wrapper

    func testTheWrapperBackgroundsTrapsWaitsAndExits() {
        let wrapper = ShellCommand.forwardingWrapper("dsh --profile web --port 0 --no-open")
        XCTAssertTrue(wrapper.hasPrefix("dsh --profile web --port 0 --no-open &\n"))
        XCTAssertTrue(wrapper.contains("_bezel_child=$!"))
        XCTAssertTrue(wrapper.hasSuffix("wait \"${_bezel_child}\"\nexit $?"))
    }

    /// The trap has to signal the whole job, not `$!`.
    ///
    /// In a pipeline `$!` is the last element, so the old trap killed the
    /// `tee` in `dsh web 2>&1 | tee log` and left the dsh running — the exact
    /// command this wrapper's own documentation gives as its reason to exist.
    /// `$!` stays as the fallback for a shell without job control.
    func testTheTrapSignalsTheWholeJobNotJustTheLastPipelineElement() {
        let wrapper = ShellCommand.forwardingWrapper("dsh web 2>&1 | tee log")
        XCTAssertTrue(wrapper.contains("kill -TERM %%"), wrapper)
        XCTAssertTrue(wrapper.contains("|| kill -TERM \"${_bezel_child}\""), wrapper)
        XCTAssertTrue(wrapper.contains("TERM INT HUP EXIT"), wrapper)
    }

    /// A trailing `&` is the user backgrounding the command themselves; the
    /// wrapper background is the one that matters, so theirs is dropped.
    func testTheWrapperDropsATrailingAmpersand() {
        let wrapper = ShellCommand.forwardingWrapper("dsh web &")
        XCTAssertTrue(wrapper.hasPrefix("dsh web &\n"))
        XCTAssertFalse(wrapper.contains("dsh web &&"))
    }

    func testTheWrapperLeavesTheCommandVerbatim() {
        // The wrapper is handed to the shell as one argument, so quoting the
        // user's text is neither needed nor done — a quote in the command
        // must survive untouched.
        let command = "dsh web --trusted-host 'host name'"
        let wrapper = ShellCommand.forwardingWrapper(command)
        XCTAssertTrue(wrapper.contains(command))
    }
}
