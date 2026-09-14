import Foundation
import Observation

/// Owns the optional local `dsh --profile web` child process.
///
/// Finding the executable and starting it are deliberately separate steps:
/// the search asks the user's login shell what it would run, probes every
/// candidate with `--version`, and only then hands the process a `PATH` its
/// shim can actually use. The child announces its Web UI URL on stdout; this
/// runner parses that line and hands the URL back, so the app attaches without
/// knowing which port `--port 0` picked.
@MainActor
@Observable
public final class LocalHostRunner {
    public enum Phase: Equatable, Sendable {
        case idle
        /// Searching for a runnable `dsh`.
        case locating
        case starting
        case running(URL)
        case failed(Failure)
    }

    /// Why a managed launch never got as far as announcing a URL.
    ///
    /// Structured rather than pre-rendered, so the message follows the UI
    /// language even when the failure is already on screen.
    public enum Failure: Equatable, Sendable {
        case noRunnableExecutable(attempts: Int)
        case launchFailed(reason: String)
        case exited(status: Int32)
        case exitedBeforeStart(status: Int32)
        case timedOut(seconds: Int)
    }

    /// What the connect prompt's primary button does for a Host.
    ///
    /// A Host nobody manages is only ever attached to; a managed one is
    /// *launched*, and the button says which launch is coming — a fresh one,
    /// or the replacement of a child that is already alive.
    public enum ConnectAction: Equatable, Sendable {
        case connect
        case startManaged
        case restartManaged
    }

    /// How long `dsh` gets to print its startup line. It normally takes a
    /// second or two; without a deadline the app would sit on "Starting local
    /// dsh…" for ever whenever the child hangs.
    public static let startupTimeout: TimeInterval = 30

    /// A child that prints without ever emitting a newline must not grow the
    /// line buffer without bound. The startup line is short, so anything past
    /// this is garbage, and only the tail is kept — that is where the line
    /// would be.
    private static let lineBufferLimit = 65_536

    public private(set) var phase: Phase = .idle
    /// Raw output from the child process, oldest first, for the connection
    /// diagnostics pane. Only what the child actually printed: the app's own
    /// notes come from `discovery` and `phase`, rendered at display time, so
    /// they are never left behind in the wrong language.
    public private(set) var recentOutput: [String] = []
    /// How the last search went, kept for the diagnostics pane.
    public private(set) var discovery: DSHDiscovery.Report?
    /// Host whose child process this runner owns.
    public private(set) var hostID: UUID?

    private var process: Process?
    private var buffer = ""
    /// Invalidates in-flight discovery and timeouts when a new start or a stop
    /// supersedes them.
    private var generation = 0

    /// How one managed launch will be executed. Kept as a value so the
    /// choice — which is really about termination semantics — is testable
    /// without spawning anything.
    public enum LaunchPlan: Equatable, Sendable {
        /// The command exec'd directly, so the process this app holds is the
        /// dsh itself and `terminate()` reaches it.
        case direct(executable: String, arguments: [String])
        /// The command needs a shell, so it runs through the login shell in
        /// `ShellCommand.forwardingWrapper`'s signal-forwarding embrace.
        case shell(script: String)
    }

    /// Derive how a custom launch command would be run.
    ///
    /// A command that parses into plain words runs directly — the first word
    /// itself when it is a path, else the first same-named executable along
    /// the merged child `PATH` — and anything that needs real shell syntax
    /// falls back to the wrapper. `nil` only for a command that is blank
    /// after trimming.
    public nonisolated static func manualLaunch(
        command: String,
        loginShell: LoginShell? = nil,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> LaunchPlan? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let words = ShellCommand.words(trimmed) {
            let executable = words[0]
            let arguments = Array(words.dropFirst())
            if executable.contains("/") {
                return .direct(executable: executable, arguments: arguments)
            }
            if let resolved = DSHDiscovery.findExecutable(named: executable, base: base, loginShell: loginShell) {
                return .direct(executable: resolved, arguments: arguments)
            }
        }
        return .shell(script: ShellCommand.forwardingWrapper(trimmed))
    }

    /// The invocation the app composes itself when a Host has no custom
    /// command: port `0` lets the system choose, and the URL comes from the
    /// child's own startup line.
    public nonisolated static func standardArguments(for host: DSHHost) -> [String] {
        let profile = host.profile.trimmingCharacters(in: .whitespacesAndNewlines)
        return ["--profile", profile.isEmpty ? "web" : profile, "--port", "0", "--no-open"]
            + host.argumentList
    }

    /// What pressing the prompt's primary button would do to `host` right now.
    public func connectAction(for host: DSHHost) -> ConnectAction {
        Self.connectAction(for: host, runnerHostID: hostID, phase: phase)
    }

    /// The pure core of `connectAction(for:)`: the button offers a restart
    /// only while a child *of this Host* is alive, and the distinction is
    /// testable without spawning anything.
    ///
    /// A search in flight owns no child yet, so it reads as a start too —
    /// pressing the button then supersedes the search, which `start` already
    /// handles by stopping whatever it holds.
    public nonisolated static func connectAction(
        for host: DSHHost,
        runnerHostID: UUID?,
        phase: Phase
    ) -> ConnectAction {
        guard host.managed else { return .connect }
        switch phase {
        // A child of this Host is alive: the launch terminates and replaces it.
        case .starting, .running:
            return runnerHostID == host.id ? .restartManaged : .startManaged
        // Nothing alive to replace — a fresh launch, after a failure same as
        // from idle.
        case .idle, .locating, .failed:
            return .startManaged
        }
    }

    public init() {}

    /// Find a usable `dsh` for `host`, start it, and report the URL it prints.
    ///
    /// Returns immediately. The search spawns shells and probe processes, so
    /// it runs off the main thread and reports through `phase`.
    ///
    /// A Host with a custom `launchCommand` skips the search: the command is
    /// the user's own answer to "which dsh", and it runs exactly as typed
    /// (`manualLaunch` decides how).
    public func start(host: DSHHost, onURL: @escaping (URL) -> Void) {
        stop()
        let token = generation
        hostID = host.id
        buffer = ""
        recentOutput = []
        discovery = nil
        phase = .locating
        let environment = ProcessInfo.processInfo.environment
        let command = host.launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)

        Task { [weak self] in
            if command.isEmpty {
                let report = await Task.detached(priority: .userInitiated) {
                    DSHDiscovery.locate(
                        host: host,
                        environment: environment,
                        loginShell: LoginShell.probe()
                    )
                }.value
                guard let self, self.generation == token, self.hostID == host.id else { return }
                self.discovery = report
                guard let chosen = report.chosen else {
                    self.fail(.noRunnableExecutable(attempts: report.attempts.count))
                    return
                }
                self.launch(
                    .direct(executable: chosen.executable, arguments: Self.standardArguments(for: host)),
                    environment: report.environment,
                    token: token,
                    onURL: onURL
                )
            } else {
                let loginShell = await Task.detached(priority: .userInitiated) {
                    LoginShell.probe()
                }.value
                guard let self, self.generation == token, self.hostID == host.id else { return }
                // The command runs with the merged `PATH` either way: a
                // direct word list needs `dsh`'s interpreter resolvable, and
                // the shell's own `-l` only rewrites what it knows about.
                let childEnvironment = DSHDiscovery.childEnvironment(
                    base: environment,
                    loginShell: loginShell
                )
                guard let plan = Self.manualLaunch(command: command, loginShell: loginShell, base: environment) else {
                    self.fail(.launchFailed(reason: "empty launch command"))
                    return
                }
                self.launch(plan, environment: childEnvironment, token: token, onURL: onURL)
            }
        }
    }

    /// Terminate the owned child, if any, and abandon any search in flight.
    public func stop() {
        generation &+= 1
        guard let process else {
            hostID = nil
            if phase != .idle { phase = .idle }
            return
        }
        self.process = nil
        process.terminationHandler = nil
        if let pipe = process.standardOutput as? Pipe { detachPipe(pipe) }
        if process.isRunning { process.terminate() }
        hostID = nil
        phase = .idle
    }

    /// Every failed end-state funnels through here, so that none of them
    /// leaves a stale `hostID` behind: the URL callback's guard reads it, and
    /// a Host that never announced a URL must not look attached.
    private func fail(_ failure: Failure) {
        hostID = nil
        phase = .failed(failure)
    }

    /// One launch, however it was composed: the standard invocation after a
    /// discovery, or a Host's custom command.
    private func launch(
        _ plan: LaunchPlan,
        environment: [String: String],
        token: Int,
        onURL: @escaping (URL) -> Void
    ) {
        let process = Process()
        switch plan {
        case .direct(let executable, let arguments):
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
        case .shell(let script):
            // The wrapper, not the raw command: a bare `zsh -l -c` would die
            // alone under SIGTERM and leave the dsh it started orphaned.
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", script]
        }
        // The child has to inherit the PATH that made the candidate runnable:
        // `dsh` is usually a shim whose interpreter (node, npm) lives on it,
        // and a Finder-launched app's own PATH contains neither.
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.terminationHandler = { finished in
            let status = finished.terminationStatus
            Task { @MainActor [weak self] in
                guard let self, self.process === finished, self.generation == token else { return }
                self.process = nil
                self.detachPipe(pipe)
                if case .running = self.phase {
                    self.fail(.exited(status: status))
                } else if case .starting = self.phase {
                    self.fail(.exitedBeforeStart(status: status))
                }
            }
        }
        self.process = process
        buffer = ""
        phase = .starting
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor [weak self] in self?.ingest(text, token: token, onURL: onURL) }
        }
        do {
            try process.run()
        } catch {
            self.process = nil
            detachPipe(pipe)
            fail(.launchFailed(reason: error.localizedDescription))
            return
        }
        scheduleStartupTimeout(token: token)
    }

    private func scheduleStartupTimeout(token: Int) {
        let seconds = Self.startupTimeout
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, self.generation == token else { return }
            guard case .starting = self.phase else { return }
            self.stop()
            self.fail(.timedOut(seconds: Int(seconds)))
        }
    }

    private func detachPipe(_ pipe: Pipe) {
        pipe.fileHandleForReading.readabilityHandler = nil
    }

    private func ingest(_ text: String, token: Int, onURL: @escaping (URL) -> Void) {
        guard generation == token else { return }
        recentOutput.append(contentsOf: text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init))
        if recentOutput.count > 200 { recentOutput.removeFirst(recentOutput.count - 200) }
        buffer += text
        if buffer.count > Self.lineBufferLimit { buffer.removeFirst(buffer.count - Self.lineBufferLimit) }
        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
            if let url = Self.announcedURL(in: line) {
                phase = .running(url)
                onURL(url)
            }
        }
    }

    /// Parse the URL out of the `dsh web: <url> (LAN: <url>)` startup line.
    public nonisolated static func announcedURL(in line: String) -> URL? {
        guard let marker = line.range(of: "dsh web:") else { return nil }
        let rest = line[marker.upperBound...]
        guard let token = rest.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "(" }).first
        else { return nil }
        let text = String(token).trimmingCharacters(in: .whitespaces)
        guard text.hasPrefix("http://") || text.hasPrefix("https://") else { return nil }
        return URL(string: text)
    }
}
