import Foundation

/// A `dsh` executable the runner could use, and where it came from.
///
/// The origin is kept so a failed launch can explain itself in the
/// connection-diagnostics pane: which bookmark field, which environment
/// variable, and which directories were consulted.
public struct DSHCandidate: Equatable, Sendable {
    public enum Origin: String, Equatable, Sendable {
        /// The bookmark's own `dshPath` field.
        case hostSetting
        /// The `BEZEL_DSH_PATH` environment variable.
        case environmentOverride
        /// Whatever `command -v dsh` answers in the user's login shell, and
        /// the directories that shell's own `PATH` contributes.
        case loginShell
        /// A `dsh` sitting on the application's own `PATH`.
        case appPath
        /// A conventional install directory, checked last.
        case wellKnown
    }

    public var executable: String
    public var origin: Origin

    public init(executable: String, origin: Origin) {
        self.executable = executable
        self.origin = origin
    }

    /// Source label for diagnostics, in the given language.
    public func label(in localization: Localization) -> String {
        switch origin {
        case .hostSetting: localization.text(.originHostSetting)
        case .environmentOverride: localization.text(.originEnvironmentOverride)
        case .loginShell: localization.text(.originLoginShell)
        case .appPath: localization.text(.originAppPath)
        case .wellKnown: localization.text(.originWellKnown)
        }
    }
}

/// What the user's login shell reports: the `dsh` it would run, and the `PATH`
/// it would run it with.
///
/// Both are needed, and getting only the first is the bug this type exists to
/// prevent. Almost every `dsh` on a real machine is a shim — `#!/usr/bin/env
/// node`, or a shell script calling `npm` — so *finding* the shim is worthless
/// unless the child also gets a `PATH` in which its interpreter resolves. This
/// app is a GUI bundle: launched from Finder it inherits launchd's minimal
/// `PATH`, which contains neither `node` nor `npm`.
public struct LoginShell: Equatable, Sendable {
    public var dshPath: String?
    /// The shell's own `PATH`, verbatim.
    public var path: String?

    public init(dshPath: String? = nil, path: String? = nil) {
        self.dshPath = dshPath
        self.path = path
    }

    /// Separates rc-file chatter from the two values we want. A `.zshrc` that
    /// prints on stdout must not be mistaken for the answer.
    static let sentinel = "<<<dsh-probe>>>"

    /// The script handed to the shell.
    static var script: String {
        "printf '\\n" + sentinel + "\\n%s\\n%s\\n' \"$(command -v dsh 2>/dev/null)\" \"$PATH\""
    }

    /// Read the probe's stdout. Pure, so the parsing is unit-testable.
    public static func parse(_ output: String) -> LoginShell? {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let marker = lines.lastIndex(of: sentinel), marker + 2 < lines.count else { return nil }
        let dsh = lines[marker + 1].trimmingCharacters(in: .whitespaces)
        let path = lines[marker + 2].trimmingCharacters(in: .whitespaces)
        return LoginShell(dshPath: dsh.isEmpty ? nil : dsh, path: path.isEmpty ? nil : path)
    }

    /// Ask the user's shell what it would do. Blocking: call it off the main
    /// thread.
    ///
    /// The shell is asked *interactively*, because the directories holding
    /// node and npm are usually exported from `~/.zshrc`, which a
    /// non-interactive `zsh -l -c` never sources. Asking non-interactively is
    /// precisely how a GUI app ends up with a `PATH` that looks nothing like
    /// the one the user's terminal has. If the interactive shell is unusable
    /// (a slow prompt framework, an rc file that blocks) the non-interactive
    /// form is tried, and the caller still merges in the conventional
    /// directories below.
    public static func probe(
        shell: String = "/bin/zsh",
        timeout: TimeInterval = 5
    ) -> LoginShell? {
        run(shell: shell, arguments: ["-l", "-i", "-c", script], timeout: timeout)
            ?? run(shell: shell, arguments: ["-l", "-c", script], timeout: timeout)
    }

    private static func run(shell: String, arguments: [String], timeout: TimeInterval) -> LoginShell? {
        guard let outcome = BoundedProcess.run(
            executable: shell,
            arguments: arguments,
            timeout: timeout
        ) else { return nil }
        // The status is deliberately ignored: an rc file that ends in failure
        // still prints the two values, and they are what we came for.
        return parse(outcome.output)
    }
}

/// How managed mode finds a `dsh` to run, and why a search failed.
public enum DSHDiscovery {
    /// One directory of the merged child `PATH`, remembered with where it
    /// came from so diagnostics label the `dsh` found in it honestly: a hit
    /// under `/opt/homebrew/bin` is a conventional install, not an "app PATH"
    /// match that merely got merged in.
    public struct PathDirectory: Equatable, Sendable {
        public var directory: String
        public var origin: DSHCandidate.Origin

        public init(directory: String, origin: DSHCandidate.Origin) {
            self.directory = directory
            self.origin = origin
        }
    }

    public struct Attempt: Equatable, Sendable {
        public enum Reason: Equatable, Sendable {
            case selected
            case notExecutable
            case didNotRun
            /// Never probed: the search's overall budget ran out first.
            case skipped
        }

        public var candidate: DSHCandidate
        public var reason: Reason

        public func text(in localization: Localization) -> String {
            switch reason {
            case .selected: localization.text(.attemptSelected)
            case .notExecutable: localization.text(.attemptNotExecutable)
            case .didNotRun: localization.text(.attemptDidNotRun)
            case .skipped: localization.text(.attemptSkipped)
            }
        }
    }

    public struct Report: Equatable, Sendable {
        /// The candidate that won, if any.
        public var chosen: DSHCandidate?
        /// The environment the managed child would be given, `PATH` already
        /// rewritten. It lives on the report rather than beside `chosen`
        /// because it exists even when the search failed — the diagnostics
        /// pane shows it then.
        public var environment: [String: String]
        public var attempts: [Attempt]

        public init(chosen: DSHCandidate?, environment: [String: String], attempts: [Attempt]) {
            self.chosen = chosen
            self.environment = environment
            self.attempts = attempts
        }

        /// Lines for the connection-diagnostics pane, oldest first.
        ///
        /// Rendered on demand, so switching the UI language re-renders a
        /// report that is already on screen instead of leaving it in whatever
        /// language it was produced in.
        public func diagnosticLines(_ localization: Localization) -> [String] {
            var lines: [String] = []
            if let chosen {
                lines.append(localization.text(
                    .diagnosticChosen,
                    chosen.executable,
                    chosen.label(in: localization)
                ))
            } else {
                lines.append(localization.text(.diagnosticNoneFound))
                if let path = environment["PATH"] {
                    lines.append(localization.text(.diagnosticChildPATH))
                    lines.append(contentsOf: path.split(separator: ":").map { "  " + $0 })
                }
            }
            lines.append(contentsOf: attempts.map { attempt in
                let mark = attempt.reason == .selected ? "✓" : "✗"
                let label = attempt.candidate.label(in: localization)
                return "\(mark) [\(label)] \(attempt.candidate.executable) — \(attempt.text(in: localization))"
            })
            return lines
        }
    }

    /// How long a candidate gets to answer `--version`.
    public static let probeTimeout: TimeInterval = 10

    /// Wall-clock budget for the whole search. A machine can hold a dozen
    /// existing-but-broken candidates, each eating its full probe timeout;
    /// without an overall budget the app would sit on "Looking for a usable
    /// dsh…" for minutes. What the budget does not reach is recorded as
    /// skipped instead.
    public static let locateBudget: TimeInterval = 30

    /// Directories merged into the child's `PATH` and probed as a last resort.
    ///
    /// `/opt/homebrew/bin` earns its place: on Apple silicon that is where
    /// Homebrew puts `node`, and a typical zsh setup does not export it.
    ///
    /// These are *interpreter* directories. Directories that merely hold
    /// another `dsh` are deliberately absent: a launcher that scans `PATH` for
    /// a "better" dsh — the DeepSeek Harness Desktop shim does exactly that —
    /// will otherwise hand the launch to whatever it finds, and a broken
    /// wrapper on `PATH` then takes the launch down with it. Measured on this
    /// machine: with `~/bin` injected, the Desktop shim deferred to
    /// `~/bin/dsh`, whose `npm exec` rewrote the arguments and stalled for
    /// minutes; without it, the shim ran its own bundled dsh and booted. Such
    /// directories are still *probed* as candidates, just not injected.
    public static func pathAdditions(home: String = NSHomeDirectory()) -> [String] {
        [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            home + "/.npm-global/bin",
            home + "/.bun/bin",
            "/opt/anaconda3/bin",
        ]
    }

    /// Directories that may themselves contain a `dsh`, checked as candidates
    /// after the ones taken from `PATH`.
    public static func wellKnownDirectories(home: String = NSHomeDirectory()) -> [String] {
        [home + "/.local/bin", home + "/bin"] + pathAdditions(home: home)
    }

    /// The managed child's `PATH`, merged and de-duplicated: the login
    /// shell's entries first (that is what the user's own terminal would
    /// use), then the entries this app inherited, then the interpreter
    /// directories. First occurrence wins, and each entry keeps the origin it
    /// arrived under.
    public static func childPath(
        base: [String: String] = ProcessInfo.processInfo.environment,
        loginShell: LoginShell? = nil,
        pathAdditions: [String] = pathAdditions()
    ) -> [PathDirectory] {
        var seen = Set<String>()
        var entries: [PathDirectory] = []
        func add(_ list: String?, origin: DSHCandidate.Origin) {
            for entry in (list ?? "").split(separator: ":") where !entry.isEmpty {
                if seen.insert(String(entry)).inserted {
                    entries.append(PathDirectory(directory: String(entry), origin: origin))
                }
            }
        }
        add(loginShell?.path, origin: .loginShell)
        add(base["PATH"], origin: .appPath)
        for directory in pathAdditions { add(directory, origin: .wellKnown) }
        return entries
    }

    /// Environment for the managed child: `base` with `PATH` rewritten to the
    /// merged one.
    public static func childEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment,
        loginShell: LoginShell? = nil,
        pathAdditions: [String] = pathAdditions()
    ) -> [String: String] {
        var environment = base
        environment["PATH"] = childPath(base: base, loginShell: loginShell, pathAdditions: pathAdditions)
            .map(\.directory)
            .joined(separator: ":")
        return environment
    }

    /// Ordered candidates for `host`, most specific first.
    ///
    /// `environment` supplies the `BEZEL_DSH_PATH` override; `path` is the
    /// merged child `PATH`, so the directories considered here are exactly
    /// the ones the child would search, each labelled with its own origin.
    public static func candidates(
        host: DSHHost,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        loginShell: LoginShell? = nil,
        path: [PathDirectory] = childPath(),
        wellKnown: [String] = wellKnownDirectories()
    ) -> [DSHCandidate] {
        var list: [DSHCandidate] = []
        func add(_ executable: String?, origin: DSHCandidate.Origin) {
            let trimmed = (executable ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !list.contains(where: { $0.executable == trimmed }) else { return }
            list.append(DSHCandidate(executable: trimmed, origin: origin))
        }
        add(host.dshPath, origin: .hostSetting)
        add(environment["BEZEL_DSH_PATH"], origin: .environmentOverride)
        add(loginShell?.dshPath, origin: .loginShell)
        for entry in path {
            add(entry.directory + "/dsh", origin: entry.origin)
        }
        for directory in wellKnown {
            add(directory + "/dsh", origin: .wellKnown)
        }
        return list
    }

    /// First executable named `name` along the merged child `PATH`.
    ///
    /// The same merged order the managed child itself gets — login shell
    /// first, then the app's inherited `PATH`, then the conventional
    /// directories — so "found here" and "runnable there" cannot disagree.
    /// The guide uses it to find `npm` for the automatic install.
    public static func findExecutable(
        named name: String,
        base: [String: String] = ProcessInfo.processInfo.environment,
        loginShell: LoginShell? = nil,
        pathAdditions: [String] = pathAdditions()
    ) -> String? {
        guard !name.isEmpty, !name.contains("/") else { return nil }
        for directory in childPath(base: base, loginShell: loginShell, pathAdditions: pathAdditions) {
            let candidate = directory.directory + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// Find the first candidate that exists *and* actually runs.
    ///
    /// `probe`, `wellKnown`, `pathAdditions` and `budget` are injectable so
    /// the ordering, the fall-through, the merged `PATH` and the cutoff can
    /// be tested without spawning processes or depending on what happens to
    /// be installed.
    public static func locate(
        host: DSHHost,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        loginShell: LoginShell? = nil,
        wellKnown: [String] = wellKnownDirectories(),
        pathAdditions: [String] = pathAdditions(),
        budget: TimeInterval = locateBudget,
        probe: (String, [String: String]) -> Bool = { canRun($0, environment: $1) }
    ) -> Report {
        let path = childPath(base: environment, loginShell: loginShell, pathAdditions: pathAdditions)
        var childEnvironment = environment
        childEnvironment["PATH"] = path.map(\.directory).joined(separator: ":")
        let candidates = candidates(
            host: host,
            environment: childEnvironment,
            loginShell: loginShell,
            path: path,
            wellKnown: wellKnown
        )

        var attempts: [Attempt] = []
        let deadline = Date().addingTimeInterval(budget)
        for candidate in candidates {
            guard FileManager.default.isExecutableFile(atPath: candidate.executable) else {
                attempts.append(Attempt(candidate: candidate, reason: .notExecutable))
                continue
            }
            guard Date() < deadline else {
                attempts.append(Attempt(candidate: candidate, reason: .skipped))
                continue
            }
            guard probe(candidate.executable, childEnvironment) else {
                attempts.append(Attempt(candidate: candidate, reason: .didNotRun))
                continue
            }
            attempts.append(Attempt(candidate: candidate, reason: .selected))
            return Report(chosen: candidate, environment: childEnvironment, attempts: attempts)
        }
        return Report(chosen: nil, environment: childEnvironment, attempts: attempts)
    }

    /// Whether `executable` runs, not merely whether it is a file with the
    /// execute bit set.
    ///
    /// The only honest test is to run it. `--version` prints and exits without
    /// touching `~/.dsh`, so it is safe to use as the probe. Its output is not
    /// captured but still drained, because a candidate whose `--version` prints
    /// more than the pipe holds must not be able to wedge the search.
    public static func canRun(
        _ executable: String,
        environment: [String: String],
        within timeout: TimeInterval = probeTimeout
    ) -> Bool {
        BoundedProcess.run(
            executable: executable,
            arguments: ["--version"],
            environment: environment,
            timeout: timeout
        )?.status == 0
    }
}
