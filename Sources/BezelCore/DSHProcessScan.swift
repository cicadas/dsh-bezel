import Foundation

/// Finds `dsh` processes running on this machine, for the first-launch guide.
///
/// The honest way to answer "is a DSH background process running?" on macOS is
/// to read the process table: `/bin/ps -axo pid=,command=` lists every process
/// with its full command line, and a dsh shows up there no matter how it was
/// started — terminal, npx, a Desktop runtime, this app's own managed mode.
///
/// The judgment of what counts is deliberately conservative and visible: a
/// process counts when the command *runs* dsh — dsh itself as the command, or
/// a known interpreter/runner (node, npm, npx…) with a dsh in its arguments.
/// `grep dsh` or `man dsh` therefore do not count, while `/x/.bin/dsh`,
/// `@deepseek-ai/dsh` and `node /x/@deepseek-ai/dsh/lib/bin.js` do. Whatever
/// matched is shown to the user, so the judgment is never a black box, and the
/// guide always keeps an escape hatch for a process the rule missed.
public enum DSHProcessScan {
    /// One process that looks like a running dsh.
    public struct Match: Equatable, Sendable, Identifiable {
        public var pid: pid_t
        /// The process's full command line, as `ps` printed it.
        public var command: String
        /// The port parsed from a `--port <n>` (or `--port=<n>`) argument, if
        /// the command line carries one. `nil` means the default port is in
        /// use; `0` means the system chose one, and only the process's own
        /// startup output knows which.
        public var port: Int?

        public init(pid: pid_t, command: String, port: Int?) {
            self.pid = pid
            self.command = command
            self.port = port
        }

        public var id: pid_t { pid }
    }

    /// What a scan found.
    public struct Report: Equatable, Sendable {
        /// The port `dsh web` serves on when its command line says nothing:
        /// the web profile's own default.
        public static let defaultWebPort = 3080

        public var matches: [Match]

        public init(matches: [Match]) {
            self.matches = matches
        }

        public var isRunning: Bool { !matches.isEmpty }

        /// The best guess at where the found process is serving: the first
        /// explicit `--port` above zero, else the web profile's default.
        public var suggestedPort: Int? {
            for match in matches {
                if let port = match.port, port > 0 { return port }
            }
            return nil
        }

        /// That guess as an origin to pre-fill the bind form with. The user
        /// pastes the real address from the process's startup output anyway;
        /// this only has to be right often enough to save them the typing.
        public var suggestedBaseURL: String {
            "http://127.0.0.1:\(suggestedPort ?? Self.defaultWebPort)"
        }
    }

    /// Interpreters and runners that may legitimately carry a dsh in their
    /// arguments. Everything else — grep, man, less, an editor — mentioning
    /// "dsh" is talking *about* dsh, not running it.
    static let runners: Set<String> = [
        "node", "npm", "npx", "pnpm", "yarn", "bun", "bunx", "deno", "tsx",
        "env", "electron",
    ]

    /// How long `ps` gets to answer. It is normally instant.
    public static let scanTimeout: TimeInterval = 5

    /// Read a `ps -axo pid=,command=` listing and pick out the dsh processes.
    ///
    /// Pure, so the matching rule is unit-testable against real-world shapes
    /// without spawning anything. `selfPID` (and the app's own binary names)
    /// keep the scan from ever reporting this app as the running dsh.
    public static func parse(
        _ output: String,
        excluding selfPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> [Match] {
        var matches: [Match] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let text = String(line).trimmingCharacters(in: .whitespaces)
            // "<pid> <command…>": the pid is the leading run of digits.
            guard let space = text.firstIndex(where: { $0 == " " || $0 == "\t" }),
                  let pid = pid_t(text[text.startIndex..<space])
            else { continue }
            let command = String(text[text.index(after: space)...]).trimmingCharacters(in: .whitespaces)
            guard !command.isEmpty, pid != selfPID else { continue }
            guard looksLikeDSH(command) else { continue }
            matches.append(Match(pid: pid, command: command, port: port(in: command)))
        }
        return matches
    }

    /// Run the process listing and report what it held. Blocking — spawn it
    /// off the main thread.
    public static func scan() -> Report {
        Report(matches: parse(runPS()))
    }

    /// Whether this command line runs dsh.
    ///
    /// A word "is dsh" when one of its `/`-separated components is exactly
    /// `dsh`: that covers `dsh`, `/opt/homebrew/bin/dsh`, `@deepseek-ai/dsh`
    /// and `/x/@deepseek-ai/dsh/lib/bin.js`, while leaving `dsh-bezel`,
    /// `yadsh4mac` and `dsh.log` alone. The first word must then be dsh
    /// itself, or one of the runners carrying a dsh later in the line —
    /// which is what keeps `grep dsh` out.
    static func looksLikeDSH(_ command: String) -> Bool {
        let words = command.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let first = words.first else { return false }
        if isDSHWord(first) { return true }
        guard runners.contains(Self.basename(first)) else { return false }
        return words.dropFirst().contains(where: isDSHWord)
    }

    /// Whether one whitespace-separated word names dsh.
    static func isDSHWord(_ word: String) -> Bool {
        word.split(separator: "/", omittingEmptySubsequences: false).contains("dsh")
    }

    /// The last `/`-component of a word, which is what a shell would look up.
    static func basename(_ word: String) -> String {
        word.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? word
    }

    /// `--port 3080` / `--port=3080` out of a command line.
    static func port(in command: String) -> Int? {
        let words = command.split(whereSeparator: { $0 == " " || $0 == "\t" })
        var previous = ""
        for word in words {
            if previous == "--port", let value = Int(word) { return value }
            if word.hasPrefix("--port="), let value = Int(word.dropFirst("--port=".count)) {
                return value
            }
            previous = String(word)
        }
        return nil
    }

    /// `ps -axo pid=,command=`, drained concurrently and bounded by a
    /// deadline. A full process table is comfortably larger than a pipe
    /// buffer, so the draining is load-bearing rather than defensive.
    private static func runPS() -> String {
        BoundedProcess.run(
            executable: "/bin/ps",
            arguments: ["-axo", "pid=,command="],
            timeout: scanTimeout
        )?.output ?? ""
    }
}
